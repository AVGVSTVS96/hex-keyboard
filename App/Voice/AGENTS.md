# Voice typing

A keyboard can't use the microphone (no access, even with Full Access), so voice typing opens the app, which records in the background (`UIBackgroundModes` audio) after starting in the foreground, and hands the text back through the App Group (`Dictation`, KeyboardStore/AGENTS.md).

Voice typing is two steps that never wait on each other, joined by `Listener`: the `Microphone` records, and once you stop, `VoiceModel.write` writes the finished recording down. Recording never waits for a model: the `Microphone` knows nothing of `VoiceModel`, which takes only finished recordings, and the status carries recording and writing apart, so nothing can make a dictation wait to start.

## Opening the app and going back

- The keyboard opens the app by `iikb://dictate` (FullKeyboard/AGENTS.md, "Opening apps and knowing the host").
- `KeyboardHost` names the app you were typing in, in that link, and the app opens it once the microphone is on, with `LSApplicationWorkspace` (all private) or else the app's own link; if that fails its screen asks you to swipe back.
- `HostApp` sends you back to the app the keyboard named, unless that's iikb itself, which iOS would quit, losing a Parakeet still getting ready; then it keeps the microphone on for Keep Mic On so the next dictation starts from the keyboard without opening the app.
- No Live Activity is needed for this, and iikb starts none: iOS shows its own mic indicator.
- Once recording, the app may keep the microphone running in the background (Keep Mic On, up to Until Turned Off, as Wispr Flow's Flow Sessions do). While it does, the mic beside the suggestions starts and stops dictation with Darwin notifications, never opening the app.

## The microphone

- The `Microphone` records a dictation as a `Recording` the moment the keyboard asks (by opening `iikb://dictate`, or with its start signal while the microphone is kept on).
- It's Automatic unless a microphone is picked in Settings › Microphone (`PickedMicrophone`, by port UID, or by name for Bluetooth, whose microphone has another UID than its speaker). Automatic is the iPhone's own microphones through Apple's voice processing, or a plugged-in wired headset; never Bluetooth, which would put a speaker or AirPods on a call and drop music to call quality.
- Voice processing hears you on all of the iPhone's microphones as a call does (on one, the folded Duo in portrait lost seconds of speech at a time).
- While Settings › Microphone's Compare Microphones is on (`-compareMicrophones NO` turns it off for a launch), each dictation the iPhone's own microphone hears, with nothing playing on its speaker, is heard one of three ways at random (`Capture`): voice processing; raw, iOS's microphone in `.measurement` mode; or a cardioid on the front microphone, which iOS forms from more than one, in `.measurement` mode, where the iPhone offers one. The next way is drawn as each dictation stops and the engine starts again in it before the next, never during one. Each transcript keeps its way and its room's and speech's levels as heard, and `python3 scripts/voicehealth.py` ends with each way's dictations and edited words in loud rooms and quiet ones. Leveling before the model is the same for all three.
- Only a picked Bluetooth microphone allows HFP, and only while it's connected; picked and away, the iPhone's hears, and a device coming or going restarts the engine onto the right one, in the same recording.
- Listing what's connected sets the session's category without making it active, and never allows Bluetooth's microphone.
- The iPhone plays the sound itself: voice processing takes the sound from a Bluetooth speaker or AirPlay to the iPhone, and music apps pause, so while one plays it hears from one microphone. A speaker or headphones connecting while voice processing holds the sound turns the microphone off once what's said is written down, since it can't hand the sound over while on.
- While voice processing is on, the engine's output plays the main mixer's silence: voice processing's I/O unit renders its output every cycle, and with nothing connected each render failed (`render err: -1`).

It's resilient, not lossy:
- A route or format change under the engine, or the media services reset, starts the engine again into the same recording; only a failed restart ends the dictation.
- The reset swaps in a new engine even with the microphone off, and a start that fails tries once more on a new engine.
- A failed `open` leaves the audio session inactive.
- The recording takes channel 0 of each buffer, the signal the meter reads.
- A finished recording of a second or more with no sample past 100/32767, or no sound at all, means the input went deaf, so the microphone goes off, Home's switch or not (the next tap opens the app), and the keyboard is told to tap the mic again.
- A dictation being written holds a background task, with an expiration handler, from its stop to its last word.

## The model

`VoiceModel.write` writes with the model you pick in Settings: Parakeet v3 (the default) or Parakeet Ultra through FluidAudio, on the Neural Engine, downloaded once from Hugging Face, or Apple's SpeechTranscriber.
- Apple's never stands in for a Parakeet. A dictation made while the picked Parakeet gets ready (its Neural Engine compile, after each install of a new build and each iOS update, takes 30 s to over 2 minutes) is recorded as any other and written once it's ready; the next one can be recorded meanwhile, and they're typed in the order said.
- Transcribe Again and a recording an ended app left, written as soon as the app starts, go through the same `write`.
- v3 is loaded when the microphone turns on and let go once it's off with nothing left to write, since it loads again in 0.1 s. Ultra, whose every load takes minutes, is kept. The simulator, which has no Neural Engine, never loads one.
- Each transcript keeps the model that wrote it.
- A Parakeet reads the recording leveled (`Recording.leveled`: FluidAudio's Parakeets drop whole stretches of quiet speech) and held to the Latin alphabet (v3 otherwise drifts into Cyrillic).
- What it wrote is then styled, read per field, capitalized and run through the Vocabulary in KeyboardCore (KeyboardCore/AGENTS.md, "Dictation's text").
- `scripts/voicebench` scores a change to that path, or a way to change it (`Tools/VoiceBench`: Dictionary boosting, LocalVQE, other models), on Bassim's own dictations against what each finally became, and on a loud set made from them, by room, mic and how each was heard: `uv run --with numpy scripts/voicecorpus.py` builds both from the backup into `voicebench/` beside it, never the repo, then `scripts/voicebench <corpus> dictation vocab …` runs each way on the Mac and `python3 -I scripts/voicescore.py <corpus> --misses <way>` prints what a way still gets wrong. Nov 5, on 590 dictations: v3 as the app runs it 1.58% wrong; CTC boosting of the Dictionary 1.72% (5.83% at FluidAudio's defaults), LocalVQE first 4.33%, Phonon-2 4.73%, Bark 3 4.87%, each worse in loud rooms too.

Measured on the iPhone Duo (iOS 27.2):
- v3's encoder compiles for the Neural Engine in about 17 to 37 s after each install of a new build and loads in 0.1 s after. That compile has iikb write about 500 MB (Core ML writes out the encoder's 425 MB of weights to compile them), against iOS's 1 GB a day before it files a disk-writes report: 4.3 GB in 97 minutes of installs on Nov 4. So `scripts/phone` installs only when something iikb is built from has changed. `HostApp.written` logs what iikb has written since it started with each load and dictation.
- Core ML keys what it compiles by the OS build, by the literal path a model loads from, and, for the parts loaded for the Neural Engine (encoder, decoder, joint), by the install. The app's own container moves to a new path with every install, so the Parakeets live in the App Group's container (`Library/Application Support/FluidAudio`, which the backup skips; `AsrModelVersion.folder` moved them over by rename and cleared Core ML's stale cache), whose path installs keep: that keeps the CPU-only preprocessor's compile and Core ML's path entries, but the other three compile again after every install (Nov 5, builds 448 to 458).
- Ultra's int8 encoder never caches there and takes 3 to 6 minutes, hot, every load (`scripts/voiceprobe`; FluidAudio #1022).
- Parakeet Unified, the English Parakeet Anomaly's iikb uses, gets 15% fewer of Bassim's words wrong than v3 (2.06% to 2.41% with um and uh set aside) but isn't offered: in FluidAudio 0.18.0 on the Duo it never runs on the Neural Engine, taking 77 s (int8) or 51 s (fp16) to load after a first compile of 5 to 8 minutes, and 9 to 16 s to write 37 s of talking, where v3 takes 0.05 s.

## The app's timers

The only ones (rule table, root AGENTS.md):
- Keep Mic On's countdown.
- The second a stop waits for quiet before it cuts.
- One clock reading: a Parakeet that takes over 0.5 s to write a second of silence is taken to be off the Neural Engine and loaded again, up to three times (`VoiceModel`).
