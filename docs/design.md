# Design

Hex's look follows the Raycast keyboard for iOS (October 2026): one bar of suggestions with the tools at its left and the mic at its end, and big flat keys, with no AI tools. This file is the spec: every size is in points, every color is sRGB hex. The Paper file "hex keyboard · Raycast" (`01M66Y7ME0SWEVV7YJM62FBE02`) draws each frame from the same numbers.

Where this file and a Paper frame disagree, this file wins.

## The main layout

```
┌──────────────────────────────────────────┐  ← system card (iOS draws it)
│ GIF  📋 │ the │ noon │ ☕ 🍵 →     (mic)  │  bar, 40
│                                          │  11, the dead gap
│ q  w  e  r  t  y  u  i  o  p             │
│  a  s  d  f  g  h  j  k  l               │  keys: 4 rows
│ ⇧   z  x  c  v  b  n  m   ⌫              │
│ 123  🌐  🙂 [      space      ]  return  │
└──────────────────────────────────────────┘
```

From top to bottom: 8 of padding, the bar (40), 11, four rows of keys, the bottom inset. The tools take no row of their own: Bassim would rather the space go to nothing than to a row of buttons, so on every screen they sit at the bar's left, as they did only where height was short.

### Keys

- Ten columns. Pitch = (keys block width − 2 × 6.5 + 6) / 10, so on the Duo's 466pt cover a letter key is 39.9 wide and its pitch is 45.9, the same as Apple's (Raycast's are 37.9 with 14pt side margins; Hex keeps Apple's wider keys).
- Side inset 6.5, gap between keys 6, gap between rows 11 (9 and 7 in the compact layouts, below).
- Corner radius 9 on every key and every size (Apple 8, Raycast ~8.5).
- Row 2 is centered (a half pitch in on each side). Row 3: shift and delete are 1.3 pitch − 6 wide at the edges; z to m are centered between them.
- Bottom row: `123` and the globe are 1.12 pitch − 6 wide, return is 2.3 pitch − 6, space takes the rest. The globe shows only when `needsInputModeSwitchKey` is true. It is true on the Duo (Touch ID, no system globe bar), so the Duo's row is `123 · globe · space · return`; Face ID iPhones get `123 · space · return`, because iOS puts the globe in the bar under the keyboard.
- The emoji key sits where Apple's does, after `123` (and the globe), half the width `123` would have alone; return gives up half a pitch to make room, and space takes the rest. Settings › Keys › Emoji Key takes it away, leaving the bar's emoji for the word as the way to emoji; on iPad, which has no room for it in the bottom row, the emoji tool sits in the bar instead.
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
- The last slot gives way to the word's emoji when it has some (`EmojiCatalog`; none beats a wrong one): the ones picked for the word, then every emoji whose name or keywords hold the word, up to 30, 36 apart. As many as fit show, centered when they all do; the rest are a swipe left away.
- What the slots hold and what a tap does doesn't change (`SuggestionBar`, Apple's three suggestions, a quoted middle when it will autocorrect).

### The tools

- GIF and Clipboard (and, on iPad with the emoji key on, Emoji) are 36 × 36 icon buttons (34 on the folded landscape) at the bar's left end, 2 apart, in the label color, before the suggestions. Each opens its panel (section "Panels").
- Nothing AI goes here.

### Where taps land

Bassim reaches for the top row fast, so a reach must never pick a suggestion or open a panel.

- The bar takes taps in its full 40.
- The bar's bottom 6 goes nowhere.
- The 11 between the bar and the keys belongs to the top key row (as `KeyGrid` gives the top row the space above it).
- Gaps between keys still take taps (`KeyboardInputView`'s invisible fill).
- Callouts of top-row keys draw over the bar.

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
| Key | `#444444` | `#FFFFFF` |
| Key pressed | `#6B6B6B` | `#ABB0BA` |
| Key shadow | none | 0 1 0 `rgba(0,0,0,0.18)` |
| Label, glyphs | `#FFFFFF` | `#000000` |
| Secondary label (side suggestions) | `#A2A2A2` | `#4A4A4C` |
| Divider | `#3A3A3C` | `#C8C9CE` |
| Mic circle / glyph | `#FFFFFF` / `#000000` | `#000000` / `#FFFFFF` |
| Accent (prominent return, cursor, selected tab) | `#0A84FF` | `#007AFF` |
| Record (stop, recording) | `#FF453A` | `#FF3B30` |
| Search field | `#333335` | `#FFFFFF` |

The key, pressed and label colors are the iOS 27 theme (`KeyboardTheme`); the mic is new.

### Per device

| | Keys block | Key h | Row gap | Top | Bar | Bar → keys | Bottom | Total |
|---|---|---|---|---|---|---|---|---|---|
| Duo folded (cover), upright, 466 × 678 | 6.5 in, keys 6 apart | 45 | 11 | 8 | 40 | 11 | 39 | |
| Duo open, upright, 951 × 669 (compact) | 9 in, keys 10 apart | 38.67 | 13 | 8 | 40 | 11 | 20 | |
| Duo open, on its side, 669 × 951 | 18 in, keys 9 apart | 45.67 | 14 | 8 | 40 | 11 | 73 | |
| Duo folded, on its side, 678 × 466 (compact) | 4.5 in, keys 7 apart | 33.33 | 9 | 4 | 34 | 8 | 20 | |
| iPhone portrait (Face ID), 375–440 wide | full width | 43, or 45 from 415 wide | 11 | 8 | 40 | 11 | today's `bottomInset` | |
| iPhone landscape (compact) | today's | today's 27.33 | today's 8 | 4 | 34 | 8 | today's | |
| iPad (all) | today's | today's | today's | today's | today's 36pt row, compact bar | today's | today's | today's |

- Every Duo row is Apple's keyboard measured in the iOS 27.1 simulator (`scripts/sim duo`, which unfolds it with Device Hub's hinge event). "Keys block" is the side inset inside the keyboard's own width, which iOS narrows on the side layouts; "Bottom" is how far above the screen's bottom Apple's last row ends.
- The open Duo is wide when you hold it upright (951 × 669) and tall on its side (669 × 951).
- Apple's letters on the Duo are bigger than on other iPhones: 25.5 on the cover, 23.5 folded on its side, 28.5 open and upright, 28 open on its side. Hex's `123`, return and symbols grow by the same share; Apple's own `123` is bigger still, but its key is three times as wide, since its row has no globe.
- The Duo's keys span the keyboard's whole width on every screen, at Apple's insets.
- Regular iPhones and iPads keep their key geometry, which is measured against Apple's.

