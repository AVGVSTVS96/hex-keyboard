# Progress

## 2026-10-08

- 04:30 Repo, XcodeGen project, app + keyboard extension building for the simulator.
- 04:50 System keyboard references captured on 8 simulators (iOS 26.3), light and dark. Measured key grid: 6pt gaps, 6.5pt side insets, 43/45pt keys, 11pt row gaps on iPhone; three distinct iPad layouts (mini, 11", 13").
- 05:05 Real extension runs in the simulator (enabled through `AppleKeyboards` prefs, no Settings UI needed). Height only sticks when the content is Auto Layout-driven; a plain height constraint gets overridden on iOS 26.
- 05:15 Keycaps are SF Compact (not SF Pro) at 23pt in the system keyboard; we load it from the system font file. Glyph sizes now match within a pixel.
- 05:16 22 core tests pass (autocap, double-space period, shift/caps lock, layer switching, word delete, layouts).
- 05:40 iPhone geometry matches the system keyboard on all four iPhones (every key rect within 0.33pt). Light and dark key/background colors match exactly.
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
| Check Spelling / Check Spelling and Grammar (27) | Not possible in the extension: the red underlines are drawn by the host text view from the system setting. The web demo draws its own (spelling only) |
| Show Math Results | Not possible: computed and drawn by the host's text system |
| Enable Dictation, Auto-Punctuation, Dictation Shortcut | Not possible: dictation is the system's mic key below a third-party keyboard |
| Slide to Type, Delete Slide-to-Type by Word | Later: swipe typing isn't built |
| One-Handed Keyboard | Later: possible, a layout feature |
| Keyboards, Hardware Keyboard | System-only |

## 2026-10-09 · typing-model branch

- 16:15 KeyboardCore: `TouchModel` (each key a 2D Gaussian, conjugate Normal-Inverse-Wishart, offsets in key cells, one model per device class/orientation/layer), `Lexicon` (flat byte trie: letter, word log-p, subtree log-mass, flags, first child), `Decoder` (exact A* over the trie; the subtree mass bounds every word below a node), `LanguageModel` (Witten-Bell: your next-word counts → your words → lexicon → letter-by-letter novel words, novelty by the rule of succession). `Math.log/exp` in pure Swift since Core can't import libc (Wasm).
- 16:20 Labels from real events only: a committed word's taps become labels when you move on (next word, keyboard hidden); a revert teaches the typed letters; deleting the word teaches nothing; backspace-then-retype labels the erased tap with the retyped letter if it's within a quarter key of it.
- 16:25 Lexicon: SCOWL 2020.12.07 en_US ≤ 60 + proper names ≤ 50 + larger-list words as common as the median size-60 word ("ok", "app"); counts from Google Books Ngram 20200217 English Fiction, 1980+ (CC BY 3.0). Google splits contractions, so "I'm" comes from the 2-gram "i 'm" and "don't" from "do not" (also counts the uncontracted phrase). 133,733 words, 2.36 MB. Licenses in `Sources/KeyboardUI/Resources/LEXICON-LICENSE`; `scripts/lexicon` rebuilds it.
- 16:40 Hit-testing uses the model: likelihood × P(next letter | prefix) over keys within a quarter key of the tap; control keys keep their own taps; the pop-up shows the resolved key. Alone (no learning) this takes raw letter accuracy at σ 0.25 from 72.0% to 88.1%.
- 17:00 "Space when he means b": a space tap between two words is re-decoded as a letter when "about" beats "a" + "out" (posterior vs posterior, no threshold), and a second space (the "." shortcut) before a word likewise ("so. Ut" → "so but"). P(second space) is learned from what you type after a space, starting at 1/2.
- 17:30 First prior (ν₀ = 4, the weakest Wishart) has Student-t₃ tails, which corrected clean real words two keys away ("tie" → "the"). Now keys of a kind (letters, space bar) share your overall spread as their prior, anchored on population tap spread (σ ≈ 0.2 key, Azenkot & Zhai 2012) and worth ν₀ = 10 taps (spread known to ~±30%). σ 0.25 broken words 21 → 15, accuracy 97.7% → 98.0%.
- 18:10 Scorer (Release build in the simulator; (a) nearest key + UITextChecker, (b) decoder with the touch model at its prior, (c) decoder learning). Unbiased, same seed and procedure as the 10-08 table, (a) reproduces it exactly:

  | σ | (a) raw / final | (b) raw / final | (c) raw / final | broken a / b / c |
  | --- | --- | --- | --- | --- |
  | 0 | 100.0 / 99.9 | 100.0 / 99.6 | 100.0 / 99.8 | 2 / 10 / 5 |
  | 0.15 | 99.2 / 99.6 | 99.4 / 99.5 | 99.7 / 99.7 | 2 / 12 / 6 |
  | 0.25 | 72.0 / 89.3 | 88.1 / 98.0 | 88.7 / 98.0 | 2 / 15 / 13 |
  | 0.35 | 35.1 / 59.5 | 60.4 / 92.6 | 60.8 / 92.2 | 1 / 25 / 40 |

  Biased thumbs (m 0.4 key toward n, b 0.55 down into the space bar, o 0.45 toward i, every tap 0.1 low, noise σ 0.2, corpus typed twice, 5,428 words, the simulated user never fixes anything), final accuracy per 500 words:

  | words | (a) | (b) | (c) |
  | --- | --- | --- | --- |
  | 1–500 | 83.2 | 94.6 | 97.2 |
  | 1,001–1,500 | 85.0 | 97.2 | 99.2 |
  | 2,501–3,000 | 87.4 | 97.6 | 98.6 |
  | 4,501–5,000 | 85.8 | 96.6 | 99.4 |
  | all | 85.2 (raw 69.6) | 96.7 (raw 83.3) | 98.6 (raw 89.9) |

  Learned centers after the run: m (−0.41, +0.10), b (−0.01, +0.56), o (−0.45, +0.09), e (0.00, +0.10): the biases it was given, recovered.
