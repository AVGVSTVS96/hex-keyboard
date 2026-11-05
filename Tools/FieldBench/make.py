"""On the Mac: says every case in cases.jsonl in several voices into <corpus>, with the clips.jsonl Tools/VoiceBench reads."""
import json, subprocess, sys
from pathlib import Path

voices = ["Samantha", "Daniel"]
corpus = Path(sys.argv[1])
corpus.mkdir(parents=True, exist_ok=True)
clips = []
for line in Path(sys.argv[2]).read_text().splitlines():
    case = json.loads(line)
    for voice in voices:
        name = f"{case['id']}-{voice}"
        if not (corpus / f"{name}.aiff").exists():
            subprocess.run(["say", "-v", voice, "-o", str(corpus / f"{name}.aiff"), case["say"]], check=True)
        clips.append({"id": name, "audio_path": f"{name}.aiff"})
(corpus / "clips.jsonl").write_text("\n".join(map(json.dumps, clips)) + "\n")
