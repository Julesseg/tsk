# Projects, tags, and priority

Organization is handled by the existing Core `TaskManager`, including capture,
focused edits, persistent reads, and project selection. Project views match an
exact, case-sensitive project name. `Work`, `Work.sub`, and `Workplace` are
separate selections; Taskwarrior filter expressions retain their independent
filter contract. Unassigned tasks are available through a dedicated selection.

Tags use the presence of individual `tag_<name>` properties. Their values and
any redundant legacy `tags` string do not determine membership. Adding/removing
tags updates the appropriate keys and reconciles the legacy string when tag
keys change, matching [Taskwarrior 3.5.0's representation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Task.cpp).
Unrelated edits leave existing unfamiliar attributes and legacy values intact.

New tag names follow the pinned
[TaskChampion 3.1.0 user-tag rules](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/task/tag.rs):
no whitespace, no initial ASCII digit/operator, no colon after the first
character, and no name made solely of uppercase ASCII letters. Existing raw
tag attributes are retained, including unfamiliar spellings. Users can remove
stored tags explicitly. Tags are added individually in the native editor; a
pending name is also validated and added when Save is pressed.

Priority supports Taskwarrior's default H/M/L values and an absent value.
Unsupported new values produce an actionable error before writing. Existing
unrecognized values are retained when another field is edited; the native
picker displays that current value explicitly until the user changes it.
Projects and priorities can be cleared without replacing the task or its other
attributes.

The shared editor includes organization during both capture and edits. The
native project menu scopes the existing list and keeps its detail, edit, and
completion actions. A new draft inherits the selected project. Moving a task
removes it from its previous exact project view after acknowledged storage,
while the editor/detail retain the saved record even when it leaves that view.
All mutations use the same public interface as synchronization and other entry
points; no alternate task dataset or persistence format is introduced.

Core tests cover exact project membership, tag-key precedence, clearing fields,
validation without mutation, and retained unknown values. Real native tests
reopen TaskChampion storage after organization edits and compare project,
priority, and tag exports against Taskwarrior 3.5.0. The app and XCUITest target
compile for an arm64 simulator. Actual simulator UI execution, appearance,
physical keyboard, and device accessibility evidence remain separate gates;
local screenshot gaps are listed in the UI report.
