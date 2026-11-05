"""Scores each <corpus>/outputs/*.jsonl against <corpus>/references.jsonl, with um and uh set aside and every text, the
references and what iikb typed too, put through <corpus>/vocabulary.json (the Dictionary as it is now, as iikb's
Vocabulary applies it) when there is one, so a name it fixes counts as fixed even where a final kept the mishearing: the
share of words wrong, the words dropped and added, the words each gets right that the baseline got wrong (fixed) and gets
wrong that it got right (broken), and the median time it took per dictation. The baseline is what iikb typed (<corpus>/typed.jsonl,
also scored as `typed`) when the corpus has it, or else outputs/dictation-100.jsonl. Then the same for each group of
clips each label in <corpus>/clips.jsonl makes (room, mic, …). With --misses <way>, the words that way still gets
wrong most often, each as the final has it and as the way wrote it, for the next change to aim at, on the terminal only:
they're Bassim's words."""
import collections, difflib, json, re, statistics, sys
from pathlib import Path

FILLERS = {"um", "uh", "umm", "uhh", "hmm", "mm", "mhm"}
WORD = re.compile(r"(?:[^\W_]|['’])+")
GLUE = set("-/\\_@.:")


def words(text):
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)*", text.lower().replace("’", "'"))


def said(text):
    return [w for w in words(text) if w not in FILLERS]


def edits(reference, hypothesis):
    """Substitutions, deletions and insertions on a minimum-edit alignment."""
    return align(reference, hypothesis)[:3]


def align(reference, hypothesis):
    """`edits`, and which reference words the alignment got right."""
    cost = [list(range(len(hypothesis) + 1))]
    for i, word in enumerate(reference, 1):
        row = [i]
        for j, heard in enumerate(hypothesis, 1):
            row.append(min(cost[i - 1][j - 1] + (word != heard), cost[i - 1][j] + 1, row[j - 1] + 1))
        cost.append(row)
    i, j, s, d, n, right = len(reference), len(hypothesis), 0, 0, 0, set()
    while i or j:
        if i and j and cost[i][j] == cost[i - 1][j - 1] + (reference[i - 1] != hypothesis[j - 1]):
            if reference[i - 1] == hypothesis[j - 1]:
                right.add(i - 1)
            else:
                s += 1
            i, j = i - 1, j - 1
        elif i and cost[i][j] == cost[i - 1][j] + 1:
            d, i = d + 1, i - 1
        else:
            n, j = n + 1, j - 1
    return s, d, n, right


def dictionary(path):
    """Vocabulary.corrected: a listed spelling of up to four whole words, joined only by spaces or hyphens, becomes its
    term, ignoring case, spaces and hyphens, never inside a name or path, longest first, keeping a possessive's 's."""
    if not path.exists():
        return lambda text: text
    key = lambda s: s.lower().replace(" ", "").replace("-", "")
    spellings = {key(s): t["term"] for t in json.load(path.open())["terms"] for s in [t["term"], *t["heardAs"]] if key(s)}
    word = lambda at, text: 0 <= at < len(text) and WORD.fullmatch(text[at]) is not None

    def corrected(text):
        spans, out, copied, i = [m.span() for m in WORD.finditer(text)], [], 0, 0
        while i < len(spans):
            for n in range(min(4, len(spans) - i), 0, -1):
                start, end = spans[i][0], spans[i + n - 1][1]
                if any(set(text[spans[j][1] : spans[j + 1][0]]) - {" ", "-"} for j in range(i, i + n - 1)):
                    continue
                if (start >= 2 and text[start - 1] in GLUE and word(start - 2, text)) or (end < len(text) and text[end] in GLUE and word(end + 1, text)):
                    continue
                spelled, possessive = text[start:end], ""
                if key(spelled) not in spellings and len(spelled) > 2 and spelled[-1] in "sS" and spelled[-2] in "'’":
                    spelled, possessive = spelled[:-2], spelled[-2:]
                if key(spelled) in spellings:
                    out += [text[copied:start], spellings[key(spelled)], possessive]
                    copied, i = end, i + n
                    break
            else:
                i += 1
        return "".join(out) + text[copied:]

    return corrected


def main():
    corpus = Path(sys.argv[1])
    corrected = dictionary(corpus / "vocabulary.json")
    references = {r["id"]: said(corrected(r["text"])) for r in map(json.loads, (corpus / "references.jsonl").open())}
    clips = {c["id"]: c for c in map(json.loads, (corpus / "clips.jsonl").open())} if (corpus / "clips.jsonl").exists() else {}
    ways = {}
    if (corpus / "typed.jsonl").exists():
        ways["typed"] = {r["id"]: (said(corrected(r["text"])), None) for r in map(json.loads, (corpus / "typed.jsonl").open())}
    for path in sorted((corpus / "outputs").glob("*.jsonl")):
        ways[path.stem] = {r["id"]: (said(corrected(r["text"])), r.get("ms")) for r in map(json.loads, path.open())}
    baseline = ways.get("typed") or ways.get("dictation-100") or {}
    scored = {way: {id: align(references[id], heard) + (ms,) for id, (heard, ms) in rows.items() if id in references}
              for way, rows in ways.items()}
    right = {id: align(references[id], heard)[3] for id, (heard, _) in baseline.items() if id in references}

    def table(ids, indent=""):
        print(f"{indent}{'way':<18}{'clips':>6}{'words':>7}{'wrong':>8}{'dropped':>9}{'added':>7}{'fixed':>7}{'broken':>8}{'ms':>7}")
        for way, rows in scored.items():
            mine = [id for id in ids if id in rows]
            if not mine:
                continue
            total = sum(len(references[id]) for id in mine)
            s, d, n = (sum(rows[id][k] for id in mine) for k in range(3))
            fixed = sum(len(rows[id][3] - right.get(id, rows[id][3])) for id in mine)
            broken = sum(len(right.get(id, rows[id][3]) - rows[id][3]) for id in mine)
            times = [rows[id][4] for id in mine if rows[id][4] is not None]
            ms = f"{statistics.median(times):.0f}" if times else ""
            print(f"{indent}{way:<18}{len(mine):>6}{total:>7}{(s + d + n) / max(total, 1) * 100:>7.2f}%{d:>9}{n:>7}{fixed:>7}{broken:>8}{ms:>7}")

    table(list(references))
    labels = sorted({k for c in clips.values() for k, v in c.items() if isinstance(v, str) and k not in ("id", "audio_path", "date", "source")})
    for label in labels:
        for value in sorted({c[label] for c in clips.values() if label in c}):
            print(f"\n{label}: {value}")
            table([id for id in references if clips.get(id, {}).get(label) == value], "  ")
    if "--misses" in sys.argv:
        way = sys.argv[sys.argv.index("--misses") + 1]
        misses = collections.Counter()
        for id, (heard, _) in ways[way].items():
            for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, references.get(id, heard), heard, autojunk=False).get_opcodes():
                if tag != "equal":
                    misses[" ".join(references[id][i1:i2]), " ".join(heard[j1:j2])] += 1
        print(f"\n{way} misses, as the final has them → as written:")
        for (final, written), count in misses.most_common(60):
            print(f"{count:>4}  {final or '·'} → {written or '·'}")


if __name__ == "__main__":
    main()
