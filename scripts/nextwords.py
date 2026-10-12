"""Builds Packages/HexKeyboard/Sources/KeyboardUI/Resources/en.next: the words that most often follow each common word.

Counts: Google Books Ngram (20200217) English Fiction 2-grams, books from 1980 on, pairs seen at least 200 times
(the same corpus as en.lexicon). A sentence start is the context "". Both words are matched to the lexicon's spelling
(build/lexicon/words.tsv from scripts/lexicon.py), so case variants count together; a follower keeps the case writers
give it after that word ("thank God"), except after a sentence start, where every word is capitalized.

For each context c (the 20,000 most common words, and ""), with N its pairs and T its distinct followers, Witten-Bell
gives P(w | c) = (n(c, w) + T P(w)) / (N + T). The file keeps the 12 likeliest followers' n(c, w) / (N + T) and the
weight β the lexicon's P(w) gets for everything else: 1 minus the kept share, so the dropped followers' mass goes back
to the lexicon instead of vanishing.

Layout: "HXN1", context count (u32 LE), then a u32 offset per context into the entries that follow, contexts sorted
by their UTF-8 bytes. Entry: length (u8), context bytes, β as round(255 β) (u8), follower count (u8), then per
follower: length (u8), bytes, -ln p in tenths of a nat (u8, at least 1).

Usage: uv run --no-project python3 scripts/nextwords.py build/bigrams build/lexicon/words.tsv out.next
The first run streams the 47 2-gram files (about 25 GB, 8 at a time) into build/bigrams/shard-*.tsv, keeping only
pairs of plain words seen at least 200 times since 1980; later runs reuse them.
"""

import glob
import math
import os
import re
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

CONTEXTS = 20000
FOLLOWERS = 12
NGRAMS = "http://storage.googleapis.com/books/ngrams/books/20200217/eng-fiction"
PAIR = re.compile(r"^(?:[A-Za-z][A-Za-z']*|_START_) [A-Za-z][A-Za-z']*$")


def keep_pairs():
    for line in sys.stdin:
        tab = line.find("\t")
        if not PAIR.match(line[:tab]):
            continue
        total = sum(int(field.split(",")[1]) for field in line[tab + 1:].split("\t") if int(field[:4]) >= 1980)
        if total >= 200:
            sys.stdout.write(f"{line[:tab]}\t{total}\n")


def stream(shards):
    os.makedirs(shards, exist_ok=True)

    def fetch(index):
        path = f"{shards}/shard-{index:05d}.tsv"
        if os.path.exists(path):
            return
        command = f"curl -sL --retry 5 {NGRAMS}/2-{index:05d}-of-00047.gz | gzip -dc | {sys.executable} {__file__} --keep > {path}.part"
        subprocess.run(command, shell=True, check=True)
        os.rename(path + ".part", path)

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch, range(47)))


if sys.argv[1] == "--keep":
    keep_pairs()
    sys.exit()

shards, words_path, out_path = sys.argv[1:4]
stream(shards)
canonical, ranked = {}, []
with open(words_path) as file:
    for line in file:
        word, count = line.rstrip("\n").split("\t")
        canonical.setdefault(word.lower(), word)
        ranked.append(word)
contexts = {word.lower() for word in ranked[:CONTEXTS]} | {""}

pairs, spellings = {}, {}
for path in sorted(glob.glob(f"{shards}/shard-*.tsv")):
    with open(path) as file:
        for line in file:
            gram, _, count = line.rstrip("\n").partition("\t")
            first, _, second = gram.partition(" ")
            context = "" if first == "_START_" else first.lower()
            follower = canonical.get(second.lower())
            if context not in contexts or follower is None or (context and context not in canonical):
                continue
            following = pairs.setdefault(context, {})
            following[follower] = following.get(follower, 0) + int(count)
            if context:
                spelled = spellings.setdefault((context, follower), {})
                spelled[second] = spelled.get(second, 0) + int(count)

entries = []
for context in sorted(pairs, key=lambda c: c.encode()):
    following = pairs[context]
    total, types = sum(following.values()), len(following)
    kept = sorted(following.items(), key=lambda item: -item[1])[:FOLLOWERS]
    share = [count / (total + types) for _, count in kept]
    beta = 1 - sum(share)
    entry = bytearray()
    name = context.encode()
    entry += bytes([len(name)]) + name + bytes([round(beta * 255), len(kept)])
    for (word, _), p in zip(kept, share):
        spelled = spellings.get((context, word), {})
        written = max(spelled, key=spelled.get) if spelled else word
        encoded = (written if written.lower() == word.lower() and written[1:] == word[1:] else word).encode()
        entry += bytes([len(encoded)]) + encoded + bytes([min(255, max(1, round(-math.log(p) * 10)))])
    entries.append(bytes(entry))

with open(out_path, "wb") as out:
    out.write(b"HXN1" + struct.pack("<I", len(entries)))
    offset = 8 + 4 * len(entries)
    for entry in entries:
        out.write(struct.pack("<I", offset))
        offset += len(entry)
    for entry in entries:
        out.write(entry)
print(f"{len(entries)} contexts, {offset} bytes", file=sys.stderr)
