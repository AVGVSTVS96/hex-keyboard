# Split keyboard

## Sub-features

On the open Duo held wide, the keys in two halves at the sides, as Apple's keyboard splits from its … menu, in letters, 123 and #+=. Full puts them back. The pick is kept as a setting (`KeyboardSettings.split`) and only applies while the Duo is open and wider than tall.

## How to get to it (user POV)

Open the Duo and hold it wide, then hold `123` or tap the bar's … menu and pick Split (or Full). Or Hex app › Settings › Keyboard › Layout › Split Keyboard.

## Driving it

`SplitTests` (package) checks the halves against Apple's split, measured by `AppleSplitShots` (UI, `HEX_SPLIT_SHOTS=<prefix>` with Apple's keyboard in use), and that holding 123 or the … menu offers Full, Split and Hex Settings.