### The compact layout

Where height is short (any landscape, and iPad), the bar is 34 (iPad 36) and the mic 34 (32 on the folded landscape), and a panel's results are one row (`Toolbar.isCompact`).

### Cut from Raycast

- The 2×2 grid button at the bar's left (Raycast's commands): Hex has no commands, so the suggestions get its width.
- Quick Fix, Ask AI and AI commands.

### States

- Pressed key: the pressed fill, plus today's callout above letter keys. Function keys and tools show only the pressed fill.
- Shift: `shift` off, `shift.fill` on, `capslock.fill` locked. Letters show uppercase while shift is on.
- The number and symbol layers keep today's keys (`PhoneLayouts`) in this look; `123` reads `ABC` there.
- Holding `123` still offers the one-handed layouts, as today.

## Panels

Emoji opens from its key, GIF and Clipboard from the bar's tools. A panel replaces the bar with a results area and a search field; the keys stay where they are and type into the field, not into the app.

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

- Top to bottom: 8, results 136, 6, the search row 40, 11, the keys, the bottom inset. On the Duo cover the keyboard grows from 311 to 453 while a panel is open.
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
- Source: KLIPY's API, its key in `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/klipy.key`, kept out of git like `Config/Team.xcconfig`. With no key built in, the GIF tool doesn't show. KLIPY over GIPHY (what Raycast uses): both give a new key 100 requests an hour, but KLIPY's production keys are free and unlimited, where GIPHY reviews each app and discusses pricing; GIPHY forbids keeping anything it sends, even a GIF's URL, where KLIPY lets an app keep slugs and fetch them again (`gifs/items`), which recents need. KLIPY requires the placeholder "Search KLIPY", loading its media straight from its URLs, and showing its results in its order.
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
- History: everything you copied, newest first, until you delete it; an identical item moves to the top instead of repeating; pinned items stay above the rest. The newest 200 show, and search reaches all of it. Kept in the keyboard's own container, never online; each keyboard reads the file before changing it, since iOS can run the keyboard in two apps at once and one would write over what the other kept.
- Results: rows 44 tall, 2 apart, three in view, scrolling up and down. Each row: a 16-wide slot with `pin.fill` (13, secondary) for pinned items, the text on one line in SF Pro 16 (images show a 32 thumbnail, radius 6), and at the right how long ago in secondary 13 (`now`, `5m`, `3h`, `2d`). iOS never tells a keyboard which app copied something (`UIPasteboard` has no such property), so a row can't say where it came from.
- Field: leading clipboard glyph, placeholder "Search clipboard"; typing filters by substring.
- Tap: inserts the text at the cursor (an image is copied back to the clipboard, as GIFs are). Hold: Pin or Unpin, Delete.
- Compact: one row of up to three cards, the key fill, radius 10, the text in 14 over its age in 11.
- Empty: "Things you copy show up here." in secondary 15.

## The app

The app takes its look from Raycast's iOS app (November 2026): a black page (`#000000` dark, `#F2F2F5` light), cards in `#1C1C1E` (white in light) with a 1pt hairline edge and a 22pt continuous corner, gray sentence-case headers above cards and gray footers under them, rows 56pt and taller split by inset hairlines, a radio mark at a choice's right (a gray ring, or a white circle with a black check), blue switches, and pills for a page's own tabs (the picked one a white capsule with black text). Titles are small, at the page's top left, as Raycast's are. Text is SF Pro in Dynamic Type styles.

Hex links against the iOS 27.1 SDK, so on the iPhone Duo iOS puts the status bar and the app's tab bar in the vertical bar at the screen's edge on every screen (AGENTS.md, `scripts/phone`). Five tabs: **Hex**, **Keyboard**, **Transcripts**, **Your Taps**, **More**.

