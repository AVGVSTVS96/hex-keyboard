# iikb: words

The source of truth for every word on the site, the link preview, the README and the launch. Numbers come from `copy/facts.json` (`bun copy/facts.mjs` counts them from the repo); the key path follows each one. When a fact changes, rerun it and `rg` every asset for the old value.

## The name

- **iikb**, lowercase everywhere, even starting a sentence or a title. Never IIKB or Iikb.
- The name stands alone: "iikb", "the iikb app". In running text the keyboard is "the keyboard", never "iikb keyboard".
- The name is never explained or expanded.
- Code and IDs keep the old name (`HexKeyboard`, `com.shahidy.hexkeyboard`, `hexkeyboard://`) so installs keep their data. Say so once, in the README's Install, and nowhere on the site.

## Hero

> **iikb**
> An iPhone keyboard that types like Apple's and learns where your thumbs land.

14 words. The demo sits right under it.

## Link preview

- `<title>`: iikb
- meta description: An open-source iPhone keyboard that types like Apple's, looks like Raycast's, and learns where your thumbs land. Try its real engine in your browser.
- `og:title`: iikb
- `og:description`: An iPhone keyboard that learns where your thumbs land. Type with its real engine in your browser.
- `og:image:alt`: iikb, an iPhone keyboard
- OG image text: the wordmark and the hero line, nothing else.

## Site

Six sections. Each is a headline, one short line and a visual, each with a layout of its own. The edge comes first: the keyboard learns your aim, and the numbers show it. Table stakes (autocorrect, emoji, GIFs, clipboard, one-handed) stay in the README.

### 1. Hero: the demo

- Headline: the wordmark, then the hero line.
- Visual: the existing demo in `web/site/`, the real `KeyboardCore` compiled to WebAssembly, as the centerpiece. Field placeholder: "Type here. iikb learns where you tap." The gear opens its Keyboards sheet as it does now.
- Caption under the demo: "The real typing engine, running in your browser. What it learns lasts until you leave the page."

The caption is load-bearing: a visitor can't tell it's the real engine, and the web build doesn't save its learning (PROGRESS.md, Oct 10).

### 2. The number

- Headline: "97.6% of words right, from thumbs that miss." (`accuracy.iikb`)
- Line: "The same taps through the nearest key and Apple's spell checker get 85.2%." (`accuracy.baseline`)
- Visual: a line chart, two lines across the run, one point per 500 words (`accuracy.iikbCurve`, `accuracy.baselineCurve`, `accuracy.blockWords`), y axis from 80% to 100%. iikb's line in the brand color, the baseline in a neutral gray, labeled at their ends, no legend box.
- Footnote: "Simulated thumbs with a steady lean (m toward n, b into the space bar, o toward i, every tap a little low) type the 500 phrases of MacKenzie and Soukoreff's set twice, 5,428 words, and never fix a mistake. Measured by `scripts/eval`; every run is in PROGRESS.md." (`accuracy.phrases`, `accuracy.words`)

### 3. Your aim

- Headline: "It moves with your grip."
- Line: "Miss a key the same way three times and it moves to meet you." (`missesToMoveAKey`, `TypingModelTests.theSameMissThreeTimesRunningMovesTheKeyAndTwoGoodTapsMoveItBack`)
- Visual: the app's Your Taps screen, its Heat view and its Aim view side by side, light and dark. `docs/taps-*.png` are a real phone's taps with the old name in the app; re-shoot from the simulator with made-up but realistic taps.

### 4. Voice

- Headline: "Talk, and it types."
- Line: "Parakeet v3 writes 8.2 seconds of speech in 0.05 seconds on the iPhone's Neural Engine. The sound never leaves the phone." (`voice.speechSeconds`, `voice.writeSeconds`, measured on the iPhone Duo, PROGRESS.md Nov 1)
- Visual: the bar while dictating (the `docs/voice-*.png` crop: an emoji beside the red mic), then the transcript it typed into a message field. Credit NVIDIA's Parakeet and FluidAudio in small type under it.

### 5. Sources

- Headline: "Plug in your own service."
- Line: "A source reads the field you're typing in and answers with a hint above the keys. One JSON request, one answer."
- Visual: the real request and answer from `docs/sources.md` in code type, an arrow to the keyboard showing the hint in the suggestions' place: "This might come across harsher than you mean." Shoot the keyboard from the simulator (`scripts/sourcetest` runs a stand-in source) rather than drawing it.

### 6. Looks, and the iPhone Duo

- Headline: "Raycast's five themes, on every screen." (`themes`)
- Line: "Default, Clear, Physical, Mechanical and iOS 5, fitted to each of the iPhone Duo's screens, folded or open."
- Visual: the five themes as a row (`docs/themes.png`), then the Duo's screens (`docs/duo.png`). `docs/duo.png` shows the old name in the app's header and field; re-shoot it before it goes on the site. Credit Raycast by name under it.

### Footer

- "Open source under MIT. iikb isn't on the App Store; build it from the code on GitHub."
- Links: GitHub (https://github.com/AVGVSTVS96/iikb), PROGRESS.md, docs/sources.md.

## Facts the copy may cite

Each once, where it means the most. Anything not here gets counted into `facts.json` before it's used.

| fact | value | key |
| --- | --- | --- |
| words right, iikb | 97.6% | `accuracy.iikb` |
| words right, nearest key + Apple's spell checker | 85.2% | `accuracy.baseline` |
| phrases, typed twice | 500, 5,428 words | `accuracy.phrases`, `accuracy.words` |
| misses before a key moves | 3 | `missesToMoveAKey` |
| themes | 5 | `themes` |
| haptic strengths | 7, half to twice Apple's | `haptics` |
| emoji | 1,905, and 6,785 words with emoji picked for them | `emoji`, `emojiWords` |
| words it knows | 137,578 | `lexiconWords` |
| KeyboardCore tests | 233, about 25 s on Linux | `tests.core`, `tests.coreSeconds` |
| Parakeet v3 download | about 500 MB | `voice.downloadMB` |
| iOS | 26 and later | `iosMinimum` |

## Words we don't use

supercharge, seamless, effortless, blazing, powerful, magical, revolutionary, unlock, unleash, AI-native, smart (except Apple's own "Smart Punctuation"), em dashes. No feature lists on the site. No personal data: no real dictations, no real tap counts.
