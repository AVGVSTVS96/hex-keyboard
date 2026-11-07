# Transcripts

## Sub-features

Every dictation is kept, newest first, in the app's Transcripts tab: typed ones, and ones canceled in the app's dictation screen (marked "Canceled, not typed"). Each keeps its sound (`Recording`, a 16 kHz WAV written as it's heard, so a recording an ended app left is written down on the next launch), the model that wrote it and the microphone it came from. Words, time talking and pace overall, words a day for the last two weeks (today's bar in full color), grouped by day, search, a context menu with Copy, Share Text, and under Recording, Send in Messages and Share Recording, and Delete, a detail page with the full text, its facts, Transcribe Again (the model picked now) and Delete, and Delete All in the … menu. Held wide on the open Duo the picked transcript shows beside the list. Stored as one JSON line each in the app's own container (`Library/Application Support/transcripts.jsonl`, sounds up to 512 MB); the keyboard never reads it.

## How to get to it (user POV)

Dictate with the keyboard's mic, then open iikb › Transcripts.

## Driving it with XCUITest

Not driven yet: dictation needs a real microphone. Screenshots: `TRANSCRIPTS=<transcripts.jsonl> PAGES=transcripts scripts/mac 'scripts/sim duoapp <tag>'` copies one into the app's container and shoots the tab on the Duo's screens; on another simulator copy it into `Library/Application Support/` of `xcrun simctl get_app_container <id> com.shahidy.iikb data` and launch with `-iikbTab transcripts`.

Sending a recording: `scripts/mac scripts/sharetest` puts a made-up transcript and its sound in the app, then opens its menu and its page and taps each way out, light and dark (`RecordingShareTests`). The simulator can't send messages, so Send in Messages shows the share sheet there; only the iPhone shows the message.

## Gotchas

Cancel keeps whatever was recorded, written down but not typed; a dictation with nothing said keeps nothing, its sound included.
