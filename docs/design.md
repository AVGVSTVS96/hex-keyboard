# Design

Hex's look follows the Raycast keyboard for iOS (October 2026): one bar of suggestions with the mic at its end, a row of tool pills under it, and big flat keys, with no AI tools. This file is the spec: every size is in points, every color is sRGB hex. The Paper file "hex keyboard · Raycast" (`01M66Y7ME0SWEVV7YJM62FBE02`) draws each frame from the same numbers.

Where this file and a Paper frame disagree, this file wins.

## The main layout

```
┌──────────────────────────────────────────┐  ← system card (iOS draws it)
│  the   │  noon  │   ☕            (mic)  │  bar, 40
│                                          │  8
│ (  🙂  )   (  GIF  )   (  clipboard  )   │  pills, 40
│                                          │  11, the dead gap
│ q  w  e  r  t  y  u  i  o  p             │
│  a  s  d  f  g  h  j  k  l               │  keys: 4 rows
│ ⇧   z  x  c  v  b  n  m   ⌫              │
│ 123  🌐  [        space       ]  return  │
└──────────────────────────────────────────┘
```

From top to bottom: 8 of padding, the bar (40), 8, the pill row (40), 11, four rows of keys, the bottom inset.

### Keys

- Ten columns. Pitch = (keys block width − 2 × 6.5 + 6) / 10, so on the Duo's 466pt cover a letter key is 39.9 wide and its pitch is 45.9, the same as Apple's (Raycast's are 37.9 with 14pt side margins; Hex keeps Apple's wider keys).
- Side inset 6.5, gap between keys 6, gap between rows 11 (9 and 7 in the compact layouts, below).
- Corner radius 9 on every key and every size (Apple 8, Raycast ~8.5).
- Row 2 is centered (a half pitch in on each side). Row 3: shift and delete are 1.3 pitch − 6 wide at the edges; z to m are centered between them.
- Bottom row: `123` and the globe are 1.12 pitch − 6 wide, return is 2.3 pitch − 6, space takes the rest. The globe shows only when `needsInputModeSwitchKey` is true. It is true on the Duo (Touch ID, no system globe bar), so the Duo's row is `123 · globe · space · return`; Face ID iPhones get `123 · space · return`, because iOS puts the globe in the bar under the keyboard.
- The emoji key leaves the bottom row: emoji live in the pill row, with GIFs and the clipboard, so every panel opens from one place and the bottom row only types.
- Space is blank (no "hex" label).
- Return shows the `return.left` glyph. For go, search, send, join, route, done and next it turns into the prominent key: accent fill, white label (`go`, `search`, `send`, …), semibold 17.
- All keys share one fill; letter and function keys look the same, as in Raycast and in iOS 27.

### Type and glyphs

- Letters: SF Compact (see AGENTS.md: loaded from the system font file), Regular 23, lowercase until shift. The design draws Inter as a stand-in because Paper has no SF.
- `123` and key words (`go`, `search`): SF Pro 17, Regular (Semibold on the prominent return).
- Suggestions: SF Pro 17. The middle slot is Medium in the label color; the side slots are Regular in the secondary color. An emoji suggestion is 24.
- Glyphs, SF Symbols at 22 unless said: `shift` / `shift.fill` / `capslock.fill`, `delete.left` (24), `globe`, `return.left` (24), `face.smiling`, `list.clipboard`, `waveform` (20, on the mic). GIF has no symbol: draw a rounded rect 18.4 × 14.4, radius 3.6, 1.7 stroke, with "GIF" in SF Pro Heavy 8 inside it.

### The bar

- 40 tall. Three suggestion slots of equal width share what the mic leaves, divided by 1pt lines 28 tall.
- The mic is a 38 circle at the bar's right end, in line with the keys' right edge. Dark: white circle, black glyph. Light: black circle, white glyph. It is always there.
- The last slot gives way to the word's emoji when it has one (as today: `EmojiCatalog`; none beats a wrong one).
- What the slots hold and what a tap does doesn't change (`SuggestionBar`, Apple's three suggestions, a quoted middle when it will autocorrect).

### The pill row

- Three pills of equal width, 40 tall, fully rounded (radius 20), 8 apart, spanning the keys block. Fill is the key fill; in light mode they get the keys' 1pt shadow.
- Left to right: Emoji (`face.smiling`), GIF, Clipboard (`list.clipboard`). Icons only, 22, in the label color. Each opens its panel (section "Panels").
- Nothing AI goes here. Snippets, if they come, take a fourth pill.

### Where taps land

Bassim reaches for the top row fast, so a reach must never pick a suggestion or open a panel.

