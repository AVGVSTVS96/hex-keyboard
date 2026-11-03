---
name: verify
description: Prove a change to Hex Keyboard works the way a user meets it, with the cheapest real check first. KeyboardCore's tests and the iPhone build run here on Linux; the Mac's simulators type through the real keyboard extension and take screenshots; scripts/phone puts main on the iPhone, where changes are tried. Use before calling any change to the keyboard, the engine, the web demo or the app done.
---

# Verify Hex Keyboard

## Order

1. Here, on Linux: `scripts/coretest` for anything in `KeyboardCore` (and `scripts/eval` when it changes what gets typed), and `scripts/check` for anything that builds into the app or the keyboard (the iPhone build, unsigned, a few minutes). Both must pass before a change lands.
2. Land on main and run `scripts/phone`, the moment the change is ready: the iPhone is where changes are tried. It prints `build <N> (main <commit>) is on the iPhone`; quote that line, and the same number shows in the app at Settings › About.
3. The simulator only for what only it shows: one row below, on the iPhone Duo.
4. What landed together goes through `scripts/mac scripts/verify`, run by the one to three agents verifying, never by every builder.

## The Mac

`scripts/mac '<command>'` runs the command on the Mac in one of its slots, each with its own folder and simulators (`hexkb<n> …`), and copies `shots/raw/` back. The Mac runs at most three simulators, other projects' included; a run waits for a slot when they're taken, and shuts its simulators down when it ends. The Mac may be in use at the same time: simulators boot headless, and Simulator.app and Xcode stay closed. `ssh mac 'xcodebuild -version | head -1; xcrun simctl list devices booted'` shows the Xcode the build uses and what's booted.

## Drive

`scripts/mac scripts/verify` syncs main's last commit, builds once, and runs KeyboardUI's package tests and every UI test on one iPhone Duo simulator (light, then the screenshot tests in dark), with screenshots in `shots/raw/verify/`. It ends with `== done, passed` and exits 0, or `== done, failed`.

For one change, the row that applies:

| Change touches | Run | Passes when |
| --- | --- | --- |
| anything in `KeyboardCore` | `scripts/coretest` | `Test run with N tests … passed`. `TextStateStressTests` (3,000 seeded runs against a host that reports late and cut off) is one of them. |
| anything in the app or keyboard | `scripts/check` | it ends with `Wrote to …/Hex.app`. |
| the decoder, models, key map, autocorrect or what a touch types | `scripts/eval`, here (about 20 minutes; `scripts/mac scripts/eval` also scores the UITextChecker baseline) | it ends with `EVAL matches eval.expected`. A change that moves the numbers must beat them and updates `scripts/eval.expected` in the same commit. |
| how the keyboard looks on the Duo | `scripts/mac 'scripts/sim duo <tag>'` (`KEYBOARDS=hex`, `APPEARANCES=dark` narrow it) | `shots/raw/duo/` reads right in every pose. |
| how the app looks on the Duo | `scripts/mac 'scripts/sim duoapp <tag>'` (`PAGES=` narrows it) | `shots/raw/duo/app/` reads right in every pose. |
| typing through the real extension | `scripts/mac scripts/uitest` (`-only-testing:HexUITests/<Class>` after the device names one class) | every `Test Case … passed`, none failed. |
| the bar, the pills or a panel | `scripts/mac scripts/looktest` | `PanelTests … passed` for light and dark, and `shots/raw/look/` shows the main layout, the emoji panel, a search and the layout after. |
| the GIF or clipboard panel, `Klipy` or `ClipboardStore` | `scripts/mac scripts/paneltest` (needs the KLIPY key; see features/panels.md) | `ToolPanelTests … passed` for light and dark, and `shots/raw/panels/` shows trending, a search, Copied, recents, the clipboard rows and a pinned row. |
| voice typing (the bar's mic, `Dictation`, `Listener`'s signals) | `scripts/mac scripts/voicetest` | `VoiceTests … passed` for light and dark, and `shots/raw/voice/` shows the mic idle, listening, the typed text and the mic gone. |
| where keys sit against Apple's | `scripts/mac 'ONLY="iPhone 17" scripts/sim all <tag>'`, then `uv run --with pillow --with numpy --with scipy scripts/shotdiff.py <tag>` | key rects match Apple's within half a point, except what docs/design.md moves on purpose. |
| the web demo | sync `web/` to the Mac and run `scripts/web` there | it builds `web/dist`; open `web/dist/index.html` through a local server and type. |

The feature map in `features/` lists each feature, how a user reaches it, and the test that drives it.

## Evidence

Quote the summary lines each command prints: the test counts, the `EVAL` diff or match line, the UI test cases, the build on the iPhone. A proof exercises the real path (taps through the extension, the engine through `handle`), not internal setters.

## Gotchas

- The simulator merges overlapping synthesized fingers into one sliding finger, so overlap at speed is covered by `TouchReplayTests` (package tests), not by `FastTypingTests`.
- `scripts/eval` runs a Release build; the decoder is too slow in Debug for the numbers to finish in reasonable time.
- Taps from outside the simulator (axe, simctl) never reach a keyboard, Apple's or Hex's, and on the iPhone Duo `XCUIScreen.main` screenshots come out black in landscape and on the open screen, whose display is another of `XCUIScreen.screens`. Drive keyboards from a UI test and read key frames from `app.debugDescription`, as `AppleSplitShots` does for Apple's split (`TEST_RUNNER_HEX_SPLIT_SHOTS=<prefix>`, `-only-testing:HexUITests/AppleSplitShots`).
- iOS 27.1, the only simulator with the iPhone Duo, has no Messages, so tests that need it skip there.
