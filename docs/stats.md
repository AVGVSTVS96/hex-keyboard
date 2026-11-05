# Stats

The app's Stats tab shows how you type and talk, and where your taps land: Typing, Dictation and Taps, each a pill
under the title. The menu beside the title shows the iPhone's or, once it has sent them, your Mac's, kept apart.
Everything is counted and timed, and nothing is ever written down: no letter of what you type leaves the keyboard.

## The iPhone

- **Typing**: `TypingEngine.tally` (KeyboardCore) counts what typing does as it happens: keys, the characters they and
  the bar's picks put in the text, deletes, words finished, autocorrect's fixes and the ones you took back, words
  picked from the bar, emoji. The keyboard reads it each time it changes (`TypingLog`) and adds the change to the hour and
  app it happened in, with the time since the last change unless that was a pause of over 4 seconds, as Keystroke
  counts on the Mac. Each time the keyboard closes or a message goes, it appends those hours as JSON lines to the App
  Group's `Library/typing.jsonl` (`TypingStats`) and posts a Darwin notification, so Stats takes them at once. A
  keyboard without Full Access can't write the group: it keeps them in its own container and moves them over once it can.
  It also keeps every line it shared in its own container (`typing-shared.jsonl`) and puts them back in a group that
  lost its file, since iOS deletes the group's container whenever an install leaves no app claiming the group; Delete
  Typing Stats leaves a token in the settings, so the keyboard deletes that copy too.
- **Dictation**: the transcripts (`Transcripts`): words, how long each dictation ran, when, and the app it was typed
  into, which the keyboard names (`KeyboardHost`, `Dictation.host`) as you start and stop it.

Speed is words a minute: for typing, words of five characters (the standard measure) over the time you were typing;
for dictation, each dictation's words over its length, as Transcripts' pace. Privacy & Data › Delete Typing Stats
deletes the iPhone's counts.

## The Mac

[Keystroke](https://glaze.app) is a Mac app Bassim made with Glaze that counts typing and dictation everywhere on the
Mac, keys by keycode and dictated text by length, and keeps the counts in
`~/Library/Application Support/<its bundle ID>/typing-stats.json` (version 3: each day's `typed` and `voice` counts,
both by hour, and the apps dictation went into).

```
Keystroke saves ──► LaunchAgent (WatchPaths) ──PUT mac/typing-stats.json──► backup server
                                                                                 │
           Stats comes forward ──GET mac/typing-stats.json──────────────────────┘
```

`scripts/keystroke` sets the Mac up: a LaunchAgent that watches Keystroke's folder and, each time Keystroke saves (and
at login), sends the file to the backup server (docs/backup.md) with its token, as `mac/typing-stats.json`, so the server
keeps every version. The app reads it back from there each time Stats comes forward (`MacStats`, `Backup.read`), and
keeps the last copy in its caches, so the Mac shows as it last was while it's asleep or the server is out of reach; a
footer says when Keystroke saved it. The server gives back only what's under `mac/`, never the iPhone's own files.
