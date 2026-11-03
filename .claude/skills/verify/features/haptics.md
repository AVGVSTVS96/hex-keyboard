# Key haptics

## Sub-features

A tap on every key press, played with Core Haptics on an engine the keyboard owns (`KeyHaptics`), at seven strengths from Lightest (half of Apple's) to Strongest (twice), with Standard in the middle as Apple's keyboard's own tap (`HapticFeedback`), or off. The slider taps at each step as you move it. Haptics keep playing while the app's microphone is on. They need Full Access.

## How to get to it (user POV)

Hex app › Settings › Keyboard › Sound & Haptics › Touch and Sound: Key Haptics, and the Strength slider under it. The Hex tab's Sound & Haptics card opens the same page.

## Driving it

`HapticFeedbackTests` (package) pins the seven levels, Standard in the middle and each stronger than the last. The simulator plays no haptics, so how they feel is checked on a phone (`scripts/phone`).

## Gotchas

While any app records, iOS mutes every app's haptics unless the recording session allows them; `Listener` allows them, so Keep Mic On doesn't silence the keys.
