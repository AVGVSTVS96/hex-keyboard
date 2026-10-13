"""Writes the emoji keyboard's catalog from Unicode's emoji-test.txt: python3 scripts/emoji.py <emoji-test.txt> <out>

Groups are merged and ordered the way Apple's emoji keyboard shows them. Each line is an emoji, followed by its five
skin tones when it has them; a line starting with "# " starts a category.
"""
import sys

CATEGORIES = [
    ("Smileys & People", ["Smileys & Emotion", "People & Body"]),
    ("Animals & Nature", ["Animals & Nature"]),
    ("Food & Drink", ["Food & Drink"]),
    ("Activity", ["Activities"]),
    ("Travel & Places", ["Travel & Places"]),
    ("Objects", ["Objects"]),
    ("Symbols", ["Symbols"]),
    ("Flags", ["Flags"]),
]
TONES = [chr(c) for c in range(0x1F3FB, 0x1F400)]


def plain(emoji):
    return "".join(c for c in emoji if c not in TONES and c != "️")


def main(source, out):
    groups, group = {}, None
    for line in open(source, encoding="utf-8"):
        if line.startswith("# group: "):
            group = groups.setdefault(line[9:].strip(), [])
        elif "; fully-qualified" in line:
            group.append(line.split("# ", 1)[1].split(" ", 1)[0])

    lines = []
    for name, sources in CATEGORIES:
        lines.append(f"# {name}")
        emoji = [e for source in sources for e in groups[source]]
        tones = {}
        for e in emoji:
            used = {c for c in e if c in TONES}
            if len(used) == 1:
                tones.setdefault(plain(e), []).append(e)
        for e in emoji:
            if any(c in TONES for c in e):
                continue
            variants = tones.get(plain(e), [])
            lines.append(" ".join([e] + variants) if len(variants) == 5 else e)
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
