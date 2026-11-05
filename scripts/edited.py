"""Checks that the app kept what each dictation became with its transcript, for scripts/edittest: the transcript's
field holds the text the UI test saw in the field as it ended, and whether it was sent.
scripts/edited.py <transcripts.jsonl> (<transcript id> <ended text> <sent: true|false>)..."""
import json, sys

transcripts, checks = sys.argv[1], sys.argv[2:]
fields = {line["id"]: line.get("field") for line in map(json.loads, open(transcripts))}
right = True
for id, ended, sent in zip(checks[::3], checks[1::3], checks[2::3]):
    field = fields.get(id)
    if not field:
        print(f"{id}: no field")
        right = False
        continue
    final = field["final"] == open(ended).read()
    print(f"{id}: typed {len(field['typed'])} characters, final {len(field['final'])}, final is the field as it ended: {final}, sent {field['sent']}")
    right = right and final and field["sent"] == (sent == "true")
sys.exit(0 if right else 1)
