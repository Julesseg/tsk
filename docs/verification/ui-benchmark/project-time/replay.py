import argparse
import base64
import csv
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw


study = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Export the anonymous reviewer sheets for one panel.")
parser.add_argument("phase", choices=("baseline", "comparison", "final"))
parser.add_argument("output", type=Path)
args = parser.parse_args()
report = (study / "report.html").read_text()
data = json.loads(report.split('<script type="application/json" id="data">', 1)[1].split("</script>", 1)[0])
with (study / "ballots.csv").open(newline="") as stream:
    rows = [b for b in csv.DictReader(stream) if b["phase"] == args.phase]

labels = {
    "normal": "Both set", "projectonly": "Project only", "dateonly": "Deadline only",
    "long": "Long project, overdue", "someday": "Future, date only", "today": "Due today", "empty": "Both empty",
}
wide = args.phase == "final"
width = 440 if wide else 390
states = ("someday", "today", "empty", "long") if wide else ("normal", "projectonly", "dateonly", "long")


def tile(row):
    cards = []
    for state in states:
        key = f"{row['variant']}/{state}{width}"
        encoded = data["pics"][key].split(",", 1)[1]
        with Image.open(io.BytesIO(base64.b64decode(encoded))) as source:
            cards.append(source.convert("RGB"))
    height = max(im.height for im in cards) + 24
    panel = Image.new("RGB", ((width + 4) * 2, height * 2), "#ebebee")
    draw = ImageDraw.Draw(panel)
    for index, (im, state) in enumerate(zip(cards, states)):
        x = (index % 2) * (width + 4)
        y = (index // 2) * height
        draw.text((x + 5, y + 3), row["id"] + "  ·  " + labels[state], font_size=14, fill="#202024")
        panel.paste(im, (x, y + 24))
    return panel


for reviewer in ("R1", "R2", "R3"):
    dest = args.output / reviewer
    dest.mkdir(parents=True, exist_ok=False)
    ordered = sorted((b for b in rows if b["reviewer"] == reviewer), key=lambda b: int(b["position"]))
    (dest / "order.txt").write_text("\n".join(b["id"] for b in ordered))
    for start in range(0, len(ordered), 2):
        panels = [tile(row) for row in ordered[start:start + 2]]
        sheet = Image.new("RGB", (sum(p.width + 6 for p in panels), max(p.height for p in panels)), "#c7c7cc")
        left = 0
        for panel in panels:
            sheet.paste(panel, (left, 0))
            left += panel.width + 6
        sheet.save(dest / f"{start // 2 + 1:02}.png")
