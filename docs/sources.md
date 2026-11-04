# Sources

A source is a web service iikb tells what you type. It sees the app’s bundle ID and the text of the field you're typing in, in any app, and can answer with a hint that iikb shows above the keys in place of the suggestions. Tapping the hint hides it until the source answers with a different one.

```
you type ──► iikb ──POST the field──► your source
                 ▲                                 │
                 └──────── { "hint": "…" } ◄───────┘
```

Sources need Allow Full Access (Settings › Apps › iikb › Keyboards), since that is what lets a keyboard use the network. iikb never sends password, new-password, one-time-code or card fields, and iOS swaps in its own keyboard for secure fields.

## Adding one

In the iikb app: Settings › iikb › Sources › Add Source, with a name, an address and an optional token. iOS lets a keyboard reach `https` URLs, and `http` only on your local network (`localhost`, `.local` names). Or a source can give you a link, which the app asks about before adding:

```
hexkeyboard://source?name=Example&url=https%3A%2F%2Fexample.com%2Fhex&token=secret
```

## What iikb sends

`POST <url>` with `Content-Type: application/json`, and `Authorization: Bearer <token>` when the source has a token.

```json
{
  "app": "com.apple.MobileSMS",
  "field": "6F1C2D0E-8A3B-4C5D-9E7F-0123456789AB",
  "before": "Running late, be there",
  "after": "",
  "by": "keyboard",
  "kind": "text",
  "returnKey": "default",
  "at": "2026-10-20T07:13:02.120Z"
}
```

- `app`: the host app’s bundle ID, available when the keyboard appears, before you type. An empty string means the private lookup could not identify it; iikb never guesses from the field or a previously opened app.
- `field`: the text field, from iOS's `documentIdentifier`. It stays the same while the field stays open, and changes when the app opens it again (Messages gives a conversation a new one each time you open it).
- `before`, `after`: the text before and after the caret, as the keyboard knows it. Apps show a keyboard a window of the text, so in a long document these may not reach its start or end.
- `by`: who changed the text last. `keyboard` is you typing. `app` is the app: the keyboard opening in a new field (always the field's first update), a sent message clearing it, a paste, the caret moving.
- `kind`: `text`, `email`, `url`, `number`, `decimal`, `twitter` or `webSearch`.
- `returnKey`: what the return key says, like `default`, `send`, `search`, `go` or `done`.
- `at`: when the field was this way.

iikb sends one update at a time to each source and waits for the answer before the next. If you type while one is on its way, only the newest text follows it, but every change the app makes is sent, so the text as it was right before an app change (a message being sent) always arrives first.

An update that gets no answer in 10 seconds, or an error, counts as unreachable: the hint goes, and iikb tries again at your next change, starting with what it couldn't send. While the keyboard stays open it keeps every change the app made and the newest text you typed, so a source that was down still learns, in order and with their `at`, what you sent.

## What a source answers

A `2xx` with JSON:

```json
{ "hint": "This might come across harsher than you mean." }
```

`{}`, `{"hint": null}` or an empty body clears the hint. A hint belongs to the field it was answered for, and stays until the source answers again. iikb ignores keys it doesn't know, so a source can be written once and keep working as iikb learns more answers.

## Which app you're typing in

iikb identifies the host app when the keyboard appears, before you type, and checks again on UIKit’s appearance, text and selection events. `KeyboardHost` matches the keyboard’s host process ID to the bundle ID reported by UIKit’s keyboard arbiter. This is private API: iOS 26.4 stopped exposing the host through the keyboard’s own properties, and an unavailable or unmatched arbiter result means unknown.

The same app identity serves:

- **Sources:** every field update carries `app`. A new app identity triggers an update even when the text has not changed, and hints belong to both their app and field.
- **Suggestions and autocorrect:** words and word pairs you keep are counted for that app as well as globally. App-specific counts rank completions, correction candidates and next-word suggestions, backing off to your shared language and then the lexicon. A new or unknown app keeps the shared behavior. Correctly typed words keep the same touch-evidence protection.
- **Emoji:** the bar and panel put emoji you choose in this app first, with shared favorites underneath. Skin-tone preferences stay shared.
- **GIF recents:** GIFs shared in this app come first, followed by your other recent GIFs. The app ID is used locally; it is not sent to KLIPY.
- **Voice typing:** the keyboard passes the same identity to the recording app so it can return you to the right app.

App-specific learning stays on the phone. Reset Learned Words and Taps also clears the per-app word counts. Touch calibration, explicit kept spellings, text replacements, voice writing settings and skin tones remain shared preferences. Field behavior follows the traits iOS reports, rather than guesses based on an app’s name. Clipboard entries have no app-of-origin label: the app where the keyboard reads the clipboard does not establish where something was copied.

An app ID does not identify a conversation, recipient or web page. iOS exposes only the text around the caret and field traits to a third-party keyboard. `UIConversationContext` (iOS 18.4) remains unavailable to it, even when the host sets it. An `app` update emptying the field after typing is evidence that its text was sent, not who received it.

Shortcuts automations are no longer needed for keyboard updates. `sources/record.ts` still accepts an app-only `{ "app": "…" }` POST from an automation for activity outside the keyboard; a keyboard update’s own `app` takes precedence, including an empty value.

## A record of what you type

`sources/record.ts` is a source that keeps a log: one JSON line for each message you send, and for each field you leave with text you typed, with when it was, the kind of field, and the bundle ID sent by the keyboard.

```sh
RECORD_TOKEN=secret bun sources/record.ts --port 2590 --out ~/record.jsonl
```

```json
{"at":"2026-10-20T07:13:02.120Z","event":"sent","text":"On my way","app":"com.apple.MobileSMS","kind":"text","returnKey":"default"}
```

It listens on `127.0.0.1`; put it behind `https` on your own devices, for example with `tailscale serve --bg --set-path /record 2590`, and add it with the token.
