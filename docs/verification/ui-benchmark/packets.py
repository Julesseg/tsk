import argparse
import csv
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps


GOALS = {
    "planner": "Identify today's tasks and how to change the day.",
    "inbox": "Scan unfiled work and locate capture.",
    "workspaces": "Find the available workspaces and the current destination.",
    "project": "Identify Work’s scheduled and unscheduled tasks and how to return to Projects.",
    "editor": "Identify the expanded task's editable properties.",
    "calendar": "Identify the selected day and how to switch days or months.",
}


def prepare(phase, output, designs, seed):
    rng = random.Random(seed)
    images = []
    used = set()
    output.mkdir(parents=True, exist_ok=False)
    for name, directory in designs:
        for screen, goal in GOALS.items():
            with Image.open(Path(directory) / f"{screen}.png") as source:
                upright = ImageOps.exif_transpose(source).convert("RGB")
                height = round(upright.height * 420 / upright.width)
                image = upright.resize((420, height), Image.Resampling.LANCZOS)
            while (number := rng.randrange(100000, 1000000)) in used:
                pass
            used.add(number)
            images.append((f"{phase[0]}{number}", name, screen, goal, image))

    with (output / "key.csv").open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["image", "phase", "design", "screen"])
        writer.writerows((key, phase, design, screen) for key, design, screen, _, _ in images)

    for reviewer in range(1, 4):
        order = rng.sample(images, len(images))
        packet = output / f"R{reviewer}"
        packet.mkdir()
        (packet / "goals.txt").write_text("".join(f"{key} | {goal}\n" for key, _, _, goal, _ in order))
        for i in range(0, len(order), 3):
            chunk = order[i:i + 3]
            sheet = Image.new("RGB", (432 * len(chunk), 48 + max(item[4].height for item in chunk)), "#e4e4e4")
            draw = ImageDraw.Draw(sheet)
            for column, (key, _, _, _, image) in enumerate(chunk):
                x = 6 + column * 432
                sheet.paste(image, (x, 48))
                draw.text((x + 6, 9), key, fill="black", font_size=22)
            sheet.save(packet / f"{i // 3 + 1}.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Prepare three blinded, shuffled screenshot packets.")
    parser.add_argument("phase", choices=["baseline", "comparison"])
    parser.add_argument("output", type=Path)
    parser.add_argument("--design", nargs=2, action="append", required=True, metavar=("NAME", "DIRECTORY"))
    parser.add_argument("--seed", type=int, required=True)
    args = parser.parse_args()
    prepare(args.phase, args.output, args.design, args.seed)
