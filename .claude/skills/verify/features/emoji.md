# Emoji keyboard

## Sub-features

Opening it (hold 123, let go on the smiley, which is already picked), Frequently Used (refreshed each time it opens, so nothing moves under your finger), the categories and their bar, skin tones under a held emoji (the one you pick sticks), delete with its speed-up, ABC back to the letters.

## How to get to it (user POV)

In any text field with Hex up, hold 123 and let go.

## Driving it with XCUITest

`UITests/OneHandedTests.testHoldingNumbersAndLettingGoOpensEmojiAndABCComesBack` opens it, types an emoji, deletes it, jumps to Flags and goes back to the letters. `EmojiTests` (package) pins the catalog, Frequently Used, tones and what the engine types. `scripts/emojishots "<device>" <type> hex|emoji light|dark` screenshots Hex's or Apple's emoji keyboard opened, scrolled and on Food & Drink.

## Gotchas

Apple's emoji button sits in the system's bottom bar, outside the app's accessibility tree, so `EmojiShots` taps it by position. iOS 26 scroll views blur their edges; the grid turns that off.
