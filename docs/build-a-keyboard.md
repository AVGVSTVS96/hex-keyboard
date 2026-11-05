# Build a keyboard on iikb

iikb's typing lives in `KeyboardCore`: Apple's layouts and key sizes for every iPhone and iPad, shift and caps lock, autocorrect that learns where each thumb lands, and a suggestion bar. It's pure Swift, so you draw the keys however you like and the engine does the rest. `KeyboardUI` is iikb's UIKit side: its keys, bar and panels, and the bridge to the host's text field.

There are two ways in:

- **All of iikb.** Subclass `HexKeyboardViewController` and you get the keyboard as it ships.
- **Your own look.** Draw your own keys and pass touches to `TypingEngine`. [`Examples/MinimalKeyboard`](../Packages/HexKeyboard/Examples/MinimalKeyboard/KeyboardViewController.swift) does this in one file of about 240 lines.

## Add the package

The package is in a subfolder (`Packages/HexKeyboard`), and Swift Package Manager can't take a git URL for a package that isn't at the repository's root. So add the repository as a submodule:

```sh
git submodule add https://github.com/AVGVSTVS96/iikb
```

Then in Xcode, choose File › Add Package Dependencies… › Add Local…, pick `iikb/Packages/HexKeyboard`, and link `KeyboardCore` and `KeyboardUI` to your keyboard extension. You need iOS 26 and Swift 6.2 or later.

## All of iikb

```swift
import KeyboardUI

final class KeyboardViewController: HexKeyboardViewController {}
```

This is iikb itself (`Keyboard/KeyboardViewController.swift`), including the parts that belong to iikb's app. The keyboard keeps its settings and what it learns in the App Group `group.com.shahidy.hexkeyboard`, opens its settings at `hexkeyboard://`, and hands voice typing to iikb's app. Unless you ship that app with those IDs, take the second way.

## Your own look

Start from the example. These are the steps it takes, in order:

**1. An engine with a dictionary.** iikb's English dictionary and next-word model come with `KeyboardUI`.

```swift
var engine = TypingEngine()
engine.corrector = Corrector(source: Lexicon.english, network: .english)
lazy var document = ProxyDocument { [unowned self] in textDocumentProxy }
```

**2. The field.** On `viewWillAppear`, `textDidChange` and `selectionDidChange`, tell the engine about the field, and about any change to its text the engine didn't make:

```swift
engine.update(InputTraits(textDocumentProxy))
engine.documentChanged(document)
```

The engine keeps its own copy of the text around the caret (`engine.text`). It changes the field only through `document`, and it never trusts a late report from the host over that copy.

**3. The keys.** Ask the engine which layout fits the screen, then lay it out:

```swift
let context = engine.layout(on: device, screen: size, showsGlobe: needsInputModeSwitchKey)
let layout = Layouts.layout(for: context)
let metrics = KeyboardMetrics.for(context, screen: size, window: view.bounds.width, style: .current)
let grid = KeyGrid(layout, width: view.bounds.width, metrics: metrics.grid, signature: context.signature)
engine.use(grid)
```

`grid.rows` holds each key's frame. `KeyFace(key, trailing:, context: engine.faces(on: device))` gives each key's label: a letter, a word, or an SF Symbol name. `KeyboardTheme` gives the colors: `.light(.current)` and `.dark(.current)` are Apple's, and `KeyboardTheme.named(.mechanical, dark: dark, style: .current)` gives one of iikb's five themes (`ThemeName`). Set your keys view's height to `metrics.height(rows:hasNumberRow:)` and the bar's to `metrics.toolbar.height`.

**4. Touches.** Find the key under a finger with `engine.key(atX:y:in: grid)`, not with the frames. It reads the touch model, so a tap where your thumb usually lands for a key goes to that key. Then send:

| When | Event |
| --- | --- |
| a finger lands | `.down(key, tapCount: touch.tapCount)` |
| it lifts on a letter, a symbol or space | `.type(key, Tap(x:y:key:))`, where the tap is where the finger lifted |
| it lifts on any other key | `.trigger(key)` |
| always, after either | `.up(key)` |

