# iikb · brand

**The idea in a sentence:** a keyboard set like a Swiss poster: Helvetica, black and white, everything on the grid the keys already make.

The app was already most of the way there (black pages, near-black cards, gray sentence-case labels, white pills for what's picked), so the brand is the name, the type and the composition, and the app moves only a little toward it.

## Personality

- **Plain.** Says what the keyboard does, with the numbers that show it. No marketing voice.
- **Built on a grid.** A keyboard is rows of equal keys. Pages are rows of equal columns. Things line up on one left edge.
- **Quiet, then exact.** Big type for the one thing that matters on a screen, small type for everything else, nothing in between.
- **Apple's where it's Apple's.** The keys, the system fonts in the app's rows and the iOS controls stay iOS. The brand lives in titles, numbers, the mark and the site.

## The name

- **iikb**, lowercase everywhere, even starting a sentence or a title. Never IIKB or Iikb, never "the iikb keyboard".
- Never explained or expanded.
- Code and IDs keep the old name (`HexKeyboard`, `HexStyle`, `com.shahidy.hexkeyboard`, `hexkeyboard://`), so installs keep their recordings, clipboard, typing record and settings.

## Type: Helvetica Neue

One family, as the International Style used it.

- **Wordmark:** Helvetica Neue Bold, tracked -45/1000, drawn from the font's own outlines by `logo/gen.mjs`.
- **Display** (titles, headlines, big numbers): Helvetica Neue Bold, tracked -0.02em at 34px and up to -0.035em at 96px and above; line-height 0.95 to 1.05. Big numbers in Bold or Medium.
- **Text** on the site: Helvetica Neue Regular 17/1.45, small 14/1.4, labels 12/1.3 Medium. Sentence case. No tracked all-caps.
- **In the app** only titles (large and inline nav titles), the stat tiles' numbers, the About mark and the space bar's corner label use Helvetica Neue (`HexStyle.display`, `Font.display`). Rows, labels and controls stay the system font, so the app keeps reading as iOS.
- **On the web:** `"Helvetica Neue", Helvetica` from the visitor's system first (every Apple device has it), then TeX Gyre Heros (GUST Font License, a free Helvetica clone) shipped in `fonts/` for everyone else. Helvetica Neue is Apple's system font and isn't redistributed: `logo/gen.mjs` reads it from `.scratch/fonts` (extracted from the Mac's `/System/Library/Fonts/HelveticaNeue.ttc`), and only the outlines are committed.

## Color: the app's own

Black and white do the work, as they already do in the app. Two colors come from the keyboard and mean one thing each.

| token | light | dark | use |
| --- | --- | --- | --- |
| `--page` | `#F2F2F5` | `#000000` | the page (HexStyle.page) |
| `--card` | `#FFFFFF` | `#1C1C1E` | cards, panels (HexStyle.card) |
| `--ink` | `#000000` | `#FFFFFF` | text, the wordmark, filled buttons (HexStyle.pill) |
| `--ink-2` | `#6C6C70` | `#8E8E93` | secondary text (HexStyle.secondary) |
| `--rule` | `#E3E3E8` | `#2C2C2E` | dividers (HexStyle.divider) |
| `--edge` | `rgb(0 0 0 / .06)` | `rgb(255 255 255 / .07)` | card edges (HexStyle.edge) |
| `--red` | `#FF3B30` | `#FF453A` | live: the mic while it records, the line that's iikb in a chart, "now" |
| `--blue` | `#007AFF` | `#0A84FF` | selected: the picked tab, a tapped key, a link |

Rule: **red means live, blue means selected, everything else is black, white and gray.** The keyboard's own UI already uses them that way (the recording mic, iOS's tint), so the brand takes them from there instead of adding a color.

Dark is the app's dark: a black page, near-black cards. It follows the system theme.

## Grid and spacing

- 4pt base. Scale: 4 · 8 · 12 · 16 · 24 · 32 · 48 · 64 · 96 · 128.
- Site: 12 columns, max 1200px, gutter 24px, margin `clamp(20px, 5vw, 64px)`. Everything starts on a column edge; text is flush left, ragged right, never centered.
- Corners: the app's continuous corners (cards 22pt) for anything that's the app or the keyboard; the page itself is square: no rounded section boxes, no shadows, no gradients, no glass.
- Rules are 1px in `--rule`, used to separate, never to decorate.

## Motifs

1. **The wordmark flush left on a bottom margin.** The icon, the OG image and the video's end card all place iikb the same way: left margin = bottom margin, the name as wide as the margins allow.
2. **The key grid.** The keyboard's rows are the page's module. Sections line up to the keys' columns where a keyboard is on screen.
3. **One big number.** A section with a number leads with it in display type (97.6%), the comparison beside it in gray.
4. **The real thing.** The demo runs the real engine; screenshots are the real app in its current version.

## Logo

`logo/gen.mjs` draws every mark from Helvetica Neue Bold's outlines (`bun logo/gen.mjs`, into `logo/out/`).

- **Wordmark:** `wordmark-ink.svg`, `wordmark-paper.svg`.
- **Icon:** `icon.svg` (full bleed, for iOS, which masks it), `icon-rounded.svg`, `icon-light.svg`. The wordmark white on black, flush left on a 13% margin, as wide as the margins allow. The app's icon is this, at 1024.
- **Favicon:** `favicon.svg`, the icon on a tighter margin so the name survives 16px, flipping to black on white in a dark browser. `apple-touch-icon.png` (180) and `icon-512.png` are the icon full bleed.
- **Not taken:** a stacked "ii / kb" (it splits the name into two words it isn't); the name smaller and low on the square (`direction-poster.svg`, less presence on the Home Screen); and a space bar with iikb in its corner (`direction-spacebar.svg`, grown from the keyboard, but the label vanishes below 60px).

## Words

`copy/MESSAGING.md` is the source of truth for words; `copy/facts.json` for numbers.

## Credits

The keyboard's look follows Raycast's keyboard; the voice model is NVIDIA's Parakeet run by FluidAudio. The site and README say so by name.
