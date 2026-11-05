# KeyboardStore

iikb's saved data, in the App Group the app and the keyboard extension share and in each side's own container, and the channels between the two.

## Files

- `AppGroup`: the group's ID and its `Library` folder, where both sides can write.
- `StoredFile`: a JSON file a person would miss. Reading tells a missing file from one that can't be read; saving moves an unreadable one aside as `<name>-unread-<seconds>.<ext>` rather than writing over it; NaN or infinity is kept as a string. Every such file goes through it (typing memory, shared touches, emoji picks, GIF recents, the Dictionary), not its own encoder (`ArchitectureTests` flags any other file access not marked `// file: <what>`).
- iOS deletes the group's container whenever an install leaves no app claiming the group, so what must outlive it is also kept in each side's own container.

## The stores

- `SettingsStore`: the App Group, plus each side's own copy, so settings outlive the group's container, and a Darwin notification on each save, so a keyboard that's up takes the app's changes at once.
- `MemoryStore`: the extension's own container.
  - Each app has a keyboard of its own, so a keyboard saves only over the version its memory was read from or its own last save, never one another saved since or before its read lands, and never over a file it couldn't read.
  - Each keyboard view controller has its own store, since iOS makes a new one each time the keyboard comes up, often in a process whose last one already read the file.
  - The app resets it by sharing a new reset token.
  - With Full Access the keyboard also writes its touch model to the group as `Library/touches.json`, since a keyboard can't write the group's root, and posts a Darwin notification.
- `ClipboardStore`: what you copied, in the App Group for the app's Clipboard tab, with a copy in the keyboard's own container that a group without a history takes.
- `TranscriptFeed`: what you dictated, copied by the app to the group's `Library/Caches` each time its transcripts change, for the keyboard's Transcripts panel; the backup leaves it out, since the app's own file is the one kept.
- `TypingStats`: the hours the keyboard appends to the group's `Library/typing.jsonl` each time it closes or a message goes, with a Darwin notification.
- `PersonalNetwork`, with `Network.current`.
- `SourceStore`: the `Source`s you add in the app.
- `AppLink`: the app's links the keyboard opens.

## Dictation, the channel to the app for voice typing

Never used in password or code fields.
- A status file in the App Group that only the app writes. It carries whether the app is recording and the length of each dictation it's still writing down, apart, and what those wait for while the model gets ready.
- A `Note` file for each dictation written down, or something to tell you, which the keyboard takes by removing it, so the two never write the same file and none is typed twice.
- A dictation is typed only by the keyboard you stopped it in, which sends a number it picks each time it appears in `finish`'s state, so it never lands in a field you've left; one whose keyboard closed first says it's in Transcripts.
- Darwin notifications both ways. The microphone's level and the seconds recorded so far are carried in a notification's state, so the bar's time is the recording's own length.
- A file lock the app holds while its microphone stays on, which the kernel drops when the app ends.
- `host`: a file only the keyboard writes, the app it's in as it starts or stops a dictation, which the transcript keeps.
- `edits`: a file the keyboard leaves for each dictation once its field is sent or left, with what it became, which the app takes into its transcript by removing it, as the keyboard takes a `Note`.
- `keep` and `takeDraft`: the dictations a keyboard was following as it went away, in its own container (`dictation-draft.json`), which the next keyboard takes and goes on following in the same field, or closes out in another.

## Backup

docs/backup.md has the whole story.
- `Backup` sends iikb's files to the server built in as `Resources/Keys/backup.key` (kept out of git; `scripts/phone` won't build without it, and `scripts/sync` keeps it off the Mac so simulators never send) each time they change: the keyboard as it goes away, the app as it starts and as it writes down a dictation or changes the Dictionary (`Backup.syncApp`, never a recording still being made).
- It sends what the server lacks or holds at another size or modification time to the second, so a failed send goes with the next.
- `server/backup.ts` keeps them in `~/.local/share/iikb/backup/mirror` as `scripts/backup` does, and moves a file it replaces to `versions/<time>/`, deleting nothing; `scripts/restore` puts them back, as they were at any time.
