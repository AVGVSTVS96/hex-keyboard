# Writing Style

## Sub-features

How a dictation is typed (`DictationWriting`, KeyboardCore). Style, Wispr Flow's four: Formal (ends with a period), Casual, the default (no last period, no comma after an opening "so" or "also"), very casual (Casual in lowercase) and Excited (ends with "!"). Editing: As Said, the default, keeps every word, um and uh included; Light leaves out um and uh; Clean also leaves out words said twice and what "scratch that" takes back. Lists types a spoken list ("one, eggs, two, milk") as a numbered one. Capitals follow Auto-Capitalization, as typing's do; very casual has none. Each style shows the same words as it would type them. Transcripts keep what the model wrote.

## How to get to it (user POV)

Hex app › Settings › Voice Typing › Writing Style, or the Hex tab's Writing Style card.

## Driving it

`DictationStyleTests` (package) pins each style and editing, the capitals and spoken lists; `scripts/coretest --filter DictationStyleTests` runs them on Linux. `-HexSettings writing` opens the page for a screenshot.
