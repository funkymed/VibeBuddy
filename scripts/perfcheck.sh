#!/usr/bin/env bash
#
# perfcheck.sh — the performance gate every RFC has to pass.
#
#   ./scripts/perfcheck.sh <scenario> <seconds> [rfc]
#
# Scenarios (RFC-001 §8):
#   A  rest        no Claude session, pill collapsed, machine on battery
#   B  activity    three live `claude` sessions in three projects
#   C  interaction panel open, cursor moving continuously
#   D  waiting     a permission panel open, waiting for a person who never answers
#
# Writes docs/perf/<date>-<rfc>-<scenario>.csv and prints a verdict against the
# budget. A regression of more than 10 % on any metric blocks closing the RFC.
#
# The governing metric is idle wakeups, not CPU percent: a process at 0.4 % CPU
# waking 70 times a second drains a battery and trips no percentage threshold.
# Those come from inside the process (mach task_power_info) — no sudo, and no
# subprocess that would perturb what it measures.

set -euo pipefail
cd "$(dirname "$0")/.."

SCENARIO="${1:-A}"
SECONDS_TOTAL="${2:-600}"
RFC="${3:-001}"
# Defaults to the development build; a release check points it at the bundle:
#   VIBEBUDDY_BIN=dist/VibeBuddy.app/Contents/MacOS/VibeBuddy ./scripts/perfcheck.sh A 600 011
# Measuring the bundle matters: it is signed, and the shipped app is the one
# whose cost the budget is about.
BIN="${VIBEBUDDY_BIN:-.build/release/VibeBuddy}"
OUT="docs/perf/$(date +%Y%m%d-%H%M)-${RFC}-${SCENARIO}.csv"

# Budget. Gated on phys_footprint, not RSS: RSS counts framework pages shared
# with every other process on the machine. See docs/perf/2026-08-19-D5-*.md.
BUDGET_RSS_MB="${BUDGET_RSS_MB:-40}"
BUDGET_CPU_REST=0.5
BUDGET_CPU_BUSY=3.0
BUDGET_IDLE_WAKES_REST=2.0
BUDGET_IDLE_WAKES_BUSY=30.0

# Each scenario needs the bench mode that actually exercises it. The script
# used to run `--bench panel` for all three, so B and C measured an empty panel
# and reported 0.000 % CPU while three sessions were live — a budget that always
# passes measures nothing.
case "$SCENARIO" in
  A) BUDGET_CPU=$BUDGET_CPU_REST;  BUDGET_WAKES=$BUDGET_IDLE_WAKES_REST; MODE=pill ;;
  B) BUDGET_CPU=$BUDGET_CPU_BUSY; BUDGET_WAKES=$BUDGET_IDLE_WAKES_BUSY; MODE=app ;;
  C) BUDGET_CPU=$BUDGET_CPU_BUSY; BUDGET_WAKES=$BUDGET_IDLE_WAKES_BUSY; MODE=interaction ;;
  # A panel holding a request is idle by construction: nobody is moving a cursor
  # over it, and the thing it waits for is a person. It answers to the rest
  # budget, not to the interaction one.
  D) BUDGET_CPU=$BUDGET_CPU_REST; BUDGET_WAKES=$BUDGET_IDLE_WAKES_REST; MODE=waiting ;;
  *) echo "unknown scenario: $SCENARIO (expected A, B, C or D)" >&2; exit 2 ;;
esac

[ -x "$BIN" ] || {
  echo "missing $BIN — run ./scripts/build.sh, or swift build -c release" >&2
  exit 1
}
mkdir -p docs/perf

echo "▶ scenario $SCENARIO · mode $MODE · ${SECONDS_TOTAL}s · RFC-$RFC"

# --bench self-reports from inside the process and exits on its own.
"$BIN" --bench "$MODE" "$SECONDS_TOTAL" "$SCENARIO" > "$OUT" 2> "${OUT%.csv}.log" &
BENCH_PID=$!

# One external sample() to prove no subprocess is spawned at rest. `sample`
# needs no privileges for a process we own.
if [ "$SCENARIO" = "A" ] && [ "$SECONDS_TOTAL" -ge 40 ]; then
  sleep 10
  APP_PID="$(pgrep -P $BENCH_PID -x VibeBuddy 2>/dev/null || echo $BENCH_PID)"
  sample "$APP_PID" 20 -f "${OUT%.csv}.sample.txt" >/dev/null 2>&1 || true
fi

wait $BENCH_PID || true

[ -s "$OUT" ] || { echo "no samples written" >&2; exit 1; }

# ── verdict ─────────────────────────────────────────────────────────────────
awk -F, -v rss_budget="$BUDGET_RSS_MB" -v cpu_budget="$BUDGET_CPU" \
        -v wake_budget="$BUDGET_WAKES" -v scenario="$SCENARIO" '
  NR == 1 { next }
  {
    n++
    # `+0` on both sides, every time. Without it awk compares these as text,
    # and "104.99" <= "40" is true letter by letter — which is how this script
    # printed PASS on a footprint two and a half times over budget.
    if ($3+0 > rss)  rss  = $3+0
    if ($4+0 > foot) foot = $4+0
    if (n == 1) { t0 = $2; cpu0 = $5; w0 = $7 }
    t1 = $2; cpu1 = $5; w1 = $7
  }
  END {
    if (n < 2) { print "not enough samples"; exit 1 }
    # `+0` is load-bearing: awk receives the budgets as strings, and a
    # string comparison made every three-digit value pass against "40"
    # ("104.94" <= "40" is true letter by letter). Every verdict this script
    # printed before 2026-08-20 was worth nothing.
    rss_budget += 0; cpu_budget += 0; wake_budget += 0
    foot += 0; rss += 0
    win = t1 - t0
    cpu = (cpu1 - cpu0) / win * 100
    # 0.2/s is the sampler itself, which belongs to the harness not the app.
    wake = (w1 - w0) / win - 0.2
    if (wake < 0) wake = 0

    printf "\n── verdict (scenario %s, %d samples over %.0fs) ──\n", scenario, n, win
    printf "  %-22s %8.1f MB   budget %s MB    %s\n", "footprint peak", foot, rss_budget, (foot <= rss_budget ? "PASS" : "FAIL")
    printf "  %-22s %8.1f MB   (indicatif — pages de frameworks partagées)\n", "RSS peak", rss
    printf "  %-22s %8.3f %%    budget %s %%     %s\n", "CPU steady",   cpu,  cpu_budget, (cpu  <= cpu_budget  ? "PASS" : "FAIL")
    printf "  %-22s %8.3f /s   budget %s /s    %s\n", "idle wakeups",   wake, wake_budget,(wake <= wake_budget ? "PASS" : "FAIL")
    printf "\n"
    if (foot > rss_budget || cpu > cpu_budget || wake > wake_budget) exit 1
  }
' "$OUT" || VERDICT=1

if [ -f "${OUT%.csv}.sample.txt" ]; then
  # grep exits 1 on zero matches, so `|| echo 0` would emit a second line.
  SPAWNS=$(grep -c 'posix_spawn' "${OUT%.csv}.sample.txt" 2>/dev/null) || SPAWNS=0
  printf "  %-22s %8s      budget 0        %s\n\n" "fork/exec at rest" "$SPAWNS" \
    "$([ "$SPAWNS" -eq 0 ] && echo PASS || echo FAIL)"
  [ "$SPAWNS" -eq 0 ] || VERDICT=1
fi

echo "  → $OUT"
exit "${VERDICT:-0}"
