# Emoji in the suggestion bar

## Sub-features

The word being typed, or the one just typed, offers its emoji in the bar's last slot, left of the mic: matched on each emoji's CLDR name and keywords and their plurals, ranked by what you picked from the bar before, then by Unicode's emoji frequency. A tap replaces the word, or after a space follows it. Hex has no emoji keyboard: the globe reaches Apple's, straight away when Hex and Emoji are the only keyboards.

## How to get to it (user POV)

Type "pizza" in any text field with Hex up.

## Driving it with XCUITest

`VoiceTests` types "pizza" and checks 🍕 sits left of the mic. `EmojiTests` (package) pins the bar's matches, plurals, what you picked first, and what the engine types.
