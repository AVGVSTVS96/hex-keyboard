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
- 06:05 iPad geometry: every key rect on iPad Pro 11/13, iPad A16 and iPad mini matches horizontally to the half point. iPad gets the system's undo/redo/paste bar above a third-party keyboard for free, so our own bar is 0pt there; vertical insets recalibrated per class. Keys are circular-cornered (r 8 iPhone, 9.5 iPad, 11.5 13"), not continuous.
- 06:05 UI tests type through the real extension on iOS 27: "hello world  next" becomes "Hello world. Next", delete + 123 layer + space-returns-to-letters works.
- 06:55 Return key now uses iOS 26's icons (go →, search 🔍, send ↑, done ✓, next ›), blue when the field asks for it. iPad numbers layer gets its flick secondaries; pair keys (`,!`, 13" number row) are modeled explicitly.
- 06:55 14 UI tests pass through the real extension on iPhone 17 and iPad Pro 11 (iOS 26.3): autocap, double-space period, caps lock, delete, 123 layer, return, long-press accents, slide from 123, space-bar cursor.
- 07:20 Captured live pop-ups by holding keys from XCUITest while grabbing frames (`scripts/capture`). Our key callout and accent panel now match iOS 26's (blue selection, 37.5pt cells, 67pt panel); on iOS 27 they switch to its gray selection and dimmed held key.
- 07:20 iOS 27: geometry identical except the system keyboard's rows sit 7pt lower, below where a third-party keyboard's area ends. We follow 3pt of that; the last 4pt would clip.
- 07:20 Every iPhone (16e, 17, Air, 17 Pro Max) and iPad (mini, A16, Pro 11, Pro 13) key rect is within 0.33–1pt of Apple's in light and dark; landscape iPhone within 0.33pt.
- 07:25 Release device build (iphoneos, unsigned) compiles clean: 632 KB app. Extension footprint 25 MB in the simulator (limit ~48–60 MB).
- 07:25 Added placeholder app icon and privacy manifests. 15 UI tests pass on iPhone and iPad including delete acceleration and iPad flicks.

## Left before packaging

- Apple Developer membership (signing team, App Group if the app should ever toggle the hex bar or haptics, TestFlight).
- Real-device pass: haptics need Full Access on device and can't read the system haptics setting; key clicks follow the system setting through `playInputClick`.
- Visual check of iPad landscape (the simulator wouldn't rotate iPad headlessly) and of a real foldable size (wide phones fall back to the iPad mini layout, untested).
- iPad `#+=` layers and 13" symbol layers are best guesses; capture references with `scripts/capture` and adjust.
- Final app icon; this one is a placeholder.
