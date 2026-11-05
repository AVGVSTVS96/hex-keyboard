# iikb

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that types like Apple's and looks like Raycast's (docs/design.md). MIT. It was called Hex until Nov 3 2026: what people see says iikb (lowercase always; `brand/BRAND.md`, `copy/MESSAGING.md`), while code names and IDs keep Hex (`HexKeyboard`, `HexStyle`, `com.shahidy.hexkeyboard`, `hexkeyboard://`), so installs keep their data.

## Modules

Each module keeps its own AGENTS.md beside its code, with what it holds and why. Read it before working in that module. What a module may import is set in `Packages/HexKeyboard/Package.swift` and the root `Package.swift`.

- `Packages/HexKeyboard/Sources/KeyboardCore`: everything the keyboard does (keys, layouts, typing, correction, swipe, dictation's text), so the extension and the web demo share it. Imports nothing, not even Foundation; it also compiles to WebAssembly. [KeyboardCore/AGENTS.md](Packages/HexKeyboard/Sources/KeyboardCore/AGENTS.md)
- `…/KeyboardEnglish`: the bundled English data and its loaders. On KeyboardCore and Foundation. [KeyboardEnglish/AGENTS.md](Packages/HexKeyboard/Sources/KeyboardEnglish/AGENTS.md)
- `…/HexStore`: iikb's saved data and the app–keyboard channel, through `StoredFile`. On KeyboardCore and KeyboardEnglish. [HexStore/AGENTS.md](Packages/HexKeyboard/Sources/HexStore/AGENTS.md)
- `…/KeyboardUI`: UIKit parts any keyboard can build on, with no private API. On KeyboardCore and KeyboardEnglish. [KeyboardUI/AGENTS.md](Packages/HexKeyboard/Sources/KeyboardUI/AGENTS.md)
- `…/HexKeyboard`: iikb's own keyboard (the view controller, its panels, sources, the host app). On the four above, and the only target that links the private `KeyboardArbiter`. [HexKeyboard/AGENTS.md](Packages/HexKeyboard/Sources/HexKeyboard/AGENTS.md)
- `App/`: the containing app, a folder per feature. On KeyboardEnglish, HexStore, KeyboardUI and FluidAudio, never HexKeyboard. [App/AGENTS.md](App/AGENTS.md); voice typing in [App/Voice/AGENTS.md](App/Voice/AGENTS.md)
- `Keyboard/`: the extension target, a one-line subclass. On HexKeyboard.
- `Packages/HexKeyboard/Examples/MinimalKeyboard`: a keyboard with a look of its own on `TypingEngine`, in one file, for docs/build-a-keyboard.md (the guide for building on iikb). It's its own package target, so it reaches only public API. Neither `scripts/check` nor `scripts/coretest` builds it, so a change to that API needs it built on the Mac to keep the guide true.
- `Packages/HexKeyboard/Tools`: the builders of KeyboardEnglish's data (KeyboardEnglish/AGENTS.md).
- `Packages/HexKeyboard/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (scripts/AGENTS.md, "scripts/eval"), with `TextCheckerSource` (`UITextChecker`) as its baseline keyboard.
- `UITests/`: types through the real extension in the simulator.
- `web/`: the web demo and iikb's page, on KeyboardCore through `TypingEngine`, deployed to iikb.vercel.app. [web/AGENTS.md](web/AGENTS.md)
- `sources/record.ts`: the record source (Bun): a log of every message you send and every field you leave with text you typed, with the host bundle ID the keyboard sends (docs/sources.md). `bun test sources/`.
- `server/backup.ts`: the backup server (HexStore/AGENTS.md, "Backup").
- `scripts/`: build, install, simulator and measuring scripts. [scripts/AGENTS.md](scripts/AGENTS.md)
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box. Simulator builds, tests and screenshots run on a Mac over ssh (`ssh mac`); the iPhone build is made here and installed through the Mac with `scripts/phone`.
- `scripts/mac <command>` syncs the tree to one of the Mac's three slots and runs the command there inside one of the Mac's turns (`turn`, two heavy runs at once across projects). Each slot has its own folder and its own simulators, so up to two runs go at once and the rest wait, and the Mac never runs more than three simulators, counting other projects'.
- A change is checked here first: `scripts/coretest` for KeyboardCore, `scripts/check` for whether everything builds for the iPhone. Then it goes to main and onto the phone with `scripts/phone` as soon as it's ready, since the phone is where changes are tried.
- The simulator is for what only it shows (a layout, a screen, typing through the real extension), one run at a time, and one to three agents test what landed together with `scripts/verify`, which always tests main's last commit.
- Device builds take the team from `Config/Team.xcconfig` (`DEVELOPMENT_TEAM = …`, not committed), which syncing leaves in place.
- To prove a change works, follow the `verify` skill (`.claude/skills/verify`).

Prefer committing straight to main, merge parallel work like a zipper on new projects

```sh
scripts/mac scripts/build                       # sync to the Mac, xcodegen, build for the simulator
scripts/coretest                                # KeyboardCore's tests here on Linux, no Mac (about 25 s)
scripts/check                                   # this checkout built for the iPhone here on Linux, unsigned (a few minutes; one at a time)
scripts/phone                                   # main's last commit built, signed and installed on the iPhone (--reinstall renews the signing)
scripts/backup <udid>                           # the iPhone's iikb data copied to ~/.local/share/hex-keyboard/backup here, never deleted, replaced files kept in versions/ (scripts/phone runs it first)
scripts/restore <udid> [--at <time>|now] [name…]  # the backup put back on the iPhone, all of it or the files named, as it is or as it was at a time; leaves out a copy much smaller than one replaced in the day after an install left Hex a new, empty container (docs/backup.md). An old build can't read a memory restored without its token, so restore only after scripts/phone
scripts/mac scripts/verify                      # what landed, at once, on one iPhone Duo simulator: package and UI tests, light and dark, shots in shots/raw/verify/
scripts/mac scripts/test                        # KeyboardCore and KeyboardUI package tests on an iOS simulator
scripts/mac scripts/uitest                      # type through the real extension (the iPhone Duo by default)
scripts/mac 'scripts/sim all v7'                # screenshots: system vs Hex, light and dark, 8 devices
scripts/mac 'scripts/sim variants "iPhone 17" v7'  # return key types, keyboard types, landscape
scripts/mac 'scripts/sim duo v8'                # Apple's keyboard and Hex on the iPhone Duo's four screens, folded and open (unfolded with Device Hub's hinge event, scripts/devicehub.c)
scripts/mac 'scripts/capture "iPhone 17" iPhone-17 hex'  # frames of held keys: pop-ups, accent panel (CAPTURE=menu: the 123 menu)
scripts/mac 'scripts/shots "iPhone 17" iPhone-17 system light "hel:hel|helo:o"'  # type through a keyboard, screenshot each step
scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max touches.json t1'  # the app's Stats › Taps screen with a touch model
scripts/keystroke                               # the Mac sends Keystroke's typing-stats.json to the backup server each time Keystroke saves it, for Stats (docs/stats.md)
scripts/mac scripts/sourcetest                  # a source through the real keyboard, scripts/source.py standing in for it; prints every update it was sent
scripts/mac scripts/voicetest                   # the bar's mic through the real keyboard, scripts/voiceapp.py standing in for the app; screenshots light and dark
scripts/voiceprobe v3 clip.wav                  # on the iPhone: a Parakeet's load and write times in the installed Hex (scripts/phone)
scripts/eval                                    # scorer here on Linux: the phrase corpus typed with tap noise and with biased thumbs, checked against scripts/eval.expected (scripts/mac scripts/eval adds the UITextChecker baseline)
scripts/web                                     # web demo into web/dist (swift.org 6.4.0 toolchain + its Wasm SDK + binaryen; on the Mac: rsync, then run it there)
scripts/lexicon                                 # rebuild en.lexicon (downloads ~1 GB, streams ~30 GB of 2-grams)
scripts/personal record.jsonl [en.network [out]] # fine-tune en.network on your typing (the server does it when the record changes)
scripts/network                                 # retrain en.network (downloads ~20 GB, about three hours on the Mac's GPU)
scripts/mac scripts/applebar in.txt out.txt     # Apple's own suggestion bar before each word and after its first two letters, typed through the system keyboard in the simulator, for head-to-heads
python3 scripts/barmatch.py apple.txt iikb.txt   # the suggestion bar's measure: how many of Apple's bar words iikb's bar shows on the same text, how often the bars are the same, and where each has the word typed next
uv run --with pillow --with numpy --with scipy scripts/shotdiff.py v7   # key-by-key geometry vs Apple
```

## Rules

- Keys behave as Apple's do (layouts, pop-ups, accents, the trackpad, the suggestion bar) and are laid out from Apple's keyboard measured in the same simulator (`shots/`, `scripts/shotdiff.py`), never eyeballed. Their look and sizes are docs/design.md's, after Raycast's keyboard: where it moves keys off Apple's geometry (the bottom row's widths, the Duo's keys filling the room they're given), it says so and why; everywhere else a key sits where Apple's does.
- Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The keyboard's only timers are the inherent ones: key repeat, long-press, and a source's 10 s to answer. The app's are listed in App/Voice/AGENTS.md. Each timer's line says which it is, `// timer: <which>` (`ArchitectureTests` checks).
- No comments unless they record a non-obvious fact.
- Keyboard behavior goes in `KeyboardCore`; `KeyboardUI` and `web/` only draw, play feedback and forward events, so the two never drift.
- `KeyboardCore` takes no Foundation or UIKit import (`ArchitectureTests` checks).
- A correctly typed real word must never be changed, and learning comes only from real events (KeyboardCore/AGENTS.md, "Correction/").
- The engine reads the text only from its `TextState` (KeyboardCore/AGENTS.md, "Typing/").
- Recording never waits for a model (App/Voice/AGENTS.md).
- Kept data reads and saves through `StoredFile` (HexStore/AGENTS.md; `ArchitectureTests` checks).
- A new use of the host app goes through `HexKeyboardViewController.hostApp` (HexKeyboard/AGENTS.md).
