# Emoji: the bar and the emoji panel

## Sub-features

The word being typed, or the one just typed, offers its emoji in the bar's last slot, left of the mic: the emoji picked by hand for that word in `emoji.txt`, or for its singular, where a word can list none; what you picked before comes first. A tap replaces the word, or after a space follows it.

The emoji pill (or, in the compact layout, the bar's emoji icon) opens the emoji panel in place of the bar and pills: ten columns of emoji, your picks first, then every emoji in Apple's order. The keys type into its search ("Search emoji"), which finds emoji by CLDR name and keyword; delete with the search empty deletes in the app; return or back closes it. A tap types the emoji into the app and leaves the panel open; holding one with skin tones offers them, and the pick is remembered.

## How to get to it (user POV)

Type "pizza" in any text field with Hex up; or tap the smiley pill under the bar.

## Driving it with XCUITest

`VoiceTests` types "pizza" and checks 🍕 sits left of the mic. `PanelTests` (UI, `scripts/looktest`) opens the panel from its pill, types "pizza" into the search, taps 🍕 into the app and goes back, screenshotting each step. `EmojiTests` and `PanelTests` (package) pin the bar's matches, the search's ranking, skin tones, and what the keys do while a panel is open.
