# App

The containing app, in Raycast's look (`AppStyle`, `Components`: black pages, near-black cards, radio marks; docs/design.md, "The app"), with titles and big numbers in Helvetica Neue (`AppStyle.display`, `Font.display`; `brand/BRAND.md`).

- A folder per feature (Voice, Transcripts, Stats, Settings, Dictionary); a piece more than one feature uses goes in `Design/`.
- Five tabs in the system tab bar, which iOS 27.1 puts in the iPhone Duo's vertical bar.
- Every page but Settings has the microphone's switch in its header: on keeps it on until you turn it off there; off lets it go once what's said is written down (`MicSwitch`, `Listener.turnMicOn`, `turnMicOff`).
- Each page is laid out by the width it gets, never the device or the fold (`Arrangement`, `Panes`): from 750 points (the open Duo in landscape, an iPad either way up, a wide iPad window), two panes, halves or a list up to 480 wide beside the page it picked; narrower, one column.
- `ThisDevice` names the device in what the app says (iPhone or iPad) and knows an iPad has no haptics; Appearance shows only the layout settings KeyboardCore applies on this device (`KeysHere`).
- `scripts/sim ipadapp` (UITests/AppShots) screenshots the pages on iPads, turned and in windows dragged to Split View and Stage Manager sizes.
- `Router` opens a tab and settings page from another.
- `Settings.bundle` has the keyboard's switches in Settings › Apps › iikb.
- `scripts/sim duoapp` screenshots every screen of it on the Duo's four screens.

Voice typing, the app's biggest part, has its own doc: Voice/AGENTS.md.

## The tabs

- **iikb**: whether the keyboard is on, a field to try it, the setup switches iOS keeps until they're on, cards for today's dictation and your taps, and one for each setting reached for most, Dictionary first, opening its page in Settings.
- **Transcripts** (`TranscriptsPage`): `Transcripts` keeps every dictation in the app's own container (`transcripts.jsonl`, docs/backup.md, "Transcripts"):
  - what the model wrote, and what the keyboard typed and it ended as once you edited and sent it (`Transcript.field`);
  - its sound as a `Recording`, a 16 kHz WAV written as it's heard (a recording an ended app left with no transcript is written down on the next launch), up to 512 MB;
  - the microphone it came from, whether voice processing heard it (`scripts/voicehealth.py` counts each capture's failures), and the app it was typed into.
  - Each change, and each launch, writes their texts to the App Group for the keyboard's Transcripts panel (`TranscriptFeed`).
  - A transcript's sound goes out from its menu in the list or right under its text (`RecordingShare`): Send in Messages attaches it as Messages records its own audio messages (Opus at 24 kHz in a .caf, `Recording.export`), and Share Recording hands the share sheet an .m4a, as Voice Memos keeps its own. Without Messages (the simulator), Send in Messages opens the share sheet too.
  - The page lists them under a card of how much you dictate (words, this week against the last, two weeks a day, time, pace, today) that opens Stats › Dictation, and a transcript with its sound can be written again with the model picked now.
- **Clipboard** (`ClipboardPage`): the history the keyboard's clipboard panel keeps, the same `ClipboardStore`, pinned first then by day. A tap copies an item again, and the app keeps what's on the clipboard when it comes forward once the keyboard has started the history.
- **Stats** (`StatsPage`, docs/stats.md): Overview, Typing, Dictation and Taps as pills, the iPhone's or, in the menu beside the title, the Mac's.
  - `Overview` shows a device's whole `Activity`, typed in blue and dictated in pink, in `StatCard`s (Overview.swift, whose charts Typing and Dictation reuse for one kind).
  - `DeviceStats` shows an `Activity`: speed, words a day, the hours you type or talk in, then on the iPhone where your typed words came from and the apps typed in, or your dictations and the apps dictated into; on the Mac the apps dictated into.
  - The iPhone's typing is `TypingStats` (KeyboardStore); its dictation is `Transcripts`.
  - Each computer's is `Computers`, Keystroke's `typing-stats.json` read straight from the computer you added (`iikb://computer` links, `mac/share`; docs/computers.md) each time Stats comes forward, decoded by `KeystrokeStats`.
  - Taps is `TapsPage`: `TapMapView` (Heat, Aim, Accuracy, laid out by `TapBoard`) with your numbers, a picked key's close-up, the thumbs' pull and misses by key, per screen of the Duo.
- **Settings** (`SettingsPage`): every setting, in one list of pages under
  - Keyboard: Appearance (theme, character preview and layout on one page), Typing, Sound & Haptics, each over a `KeyboardPreviewView` to try (`KeyboardSettingsPages`);
  - Voice Typing: Voice (voice model, Keep Mic On and microphone on one page), Writing Style, Dictionary (`VoiceSettingsPages`);
  - iikb: Sources, Keyboard Access, Privacy & Data, Changelog (`ChangelogPage`), About, which credits the swipe decoder and links its license (`SettingsPages`).