Every page knows which of the Duo's screens it's on (`Arrangement`):

```
open, upright 951 × 669         open, on its side 669 × 951     cover 466 × 678
┌───────────┬────────────┬─┐    ┌──────────────────────┐        ┌───────────┬─┐
│ Keyboard  │ (Theme)Typ │ │    │ Keyboard             │        │ Keyboard  │ │
│ ┌───────┐ │ ┌────────┐ │⌂│    │ ┌──────────────────┐ │        │ ┌───────┐ │⌂│
│ │ q w e │ │ │Default○│ │⌨│    │ │   q w e r t y    │ │        │ │ q w e │ │⌨│
│ │ a s d │ │ │Clear  ○│ │…│    │ └──────────────────┘ │        │ └───────┘ │…│
│ └───────┘ │ │iOS 5  ●│ │ │    ├──────── hinge ───────┤        │(Theme)Typ │ │
│ Tap to try│ └────────┘ │ │    │ (Theme) Typing Keys  │        │ ┌───────┐ │ │
└───────────┴─hinge──────┴─┘    │ ┌──────────────────┐ │        │ │Default│ │ │
                                └──────────────────────┘        └───────────┴─┘
```

- Wider than tall (the open screen upright, the cover on its side): two panes side by side (`Panes`). On the open screen they meet at the window's middle, the hinge, 36 apart; on the cover, which has no hinge, the first takes the share its page asks for (0.42 for Keyboard, 0.44 for Hex).
- The open screen on its side: one pane above the hinge, one below.
- The cover upright: one column.

- **Hex**: the mark, "Hex" and whether the keyboard is on (green "On, with Full Access", yellow without it, orange "Not added yet" with Turn On); a field to try it (a `UITextView`, which the UI tests type into); Set Up, the three switches iOS keeps (Add Hex, Allow Full Access, Paste from Other Apps), each checked once the keyboard has seen it on, until all three are; and four tiles: words dictated today (opens Transcripts), taps learned (opens Your Taps), Theme and Voice Model (open those Keyboard pages). Wide, the header and field take the first pane, Set Up and the tiles the second, so the field stays above the keys.
- **Keyboard**: Raycast's Keyboard page. Hex drawn as it will look with these settings (`KeyboardPreviewView`) over "Tap to try", which swaps the drawing for a field so the real keyboard comes up; and pills for a page per subject:
  - **Theme**: Default, Clear, Physical, Mechanical, iOS 5, each with a line on how it looks; under the picked Physical or Mechanical, Automatic, Dark and Light, each as two keycaps.
  - **Typing**: Auto-Capitalization, Auto-Correction, Predictive Text; Smart Punctuation, Enable Caps Lock, "." Shortcut; where Text Replacements come from.
  - **Keys**: Number Row, Emoji Key; Character Preview (None, Detached, Attached, each drawn); the emoji's Skin Tone; One-Handed Keyboard (Off, Left, Right).
  - **Voice**: the voice model, each with a line on what it costs and, for the picked one, its download, getting ready, or why it failed with Try Again; Style, each with an example; Keep Mic On; Vocabulary.
  - **Sound & Haptics**: Key Haptic Feedback (Off, Soft, Standard), Sound, and Allow Full Access when Hex hasn't seen it.
- **Transcripts**: every dictation, newest first by day, under a search field and a card of words, time talking, pace and a two-week chart. Wide, the picked transcript (the newest until you pick) shows in the second pane; otherwise it opens on its own.
- **Your Taps**: the touch model drawn on the keyboard (Heat, Aim, Accuracy, as pills), four numbers in cards, a picked key's close-up, how your thumbs pull, and the most-missed keys. Wide, the map and the pull take the first pane and the rest the second. Each screen of the Duo learns apart, the layout menu beside the title names them (Folded, upright · Open, on its side), and the screen you're on shows first, drawn at its own size.
- **More**: Raycast's grid of tiles (three across on the open screen, two on the cover), each opening its page: **Sources** (Add Source and a tapped source open a form, name, https address and secure token, that says what's wrong before Save), **Vocabulary**, **Keyboard Access** (the three switches and Open Hex in Settings), **Privacy & Data** (what stays on the iPhone and what goes online; Reset Learned Words and Taps; Delete All Transcripts) and **About Hex**.
- Settings › Apps › Hex has the same pages for the keyboard's switches (Typing, Keys, Sound & Haptics, Voice Typing), and says the app also picks the voice model and adds sources.
- Full Access is known on once the keyboard has opened with it (`SettingsStore.fullAccessSeen`), and Paste from Other Apps once the keyboard has tried the clipboard (`SettingsStore.pasteAllowed`); a keyboard can't write to the App Group without Full Access, so turning either off later goes unseen.
- The dictation screen (opened by the keyboard's mic) is the record-red circle swelling with your voice over a readable-width hint; if it couldn't listen it says why, with Close.

## Out of this design

Swipe typing, themes, snippets and quicklinks are later phases. Nothing here uses AI.
