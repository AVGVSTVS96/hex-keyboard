# Settings

## Sub-features

The app's settings screen (styled like Settings › General › Keyboard), the same switches in Settings › Apps › Hex, and Reset Keyboard Dictionary.

## How to get to it (user POV)

Hex app › Settings, or Settings › Apps › Hex.

## Driving it with XCUITest

`UITests/SettingsAppTests.swift` flips a switch in the Settings app and reads it in Hex; `SuggestionTests.testAutoCorrectionSettingIsSharedWithTheKeyboard` checks the keyboard follows it. `-HexResetSettings YES` clears settings and the learned memory at launch.

## Gotchas

The keyboard reads settings in `viewWillAppear`, so a test must reopen the keyboard after changing one.
