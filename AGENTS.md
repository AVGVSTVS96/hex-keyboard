# iikb

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that types like Apple's and looks like Raycast's (docs/design.md). MIT. Its name is iikb, lowercase always, in what people see and in code names and IDs alike (`brand/BRAND.md`, `copy/MESSAGING.md`).

## Modules

Each module keeps its own AGENTS.md beside its code, with what it holds and why. Read it before working in that module. What a module may import is set in `Packages/KeyboardModules/Package.swift` and the root `Package.swift`.

- `Packages/KeyboardModules/Sources/KeyboardCore`: everything the keyboard does (keys, layouts, typing, correction, swipe, dictation's text), so the extension and the web demo share it. Imports nothing, not even Foundation; it also compiles to WebAssembly. [KeyboardCore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardCore/AGENTS.md)
- `…/KeyboardEnglish`: the bundled English data and its loaders. On KeyboardCore and Foundation. [KeyboardEnglish/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardEnglish/AGENTS.md)
- `…/KeyboardStore`: iikb's saved data and the app–keyboard channel, through `StoredFile`. On KeyboardCore and KeyboardEnglish. [KeyboardStore/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardStore/AGENTS.md)
- `…/KeyboardUI`: UIKit parts any keyboard can build on, with no private API. On KeyboardCore and KeyboardEnglish. [KeyboardUI/AGENTS.md](Packages/KeyboardModules/Sources/KeyboardUI/AGENTS.md)
- `…/FullKeyboard`: iikb's own keyboard (the view controller, its panels, sources, the host app). On the four above, and the only target that links the private `KeyboardArbiter`. [FullKeyboard/AGENTS.md](Packages/KeyboardModules/Sources/FullKeyboard/AGENTS.md)
- `App/`: the containing app, a folder per feature. On KeyboardEnglish, KeyboardStore, KeyboardUI and FluidAudio, never FullKeyboard. [App/AGENTS.md](App/AGENTS.md); voice typing in [App/Voice/AGENTS.md](App/Voice/AGENTS.md)
- `Keyboard/`: the extension target, a one-line subclass. On FullKeyboard.
- `Packages/KeyboardModules/Examples/MinimalKeyboard`: a keyboard with a look of its own on `TypingEngine`, in one file, for docs/build-a-keyboard.md (the guide for building on iikb). It's its own package target, so it reaches only public API. Neither `scripts/check` nor `scripts/coretest` builds it, so a change to that API needs it built on the Mac to keep the guide true.
- `Packages/KeyboardModules/Tools`: the builders of KeyboardEnglish's data (KeyboardEnglish/AGENTS.md).
- `Packages/KeyboardModules/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (scripts/AGENTS.md, "scripts/eval"), with `TextCheckerSource` (`UITextChecker`) as its baseline keyboard.
- `UITests/`: types through the real extension in the simulator.
- `web/`: the web demo and iikb's page, on KeyboardCore through `TypingEngine`, deployed to iikb.vercel.app. [web/AGENTS.md](web/AGENTS.md)
- `sources/record.ts`: the record source (Bun): a log of every message you send and every field you leave with text you typed, with the host bundle ID the keyboard sends (docs/sources.md). `bun test sources/`.
- `server/backup.ts`: the backup server (KeyboardStore/AGENTS.md, "Backup").
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
scripts/backup <udid>                           # the iPhone's iikb data copied to ~/.local/share/iikb/backup here, never deleted, replaced files kept in versions/ (scripts/phone runs it first)
scripts/restore <udid> [--at <time>|now] [name…]  # the backup put back on the iPhone, all of it or the files named, as it is or as it was at a time; leaves out a copy much smaller than one replaced in the day after an install left iikb a new, empty container (docs/backup.md)
scripts/mac scripts/verify                      # what landed, at once, on one iPhone Duo simulator: package and UI tests, light and dark, shots in shots/raw/verify/
scripts/mac scripts/test                        # KeyboardCore and KeyboardUI package tests on an iOS simulator
scripts/mac scripts/uitest                      # type through the real extension (the iPhone Duo by default)
scripts/mac 'scripts/sim all v7'                # screenshots: system vs iikb, light and dark, 8 devices
scripts/mac 'scripts/sim variants "iPhone 17" v7'  # return key types, keyboard types, landscape
scripts/mac 'scripts/sim duo v8'                # Apple's keyboard and iikb on the iPhone Duo's four screens, folded and open (unfolded with Device Hub's hinge event, scripts/devicehub.c)
scripts/mac 'scripts/capture "iPhone 17" iPhone-17 iikb'  # frames of held keys: pop-ups, accent panel (CAPTURE=menu: the 123 menu)
scripts/mac 'scripts/shots "iPhone 17" iPhone-17 system light "hel:hel|helo:o"'  # type through a keyboard, screenshot each step
scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max touches.json t1'  # the app's Stats › Taps screen with a touch model
scripts/keystroke                               # the Mac sends Keystroke's typing-stats.json to the backup server each time Keystroke saves it, for Stats (docs/stats.md)
scripts/mac scripts/sourcetest                  # a source through the real keyboard, scripts/source.py standing in for it; prints every update it was sent
scripts/mac scripts/voicetest                   # the bar's mic through the real keyboard, scripts/voiceapp.py standing in for the app; screenshots light and dark
scripts/mac scripts/edittest                    # what dictations become: a long one edited in the middle and a short one edited at its end, each sent, checked in its transcript (made-up text)
scripts/voiceprobe v3 clip.wav                  # on the iPhone: a Parakeet's load and write times in the installed iikb (scripts/phone)
scripts/eval                                    # scorer here on Linux: the phrase corpus typed with tap noise and with biased thumbs, checked against scripts/eval.expected (scripts/mac scripts/eval adds the UITextChecker baseline)
scripts/gate                                    # the bar on everyday text (scripts/gate.txt) through TypingEngine: fresh, with awkward contact names, and on the iPhone's own network and memory from the backup; scripts/phone installs no build that fails it (about 2 min)
scripts/web                                     # web demo into web/dist (swift.org 6.4.0 toolchain + its Wasm SDK + binaryen; on the Mac: rsync, then run it there)
scripts/lexicon                                 # rebuild en.lexicon (downloads ~1 GB, streams ~30 GB of 2-grams)
scripts/personal record.jsonl [en.network [out]] # fine-tune en.network on your typing (the server does it when the record changes)
scripts/network                                 # retrain en.network (downloads ~20 GB, about three hours on the Mac's GPU)
scripts/mac scripts/applebar in.txt out.txt     # Apple's own suggestion bar before each word and after its first two letters, typed through the system keyboard in the simulator, for head-to-heads
python3 scripts/barmatch.py apple.txt iikb.txt   # the suggestion bar's measure: how many of Apple's bar words iikb's bar shows on the same text, how often the bars are the same, and where each has the word typed next
uv run --with pillow --with numpy --with scipy scripts/shotdiff.py v7   # key-by-key geometry vs Apple
```

## Rules

Each rule with what enforces it. When an agent repeats a mistake, fix it at the highest level that works (a module boundary, then a type, then a check whose error names the fix) and add its row here; drop a row once its mistake can't happen. The why behind each rule, iOS facts included, is in the module doc named.

| Rule | Enforced by |
| --- | --- |
| `KeyboardCore` imports nothing, not even Foundation; platform services sit outside it behind Core protocols | Package.swift (no dependencies), `ArchitectureTests` |
| Keyboard behavior goes in `KeyboardCore`; `KeyboardUI` and `web/` only draw, play feedback and forward events, so the two never drift | judgment: nothing enforces it |
| `KeyboardUI` uses no private API; only `FullKeyboard` links `KeyboardArbiter` | Package.swift for `KeyboardArbiter`; judgment for anything called by name |
| The app never imports `FullKeyboard` | Package.swift, project.yml |
| Kept data reads and saves through `StoredFile`, which never saves over a file it couldn't read; any other file access says what it is, `// file: <what>` (KeyboardStore) | `StoredFile`, `ArchitectureTests` |
| Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The keyboard's only timers are key repeat, long-press and a source's 10 s to answer; the app's are in App/Voice. Each timer's line says which it is, `// timer: <which>` | `ArchitectureTests` |
| The engine reads the text only from its `TextState`; every edit goes through `TypingEngine.write`; automatic edits replace only characters the keyboard typed (KeyboardCore) | `TextState`, `TextStateStressTests` |
| A correctly typed real word is never changed; word frequencies only choose among what the fingers could have meant (KeyboardCore) | `TypingModelTests`, `scripts/eval` |
| Learning comes only from real events, and nothing in the model runs on a clock (KeyboardCore) | `TypingModelTests` |
| A change that moves the eval's numbers beats them and updates `scripts/eval.expected` in the same commit (scripts) | `scripts/eval` diffs every full run |
| Keys behave and sit as Apple's do, measured in the same simulator (`shots/`, `scripts/shotdiff.py`), never eyeballed; docs/design.md says where and why it moves a key off Apple's geometry | judgment, measured with `scripts/shotdiff.py` |
| The keyboard, the app's preview and Your Taps lay out the same keys (KeyboardCore) | `KeyboardGeometry`, `GeometryTests` |
| The bar's buttons are set out as the top row's keys are (KeyboardCore) | `BarLayoutTests` |
| Gaps between keys take taps (KeyboardUI) | `FirstTapTests` |
| Keycaps use SF Compact from the system font file (KeyboardUI) | judgment: nothing enforces it |
| The keyboard's height comes from Auto Layout content, never a plain height constraint (KeyboardUI) | judgment: nothing enforces it |
| Recording never waits for a model: the `Microphone` knows nothing of `VoiceModel` (App/Voice) | judgment: nothing enforces it |
| Never a Bluetooth microphone unless one is picked in Settings › Microphone (App/Voice) | judgment: nothing enforces it |
| A new use of the host app goes through `FullKeyboardViewController.hostApp` (FullKeyboard) | judgment: nothing enforces it |
| Only main's last commit reaches the phone, never mid-dictation, never without backup, never linked below iOS 27.1 (scripts) | `scripts/phone`: builds main in its own worktree, waits for the dictation, refuses without `backup.key` or below 27.1 |
| Restore only after `scripts/phone`: an old build can't read a memory restored without its token | judgment: nothing enforces it |
| No comments unless they record a non-obvious fact | judgment: nothing enforces it |
| Every AGENTS.md names only code that exists, and no file keeps a conflict marker | `ArchitectureTests` |
| A change you'd notice in the app or keyboard carries a `Changelog:` trailer, one short line (App/Settings/ChangelogPage.swift) | judgment: nothing enforces it |
