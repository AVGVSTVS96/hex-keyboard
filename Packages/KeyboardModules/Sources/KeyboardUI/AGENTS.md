# KeyboardUI

UIKit, the parts any keyboard can build on, with no private API. Keyboard behavior lives in KeyboardCore; this module only draws, plays feedback and forwards events.

## The keys

- `KeyboardView`: one view owns all touches: rollover, slide-off, callouts, long-press accents, the spacebar trackpad, iPad flicks, and swipes.
  - A touch that began on a letter in the letters layer and has gone 0.8 key widths from where it began, past the neighboring key a tap's drift never reaches, stops being a key, collects its path from every coalesced sample, and sends `.swipe` when it lifts or when another finger lands.
  - `TrailView` draws the thin fading line behind it in the theme's prominent color, never touching the keys.
  - The top row takes taps over the bar's bottom edge (docs/design.md, "Where taps land"), so a reach for it types its key, never picking a suggestion or opening a panel.
- `HostText`: the body font most fields draw in, so the trackpad moves the caret a character for as far as the character is wide. Up and down move a sentence for each row of keys the finger crosses (`Sentences`, in KeyboardCore).
- `KeyView`.
- `KeyHaptics`: Apple's keyboard haptic values, played with public Core Haptics on an engine the keyboard owns. While any app records, iOS mutes every app's haptics unless the recording session allows them, so `Listener` does, or Keep Mic On silences the keys.

## The bar

- `SuggestionBar`: Apple's three suggestions, the last giving way to the word's emoji when it has some, as many as fit and the rest a swipe away, the tools at its left, and `MicButton`, a round button always at its right end, set out as the top row's keys are (`BarLayout`, KeyboardCore).
- The mic: tap to dictate (opening the app while its microphone is off), tap again to stop. Nothing in the keyboard turns the microphone off, only Home's switch or Keep Mic On running out.
  - While the app listens the mic grows into a red capsule over the suggestions holding the time and a waveform of the levels it publishes, after a cancel button, which throws away what's being recorded so it's never typed (`Dictation`'s `cancel`; Transcripts still keeps it).
  - Once you stop, dictations still waiting for the model stack as cards, the next with its length, beside what it's doing.
  - Stopping plays the stop animation Settings › Appearance picks (`StopAnimation`): Squeeze (the bars rush into the mic, a ring and a check while it writes), Drain (the red pours into the mic, which glows while it writes) or Card (the recording folds into a card that lifts off the keyboard's top). Cancelling turns the recording to dust (`Dust`).
- `BarButton`: the More button or a tool at the bar's left, one per panel. The emoji panel opens from the emoji key beside space on iPhone, which Settings can take away.
- `PanelView`: a panel in place of the bar: a `PanelContent`'s results over a back button and a search field the keys type into. `EmojiPanel` is the emoji one.

## For the app

- `KeyboardPreviewView`: the keyboard as some settings make it look, drawn by the keyboard's own views, for the app's preview.
- `KeycapSwatchView`: a theme's A and B keys, for its picker.
- `TapMapView`: the keyboard drawn with what the touch model learned (Heat, Aim, Accuracy), and `TapCharts` (the heat ramp, a key's close-up and the thumbs' pull arrows).

## iOS facts

- Keycaps use SF Compact, loaded from the system font file, because that is what the system keyboard uses (verified by glyph metrics) and UIKit has no public name for it. It falls back to SF Pro.
- iOS 26 ignores a plain height constraint on the input view; the height comes from Auto Layout content (`keyboardHeightConstraint`).
- A third-party keyboard can't draw above its own area, so top-row pop-ups are clamped into the space above the keys, where they draw over the bar.
- iOS doesn't deliver touches that land on fully transparent pixels of a third-party keyboard. `KeyboardInputView` has an invisible fill (alpha 0.001, pixel-identical in screenshots) so gaps between keys still take taps; `FirstTapTests` checks it.