- The bar takes taps in its full 40.
- The 8 between bar and pills goes nowhere.
- A pill takes taps in its top 34; its bottom 6 goes nowhere.
- The 11 between pills and keys: its bottom 5 belongs to the top key row (as today's `KeyGrid` gives the top row the space above it); its top 6 goes nowhere.
- Gaps between keys still take taps (`KeyboardInputView`'s invisible fill).
- Callouts of top-row keys may draw over the pill row; they no longer need clamping into a thin strip.

### The mic

Behavior is what `MicButton` does today; only its look changes.

| State | Look |
|---|---|
| Microphone off (the app isn't holding it) | Circle with the `waveform` glyph. Tap opens the app to dictate. |
| Microphone kept on (Keep Mic On) | Same circle, plus a 6pt green (`#30D158`) dot at its top right. Tap starts dictating in place. |
| Recording | The three suggestion slots become one live waveform in the label color (bars 3 wide, 3 apart, heights from the published level) with the elapsed time `0:07` at its left in secondary 15, tabular figures. The mic becomes a stop button: record-red circle, white `stop.fill` 14. Tap stops and inserts. Hold turns the microphone off, as today. |
| Transcribing (after stop, until the text lands) | Waveform freezes at 40% opacity; the stop button shows a 16pt spinner in white. |

### Colors

| Role | Dark | Light |
|---|---|---|
| Card (iOS draws it behind the keyboard; Hex draws nothing there) | `#222223` | `#E2E3E8` |
| Key, pill | `#444444` | `#FFFFFF` |
| Key pressed | `#6B6B6B` | `#ABB0BA` |
| Key shadow | none | 0 1 0 `rgba(0,0,0,0.18)` |
| Label, glyphs | `#FFFFFF` | `#000000` |
| Secondary label (side suggestions) | `#A2A2A2` | `#4A4A4C` |
| Divider | `#3A3A3C` | `#C8C9CE` |
| Mic circle / glyph | `#FFFFFF` / `#000000` | `#000000` / `#FFFFFF` |
| Accent (prominent return, cursor, selected tab) | `#0A84FF` | `#007AFF` |
| Record (stop, recording) | `#FF453A` | `#FF3B30` |
| Search field | `#333335` | `#FFFFFF` |

The key, pressed and label colors are today's iOS 27 theme (`KeyboardTheme`); pills and the mic are new.

### Per device

| | Keys block | Key h | Row gap | Top | Bar | Pills | Pills → keys | Bottom | Total |
|---|---|---|---|---|---|---|---|---|---|
| Duo folded (cover), upright, 466 × 678 | 6.5 in, keys 6 apart | 45 | 11 | 8 | 40 | 8 + 40 | 11 | 39 | |
| Duo open, upright, 951 × 669 (compact) | 9 in, keys 10 apart | 38.67 | 13 | 8 | 40 | none | 11 | 20 | |
| Duo open, on its side, 669 × 951 | 18 in, keys 9 apart | 45.67 | 14 | 8 | 40 | 8 + 40 | 11 | 73 | |
| Duo folded, on its side, 678 × 466 (compact) | 4.5 in, keys 7 apart | 33.33 | 9 | 4 | 34 | none | 8 | 20 | |
| iPhone portrait (Face ID), 375–440 wide | full width | 43, or 45 from 415 wide | 11 | 8 | 40 | 8 + 40 | 11 | today's `bottomInset` | today's + 51 |
| iPhone landscape (compact) | today's | today's 27.33 | today's 8 | 4 | 34 | none | 8 | today's | |
| iPad (all) | today's | today's | today's | today's | today's 36pt row, compact bar | none | today's | today's | today's |

- Every Duo row is Apple's keyboard measured in the iOS 27.1 simulator (`scripts/sim duo`, which unfolds it with Device Hub's hinge event). "Keys block" is the side inset inside the keyboard's own width, which iOS narrows on the side layouts; "Bottom" is how far above the screen's bottom Apple's last row ends.
- The open Duo is wide when you hold it upright (951 × 669) and tall on its side (669 × 951).
- Apple's letters on the Duo are bigger than on other iPhones: 25.5 on the cover, 23.5 folded on its side, 28.5 open and upright, 28 open on its side. Hex's `123`, return and symbols grow by the same share; Apple's own `123` is bigger still, but its key is three times as wide, since its row has no globe.
- The Duo's keys span the keyboard's whole width on every screen, at Apple's insets.
- Regular iPhones and iPads keep today's key geometry, which is measured against Apple's. Only the bar, the pill row and the colors above change, so nothing that types today moves.

### The compact layout

Where height is short (any landscape, and iPad), there's no pill row: the three tools sit in the bar's left end as 36 × 36 (34 on the folded landscape) icon buttons, 2 apart, before the suggestions. Same icons, same panels. The bar spans the keys block. The mic is 34 (32 on the folded landscape). With no pill row, the bar's bottom 6 goes nowhere, as today.

### Cut from Raycast

- The 2×2 grid button at the bar's left (Raycast's commands): Hex has no commands, so the suggestions get its width.
- Quick Fix, Ask AI and AI commands.
- The emoji key in the bottom row (moved to the pill row).

### States

- Pressed key: the pressed fill, plus today's callout above letter keys. Function keys and pills show only the pressed fill.
- Shift: `shift` off, `shift.fill` on, `capslock.fill` locked. Letters show uppercase while shift is on.
- The number and symbol layers keep today's keys (`PhoneLayouts`) in this look; `123` reads `ABC` there.
- Holding `123` still offers the one-handed layouts, as today.

## Panels

Emoji, GIF and Clipboard open from their pills (or, in the compact layout, the bar's icons). A panel replaces the bar and the pill row with a results area and a search field; the keys stay where they are and type into the field, not into the app.

```
┌──────────────────────────────────────────┐
│ ☕ 😂 ❤️ 👍 🙏 🔥 😭 🥺 ✨ 🎉           │  results, 136
│ 😀 😃 😄 😁 😆 😅 🤣 😊 😇 🙂           │
│ 🙃 😉 😌 😍 🥰 😘 😗 😙 😚 😋           │
│                                          │  6
│ ‹  ( 🔍 Search emoji                  )  │  search row, 40
│                                          │  11
│ q  w  e  r  t  y  u  i  o  p             │  the same keys
```

### Shared

- Top to bottom: 8, results 136, 6, the search row 40, 11, the keys, the bottom inset. On the Duo cover the keyboard grows from 359 to 453 while a panel is open (Raycast's grows about as much).
- Search row: a 36-wide back button (`chevron.left` 22, label color), 4, then the field: fully rounded (radius 20), search-field fill (light mode adds the keys' shadow), 14 in on the left and 12 on the right, a leading glyph (secondary, 17–20), text SF Pro 17 (placeholder in secondary), the accent cursor, and trailing buttons.
- With text in the field, a clear button sits at its right end: a 20 secondary circle with a field-colored `xmark` 11. It empties the field.
- What the keys do in a panel: letters, numbers, space and shift type into the field. Delete deletes in the field; with the field empty, it deletes before the app's cursor, so a wrong insert can be fixed without leaving the panel. Return and the back button close the panel. The globe works as everywhere.
- Every keystroke searches at once: the newest query cancels any search still running, and results only ever show for the text in the field. No debounce timer (AGENTS.md: no timers).
- A panel stays open after you insert something, so you can add several. It closes with back, return, or when the keyboard goes away; the keyboard always comes back on the main layout.
- The bar's suggestions and the mic hide while a panel is open.
- Compact layout: results 46 tall (one row), the search row 34, the gaps as in the main compact layout.

### Emoji

- Works without Full Access.
- Results: 10 columns across the keys block (45.3 each on the Duo cover), rows 45.3 tall (three show), emoji 30 (26 in compact). Rows fill left to right; the results scroll up and down.
- Empty field: your recent emoji first (the ones you picked here and from the bar, as `EmojiHistory` weighs them, up to 30), then every emoji in Apple's order. No category tabs: search is faster than tabs.
- Typing: matches by CLDR name and keywords, best first, ranked by what you use and then by Unicode's emoji frequency. This search existed (commit 416f351, removed in 00edb44 with `EmojiKeyboardView`): bring it back from history rather than rewrite it. Placeholder: "Search emoji".
- Tap: inserts the emoji at the app's cursor and counts it as used. Hold an emoji with skin tones: a callout of the tones above it, like a key's accents; the pick is remembered for that emoji.
- No results: the results area says "No emoji for "query"" in secondary 15, centered.

### GIF

- Needs Full Access (it goes online). Without it, the results area says "GIF search needs Full Access." in secondary 15 with a "Turn On" button (accent text) that opens Hex's app where it explains how.
- Source: KLIPY's API, its key in `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/klipy.key`, kept out of git like `Config/Team.xcconfig`. With no key built in, the GIF pill doesn't show. KLIPY over GIPHY (what Raycast uses): both give a new key 100 requests an hour, but KLIPY's production keys are free and unlimited, where GIPHY reviews each app and discusses pricing; GIPHY forbids keeping anything it sends, even a GIF's URL, where KLIPY lets an app keep slugs and fetch them again (`gifs/items`), which recents need. KLIPY requires the placeholder "Search KLIPY", loading its media straight from its URLs, and showing its results in its order.
- Field: leading GIF glyph (20, secondary), placeholder "Search KLIPY", trailing `clock` (20, secondary) that switches the results to your recent GIFs; it turns accent while on. Raycast's GIF token chip is cut: the panel only searches GIFs.
- Results: two rows 65 tall, 6 apart, scrolling sideways. Each GIF keeps its own aspect ratio at that height (no letterboxing, unlike Raycast), radius 8, the key fill while it loads.
- Empty field: KLIPY's trending GIFs.
- Searching: one request is out at a time. Keys typed while it's out don't each send one; when it returns, one search goes out for what the field holds then (`GifSearch`). That keeps a new key's 100 requests an hour from running out in a few searches, with no timer.
- Memory: a keyboard has a small memory limit. Load KLIPY's small WebP (`sm`), animate only the tiles on screen, and drop the rest.
- Tap: a keyboard can't put an image into the app's field (`UITextDocumentProxy` only types text; the image inserts UIKit has, `RTITextOperations`' and the sticker path, serve Apple's own keyboard), so Hex copies the GIF (KLIPY's `md` GIF, the format every app pastes) to the clipboard, as GIPHY's and Raycast's keyboards do (Raycast's manual: "tap a GIF to copy it and paste it into your message"), and the search row shows "Copied. Paste it, or hold a GIF to drag it in." in its place until your next touch.
- Hold: the GIF lifts out of the keyboard and drops into the app's field as the GIF itself, no paste (a system drag, which a keyboard may start; the app decides whether it takes images, as Messages does).
- A GIF tapped or dropped goes into recents by its slug (last 50, kept in the keyboard's own container), and KLIPY is told it was shared.

### Clipboard

- Needs Full Access (a keyboard can't read the clipboard without it) and Settings › Apps › Hex › Paste from Other Apps set to Allow. iOS counts a keyboard's reads as its app's, even inside another app; at Ask (the default) it refuses them silently, since the prompt it means to show never appears over a keyboard, and at Allow it lets them through without asking (iOS 27 simulator, from `pasted`'s log). The panel says which is missing, with a "Turn On" button that opens Hex's app.
- Hex keeps what you copy when it sees it: each time the keyboard appears and each time this panel opens, it checks the clipboard's `changeCount` and keeps a new item. Nothing runs in the background. A refused read isn't counted as seen, so turning Allow on catches up.
- Never kept: items marked concealed (`org.nspasteboard.ConcealedType`, which password managers set) and anything copied while a secure field was active.
- History: the last 50 items, newest first, an identical item moves to the top instead of repeating; pinned items stay above them and never age out. Kept in the keyboard's own container, never online.
- Results: rows 44 tall, 2 apart, three in view, scrolling up and down. Each row: a 16-wide slot with `pin.fill` (13, secondary) for pinned items, the text on one line in SF Pro 16 (images show a 32 thumbnail, radius 6), and at the right how long ago in secondary 13 (`now`, `5m`, `3h`, `2d`). iOS never tells a keyboard which app copied something (`UIPasteboard` has no such property), so a row can't say where it came from.
- Field: leading clipboard glyph, placeholder "Search clipboard"; typing filters by substring.
- Tap: inserts the text at the cursor (an image is copied back to the clipboard, as GIFs are). Hold: Pin or Unpin, Delete.
- Compact: one row of up to three cards, the key fill, radius 10, the text in 14 over its age in 11.
- Empty: "Things you copy show up here." in secondary 15.

## The app

The app wears the keyboard's colors, so it looks like the keys it sets up: the backdrop iOS draws behind the keyboard (`#222223` dark, `#E2E3E8` light) behind every screen, and the key fill (`#444444`, white with the keys' 1pt shadow) on every card and list row. Rows carry Settings' colored glyphs (a white SF Symbol on a 30pt rounded square).

- **Hex** (home): the app's mark, "Hex" and whether the keyboard is on (green dot, "On, with Full Access"; orange with a Turn On button until it's added). Then "Try It", a field in a card; two tiles, what you dictated today with the voice model's state (opens Transcripts) and how many taps Hex learned your aim from (opens Your Taps); "Set Up", the three switches iOS keeps (Add Hex, Allow Full Access, Paste from Other Apps), each checked when Hex can tell, opening Settings; and Keyboard Settings. At most 680 wide, centered, so the open Duo reads like the cover.
- **Keyboard Settings**, **Transcripts** and **Your Taps** keep their content in the same colors.
- Full Access is known on once the keyboard has opened with it (`SettingsStore.fullAccessSeen`); a keyboard can't write to the App Group without it, so turning it off later goes unseen.

## Out of this design

Swipe typing, themes, snippets and quicklinks are later phases. Nothing here uses AI.
