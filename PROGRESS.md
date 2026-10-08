# Progress

## 2026-10-08

- 04:30 Repo, XcodeGen project, app + keyboard extension building for the simulator.
- 04:50 System keyboard references captured on 8 simulators (iOS 26.3), light and dark. Measured key grid: 6pt gaps, 6.5pt side insets, 43/45pt keys, 11pt row gaps on iPhone; three distinct iPad layouts (mini, 11", 13").
- 05:05 Real extension runs in the simulator (enabled through `AppleKeyboards` prefs, no Settings UI needed). Height only sticks when the content is Auto Layout-driven; a plain height constraint gets overridden on iOS 26.
- 05:15 Keycaps are SF Compact (not SF Pro) at 23pt in the system keyboard; we load it from the system font file. Glyph sizes now match within a pixel.
- 05:16 22 core tests pass (autocap, double-space period, shift/caps lock, layer switching, word delete, layouts).
