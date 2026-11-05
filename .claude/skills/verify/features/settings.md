# Settings

## Sub-features

The app's Settings tab, in Raycast's look (docs/design.md, "The app"): one list in three sections, Keyboard (Theme, Layout, Typing, Sound & Haptics, each over a preview of iikb to try), Voice Typing (Voice Model, Writing Style, Your Words, Keep Mic On) and iikb (Sources, Keyboard Access, Privacy & Data, About). Held wide on the open Duo the list and the picked page sit side by side. The keyboard's switches are also in Settings › Apps › iikb (Theme, Layout, Typing, Feedback, Voice Typing). Typing's switches keep Apple's names and defaults, except Auto-Capitalization and Auto-Correction, which start off (`KeyboardSettings.initial`). Privacy & Data has Reset Learned Words and Taps.

## How to get to it (user POV)

iikb app › Settings, or the keyboard's … menu › iikb Settings, or Settings › Apps › iikb. The iikb tab's cards open the settings reached for most.

## Driving it with XCUITest

`UITests/SettingsAppTests.swift` flips a switch in the Settings app and reads it in iikb; `SettingsAppTests.testKeepMicOnIsPickedInAppAndShownInSettings` picks a Keep Mic On value in iikb and finds it in Settings (screenshots with `TEST_RUNNER_IIKB_SHOTS=<folder>`); `SuggestionTests.testAutoCorrectionSettingIsSharedWithTheKeyboard` checks the keyboard follows it. `-iikbResetSettings YES` clears settings and the learned memory at launch; `-iikbSettings <page>` (theme, layout, typing, feedback, model, writing, words, mic, sources, access) opens a page, and `scripts/mac 'scripts/sim duoapp <tag>'` screenshots every page on the Duo's screens.

## Gotchas

The keyboard reads settings in `viewWillAppear`, so a test must reopen the keyboard after changing one.
