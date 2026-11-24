# Project and deadline

Open the [interactive gallery](report.html) in a browser. It includes 24 new variations and the previous **Time as the picker** control. Compare any two at 390 or 440 pt, switch between a populated task, two empty properties and an overdue task with a long project hierarchy, and try the pickers in context. Edits stay in memory. The two-sided card and pull-down drawer each add one tap before choosing a field.

| Family | Alternatives |
| --- | --- |
| Conventional | Pills under Notes, split capsule, stacked rows, two-column footer, plain-text corners, trailing toolbar |
| By placement | Project over title, project under title, project with tags, deadline under title, card header, deadline under time |
| By treatment | Sentence below Notes, relative deadline, project path, index strip, schedule to deadline, calendar tile |
| Expressive | Folder tab, ledger lines, tear-off date stub, deadline bookmark, two-sided card, pull-down details |

## Findings

| Layout | 390 pt, all options | 440 pt, family finalists | Populated card at 390 pt |
| --- | ---: | ---: | ---: |
| Time as the picker reference | 7.67 | 7.83 | 125 pt |
| Stacked rows | 9.67 | 9.33 | 154 pt |
| Card header | 9.00 | 8.17 | 126 pt |
| Relative deadline | 9.50 | 8.67 | 127 pt |
| Tear-off date stub | 9.83 | 9.00 | 141 pt |

Reviewers favored separate edit targets that still worked with long values. The stub made the day and time scannable. Two disclosure rows made editability explicit but took more space. The populated relative date often read as a status label. Putting the project in the tag gutter scored 5.50, with midword wrapping the recurring concern.

The chosen time picker, title-aligned Notes, cycling priority, tag area, 12 pt leading inset, Adaptive row spacing and checked workspace menu anchor the study. Project and deadline use the same underlying single-task pickers from the [previous study](../expanded-pickers/README.md). New options use explicit empty actions and a tint on overdue dates. Treat improvements over the reference as the combined effect of placement, styling and those shared changes. The two-sided option temporarily replaces the editor with the property face. Native interaction and accessibility are outside this browser study.

## Reproduce the scoring

Three independent same-provider Codex iPhone UI critics reviewed the reference at 390 pt (mean 7.50). Three fresh critics reviewed 25 shuffled anonymous designs at 390 pt. Three further critics reviewed five at 440 pt, the same reference and one finalist per family. Each family advanced its highest mean from the first comparison, breaking a tie by shorter populated card and then catalogue order. Data and scoring criteria were identical across alternatives in each panel. The extra editing-face image for the two disclosure alternatives was captured at 390 pt.

From this directory, run the following to reproduce the means and anonymous packets. The packet export uses Pillow. Give each fresh reviewer only its own R1, R2 or R3 directory. Use fresh output directories.

```sh
python3 ../workspace-rows/summarize.py ballots.csv
python3 replay.py baseline /tmp/project-deadline-reference
python3 replay.py comparison /tmp/project-deadline-comparison
python3 replay.py final /tmp/project-deadline-final
```

Ask each reviewer to locate Project and Deadline, identify which control edits each, and distinguish the two across populated, empty and long-project/overdue states. Inspect the sheets in order. Score orientation, scanability, affordance, legibility and composition from 0 to 2 in half-point steps. A 2 indicates clear evidence, 1.5 minor friction, 1 meaningful friction, 0.5 substantial friction and 0 missing evidence. Return the five marks and a specific visible tradeoff for each opaque ID. The [93 recorded judgments](ballots.csv) preserve the marks, presentation order and reviewer comments.
