"""scripts/voiceloop: iikb's whole dictation path, from the sound to what the keyboard types, scored against what each
dictation should have become, on three sets (each in voicebench/ beside the backup, never the repo):

real: Bassim's own dictations (scripts/voicecorpus.py), against what each finally became, and loud, the quiet ones
mixed into his loud rooms, speech as said and 6, 12 and 18 dB quieter (a whisper).
spoken: scripts/voicespoken.txt's made-up sentences said by macOS voices, normal and whispered, in a quiet room and in
his loud ones, against what iikb must type for each.

Each clip goes through Parakeet v3 as the app runs it (Tools/VoiceBench, on the Mac's Neural Engine, one turn at a
time), once per clip and version of that path: what it wrote is kept in voicebench/cache/, keyed by the clip's sound
and the path's code, so a run whose sound and Parakeet path are unchanged never touches the Mac. Then the rest of the
iPhone's path here (Tools/VoiceBench/Text, on KeyboardCore): the app's writing style and Dictionary, then the keyboard's
reading of the field it went into, after the text before it there, with the words the keyboard has seen typed (its
saved memory in the backup). The real set is replayed with the iPhone's own settings, the spoken set with the defaults.

Prints, for each set and each group of its clips, the share of words wrong (um and uh set aside, case and punctuation
too) and the share of dictations typed exactly; for the real set the same for what the iPhone typed, and how often the
bench wrote and typed what the iPhone did. Then every word wrong ranked by what kind of thing it was in the reference
(emails, links, versions, times, money, digits, names, words misheard, dropped or added) and every word right but
punctuated or capitalized wrong, written with examples to voicebench/categories.txt, and each dictation's texts to
voicebench/<set>/loop.jsonl: Bassim's words stay there and on this terminal. Against his finals, which keep what the
build of their day typed and lack what he cut after, "cut later" and "number form" are set aside (`diff`).
"""
import collections, concurrent.futures, difflib, fcntl, hashlib, importlib.util, json, os, plistlib, random, re, shutil, subprocess, sys, time
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
BACKUP = Path(os.environ.get("IIKB_BACKUP", Path.home() / ".local/share/iikb/backup"))
DATA = BACKUP.parent / "voicebench"
LEXICON = ROOT / "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon"
MEMORY = BACKUP / "mirror/keyboard/support/typing-memory.json"
VOICES = ["Samantha", "Daniel", "Karen", "Moira", "Rishi", "Tessa"]
DEFAULTS = ["casual", "asSaid", "numbered", "on"]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"scripts/{name}.py")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


corpus, score = module("voicecorpus"), module("voicescore")


def rows(path):
    return [json.loads(line) for line in path.open()] if path.exists() else []


def lines(path, items):
    path.write_text("".join(json.dumps(item) + "\n" for item in items))


def digest(*parts):
    h = hashlib.sha256()
    for part in parts:
        h.update(part if isinstance(part, bytes) else str(part).encode())
    return h.hexdigest()[:20]


def real():
    """The real and loud sets, built again whenever the backup or the builder has changed since."""
    built = DATA / "real/context.jsonl"
    sources = [BACKUP / "mirror/app/transcripts.jsonl", BACKUP / "mirror/app/vocabulary.json", BACKUP.parent / "record.jsonl",
               ROOT / "scripts/voicecorpus.py"]
    if not built.exists() or max(p.stat().st_mtime for p in sources) > built.stat().st_mtime:
        subprocess.run([sys.executable, ROOT / "scripts/voicecorpus.py"], check=True)


def settings():
    """The iPhone's writing settings, as SettingsStore reads them from the App Group."""
    path = BACKUP / "mirror/group/Library/Preferences/group.com.shahidy.iikb.plist"
    kept = plistlib.load(path.open("rb")) if path.exists() else {}
    lists = kept.get("spokenLists") or ({True: "numbered", False: "off"}.get(kept.get("dictationLists")) or DEFAULTS[2])
    editing = kept.get("dictationEditing") or ({True: "asSaid", False: "light"}.get(kept.get("keepsUmAndUh")) or DEFAULTS[1])
    return [kept.get("writingStyle", DEFAULTS[0]), editing, lists, "off" if kept.get("autoCapitalization") is False else "on"]


