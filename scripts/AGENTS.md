# scripts

The command list is in the root AGENTS.md, "Build and test". This is how the bigger ones work.

## Simulators

- `scripts/sim` creates its own `iikb<slot> …` simulators and enables the extension by writing `AppleKeyboards` (and, for iPad, `AppleKeyboardsExpanded = 1`) into the simulator's global preferences, so no Settings UI is needed.
- Simulators boot headless; the Simulator app never opens.
- Reference screenshots of Apple's keyboard come from the same simulators with `KEYBOARDS=system`.
- Builds are ad-hoc signed for the simulator (`CODE_SIGN_IDENTITY = -`), which embeds simulated entitlements, so the App Group works in the simulator without a team. Device builds need a team with the group `group.com.shahidy.iikb` registered.

## scripts/phone

It builds the app and keyboard with [xtool](https://github.com/xtool-org/xtool) from the root `Package.swift` and `xtool.yml` (their Info.plists are `Config/xtool/`, kept in step with `project.yml` by hand), and:
- signs them with a free-team profile that xtool renews on every run. It covers every device the team has registered; a new phone gets registered by one direct `xtool install` to it.
- stamps main's commit count as the build number (Settings › About shows it); an iPhone that already has that build is left alone.
- installs them through the Mac with `devicectl` on the iPhone the Mac reaches, by cable or Wi-Fi, once the running app's status in the App Group (`Dictation.Status`) says no dictation is being recorded or written down, checked last thing before the install, after the backup, so an install never cuts off a dictation.
- installs nothing that fails `scripts/gate` (the bar) or then `scripts/formats` (dictation's versions, decimals, percentages and addresses), each run on the commit it builds; the second reuses the first's build, so it adds seconds.
- then starts iikb in the background, now or the moment the iPhone next unlocks (`scripts/unlocked`, left running on the Mac, which watches SpringBoard's lock state), so Parakeet's compile for the new install begins then rather than at the next dictation.

It needs:
- Swift 6.4.
- xtool built from [AVGVSTVS96/xtool](https://github.com/AVGVSTVS96/xtool). It signs with the real bundle and group IDs, so it updates the installed app and keeps its data, where stock xtool installs a separate `XTL-…` copy; and it keeps the App Group on free teams, which stock xtool drops, so iOS deletes the group's container.
- xtool's Darwin SDK: `xtool sdk install --slim` on an Xcode whose iPhoneOS platform also holds Xcode-beta's `iPhoneOS27.1.sdk`. The fork picks the newest iPhoneOS SDK for `arm64-apple-ios` and puts `-Xclang-linker -isysroot -Xclang-linker <its path>` in the bundle's `toolset-swb.json`. Never rebuild xtool while others build, since a rebuild that changes its Anisette provider logs it out.
- `xtool auth login`, and the iPhone paired with the Mac.

Linker facts:
- The keyboard target links with `-ObjC` because its principal class is only named in Info.plist.
- On Linux the Swift driver hands clang `--sysroot`, and clang reads an SDK's version only from `-isysroot`, so without that option the binaries record the deployment target (26.0) as their SDK. iOS 27.1 then runs iikb on the iPhone Duo as an old iPhone app, small and without the vertical bar, which the simulator never showed. `scripts/phone` refuses a build linked below 27.1, and `scripts/mac` runs everything on the Mac with Xcode-beta (27.1) so the simulator shows what the phone does.

## scripts/voiceloop

Dictation from the sound to what the keyboard types, scored against what it should have typed, so a fix to any part of it is chosen and checked by numbers:
- Three sets, in `voicebench/` beside the backup, never the repo: real, Bassim's dictations against what each finally became (`scripts/voicecorpus.py`, which also takes the kind of field and the text before it from the record source's log); loud, the quiet ones mixed into his loud rooms, as said and up to 18 dB quieter (picked by a hash of each id, so new dictations seldom change which, and a new loud dictation changes the room's sound, so all of them go through Parakeet again); and spoken, `scripts/voicespoken.txt`'s made-up sentences (emails, phone numbers, codes, model versions, links, times, money, names), each with what iikb must type, said by three of six macOS voices in a quiet room, in his loud room and 18 dB softer there, and by Whisper in both. Its `{name}` lines are said with stand-ins and with names from his Dictionary, filled in outside the repo.
- Parakeet v3 writes each clip on the Mac as the app runs it (`Tools/VoiceBench`, in a turn), once per clip and version of that path: `voicebench/cache/` keeps what it wrote by the clip's sound and a hash of Tools/VoiceBench's code, links followed, so only new clips or a changed Parakeet path reach the Mac, and `--cached` leaves new clips out.
- The rest of the iPhone's path runs here (`Tools/VoiceBench/Text`, on a package of KeyboardCore alone): the app's writing style and Dictionary, then the keyboard's `.dictated` in a field of that kind after the text before it and with the keyboard's saved memory (the words you type, which fix ones Parakeet mishears), with the iPhone's settings from the backup for his sets and the defaults for the spoken one.
- Each set prints words wrong (um and uh, case and punctuation aside) and dictations typed exactly, by group: room, mic and kind of final for real; level for loud; condition, voice, topic, field and name for spoken. Real also scores what the iPhone typed (`phone`) and the bench's text stage on the iPhone's own Parakeet output (`replay`), and counts how often each matches the iPhone's.
- Against his finals, which keep whatever the build of their day typed and lack what he cut after, four or more words in a row a final lacks ("cut later") and the same number in another form ("number form") are set aside, his references go through the Dictionary as a dictation does, and punctuation and capitals count only against finals the keyboard followed (build 479 on).
- Every remaining error is labelled by what the reference had there (emails, links, versions, times, money, digits, names, else words misheard, dropped or added) and ranked in `voicebench/categories.txt` with examples, and each dictation's texts go to `voicebench/<set>/loop.jsonl`.
- Nov 5: real 3.58% wrong (the iPhone 3.58%; the bench's Parakeet wrote what the iPhone's did on 579 of 619, and its text stage typed what the iPhone did on 202 of 216, the other 14 each a fix landed since), 9.54% in loud rooms; spoken 16.2% in a quiet room, 26.6% in a loud one, 34.5% whispered. Cold, with every clip said and written, about 11 minutes, most of it waiting for the Mac's turn and Parakeet's 5.5 minutes; warm about 15 s, 30 s once new dictations rebuild the real set, and about 30 s more after a change to KeyboardCore. One run at a time: a second waits for the first, since they share `voicebench/`.

## scripts/eval

It types the MacKenzie & Soukoreff phrase set (500 phrases, 2,714 words) through `TypingEngine` with taps drawn from a Gaussian around the real key centers (`KeyGrid`, iPhone 17 width), seeded, and prints word accuracy without and with autocorrect and the top-3 suggestion hit rate, for three keyboards: (a) nearest key + `UITextChecker`, (b) iikb's decoder with the touch model held at its prior, (c) the decoder learning.

Its runs:
- `noise` reruns the original noise levels.
- `biasedThumbs` types the corpus twice as a user whose m, b and o land off target and prints a learning curve.
- `aimShift` types it once that way, then again after the user's aim moves (lower and right, o and e swinging the other way), and prints how fast the learning keyboard follows.
- `missedSpaces` types two, three and four words in a row from each phrase with every space's tap landing on the row above the space bar, and two and three with the spaces never typed, and prints how often the key map reads a tap as the space anyway, and how often the bar offers the words when it reads none.
- `predictions` scores the suggestion bar before each word (is the next word in the top 3, is it first) on the phrase set and on `chat.txt` (1,000 sentences from Taskmaster-1 user turns), for a new user and one whose memory keeps every phrase.
- `swipe` (not part of a full run, since it needs the 570 MB of swipe.futo.org's test and validation splits from `scripts/swipe data`) decodes the 48,355 test swipes whose word is letters and apostrophes through `Swipe.decode` and prints top-1/3/10 from the encoder alone and with the decoder, against iikb's lexicon and against it with every target added at a fixed frequency (the report adds them too; how common they're made moves top 1 by 2 points, so each of three is printed). It's diffed against eval.expected's `EVAL swipe` lines alone.
- `swipeTune` fits `Swipe.Scoring` on the validation split.

It runs a Release build (the decoder is slow in Debug), here on Linux in a package of KeyboardCore, the word lists and `Evaluation` alone, which gives the same numbers as the Mac; only the baseline needs `UITextChecker`, so its lines are scored on the Mac (`scripts/mac scripts/eval`). A full run is diffed against `scripts/eval.expected` (the root AGENTS.md's rule table says what a change that moves the numbers owes).
