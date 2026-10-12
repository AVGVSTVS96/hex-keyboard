# Hex Keyboard

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that looks and types like Apple's. MIT.

## Layout

- `Packages/HexKeyboard/Sources/KeyboardCore`: pure Swift, no Foundation or UIKit (it also compiles to WebAssembly). Everything the keyboard does lives here, so the extension and the web demo share it. Fully unit tested.
  - `Keys/`: layouts per device class, `KeyGrid` (key frames and hit testing), metrics, key faces and theme.
  - `Typing/`: `TypingEngine` takes `KeyboardEvent`s (`handle`) and does shift, caps lock, autocap, double-space period, smart punctuation, layers, word delete, autocorrect and reverts, and the tap labels it learns from. It reads the text only from `TextState` (see Rules).
  - `Correction/`: `Corrector` (what to correct, text replacements, names, learned words) over a `CandidateSource`. With a `Lexicon` (a flat byte trie of words and frequencies) as its source it decodes taps (`Decoder`, exact A* over the trie) against your `TouchModel` (each key a 2D Gaussian with a conjugate Normal-Inverse-Wishart prior, whose center blends three memories of where you aim, all taps, the last ~30 and the last ~3, weighted by how well each predicted your taps) and a `LanguageModel` (Witten-Bell over your next-word counts, your words, `NextWords` (the corpus's likeliest followers of each common word) and the lexicon). `KeyMap` (which key a touch means) is made off the main thread after every edit. `TypingMemory` holds everything learned and is `Codable`. `Aim` turns the touch model into what the app shows: each key's learned center and spread in points, its last 48 taps, and the share of its taps the grid would put on each key.
- `Packages/HexKeyboard/Sources/KeyboardUI`: UIKit. `HexKeyboardViewController` (the extension's principal class: forwards events to the engine, renders, runs ranking jobs), `KeyboardView` (one view owns all touches: rollover, slide-off, callouts, long-press accents, spacebar trackpad, iPad flicks), `KeyView`, `SuggestionBar`, `Lexicon.english` (`Resources/en.lexicon`, built by `scripts/lexicon`) and `NextWords.english` (`Resources/en.next`, built by `scripts/nextwords.py` from the same corpus's 2-grams; sources and licenses in `Resources/LEXICON-LICENSE`), `SettingsStore` (the App Group, plus each side's own copy, so settings outlive the group's container, which iOS deletes whenever an install leaves no app claiming the group) and `MemoryStore` (the extension's own container; the app resets it by sharing a new reset token; with Full Access the keyboard also writes its touch model to the group as `touches.json` and posts a Darwin notification), `KeyHaptics` (Apple's keyboard haptic values, played with public Core Haptics on an engine the keyboard owns), `TapMapView` (the keyboard drawn with what the touch model learned, for the app).
- `Packages/HexKeyboard/Tools/LexiconBuilder`: turns `scripts/lexicon.py`'s word counts into `en.lexicon` with `Lexicon(counts:)`, so the format has one implementation.
- `Packages/HexKeyboard/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (see below), with `TextCheckerSource` (`UITextChecker`) as its baseline keyboard.
- `web/`: the web demo. `Sources/HexWeb` exports a `Keyboard` class to JavaScript (JavaScriptKit BridgeJS) that forwards to `TypingEngine` the way `HexKeyboardViewController` does, against the page's text field; `site/` draws the keys from `KeyboardCore`'s metrics, faces and colors and ports `KeyboardView+Touches` to pointer events. Deployed to Vercel as `hex-keyboard`.
- `Keyboard/`: the extension target, a one-line subclass.
- `App/`: the containing app (setup steps, a test field, settings, and Your Taps: `TapMapView` with stats, per-key detail and the most-missed keys).
- `UITests/`: types through the real extension in the simulator.
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box. Simulator builds, tests and screenshots run on a Mac over ssh (`ssh mac`); the iPhone build is made and installed on the Linux box with `scripts/phone` (see below). `scripts/mac <command>` syncs the tree to `~/Developer/hex-keyboard` on the Mac and runs the command there. Device builds take the team from `Config/Team.xcconfig` (`DEVELOPMENT_TEAM = …`, not committed), which syncing leaves in place. To prove a change works, follow the `verify` skill (`.claude/skills/verify`).

```sh
scripts/mac scripts/build                       # sync to the Mac, xcodegen, build for the simulator
scripts/mac scripts/test                        # KeyboardCore unit tests on an iOS simulator
scripts/mac scripts/uitest                      # type through the real extension (iPhone 17 by default)
scripts/mac 'scripts/sim all v7'                # screenshots: system vs Hex, light and dark, 8 devices
scripts/mac 'scripts/sim variants "iPhone 17" v7'  # return key types, keyboard types, landscape
scripts/mac 'scripts/capture "iPhone 17" iPhone-17 hex'  # frames of held keys: pop-ups, accent panel
scripts/mac 'scripts/shots "iPhone 17" iPhone-17 system light "hel:hel|helo:o"'  # type through a keyboard, screenshot each step
scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max touches.json t1'  # the app's Your Taps screen with a touch model
scripts/mac scripts/eval                        # scorer: the phrase corpus typed with tap noise and with biased thumbs, checked against scripts/eval.expected
scripts/web                                     # web demo into web/dist (swift.org 6.4.0 toolchain + its Wasm SDK + binaryen; on the Mac: rsync, then run it there)
scripts/lexicon                                 # rebuild en.lexicon (downloads ~1 GB, streams ~30 GB of 2-grams)
uv run --no-project python3 scripts/nextwords.py build/bigrams build/lexicon/words.tsv Packages/HexKeyboard/Sources/KeyboardUI/Resources/en.next   # see its docstring for the 2-gram shards
uv run --with pillow --with numpy --with scipy scripts/shotdiff.py v7   # key-by-key geometry vs Apple
```

`scripts/sim` creates its own `hexkb …` simulators and enables the extension by writing `AppleKeyboards` (and, for iPad, `AppleKeyboardsExpanded = 1`) into the simulator's global preferences, so no Settings UI is needed. Simulators boot headless; the Simulator app never opens. Reference screenshots of Apple's keyboard come from the same simulators with `KEYBOARDS=system`.

Builds are ad-hoc signed for the simulator (`CODE_SIGN_IDENTITY = -`), which embeds simulated entitlements, so the App Group works in the simulator without a team. Device builds need a team with the group `group.com.shahidy.hexkeyboard` registered.

`scripts/phone` builds the app and keyboard with [xtool](https://github.com/xtool-org/xtool) from the root `Package.swift` and `xtool.yml` (their Info.plists are `Config/xtool/`, kept in step with `project.yml` by hand), signs them with a free-team profile that xtool renews on every run, and installs them over Wi-Fi through [netmuxd](https://github.com/jkcoxson/netmuxd). It needs Swift 6.4, xtool built from the `keep-identifiers` branch of [AVGVSTVS96/xtool](https://github.com/AVGVSTVS96/xtool) (`XTL_KEEP_IDENTIFIERS=1` signs with the real bundle and group IDs, so it updates the installed app and keeps its data; stock xtool installs a separate `XTL-…` copy; the branch also carries [xtool-org/xtool#284](https://github.com/xtool-org/xtool/pull/284), without which xtool drops the App Group entitlement on free teams and iOS deletes the group's container), xtool's Darwin SDK (`xtool sdk install` on Xcode's SDK folders), `xtool auth login`, and netmuxd holding the phone's pairing record. The keyboard target links with `-ObjC` because its principal class is only named in Info.plist.

`scripts/eval` types the MacKenzie & Soukoreff phrase set (500 phrases, 2,714 words) through `TypingEngine` with taps drawn from a Gaussian around the real key centers (`KeyGrid`, iPhone 17 width), seeded, and prints word accuracy without and with autocorrect and the top-3 suggestion hit rate, for three keyboards: (a) nearest key + `UITextChecker`, (b) Hex's decoder with the touch model held at its prior, (c) the decoder learning. `noise` reruns the original noise levels; `biasedThumbs` types the corpus twice as a user whose m, b and o land off target and prints a learning curve; `aimShift` types it once that way, then again after the user's aim moves (lower and right, o and e swinging the other way), and prints how fast the learning keyboard follows. It runs a Release build (the decoder is slow in Debug). A full run is diffed against `scripts/eval.expected`: a change that moves the numbers must beat them, and updates that file in the same commit.

## Rules

- Match the system keyboard to the pixel. Measure against reference screenshots in the same simulator (`shots/`), don't eyeball.
- Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The only timers are the inherent ones: key repeat and long-press.
- No comments unless they record a non-obvious fact.
- Keycaps use SF Compact, loaded from the system font file, because that is what the system keyboard uses (verified by glyph metrics) and UIKit has no public name for it. It falls back to SF Pro.
- iOS 26 ignores a plain height constraint on the input view; the height comes from Auto Layout content (`keyboardHeightConstraint`).
- Third-party keyboards get a system bottom bar (globe, mic) on Face ID iPhones and a system undo/redo/paste bar on iPad. Metrics are calibrated so the keys land where Apple's do with those bars in place.
- A third-party keyboard can't draw above its own area, so top-row pop-ups are clamped into the 27pt strip above the keys. The host draws 16pt of backdrop above that strip, so the suggestion bar lives in the 27pt strip: Apple's 38pt pill becomes 27pt and the text sits ~5pt lower than Apple's, but the keyboard height and keys stay identical.
- On iPad the system's own shortcut bar (undo, redo, paste) sits above a third-party keyboard and its middle can't be used, so Hex adds a 36pt suggestion row there when Predictive Text is on.
- A correctly typed real word must never be changed. The corrector replaces a word that stands on its own (kept, or read as itself when typed perfectly) only when the touches favor the other word; word frequencies may only choose among what the fingers could have meant.
- Learning comes only from real events: the letters of a word you kept once you move on (next word, keyboard hidden), a reverted correction teaches what you typed, and a backspace-then-retype within a quarter key labels the erased tap. Words you delete teach nothing. Nothing in the model runs on a clock: older taps fade only as newer taps of the same key arrive, and every weight is a posterior or a count.
- The engine reads the text only from its `TextState`. Every edit goes through `TypingEngine.write`, which changes the host and `TextState` together; the host's reports (`textDidChange`, `selectionDidChange`) reach it only through `documentChanged`, which ignores reports that show the keyboard's own edits late or in a shorter window and adopts anything else. Automatic edits only replace characters the keyboard typed itself (`TextState.owned`).
- iOS doesn't deliver touches that land on fully transparent pixels of a third-party keyboard. `KeyboardInputView` has an invisible fill (alpha 0.001, pixel-identical in screenshots) so gaps between keys still take taps; `FirstTapTests` checks it.
- Keyboard behavior goes in `KeyboardCore`; `KeyboardUI` and `web/` only draw, play feedback and forward events, so the two never drift.
- `KeyboardCore` takes no Foundation or UIKit import (`ArchitectureTests` checks). Platform services (UILexicon, files, the scorer's UITextChecker) live outside it behind Core protocols.
