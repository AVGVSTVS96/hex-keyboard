"""Builds the corpora scripts/voicebench scores from Bassim's own dictations on the backup server, into voicebench/
beside the backup (never the repo: they're his voice and his words). Run it with
`uv run --with numpy scripts/voicecorpus.py [out]`; it writes two:

real: every dictation Parakeet v3 wrote and iikb typed, with what it finally became as the reference: its transcript's
`field.final`, what the keyboard followed it to until its field was sent or changed, or else the span of what was sent
in the three hours after (the record source's log, and hex's messages) that its words line up with. typed.jsonl is what iikb
typed, and clips.jsonl each clip's date, mic, how it was heard (its transcript's `capture`, voice processing, raw or a
front cardioid; or else its `voiceProcessing`; or, from before iikb kept either, whether it came after voice processing
went in), its room and speech levels (each a group voicescore splits by) and where its final came from.

loud: the real set's quiet dictations that went in as typed, mixed with the room of its loud ones (their stretches
without speech) at that room's own level, the speech as loud as said there and 6, 12 and 18 dB quieter (a whisper), with
each clean dictation's final as the reference.
"""
import datetime, difflib, json, os, random, re, shutil, sqlite3, sys, wave
from pathlib import Path
import numpy as np

HOME = Path.home()
BACKUP = Path(os.environ.get("IIKB_BACKUP", HOME / ".local/share/iikb/backup"))
MIRROR = BACKUP / "mirror"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else BACKUP.parent / "voicebench"
EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)
VOICE_PROCESSING = datetime.datetime(2026, 11, 3, 12, 24, tzinfo=datetime.timezone.utc)
LOUD_ROOM = -40
TOKEN = re.compile(r"[A-Za-z0-9'’]+")


def words(text):
    return [m.group().lower().replace("’", "'") for m in TOKEN.finditer(text)]


def read(path):
    with wave.open(str(path)) as w:
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32767


