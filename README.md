<p align="center">
  <img src="./docs/icon.png" alt="VibeBuddy" width="192" />
</p>

# VibeBuddy

A native macOS app that turns the MacBook notch into a dashboard for your coding
agents. Swift, SwiftPM, macOS 14 or later, no external dependencies: the standard
library and Apple frameworks, nothing else.

## What it does

In order of importance. A feature that serves none of these is comfort, and gets
judged as such.

1. Alert you without you looking: when the agent has finished, and when it is
   waiting for an answer. Both are read from the transcript, without a hook.
2. Show real usage, meaning the 5 h and 7 d limit percentages as Anthropic
   reports them, not an estimate derived from token counts.
3. Track several sessions at once, each with its own state, grouped by project.
   Clicking a live row brings its terminal tab back.
4. Do it playfully: an animated *buddy* carries the state in the notch. It
   follows your pointer, chases it when you shake the mouse, and laughs when
   you poke it.
5. Answer permission prompts from the notch: when Claude Code asks to run a
   command, edit a file or fetch a URL, the panel shows what is being asked and
   the decision goes back without touching the terminal.

## Install

```sh
brew install --cask funkymed/vibebuddy/vibebuddy
xattr -dr com.apple.quarantine /Applications/VibeBuddy.app
```

**The second line is not optional.** Homebrew *adds* the quarantine attribute —
`xattr -l` on the installed app shows "Homebrew Cask" as its writer — and macOS
then refuses the first launch, offering to move the app to the Trash. The app
is signed with a stable self-signed identity but is **not notarised**, and
notarisation needs an Apple Developer membership at 99 €/year.

`--no-quarantine` used to do this at install time; the option was removed in
Homebrew 6.

