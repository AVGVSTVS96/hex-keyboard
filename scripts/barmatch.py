"""Scores iikb's suggestion bar against Apple's on the same text: python3 scripts/barmatch.py apple.txt iikb.txt [...]

Each file has one line per word typed: segment|position|word|bar before it|bar after its 1st letter|after its 2nd,
each bar its suggestions left to right, comma-separated, the typed letters in quotes (scripts/applebar's format).
"""
import sys

STAGES = ["before the word", "after 1 letter", "after 2 letters"]


def norm(s):
    return s.strip().lower().replace("’", "'")


def bars(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        f = line.rstrip("\n").split("|")
        if len(f) < 4:
            continue
        words = [[norm(x) for x in b.split(",") if x.strip() and not x.startswith("“")] for b in f[3:6]]
        out[(f[0], f[1])] = (norm(f[2]), words)
    return out


def score(apple, other):
    rows = []
    for key, (word, a_bars) in apple.items():
        if key not in other:
            continue
        o_bars = other[key][1]
        for k, a in enumerate(a_bars):
            if not a or k >= len(o_bars):
                continue
            rows.append((k, word, a, o_bars[k][:3]))
    return rows


def pct(n, d):
    return f"{100 * n / d:5.1f}%" if d else "    -"


def report(name, rows):
    print(name)
    print(f"  {'':16} {'bars':>5} {'shown':>7} {'same':>7} {'top':>7} | {'word: Apple':>11} {'iikb':>7} {'only iikb':>9} {'only Apple':>10}")
    for k in [None, 0, 1, 2]:
        sel = [r for r in rows if k is None or r[0] == k]
        if not sel:
            continue
        shown = sum(len(set(a) & set(o)) for _, _, a, o in sel)
        total = sum(len(set(a)) for _, _, a, o in sel)
        same = sum(set(a) == set(o) for _, _, a, o in sel)
        top = sum(bool(o) and o[0] in a for _, _, a, o in sel)
        ah = sum(w in a for _, w, a, o in sel)
        oh = sum(w in o for _, w, a, o in sel)
        only_o = sum(w in o and w not in a for _, w, a, o in sel)
        only_a = sum(w in a and w not in o for _, w, a, o in sel)
        n = len(sel)
        label = "all" if k is None else STAGES[k]
        print(f"  {label:16} {n:5} {pct(shown, total)} {pct(same, n)} {pct(top, n)} | {pct(ah, n):>11} {pct(oh, n)} {pct(only_o, n):>9} {pct(only_a, n):>10}")


if __name__ == "__main__":
    apple = bars(sys.argv[1])
    for path in sys.argv[2:]:
        report(path, score(apple, bars(path)))
    print("shown: of Apple's bar words, how many iikb's bar shows too. same: the bar shows Apple's exact words.")
    print("top: iikb's first pick is one of Apple's. word: the word typed next is in the bar.")
