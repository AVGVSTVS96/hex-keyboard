# Themes

## Sub-features

Raycast's five themes (docs/design.md, "Themes"): Default, Clear, Physical, Mechanical and iOS 5, each a `KeyPaint` per kind of key from `KeyboardTheme.named`. Physical and Mechanical come Automatic (following the app), Dark or Light; the others follow the app. A theme paints only the keys: the bar, panels and mic stay on iOS's card. Every theme has Raycast's key corners and label sizes (`KeyShape`). The picker shows each as two keycaps (`KeycapSwatchView`).

## How to get to it (user POV)

Hex app › Settings › Keyboard › Theme (it opens over a preview of Hex, with "Tap to try"), or Settings › Apps › Hex › Theme. The Hex tab's Theme card opens the same page.

## Driving it

`scripts/mac 'scripts/sim themes <tag>'` screenshots every theme and look on the Duo's screens, light and dark, into `shots/raw/themes/` (`THEMES`, `SCREENS` and `APPEARANCES` pick some). `-HexTheme mechanical -HexThemeAppearance dark` sets one at launch for any screenshot. `ThemeTests` (package) pins each theme's paint, corners and what follows the app.
