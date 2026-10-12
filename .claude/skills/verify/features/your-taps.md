# Your Taps

## Sub-features

The app's Your Taps screen: the keyboard at real size with each key's learned aim (recent taps as dots, the ellipse holding half its taps, the line from the key's center to the aim), an Accuracy view (share of taps landing on the key meant, and for a selected key, where its taps land), the stats row and Most missed.

## How to get to it (user POV)

Hex app › Your Taps. It fills in once the keyboard has Full Access and has closed after typing: the keyboard writes `touches.json` to the App Group and posts a Darwin notification the screen listens for.

## Driving it

`scripts/mac 'scripts/sim taps "iPhone 17 Pro Max" iPhone-17-Pro-Max <touches.json> <tag>'` copies a touch model into the simulator's App Group and screenshots Aim, Aim with a key, Accuracy and Accuracy with a key (`KEY=p` by default), light and dark. A phone's model comes from `typing-memory.json` in the keyboard's container (`devicectl device copy from --domain-type appDataContainer --domain-identifier com.shahidy.hexkeyboard.keyboard`), its `memory.touches` object. The numbers come from `TouchModel.aims(on:)`, covered by `TouchModelTests`.

## Gotchas

Memory saved before `recent` existed has no dots; they appear as new words are kept. Keys with fewer than 10 taps stay out of Most missed, since the 10-tap prior on spread still outweighs them.
