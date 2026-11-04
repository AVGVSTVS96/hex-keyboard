"""Trains the next-word network behind Packages/HexKeyboard/Sources/KeyboardUI/Resources/en.network.

Corpus: what people type to each other and to chatbots. Reddit comments from 16 subreddits, 7M words from the first
file of each (HuggingFaceGECLM/REDDIT_comments, with links and Markdown taken out), the English user turns of
WildChat-4.8M, and two in five lines of WildChat-1M's with SODA's dialogues (allenai; ODC-BY, CC BY 4.0). Lines are
kept when they read as prose: mostly letters, at most 120 words, no code or markup characters. A chatbot line repeated
within its source is dropped by its first 60 characters.

Tokens: lowercase words (apostrophes kept), a comma, a number, and a sentence's start; the 20,000 commonest words and
the specials are the vocabulary, every other word one unknown token.

Model: a word embedding (128 wide, also scoring the next word) into one LSTM layer (768 wide) projected back to the
embedding, trained on 32-token windows, 256 at a time, for 30,000 steps (Adam, one-cycle learning rate to 3e-3).
About two hours on an M1 Max's GPU; on a CPU, days.

Usage: uv run --no-project --with pyarrow --with numpy --with torch python3 scripts/network.py build/network
Each stage is skipped when its output is there: reddit.txt, wildchat.txt and chat.txt, vocab.txt and tokens.npy, model.pt, then
weights.f32 (the widths and the float32 tensors in Network's order), which scripts/network packs with Tools/NetworkBuilder.
"""

import hashlib
import math
import os
import random
import re
import subprocess
import sys
from collections import Counter

HUB = "https://huggingface.co/datasets"
WILDCHAT = [(f"allenai/WildChat-4.8M/resolve/main/data/train-{i:05d}-of-00086.parquet") for i in range(86)]
WILDCHAT_1M = [(f"allenai/WildChat-1M/resolve/main/data/train-{i:05d}-of-00014.parquet") for i in range(14)]
SODA = ["allenai/soda/resolve/main/train.parquet"]
REDDIT = [f"HuggingFaceGECLM/REDDIT_comments/resolve/main/data/{name}.parquet" for name in [
    "IAmA-00000-of-00019-06736ec34c459e98", "LifeProTips-00000-of-00011-3a9e835a552d2710",
    "Showerthoughts-00000-of-00027-6e7342a5eac6f96c", "buildapc-00000-of-00020-0382afa88fc5d8f8",
    "changemyview-00000-of-00018-12261008ea895e29", "explainlikeimfive-00000-of-00017-21d7b92cb6f7a8ba",
    "gaming-00000-of-00057-943c09de1b2d3604", "mildlyinteresting-00000-of-00019-99c7f919d3e81fa6",
    "personalfinance-00000-of-00019-4a7e59196197a2c1", "podcasts-00000-of-00001-9af2599ee776d606",
    "programming-00000-of-00007-682384b233d9a62b", "relationship_advice-00000-of-00045-da08cc6ebcf82ddb",
    "socialskills-00000-of-00003-775ee50d8a579123", "technology-00000-of-00022-7a3b7f76ceb7c961",
    "tifu-00000-of-00010-b52d0440151617c8", "todayilearned-00000-of-00046-2ed2870d54c80544",
]]
REDDIT_WORDS = 7_000_000
SOURCES = {"reddit.txt": 1.0, "wildchat.txt": 1.0, "chat.txt": 0.4}

VOCABULARY = 20_000
SPECIALS = ["<s>", "<unk>", "<n>", ","]
TOKEN = re.compile(r"[a-z0-9]+(?:'[a-z0-9]+)*|[.!?,]")
WIDTH, HIDDEN, WINDOW, BATCH, STEPS, RATE = 128, 768, 32, 256, 30_000, 3e-3

out = sys.argv[1]
os.makedirs(os.path.join(out, "download"), exist_ok=True)


def path(name):
    return os.path.join(out, name)


def download(files):
    paths = []
    for file in files:
        local = path(os.path.join("download", file.replace("/", "_")))
        if not os.path.exists(local):
            subprocess.run(["curl", "-sfL", "-o", local + ".part", f"{HUB}/{file}"], check=True)
            os.rename(local + ".part", local)
        paths.append(local)
    return paths


def prose(text, markup=r"[{};<>=_\\|`#*@\[\]]"):
    for line in text.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"').split("\n"):
        line = re.sub(r"\s+", " ", line).strip()
        if not line or len(line.split()) > 120:
            continue
        if sum(c.isalpha() for c in line) < 0.7 * len(line.replace(" ", "")):
            continue
        if re.search(markup, line):
            continue
        yield line


def write_unique(name, lines):
    seen = set()
    with open(path(name), "w") as file:
        for line in lines:
            key = hashlib.md5(line.lower()[:60].encode()).digest()
            if key not in seen:
                seen.add(key)
                file.write(line + "\n")


def user_turns(files):
    import pyarrow.parquet as pq
    for file in files:
        table = pq.read_table(file, columns=["conversation", "language"])
        for conversation, language in zip(table.column("conversation").to_pylist(), table.column("language").to_pylist()):
            if language != "English":
                continue
            for message in conversation:
                if message["role"] == "user" and message.get("language") == "English" and len(message["content"].split()) <= 300:
                    yield from prose(message["content"])


def dialogues(files):
    import pyarrow.parquet as pq
    for file in files:
        for dialogue in pq.read_table(file, columns=["dialogue"]).column("dialogue").to_pylist():
            for turn in dialogue:
                yield from prose(turn)


