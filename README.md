<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="brand/readme/header-dark.png">
    <img alt="iikb" src="brand/readme/header-light.png" width="838">
  </picture>
</h1>

**The best iOS keyboard. In the world.**

That's what we're building. iikb learns your thumbs, writes what you say, and puts your clipboard, emoji, GIFs and tools beside the words you're typing. Apple and Raycast set a high bar. We want to raise it.

Open source under MIT. For iPhone and iPad on iOS 26 and later, including the Duo folded or open. [See the keyboard layouts and features](https://iikb.vercel.app). iikb is in active development; the ambition is the best keyboard in the world, and the work is public.

| iPhone | iPad |
| --- | --- |
| ![iikb's iPhone keyboard layout](web/site/shots/iphone-light.webp) | ![iikb's iPad keyboard layout with a number row and flick characters](web/site/shots/ipad-light.webp) |

Keyboard layout crops from simulator captures. The app continues to evolve.

## Familiar under your thumbs

Layouts, pop-ups, accents, the space bar cursor and the suggestion bar work as Apple's do, measured against Apple's keyboard in the same simulator on every iPhone and iPad size and each of the Duo's screens, in light and dark. Keys sit where Apple's do, except where the look moves them on purpose: Raycast's bottom-row widths, and on the Duo, keys that grow into the room each screen gives ([docs/design.md](docs/design.md) has every size). Haptics start at the strength Apple's keyboard uses, read off a real iPhone, with three steps softer and three stronger. Settings have Apple's names and defaults, except that auto-capitalization and auto-correction start off. Your Text Replacements still work.

## Make it yours

Five themes inspired by Raycast (Default, Clear, Physical, Mechanical and iOS 5), with controls for key spacing, roundness and haptic strength. The tools sit beside the suggestions, with dictation at the bar's right edge.

![The Default theme](web/site/shots/theme-default.webp)

## Every screen gets its space

iPhone gets familiar key positions. iPad gets a number row and flick-down secondary characters. iikb also fits each of the Duo's screens: the cover upright and on its side, open and held wide or tall, and half folded. Open and held wide, hold 123 to split the keys for two thumbs. The app lays out every page for the screen it's on, in two panes beside the hinge when there's room.

![The expanded Duo keyboard layout](web/site/shots/duo-dark.webp)

## It learns where you tap

Each key remembers where your thumb really lands, from the words you keep and the letters you fix. If your grip changes, it catches up within a few taps. Autocorrect reads every tap with that in mind, and it only changes a word you spelled right when your taps fit another word better.

A test types 500 phrases twice with off-target thumbs. A keyboard that takes the nearest key and corrects with Apple's spell checker gets 85.2% of words right; iikb gets 97.7%. This is a recorded simulated-tap benchmark against a spell-checker baseline, not a comparison with Apple's complete keyboard. [PROGRESS.md](PROGRESS.md) has the numbers and how they're measured.

The suggestion bar combines a small on-device language model with your learned word and phrase counts. It offers completions, next words, and corrections for runs with missed or mistyped spaces. Learning can use the host app when its identity is available.

The app's Your Taps tab shows what it learned: a heat map of where your thumbs press, where each key's taps land, and the keys you miss most.

## Talk instead of typing

Tap the mic beside the suggestions. iOS doesn't let keyboards use the microphone, so the first time, iikb opens its app to start listening, then goes back to your app while you keep talking. The app can keep the mic on for as long as you pick, and while it's on, the mic starts and stops dictation right there, in any app; use the microphone switch in the app to turn it off. Cancel discards a recording without inserting it; its transcript is still kept for review.

What you say becomes text on the iPhone, written by the voice model you pick in the app's Settings › Voice Model: NVIDIA's [Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (the default) or moondream's [Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra), run on the Neural Engine by [FluidAudio](https://github.com/FluidInference/FluidAudio), or Apple's own. Parakeet v3 downloads once, about 500 MB; a dictation made while it gets ready is saved and written once it is. Pick a dictation style, punctuation, editing level and list formatting. The Transcripts tab keeps every transcript with its model, the original words when editing changes them, and available recordings for playback and sharing.

## Emoji

Type a word like "pizza" and its emoji shows up in the suggestion bar; tap it to swap the word for it. The emoji key beside the space bar opens every other emoji, the ones you've picked first, and the keys type into its search, which finds emoji by name and keyword. Hold one for its skin tones. Settings can take the key away, leaving the bar's emoji.

## Sources

A source is a web service you plug into the keyboard. iikb sends it the text of the field you're typing in, in any app, and it can answer with a hint that shows above the keys: a tone check before you send a text, a reminder, anything it can work out from what you're writing. Add one in the app, or by tapping the link it gives you. The API is one JSON request and answer, in [docs/sources.md](docs/sources.md). [`sources/record.ts`](sources/record.ts) is one you can run yourself: it keeps a log of every message you send.

## Also

- GIF search and your clipboard history, from the tools at the bar's left. The app's Clipboard tab shows the same history, pinned items first.
- A number row, Character Preview and skin tones, as Raycast's keyboard has.
- One-handed keyboard: hold 123 and slide left or right.
- Hold the space bar and slide to move the cursor, hold delete to erase whole words, flick down on iPad keys for their second character.
- Return, email, URL and search fields get the keys Apple gives them.
- Typing predictions and Parakeet speech recognition run on device. Network access covers model downloads, GIF search, sources you configure, and a backup server in builds configured with one. Sources receive field text; configured backups can include typing data, clipboard history, transcripts and recordings. See [backup behavior](docs/backup.md).

Swipe typing is in development. Languages other than English aren't available yet.

## Install

iikb isn't on the App Store, so you build it yourself. The code and IDs still use the old name (the `iikb` scheme, `FullKeyboard`, `com.shahidy.iikb`, the `iikb://` links), so an existing install updates in place and keeps what it learned.

On a Mac, with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
open iikb.xcodeproj
```

Put your team in `Config/Team.xcconfig` (`DEVELOPMENT_TEAM = <your team ID>`) and run the `iikb` scheme. On Linux, `scripts/phone` builds and installs it with [AVGVSTVS96/xtool](https://github.com/AVGVSTVS96/xtool), a fork that keeps the app and App Group IDs (stock xtool installs a separate copy and drops the App Group); [AGENTS.md](AGENTS.md) has the details. A different team may need to swap in its own app and App Group IDs.

Then on the phone: Settings › General › Keyboard › Keyboards › Add New Keyboard… › iikb, and turn on Allow Full Access. iikb needs it for haptics, voice, GIFs, the clipboard, Your Taps and sources. The clipboard also needs Settings › Apps › iikb › Paste from Other Apps set to Allow.

## How it's built

| Path | What |
| --- | --- |
| `Packages/KeyboardModules/Sources/KeyboardCore` | Everything the keyboard does: layouts, typing, autocorrect, the tap model, emoji search. Pure Swift with no Foundation or UIKit, so it also runs in the browser as WebAssembly. Unit tested. |
| `Packages/KeyboardModules/Sources/KeyboardUI` | Draws the keys, handles touches and haptics. |
| `Packages/KeyboardModules/Sources/FullKeyboard` | iikb's own keyboard on those: talks to the app, and adds GIFs, the clipboard and sources. |
| `Packages/KeyboardModules/Examples/` | A keyboard of its own built on `KeyboardCore`'s public API, for [docs/build-a-keyboard.md](docs/build-a-keyboard.md). |
| `Keyboard/` | The keyboard extension. |
| `App/` | The app: setup and settings, voice typing, Transcripts, Clipboard and Your Taps. |
| `web/site/` | The product site and keyboard layout showcase. `scripts/site` builds it into `web/dist`. |
| `web/Sources/` | The WebAssembly typing-engine tooling. `scripts/web` compiles the engine alongside the site. |
| `UITests/` | Types through the real keyboard in the simulator. |
| `brand/`, `copy/` | The logo, README header and site images, and the words they use. `bun copy/facts.mjs` counts every number the copy cites. |

Tests:

```sh
scripts/coretest   # KeyboardCore's tests on Linux, no Mac needed (about 25 s)
scripts/check      # builds the app and keyboard for the iPhone on Linux
scripts/test       # on a Mac: KeyboardUI on an iPhone Duo simulator, without the slow autocorrect scorer
scripts/uitest     # on a Mac: types through the real keyboard
```

[AGENTS.md](AGENTS.md) explains the design and the scripts; [PROGRESS.md](PROGRESS.md) is the build log, with every measurement.

## Build your own

iikb's typing engine is yours to build on. Draw the keys your way, and `KeyboardCore` handles Apple's layouts, autocorrect that learns your taps, and the suggestion bar. [docs/build-a-keyboard.md](docs/build-a-keyboard.md) walks through it, and [MinimalKeyboard](Packages/KeyboardModules/Examples/MinimalKeyboard/KeyboardViewController.swift) is a working keyboard in one file.

## License

MIT. See [LICENSE](LICENSE).
