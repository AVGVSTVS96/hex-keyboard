# KeyboardEnglish

The bundled English data and its loaders, apart from the UI, on KeyboardCore and Foundation alone.

- `Lexicon.english`: `Resources/en.lexicon`, built by `scripts/lexicon`; sources and licenses in `Resources/LEXICON-LICENSE`.
- `Network.english`: `Resources/en.network`, trained by `scripts/network` on what people type to each other and to chatbots; sources and licenses in `Resources/NETWORK-LICENSE`.
- `Swipe.english`: `Resources/en.swipe`, `scripts/swipe`.
- `EmojiCatalog.english` and `EmojiSearch.english` (KeyboardCore/AGENTS.md, "Keys/").
- `Network.current`, the personal network when the app has fetched one, is iikb's and lives in KeyboardStore's `PersonalNetwork`.

The builders, so each format has one implementation:
- `Packages/KeyboardModules/Tools/LexiconBuilder` turns `scripts/lexicon.py`'s word counts into `en.lexicon` with `Lexicon(counts:)`; `Tools/NetworkBuilder` does the same for `scripts/network.py`'s trained weights and `en.network`.
- `scripts/personal` fine-tunes the shipped `en.network`'s output side on `record.jsonl` into the owner's own network (docs/backup.md, "Your network"), kept on the server and the iPhone (`PersonalNetwork`, `Network.current`), never in git.
