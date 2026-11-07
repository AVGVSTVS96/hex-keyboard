# Stats

The app's Stats tab shows how you type and talk, and where your taps land: Overview, Typing, Dictation and Taps, each a
pill under the title. Overview is everything at once, as Keystroke's dashboard is, typed in blue and dictated in pink:
today, words or speed a day over 7, 30 or 90 days, records (streak, most words, fastest day, top burst), the hours you
write in, how often you type at each speed, dictation and the apps your words went into, the past year a square a day
(bluer for typing, pinker for dictation) and all time. The menu beside the title shows the iPhone's or a computer's you
added (docs/computers.md), kept apart.
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
- **App names**: the keyboard knows an app only by its bundle ID (`com.atebits.Tweetie2`), and iOS gives an app no
  public way to read another's name, so `AppName` asks Apple's iTunes Search API (`itunes.apple.com/lookup`) once for
  the App Store's name, cuts its tagline and maker ("Gmail - Email by Google" is Gmail, "Claude by Anthropic" Claude)
  and keeps it in Caches. Apple's own apps the store doesn't list, like Settings, are named in `AppName.unlisted`; any
  other shows its bundle ID's last part.

Speed is words a minute: for typing, words of five characters (the standard measure) over the time you were typing;
for dictation, each dictation's words over its length, as Transcripts' pace. Privacy & Data › Delete Typing Stats
deletes the iPhone's counts.

## The Mac

[Keystroke](https://glaze.app) is a Mac app made with Glaze that counts typing and dictation everywhere on the
Mac, keys by keycode and dictated text by length, and keeps the counts in
`~/Library/Application Support/<its bundle ID>/typing-stats.json` (version 3: each day's `typed` and `voice` counts,
both by hour, and the apps dictation went into).

```
iPhone ──GET typing-stats.json──► the Mac (mac/share) ── Keystroke's typing-stats.json
```

`mac/share` has the Mac answer the app with that file, over Tailscale or the local network, and shows the QR code that
adds it (docs/computers.md); any computer that answers the same way shows here too. The app reads each one each time
Stats comes forward (`Computers`, decoded by `KeystrokeStats`), and keeps the last copy in its caches, so a computer
shows as it last was while it's asleep or out of reach; a footer says when Keystroke saved it.
`scripts/keystroke` runs `mac/share` on the Mac `ssh mac` reaches, and gives Keystroke there the backup server's key
(below).

## The iPhone in Keystroke

Keystroke shows the iPhone too, beside the Mac or alone (All · Mac · iPhone in its title bar). The backup server makes
`GET /iphone/typing-stats.json` (`server/keystroke.ts`) from what the iPhone already sent it, the keyboard's hours
(`group/Library/typing.jsonl`) and the transcripts, in Keystroke's own version 3 shape: each day's typed and voice
counts by hour, with iikb as the dictation app. Only counts and times go: no word of a transcript leaves the server.

```
iPhone ──backup──► server ──GET iphone/typing-stats.json──► Keystroke (Mac)
```

Keystroke fetches it with the Mac's `~/.config/iikb/backup.key` (`scripts/keystroke` puts it there) as it starts and
each minute while its window shows, and keeps the last copy as `iphone-stats.json` beside its own, so the iPhone shows
as it last was when the server is out of reach. The iPhone's typing has no bursts or per-minute speeds, so Top burst and
Typing speed stay the Mac's.
