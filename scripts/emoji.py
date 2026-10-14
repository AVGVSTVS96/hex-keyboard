"""Writes the emoji keyboard's catalog: python3 scripts/emoji.py <emoji-test.txt> <annotations en.xml> <emoji-frequency.html> <out>

Sources: Unicode's emoji-test.txt (the emoji), CLDR's English annotations (each emoji's name and keywords) and the page
of Unicode's emoji frequency (how often each emoji is used, https://home.unicode.org/emoji/emoji-frequency/).

Groups are merged and ordered the way Apple's emoji keyboard shows them. Each line is an emoji, followed by its five
skin tones when it has them, then a tab, its rank by use (0 is the most used) and a tab, then its name and keywords
separated by "|"; a line starting with "# " starts a category.
"""
import html
import re
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


def annotations(source):
    words = {}
    for cp, kind, text in re.findall(r'<annotation cp="([^"]+)"( type="tts")?>([^<]*)</annotation>', open(source, encoding="utf-8").read()):
        entry = words.setdefault(html.unescape(cp).replace("️", ""), [[], []])
        entry[0 if kind else 1] += [w.strip().lower() for w in html.unescape(text).split("|") if w.strip()]
    return {cp: names + [k for k in keywords if k not in names] for cp, (names, keywords) in words.items()}


def ranks(source):
    order = []
    for row in re.findall(r"<tr.*?</tr>", open(source, encoding="utf-8").read(), re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<td.*?</td>", row, re.S)]
        order += [e.replace("️", "") for c in cells[1:] for e in c.split() if e != "…"]
    return {e: i for i, e in reversed(list(enumerate(order)))}


def main(source, cldr, frequency, out):
    groups, group, names = {}, None, {}
    for line in open(source, encoding="utf-8"):
        if line.startswith("# group: "):
            group = groups.setdefault(line[9:].strip(), [])
        elif "; fully-qualified" in line:
            emoji, name = line.split("# ", 1)[1].split(" ", 2)[::2]
            group.append(emoji)
            names[emoji] = name.strip().lower()
    words, rank = annotations(cldr), ranks(frequency)
    unranked = len(rank)

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
            key = e.replace("️", "")
            keywords = words.get(key) or [names[e]]
            lines.append("\t".join([" ".join([e] + variants) if len(variants) == 5 else e, str(rank.get(key, unranked)), "|".join(keywords)]))
    open(out, "w", encoding="utf-8").write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
