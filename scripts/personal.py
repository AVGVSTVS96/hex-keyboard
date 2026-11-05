"""Fine-tunes the shipped next-word network (scripts/network.py) on what its owner types, and packs it as another en.network.

Input: a record.jsonl as sources/record.ts writes it (the text of each line, of the kinds a person types prose in), or any
file of text lines. Lines are kept whole, with near-repeats dropped, since the record holds a field's text
again each time it's saved.

Only the output side learns: the embedding (which also scores the next word), the projection and the output biases. The
LSTM stays as shipped, so its int8 rows are copied byte for byte and the file stays the size it was. Learning stops at the
pass where 10% of the lines, kept aside, are best predicted; when no pass beats the shipped network, the output is the
shipped file.

Usage: scripts/personal record.jsonl [en.network [out]]
Defaults: the shipped network in the repo, and ~/.local/share/iikb/backup/mirror/personal/en.network, where
server/backup.ts gives it back to the iPhone. With --daily it does nothing when the output is under a day old and newer
than both inputs, which is what the systemd path unit iikb-personal runs.
"""

import json
import math
import os
import re
import struct
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import network

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIPPED = f"{ROOT}/Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.network"
MIRROR = os.path.expanduser("~/.local/share/iikb/backup/mirror/personal/en.network")
KINDS = {"text", "webSearch", "twitter"}
WINDOW, BATCH, RATE, PASSES, HELD = 32, 32, 1e-3, 8, 0.1


def read_network(raw):
    """The words and every section of an en.network (the layout is in Network.swift), the matrices as int8 rows."""
    assert raw[:4] == b"HXN1"
    words, width, hidden, spelled = struct.unpack_from("<4I", raw, 4)
    offsets = struct.unpack_from(f"<{words}I", raw, 20)
    spellings = raw[20 + 4 * words:20 + 4 * words + spelled]
    vocabulary = [spellings[o:spellings.index(b"\0", o)].decode() for o in offsets]
    scales_at = (20 + 4 * words + spelled + 4 * words + 3) // 4 * 4
    rows = [words, 4 * hidden, 4 * hidden, width]
    n_scales = words + 8 * hidden + width
    n_biases = 4 * hidden + width + words
    scales = np.frombuffer(raw, "<f4", n_scales, scales_at)
    biases = np.frombuffer(raw, "<f4", n_biases, scales_at + 4 * n_scales)
    at = scales_at + 4 * (n_scales + n_biases)
    cols = [width, width, hidden, hidden]
    matrices = []
    for count, size in zip(rows, cols):
        matrices.append(np.frombuffer(raw, np.int8, count * size, at).reshape(count, size))
        at += count * size
    assert at == len(raw)
    split = np.cumsum(rows)[:-1]
    return dict(vocabulary=vocabulary, width=width, hidden=hidden, head=raw[:scales_at], scales=np.split(scales, split),
                gates=biases[:4 * hidden], proj_bias=biases[4 * hidden:4 * hidden + width], output=biases[4 * hidden + width:],
                emb=matrices[0], input=matrices[1], recurrent=matrices[2], proj=matrices[3])


def quantize(matrix):
    """Each row as int8 with its own scale, as Network.init(vocabulary:...) does it, in float32 and rounding halves away from zero."""
    matrix = np.asarray(matrix, dtype=np.float32)
    scale = np.maximum(np.abs(matrix).max(axis=1), np.finfo(np.float32).tiny) / np.float32(127)
    scaled = matrix / scale[:, None]
    return (np.sign(scaled) * np.floor(np.abs(scaled) + np.float32(0.5))).astype(np.int8), scale.astype(np.float32)


def pack(net, emb, proj, proj_bias, output):
    emb, emb_scale = quantize(emb)
    proj, proj_scale = quantize(proj)
    scales = [emb_scale, net["scales"][1], net["scales"][2], proj_scale]
    parts = [net["head"], *(s.astype("<f4").tobytes() for s in scales), net["gates"].astype("<f4").tobytes(),
             proj_bias.astype("<f4").tobytes(), output.astype("<f4").tobytes(), emb.tobytes(), net["input"].tobytes(),
             net["recurrent"].tobytes(), proj.tobytes()]
    return b"".join(parts)


