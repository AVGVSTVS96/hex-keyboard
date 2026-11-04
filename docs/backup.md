# Backup

Everything iikb keeps lives on the iPhone, so a lost phone, a deleted app, an install that starts a new container, or a
bug that saves over a file would take it with it. A build with a backup server sends each file there as it changes,
and the server never deletes one.

## What goes

Everything but what downloads again or iOS may clear (Parakeet's models, `Caches`), under the names `scripts/backup`
gives them:

| On the server | On the iPhone | What it holds |
|---|---|---|
| `app/` | the app's `Library/Application Support` | transcripts, their recordings, the Dictionary |
| `app/Preferences/` | the app's `Library/Preferences` | the app's settings |
| `keyboard/support/` | the keyboard's `Library/Application Support` | what it learned (words, taps), emoji and GIF picks, its clipboard copy |
| `keyboard/Preferences/` | the keyboard's `Library/Preferences` | the keyboard's settings |
| `group/Library/` | the App Group's `Library` | the clipboard history, the taps the app shows, the settings both read |

## When

When something changes, never on a clock:

- the keyboard, each time it goes away, after saving what it learned (Full Access only, since a keyboard can't go online
  without it);
- the app, as it starts, each time it writes down a dictation or changes the transcripts, and each time you change the
  Dictionary;
- `scripts/phone`, before every install (`scripts/backup`, which copies the same files through the Mac).

Each sync asks the server what it holds and sends every file it lacks or holds at another size or modification time to
the second (rsync's quick check), so a send that failed, offline or cut off, goes with the next. A recording goes once
its dictation is written down, never while it's still being recorded. Settings › iikb › Privacy & Data checks the app's
files against the server when it opens and says whether they're all there.

## The server

`server/backup.ts` keeps what it's sent in `~/.local/share/hex-keyboard/backup/mirror`, with the modification time it was
sent with. A file sent with other contents moves the one it replaces to `versions/<time>/`; nothing is ever deleted.
It runs as the user service `hex-keyboard-backup` (dotfiles), on port 2591 behind `tailscale serve` at `/backup`, so
only the tailnet reaches it, and takes requests with the token in `~/.config/hex-keyboard/backup.env`.

A build gets the server from `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/backup.key`, kept out of git: the
address on the first line, the token on the second. `scripts/phone` takes it from the main checkout and won't build
without it, so no install of its leaves the iPhone unbacked. `scripts/sync` leaves it out of the Mac's trees, so a
simulator's made-up data never reaches the backup. A build without the file sends nothing and shows no Backup section.

## Getting it back

`scripts/restore <udid>` puts the backup on an iPhone the Mac reaches: everything, or only the files named
(`keyboard/support/typing-memory.json`), as it is now or, with `--at 2026-11-04T0300`, as it was then. It quits the app
first when the app's files go back. A keyboard that's up reads what was put back the next time it appears.
