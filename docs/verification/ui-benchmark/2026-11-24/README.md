# Detail study · November 24

[Open the standalone visual report](report.html) locally. Each section shows a matching detail crop of Current, Compact and Descriptive. “Full screens” restores the surrounding interface. Each scored PNG is available from its caption.

The current app scored 8.28/10 across three initial reviews. Three fresh reviewers then scored all three versions together.

| Design | Round 1 | Round 2 | Round 3 | Mean / 10 |
| --- | ---: | ---: | ---: | ---: |
| Initial baseline | 8.25 | 8.25 | 8.33 | 8.28 |
| Current, mixed comparison | 7.42 | 7.58 | 7.42 | 7.47 |
| Compact | 8.67 | 8.92 | 8.75 | 8.78 |
| Descriptive | 9.42 | 9.75 | 9.50 | 9.56 |

**The editor showed the clearest improvement.** In the comparison panel it scored 5.50 with the current scrolling strip, 7.83 with compact date pills wrapped below the organization controls, and 9.50 with named date fields inside the same expanded row. All three reviewers still found Notes pale in the labeled version.

A deadline directly below its task made it easier to associate than a trailing flag. Two-letter weekdays improved identification in the existing month grid. The checkmark was sufficient for most of the workspace-menu gain. The project-list scores were close at 8.33 and 8.50. Adding “No schedule” had a smaller benefit than labeling the editor fields.

## Evidence

The prototype starts from six full-resolution XCUITest screenshots of commit 4fe70da on iPhone 18 Pro Max, iOS 27.2. Only local text and symbol overlays change between variants. The native toolbar, glass controls, date pill, month grid, expanded card and completion-circle positions come from the app. The date chooser outside Planner retains the dash button requested in PR #122. The pixel audit compares every full-resolution RGB pixel with the native source. Each rendered control matched exactly, and under 1% of pixels changed for each alternative. [Source XCUITest run](https://github.com/Julesseg/tsk/actions/runs/45270385965) · [Planner design history](https://github.com/Julesseg/tsk/pull/122)

Each phase used three separate Codex GPT-6.2-astra reviewers at high reasoning effort. Each reviewer opened the anonymous sheets in packet order and used reviewer-brief.txt. Every mark, comment and presentation position is recorded in ballots.csv. The key.csv file maps image IDs to screens. The 0.81-point difference between the initial baseline and the unchanged comparison control is one reason to compare designs within the second panel.

The screenshots show lightly populated, standard-text, portrait states. The visual overlays do not exercise SwiftUI layout at other widths, native interaction, scrolling, VoiceOver or dark appearance.

## Repeat

Run `python3 ../score.py .` here to reproduce the means. To reconstruct the packets, save the original PNGs from the report, place each design in its own directory and remove the design prefix from each image filename. Run packets.py as described in the [benchmark protocol](../README.md), using seed 2411 with Current for baseline and seed 2422 with Current, Compact, Descriptive in that order for comparison.
