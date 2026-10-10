# Hex Keyboard

An open-source iOS keyboard that looks, feels and types like Apple's, built to grow into the front end for hex, a personal agent.

MIT licensed. UIKit, Swift 6, iOS 26 and later, iPhone and iPad.

Apple's keyboard on the left, Hex on the right, same simulator, iOS 26.3:

![iPhone 17, light and dark](docs/iphone.png)

![iPad Pro 11-inch, light and dark](docs/ipad.png)

## What it does today

- Apple's iOS 26 layouts, measured against the system keyboard in the same simulator: iPhone, iPad mini, 11" and 13" iPads (with tab, caps lock, both shifts and number row), light and dark.
- Keycaps in SF Compact, the face the system keyboard uses, at the same size and position.
- Key pop-ups on iPhone, long-press accents, slide-off typing, multi-touch rollover.
- Shift, double-tap caps lock, hold shift to type capitals, auto-capitalization, double-space period.
- `123` and `#+=` layers; press `123` and slide to a symbol to type it and come back.
- Delete repeats on hold and speeds up to whole words.
- Hold the space bar to move the cursor.
- iPad flick-down for the gray secondary characters.
- Return key follows the field's `returnKeyType`; email, URL and search fields get their own bottom rows.
- Globe key only when iOS asks for one (`needsInputModeSwitchKey`).
- Landscape iPhone and wide (foldable-size) phones, which get the iPad mini layout.
- Suggestion bar drawn like iOS 26/27's: the literal “word” in quotes, the pending autocorrection in a pill, light and dark.
- Learns your thumbs: every key's touch spot is a personal 2D Gaussian, updated from the words you keep and from backspace-and-retype, with no settings and nothing to tune. Taps are hit-tested against it and against which letter is likely next, so keys grow and shrink invisibly like Apple's (never past a quarter key).
- Its own autocorrect: a 138k-word English lexicon (American, British and Canadian spellings) with frequencies (2.4 MB, SCOWL words and Google Books counts, see `Packages/HexKeyboard/Sources/KeyboardUI/Resources/LEXICON-LICENSE`), decoded against your taps and the words you use. It fixes slips, swaps, missed keys, skipped apostrophes and a space tapped instead of a letter ("a out" → "about", "jo." → "job"). A real word you typed is only changed when your touches themselves fit the other word better, never just because the other word is more common. Backspace right after a correction offers the original back, and reverted words are never corrected again. Your Text Replacements and contacts (`requestSupplementaryLexicon`) still apply. Fields that turn autocorrection off, and URL, email and number fields, are left alone.
- Smart Punctuation (curly quotes, em dashes), since host apps don't convert a third-party keyboard's input.
- A settings screen in the app, styled like Settings › General › Keyboard and shared with the keyboard through an App Group.
- No network, no Full Access.

## Build

Requires Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open HexKeyboard.xcodeproj
```

Run the `Hex` scheme, then add the keyboard in Settings › General › Keyboard › Keyboards › Add New Keyboard… › Hex.

Tests:

```sh
cd Packages/HexKeyboard
xcodebuild test -scheme HexKeyboard-Package -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Structure

| Path | What |
| --- | --- |
| `Packages/HexKeyboard/Sources/KeyboardCore` | Layouts, typing and autocorrect logic. Pure Swift, no Foundation or UIKit, fully unit tested. |
| `Packages/HexKeyboard/Sources/KeyboardUI` | The keyboard view controller, key views, metrics and theme. |
| `Keyboard/` | The keyboard extension. |
| `App/` | The containing app: setup steps, a test field and the keyboard settings. |
| `UITests/` | End-to-end typing through the real extension. |

## License

MIT. See [LICENSE](LICENSE).
