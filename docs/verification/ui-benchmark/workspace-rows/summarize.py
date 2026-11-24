import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean

criteria = ("orientation", "scanability", "affordance", "legibility", "composition")
scores = defaultdict(dict)
with Path(__file__).with_name("ballots.csv").open(newline="") as stream:
    for row in csv.DictReader(stream):
        group = scores[row["axis"], row["phase"], row["variant"]]
        marks = [float(row[name]) for name in criteria]
        if row["reviewer"] in group or any(value not in (0, 0.5, 1, 1.5, 2) for value in marks):
            raise ValueError(f"Invalid ballot for {row['id']}")
        score = sum(marks)
        if score != float(row["score"]):
            raise ValueError(f"Inconsistent total for {row['id']}")
        group[row["reviewer"]] = score

for (axis, phase, variant), panel in sorted(scores.items()):
    if set(panel) != {"R1", "R2", "R3"}:
        raise ValueError(f"Incomplete panel for {axis}, {phase}, {variant}")
    print(f"{axis:12} {phase:12} {variant:10}  {mean(panel.values()):5.2f}  "
          + "  ".join(f"{panel[r]:.1f}" for r in sorted(panel)))
