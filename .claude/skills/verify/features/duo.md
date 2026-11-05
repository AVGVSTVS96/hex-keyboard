# The iPhone Duo

## Sub-features

The keyboard and the app on each of the Duo's screens: the cover upright (466 × 678) and on its side, open and held wide (951 × 669), open and held tall (669 × 951), and half folded. On every screen the keys span the keyboard at Apple's insets, except open on its side, where they take over the margins Apple's leave (docs/design.md, "Per device"). Half folded on its side, iOS gives the keyboard only the screen below the hinge, so a panel that doesn't fit goes to its one row (`Toolbar.fitting`); whatever extra height iOS gives, the rows share it (`KeyboardMetrics.filling`). The app lays out each page for its screen (`Arrangement`, `Panes`): two panes meeting at the hinge only when it's open and held wide, one column elsewhere. Your Taps learns each screen apart.

## How to get to it (user POV)

Use iikb on the Duo, folded and open, upright and on its side.

## Driving it

`scripts/mac 'scripts/sim duo <tag>'` screenshots Apple's keyboard and iikb on the cover and open screens, upright and on its side, and half folded (`open-book`, 110°), light and dark, into `shots/raw/duo/`; `scripts/mac 'scripts/sim duoapp <tag>'` does every page of the app into `shots/raw/duo/app/`. `scripts/mac scripts/verify` runs the UI tests on a Duo simulator. `LayoutTests` pins Apple's keys and letters on each screen, `BarLayoutTests` the bar's spacing on every screen.

## Gotchas

The simulator's Duo opens only with Device Hub's hinge event (`scripts/devicehub.c`, which `scripts/sim` sends), and a reboot folds it again. iOS decides the keyboard's height in each pose; asking for more doesn't get it (docs/design.md, "The compact layout"), so a fill problem is checked on a real Duo.