def comments(files):
    import pyarrow.parquet as pq
    for file in files:
        words = 0
        for batch in pq.ParquetFile(file).iter_batches(columns=["body"], batch_size=5000):
            for body in batch.column("body").to_pylist():
                if not body or body in ("[deleted]", "[removed]"):
                    continue
                body = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", body)
                body = re.sub(r"https?://\S+|www\.\S+|/?[ru]/\w+", "", body).replace("&amp;", "&")
                body = "\n".join(line.strip().lstrip(">") for line in body.split("\n"))
                for line in prose(body, markup=r"[{};<>=_\\|`#*@\[\]^~]"):
                    words += len(line.split())
                    yield line
            if words >= REDDIT_WORDS:
                break


def corpus():
    if not os.path.exists(path("reddit.txt")):
        with open(path("reddit.txt"), "w") as file:
            file.writelines(line + "\n" for line in comments(download(REDDIT)))
    if not os.path.exists(path("wildchat.txt")):
        write_unique("wildchat.txt", user_turns(download(WILDCHAT)))
    if not os.path.exists(path("chat.txt")):
        write_unique("chat.txt", (line for source in (user_turns(download(WILDCHAT_1M)), dialogues(download(SODA))) for line in source))


def tokens(line):
    out = ["<s>"]
    for token in TOKEN.findall(line.lower().replace("’", "'")):
        if token in ".!?":
            if out[-1] != "<s>":
                out.append("<s>")
        elif token == ",":
            out.append(",")
        elif any(c.isdigit() for c in token):
            out.append("<n>")
        else:
            out.append(token)
    return out


def prepare():
    import numpy as np
    if os.path.exists(path("tokens.npy")):
        return
    lines = []
    for name, keep in SOURCES.items():
        sample = random.Random(1)
        lines += [line for line in open(path(name)) if sample.random() < keep]
    random.Random(2).shuffle(lines)
    counts = Counter(t for line in lines for t in tokens(line) if t not in SPECIALS)
    vocabulary = SPECIALS + [word for word, _ in counts.most_common(VOCABULARY - len(SPECIALS))]
    ids = {word: i for i, word in enumerate(vocabulary)}
    with open(path("vocab.txt"), "w") as file:
        file.write("\n".join(vocabulary) + "\n")
    total = sum(len(tokens(line)) for line in lines)
    array = np.lib.format.open_memmap(path("tokens.npy.part"), mode="w+", dtype=np.uint16, shape=(total,))
    at = 0
    for line in lines:
        row = [ids.get(word, 1) for word in tokens(line)]
        array[at:at + len(row)] = row
        at += len(row)
    array.flush()
    del array
    os.rename(path("tokens.npy.part"), path("tokens.npy"))


def train():
    import numpy as np
    import torch
    from torch import nn
    if os.path.exists(path("model.pt")):
        return
    torch.manual_seed(0)
    device = torch.device("mps" if torch.backends.mps.is_available() else "cuda" if torch.cuda.is_available() else "cpu")
    words = len(open(path("vocab.txt")).read().split("\n")) - 1
    data = np.load(path("tokens.npy"), mmap_mode="r")
    held = 2_000_000
    training, validation = data[:-held], data[-held:]

    class Model(nn.Module):
        def __init__(self):
            super().__init__()
            self.emb = nn.Embedding(words, WIDTH)
            self.lstm = nn.LSTM(WIDTH, HIDDEN, batch_first=True)
            self.proj = nn.Linear(HIDDEN, WIDTH)
            self.bias = nn.Parameter(torch.zeros(words))

        def forward(self, x):
            return self.proj(self.lstm(self.emb(x))[0]) @ self.emb.weight.T + self.bias

    model = Model().to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=RATE)
    schedule = torch.optim.lr_scheduler.OneCycleLR(optimizer, max_lr=RATE, total_steps=STEPS, pct_start=0.05)
    loss = nn.CrossEntropyLoss()
    rng = np.random.default_rng(0)

    def batch(source):
        starts = rng.integers(0, len(source) - WINDOW - 1, BATCH)
        x = torch.from_numpy(np.stack([source[s:s + WINDOW + 1] for s in starts]).astype(np.int64)).to(device)
        return x[:, :-1], x[:, 1:]

    for step in range(1, STEPS + 1):
        x, y = batch(training)
        error = loss(model(x).reshape(-1, words), y.reshape(-1))
        optimizer.zero_grad()
        error.backward()
        nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        optimizer.step()
        schedule.step()
        if step % 2000 == 0 or step == STEPS:
            with torch.no_grad():
                x, y = batch(validation)
                held_out = loss(model(x).reshape(-1, words), y.reshape(-1)).item()
            print(f"step {step} perplexity {math.exp(held_out):.1f}", file=sys.stderr, flush=True)
    torch.save({k: v.cpu() for k, v in model.state_dict().items()}, path("model.pt"))


def export():
    import numpy as np
    import torch
    state = torch.load(path("model.pt"))
    parts = [np.array([WIDTH, HIDDEN], dtype=np.float32), state["emb.weight"], state["lstm.weight_ih_l0"],
             state["lstm.weight_hh_l0"], state["lstm.bias_ih_l0"] + state["lstm.bias_hh_l0"], state["proj.weight"],
             state["proj.bias"], state["bias"]]
    with open(path("weights.f32"), "wb") as file:
        for part in parts:
            file.write(np.asarray(part, dtype="<f4").tobytes())


if __name__ == "__main__":
    corpus()
    prepare()
    train()
    export()
