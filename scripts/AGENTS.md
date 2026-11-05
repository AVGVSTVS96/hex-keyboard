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
- then starts iikb in the background, now or the moment the iPhone next unlocks (`scripts/unlocked`, left running on the Mac, which watches SpringBoard's lock state), so Parakeet's compile for the new install begins then rather than at the next dictation.

It needs:
- Swift 6.4.
- xtool built from [AVGVSTVS96/xtool](https://github.com/AVGVSTVS96/xtool). It signs with the real bundle and group IDs, so it updates the installed app and keeps its data, where stock xtool installs a separate `XTL-…` copy; and it keeps the App Group on free teams, which stock xtool drops, so iOS deletes the group's container.
- xtool's Darwin SDK: `xtool sdk install --slim` on an Xcode whose iPhoneOS platform also holds Xcode-beta's `iPhoneOS27.1.sdk`. The fork picks the newest iPhoneOS SDK for `arm64-apple-ios` and puts `-Xclang-linker -isysroot -Xclang-linker <its path>` in the bundle's `toolset-swb.json`. Never rebuild xtool while others build, since a rebuild that changes its Anisette provider logs it out.
- `xtool auth login`, and the iPhone paired with the Mac.

Linker facts:
- The keyboard target links with `-ObjC` because its principal class is only named in Info.plist.
- On Linux the Swift driver hands clang `--sysroot`, and clang reads an SDK's version only from `-isysroot`, so without that option the binaries record the deployment target (26.0) as their SDK. iOS 27.1 then runs iikb on the iPhone Duo as an old iPhone app, small and without the vertical bar, which the simulator never showed. `scripts/phone` refuses a build linked below 27.1, and `scripts/mac` runs everything on the Mac with Xcode-beta (27.1) so the simulator shows what the phone does.

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
