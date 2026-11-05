# Sources

## Sub-features

A web service the keyboard sends the field you're typing in to, as JSON, one update at a time, and whose hint stands in for the suggestions until tapped (docs/sources.md). Never password or code fields. An unreachable source gets what it missed at your next change. `sources/record.ts` is one you can run: a log of every message you send.

## How to get to it (user POV)

iikb app › Settings › iikb › Sources › Add Source (name, https address, optional token), or a `iikb://source?...` link the source gives you. It needs Full Access.

## Driving it

`scripts/mac scripts/sourcetest` runs `SourceTests` through the real keyboard with `scripts/source.py` standing in for a source, and prints every update it was sent. `SourceFeedTests` (package) pins what's sent and in what order; `bun test sources/` tests the record source.
