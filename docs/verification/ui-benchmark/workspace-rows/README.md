# Workspace switching and task rows

Open the [single-file visual report](report.html) in a browser. **Try workspace tabs** and **Try bottom shelf** use the same task list, editor and spacing. Switch to Inbox, return to Planner, then expand “Review the print proof with the production team.” The prototype lets you mix all 13 alternatives across the three decisions.

## Findings

| Decision | Final panel | What you can see |
| --- | --- | --- |
| Workspace switching | Tabs 10.00/10, bottom shelf 9.50, shelf above footer 9.33 | Tabs expose all three destinations and switch in one tap. The shelf takes two taps and temporarily replaces date and capture. It recovers 40 pt, enough for one extra complete task with Adaptive spacing at 390 pt. |
| Expanded controls | Full-width controls with title-aligned Notes 9.50, all controls and Notes at the left inset 9.33 | The time and circle stay aligned with their collapsed positions. Using the width below Notes fits five properties on one line at 440 pt. The two dates wrap together at 390 pt. |
| Row spacing | Adaptive and Balanced 9.17, Tight 7.83 | With the reference footer, Adaptive shows 17 complete tasks at 390 pt and 20 at 440 pt. Balanced shows 16 and 19. Tight shows 18 and 22, but the project tags approach the next title and the editor feels crowded. |

All prototypes use compact date chips, full relative deadline words aligned to the trailing edge, and a check beside the active workspace. The populated list is a synthetic fixture over chrome taken from [iPhone XCUITest at 4fe70da](https://github.com/Julesseg/tsk/actions/runs/45270385965). Scores apply to visual evidence at standard text size in light appearance. The combined presets are interactive browser studies. Native input, gestures and accessibility require separate verification.

## Repeat the review

Three independent, same-provider Codex UI critics reviewed three reference sheets. Three fresh reviewers then reviewed ten conditions with repeated references. Three more reviewed eight conditions including five exact repeats. Each sheet changes one decision. Comparing means within the same phase controls for differences between panels. The initial reference means were 8.33 for navigation, 8.67 for expanded controls and 8.33 for spacing.

1. From this directory run `python3 packets.py baseline /tmp/tsk-baseline` with Pillow installed. Repeat for `comparison` and `refinement` using new output directories. The exporter recovers the losslessly embedded review images and the recorded presentation order. The original shuffle seeds were 3241, 3242 and 3243.
2. Give each fresh reviewer only its R1, R2 or R3 directory and the [brief](reviewer-brief.txt). Each directory contains numbered PNGs and a goal per sheet. Collect five half-point marks from zero to two, the total, a visible strength and a concern for each opaque ID.
3. Run `python3 summarize.py` to reproduce the recorded means and three individual scores. To score a new run, copy the study directory and replace the five marks, total and comments in [ballots.csv](ballots.csv) using the corresponding phase, reviewer and ID. The original file preserves all 63 judgments.

The [fixture](fixture.json) records title, project, scheduled time and trailing deadline in display order. Navigation sheets show Planner, the choices and arrival in Inbox. Editor sheets show the same task closed and open at 440 pt and open at 390 pt. Density sheets show a closed list and an expanded task at 390 pt. The [geometry measurements](combination-metrics.csv) cover every combination at 390 × 844 and 440 × 956 pt. A task counts only when the complete row fits between the header and reserved footer. Card height is in points.
