# Design

Hex's look follows the Raycast keyboard for iOS (October 2026): one bar of suggestions with the tools at its left and the mic at its end, and big flat keys, with no AI tools. This file is the spec: every size is in points, every color is sRGB hex. The Paper file "hex keyboard · Raycast" (`01M66Y7ME0SWEVV7YJM62FBE02`) draws each frame from the same numbers.

Where this file and a Paper frame disagree, this file wins.

## The main layout

```
┌──────────────────────────────────────────┐  ← system card (iOS draws it)
│ GIF  📋 │ the │ noon │ ☕ 🍵 →     (mic)  │  bar, 38: the mic's height
│                                          │  7, the dead gap
│ q  w  e  r  t  y  u  i  o  p             │
│  a  s  d  f  g  h  j  k  l               │  keys: 4 rows
│ ⇧   z  x  c  v  b  n  m   ⌫              │
│ 123  🙂  [        space        ]  return │
└──────────────────────────────────────────┘
```

From top to bottom: 3 of padding (iOS draws its backdrop 4 above the keyboard, so 7 show), the bar (38), 7, four rows of keys, the bottom inset. The mic has the same 7 above it, below it and beside it, and the keyboard is as tall as Apple's with its suggestions (Apple's is 49 to 53 above the keys on the Duo's four screens; Hex was 52 to 66). The tools take no row of their own: Bassim would rather the space go to nothing than to a row of buttons, so on every screen they sit at the bar's left, as they did only where height was short.

### Keys

- Ten columns. Pitch = (keys block width − 2 × 6.5 + 6) / 10, so on the Duo's 466pt cover a letter key is 39.9 wide and its pitch is 45.9, the same as Apple's (Raycast's are 37.9 with 14pt side margins; Hex keeps Apple's wider keys).
- Side inset 6.5, gap between keys 6, gap between rows 11 (9 and 7 in the compact layouts, below).
- Corners are Raycast's on every theme (Themes, below).
- Row 2 is centered (a half pitch in on each side). Row 3: shift and delete are 1.3 pitch − 6 wide at the edges; z to m are centered between them.
- Bottom row: `123` is 1.25 pitch − 6 wide (1 in landscape), as wide as the emoji key, as Bassim asked (Nov 3), return is 2.5 pitch − 6 (2 in landscape), space takes the rest. An iPhone's row has no globe, so `123 · emoji · space · return`: Bassim kept hitting it by accident. Where iOS wants a way to the next keyboard (`needsInputModeSwitchKey`, and always on the Duo, which has no system globe bar), the bar's More menu offers Next Keyboard above iikb Settings, as does holding `123`; App Review asks only for "a method for progressing to the next keyboard" (4.4.1). Face ID iPhones also have iOS's globe in the bar under the keyboard. iPad keeps its globe key.
- The emoji key sits where Apple's does, after `123`, 1.25 pitch − 6 wide (1 in landscape), wider than Raycast's because it's the one Bassim taps most, in every field, email, URL, X and search ones too. Beside it return is Raycast's 1.4 pitch − 6 (measured on the open Duo in portrait and landscape), and space takes the rest. Settings › Keyboard › Layout › Emoji Key takes it away, leaving the bar's emoji for the word as the way to emoji; on iPad, which has no room for it in the bottom row, the emoji tool sits in the bar instead.
- Space carries "hex" in its top trailing corner, in the theme's secondary label color at the key's secondary size, where Raycast's space is blank.
- Return shows the `return.left` glyph. For go, search, send, join, route, done and next it turns into the prominent key: accent fill, white label (`go`, `search`, `send`, …), semibold 17.
- All keys share one fill; letter and function keys look the same, as in Raycast and in iOS 27.

### Type and glyphs

