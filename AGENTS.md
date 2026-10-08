# Hex Keyboard

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that looks and types like Apple's. MIT.

## Layout

- `Packages/HexKeyboard/Sources/KeyboardCore`: pure Swift, no Foundation or UIKit (it should compile to WebAssembly later). Layouts per device class, `KeyGrid` (key frames and hit testing), `TypingEngine` (shift, caps lock, autocap, double-space period, smart punctuation, layer switching, word delete, autocorrect and reverts), `Corrector` (the decisions: what to correct, text replacements, names, learned words) behind the `CandidateSource` protocol. Fully unit tested.
- `Packages/HexKeyboard/Sources/KeyboardUI`: UIKit. `HexKeyboardViewController` (the extension's principal class), `KeyboardView` (one view owns all touches: rollover, slide-off, callouts, long-press accents, spacebar trackpad, iPad flicks), `KeyView`, `SuggestionBar`, `TextCheckerSource` (the `UITextChecker` + lexicon `CandidateSource`), `SettingsStore` and `MemoryStore` (App Group), metrics and theme.
- `Packages/HexKeyboard/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (see below).
- `Keyboard/`: the extension target, a one-line subclass.
- `App/`: the containing app (setup steps and a test field).
- `UITests/`: types through the real extension in the simulator.
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box; builds run on a Mac over ssh (`ssh mac`).

```sh
scripts/mac scripts/build                       # sync to the Mac, xcodegen, build for the simulator
scripts/mac scripts/test                        # KeyboardCore unit tests on an iOS simulator
scripts/mac scripts/uitest                      # type through the real extension (iPhone 17 by default)
scripts/mac 'scripts/sim all v7'                # screenshots: system vs Hex, light and dark, 8 devices
scripts/mac 'scripts/sim variants "iPhone 17" v7'  # return key types, keyboard types, landscape
scripts/mac 'scripts/capture "iPhone 17" iPhone-17 hex'  # frames of held keys: pop-ups, accent panel
scripts/mac 'scripts/shots "iPhone 17" iPhone-17 system light "hel:hel|helo:o"'  # type through a keyboard, screenshot each step
scripts/mac scripts/eval                        # autocorrect baseline: the phrase corpus typed with tap noise
uv run --with pillow --with numpy --with scipy scripts/shotdiff.py v7   # key-by-key geometry vs Apple
```

`scripts/sim` creates its own `hexkb …` simulators and enables the extension by writing `AppleKeyboards` (and, for iPad, `AppleKeyboardsExpanded = 1`) into the simulator's global preferences, so no Settings UI is needed. Simulators boot headless; the Simulator app never opens. Reference screenshots of Apple's keyboard come from the same simulators with `KEYBOARDS=system`.

Builds are ad-hoc signed for the simulator (`CODE_SIGN_IDENTITY = -`), which embeds simulated entitlements, so the App Group works in the simulator without a team. Device builds need a team with the group `group.com.shahidy.hexkeyboard` registered.

`scripts/eval` types the MacKenzie & Soukoreff phrase set (500 phrases, 2,714 words) through `TypingEngine` with taps drawn from a Gaussian around the real key centers (`KeyGrid`, iPhone 17 width), seeded, and prints word accuracy without and with autocorrect and the top-3 suggestion hit rate at several noise levels. Any new corrector must beat its numbers in `PROGRESS.md`.

## Rules

- Match the system keyboard to the pixel. Measure against reference screenshots in the same simulator (`shots/`), don't eyeball.
- Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The only timers are the inherent ones: key repeat and long-press.
- No comments unless they record a non-obvious fact.
- Keycaps use SF Compact, loaded from the system font file, because that is what the system keyboard uses (verified by glyph metrics) and UIKit has no public name for it. It falls back to SF Pro.
- iOS 26 ignores a plain height constraint on the input view; the height comes from Auto Layout content (`keyboardHeightConstraint`).
- Third-party keyboards get a system bottom bar (globe, mic) on Face ID iPhones and a system undo/redo/paste bar on iPad. Metrics are calibrated so the keys land where Apple's do with those bars in place.
- A third-party keyboard can't draw above its own area, so top-row pop-ups are clamped into the 27pt strip above the keys. The host draws 16pt of backdrop above that strip, so the suggestion bar lives in the 27pt strip: Apple's 38pt pill becomes 27pt and the text sits ~5pt lower than Apple's, but the keyboard height and keys stay identical.
- On iPad the system's own shortcut bar (undo, redo, paste) sits above a third-party keyboard and its middle can't be used, so Hex adds a 36pt suggestion row there when Predictive Text is on.
- `KeyboardCore` takes no Foundation or UIKit import. Platform services (UITextChecker, UILexicon, files) live in `KeyboardUI` behind Core protocols.
