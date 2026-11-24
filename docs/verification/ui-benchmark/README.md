# iPhone screenshot benchmark

Use this protocol to compare visual designs for tsk. Freeze the screen list, fixture, appearance, device, rubric and number of rounds before looking at ratings. Each reviewer is a fresh same-provider subagent taking the role of an iPhone UI design critic. Give it only the review prompt, a list of opaque image paths and the corresponding user goals. Keep the score key, other reviews and implementation notes private until all ballots are in.

[November 24 detail study, scores and visual report](2026-11-24/README.md)

[Workspace switching, expanded controls and row density](workspace-rows/README.md) uses a populated fixture and evaluates each decision separately.

[Expanded task pickers and leading inset](expanded-pickers/README.md) compares single-task uses of the rebased multi-edit pickers.

[Project and deadline](project-deadline/README.md) explores 24 treatments within the selected Time as the picker layout.

## Capture list

Use standard text size, portrait and light appearance. The first run used the iPhone smoke suite's existing XCUITest attachments. For an exact rerun, download the ui-test-results artifact from [run 45270385965](https://github.com/Julesseg/tsk/actions/runs/45270385965) and run `xcrun xcresulttool export attachments --path App/TestResults.xcresult --output-path shots`. Map its manifest to the six test and attachment names in captures.json. The benchmark archive retains the original PNGs for repeat scoring. For a new revision, capture the same states with those tests. Use the repository simulator lease and device workflow for local runtime work. Record revision, runtime, viewport and capture method.

| Screen | Starting state and user goal |
| --- | --- |
| Planner | Today, with two tasks. Identify today's tasks and how to change the day. |
| Inbox | Inbox with a deadline-only task. Scan unfiled work and locate capture. |
| Workspaces | Open the bottom workspace menu. Find the available workspaces and the current destination. |
| Project | Open Work. Identify scheduled and unscheduled tasks and how to return to Projects. |
| Editor | Expand the populated task without a keyboard. Identify editable properties. |
| Calendar | Open the Planner month picker. Identify the selected day and how to switch days or months. |

Use the same visible records, dates, control states and viewport for every candidate. Label intentional structural changes and disclose unavoidable mismatches in the report. Save the original images and rasterize each prototype at the matched viewport. Use a neutral outer canvas and identical image treatment. Discard and recapture stale, obscured or wrong screens before scoring.

## Reviewer prompt

Inspect every supplied image visually. Work independently as an iPhone UI design critic. For each image, give each criterion 0 for missing or misleading evidence, 0.5 for substantial friction, 1 for a usable result with a specific obstacle, 1.5 for a clear result with minor friction, or 2 for no meaningful visual friction for the stated goal. Consider metadata, alignment, dates and hierarchy where relevant. A sparse screen can score highly. Extra labels or decoration can hurt.

1. Orientation. Can I identify where I am and the active context?
2. Scanability. Can I find the content named in the goal and distinguish its hierarchy?
3. Affordance. Can I recognize how to perform the stated action or navigate from here?
4. Legibility. Are the text and meaningful control or state differences visually legible?
5. Composition. Do alignment, grouping, spacing and density support this screen's purpose?

Return the image ID, five marks in half-point increments in that order, one visible strength and one specific concern. Score only visible evidence. Do not infer gesture behavior, target sizes, accessibility compliance or performance. Use the whole scale as warranted. Do not examine source files, metadata, previous ratings or the design key.

## Run and compare

1. Obtain three independent ballots on the current screenshots, changing presentation order per reviewer. Freeze and aggregate those ballots before prototyping. Use recurring concrete feedback to define alternatives.
2. Run three fresh independent ballots under the same prompt. Include an unannounced copy of the baseline as a control. Mix all designs under anonymous image IDs, rotate presentation order and keep each screen equally weighted. Avoid sequential conversations with a reviewer who has seen earlier scores.
3. Sum the five marks to get each screenshot score out of ten. Average across screens for each ballot, then across the three ballots for each design. Report the three ballot means, screen means, and each candidate's difference from the same-round control. Show the difference between the first baseline and the control as a check on reviewer drift. Keep unrounded values through aggregation.
4. Archive the image-to-screen key, ordered packets, raw ballots and exact images with the report. Show regressions, disagreements and tradeoffs alongside the means. These scores are subjective visual judgments from one model family. Interactions, accessibility, Dynamic Type and user preference require separate evidence.

Run `python3 score.py <evidence-directory>` from this directory to reproduce the means. Supply a key.csv with image,phase,design,screen columns and a ballots.csv with reviewer,image,orientation,scanability,affordance,legibility,composition columns. Additional columns can record the reviewers' comments. Use globally unique image IDs for phase-specific packets. Each phase and design needs one score per screen from each of three reviewers.

With Pillow 10.1+ installed, place the six PNGs named planner, inbox, workspaces, project, editor and calendar in a directory per design. Prepare a phase with `python3 packets.py baseline run/baseline --seed 2411 --design Current <png-directory>`. For the second phase use `comparison`, a new output path and seed, and one `--design NAME DIRECTORY` per design including Current. Give each subagent only its R1, R2 or R3 directory and the reviewer prompt above. Join both key.csv files with a single header before scoring.

If alternatives reach the scoring ceiling, retain the original ballots. A supplemental panel can judge each pair for the same screen goal. Shuffle screen order, balance the left and right positions, allow a tie, and record both the visible reason and the tradeoff. Report pair preferences separately from scores and identify whether the follow-up was planned before scoring.
