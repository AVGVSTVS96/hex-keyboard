# Hex Keyboard

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that looks and types like Apple's. MIT.

## Layout

- `Packages/HexKeyboard/Sources/KeyboardCore`: pure Swift, no Foundation or UIKit (it should compile to WebAssembly later). Layouts per device class, `KeyGrid` (key frames and hit testing), `TypingEngine` (shift, caps lock, autocap, double-space period, smart punctuation, layer switching, word delete, autocorrect and reverts, and the tap labels it learns from), `Corrector` (the decisions: hit-testing, what to correct, text replacements, names, learned words) over a `CandidateSource`. With a `Lexicon` (a flat byte trie of words and frequencies) as its source it decodes taps (`Decoder`, exact A* over the trie) against your `TouchModel` (each key a 2D Gaussian with a conjugate Normal-Inverse-Wishart prior) and a `LanguageModel` (Witten-Bell over your next-word counts, your words and the lexicon). `TypingMemory` holds everything learned and is `Codable`. Fully unit tested.
- `Packages/HexKeyboard/Sources/KeyboardUI`: UIKit. `HexKeyboardViewController` (the extension's principal class), `KeyboardView` (one view owns all touches: rollover, slide-off, callouts, long-press accents, spacebar trackpad, iPad flicks), `KeyView`, `SuggestionBar`, `Lexicon.english` (`Resources/en.lexicon`, built by `scripts/lexicon`, sources and licenses in `Resources/LEXICON-LICENSE`), `TextCheckerSource` (the old `UITextChecker` source, kept as the scorer's baseline), `SettingsStore` (App Group) and `MemoryStore` (the extension's own container; the app resets it through a counter in the App Group), metrics and theme.
- `Packages/HexKeyboard/Tools/LexiconBuilder`: turns `scripts/lexicon.py`'s word counts into `en.lexicon` with `Lexicon(counts:)`, so the format has one implementation.
- `Packages/HexKeyboard/Tests/KeyboardUITests`: `Evaluation`, the autocorrect scorer (see below).
- `web/`: the web demo. `Sources/HexWeb` exports a `Keyboard` class to JavaScript (JavaScriptKit BridgeJS) that wraps `TypingEngine` the way `HexKeyboardViewController` does, against the page's text field; `site/` draws the keys from `KeyboardCore`'s metrics, faces and colors and ports `KeyboardView+Touches` to pointer events. Deployed to Vercel as `hex-keyboard`.
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
scripts/mac scripts/eval                        # scorer: the phrase corpus typed with tap noise and with biased thumbs
scripts/web                                     # web demo into web/dist (swift.org 6.4.0 toolchain + its Wasm SDK + binaryen; on the Mac: rsync, then run it there)
scripts/lexicon                                 # rebuild en.lexicon (downloads ~1 GB, streams ~30 GB of 2-grams)
uv run --with pillow --with numpy --with scipy scripts/shotdiff.py v7   # key-by-key geometry vs Apple
```

`scripts/sim` creates its own `hexkb …` simulators and enables the extension by writing `AppleKeyboards` (and, for iPad, `AppleKeyboardsExpanded = 1`) into the simulator's global preferences, so no Settings UI is needed. Simulators boot headless; the Simulator app never opens. Reference screenshots of Apple's keyboard come from the same simulators with `KEYBOARDS=system`.

Builds are ad-hoc signed for the simulator (`CODE_SIGN_IDENTITY = -`), which embeds simulated entitlements, so the App Group works in the simulator without a team. Device builds need a team with the group `group.com.shahidy.hexkeyboard` registered.

`scripts/eval` types the MacKenzie & Soukoreff phrase set (500 phrases, 2,714 words) through `TypingEngine` with taps drawn from a Gaussian around the real key centers (`KeyGrid`, iPhone 17 width), seeded, and prints word accuracy without and with autocorrect and the top-3 suggestion hit rate, for three keyboards: (a) nearest key + `UITextChecker`, (b) Hex's decoder with the touch model held at its prior, (c) the decoder learning. `noise` reruns the original noise levels; `biasedThumbs` types the corpus twice as a user whose m, b and o land off target and prints a learning curve. It runs a Release build (the decoder is slow in Debug). Any change must beat its numbers in `PROGRESS.md`.

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
- Learning comes only from real events: the letters of a word you kept once you move on (next word, keyboard hidden), a reverted correction teaches what you typed, and a backspace-then-retype within a quarter key labels the erased tap. Words you delete teach nothing. Nothing in the model has a rate, schedule or decay; every weight is a posterior or a count.
- `KeyboardCore` takes no Foundation or UIKit import. Platform services (UITextChecker, UILexicon, files) live in `KeyboardUI` behind Core protocols.
