# Emoji keyboard

## Sub-features

Opening it (hold 123, let go on the smiley, which is already picked unless Settings › Hold 123 says Voice), Search Emoji (the field above the grid; tapping it puts the field and a row of results above the letter keys, which type into the search; a result types into the text and the search stays; ✕ clears it, the checkmark goes back to the grid), emoji in the suggestion bar (the word being typed, or the one just typed, offers its emoji in the last slot, also beside the mic; a tap replaces the word or follows it), Frequently Used (refreshed each time it opens, so nothing moves under your finger), the categories and their bar, skin tones under a held emoji (the one you pick sticks), delete with its speed-up, ABC back to the letters.

## How to get to it (user POV)

In any text field with Hex up, hold 123 and let go.

## Driving it with XCUITest

`UITests/OneHandedTests.testHoldingNumbersAndLettingGoOpensEmojiAndABCComesBack` opens it, types an emoji, deletes it, jumps to Flags and goes back to the letters. `UITests/EmojiSearchTests` searches "heart" and types results, and taps the bar's 🍕 and 🐶; `VoiceTests` checks the bar's emoji sit beside the mic. `EmojiTests` and `EmojiSearchTests` (package) pin the catalog, search ranking, the bar's matches, Frequently Used, tones and what the engine types. `scripts/emojishots "<device>" <type> hex|emoji light|dark` screenshots Hex's or Apple's emoji keyboard opened, scrolled, on Food & Drink and searching "heart", and Hex's bar emoji.

## Gotchas

Apple's emoji button sits in the system's bottom bar, outside the app's accessibility tree, so `EmojiShots` taps it by position. iOS 26 scroll views blur their edges; the grid turns that off.
