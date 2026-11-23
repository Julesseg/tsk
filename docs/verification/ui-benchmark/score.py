import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def read_rows(path):
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream))


def summarize(directory):
    key_rows = read_rows(directory / "key.csv")
    key = {row["image"]: row for row in key_rows}
    slots = {(row["phase"], row["design"], row["screen"]) for row in key_rows}
    if not key or len(key) != len(key_rows) or len(slots) != len(key_rows):
        raise ValueError("The key must map one unique image to each phase, design and screen")
    scores = defaultdict(dict)
    criteria = ["orientation", "scanability", "affordance", "legibility", "composition"]
    for row in read_rows(directory / "ballots.csv"):
        item = key[row["image"]]
        reviewer = row["reviewer"]
        group = (item["phase"], item["design"], item["screen"])
        values = [float(row[name]) for name in criteria]
        if reviewer in scores[group] or any(v not in (0, 0.5, 1, 1.5, 2) for v in values):
            raise ValueError(f"Invalid or duplicate ballot: {row}")
        scores[group][reviewer] = sum(values)

    screens = {row["screen"] for row in key.values()}
    groups = sorted({(row["phase"], row["design"]) for row in key.values()})
    reviewers_by_phase = {}
    for phase, design in groups:
        panel = [scores[phase, design, screen] for screen in sorted(screens)]
        reviewers = sorted(panel[0])
        if len(reviewers) != 3 or any(set(row) != set(reviewers) for row in panel):
            raise ValueError(f"Incomplete panel: {phase}, {design}")
        if reviewers_by_phase.setdefault(phase, reviewers) != reviewers:
            raise ValueError(f"Different reviewers across designs in phase {phase}")
        means = [statistics.mean(row[r] for row in panel) for r in reviewers]
        print(f"{phase} / {design}   {statistics.mean(means):.2f}/10")
        print("  rounds  " + "  ".join(f"{r} {m:.2f}" for r, m in zip(reviewers, means)))
        print("  screens " + "  ".join(f"{s} {statistics.mean(v.values()):.2f}" for s, v in zip(sorted(screens), panel)))


if __name__ == "__main__":
    summarize(Path(sys.argv[1]))
