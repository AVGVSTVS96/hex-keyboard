"""How dictations fared on the iPhone, from the backup server's copy of Transcripts: python3 scripts/voicehealth.py [days]

Per day: dictations, ones whose recording holds no sound at all (no sample past 100 of 32767: no real microphone is
that quiet, and none of 628 dictations with speech came within 200), ones written down as nothing, ones recovered after
iikb ended mid-dictation, and ones whose recording file is shorter than the dictation was. Then the last silent ones.
"""
import datetime
import json
import os
import struct
import sys
from collections import defaultdict

APP = os.path.expanduser("~/.local/share/hex-keyboard/backup/mirror/app")
SILENT = 100
EPOCH = datetime.datetime(2001, 1, 1, tzinfo=datetime.timezone.utc)


def samples(path):
    data = open(path, "rb").read()[44:]
    count = len(data) // 2
    return struct.unpack(f"<{count}h", data[: count * 2])


def main():
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    rows = [json.loads(line) for line in open(f"{APP}/transcripts.jsonl") if line.strip()]
    since = datetime.datetime.now().astimezone() - datetime.timedelta(days=days)
    table = defaultdict(lambda: defaultdict(int))
    silent = []
    for row in sorted(rows, key=lambda r: r["date"]):
        when = (EPOCH + datetime.timedelta(seconds=row["date"])).astimezone()
        if when < since:
            continue
        day = table[when.strftime("%m-%d")]
        day["dictations"] += 1
        day["nothing written"] += not row["text"]
        day["recovered"] += bool(row.get("recovered"))
        path = f"{APP}/recordings/{row['id']}.wav"
        if not os.path.exists(path):
            day["no recording"] += 1
            continue
        sound = samples(path)
        if len(sound) / 16_000 < row["seconds"] - 0.5:
            day["recording short"] += 1
        if max(map(abs, sound), default=0) < SILENT:
            day["silent"] += 1
            silent.append((when, row))
    columns = ["dictations", "silent", "nothing written", "recovered", "recording short", "no recording"]
    print("day    " + "  ".join(columns))
    for day in sorted(table):
        print(f"{day}  " + "  ".join(f"{table[day][c]:>{len(c)}}" for c in columns))
    for when, row in silent[-10:]:
        print(f"silent {when:%m-%d %H:%M:%S} {row['seconds']:5.1f}s {row.get('mic') or '?'} {row.get('app') or ''}")


main()
