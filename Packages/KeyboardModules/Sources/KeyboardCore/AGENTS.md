# KeyboardCore

Pure Swift, no Foundation or UIKit (it also compiles to WebAssembly). Everything the keyboard does lives here, so the extension and the web demo share it. Fully unit tested (`scripts/coretest`, here on Linux). Platform services (UILexicon, files, the scorer's UITextChecker) live outside it behind Core protocols.

## Keys/

- Layouts per device class, `KeyGrid` (key frames and hit testing), metrics, key faces and theme. `KeyboardGeometry` is the keys of a context on a screen; the keyboard, the app's preview and Your Taps all lay out from it (`GeometryTests`).
- `Keys/Themes.swift`: Raycast's themes (Default, Clear, Physical, Mechanical, iOS 5; docs/design.md, "Themes"), each a `KeyPaint` per kind of key, made by `KeyboardTheme.named`.
- `Keys/Emoji.swift`:
  - `EmojiCatalog`: the bar's emoji for a word, or else for its singular. Read from `KeyboardEnglish/Resources/emoji.txt`, picked by hand per word (a word can also find none), and checked by `scripts/emoji.py`, which prints each word's candidates from CLDR, emojilib and gemoji.
  - `EmojiSearch`: every emoji in Apple's order with its skin tones and CLDR names and keywords, for the emoji panel; `KeyboardEnglish/Resources/emoji-search.txt`, written by `scripts/emoji-search.py`.
  - `EmojiHistory`: the emoji you picked from the bar or the panel, and the skin tone picked for each; each pick outweighs the ones before it, no clock.
- `Keys/Toolbar.swift`: what sits above the keys per device (`KeyboardMetrics.toolbar`): the bar (the tools sit at its left on every screen, with no row of their own), a panel's results and search row, and which edges go nowhere.
- `Keys/BarLayout.swift`: the bar's buttons set out as the top row's keys are. Every button is one circle (`Toolbar.button`) in a square cell the bar's height; the More button's and the tools' run from the first key's left edge a key gap apart, and the mic's ends on the last key's right edge; each glyph fits one square (`Toolbar.glyph`). `BarLayoutTests`.

iOS facts the metrics follow:
- Third-party keyboards get a system bottom bar (globe, mic) on Face ID iPhones and a system undo/redo/paste bar on iPad. Metrics are calibrated so the keys land where Apple's do with those bars in place.
- iOS draws the keyboard's backdrop 4pt above the keyboard's own top, so on iPhone the bar is 38pt under 3pt of padding, 7pt from the backdrop's top and 7pt from the keys, with the tools beside the suggestions rather than in a row of their own (`Toolbar`): on the iPhone Duo the keyboard is as tall as Apple's with its suggestions.
- On iPad the system's own shortcut bar (undo, redo, paste) sits above a third-party keyboard and its middle can't be used, so iikb adds a 36pt suggestion row there, for the mic and, with Predictive Text on, the suggestions.

## Typing/

- `TypingEngine` takes `KeyboardEvent`s (`handle`) and does shift, caps lock, autocap, double-space period, smart punctuation, layers, word delete, autocorrect and reverts, and the tap labels it learns from.
- The engine reads the text only from its `TextState`. Every edit goes through `TypingEngine.write`, which changes the host and `TextState` together. The host's reports (`textDidChange`, `selectionDidChange`) reach it only through `documentChanged`, which ignores reports that show the keyboard's own edits late or in a shorter window, the text after the caret included, and adopts anything else. Automatic edits only replace characters the keyboard typed itself (`TextState.owned`). `TextStateStressTests` checks late, truncated reports never change what taps type.
- `Lines` moves the caret up and down lines through a `LineLayout`, keeping its x across a short line as a text view does.
- `Typing/Panel.swift`: the panels (emoji, GIF, clipboard). `TypingEngine.panel` is the open one and `query` its search, which the keys type into while it's open (`KeyboardEvent.panel`). `Panels/` holds what the GIF and clipboard panels keep (`GifSearch`, `ClipboardHistory`).
- `Typing/SourceFeed.swift`: what one source is sent (`FieldUpdate`s, one at a time: your typing collapsed into the newest text while every change the app makes goes in turn, and what an unreachable source missed kept for your next change) and the hint it answered with.
- `Typing/TypingTally.swift`: `TypingTally`, what typing did as counts (keys, characters, deletes, words, autocorrect's fixes and the ones taken back, picks from the bar, emoji), which `TypingEngine.tally` only adds to; and `TypingLog`, the change in it by hour and app with the time between changes, pauses over 4 s left out (docs/stats.md).

### Dictation drafts

`Typing/DictationDraft.swift`: what each dictation typed becomes.
- `TypingEngine` starts a `DictationDraft` when it types a dictation with its transcript's id (`KeyboardEvent.dictated`) and follows it through every edit until the field is sent or left (`leaveField`, a new `documentIdentifier`). Sent is emptied with nothing selected, by a host that has shown its text; a return the keyboard typed just before is the send, not part of the dictation. A keyboard that goes away keeps the draft (`takeDraft`), and the next one in the same field goes on following it (`resume`).
- The keyboard's own edits land on it exactly. Each window of the field the host shows that they don't explain (a tap moving the caret, a paste, a cut) is placed on the field the draft has seen as the smallest edit that explains it, since iOS shows a keyboard only a window around the caret, cut at a length of its own before and after the caret. A window that fits two places as well loses the place rather than guessing.
- `takeDictations` gives each dictation's `Outcome`: what was typed, what it is now (`final`: edits inside it, a dictation typed into it cut out, typing that runs on from either end left out unless it retypes what was deleted there, though whitespace at that end counts only once more retyping follows it, and punctuation typed against its end counts, since it shows what the style left out that you wanted, and empty once all of it is deleted), whether the field was sent, and whether it's `uncertain` (the field changed while the place was lost).

### Slide to Type

`Typing/TypingEngine+Swipe.swift`: Slide to Type (`KeyboardSettings.slideToType`, on by default).
- `KeyboardEvent.swipe` carries a path of `SwipePoint`s (keyboard points and seconds). The engine holds the `Swipe` model (`swipeModel`) and reads the path on the live grid's letters (`KeyGrid.swipeLayout(near:)`: on a split keyboard, a letter on both halves is the one nearer the swipe).
- It runs the network once and searches the lexicon's trie, and the trie of the words you've taught the keyboard (learned words and names the lexicon lacks, kept in `ownedWords` and made again only when that set changes).
- Each candidate is scored as the decoder alone scores it (`Swipe.Scoring.refined`, whose λ·ln f is already a word prior) plus 0.3 × (ln P(word | the words before it) − ln P(word | a sentence start)), so the sentence replaces that prior rather than stacking a second, and an empty field ranks as the decoder alone. P(word | the words before it) is the same `LanguageModel.predictor` under `Corrector.expected` that ranks the bar's next words (`Corrector.continuation`).
- α was tuned on the validation split by `scripts/eval swipeContext`: test top 1 90.71 to 91.99, top 3 95.28 to 95.54 with a sentence, unchanged without. The 400 bench swipes through the engine on the folded Duo: 375/400 top 1 (`SWIPE_BENCH=scripts/swipebench.tsv scripts/eval swipeBench`).
- The best is typed the way a word follows a word: a space first when the caret follows a word, none after, capitals from shift, caps lock and auto-capitalization, spelled as the lexicon or your names spell it, and owned like typed text.
- While the text before the caret is as the swipe left it (`TypingEngine.swipedWord`), the bar offers the next three readings, not the swiped word, as Apple's does (a pick replaces it, as a pick does); delete takes out the word and the space the swipe added; and the space or a letter you type next goes on as after any word (no autocorrect on the swiped word itself, since it has no taps to read), so it's learned when you move on.

### Dictation's text

What the model wrote is typed as Settings › Writing Style writes it (`DictationWriting`):
- Edited (`DictationEditing`): As Said, the default, keeps every word, um and uh included, as Bassim's said keeps them on purpose; Light leaves out um and uh; Clean also leaves out short words said twice, "like" and "you know" said between commas, what "scratch that" takes back and what you fix as you go ("at two, I mean three" typed "at three").
- In a `DictationStyle`, Wispr Flow's four, each setting all the punctuation, never the words. Every style ends a question the model wrote with a period with "?".
  - Formal. keeps every comma, ends every sentence, sets off an opening "However" or "Actually" and keeps one "!" or "?".
  - Casual, the default, drops the last period, the comma after an opening "so", "hey" or "thanks", and semicolons for commas.
  - very casual is Casual in lowercase without the comma before "and", "but" or "so".
  - Excited! is Formal with "!" ending the last sentence, every short one and every cheer.
- A list you speak ("one, eggs, two, milk", or first, second) is written as a numbered or bulleted one, or left in its sentence (`SpokenList`, `DictationLists`, Settings › Lists), since Parakeet takes no instructions and writes a spoken list as a sentence.

A field reads it its own way, picked by the keyboard as it types (`DictationReading`, from `InputTraits`' keyboard type and `content`, the field's `textContentType`):
- An email or URL keyboard, or an email, URL or username field, reads what the model wrote as one address (`SpokenAddress`: "at", "dot", "underscore", "dash", "slash" and "colon" become their signs, number words and spoken digits digits, spaces and the closing period go, "J-O-H-N" is john, "John dot Smith at Gmail dot com" is john.smith@gmail.com).
- A number, phone or decimal pad, or a telephone, one-time code, postal code or card field, reads the digits said ("oh" and "o" beside a digit are 0, a "+" it starts with stays, and a decimal pad keeps its point), with the field formatting itself.
- A search field reads an address only when all of it is one (no two plain words in a row); any field reads an address when the caret follows part of one ("john@").
- An address or digits are typed with no capitals or spaces, from `Dictation.Note`'s `plain` (what the model wrote with the Vocabulary and no style or lists). A field it can't read that way, or any other, types the styled text, in which an email spoken in a sentence ("email me at john at gmail dot com", "jane.doe at gmail.com") is written as one (`SpokenAddress.inline`), and so is a web address with its ending ("open kestrel dot run", though not after "the" or "my"). A decimal or percentage it wrote in words is written as Parakeet mostly writes it ("Opus five point five" Opus 5.5, "fifty percent" 50%), and so are four or more digits said one by one, which it sometimes leaves as words (a phone number, code or PIN, grouped by the commas it heard or else as a phone number's are), while "at one point", "a five point plan", counting ("one two three four", "five, four, three, two, one", "one two, one two") and every other number stay as written (`SpokenNumber`).
- `scripts/formats` checks all of it, through the app's writing and Dictionary and then the keyboard's, on made-up text in Parakeet's own forms (scripts/formats.txt, `FormatTests`), in seconds; `scripts/phone` installs nothing that fails it.
- `scripts/fieldbench` scores it, saying Tools/FieldBench's cases on the Mac in two voices.

Its capitals are the keyboard's, set where it goes in (`TypingEngine.fitted`) from the field and Settings › Keyboard › Typing › Auto-Capitalization, as typing's are, and the style (`DictationWriting.capitals`): with Auto-Capitalization off or in very casual, each sentence's first word is lowered where the lexicon spells it lowercase, and so is I, while names keep theirs; otherwise sentences start with a capital as the field asks.

Then it goes through your `Vocabulary` (`VocabularyView` in the app's Settings, kept as vocabulary.json in the app's container, so a person's words never reach git): the words the model gets wrong, each with what it writes instead, matched as whole words only. The transcript keeps what the model wrote when the style or vocabulary changed it.
- Parakeet writes a name a new way each time ("IKB", "IITB" and "IIK be" for iikb), so a listed spelling alone missed most of them. With the lexicon (the app passes it), a span of up to five words with one the lexicon lacks, whose spoken letters ("." said "dot") are a letter or two from a term's or a listed spelling's and start the same, becomes the term; its first and last words are made up or the term's own, so "Wispr Flow or" keeps its "or". A real word is still only swapped when listed. A spoken dot before a term with a dot joins it ("dash dot example.run" is dash.example.run).
- The keyboard runs the same match on what it's about to type, against the field's own words (`Vocabulary.seen`: each dotted name from each part to its end, each word of four letters or more the lexicon lacks), so a name already written comes out the same when said again. A word that only adds an ending to one there, or only changes its case, stays.
- Nov 5, on Bassim's 668 dictations: 13 words changed, each to the name meant, none wrong.

## Correction/

`Corrector` (what to correct, text replacements, names, learned words) over a `CandidateSource`.
- With a `Lexicon` (a flat byte trie of words and frequencies) as its source it decodes taps (`Decoder`, exact A* over the trie) against your `TouchModel` and a `LanguageModel`.
  - `TouchModel`: each key a 2D Gaussian with a conjugate Normal-Inverse-Wishart prior, whose center blends three memories of where you aim (all taps, the last ~30 and the last ~3), weighted by how well each predicted your taps.
  - `LanguageModel`: Witten-Bell over your next-word counts, your words and the lexicon, each next-word count less half a word, so a word seen once after another doesn't outrank one the level below knows far better.
- A correctly typed real word is never changed: the corrector replaces a word that stands on its own (kept, or read as itself when typed perfectly) only when the touches favor the other word; word frequencies may only choose among what the fingers could have meant.
- Missed spaces (`Corrector.split`): a run whose spaces went astray (a space missed, "greatday"; hit as a letter on the row above the space bar, "freatvday"; or a space tap meaning a letter, "a out" in a selection) is read as the words it likeliest spells, each from its own taps after the word before it and with a typo of its own ("iblovebuoubbaby" → "I love you baby"). It keeps the three likeliest readings up to each point and picks among the whole ones by each word's likelihood after the words before it, `Network` included, so "inalsonuodated" after "done" is "I also updated", not "in also updated". A word typed as one gets them in the bar only when they beat every reading of it as one known word, and they're never applied by the space, since a new word you coin can read as two.
- A word read without its taps, as one you go back to or select is, counts each tap as landing anywhere on the key it hit (`Corrector.shares`).
- The bar is for the text a tap on it replaces: the selection (up to 64 characters of words and spaces), or else the whole word around the caret, so a word you go back to or select gets its corrections too.
- `Network` (a small LSTM over the last 16 words, commas and sentence starts, int8 weights read in place) gives what comes next after the text before the caret. It sits under your next-word counts (after the word before, and after the two before) when ranking next-word predictions and the completions of the word you're typing, and goes on from what it read for the text before, so a keystroke costs a lookup and a new word one step of it. Autocorrect leaves it out, because its vocabulary of the corpus's 20,000 commonest words would push every other word down.
- `KeyMap` (which key a touch means) is made for the text as it is after every edit, so the next touch, rollover included, reads it at once. It costs hundredths of a millisecond, since `Corrector` keeps its count of words the lexicon doesn't know up to date rather than recounting, and `TypingMemory` changes in place (`Corrector.record`, `forget`, `changeMemory`).
- `TypingMemory` holds everything learned and is `Codable`.
- `Aim` turns the touch model into what the app shows: each key's learned center and spread in points, its last 48 taps and the key the grid reads each as, where each of its three memories centers and its weight, and the share of its taps the grid would put on each key.

Learning comes only from real events: the letters of a word you kept once you move on (next word, the message sent, keyboard hidden), a reverted correction teaches what you typed, and a backspace-then-retype within a quarter key labels the erased tap. Words you delete teach nothing. Nothing in the model runs on a clock: older taps fade only as newer taps of the same key arrive, and every weight is a posterior or a count.

A change that moves correction or prediction numbers is scored with `scripts/eval` (scripts/AGENTS.md).
