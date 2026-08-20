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
4. Do it playfully: an animated *buddy* carries the state in the notch.

## Install and run

The app is not packaged yet, it runs from the repository. RFC-011 covers that.

```sh
swift build -c release
.build/release/VibeBuddy              # runs until Ctrl-C or the power button
```

Buddies live outside the binary, in
`~/Library/Application Support/VibeBuddy/buddies/`. To edit the ones in the
repository in place:

```sh
mkdir -p ~/Library/Application\ Support/VibeBuddy/buddies
ln -s "$PWD/assets/buddies/emoji.buddy" ~/Library/Application\ Support/VibeBuddy/buddies/
```

They reload when the file is saved, with no relaunch and no rebuild.

## Diagnostics and measurement

`--info` is the first thing to reach for: screens, geometry, computed frames,
wake and animation budgets, installed buddies with their frame rate, language,
the parser run against real transcripts, live sessions with their tty, usage,
memory cost.

```sh
.build/release/VibeBuddy --info
.build/release/VibeBuddy --hover                  # hover regions against the pixels actually painted
.build/release/VibeBuddy --bench <mode> <seconds>
#   modes: shell · panel · pill · hidden · interaction · sessions · app
scripts/perfcheck.sh <scenario> <duration>        # A rest · B 3 sessions · C panel open
```

## The `.buddy` format

A buddy is data, not code: a text file, editable by hand or from the app's
settings.

```
font: Menlo                   # optional, system font by default
size: 15                      # default size
speed: 1                      # frames per second, 1 by default

idle (yellow #FFBB00) 17 3    # colour, then size, then speed (positional)
(ᵕ • ᴗ •)                     # one frame per line
(„• ֊ •„)
                              # a blank line ends the section
```

Six expressions: `sleeping`, `idle`, `working`, `awaiting`, `finished`,
`failed`. Only `idle` is required, the others fall back to it. The colour word
before the hex code is decoration, only the `#RRGGBB` counts.

Two formats came before this one, bezier paths then a pixel grid. Both worked at
poster size and lost their meaning at 20 pt.

## The constraint that governs

Lightness comes before features. The app is on screen permanently, so every
needless wakeup is paid for in battery life.

| Metric | Target | Measured |
|---|---|---|
| `phys_footprint` | < 40 MB | 11.8 MB (`--bench pill 10`) |
| Idle wakeups at rest | < 2/s | 0.000/s (same run) |
| CPU at rest | < 0.5 % | 0.016 % (same run) |
| `fork`/`exec` at rest | 0 | 0 |

Measured on 2026-08-20 on the development machine, pill on screen and panel
closed. Measure again rather than quoting these, that is the repository's rule.

Wakeup count governs, not CPU percentage: a process sitting at 0.4 % CPU with 70
wakeups per second drains a battery without crossing any threshold expressed as
a percentage. Hence a single clock for the whole app (`WakeCoordinator`), and an
animation budget that can drop to zero frames per second.

## Tests

```sh
swift test        # 261 tests, 51 suites
```

They cover what breaks silently: the transcript parser, the alert state machine,
notch geometry, the `.buddy` format, the context window, the buddy edit layer and
terminal matching.

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