def lines(path):
    """The lines to learn from, in the order they were typed."""
    with open(path) as file:
        if path.endswith(".jsonl"):
            texts = []
            for line in file:
                entry = json.loads(line)
                if entry.get("kind", "text") in KINDS:
                    texts.append(entry["text"])
        else:
            texts = [file.read()]
    seen, out = set(), []
    for line in (re.sub(r"\s+", " ", line).strip() for text in texts for line in text.split("\n")):
        words = re.findall(r"[a-z']+", line.lower())
        if not words:
            continue
        shingles = {tuple(words[i:i + 5]) for i in range(max(1, len(words) - 4))}
        if len(shingles & seen) > 0.3 * len(shingles):
            continue
        seen |= shingles
        out.append(line)
    return out


def fine_tune(net, corpus):
    import torch
    from torch import nn
    torch.set_num_threads(4)
    torch.manual_seed(0)
    ids = {word: i for i, word in enumerate(net["vocabulary"])}
    words = len(ids)
    held = max(1, int(len(corpus) * HELD))

    def encode(part):
        return np.array([ids.get(t, 1) for line in part for t in network.tokens(line)], dtype=np.int64)

    fit, check = encode(corpus[:-held]), encode(corpus[-held:])
    dequantized = lambda name, i: torch.from_numpy(net[name].astype(np.float32) * net["scales"][i][:, None])
    emb, proj = dequantized("emb", 0).clone(), dequantized("proj", 3).clone()
    lstm = nn.LSTM(net["width"], net["hidden"], batch_first=True)
    with torch.no_grad():
        lstm.weight_ih_l0.copy_(dequantized("input", 1))
        lstm.weight_hh_l0.copy_(dequantized("recurrent", 2))
        lstm.bias_ih_l0.copy_(torch.from_numpy(net["gates"].copy()))
        lstm.bias_hh_l0.zero_()
    for p in lstm.parameters():
        p.requires_grad = False
    proj_bias = torch.from_numpy(net["proj_bias"].copy())
    output = torch.from_numpy(net["output"].copy())
    params = [emb, proj, proj_bias, output]
    for p in params:
        p.requires_grad = True

    def forward(x):
        return (lstm(emb[x])[0] @ proj.T + proj_bias) @ emb.T + output

    loss = nn.CrossEntropyLoss()

    def held_out():
        count = (len(check) - 1) // WINDOW
        total = 0.0
        with torch.no_grad():
            for start in range(0, count, 64):
                batch = torch.from_numpy(np.stack([check[j * WINDOW:j * WINDOW + WINDOW + 1] for j in range(start, min(count, start + 64))]))
                total += loss(forward(batch[:, :-1]).reshape(-1, words), batch[:, 1:].reshape(-1)).item() * len(batch)
        return total / count

    best = (held_out(), None)
    print(f"{len(fit)} tokens to learn from, {len(check)} held out; shipped {best[0]:.3f}", file=sys.stderr)
    optimizer = torch.optim.Adam(params, lr=RATE)
    rng = np.random.default_rng(0)
    for step in range(1, PASSES + 1):
        for _ in range(len(fit) // (WINDOW * BATCH) + 1):
            starts = rng.integers(0, len(fit) - WINDOW - 1, BATCH)
            batch = torch.from_numpy(np.stack([fit[s:s + WINDOW + 1] for s in starts]))
            error = loss(forward(batch[:, :-1]).reshape(-1, words), batch[:, 1:].reshape(-1))
            optimizer.zero_grad()
            error.backward()
            optimizer.step()
        now = held_out()
        print(f"pass {step} held out {now:.3f}", file=sys.stderr)
        if now < best[0]:
            best = (now, [p.detach().numpy().copy() for p in params])
    return best[1]


def main():
    daily = "--daily" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--daily"]
    record, source, out = args[0], (args[1] if len(args) > 1 else SHIPPED), (args[2] if len(args) > 2 else MIRROR)
    if daily and os.path.exists(out) and time.time() - os.path.getmtime(out) < 86400 and os.path.getmtime(out) > os.path.getmtime(source):
        return
    raw = open(source, "rb").read()
    net = read_network(raw)
    corpus = lines(record)
    if len(corpus) < 20:
        print("too little to learn from", file=sys.stderr)
        return
    learned = fine_tune(net, corpus)
    result = raw if learned is None else pack(net, *learned)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out + ".part", "wb") as file:
        file.write(result)
    os.replace(out + ".part", out)
    print(f"{len(corpus)} lines, {len(result)} bytes, {'shipped network kept' if learned is None else 'fine-tuned'}", file=sys.stderr)


if __name__ == "__main__":
    main()
