# Project as place, deadline as time

Open the [interactive mixer](report.html). Start with the folder tab in both columns and switch between the countdown and calendar leaf. **Match projects** or **Match deadlines** copies that treatment from left to right. **Try in the task list** opens the working editor, where either treatment can be changed while preserving edits to the task.

Five project treatments explore filing location: a hierarchical path above the title, a folder tab on the card edge, a byline under the title, a “Filed in” row with an explicit Move action, and a collection initial next to Notes. Four deadline treatments explore due time: a trailing flag, a calendar leaf, a countdown with the exact timestamp, and a strip showing the due week. All 20 pairings share the Time as the picker layout. Two previous finalists serve as controls.

## Outcomes

| Project and deadline | 390 pt comparison | 440 pt finalists |
| --- | ---: | ---: |
| Folder tab + time remaining | 9.33 | 8.83 |
| Folder tab + calendar leaf | 9.33 | 8.33 |
| Folder tab + trailing flag | 8.17 | 8.83 |
| Filing path + week strip | 7.33 | 6.17 |
| Previous stacked rows | 8.33 | 8.17 |
| Previous tear-off stub | 8.33 | 7.33 |

The folder tab averaged 8.54 across all deadline styles in the 390 pt panel. It communicates where the full task belongs and makes the project picker discoverable. The countdown communicates urgency in words and keeps the due timestamp apart from the scheduled time. Its main weakness is that a populated countdown can look read-only. The calendar leaf provides a more recognizable date shape, with redundant text for distant date-only deadlines. The trailing flag uses less vertical space but takes width from the title. The week strip introduces several competing dates.

## Method and replay

Nine independent, same-provider Codex iPhone UI critics completed three blinded panels. The baseline panel scored the two earlier finalists at 8.50 each. Three new critics then scored both references and all 20 combinations. The third panel covered the previous references and the best pairing for each deadline treatment. Ties advanced the shorter populated card, then the alphabetically first layout ID.

The first two panels used a 390 pt screen and matched populated, project-only, deadline-only and long-project/overdue states. The final 440 pt panel used a future date without a time, due today, both empty, and the same long-project/overdue state. The task's title, notes, tags, priority, scheduled time, clock, and list fixture are fixed across the conditions for a given state. Compare means within a panel. Each criterion has equal weight. This study captures visual judgments, with input exercised in browser prototypes. Native touch, keyboard behavior, VoiceOver and dark appearance require separate verification.

Use Pillow and run the following from this directory. Each export requires a fresh destination.

```sh
python3 ../workspace-rows/summarize.py ballots.csv
python3 replay.py baseline /tmp/project-time-baseline
python3 replay.py comparison /tmp/project-time-comparison
python3 replay.py final /tmp/project-time-final
```

Give each new reviewer only its R1, R2 or R3 packet. Ask whether Project communicates where a task belongs, Deadline communicates when it is due, and both fields remain independently identifiable and editable across the shown states without confusion with the schedule or tags. Request marks for orientation, scanability, affordance, legibility and composition, each from zero to two in half-point steps, and a specific visible tradeoff for each ID. The [90 ballots](ballots.csv) preserve raw marks, comments and presentation order.
