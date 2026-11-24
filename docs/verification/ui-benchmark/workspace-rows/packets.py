import argparse
import base64
import csv
import io
import json
from pathlib import Path

from PIL import Image


goals = {
    "navigation": "Find how to switch from Planner to Inbox, tell which workspace is active, and keep date browsing and capture distinct. The three views are before, destination choices and arrival. Persistent choices may produce identical before and choices images.",
    "editor": "Identify the schedule to the left of the completion circle and inspect compact property controls after expanding the same task. Judge alignment, use of the card width, order and fit at both phone widths. Property captions are intentionally omitted.",
    "density": "Scan a populated list with short and wrapping titles, project tags, scheduled times and trailing deadlines. Judge whether each row is distinct and dense, and whether the expanded card has appropriate internal and external spacing.",
}

parser = argparse.ArgumentParser(description="Export the anonymous review packets from the self-contained report.")
parser.add_argument("phase", choices=["baseline", "comparison", "refinement"])
parser.add_argument("output", type=Path)
args = parser.parse_args()
study = Path(__file__).resolve().parent
report = (study / "report.html").read_text()
sheets, _ = json.JSONDecoder().raw_decode(report.split("const sheets=", 1)[1])
brief = (study / "reviewer-brief.txt").read_text()
with (study / "ballots.csv").open(newline="") as stream:
    rows = [row for row in csv.DictReader(stream) if row["phase"] == args.phase]

for reviewer in ("R1", "R2", "R3"):
    packet = args.output / reviewer
    packet.mkdir(parents=True, exist_ok=False)
    (packet / "brief.txt").write_text(brief)
    tasks = []
    for row in sorted((row for row in rows if row["reviewer"] == reviewer), key=lambda row: int(row["position"])):
        axis = row["axis"]
        key = f"{axis}-{row['variant']}"
        if args.phase == "baseline" and key == "navigation-menu":
            key = "baseline-navigation-menu"
        encoded = sheets[key].split(",", 1)[1]
        position = f"{int(row['position']):02}"
        with Image.open(io.BytesIO(base64.b64decode(encoded))) as image:
            image.convert("RGB").save(packet / f"{position}.png")
        tasks.append(f"{position} | {row['id']} | {goals[axis]}")
    (packet / "goals.txt").write_text("\n".join(tasks) + "\n")