def cases(dictionary):
    """voicespoken.txt's lines, each {name} line once for two stand-ins and two Dictionary names, in turn."""
    names, topic, out, n = [], "", [], 0
    picks = [t["term"] for t in dictionary if re.fullmatch(r"[A-Z][a-z]+", t["term"])]
    random.Random(806).shuffle(picks)
    for line in (ROOT / "scripts/voicespoken.txt").read_text().splitlines():
        if line.startswith("names:"):
            names = line.split()[1:]
        elif line.startswith("# ") and not out and not names:
            continue
        elif line.startswith("# "):
            topic = line[2:]
        elif line.strip() and not line.startswith("#"):
            parts = line.split(" | ")
            field, said, typed = (parts if len(parts) == 3 else ["text", *parts])
            if "name}" not in line:
                out.append(dict(topic=topic, field=field, say=said, typed=typed, name="none"))
                continue
            n += 1
            for name, kind in [(names[(2 * n + k) % len(names)], "stand-in") for k in (0, 1)] + \
                              [(picks[(2 * n + k) % len(picks)], "Dictionary") for k in (0, 1) if picks]:
                fill = lambda s: s.replace("{lname}", name.lower()).replace("{name}", name)
                out.append(dict(topic=topic, field=field, say=fill(said), typed=fill(typed), name=kind))
    return out, names


def spoken():
    """The spoken set: each case said by three of the voices (in turn) and by Whisper on the Mac, kept in
    voicebench/said/, then each normal voice in a quiet room, in Bassim's loud room, and 18 dB softer in it, and Whisper
    in a quiet room and the loud one, each mixed as voicecorpus mixes the loud set."""
    vocabulary = json.load((BACKUP / "mirror/app/vocabulary.json").open())
    all_cases, names = cases(vocabulary["terms"])
    said_dir = DATA / "said"
    said_dir.mkdir(parents=True, exist_ok=True)
    plan = []
    for i, case in enumerate(all_cases):
        case["id"] = digest(case["field"], case["say"], case["typed"])
        for voice in [VOICES[(i + k * 2) % len(VOICES)] for k in range(3)] + ["Whisper"]:
            plan.append((case, voice, digest(voice, case["say"])))
    missing = sorted({(key, voice, case["say"]) for case, voice, key in plan if not (said_dir / f"{key}.wav").exists()})
    if missing:
        print(f"spoken: saying {len(missing)} clips on the Mac", flush=True)
        subprocess.run(["ssh", "mac", "mkdir -p ~/Developer/voicebench/said && cd ~/Developer/voicebench/said && xargs -0 -n 3 -P 3 "
                        "sh -c 'nice -n 19 say -v \"$1\" --data-format=LEI16@16000 -o \"$0.wav\" \"$2\"'"],
                       input="".join(f"{k}\0{v}\0{t}\0" for k, v, t in missing), text=True, check=True)
        subprocess.run(["rsync", "-a", "--remove-source-files", "mac:Developer/voicebench/said/", f"{said_dir}/"], check=True)

    clips = rows(DATA / "real/clips.jsonl")
    folder = DATA / "real"
    noisy = [c for c in clips if c["room"] == "loud"]
    bed = corpus.room(folder, noisy)
    loud_said = round(float(np.median([c["speech_db"] for c in noisy])))
    quiet_said = round(float(np.median([c["speech_db"] for c in clips if c["room"] == "quiet"])))
    out = DATA / "spoken"
    stamp = digest(bed.tobytes(), loud_said, quiet_said)
    if (out / "bed").exists() and (out / "bed").read_text() != stamp:
        shutil.rmtree(out)
    (out / "audio").mkdir(parents=True, exist_ok=True)
    (out / "bed").write_text(stamp)
    meta, references, context = [], [], []
    for case, voice, key in plan:
        conditions = [("whisper", "quiet", 0), ("whisper", "loud", 0)] if voice == "Whisper" else \
                     [("normal", "quiet", 0), ("normal", "loud", 0), ("soft", "loud", 18)]
        for speech, room, softer in conditions:
            name = f"{case['id']}-{voice}-{speech}-{room}"
            path = out / f"audio/{name}.wav"
            if not path.exists():
                samples = corpus.read(said_dir / f"{key}.wav")
                level = loud_said if room == "loud" else quiet_said
                samples = samples * 10 ** ((level - softer - corpus.levels(samples)[1]) / 20)
                if room == "loud":
                    start = random.Random(name).randrange(len(bed))
                    samples = samples + np.resize(np.roll(bed, -start), len(samples))
                corpus.write(path, samples / max(1, np.abs(samples).max() / 0.99))
            meta.append(dict(id=name, audio_path=f"audio/{name}.wav", voice=voice, speech=speech, room=room,
                             condition=f"{speech} in a {room} room", topic=case["topic"], field=case["field"], name=case["name"]))
            references.append(dict(id=name, text=case["typed"]))
            context.append(dict(id=name, field=case["field"], before=""))
    lines(out / "clips.jsonl", meta)
    lines(out / "references.jsonl", references)
    lines(out / "context.jsonl", context)
    vocabulary["terms"] += [{"term": n, "heardAs": []} for n in names]
    (out / "vocabulary.json").write_text(json.dumps(vocabulary))


