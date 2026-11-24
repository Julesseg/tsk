import argparse
import base64
import csv
import io
import json
import re
from pathlib import Path

from PIL import Image


study = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Recreate the anonymous screenshot packets for one panel.")
parser.add_argument("phase", choices=("baseline", "comparison", "followup"))
parser.add_argument("directory", type=Path)
args = parser.parse_args()
goals = {
    "inset": "Judge the space to the left of the scheduled time relative to the other card edges, the circle and the title/Notes column, at both widths. Consider whether the extra width creates awkward wraps. Score this spacing decision.",
    "layout": "Find the current tags, priority, project, schedule and deadline for the expanded task. Judge clarity, alignment and distance from the task across populated, empty and long values. "
    + ("Compare all three complete screens and the wider card crop." if args.phase == "followup" else "The popover is open in the lower right view.")
    + " Dates use compact symbol buttons, and workspace navigation is the checked bottom menu.",
}
report = (study / "report.html").read_text()
data = json.loads(re.search(r'<script type="application/json" id="study">(.*?)</script>', report, re.S)[1])
with (study / "ballots.csv").open(newline="") as file:
    ballots = [row for row in csv.DictReader(file) if row["phase"] == args.phase]
for reviewer in ("R1", "R2", "R3"):
    packet = args.directory / reviewer
    packet.mkdir(parents=True, exist_ok=False)
    lines = []
    for row in sorted((b for b in ballots if b["reviewer"] == reviewer), key=lambda b: int(b["position"])):
        key = data["keys"][row["id"]]["pic"]
        image = base64.b64decode(data["assets"][key].split(",", 1)[1])
        position = f"{int(row['position']):02}"
        with Image.open(io.BytesIO(image)) as source:
            source.convert("RGB").save(packet / f"{position}.png")
        lines.append(f"{position} {row['id']} {goals[row['axis']]}")
    (packet / "goals.txt").write_text("\n".join(lines) + "\n")
