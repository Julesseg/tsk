# November 23 iPhone design comparison

Open the [standalone report](report.html) locally to inspect the six screens side by side, enlarge an image or download the original PNG. The report contains 18 images, the screen-level scores and the follow-up preference results.

| Design | Round 1 | Round 2 | Round 3 | Mean / 10 |
| --- | ---: | ---: | ---: | ---: |
| Current app, baseline only | 8.00 | 8.00 | 8.17 | 8.06 |
| Current app, mixed comparison | 6.67 | 7.17 | 7.00 | 6.94 |
| Fieldnotes | 10.00 | 10.00 | 10.00 | 10.00 |
| Index | 10.00 | 10.00 | 10.00 | 10.00 |

Three baseline reviewers identified the clipped date and unlabeled properties in the editor. It scored 6.00 in both phases. The project list's faint dash for unscheduled work and unnamed back destination also drew consistent criticism. Both mockups spelled out deadlines, identified the current workspace and fit the editable properties on screen.

All 36 concept scores reached the rubric's ceiling. Three additional independent reviewers compared the alternatives side by side. All three preferred Index for planning and editing and Fieldnotes for capturing unfiled work and separating scheduled project tasks. All three tied the workspace menus. Two tied the month pickers and one favored Index.

The current screenshots came from iPhone 18 Pro Max XCUITest at revision 4fe70da. The alternatives are static HTML prototypes rendered at the same 440 × 956-point viewport. These six lightly populated, light-appearance states do not measure interaction quality. The Projects index and Settings were outside the scored set. [Source CI run](https://github.com/Julesseg/tsk/actions/runs/45270385965)

## Reproduce the results

Run `python3 ../score.py .` from this directory. The ballots file includes the five marks and each reviewer's two observations. The key maps each anonymous image ID to its phase, screen and design. The preferences file records pair order, left and right assignment, choice, reason and tradeoff. R1–R3 identify different reviewers in each phase.

To recreate the shuffled screenshot packets, use the report's original PNGs, removing the design prefix from each filename inside its design directory. Run packets.py with seed 1221 and Current for baseline. Use seed 2251 and design order Current, Fieldnotes, Index for comparison. For the supplemental pair review, each reviewer saw each screen once in shuffled order. Each concept appeared on the left three times per reviewer. Use the recorded order and sides in preferences.csv to reproduce those ballots.