def write(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(16_000)
        w.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def frames(samples):
    """Each 20 ms frame's level, as Recording.leveled measures it."""
    n = len(samples) // 320
    return samples[: n * 320].reshape(n, 320).std(axis=1)


def levels(samples):
    """The room (10th percentile frame) and the speech (95th), in dBFS."""
    level = np.sort(frames(samples))
    db = lambda x: round(float(20 * np.log10(max(x, 1e-6))), 1)
    return db(level[len(level) // 10]), db(level[len(level) * 95 // 100])


def sent():
    """Everything sent, oldest first: the record source's log, and hex's messages when they're here."""
    at = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    out = [("record", at(r["at"]), r["text"]) for r in map(json.loads, open(BACKUP.parent / "record.jsonl"))]
    if (HOME / "hex/state/hex.db").exists():
        db = sqlite3.connect(f"file:{HOME}/hex/state/hex.db?mode=ro", uri=True)
        out += [("hex", at(a), body) for a, body in db.execute("select at, body from messages where author = 'owner'")]
    return sorted(out, key=lambda c: c[1])


def locate(said, text):
    """The share of the dictation's words found in `text`, and the span of `text` they became: from the first to the
    last word lined up with it, in the biggest group of matches that sit together, widened over the dictation's own
    unmatched words at either edge."""
    found = words(text)
    blocks = [b for b in difflib.SequenceMatcher(None, said, found, autojunk=False).get_matching_blocks() if b.size]
    if not blocks:
        return 0, None
    groups = [[blocks[0]]]
    for before, block in zip(blocks, blocks[1:]):
        if block.b - (before.b + before.size) <= block.a - (before.a + before.size) + 8:
            groups[-1].append(block)
        else:
            groups.append([block])
    group = max(groups, key=lambda g: sum(b.size for b in g))
    first, last = group[0], group[-1]
    lo = max(first.b - first.a, 0)
    hi = min(last.b + last.size + len(said) - (last.a + last.size), len(found))
    spans = [m.span() for m in TOKEN.finditer(text)]
    return sum(b.size for b in group) / len(said), text[spans[lo][0] : spans[hi - 1][1]] if hi > lo else None


def final(transcript, candidates):
    """What the dictation became, and where that came from."""
    field = transcript.get("field")
    if field and not field.get("uncertain"):
        return field["final"], "field"
    said = words(transcript.get("heard") or transcript["text"])
    if len(said) < 3:
        return None, None
    at = EPOCH + datetime.timedelta(seconds=transcript["date"])
    best = (0, None, None)
    for source, when, text in candidates:
        if at - datetime.timedelta(seconds=60) <= when <= at + datetime.timedelta(hours=3):
            share, span = locate(said, text)
            if share > best[0] + 0.02 or (abs(share - best[0]) <= 0.02 and span and best[1] and len(span) > len(best[1])):
                best = (share, span, source)
    return (best[1], best[2]) if best[0] >= 0.6 else (None, None)


def lines(path, rows):
    path.write_text("".join(json.dumps(row) + "\n" for row in rows))


def real():
    folder = OUT / "real"
    shutil.rmtree(folder, ignore_errors=True)
    (folder / "audio").mkdir(parents=True)
    candidates = sent()
    clips, references, typed = [], [], []
    for t in map(json.loads, open(MIRROR / "app/transcripts.jsonl")):
        recording = MIRROR / f"app/recordings/{t['id']}.wav"
        if not t["typed"] or t.get("model") != "Parakeet v3" or not recording.exists():
            continue
        text, source = final(t, candidates)
        samples = read(recording)
        if not text or len(samples) < 16_000:
            continue
        os.link(recording, folder / f"audio/{t['id']}.wav")
        date = EPOCH + datetime.timedelta(seconds=t["date"])
        heard = t.get("capture") or ("voiceProcessing" if t.get("voiceProcessing", date >= VOICE_PROCESSING) else "raw")
        room, speech = levels(samples)
        clips.append(dict(id=t["id"], audio_path=f"audio/{t['id']}.wav", date=date.isoformat(timespec="seconds"),
                          seconds=round(len(samples) / 16_000, 1), room_db=room, speech_db=speech,
                          room="loud" if room >= LOUD_ROOM else "quiet", capture=heard,
                          mic=t.get("mic") or "unknown", final=source))
        references.append(dict(id=t["id"], text=text))
        typed.append(dict(id=t["id"], text=t["text"]))
    lines(folder / "clips.jsonl", clips)
    lines(folder / "references.jsonl", references)
    lines(folder / "typed.jsonl", typed)
    shutil.copy(MIRROR / "app/vocabulary.json", folder / "vocabulary.json")
    print(f"real: {len(clips)} dictations, {sum(c['room'] == 'loud' for c in clips)} in a loud room,",
          f"finals {', '.join(f'{s} {sum(c['final'] == s for c in clips)}' for s in ('field', 'record', 'hex'))}")
    return folder, clips, {r["id"]: r["text"] for r in references}, {r["id"]: r["text"] for r in typed}


def room(folder, clips):
    """The loud dictations' stretches without speech, each frame within 6 dB of its recording's room, in runs of half a
    second or more less 40 ms at each end, joined end to end and brought to their rooms' middle level."""
    parts = []
    for clip in clips:
        samples = read(folder / clip["audio_path"])
        level = frames(samples)
        quiet = np.append(level <= np.sort(level)[len(level) // 10] * 2, False)
        start = None
        for at, still in enumerate(quiet):
            if still and start is None:
                start = at
            elif not still and start is not None:
                if at - start >= 25:
                    parts.append(samples[(start + 2) * 320 : (at - 2) * 320])
                start = None
    bed = np.concatenate(parts)
    return bed * 10 ** ((np.median([c["room_db"] for c in clips]) - levels(bed)[0]) / 20)


def loud(folder, clips, references, typed, count=120):
    out = OUT / "loud"
    shutil.rmtree(out, ignore_errors=True)
    (out / "audio").mkdir(parents=True)
    noisy = [c for c in clips if c["room"] == "loud"]
    bed = room(folder, noisy)
    said = float(np.median([c["speech_db"] for c in noisy]))
    clean = [c for c in clips if c["room"] == "quiet" and c["capture"] == "voiceProcessing" and 3 <= c["seconds"] <= 30
             and words(references[c["id"]]) == words(typed[c["id"]])]
    rows, refs = [], []
    for clip in sorted(random.Random(806).sample(clean, min(count, len(clean))), key=lambda c: c["date"]):
        samples = read(folder / clip["audio_path"])
        samples = samples * 10 ** ((said - clip["speech_db"]) / 20)
        start = random.Random(clip["id"]).randrange(len(bed))
        noise = np.resize(np.roll(bed, -start), len(samples))
        for quieter in (None, 0, 6, 12, 18):
            mixed = samples * 10 ** (-(quieter or 0) / 20) + (0 if quieter is None else noise)
            mixed /= max(1, np.abs(mixed).max() / 0.99)
            name = f"{clip['id']}-{'clean' if quieter is None else quieter}"
            write(out / f"audio/{name}.wav", mixed)
            room_db, speech_db = levels(mixed)
            rows.append(dict(id=name, audio_path=f"audio/{name}.wav", source=clip["id"], room_db=room_db, speech_db=speech_db,
                             speech="clean" if quieter is None else f"-{quieter} dB" if quieter else "as said"))
            refs.append(dict(id=name, text=references[clip["id"]]))
    lines(out / "clips.jsonl", rows)
    lines(out / "references.jsonl", refs)
    shutil.copy(folder / "vocabulary.json", out / "vocabulary.json")
    print(f"loud: {len(rows) // 5} of {len(clean)} clean dictations, each clean and in a {levels(bed)[0]:.0f} dBFS room",
          f"({len(bed) / 16_000:.0f} s of it from {len(noisy)} dictations) said at {said:.0f} dBFS and 6, 12, 18 dB quieter")


folder, clips, references, typed = real()
loud(folder, clips, references, typed)