The tap is
[`funkymed/homebrew-vibebuddy`](https://github.com/funkymed/homebrew-vibebuddy);
releases are at [`funkymed/VibeBuddy`](https://github.com/funkymed/VibeBuddy/releases).

To remove it, including the buddies, the preferences and the socket:

```sh
brew uninstall --zap --cask vibebuddy
```

## Build it yourself

Everything goes through the `Makefile`; `make` on its own lists it.

```sh
make app                      # dist/VibeBuddy.app, universal, signed
make dmg                      # dist/VibeBuddy-<version>.dmg
make run                      # debug build, straight from source
make stop                     # kill every instance and unlink the socket
make test                     # 449 tests, 75 suites
make publish version=0.1.0    # sign, package, tag, release
```

Two instances fight over the same socket — the second unlinks it and binds its
own, so the first listens on a dead inode while still drawing its pill. `make
stop` before starting another.

Or run it straight from the checkout, without packaging:

```sh
swift build -c release
.build/release/VibeBuddy      # runs until Ctrl-C or the power button
```

Signing needs a one-time identity, created in your login keychain and never
stored in the repository:

```sh
./scripts/make-identity.sh
```

### Why macOS refuses the first launch

VibeBuddy is signed with a self-signed certificate, not a notarised one.
Notarisation needs an Apple Developer membership at 99 €/year, and this project
does not have one. So Gatekeeper says no:

```
$ spctl -a -t exec -vv /Applications/VibeBuddy.app
/Applications/VibeBuddy.app: rejected
origin=VibeBuddy Self-Signed
```

**Homebrew does not help here — it makes it worse.** Installing a cask *adds*
the quarantine attribute; `xattr -l` on the installed app names "Homebrew Cask"
as its writer. The `--no-quarantine` option that used to prevent it was removed
in Homebrew 6. Hence the second line of the install:

```sh
xattr -dr com.apple.quarantine /Applications/VibeBuddy.app
```

For a DMG downloaded by hand, **right-click → Open** once works too: macOS
remembers, and every later launch is normal.

That `xattr` command disables a protection macOS applied on purpose. It is
written here rather than run silently from a cask postflight, because turning
off someone's protection is their decision to make, not a package's.

What the signature *does* buy, and it is not nothing, is a **stable identity**:
the permissions you grant — automation of your terminal, opening at login —
survive updates. An ad-hoc signature changes identity on every build and
revokes them every time, which is why `scripts/build.sh` refuses to fall back
to one.

## Diagnostics and measurement

`--info` is the first thing to reach for: screens, geometry, computed frames,
wake and animation budgets, installed buddies with their frame rate, language,
the parser run against real transcripts, live sessions with their tty, usage,
memory cost.

```sh
make info                                         # the whole diagnostic
make simulate kind=diff                           # a fake permission panel, no Claude needed
#   kinds: shell · diff · write · read · url · question · other
make perf                                         # scenario A, 10 min, the gate every RFC passes
make perf-busy  /  make perf-panel                # scenarios B and C

.build/release/VibeBuddy --hover                  # hover regions against the pixels actually painted
.build/release/VibeBuddy --bench <mode> <seconds>
#   modes: shell · panel · pill · hidden · interaction · sessions · app
```

Run `make perf` in the **foreground**. Launched detached the process gets reaped
and the run stops early — 149 s, 40 s and 265 s were measured that way, with
contradictory verdicts.

## The `.buddy` format

A buddy is data, not code: a text file in
`~/Library/Application Support/VibeBuddy/buddies/`, reloaded on save without
relaunching or recompiling. Edit it by hand — the app's settings show a preview
of the six faces and nothing more.

A face, not glyphs: one screen, two eyes drawn **mirrored**, an optional mouth.

```
kind: eyes
face: 62x30 r8                # or « 62x30 oval »

idle (amber #FFBB00)
eye   shape:oval w:13 h:12 r:6 gap:10 y:0
mouth shape:arc w:24 h:9 t:0.6 bend:1 y:8
time  beat:1.6 blink:0.3 grain:0.03 glitch:0 gaze:wander
```

Shapes: `oval · iris · arc · ring · wing · line · dots · caret · x`. A manifest
**picks** one, it never describes one — a third-party file does not get to
become a geometry evaluator inside the render loop.

Gazes: `none · calm · bored · scan · wander · dart`. A repertoire, not a speed.

Six expressions: `sleeping`, `idle`, `working`, `awaiting`, `finished`,
`failed`. Only `idle` is required, the others fall back to it. The colour word
before the hex code is decoration, only the `#RRGGBB` counts.

Movement is discrete. A *beat* lasts a second or two; the eyes hold a position
for the whole beat and are somewhere else on the next one, with a 0.26 s travel
and an overshoot. The sequence comes from a hash of the beat index: same phase,
same picture, so there is nothing to remember, no `Task` and no `Timer`.

Rasterisation is analytic. Every cell of the screen is tested against the
outline and lit whole or not at all — nothing is drawn smooth then quantised.

Three formats came before this one: bezier paths, a pixel grid, then animated
text. RFC-005 §4 says why each fell, with the measurements. Do not go back to
one without reading it.

## The constraint that governs

Lightness comes before features. The app is on screen permanently, so every
needless wakeup is paid for in battery life.

| Metric | Target | Measured |
|---|---|---|
| `phys_footprint` | < 40 MB | 15.0 MB |
| Idle wakeups at rest | < 2/s | 0.249/s |
| CPU at rest | < 0.5 % | 0.000 % |
| `fork`/`exec` at rest | 0 | 0 |

Measured on 2026-08-21, scenario A, 594 s, 120 samples
(`docs/perf/20260821-2136-004-A.csv`). Measure again rather than quoting these,
that is the repository's rule.

Following the pointer costs **nothing** at rest: the gaze rides an event
monitor, silent until the mouse moves. Polling `NSEvent.mouseLocation` at 10 Hz
was measured at 6.3 wakeups/s against a budget of 2.

Wakeup count governs, not CPU percentage: a process sitting at 0.4 % CPU with 70
wakeups per second drains a battery without crossing any threshold expressed as
a percentage. Hence a single clock for the whole app (`WakeCoordinator`), and an
animation budget that can drop to zero frames per second.

## Tests

```sh
make test                     # 467 tests, 78 suites
make test-filter filter=PermissionQueue
make lint                     # fails on any compiler warning
```

They cover what breaks silently: the transcript parser, the alert state machine,
notch geometry, the `.buddy` format, the context window, terminal matching, the
hook wire format byte for byte, the permission queue's five exits, and the
ordered JSON that keeps `~/.claude/settings.json` in the order its owner wrote
it.

What they do **not** catch is what only a real session shows. Five defects were
found in one evening of driving Claude Code by hand, none of them visible to any
of the 467: a permission expiring because a *neighbouring* session wrote to its
transcript, a panel expiring itself two seconds after opening, a refusal sent
with an empty message so the model kept retrying. Field-test the thing.

## The Claude Code hook

Permission interception needs a hook registered in `~/.claude/settings.json`.
The app never writes that file on its own: the command shows the exact diff and
waits.

```sh
make install-hook                          # shows the diff, asks, then writes
make install-hook settings=/tmp/copy.json  # aim at a copy instead
make uninstall-hook                        # removes exactly our entries
```

A second executable, `vibe-hook`, is what Claude Code actually runs — Foundation
only, no AppKit, **3.2 ms** to start against a target of 8. It is spawned on
every tool call of every session, so what it links is what it costs. If the app
is not running it exits 0 without writing, and Claude Code falls back to its own
prompt: a hook that hangs is worse than no hook.

## Documentation

| File | Contents |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | The rules: product goals, structural decisions, Gantt, conventions |
| [`docs/rfc/`](docs/rfc/) | One RFC per subject, with its action plan and percentages |
| [`docs/perf/`](docs/perf/) | The measurements, as dated CSVs |

## Inspiration

Inspired by Notch-Pilot for the mechanics of collecting Claude's data and its
integration in Swift.

This is not a fork, but a different and free interpretation.
