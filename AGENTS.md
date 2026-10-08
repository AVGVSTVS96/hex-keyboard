# Hex Keyboard

An iOS custom keyboard (UIKit, Swift 6, iOS 26+) that looks and types like Apple's. MIT.

## Layout

- `Packages/HexKeyboard/Sources/KeyboardCore`: pure logic, no UIKit. Layouts per device class, `TypingEngine` (shift, caps lock, autocap, double-space period, layer switching, word delete). Fully unit tested.
- `Packages/HexKeyboard/Sources/KeyboardUI`: UIKit. `HexKeyboardViewController` (the extension's principal class), `KeyboardView` (one view owns all touches: rollover, slide-off, callouts, long-press accents, spacebar trackpad, iPad flicks), `KeyView`, metrics and theme.
- `Keyboard/`: the extension target, a one-line subclass.
- `App/`: the containing app (setup steps and a test field).
- `UITests/`: types through the real extension in the simulator.
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, never committed.

## Build and test

Development happens on a Linux box; builds run on a Mac over ssh (`ssh mac`).

```sh
scripts/mac scripts/build                 # sync to the Mac, xcodegen, build for the simulator
scripts/mac scripts/test                  # KeyboardCore unit tests on an iOS simulator
scripts/mac 'scripts/sim all v3'          # screenshots: system vs Hex keyboard, light and dark, 8 devices
```

`scripts/sim` creates its own `hexkb …` simulators and enables the extension by writing `AppleKeyboards` into the simulator's global preferences, so no Settings UI is needed. Simulators boot headless; the Simulator app never opens.

## Rules

- Match the system keyboard to the pixel. Measure against reference screenshots in the same simulator (`shots/`), don't eyeball.
- Behavior follows real events (touches, `textDidChange`, `selectionDidChange`). The only timers are the inherent ones: key repeat and long-press.
- No comments unless they record a non-obvious fact.
- Keycaps use SF Compact, loaded from the system font file, because that is what the system keyboard uses (verified by glyph metrics) and UIKit has no public name for it. It falls back to SF Pro.
- iOS 26 ignores a plain height constraint on the input view; the height comes from Auto Layout content (`keyboardHeightConstraint`).
