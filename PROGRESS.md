# Progress

## 2026-10-08

- 04:30 Repo, XcodeGen project, app + keyboard extension building for the simulator.
- 04:50 System keyboard references captured on 8 simulators (iOS 26.3), light and dark. Measured key grid: 6pt gaps, 6.5pt side insets, 43/45pt keys, 11pt row gaps on iPhone; three distinct iPad layouts (mini, 11", 13").
- 05:05 Real extension runs in the simulator (enabled through `AppleKeyboards` prefs, no Settings UI needed). Height only sticks when the content is Auto Layout-driven; a plain height constraint gets overridden on iOS 26.
- 05:15 Keycaps are SF Compact (not SF Pro) at 23pt in the system keyboard; we load it from the system font file. Glyph sizes now match within a pixel.
- 05:16 22 core tests pass (autocap, double-space period, shift/caps lock, layer switching, word delete, layouts).
- 05:40 iPhone geometry matches the system keyboard on all four iPhones (every key rect within 0.33pt). Light and dark key/background colors match exactly; the host-drawn backdrop behind a third-party keyboard is 3 levels darker in light mode (223 vs 226), which we can't control.
- 05:40 iPad needs `AppleKeyboardsExpanded = 1` before it honors `AppleKeyboards`; now in `scripts/sim`.
- 05:40 Email, URL and web search bottom rows re-measured from iOS 27 references (1.25-wide @/., three equal URL keys, 1.75 search return).
