# Edit tasks in the current list

Task editing and capture use an expanding task row in the current list, replacing the separate task-detail page and native editor sheet, to preserve the user's place while acting on work. The title and completion control keep a shared header position while only the lower section expands; compact project and deadline metadata fade as the attribute controls appear. There is no collapse arrow. Native project and priority menu pickers and glass date-picker containers open from their attribute pills, while surrounding rows move aside and dim; capture inserts a new row already expanded, and tapping outside saves valid changes and collapses the editor, with no Cancel button. This deliberately takes on custom layout, focus and gesture coordination in exchange for continuity between scanning and editing; rows remain anchored until editing finishes, and existing task links reveal a containing list and expand the task, preserving a route back. Detailed behavior is recorded in the [design audit](../design-audit.md).

The lower reveal updates layout height from elapsed time with implicit List
animations disabled. This keeps the shared header fixed while neighbouring
rows follow the changing bottom edge; it avoids the native hosting cell
recentering its content during a row-height animation. Reduce Motion applies
the final height directly.
