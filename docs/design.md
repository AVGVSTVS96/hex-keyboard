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
| Duo folded (cover), portrait, 466 × 678 | full width | 45 | 11 | 8 | 40 | 8 + 40 | 11 | 39 | 359 |
| Duo open, portrait, 669 × 951 | 466, centered | 45 | 11 | 8 | 40 | 8 + 40 | 11 | 20 | 340 |
| Duo open, landscape, 951 × 669 (compact) | 560, centered | 36 | 9 | 6 | 36 | none | 10 | 16 | 239 |
| Duo folded, landscape, 678 × 466 (compact) | 560, centered | 30 | 7 | 4 | 34 | none | 8 | 6 | 193 |
| iPhone portrait (Face ID), 375–440 wide | full width | 43, or 45 from 415 wide | 11 | 8 | 40 | 8 + 40 | 11 | today's `bottomInset` | today's + 51 |
| iPhone landscape (compact) | today's | today's 27.33 | today's 8 | 4 | 34 | none | 8 | today's | |
| iPad (all) | today's | today's | today's | today's | today's 36pt row, compact bar | none | today's | today's | today's |

- The open Duo in portrait uses exactly the folded keys, centered, so typing feels the same folded and open.
- The bottom insets on the Duo are measured on the cover screen in the iOS 27.1 simulator (Apple's last row ends 39 above the screen's bottom). The open screen's are a first guess: the simulator can only unfold through Xcode's DeviceHub window, so they get checked against Apple's keyboard once someone can unfold it.
- Regular iPhones and iPads keep today's key geometry, which is measured against Apple's. Only the bar, the pill row and the colors above change, so nothing that types today moves.
- On the Duo cover in the 27.1 simulator, today's Hex draws its letter keys 38.5 wide with 13.7 side margins (Apple: 40 and 6.5), as if laid out for a 440 screen. The spec above is Apple's geometry; the build has to find where the extra margin comes from.

### The compact layout

Where height is short (any landscape, and iPad), there's no pill row: the three tools sit in the bar's left end as 36 × 36 (34 on the folded landscape) icon buttons, 2 apart, before the suggestions. Same icons, same panels. The keys block is at most 560 wide and centered; the bar spans the same block.

### Cut from Raycast

- The 2×2 grid button at the bar's left (Raycast's commands): Hex has no commands, so the suggestions get its width.
- Quick Fix, Ask AI and AI commands.
- The emoji key in the bottom row (moved to the pill row).
