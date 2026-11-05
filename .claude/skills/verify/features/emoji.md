# Emoji: the bar and the emoji panel

## Sub-features

The word being typed, or the one just typed, offers its emoji in the bar, left of the mic: in the last slot, or beside the three suggestions where the bar has room (the open Duo), as many as fit and the rest a swipe left away. They're the emoji picked by hand for that word in `emoji.txt`, or for its singular, where a word can list none, then every emoji whose name or keywords hold the word; what you picked before comes first. A tap replaces the word, or after a space follows it.

The emoji key beside space (on iPad, the bar's emoji tool) opens the emoji panel in place of the bar: ten columns of emoji, your picks first, then every emoji in Apple's order. The keys type into its search ("Search emoji"), which finds emoji by CLDR name and keyword; delete with the search empty deletes in the app; return or back closes it. A tap types the emoji into the app and leaves the panel open; holding one with skin tones offers them, and the pick is remembered.

## How to get to it (user POV)

Type "pizza" in any text field with iikb up; or tap the emoji key between 123 and space. Settings › Keyboard › Layout › Emoji Key takes the key away, leaving the bar's emoji.

## Driving it with XCUITest

`VoiceTests` types "pizza" and checks 🍕 sits left of the mic. `PanelTests` (UI, `scripts/looktest`) opens the panel from the emoji key, types "pizza" into the search, taps 🍕 into the app and goes back, screenshotting each step. `EmojiTests` and `PanelTests` (package) pin the bar's matches, the search's ranking, skin tones, and what the keys do while a panel is open.
