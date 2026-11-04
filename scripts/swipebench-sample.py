import json, random, sys
from wordfreq import zipf_frequency
src, out = sys.argv[1], sys.argv[2]
bins = [(5.5, 9), (4.8, 5.5), (4.2, 4.8), (3.6, 4.2), (3.0, 3.6)]
pool = {b: [] for b in bins}
for line in open(src):
    r = json.loads(line)
    w = r['word']
    if r['orientation'] != 'portrait-primary' or r['potentially_invalid_sentence'] or r['distance'] > 60: continue
    if len(w) < 2 or not w.isascii() or not w.isalpha() or not (w.islower() or (r['word_idx'] == 0 and w[1:].islower())): continue
    if len(r['data']) < 8: continue
    z = zipf_frequency(w.lower(), 'en')
    for b in bins:
        if b[0] <= z < b[1]: pool[b].append((w.lower(), r))
rng = random.Random(798)
rows, seen = [], set()
for b in bins:
    rng.shuffle(pool[b])
    n = 0
    for w, r in pool[b]:
        if w in seen: continue
        seen.add(w); n += 1
        t0 = r['data'][0]['t']
        path = ';'.join(f"{round(p['x']*1000)},{round(p['y']*1000)},{p['t']-t0}" for p in r['data'])
        rows.append((w, path))
        if n == 80: break
rng.shuffle(rows)
with open(out, 'w') as f:
    f.write("# Swipes from futo-org/swipe.futo.org (test split of swipe-1), MIT, Copyright (c) 2025 FUTO. Sample: seed 798, 80 words in each of 5 frequency bands.\n")
    f.write("# word<TAB>x,y,ms;... with x,y in thousandths of the dataset's keyboard frame (layouts/qwerty.json: rows at y 1/6, 1/2, 5/6) and ms since touch down\n")
    for w, p in rows: f.write(f"{w}\t{p}\n")
print(len(rows), {b: len(pool[b]) for b in bins})
