# Typing

## Sub-features

Autocapitalization (off until you turn it on in Settings › Keyboard › Typing), double-space period, shift and double-tap caps lock, holding shift, `123` and `#+=` layers, sliding from a layer key to type one symbol and come back, delete and its speed-up to words, return, the space bar trackpad (along a line and up and down lines), long-press accents, iPad flick-down secondaries, smart punctuation, the one-handed keyboard (hold 123, the chevron), the 123 menu (hold 123: left, both and right hands in one row, the current one above the key, then Split on the open Duo held wide, Next Keyboard where iOS asks for one, and iikb Settings).

## How to get to it (user POV)

Open the iikb app, tap the text field, and iikb is the keyboard.

## Driving it with XCUITest

`UITests/TypingTests.swift` launches the app with `-iikbFocus YES`, finds keys by accessibility identifier (`iikb.q`, `iikb.space`, `iikb.delete`, `iikb.numbers`, …) and reads the field's value. `scripts/mac scripts/uitest` runs it. Engine-level behavior (what each `KeyboardEvent` does) is pinned in `TypingEngineTests`. `UITests/OneHandedTests.swift` holds 123, picks each hand and taps the chevron (`iikb.expand`); `-iikbOneHanded left|right|off` sets the hand at launch for screenshots. `CAPTURE=menu scripts/capture` grabs frames of the open menu.

## Gotchas

Flicks exist only on iPad, so `testFlickDownTypesSecondaryOnPad` skips on iPhone. Run the iPad simulator to cover it.
