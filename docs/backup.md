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
| `group/Library/` | the App Group's `Library` | the clipboard history, the taps and typing counts the app shows, the settings both read |
| `personal/` | the server (`scripts/personal`) | `en.network`, the next-word network fine-tuned on your typing (below); made there, so the iPhone only reads it |
| `mac/` | the Mac (`scripts/keystroke`) | Keystroke's `typing-stats.json`, for Stats (docs/stats.md); given back to the app, never put on the iPhone |

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
sent with. A file sent with other contents moves the one it replaces to `versions/<time>/` (`<time>.001` and on when that second
already kept one of it); nothing is ever deleted.
It runs as the user service `hex-keyboard-backup` (dotfiles), on port 2592 behind `tailscale serve` at `/backup`, so
only the tailnet reaches it, and takes requests with the token in `~/.config/hex-keyboard/backup.env`.

A build gets the server from `Packages/HexKeyboard/Sources/KeyboardUI/Resources/Keys/backup.key`, kept out of git: the
address on the first line, the token on the second. `scripts/phone` takes it from the main checkout and won't build
without it, so no install of its leaves the iPhone unbacked. `scripts/sync` leaves it out of the Mac's trees, so a
simulator's made-up data never reaches the backup. A build without the file sends nothing and shows no Backup section.

## Your network

The suggestion bar's network (`en.network`, trained on what people type; `scripts/network`) learns how you write. The
server keeps a log of what you type (`sources/record.ts`, the user service `hex-keyboard-record`), and
`scripts/personal` fine-tunes a copy of the shipped network on it: only its output side (the embedding that scores the
next word, the projection and the output biases) learns, from the lines of the log with near-repeats dropped, and the
pass that best predicts the last tenth of them, kept aside, is the one saved (the shipped network itself if none beats
it). The LSTM is copied byte for byte, so the file is the same size.

It runs when the log or the shipped network changes, at most once a day: the path unit `hex-keyboard-personal`
(dotfiles) starts the service of the same name, which asks for `--daily`. The network goes to `mirror/personal/en.network`.
The app fetches it whenever it syncs (the quick check above, in the other direction) into the App Group's
`Library/Personal/`, which the backup leaves out since the server made it, and the keyboard reads it from there in place
of the bundled one the next time it starts, or the bundled one when it's absent. Reset Learned Words and Taps removes the copy and takes no network the server made before then.

The network is made from what you type, so it stays on the server and the iPhone: never in git, tests or logs.

## Getting it back

`scripts/restore <udid>` puts the backup on an iPhone the Mac reaches: everything, or only the files named
(`keyboard/support/typing-memory.json`), as it is now or, with `--at 2026-11-04T0300`, as it was then. It backs the iPhone
up first (`scripts/backup`), once it has picked what to put back, so what the iPhone hadn't sent yet is kept under
`versions/` rather than written over. It quits the app first when the app's files go back. A keyboard that's up reads what was put back the next time it appears.

A reinstall that starts a new container sends its near-empty files over the good ones as soon as the app starts, so
the good ones are in `versions/` and the mirror holds the empty ones. Without `--at`, `scripts/restore` refuses a file
the mirror holds at under half the size of a copy replaced in the last 30 days (one over 4 KB), and prints the `--at`
that puts each larger copy back; `--at now` takes the mirror as it is. `scripts/backup` keeps the mirror's copy of such a
file rather than the iPhone's, which goes to `smaller/<time>/`, and says so; `--smaller` takes the iPhone's, as after a
reset you meant.

Reset Learned Words and Taps gives the memory a new reset token, and a keyboard lets go of a memory saved under another,
so `scripts/restore` puts `keyboard/support/typing-memory.json` back without its token, and the first keyboard to read it
saves it at once under the one it has: restoring that file alone, from before the reset (`--at`), undoes a reset, and a
reset made once a keyboard has read it lets it go as any other. Your network comes back with the next one the server
makes.
