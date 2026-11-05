"""How dictations fared on the iPhone, from the backup server's copy of Transcripts: python3 scripts/voicehealth.py [days]

Per day: dictations, ones whose recording holds no sound at all (no sample past 100 of 32767: no real microphone is
that quiet, and none of 628 dictations with speech came within 200), ones written down as nothing, ones recovered after
iikb ended mid-dictation, and ones whose recording file is shorter than the dictation was. Then the same per capture,
the microphone and whether voice processing heard it, and the last silent ones.

Last, each way of hearing the dictations were compared in (`Capture`), in loud rooms and quiet ones: how many, and how
many of the words each typed were changed by the time its field was sent or left (`field.final`, leaving out the ones
marked uncertain). A room is loud at -40 dBFS or more, measured on the recording; voice processing holds a room down,
so one it heard takes the room of the raw dictations within 15 minutes of it, and goes uncounted without one.
"""
import datetime
import json
import os
import struct
import sys
from collections import defaultdict

from voicescore import edits, words

APP = os.path.expanduser("~/.local/share/iikb/backup/mirror/app")
SILENT = 100
LOUD_ROOM = -40
NEARBY = 15 * 60
EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)


def samples(path):
    data = open(path, "rb").read()[44:]
    count = len(data) // 2
    return struct.unpack(f"<{count}h", data[: count * 2])


def outcomes(row):
    found = ["dictations"]
    if not row["text"]:
        found.append("nothing written")
    if row.get("recovered"):
        found.append("recovered")
    path = f"{APP}/recordings/{row['id']}.wav"
    if not os.path.exists(path):
        return found + ["no recording"]
    sound = samples(path)
    if len(sound) / 16_000 < row["seconds"] - 0.5:
        found.append("recording short")
    if max(map(abs, sound), default=0) < SILENT:
        found.append("silent")
    return found


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    rows = [json.loads(line) for line in open(f"{APP}/transcripts.jsonl") if line.strip()]
    since = datetime.datetime.now().astimezone() - datetime.timedelta(days=days)
    table = defaultdict(lambda: defaultdict(int))
    captures = defaultdict(lambda: defaultdict(int))
    silent = []
    for row in sorted(rows, key=lambda r: r["date"]):
        when = (EPOCH + datetime.timedelta(seconds=row["date"])).astimezone()
        if when < since:
            continue
        processing = {True: "voice processing", False: "plain"}.get(row.get("voiceProcessing"), "?")
        found = outcomes(row)
        for column in found:
            table[when.strftime("%m-%d")][column] += 1
            captures[f"{row.get('mic') or '?'}, {processing}"][column] += 1
        if "silent" in found:
            silent.append((when, row))
    columns = ["dictations", "silent", "nothing written", "recovered", "recording short", "no recording"]
    print("day    " + "  ".join(columns))
    for day in sorted(table):
        print(f"{day}  " + "  ".join(f"{table[day][c]:>{len(c)}}" for c in columns))
    print()
    for capture in sorted(captures, key=lambda c: -captures[c]["dictations"]):
        print(f"{capture}: " + ", ".join(f"{captures[capture][c]} {c}" for c in columns if captures[capture][c]))
    for when, row in silent[-10:]:
        print(f"silent {when:%m-%d %H:%M:%S} {row['seconds']:5.1f}s {row.get('mic') or '?'} {row.get('app') or ''}")
    arms(rows)


def arms(rows):
    compared = [r for r in rows if r.get("capture") and r.get("room") is not None]
    raw = [r for r in compared if r["capture"] != "voiceProcessing"]
    table = defaultdict(lambda: [0, 0, 0])
    for row in compared:
        rooms = [r["room"] for r in raw if abs(r["date"] - row["date"]) <= NEARBY] if row["capture"] == "voiceProcessing" else [row["room"]]
        field = row.get("field")
        if not rooms or not field or field.get("uncertain"):
            continue
        typed = words(field["typed"])
        cell = table[row["capture"], "loud" if sorted(rooms)[len(rooms) // 2] >= LOUD_ROOM else "quiet"]
        cell[0] += 1
        cell[1] += len(typed)
        cell[2] += sum(edits(typed, words(field["final"])))
    print(f"\n{'compared as':<18}{'room':<7}{'dictations':>11}{'words':>8}{'edited':>9}")
    for (capture, room), (count, total, edited) in sorted(table.items()):
        print(f"{capture:<18}{room:<7}{count:>11}{total:>8}{edited / max(total, 1) * 100:>8.2f}%")


main()
