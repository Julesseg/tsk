import argparse
import base64
import csv
import io
import json
from pathlib import Path

from PIL import Image, ImageDraw


study = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Recreate the anonymous project and deadline review sheets.")
parser.add_argument("phase", choices=("baseline", "comparison", "final"))
parser.add_argument("output", type=Path)
args = parser.parse_args()
report = (study / "report.html").read_text()
data = json.loads(report.split('<script type="application/json" id="data">', 1)[1].split("</script>", 1)[0])
with (study / "ballots.csv").open(newline="") as file:
    rows = [row for row in csv.DictReader(file) if row["phase"] == args.phase]


def image(variant, name):
    encoded = data["pics"][f"{variant}/{name}"].split(",", 1)[1]
    with Image.open(io.BytesIO(base64.b64decode(encoded))) as source:
        return source.convert("RGB")


def tile(row):
    final = args.phase == "final"
    width = 440 if final else 390
    states = ["normal", "long", "empty"] if final else ["normal", "empty", "long"]
    labels = {"normal": "Populated", "long": "Long project, overdue", "empty": "Both empty"}
    variant = row["variant"]
    cards = [image(variant, f"{state}{width}") for state in states]
    height = max(card.height for card in cards)
    revealed = image(variant, "revealed") if variant in ("reverse", "drawer") else None
    total_height = height + 30 + (revealed.height + 20 if revealed else 0)
    result = Image.new("RGB", ((width + 4) * 3, total_height), "#efeff2")
    draw = ImageDraw.Draw(result)
    for index, (state, card) in enumerate(zip(states, cards)):
        left = index * (width + 4)
        draw.text((left + 5, 3), row["id"] + "  ·  " + labels[state], fill="#222", font_size=14)
        result.paste(card, (left, 24))
    if revealed:
        draw.text((5, height + 27), "After opening details", fill="#222", font_size=13)
        result.paste(revealed, (0, height + 47))
    return result


for reviewer in ("R1", "R2", "R3"):
    packet = args.output / reviewer
    packet.mkdir(parents=True, exist_ok=False)
    ordered = sorted((r for r in rows if r["reviewer"] == reviewer), key=lambda r: int(r["position"]))
    (packet / "order.txt").write_text("\n".join(r["id"] for r in ordered))
    for start in range(0, len(ordered), 3):
        tiles = [tile(r) for r in ordered[start:start + 3]]
        sheet = Image.new("RGB", (tiles[0].width, sum(t.height + 5 for t in tiles)), "#d0d0d3")
        top = 0
        for item in tiles:
            sheet.paste(item, (0, top))
            top += item.height + 5
        sheet.save(packet / f"{start // 3 + 1:02}.png")