- Letters: SF Compact (see AGENTS.md: loaded from the system font file), Regular 23, lowercase until shift. The design draws Inter as a stand-in because Paper has no SF.
- `123` and key words (`go`, `search`): SF Pro 17, Regular (Semibold on the prominent return).
- Suggestions: SF Pro 17. The middle slot is Medium in the label color; the side slots are Regular in the secondary color. An emoji suggestion is 24.
- Glyphs, SF Symbols at 22 unless said: `shift` / `shift.fill` / `capslock.fill`, `delete.left` (24), `globe`, `return.left` (24), `face.smiling`, `list.clipboard`, `waveform` (20, on the mic). GIF has no symbol: draw a rounded rect 18.4 × 14.4, radius 3.6, 1.7 stroke, with "GIF" in SF Pro Heavy 8 inside it.

### The bar

- The mic's height: 38, or 32 to 34 where height is short. Three suggestion slots of equal width share what the tools and the mic leave, 4 from each, divided by 1pt lines 28 tall.
- Where everything goes comes from one rule (`BarLayout`): the mic sits 7 from the top of the backdrop, 7 from the keys and 7 from the keyboard's side, or in line with the keys' right edge where they sit further in (landscape, the open Duo, one-handed). The tools mirror it at the left. So no screen can crowd the mic into the keyboard's corner, and `BarLayoutTests` checks it on every screen.
- The mic is a circle at the bar's right end. Dark: white circle, black glyph. Light: black circle, white glyph. It is always there.
- Where an iPhone's bar has room for three suggestions of 130 and two emoji more (the open Duo, and the folded Duo in landscape), the three are 130 wide from the bar's left and the word's emoji sit in the rest, as many as fit; with or without emoji the suggestions stay where they are, as Apple's never move while you type. Elsewhere the last slot gives way to the word's emoji when it has some (`EmojiCatalog`; none beats a wrong one): the ones picked for the word, then every emoji whose name or keywords hold the word, up to 30, 36 apart. As many as fit show, centered when they all do; the rest are a swipe left away.
- What the slots hold and what a tap does doesn't change (`SuggestionBar`, Apple's three suggestions, a quoted middle when it will autocorrect).

### The tools

- GIF and Clipboard (and, on iPad with the emoji key on, Emoji) are round cells the mic's size at the bar's left end, 4 apart, in the label color, before the suggestions. Each opens its panel (section "Panels").
- Nothing AI goes here.

### Where taps land

Bassim reaches for the top row fast, so a reach must never pick a suggestion or open a panel.

