# FullKeyboard

iikb's own keyboard, on KeyboardUI and KeyboardStore, and the only target that links `KeyboardArbiter`, the private API.

- `FullKeyboardViewController`: the extension's principal class. Forwards events to the engine, renders, runs ranking jobs.
- Its panels besides `EmojiPanel`:
  - `GifPanel` searches KLIPY (`Klipy`, its key in `Resources/Keys/klipy.key`, kept out of git; one request out at a time, `GifSearch`) and puts a tapped GIF on the clipboard (`GifClipboard`), since a keyboard can only type text, or drags a held one into the app's field.
  - `ClipboardPanel` shows what `ClipboardStore` kept of what you copied, read when the keyboard appears and when the panel opens, on a queue of its own, never the main thread. iOS refuses that read silently unless Settings › Apps › iikb › Paste from Other Apps is Allow.
  - `TranscriptsPanel` shows what you dictated, from the copy the app writes for it (`TranscriptFeed`), in `ClipboardPanel`'s rows; each one's field switches to the other (`DrawerSwitch`).
- The clipboard's tool lets out the bar's tray first (`SuggestionBar.Edit`): cut, copy and paste through `UIPasteboard` and the engine, then the two panels.
- `Sources`: the sources you add in the app (docs/sources.md). Each gets the field you type in as JSON, off the main thread, and its hint stands in for the suggestions until tapped. Only with Full Access, never password or code fields.
- `KeyboardHost`: the app the keyboard is in, from the moment it appears (docs/sources.md, "Which app you're typing in").

## Opening apps and knowing the host

- Apps can't be opened from a keyboard through public API; iikb walks the responder chain to the host's `UIApplication`, as Wispr Flow and others do.
- Since iOS 26.4 a keyboard's own properties don't name the app you were typing in, and a keyboard can't reopen it. So `KeyboardHost` matches its host's process ID to the app UIKit's keyboard arbiter names, which the C target `KeyboardArbiter` switches on as the keyboard loads, and names it in the dictation link (App/Voice/AGENTS.md).

Host identity is keyboard-wide context, not voice typing's alone: `KeyboardHost` resolves it on appearance and UIKit text/selection events, and whatever gains from knowing the app takes it from there.
- Sources receive its bundle ID (`app`, empty when unknown).
- Language ranking learns per-app word and next-word counts over shared vocabulary.
- Emoji choices and GIF recents prefer this app's picks.
- Typing stats count each hour under its app.
- Voice typing returns to it, and each transcript keeps the app it was typed into (`Dictation.host`), for Transcripts and Stats › Dictation.

Counts and picks stay local; the GIF service receives no host ID. App identity cannot establish clipboard origin or a conversation. A new use goes through `FullKeyboardViewController.hostApp`, never a lookup of its own.
