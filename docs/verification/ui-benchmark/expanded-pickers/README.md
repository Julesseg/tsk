# Expanded task pickers

Open the [interactive visual report](report.html) in a browser. **Try inline date and tags** opens a single-task editor with the calendar and time beside the completion circle. **Try bottom tray** presents all five current values together. Tap a property, switch the task to **Long tags**, or compare the six layouts on identical records. All changes are in memory.

## Decision under review

The checked bottom workspace menu, Adaptive vertical spacing, compact dates and trailing relative deadlines are fixed. The inline study puts short tags under the time, the cycling priority symbol under the completion circle and Notes under the title. Project and deadline placement, paired dates, direct editing of the time, and a detached set of controls are the alternatives. The bottom layouts use single-task draft values in place of bulk staging and Apply. The grouped tray repeats the task title to connect it to the open editor.

| Layout | First comparison | Follow-up |
| --- | ---: | ---: |
| Previous full-width strip | 8.50 | 8.00 |
| Two dates together | 7.33 | 7.00 |
| Existing time opens the picker | 6.33 | 6.00 |
| Five bottom pickers | 7.33 | 6.00 |
| Calendar date and time beside the checkmark, whole-word tags | | 8.00 |
| Bottom tray with task title | | 8.50 |

The initial reference panel averaged 7.50. The separate left-inset comparison scored 8 pt at 9.00, 12 pt at 9.50 and 16 pt at 8.83. The previous reference has 1 pt of space before the time. All three reviewers preferred 12 pt. The two refined layouts use 12 pt on both sides of the expanded card and start their collapsed rows on the same column. Both retain 17 complete rows at 390 pt and 20 at 440 pt. [Measured dimensions](geometry.csv)

The first comparison uses full populated screens and smaller long and empty card crops. Those crops omitted detached controls. The final panel saw all three full states in every condition. Interpret scores within their panel. The prototypes use simulated input in a browser. Physical reach, keyboards, VoiceOver, larger text and native motion were outside the review.

## Source and replay

The visual references for bulk selection are the iPhone 18 Pro Max, iOS 27.2 captures for PR #124 at 93e0189. The tag picker, selection date picker and bulk bar SwiftUI files from that revision match rebased main at e8ae94f. The study follows the five-control order, searchable Add/Remove tag popover and calendar with time, reset, remove and shortcuts. Two original native captures are visible in the report. Surrounding Planner chrome comes from the preceding study at 4fe70da. The 28-row fixture is shared with the [workspace and rows study](../workspace-rows/fixture.json). Its print-proof task has timed dates, a project, two tags and a note, with empty-field and four-long-tag alternatives.

From this directory run these commands to reproduce the recorded means and export the shuffled reviewer packets. Export requires Pillow. Use a new output directory for each phase.

```sh
python3 ../workspace-rows/summarize.py ballots.csv
python3 replay.py baseline /tmp/tsk-pickers-baseline
python3 replay.py comparison /tmp/tsk-pickers-comparison
python3 replay.py followup /tmp/tsk-pickers-followup
```

Give each of three fresh Codex iPhone UI critics only its R1, R2 or R3 directory. Have each reviewer read goals.txt, open each PNG in order and score orientation, scanability, affordance, legibility and composition. Each takes half-point steps from zero (missing) to two (clear). One indicates a meaningful obstacle and 1.5 indicates minor friction. Ask for one visible strength and one concern with each ID. Keep the design key and earlier scores private until the panel is complete.

The [42 ballots](ballots.csv) preserve the five raw marks, opaque identifiers, presentation order and condensed reviewer comments. Three new reviewers formed each panel. All six follow-up layouts have three ratings. Each screenshot sheet carries equal weight within its condition.