def engine():
    """Tools/VoiceBench's Parakeet path as the Mac builds it: its package and sources, links followed."""
    tool = ROOT / "Tools/VoiceBench"
    files = [tool / "Package.swift", *sorted((tool / "Sources").rglob("*.swift"))]
    return digest(*(f"{f.relative_to(tool)}\n".encode() + f.read_bytes() for f in files))


def parakeet(sets, cached):
    """What Parakeet v3 writes for every clip of every set, from the cache, writing on the Mac only the clips it lacks,
    or with `cached` leaving those out."""
    cache_path = DATA / f"cache/parakeet-{engine()}.jsonl"
    cache_path.parent.mkdir(exist_ok=True)
    cache = {r["audio"]: r["text"] for r in rows(cache_path)}
    sounds = {}
    for name in sets:
        for clip in rows(DATA / name / "clips.jsonl"):
            path = DATA / name / clip["audio_path"]
            sounds[(name, clip["id"])] = (digest(path.read_bytes()), path)
    missing = {key: path for key, path in sounds.values() if key not in cache}
    if missing and cached:
        print(f"parakeet: leaving out {len(missing)} clips it hasn't written yet (--cached)")
    elif missing:
        print(f"parakeet: writing {len(missing)} of {len(sounds)} clips on the Mac", flush=True)
        pending = DATA / "pending"
        shutil.rmtree(pending, ignore_errors=True)
        (pending / "audio").mkdir(parents=True)
        for key, path in missing.items():
            os.link(path, pending / f"audio/{key}.wav")
        lines(pending / "clips.jsonl", [dict(id=k, audio_path=f"audio/{k}.wav") for k in missing])
        subprocess.run(["rsync", "-aL", "--delete", "--exclude", ".build", "--exclude", "Text", f"{ROOT}/Tools/VoiceBench/",
                        "mac:Developer/voicebench/tool/"], check=True)
        subprocess.run(["rsync", "-a", "--delete", f"{pending}/", "mac:Developer/voicebench/pending/"], check=True)
        subprocess.run(["ssh", "mac", "cd ~/Developer/voicebench && swift build -c release --package-path tool >/dev/null && "
                        "~/.local/bin/turn tool/.build/release/VoiceBench pending dictation 100"], check=True, stdin=subprocess.DEVNULL)
        subprocess.run(["rsync", "-a", "mac:Developer/voicebench/pending/outputs/dictation-100.jsonl", f"{pending}/written.jsonl"], check=True)
        subprocess.run(["ssh", "mac", "rm -rf ~/Developer/voicebench/pending"], check=True, stdin=subprocess.DEVNULL)
        written = rows(pending / "written.jsonl")
        with cache_path.open("a") as f:
            f.writelines(json.dumps(dict(audio=r["id"], text=r["text"], ms=r["ms"])) + "\n" for r in written)
        cache.update({r["id"]: r["text"] for r in written})
        shutil.rmtree(pending)
    return {key: cache[sound] for key, (sound, _) in sounds.items() if sound in cache}