`engine.handle(event, in: document)` returns whether anything changed, so you know when to redraw. Shift, caps lock, delete and the layer keys (123, ABC, #+=) act on `.down`, as Apple's keys do. When a second finger lands, finish the keys still held down first, or fast typing comes out of order.

Three keys are yours to handle: the globe (`.nextKeyboard`) calls `advanceToNextInputMode()`, the iPad's hide key (`.dismiss`) calls `dismissKeyboard()`, and the record key (`.dictate`) appears only with `engine.settings.micKey`. The emoji key beside an iPhone's space bar opens the engine's emoji panel. While it's open (`engine.panel`), the keys type into the panel's search (`engine.query`) until return closes it. Draw the panel, or turn the key off with `engine.settings.emojiKey = false`, as the example does.

**5. Suggestions.** With `engine.defersSuggestions = true`, the engine leaves its suggestions stale for you to rank off the main thread:

```swift
guard engine.suggestionsAreStale, let job = engine.suggestionJob() else { return }
Task.detached { [weak self] in
    var job = job
    job.run()
    await self?.finish(job)
}
```

`finish`, on the main actor, calls `engine.finish(job)`, then shows `engine.suggestions` (each one's `title`, while `engine.showsSuggestions` is true). A tap on one calls `engine.accept(suggestion, in: document)`. A job can finish after the keyboard has gone, so draw only between `viewWillAppear` and `viewWillDisappear` (see below).

**6. Learning.** Call `engine.endSession()` in `viewWillDisappear`, so the keyboard learns from the last words you kept. Everything it has learned is `engine.corrector?.memory`, a `Codable` `TypingMemory`. Save it, and put it back with `engine.corrector?.changeMemory { $0 = saved }`. To pick up the person's Text Replacements and contact names:

```swift
engine.corrector?.learn(await requestSupplementaryLexicon())
engine.suggestionsChanged()
```

## What iOS requires

- iOS doesn't send a keyboard the touches that land on fully transparent pixels. Give the view under your keys a fill (`UIColor(white: 0, alpha: 0.001)`), or taps between keys go nowhere.
- The keyboard's height comes from the Auto Layout constraints of what's inside it. iOS ignores a plain height constraint on the input view.
- Once `viewWillDisappear` runs, iOS tears down `textDocumentProxy` while your controller lives on, and reading it then crashes. A ranking or layout pass that lands later must draw nothing.
- A keyboard can't draw above its own frame, and can't use the microphone.
- Haptics, the network and writing to a shared App Group need Allow Full Access, which you turn on with `RequestsOpenAccess` in the extension's Info.plist.

## What the example leaves out

These all live in `KeyboardUI`'s `KeyboardView`, which isn't public yet: holding delete to repeat, the pop-up over a pressed key, accents on a long press, the space bar trackpad and Slide to Type. If you need them now, subclass `HexKeyboardViewController`. For haptics, `KeyHaptics` plays Apple's keyboard haptics: `start()` it in `viewWillAppear`, `play(.input)` as a key goes down, and `stop()` it in `viewWillDisappear`.

Linking `KeyboardUI` turns on UIKit's private keyboard arbiter when an extension loads (`KeyboardArbiter`). iikb uses it to learn which app it's typing in. `KeyboardCore` uses no private API. A keyboard that links `KeyboardUI` runs on your own devices, but App Review may reject it.

## Run it

1. In Xcode, create an iOS App. Then choose File › New › Target… › Custom Keyboard Extension.
2. Add the package as above, and link `KeyboardCore` and `KeyboardUI` to the extension.
3. Replace the template's `KeyboardViewController.swift` with the example's.
4. Run the app. On the phone, go to Settings › General › Keyboard › Keyboards › Add New Keyboard… and add yours.

## Test on Linux

`KeyboardCore` imports no Foundation or UIKit, so it builds anywhere Swift 6.3 or later runs:

```sh
swift build --package-path Packages/HexKeyboard --target KeyboardCore
scripts/coretest   # its tests, in a package of KeyboardCore alone, since the other targets need UIKit
```

## Where things are

| Types | What they are |
| --- | --- |
| `TypingEngine`, `KeyboardEvent`, `TextDocument` | the engine, what it takes, and the field it edits |
| `Layouts`, `LayoutContext`, `KeyboardMetrics`, `KeyGrid` | which keys appear, how big they are, and where |
| `KeyFace`, `KeyboardTheme`, `ThemeName` | what a key shows, and in what colors |
| `Corrector`, `Lexicon`, `TouchModel`, `TypingMemory` | autocorrect, the dictionary, where you tap, and what's learned |
| `ProxyDocument`, `InputTraits(_:)`, `Corrector.learn(_:)`, `KeyboardStyle.current` | `KeyboardUI`'s link to UIKit |
| `Lexicon.english`, `Network.english` | the English dictionary and next-word model |

[AGENTS.md](../AGENTS.md) explains how each piece works and why.
