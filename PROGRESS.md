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

## 2026-10-08 · suggestions branch

- 13:50 Captured Apple's suggestion bar on iOS 26.3 and 27 (light, dark, iPad) by typing through the system keyboard from XCUITest (`scripts/shots`). Measured: SF Pro 17, three equal slots, 1×24pt dividers, a 38pt capsule behind the pending autocorrection with the dividers next to it hidden; text colors differ per OS (26: #36383C light / #ACACAC dark; 27: #4A4A4C / #A2A2A2), pill #EBEDF0 light / #737373 dark.
- 14:00 Backspace right after an autocorrection on iOS 27 deletes only the space and offers the original (unquoted) in the first slot; tapping it restores it. Apple doesn't highlight a correction while the typed word is still a prefix ("Hel").
- 14:10 A third-party keyboard starts 16pt below the host-drawn backdrop and the backdrop grows with our view (tested: +20pt bar moved the backdrop 20pt). Apple's bar needs 11pt more than our 27pt strip, so the pill is 27pt tall and the text ~5pt lower than Apple's; the keyboard height and every key stay identical. Growing the strip to 38pt is one constant if Bassim prefers the exact bar over the exact height.
- 14:35 KeyboardCore: `Corrector` behind `CandidateSource` (isWord, guesses for a `TypedWord` with its taps, completions, predictions), `TypingMemory` (learned words, next-word counts, kept words), reverts, text replacements, name capitalization, `KeyGrid` (the key frame math, now shared by `KeyboardView` and the scorer), tap samples (`onTapSamples`: tap point + intended letter for every committed word whose length matches its taps). No Foundation.
- 14:50 Baseline scorer (`scripts/eval`): MacKenzie & Soukoreff phrase set, 2,714 words, taps from a Gaussian around the real iPhone 17 key centers, σ as a fraction of the key pitch, seed 2026, `UITextChecker` en_US:

  | σ | typed as-is | with autocorrect | top-3 hit |
  | --- | --- | --- | --- |
  | 0 | 100.0% | 99.9% | 100.0% |
  | 0.15 | 99.2% | 99.6% | 99.7% |
  | 0.25 | 72.0% | 89.3% | 91.3% |
  | 0.35 | 35.1% | 59.5% | 62.7% |

  Corrections that break a correctly typed word: 2 (claus→class, favourite→favorite). Keeping prefixes uncorrected like Apple's bar costs 1.8 points at σ 0.25 (87.5%), so Hex corrects them; the bar shows that honestly with the pill.
- 15:00 There is no public next-word API for keyboards (`UITextChecker` only completes and guesses, `UILexicon` is replacements and names). Empty-word predictions come only from what you've typed (next-word counts in `TypingMemory`) plus `CandidateSource.predictions(after:)`, which `UITextChecker` leaves empty. That's the seam for a model.
- 15:00 Host apps don't apply smart quotes to a third-party keyboard's input (verified: "It's" stayed straight), so Smart Punctuation lives in the engine.
- 15:10 Settings screen in the app, shared through the App Group `group.com.shahidy.hexkeyboard`. Works in the simulator because builds are now ad-hoc signed, which embeds simulated entitlements; verified end to end by a UI test that turns Auto-Correction off in the app and types in the keyboard. Learned words live in the group container too, so the app can reset them.
- 15:20 Memory, measured without XCUITest (it inflates the extension): 26–27 MB at launch, same as main; 46–49 MB once `UITextChecker` is first used, flat after that (no growth over 100+ keystrokes). The jump is `UITextChecker` loading its frameworks (dyld private memory 1.4 → 15 MB, malloc +5 MB); turning off the lexicon request changes nothing. That is at the ~48–60 MB extension limit in the simulator, so it needs a device measurement before shipping.
- 15:30 `requestSupplementaryLexicon` never calls back in some simulators (logged request, no reply on iPad Pro 11 26.3 and iPhone 17 iOS 27; it does on iPhone 17 26.3), so the text-replacement UI test fails there. The engine side is unit tested.
- 16:10 Tests: 42 core (20 new), 16 UI tests on iPhone 17 26.3 all pass; iPad Pro 11 26.3 and iPhone 17 iOS 27 pass all but text replacement (lexicon above).

## Settings parity (iOS 26.3 and 27 Settings › General › Keyboard)

| Apple | Hex |
| --- | --- |
| Auto-Capitalization, Auto-Correction, Enable Caps Lock, Smart Punctuation, “.” Shortcut, Predictive Text, Character Preview, Sound | Done, Apple's defaults (all on) |
| Text Replacement | Done, read from the system list; edited only in Settings (no API to write it) |
| Reset Keyboard Dictionary (Transfer or Reset) | Done, in Hex's settings |
| Haptic Feedback (default off) | Later: haptics in a keyboard need Full Access, which Hex doesn't ask for |
| Show Predictions Inline | Not possible as Apple draws it: a keyboard can only set marked text, which hosts underline instead of graying |
| Check Spelling / Check Spelling and Grammar (27) | Not possible: the red underlines are drawn by the host text view from the system setting |
| Show Math Results | Not possible: computed and drawn by the host's text system |
| Enable Dictation, Auto-Punctuation, Dictation Shortcut | Not possible: dictation is the system's mic key below a third-party keyboard |
| Slide to Type, Delete Slide-to-Type by Word | Later: swipe typing isn't built |
| One-Handed Keyboard | Later: possible, a layout feature |
| Keyboards, Hardware Keyboard | System-only |