def text_stage():
    """Tools/VoiceBench/Text built here on a package of KeyboardCore alone, as scripts/coretest builds its tests:
    optimized but file by file, so a change to KeyboardCore rebuilds in about 30 s rather than 95 (SwiftPM's default
    build system fails without whole-module optimization)."""
    pkg = ROOT / "build/voicetext"
    (pkg / "Sources/VoiceText").mkdir(parents=True, exist_ok=True)
    for link, target in [(pkg / "Sources/KeyboardCore", ROOT / "Packages/KeyboardModules/Sources/KeyboardCore"),
                         (pkg / "Sources/VoiceText/main.swift", ROOT / "Tools/VoiceBench/Text/main.swift")]:
        if not link.is_symlink():
            link.symlink_to(target)
    (pkg / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription

let package = Package(name: "VoiceText", targets: [
    .target(name: "KeyboardCore", exclude: ["AGENTS.md"]),
    .executableTarget(name: "VoiceText", dependencies: ["KeyboardCore"]),
])
""")
    built = subprocess.run(["swift", "build", "-c", "release", "--build-system", "native", "-Xswiftc", "-no-whole-module-optimization",
                            "--package-path", pkg], capture_output=True, text=True)
    if built.returncode:
        sys.exit(built.stdout + built.stderr)
    return pkg / ".build/release/VoiceText"


def typed(tool, folder, heard, settings, *mode):
    """What the keyboard types for each clip's `heard`, in its field, after the text before it there; or with mode
    `dictionary`, `heard` through the Dictionary alone."""
    context = {c["id"]: c for c in rows(folder / "context.jsonl")}
    given = "".join(json.dumps(dict(id=id, heard=text, field=context[id]["field"], content=context[id].get("content"), before=context[id]["before"])) + "\n"
                    for id, text in heard.items())
    memory = MEMORY if MEMORY.exists() else "-"
    done = subprocess.run([tool, LEXICON, folder / "vocabulary.json", memory, *settings, *mode], input=given, capture_output=True, text=True, check=True)
    return {r["id"]: r["typed"] for r in map(json.loads, filter(None, done.stdout.split("\n")))}


# Scoring

MERIDIEM = re.compile(r"(?:(?<=\d)\s?|\b)([ap])(?:m|\.\s?m\.)(?=\W|$)|(?<=\d)\s?([ap])\s?m(?=\W|$)", re.I)
CHUNK = re.compile(r"\S+")
MODELS = {"opus", "gpt", "sonnet", "haiku", "claude", "fable", "ios", "python", "gemini", "parakeet", "macos", "version", "v"}
KINDS = ["emails", "links", "versions", "times", "money", "digits", "names"]


def said(text):
    return score.said(MERIDIEM.sub(lambda m: " " + (m[1] or m[2]) + "m", text))


def kind(chunk, before, terms, first):
    bare = chunk.strip(".,!?;:\"'()“”‘’")
    low = bare.lower()
    if "@" in bare:
        return "emails"
    if "/" in bare or re.search(r"[a-z0-9]\.(com|org|net|io|me|app|dev|run|ai|co|edu|gov|so|sh)\b", low):
        return "links"
    if re.search(r"\d\.\d", bare) and (before in MODELS or bare.count(".") > 1 or re.match(r"[a-z]", low)) or re.fullmatch(r"v\d+", low):
        return "versions"
    if re.search(r"\d:\d\d", bare) or low in {"am", "pm", "a.m", "p.m"}:
        return "times"
    if "$" in bare or "%" in bare or low in {"dollars", "dollar", "cents", "percent", "bucks"}:
        return "money"
    if re.search(r"\d", bare):
        return "digits"
    if low in terms or (bare[:1].isupper() and not first and low not in {"i", "i'm", "i'll", "i've", "i'd", "ok"}):
        return "names"
    return "words"


def tokens(text, terms):
    """The text's words as said() reads them, each with the kind of the chunk it's in, and the chunks themselves."""
    out, chunks, first, before = [], [], True, ""
    for m in CHUNK.finditer(text):
        chunk = m.group()
        k = kind(chunk, before, terms, first)
        chunks.append((chunk, k))
        out += [(w, k, len(chunks) - 1) for w in said(chunk)]
        first, before = chunk[-1:] in ".!?\n", chunk.strip(".,!?;:").lower()
    return out, chunks


UNITS = {w: n for n, w in enumerate("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen "
                                    "fifteen sixteen seventeen eighteen nineteen".split())} | {"oh": 0}
TENS = {w: 10 * n for n, w in enumerate("twenty thirty forty fifty sixty seventy eighty ninety".split(), 2)}
SET_ASIDE = {"cut later", "number form", "casing", "punctuation"}


def number(words):
    """The digits a run of words says, spoken or written ("five point five" and "5 5" are both 55), or None when it
    holds any other word."""
    out, now = [], None
    for w in words:
        if w.isdigit() or w in {"point", "percent", "dollars", "dollar", "cents", "dot"}:
            out += [str(now)] if now is not None else []
            out += [w] if w.isdigit() else []
            now = None
        elif w == "and":
            continue
        elif w in UNITS and now is not None and (20 <= now < 100 and now % 10 == 0 and UNITS[w] < 10 or now >= 100 and now % 100 == 0):
            now += UNITS[w]
        elif w in TENS and now is not None and now >= 100 and now % 100 == 0:
            now += TENS[w]
        elif w in UNITS or w in TENS:
            out += [str(now)] if now is not None else []
            now = UNITS.get(w, TENS.get(w))
        elif w in ("hundred", "thousand") and now is not None:
            now *= 100 if w == "hundred" else 1000
        else:
            return None
    return "".join(out + ([str(now)] if now is not None else [])) or None


def diff(reference, hypothesis, terms, final, marks):
    """Each way `hypothesis` differs from `reference`, as (label, words, the reference's, the hypothesis's): a word error
    labelled by the kind of thing the reference has there, or a word right but punctuated or capitalized wrong
    (`marks`). Against a final (`final`), which kept whatever the build of its day typed and lacks what was cut after,
    four or more words in a row it lacks are "cut later" and the same number in another form "number form"."""
    ref, ref_chunks = tokens(reference, terms)
    hyp, hyp_chunks = tokens(hypothesis, terms)
    out = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, [w for w, _, _ in ref], [w for w, _, _ in hyp], autojunk=False).get_opcodes():
        a, b = [w for w, _, _ in ref[i1:i2]], [w for w, _, _ in hyp[j1:j2]]
        if tag == "equal":
            for i, j in zip(range(i1, i2), range(j1, j2)):
                x, y = ref_chunks[ref[i][2]][0], hyp_chunks[hyp[j][2]][0]
                if marks and (i == i1 or ref[i][2] != ref[i - 1][2]) and x != y and said(x) == said(y):
                    out.append(("casing" if x.lower() == y.lower() else "punctuation", 1, x, y))
            continue
        near = {k for _, k, _ in ref[max(i1 - 1, 0) : i2 + 1]} if tag == "insert" else {k for _, k, _ in ref[i1:i2]}
        near |= {k for _, k, _ in hyp[j1:j2]}
        if final and tag == "insert" and len(b) >= 4:
            label = "cut later"
        elif final and number(a) is not None and number(a) == number(b):
            label = "number form"
        else:
            label = next((k for k in KINDS if k in near), {"replace": "misheard words", "delete": "dropped words", "insert": "added words"}[tag])
        out.append((label, max(len(a), len(b)), " ".join(a) or "·", " ".join(b) or "·"))
    return out


def table(name, references, ways, diffs, clips, groups):
    words = {id: len(said(text)) for id, text in references.items()}

    def line(way, ids, indent):
        ids = [id for id in ids if id in ways[way]]
        total = sum(words[id] for id in ids)
        wrong = sum(n for id in ids for label, n, _, _ in diffs[way][id] if label not in SET_ASIDE)
        aside = sum(n for id in ids for label, n, _, _ in diffs[way][id] if label in ("cut later", "number form"))
        exact = sum(ways[way][id].strip() == references[id].strip() for id in ids)
        print(f"{indent}{way:<8}{len(ids):>6}{total:>7}{wrong / max(total, 1) * 100:>8.2f}%{exact / max(len(ids), 1) * 100:>8.1f}%{aside:>7}")
        return wrong / max(total, 1) * 100

    print(f"\n{name}\n  {'way':<8}{'clips':>6}{'words':>7}{'wrong':>9}{'exact':>9}{'aside':>7}")
    numbers = {way: line(way, list(references), "  ") for way in ways}
    for label in groups:
        for value in sorted({c[label] for c in clips.values()}):
            ids = [id for id in references if clips[id][label] == value]
            print(f"  {label}: {value}")
            for way in ways:
                numbers[way, label, value] = line(way, ids, "    ")
    return numbers


def main():
    DATA.mkdir(parents=True, exist_ok=True)
    lock = (DATA / ".lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("waiting for another scripts/voiceloop, which shares voicebench/", flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
    began = time.monotonic()
    stages = {}

    def stage(label):
        nonlocal began
        stages[label] = time.monotonic() - began
        began = time.monotonic()

    real()
    stage("real and loud sets")
    spoken()
    stage("spoken set")
    sets = ["real", "loud", "spoken"]
    heard = parakeet(sets, "--cached" in sys.argv)
    stage("parakeet")
    tool = text_stage()
    stage("text stage build")
    phone = settings()
    numbers, tally_all, read, runs = {}, {}, {}, {}
    pool = concurrent.futures.ThreadPoolExecutor()
    for name in sets:
        folder = DATA / name
        references = {r["id"]: r["text"] for r in rows(folder / "references.jsonl")}
        clips = {c["id"]: c for c in rows(folder / "clips.jsonl") if (name, c["id"]) in heard and c["id"] in references}
        references = {id: text for id, text in references.items() if id in clips}
        context = {c["id"]: c for c in rows(folder / "context.jsonl")}
        knobs = phone if name != "spoken" else DEFAULTS
        read[name] = clips, references, context, knobs
        runs[name] = dict(bench=pool.submit(typed, tool, folder, {id: heard[name, id] for id in clips}, knobs))
        if name == "real":
            runs[name]["replay"] = pool.submit(typed, tool, folder, {id: context[id]["heard"] for id in clips}, knobs)
        if name != "spoken":
            runs[name]["references"] = pool.submit(typed, tool, folder, references, knobs, "dictionary")
    for name in sets:
        folder = DATA / name
        clips, references, context, knobs = read[name]
        mine = {id: heard[name, id] for id in clips}
        ways = {way: run.result() for way, run in runs[name].items()}
        final = "references" in ways
        references = ways.pop("references", references)
        if name == "real":
            ways["phone"] = {r["id"]: r["text"] for r in rows(folder / "typed.jsonl") if r["id"] in clips}
        terms = {t["term"].lower() for t in json.load((folder / "vocabulary.json").open())["terms"]}
        marks = {id: name == "spoken" or clips[id].get("final") == "field" for id in clips}
        diffs = {way: {id: diff(references[id], text, terms, final, marks[id]) for id, text in got.items()} for way, got in ways.items()}
        groups = {"real": ["room", "capture", "final"], "loud": ["speech"], "spoken": ["condition", "voice", "topic", "field", "name"]}[name]
        numbers[name] = table(f"{name} ({', '.join(knobs)})", references, ways, diffs, clips, groups)
        if name == "real":
            same_heard = sum(mine[id].strip() == context[id]["heard"].strip() for id in clips)
            recent = [id for id in clips if clips[id]["final"] == "field"]
            same_typed = sum(ways["replay"][id].strip() == ways["phone"][id].strip() for id in recent)
            print(f"  the bench's Parakeet wrote what the iPhone's did on {same_heard} of {len(clips)} dictations;"
                  f" the text stage typed what the iPhone did for that on {same_typed} of {len(recent)} kept since build 479")
        for id, found in diffs["bench"].items():
            part = name if name != "spoken" else "spoken quiet" if clips[id]["condition"] == "normal in a quiet room" else "spoken rest"
            tally, examples = tally_all.setdefault(part, (collections.Counter(), collections.defaultdict(list)))
            for label, n, a, b in found:
                tally[label] += n
                examples[label].append((id, a, b))
        lines(folder / "loop.jsonl", [dict(id=id, reference=references[id], heard=mine[id], **{w: ways[w][id] for w in ways})
                                      for id in references])
    stage("text stage and scoring")

    with (DATA / "categories.txt").open("w") as f:
        f.write(f"scripts/voiceloop, {time.strftime('%Y-%m-%d %H:%M')}: what the bench (Parakeet v3 as the app runs it, then\n"
                "the app's writing and Dictionary and the keyboard's reading) still gets wrong, as word errors by the kind\n"
                "of thing the reference had there, and words right but punctuated or capitalized wrong (in real, only\n"
                "against finals the keyboard followed, since build 479). Against his finals, \"cut later\" (4+ words in a\n"
                "row the final lacks) and \"number form\" (the same number written another way) aren't errors: a final\n"
                "keeps what the build of its day typed. Examples are reference → typed, by clip id (each set's loop.jsonl\n"
                "has the whole texts). \"spoken quiet\" is the normal voices in a quiet room, where Parakeet hears well.\n")
        for name, (tally, examples) in tally_all.items():
            f.write(f"\n{name}\n")
            for label, count in tally.most_common():
                f.write(f"{count:>6}  {label}\n")
                for where, a, b in examples[label][:12]:
                    f.write(f"          {a} → {b}   ({where})\n")
    print("\nword errors by kind (bench), words punctuated or capitalized wrong, and what's set aside against a final:")
    print(f"  {'':<16}" + "".join(f"{n:>14}" for n in tally_all))
    for label in sorted({l for t, _ in tally_all.values() for l in t}, key=lambda l: -sum(t[l] for t, _ in tally_all.values())):
        print(f"  {label:<16}" + "".join(f"{t[label]:>14}" for t, _ in tally_all.values()))
    print(f"\nexamples in {DATA / 'categories.txt'}")
    real_set, loud_set, spoken_set = (numbers[n] for n in sets)
    print(f"\nwords wrong, as typed: real {real_set['bench']:.2f}% (the iPhone {real_set['phone']:.2f}%), in loud rooms"
          f" {real_set['bench', 'room', 'loud']:.2f}%, his voice whispered (-18 dB) in one {loud_set['bench', 'speech', '-18 dB']:.2f}%;"
          f" spoken {spoken_set['bench']:.2f}%: in a quiet room {spoken_set['bench', 'condition', 'normal in a quiet room']:.2f}%,"
          f" a loud one {spoken_set['bench', 'condition', 'normal in a loud room']:.2f}%, whispered"
          f" {spoken_set['bench', 'condition', 'whisper in a quiet room']:.2f}% (in a loud room"
          f" {spoken_set['bench', 'condition', 'whisper in a loud room']:.2f}%), 18 dB softer in a loud room"
          f" {spoken_set['bench', 'condition', 'soft in a loud room']:.2f}%")
    print("time: " + ", ".join(f"{k} {v:.0f} s" for k, v in stages.items()) + f", {sum(stages.values()):.0f} s in all")


if __name__ == "__main__":
    main()
