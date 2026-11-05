# Voice typing

## Sub-features

The mic at the bar's right end, always there. With the app's microphone off, a tap opens the iikb app (`iikb://dictate`), which starts recording and then reopens the app you were typing in (`HostApp`: the keyboard names its host in the link, from UIKit's keyboard arbiter (`KeyboardHost`), and the app opens it with `LSApplicationWorkspace` or the app's own link; if both fail, its screen asks you to swipe back). While listening the suggestions give way to a waveform of your voice with the time, and the mic becomes a red stop button; a tap stops, and once the voice model has written it down it's typed, joined to the text before it with a space. While it's being written the mic shows a spinner and a tap starts the next dictation; they're typed in the order said. Without Full Access the bar says so instead.

Keep Mic On (Settings: Off, 30 Seconds, 1 Minute, 5 Minutes (default), 15 Minutes, 1 Hour, Until Turned Off): after a dictation the app keeps the microphone running in the background for that long, dropping its audio, and holds `Library/mic.lock` in the App Group. While the lock is held the mic has a green dot and a tap sends `Dictation.Signal.start`, so the app doesn't open; holding the mic turns the microphone off. Another app taking the microphone (a call) or the engine stopping on a route change turns it off at once.

## How to get to it (user POV)

Tap the mic beside the suggestions, talk, tap it again.

## Driving it with XCUITest

`scripts/voicetest` runs `VoiceTests` with `scripts/voiceapp.py` standing in for the app (a simulator can't record): the mic shows Mic On, a tap starts listening, a tap stops it and the mic shows Writing, a tap then starts a second dictation while "hello from the mic" is typed, a tap types "and again" after it, a hold turns the microphone off and leaves the mic. On a phone: watch `Dictation`'s status with `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.com.shahidy.iikb --source Library/dictation.json` (it lives under Library because devicectl reads only Library, Documents and tmp), and the app's return with `log stream --predicate 'subsystem == "com.shahidy.iikb"'`.

## Gotchas

Only one app can record at a time: a call that takes the microphone ends Keep Mic On. While the microphone stays on with AirPods connected, they stay in their call mode (Bluetooth HFP), so music through them sounds like a phone call until it turns off. Opening the app from the keyboard isn't public API (App Review 4.4.1); it works through the responder chain.
