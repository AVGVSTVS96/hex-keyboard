# Voice typing

## Sub-features

The 123 menu's mic: the keyboard opens the Hex app (`hexkeyboard://dictate`), the app listens and transcribes on the iPhone (SpeechTranscriber, or DictationTranscriber with punctuation where the iPhone lacks it), you go back to your app, the keyboard shows Listening with Done and ✕ in place of the keys, and Done types what was heard, joined to the text before it with a space. Without Full Access the keyboard says so instead.

Keep Mic On (Settings: Off, 30 Seconds, 1 Minute, 5 Minutes (default), 15 Minutes, 1 Hour): after a dictation the app keeps the microphone running in the background for that long, dropping its audio, and holds `Library/mic.lock` in the App Group. While the lock is held the keyboard's mic sends `Dictation.Signal.start` and the app starts listening in place, so the app doesn't open. The countdown restarts after each dictation; another app taking the microphone (a call) or the engine stopping on a route change turns it off at once.

## How to get to it (user POV)

Hold 123, slide to the mic, let go. Talk, swipe back to your app, tap Done.

## Driving it with XCUITest

Not driven yet: the simulator records from the Mac's microphone. `EmojiTests.dictationJoinsWhatsThereWithASpace` pins what the engine types. On a phone: watch `Dictation`'s status with `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.com.shahidy.hexkeyboard --source Library/dictation.json` (it lives under Library because devicectl reads only Library, Documents and tmp).

## Gotchas

Only one app can record at a time: picking voice during a hex voice call interrupts the call's microphone, and a call that takes the microphone ends Keep Mic On. While the microphone stays on with AirPods connected, they stay in their call mode (Bluetooth HFP), so music through them sounds like a phone call until it turns off. Opening the app from the keyboard isn't public API (App Review 4.4.1); it works through the responder chain.