- 18:10 Broken words are the cost: the decoder corrects real words when the evidence says so ("tie" → "time" via a missed m, because "time" is frequent in what you've typed; "ides" → "idea"; "presidents" → "president's"). One revert keeps a word forever. British spellings outside the US lexicon get corrected, as with UITextChecker.
- 18:20 Memory (`scripts/memory`: app launched with text in the field so the corrector runs, no XCUITest, iPhone 17 26.3, Mac heavily loaded): old build (UITextChecker) 26 MB idle / 28 MB with suggestions showing; this branch 27 MB / 28 MB, lexicon (2.4 MB, copied out of a mapped file) included. The 46–49 MB jump measured on 10-08 did not reproduce this way even though UITextChecker was answering ("help", "hilo" for "helo"), so the saving from dropping it is unconfirmed; it needs the same typing-based measurement as 10-08 or a device.
- 18:20 Without taps (text already in the field), "helo" gets "help" (substitution at the o's center) over "hello" (missed l); with real taps the touch model decides.
- 18:20 Persistence: memory (words + touch model) lives in the extension's own container, saved when the keyboard disappears. Without Full Access a keyboard can't write the App Group, so the app can't touch that file; "Reset Keyboard Dictionary" bumps a counter in the group's defaults and the keyboard starts over when it sees it moved. Nothing syncs from the keyboard to the app. Whether a keyboard without Full Access can even read the group's defaults (settings rely on it too) needs a device check.
- 18:40 Tests: 73 core (31 new: math, touch model, labels, joins, decoder, language model, lexicon), all pass on macOS and the iOS 26.3 simulator. UI tests on iPhone 17 26.3: 12 of 13 pass; `testExpandsTextReplacements` fails at adding the replacement in the Settings app (line 86, the new entry never appears), and the pre-branch build fails it identically on this simulator today, so it's the Settings flow, not the keyboard.

## 2026-10-09 · over-correction

- 19:30 Rule: a word that stands on its own (kept, or one that you typing it with every tap on its key's center would get read back as itself, by your touches and the lexicon without your word counts) is replaced only when your touches fit the other word better. Frequencies can choose among readings of your fingers but never overrule them. A missed key or apostrophe never counts against a real word, so "tie" stays "tie" however often you type "time", and "presidents" stays plural. A rare word your own perfect taps would still be read past gets no cover. No constant: both tests compare the model's own likelihoods.
- 19:30 Tried and dropped: requiring the replacement to also win without your word counts (robust Bayes). It kept 98.1–98.3% but broke 6–7 words at σ 0.25. A center prior worth 4 taps (κ₀ = 4) changed nothing, so κ₀ stays 1.
- 19:30 Lexicon now includes SCOWL's British and Canadian spellings (137,578 words, 2.42 MB), so "favourite" and "labour" are words, not typos.
- 19:30 Stray spaces: a space typed where no word ended (start of text, after a space) is re-read as the next word's first letter like the "." shortcut's, and a "." shortcut right after a word can be the word's last letter instead ("jo." → "job"; backspace offers "jo." back). The biased run has no more " ut"/"jo." misses.
- 19:30 Scorer, same procedure (broken = correctly typed words changed):

  | σ | (a) raw / final | (b) raw / final | (c) raw / final | broken a / b / c |
  | --- | --- | --- | --- | --- |
  | 0 | 100.0 / 99.9 | 100.0 / 99.9 | 100.0 / 100.0 | 2 / 2 / 0 |
  | 0.15 | 99.2 / 99.6 | 99.4 / 99.7 | 99.7 / 99.8 | 2 / 2 / 0 |
  | 0.25 | 72.0 / 89.3 | 88.2 / 97.3 | 88.2 / 96.5 | 2 / 2 / 2 |
  | 0.35 | 35.1 / 59.5 | 60.4 / 88.8 | 60.9 / 90.3 | 1 / 1 / 7 |

  Biased thumbs, 5,428 words: (a) 85.2% (broken 5), (b) 95.3% (4), (c) 97.4% (2); (c) per 500 words 96.0, 97.0, 96.6, 98.0, 97.0, 97.2, 97.0, 97.8, 97.4, 98.8. Cost of the rule versus the last run: σ 0.25 (c) 98.0 → 96.5, biased (c) 98.6 → 97.4. What's lost is rare lexicon words your touches really did land on ("os" for "is", "mot" for "not"); the suggestion bar still offers the common word.
- Oct 10: Bassim picked A for the suggestion bar: keys and keyboard height exact, the pill stays 27pt (Apple's is 38pt).

## 2026-10-10 · web-demo branch

- 19:30 `KeyboardCore` builds for WebAssembly unchanged (Swift 6.4.0 Wasm SDK). Key metrics, key faces and colors moved from `KeyboardUI` into Core so the web draws from the same numbers; iOS builds and 77 core tests pass.
- 19:45 `web/`: the engine in Wasm (4.2 MB, 1.6 MB brotli; Foundation for saving the touch model would double it, so learning lasts one page visit) plus the lexicon (1.2 MB brotli). Key rects, backdrop top and colors match the iOS 26.3 iPhone 17 reference pixel for pixel; glyphs differ because SF Compact and SF Symbols can't ship on the web (system font and drawn icons instead). The suggestion bar uses Apple's 38pt pill, since a page has no 27pt strip limit.
- 19:45 iOS Safari (simulator, iOS 26.3) loads it with a caret in the field and no system keyboard (`inputmode="none"`).

## 2026-10-10 · web settings

- 20:30 The web demo has a Keyboards sheet (gear, top right) with iOS 27's names and order from Settings › General › Keyboard: Character Preview, Haptic Feedback, then All Keyboards: Auto-Capitalization, Auto-Correction, Predictive Text, Enable Caps Lock, Smart Punctuation, “.” Shortcut. Apple's defaults (haptics off), saved in `localStorage`, fed to the same `KeyboardSettings` the extension reads.
- 20:30 Haptics: iOS Safari has no `navigator.vibrate`. A `<input type="checkbox" switch>` plays the system haptic when a trusted click toggles it, and since iOS 26.5 a script's `label.click()` no longer counts (WebKit fc1ef83), so a transparent label holding a hidden switch covers the keys and the real tap toggles it. iOS makes that click as the finger lifts (measured in the iOS 27.0 simulator: ~35 ms after `touchend`), so the tick comes on key up, not key down like Apple's; long presses and slides make no click and no tick. One toggle per tap for letters, space, delete and shift. Android uses `navigator.vibrate` on key down.
- 20:30 Check Spelling (and Grammar) is left out: with `inputmode="none"` WebKit never draws the misspelling underline, whether text arrives through `setRangeText` or `execCommand("insertText")`, with or without `autocorrect="off"`; it only appeared after the system keyboard had been up.
- 21:30 Check Spelling and Grammar is in the web demo, in iOS 27's place (after Predictive Text, on by default). Safari draws no underline under `inputmode="none"`, so the page draws WebKit's own marker over a mirror of the field: round dots 0.13247 × font size wide with 0.09457 × font size gaps, as many whole dots as fit, centered under the word, top 0.11035 × font size below the baseline, rgb(255 59 48 / 0.75) light and rgb(255 140 140 / 0.85) dark (WebKit `drawDotsForDocumentMarker`, `markerYPositionAndHeightForFont`, `platformSpellingMarkerColor`; matches the iOS 27.0 Safari reference pixel for pixel in color and size). A word is checked once you finish it: the word at the caret stays unmarked while you type it and is checked when you type past it or move the caret. Words come from `Corrector.misspellings(in:)`: not in the lexicon (or its possessive), a name, a replacement or a word you kept. Grammar isn't checked.