- The bar takes taps from its top.
- The 7 between the bar and the keys, and the bar's bottom 10 over it, belong to the top key row (as `KeyGrid` gives the top row the space above it), so a reach of 17 above the top row types the key reached for: it never picks a suggestion and never goes nowhere. With a panel open, the bottom 10 of its search row are the top row's the same way.
- Gaps between keys still take taps (`KeyboardInputView`'s invisible fill).
- Callouts of top-row keys draw over the bar.

### The mic

Behavior is what `MicButton` does today; only its look changes.

| State | Look |
|---|---|
| Microphone off (the app isn't holding it) | Circle with the `waveform` glyph. Tap opens the app to dictate. |
| Microphone kept on (Keep Mic On) | Same circle, plus a 6pt green (`#30D158`) dot at its top right. Tap starts dictating in place. |
| Recording | The three suggestion slots become one live waveform in the label color (bars 3 wide, 3 apart, heights from the published level) with the elapsed time `0:07` at its left in secondary 15, tabular figures. The mic becomes a stop button: record-red circle, white `stop.fill` 14. Tap stops and inserts. Hold turns the microphone off, as today. |
| Writing (after stop, until the text lands) | Waveform freezes at 40% opacity; the mic's circle shows a 16pt spinner in its glyph's color in place of the glyph. A tap starts the next dictation. |

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

The key, pressed and label colors are the iOS 27 theme (`KeyboardTheme`), which the light Default theme keeps; the mic is new.

### Themes

Raycast's five, picked in the app (Keyboard › Theme) or Settings › Apps › iikb › Theme (`ThemeName`, `KeyboardTheme.named`), each read pixel by pixel off Raycast's keyboard and its app's preview on the iPhone Duo (full-resolution screenshots, Nov 2 2026). A theme paints the keys (`KeyPaint`: a face shading top to bottom, a pressed face, the label and its letterpress, a lit rim, a keycap's sides and glow, the shadow below); the bar, panels and mic stay on iOS's card and follow the app's light or dark. Callouts and accents take the letter keys' face.

Every theme has Raycast's keys (`KeyShape`): continuous corners, 3.9 + 0.143 × a letter key's width (Raycast's are 13.75 on its 69-wide keys on the open Duo in landscape, 11.75 on its 55-wide keys in portrait, 7.8 in its preview), and Apple's SF Compact letters 1.08 times Apple's size, with `123` at 0.67 of Apple's, 1.6 above the middle, and symbols at 0.86. Labels are lowercase, as Raycast's are, and sit where they do on the plain keys whatever the theme. Keys, labels and icons sit on whole pixels of the screen, as Raycast's do, so their edges and letters draw crisp rather than smeared across two pixels.

| Theme | Letter keys | Function keys | Notes |
|---|---|---|---|
| Default, dark | `#2F2F2F`, flat, white label | the same | |
| Default, light | the Colors above | the same | Raycast's light Default wasn't captured |
| Clear | no fill; label in the label color; pressed: the label color at 16% | the same | glyphs only |
| Physical, dark | `#0B0B0B`→`#050505`, white label; a ⅓ pt rim, white 15% at the top, gone a quarter of the way down | the same | |
| Physical, light | `#F8F8F8`, label `#2C2C2C`; a ⅓ pt rim, white 60%, gone a tenth of the way down | the same | |
| Mechanical, dark | face `#171717`→`#202020` inside sides `#171717`→`#0E0E0E` (80%)→`#0D0D0D`, lit by a glow of white 12% from the middle of the top edge, 0.93 of the key's height across | the same | the face sits 9.3% of the key's height below its top, 9.7% in from its sides and 15% above its bottom, with corners 65% of the key's |
| Mechanical, light | face `#FAFAFA`→`#E5E5E5` inside sides `#E0E0E0`→`#DBDBDB`, glow white 23%; label `#2A2A29` | the same | |
| iOS 5 | `#F5F5F5`→`#C3C5C9`, black label over a white line 1 pt below it; a 0.85 pt rim, white 30%, gone a fifth of the way down | `#9EA6AF`→`#6D737C`, white label under a black 55% line 1 pt above it; a 0.85 pt rim, white 18%, gone a fifth of the way down | every key casts black 30%, 1 pt down, 1 blurred, from the key set in 1 pt at its sides, so it shows only below; a prominent return stays blue (`#609CF5`→`#2462D8`), which Raycast's screenshots don't show |

Physical and Mechanical come Automatic (following the app), Dark or Light.

### Options from Raycast

- **Character Preview**: None, Detached (the letter in a bubble of its own 6 above the key, which shows pressed) or Attached (Apple's: the key grows up into the bubble). Default Attached.
- **Number Row**: digits 1 to 0 above an iPhone's letters, 80% of a key's height, one row gap above the letters; the letters stay where Apple's are and the keyboard grows upward. Off by default.
- **Skin Tone**: the tone emoji take in the bar and the panel until you pick another for one by holding it. Default none (yellow).
- **Key Spacing**: the space between the keys, the one knob for their size (Bassim, Nov 3), seven stops on a slider with Standard (the gaps below) in the middle: Tightest, Tighter and Tight take the gaps down to a quarter of Standard's, Roomy, Roomier and Roomiest up to seven quarters. The keyboard's height and its outermost keys' edges stay put, so the keycaps take what the gaps give up. Default Standard.
- **Haptic Feedback**: Off, or seven strengths on a slider, Standard (Apple's) in the middle, three softer and three up to twice as strong (Lightest, Lighter, Light, Standard, Strong, Stronger, Strongest; Bassim asked for 5 to 7, Nov 3). Default Standard.

### Per device

| | Keys block | Key h | Row gap | Top | Bar | Bar → keys | Bottom | Total |
|---|---|---|---|---|---|---|---|---|---|
| Duo folded, portrait, 466 × 678 | 6.5 in, keys 6 apart | 45 | 11 | 3 | 38 | 7 | 39 | |
| Duo open, landscape, 951 × 669 (compact) | 4.5 in, keys 6 apart | 41.67 | 9 | 3 | 38 | 7 | 20 | |
| Duo open, portrait, 669 × 951 | 4.5 in, keys 6 apart | 49.42 | 9 | 3 | 38 | 7 | 73 | |
| Duo folded, landscape, 678 × 466 (compact) | 4.5 in, keys 7 apart | 33.33 | 9 | 3 | 32 | 7 | 20 | |
| iPhone portrait (Face ID), 375–440 wide | full width | 43, or 45 from 415 wide | 11 | 3 | 38 | 7 | today's `bottomInset` | |
| iPhone landscape (compact) | today's | today's 27.33 | today's 8 | 3 | 34 | 7 | today's | |
| iPad (all) | today's | today's | today's | today's | today's 36pt row, compact bar | today's | today's | today's |

- Every Duo row is Apple's keyboard measured in the iOS 27.1 simulator (`scripts/sim duo`, which unfolds it with Device Hub's hinge event). "Keys block" is the side inset inside the keyboard's own width, which iOS narrows on the side layouts; "Bottom" is how far above the screen's bottom Apple's last row ends.
- The Duo's screens go by Bassim's words, as `Duo.Screen` names them: folded (the cover) or open (the inner screen), in portrait (taller than wide) or landscape (wider than tall). Slightly folding the open screen keeps its screen and changes only the height iOS gives the keyboard; nothing reads the hinge. The open screen's own upright is landscape, which is why the simulator's portrait shows it 951 wide.
- Apple's letters on the Duo are bigger than on other iPhones: 25.5 folded in portrait, 23.5 folded in landscape, 28.5 open in landscape, 28 open in portrait. Hex's `123`, return and symbols grow by the same share; Apple's own `123` is bigger still, but its key is three times as wide, since its row has no globe.
- The Duo's keys span the keyboard's whole width on every screen, at Apple's insets folded. Open, Apple's keys leave wide margins and gaps (in portrait 18 in, 9 apart, 45.67 tall, rows 14 apart; in landscape 9 in, 10 apart, 38.67 tall, rows 13 apart), and Bassim asked for keys "taller and wider as much as possible using as much available space as possible" (Nov 3), every key alike, so open the keys take the folded landscape's margins and gaps (4.5 in, 6 apart, rows 9 apart) in Apple's keyboard height: in portrait about 10% wider and 8% taller, in landscape about 6% wider and 8% taller.
- Split Keyboard (open in landscape; Settings › Keyboard › Layout, holding `123`, or the bar's … menu) puts half of each row under each thumb, as Apple's does: each half five keys from the keyboard's edge, with two keys' room between the hands (12 columns of the same margins and gaps), G and V on both halves, the layer and emoji keys and a space bar on the left, a space bar, the field's own keys and return on the right. Apple's split keys are a fifth narrower, with about four keys' room between the halves, which Bassim found used "barely any" of the screen (Nov 2).
- Regular iPhones and iPads keep their key geometry, which is measured against Apple's.

### The compact layout

Where height is short (any landscape, and iPad), the bar and the mic are 34 (32 on the Duo folded in landscape, 38 open in landscape; iPad: a 36 bar and a 34 mic), and a panel's results are one row (`Toolbar.isCompact`). Settings › Keyboard › Layout › Compact Emoji & GIFs makes the emoji and GIF panels that one row on every screen (`Toolbar.showing`); it's off, so portrait screens keep the large panels.

Slightly folded in portrait with a panel open, the open Duo gives a keyboard only the screen below the hinge: about 322 of the 420 Hex asks for with a panel open. Hex keeps asking for its full height and lays out in what it gets: the keys keep theirs at the bottom, and a panel that doesn't fit goes to its one row (`Toolbar.fitting`), back to its size once the Duo opens flat. iOS rounds that height to the screen's pixels, so a panel less than a point short keeps its size. Without a panel, slightly folded in portrait, iOS gives Hex a taller keyboard than it asks for, the same height it gives its own (Bassim's photos of both, Nov 3). That height is iOS's, not the keyboard's: asking for more doesn't get it, as a build that asked to reach the hinge got exactly Apple's folded height there (its top 554 points down on his Duo, as Apple's), while flat it got the whole half, which Bassim called backwards (Nov 3). Measured in the iOS 27.1 simulator held tall at 110° to 170°: iOS gives a third-party keyboard 321 points whatever it asks for (276 or 560, by a required constraint, `allowsSelfSizing` or `preferredContentSize`), where flat it gives exactly what's asked; the keyboard's window is its own bounds, so nothing draws above its top, and inside a keyboard `UIHingeInteraction` never reports and the view has no reserved regions. So Hex asks for its own height in every pose. Whatever extra height iOS gives, on any screen, the rows share it as Apple's do (`KeyboardMetrics.filling`): the keys grow, the gaps, insets and bar keep their size, and the bar or panel sits on the keys. Hex keeps asking for its own height, so the keys shrink back once iOS gives less.

### Cut from Raycast

- The 2×2 grid button at the bar's left (Raycast's commands): Hex has no commands, so the suggestions get its width.
- Quick Fix, Ask AI and AI commands.

### States

- Pressed key: the pressed fill, plus today's callout above letter keys. Function keys and tools show only the pressed fill.
- Shift: `shift` off, `shift.fill` on, `capslock.fill` locked. Letters show uppercase while shift is on.
- The number and symbol layers keep today's keys (`PhoneLayouts`) in this look; `123` reads `ABC` there.
- Holding `123` opens the bar's … menu in a row on every iPhone screen: the layouts that apply there (Left, Full and Right in portrait, on the Duo only folded; Full and Split on the open Duo in landscape; elsewhere the layout in use, so letting go without sliding changes nothing), Next Keyboard where iOS wants one, and iikb Settings. Bassim reaches Hex's settings this way (Nov 2). Settings › Keyboard › Layout › Keyboard Menu picks where the menu opens: holding `123`, the … button, or both (the default); Bassim found the … button unneeded once holding `123` had it (Nov 3). An iPad has no hold menu, so it always keeps the button.

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
- What the keys do in a panel: letters, numbers, space and shift type into the field. Delete deletes in the field; with the field empty, it deletes before the app's cursor, so a wrong insert can be fixed without leaving the panel. Return and the back button close the panel. The globe works as everywhere on iPad.
- Every keystroke searches at once: the newest query cancels any search still running, and results only ever show for the text in the field. No debounce timer (AGENTS.md: no timers).
- A panel stays open after you insert something, so you can add several. It closes with back, return, or when the keyboard goes away; the keyboard always comes back on the main layout.
- The bar's suggestions and the mic hide while a panel is open.
- Compact layout: results 46 tall (one row), the search row 34, the gaps as in the main compact layout.

### Emoji

- Works without Full Access.
- Results: 10 columns across the keys block (45.3 each on the Duo cover), rows 45.3 tall (three show), emoji 30 (26 in compact). Rows fill left to right; the results scroll up and down. Compact: one row, the same columns wide, scrolling sideways.
- Empty field: your recent emoji first (the ones you picked here and from the bar, as `EmojiHistory` weighs them, up to 30), then every emoji in Apple's order. No category tabs: search is faster than tabs.
- Typing: matches by CLDR name and keywords, best first, ranked by what you use and then by Unicode's emoji frequency. This search existed (commit 416f351, removed in 00edb44 with `EmojiKeyboardView`): bring it back from history rather than rewrite it. Placeholder: "Search emoji".
- Tap: inserts the emoji at the app's cursor and counts it as used. Hold an emoji with skin tones: a callout of the tones above it, like a key's accents; the pick is remembered for that emoji.
- No results: the results area says "No emoji for "query"" in secondary 15, centered.

### GIF

- Needs Full Access (it goes online). Without it, the results area says "GIF search needs Full Access." in secondary 15 with "Turn On" (accent, semibold) under it, or after it on the same line when the results are one row, and the whole notice opens Hex's app where it explains how. The clipboard's notices work the same (`PanelNotice`).
- Source: KLIPY's API, its key in `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/klipy.key`, kept out of git like `Config/Team.xcconfig`. With no key built in, the GIF tool doesn't show. KLIPY over GIPHY (what Raycast uses): both give a new key 100 requests an hour, but KLIPY's production keys are free and unlimited, where GIPHY reviews each app and discusses pricing; GIPHY forbids keeping anything it sends, even a GIF's URL, where KLIPY lets an app keep slugs and fetch them again (`gifs/items`), which recents need. KLIPY requires the placeholder "Search KLIPY", loading its media straight from its URLs, and showing its results in its order.
- Field: leading GIF glyph (20, secondary), placeholder "Search KLIPY", trailing `clock` (20, secondary) that switches the results to your recent GIFs; it turns accent while on. Raycast's GIF token chip is cut: the panel only searches GIFs.
- Results: two rows 65 tall, 6 apart, scrolling sideways (compact: one row), also when a swipe starts on a GIF (`ButtonScrollView`). Each GIF keeps its own aspect ratio at that height (no letterboxing, unlike Raycast), radius 8, the key fill while it loads.
- Empty field: KLIPY's trending GIFs.
- Searching: one request is out at a time. Keys typed while it's out don't each send one; when it returns, one search goes out for what the field holds then (`GifSearch`). KLIPY answers 30 at a time; scrolled within a screen of the end, the panel asks for the next page while KLIPY says there's one, and adds it after what shows. That keeps a new key's 100 requests an hour from running out in a few searches, with no timer.
- Memory: a keyboard has a small memory limit. Load KLIPY's small WebP (`sm`), animate only the tiles on screen, and drop the rest.
- Tap: a keyboard can't put an image into the app's field (`UITextDocumentProxy` only types text; the image inserts UIKit has, `RTITextOperations`' and the sticker path, serve Apple's own keyboard), so Hex copies the GIF (KLIPY's `md` GIF, the format every app pastes) to the clipboard, as GIPHY's and Raycast's keyboards do (Raycast's manual: "tap a GIF to copy it and paste it into your message"), and the search row shows "Copied. Paste it, or hold a GIF to drag it in." in its place until your next touch.
- Hold: the GIF lifts out of the keyboard and drops into the app's field as the GIF itself, no paste (a system drag, which a keyboard may start; the app decides whether it takes images, as Messages does).
- A GIF tapped or dropped goes into recents by its slug (last 50, kept in the keyboard's own container), and KLIPY is told it was shared.

### Clipboard

- Needs Full Access (a keyboard can't read the clipboard without it) and Settings › Apps › iikb › Paste from Other Apps set to Allow. iOS counts a keyboard's reads as its app's, even inside another app; at Ask (the default) it refuses them silently, since the prompt it means to show never appears over a keyboard, and at Allow it lets them through without asking (iOS 27 simulator, from `pasted`'s log). The panel says which is missing, with a "Turn On" button that opens Hex's app.
- Hex keeps what you copy when it sees it: each time the keyboard appears and each time this panel opens, it checks the clipboard's `changeCount` and keeps a new item. Nothing runs in the background. A refused read isn't counted as seen, so turning Allow on catches up.
- Never kept: items marked concealed (`org.nspasteboard.ConcealedType`, which password managers set) and anything copied while a secure field was active.
- History: everything you copied, newest first, until you delete it; an identical item moves to the top instead of repeating; pinned items stay above the rest. All of it shows, each row made as it scrolls into view, and every read and write of its files happens off the main thread, so a long history never slows a key. Kept in the App Group, so the app's Clipboard tab shows it, never online, with a copy in the keyboard's own container that a group without a history takes (iOS deletes the group's container whenever an install leaves no app claiming it; the history kept before it moved to the group got there this way). The keyboard starts the group's history, so the app keeps nothing before it has. Texts over 100 KB live in individual UTF-8 files, with only a short preview in the history; search reads the whole text, and selecting one loads it in full. The backup includes those files. Each side locks the history while reading and changing it, since iOS can run the keyboard in two apps at once, beside the app, and one would write over what another kept.
- Results: rows 44 tall, 2 apart, three in view, scrolling up and down. Each row: a 16-wide slot with `pin.fill` (13, secondary) for pinned items, the text on one line in SF Pro 16 (images show a 32 thumbnail, radius 6), and at the right how long ago in secondary 13 (`now`, `5m`, `3h`, `2d`). iOS never tells a keyboard which app copied something (`UIPasteboard` has no such property), so a row can't say where it came from.
- Field: leading clipboard glyph, placeholder "Search clipboard"; typing filters by substring.
- Tap: inserts the text at the cursor (an image is copied back to the clipboard, as GIFs are). Hold: Pin or Unpin, Delete.
- Compact: one row of up to three cards, the key fill, radius 10, the text in 14 over its age in 11.
- Empty: "Things you copy show up here." in secondary 15.

## The app

The app takes its look from Raycast's iOS app (November 2026): a black page (`#000000` dark, `#F2F2F5` light), cards in `#1C1C1E` (white in light) with a 1pt hairline edge and a 22pt continuous corner, gray sentence-case headers above cards and gray footers under them, rows 56pt and taller split by inset hairlines, a radio mark at a choice's right (a gray ring, or a white circle with a black check), blue switches, and pills for a page's own tabs (the picked one a white capsule with black text). Every page's title and buttons are the system's navigation bar (`navigationTitle`, `.inlineLarge`, `toolbar`), never a header of Hex's own, as Apple's iPhone Duo guidance asks: the system places them for each pose, in the status band beside the clock on the open Duo in portrait, in the side bar with glass buttons folded and open in landscape, and a button with an icon and a title can move to the side bar or an overflow menu. A page's pills sit pinned just under the bar. Text is SF Pro in Dynamic Type styles.

Hex links against the iOS 27.1 SDK, so on the iPhone Duo iOS puts the status bar and the app's tab bar in the vertical bar at the screen's edge on every screen (AGENTS.md, `scripts/phone`). Five tabs: **iikb**, **Transcripts**, **Clipboard**, **Your Taps**, **Settings**. Every setting lives in Settings and nowhere else; the other tabs show what Hex has gathered.

Every page knows which of the Duo's screens it's on (`Arrangement`):

```
open, landscape 951 × 669       open, portrait 669 × 951      folded 466 × 678
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

- The open screen in landscape (951 × 669), the only one with room: two columns, as an iPad's split view, each taking half the width the page gets, each with its own margin and header, each scrolling on its own (`Panes`), with no line between them. A layout follows the viewport's size, never the fold: folding the Duo a little changes nothing.
- Everywhere else (folded either way, open in portrait): one column that scrolls as one, as iOS lays out a compact width; a list's item opens on its own page. Halves that scroll apart on the open screen in portrait read as one page cut in two, and two columns folded in landscape cut their labels short.

- **iikb**: whether the keyboard is on (in the bar's subtitle, with Turn On until it's added); a field to try it (a `UITextView`, which the UI tests type into); Set Up, the three switches iOS keeps (Add iikb, Allow Full Access, Paste from Other Apps), each checked once the keyboard has seen it on, until all three are; then three counts across, words said today, items copied and taps learned, each opening its tab, and cards two across, one for each setting reached for most, Dictionary, Theme, Voice Model, Writing Style, Sound & Haptics and Keep Mic On, each showing what it is set to and opening its page in Settings, where every setting lives. Wide, the field and the three counts take the first pane, Set Up and the settings cards the second, so the field stays above the keys.
- **Transcripts**: every dictation, newest first by day, under a search field and a card of words, time talking, pace and a two-week chart; wide, the picked transcript (the newest until you pick) shows in the second pane, otherwise it opens on its own, with its facts, Transcribe Again and Delete.
- **Clipboard**: the history the keyboard's clipboard panel keeps, the same items: Pinned first, then by day, newest first, each row its text (up to four lines) or a 64 thumbnail over the time it was kept, under a search field. A tap copies it again and shows "Copied" in place of the time; holding offers Copy, Share, Pin or Unpin and Delete; the bar's menu has Clear History, which keeps what's pinned. Wide, the item last tapped (the newest until you tap one) shows in full in the second pane, all its text or its image as wide as the pane, with Copy, Share, Pin and Delete. When Hex comes forward it keeps what's on the clipboard, as the keyboard does, once Full Access and Paste from Other Apps are on (it reads without asking at Allow); until they are, a card above says which to turn on and opens Keyboard Access.
- **Your Taps** (`TapsPage`): four numbers in a card (taps, on target, on target lately, off center), the keyboard drawn with the touch model (`TapMapView`: Heat, Aim and Accuracy as pills right above it, the legend for its marks under it), a picked key's card (on target and taps, where you aim, its close-up, a segmented bar of where its taps land, and what its aim follows), how your thumbs pull (every key's arrow, then the left half, the right half and the space bar each on a small target), and misses by key (a column per letter, most missed first, and where the worst three go; a column or row picks its key). Big numbers are Helvetica Neue Bold; blue marks your aim and taps that land, orange misses. Wide, the keyboard and the pull take the first pane and the rest the second. Each screen of the Duo learns apart, the layout menu beside the title names them (Folded, portrait · Open, landscape), and the screen you're on shows first, drawn at its own size.
- **Settings**: one list, as iOS Settings and Raycast's settings are, in three sections, each row a glyph, a title and what it's set to. Wide, the list takes the first pane and the picked page (Theme until you pick) the second, the picked row filled; elsewhere a row opens its page. The keyboard's "…" menu opens this list.
  - **Keyboard**. Each page starts with Hex drawn as it will look (`KeyboardPreviewView`) over "Tap to try", which swaps the drawing for a field so the real keyboard comes up.
    - **Theme**, how the keys look: Default, Clear, Physical, Mechanical, iOS 5, each with a line on how it looks; under the picked Physical or Mechanical, Automatic, Dark and Light, each as two keycaps.
    - **Layout**, which keys there are and where: Key Spacing, a slider of seven stops, Standard in the middle, from Bigger Keys to More Space; Number Row; Emoji Key, the emoji's Skin Tone and Compact Emoji & GIFs; Split Keyboard; One-Handed Keyboard (Off, Left, Right).
    - **Typing**, what typing does to your text: Auto-Capitalization, Auto-Correction, Predictive Text; Smart Punctuation, Enable Caps Lock, "." Shortcut; where Text Replacements come from.
    - **Sound & Haptics**, how a press feels: Character Preview (None, Detached, Attached, each drawn), Key Haptics with a Strength slider of seven stops, Standard in the middle, which it keeps while haptics are off, Sound, and Allow Full Access when Hex hasn't seen it.
  - **Voice Typing**.
    - **Voice Model**: each with a line on what it costs and, for the picked one, its download, getting ready, or why it failed with Try Again.
    - **Writing Style**: Style (Wispr Flow's four) and Editing (As Said, Light, Clean), each choice showing the same words as it types them with everything else as picked, and Lists.
    - **Dictionary**: Add Word at the top, then the words the model gets wrong, each with what it writes instead.
    - **Keep Mic On**: how long the mic stays on after a dictation.
  - **iikb**.
    - **Sources**: Add Source and a tapped source open a form, name, https address and secure token, that says what's wrong before Save.
    - **Keyboard Access**: the three switches and Open iikb in Settings.
    - **Privacy & Data**: what stays on the iPhone and what goes online; Reset Learned Words and Taps; Delete All Transcripts.
    - **About iikb**.
- Settings › Apps › iikb has the same pages for the keyboard's switches (Theme; Layout with Split Keyboard and One-Handed Keyboard; Typing; Sound & Haptics; Voice Typing), and says the app also picks the voice model and adds sources.
- Full Access and Paste from Other Apps are read from TCC, where iOS keeps them for the app (`HexStatus`), and with Add iikb each time the app comes forward, so Home's setup steps check off as you come back from Settings and leave once all three are on.
- The dictation screen (opened by the keyboard's mic) is the record-red circle swelling with your voice over a readable-width hint; if it couldn't listen it says why, with Close.

## Out of this design

Swipe typing, snippets and quicklinks are later phases. Nothing here uses AI.
