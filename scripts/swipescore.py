#!/usr/bin/env python3
"""Scores swipebench outputs side by side: scripts/swipescore.py name=out.tsv [name=out.tsv ...]"""
import sys


def load(path):
    rows = {}
    for line in open(path):
        index, target, typed, *bar = line.rstrip("\n").split("\t") + [""]
        rows[int(index)] = (target.lower(), typed.lower(), [w.lower() for w in bar[0].split("|") if w])
    return rows


runs = [(arg.split("=", 1)[0], load(arg.split("=", 1)[-1])) for arg in sys.argv[1:]]
common = sorted(set.intersection(*(set(rows) for _, rows in runs)))
print(f"{len(common)} swipes")
print(f"{'':10}{'top-1':>8}{'top-3':>8}")
for name, rows in runs:
    top1 = sum(rows[i][0] == rows[i][1] for i in common)
    top3 = sum(rows[i][0] == rows[i][1] or rows[i][0] in rows[i][2][:3] for i in common)
    print(f"{name:10}{100 * top1 / len(common):7.1f}%{100 * top3 / len(common):7.1f}%")
