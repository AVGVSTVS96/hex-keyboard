"""Word error rate of each <corpus>/outputs/*.jsonl against <corpus>/references.jsonl, with dropped and added words."""
import json, re, sys
from pathlib import Path

def words(text):
    return re.findall(r"[a-z0-9]+(?:'[a-z0-9]+)*", text.lower().replace("’", "'"))

def edits(reference, hypothesis):
    """Substitutions, deletions and insertions on a minimum-edit alignment."""
    rows = [(j, 0, 0, j) for j in range(len(hypothesis) + 1)]
    for i, word in enumerate(reference, 1):
        row = [(i, 0, i, 0)]
        for j, heard in enumerate(hypothesis, 1):
            options = [(rows[j - 1][0] + (word != heard), rows[j - 1], (word != heard, 0, 0)),
                       (rows[j][0] + 1, rows[j], (0, 1, 0)), (row[j - 1][0] + 1, row[j - 1], (0, 0, 1))]
            cost, (_, s, d, n), (ds, dd, dn) = min(options, key=lambda o: o[0])
            row.append((cost, s + ds, d + dd, n + dn))
        rows = row
    return rows[-1][1:]

def main():
    corpus = Path(sys.argv[1])
    references = {r["id"]: r["text"] for r in map(json.loads, (corpus / "references.jsonl").open())}
    print(f"{'way':<16}{'clips':>6}{'wrong':>8}{'dropped':>9}{'added':>7}")
    for path in sorted((corpus / "outputs").glob("*.jsonl")):
        total = subs = drops = adds = clips = 0
        for row in map(json.loads, path.open()):
            if row["id"] not in references: continue
            reference = words(references[row["id"]])
            s, d, n = edits(reference, words(row["text"]))
            total, subs, drops, adds, clips = total + len(reference), subs + s, drops + d, adds + n, clips + 1
        print(f"{path.stem:<16}{clips:>6}{(subs + drops + adds) / max(total, 1) * 100:>7.2f}%{drops:>9}{adds:>7}")


if __name__ == "__main__":
    main()
