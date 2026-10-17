# Adaptive workspace and keyboard verification

Wide windows use the native three-column `NavigationSplitView`: task views, projects, and saved filters in the sidebar; the existing task list in the content column; and the shared task detail in the detail column. Narrow windows use the native navigation stack and existing segmented/project controls. Native lists, forms, sidebar styles, materials, toolbars, Dynamic Type, and semantic labels retain system appearance, including Liquid Glass on supported systems.

At accessibility Dynamic Type sizes, regular windows use a two-column sidebar and task navigation stack. Body-scaled sidebar width hints are bounded by the available window width so task content retains space. Selecting a task opens the same shared detail within the stack, and Back returns to the list. Ordinary text keeps the three-column workspace; narrow windows keep the compact controls. The selected UUID remains shared across these presentations, without capping text scaling.

The largest-type XCUITest retains custom-view assertions and captures, and additionally checks sidebar/content geometry, capture and edit/save, and returning from detail to the same task identity. The source correction follows the actual CI14 largest-type capture, which showed cramped columns despite the earlier test passing. New runtime screenshots and presentation-transition verification remain pending canonical CI; generic compilation does not establish the resulting readability.

Task selection uses UUIDs. Upcoming rows retain their separate date/role presentation identities while selecting the same underlying task. Keyboard movement follows the visible list order, visits each task once, stops at the ends, and scrolls the selected row into view. Arrow movement uses cached records through the pure public TaskManager selection operation, without a storage query or synchronization interruption. Editing and completion use the existing TaskManager mutations, semantic mutation lease, persistence, and synchronization hooks.

The native Tasks command menu exposes:

| Shortcut | Action |
| --- | --- |
| Command-N | Capture a task |
| Command-Up / Command-Down | Previous / next visible task |
| Command-O | Reveal selected details in narrow navigation |
| Command-E | Edit selected task |
| Command-Shift-Return | Complete selected task |
| Command-1 / 2 / 3 / 4 | Today / Upcoming / Unfinished / Completed |
| Command-R | Reload tasks |
| Command-Return | Save the native editor |

Mutating commands are unavailable while saving or while a workspace sheet is open; normal editor typing and save shortcuts retain their own focus. Unsupported task states retain their existing action restrictions. Native Tab and list keyboard interaction remain available.

## Checks

Core public TaskManager tests cover view order, repeated appearances, empty/changed view recovery, and completing only the selected identity while retaining opaque attributes. The real TaskChampion adapter check selects, edits, completes, reopens, and exports through Taskwarrior, verifying that the other task remains pending and that UUID, opaque fields, scheduled date, and deadline are preserved.

The canonical workflow retains the full iPhone suite and adds an independent iPad XCUITest job with its own result bundle. The iPad scenarios cover a landscape workspace, keyboard-event capture/edit/completion and persisted reopen, project Today membership with a waiting task, portrait detail, Upcoming date roles sharing one UUID, custom sidebar views, and accessibility text size. Screenshots are kept as XCTest attachments. Both device jobs retain ad-hoc simulator signing, shared App Group and intent metadata verification, and simulator ownership cleanup.

The local signed generic arm64 App and XCUITest build passed. Core tests (44) and the real native/Taskwarrior selected-action test passed. Local simulator execution and screenshots were not performed because the shared Mac was explicitly constrained against new simulator boots. The new iPad CI scenarios still require execution on the published integration branch. Existing iPhone CI results from earlier revisions are baseline evidence, not proof of this navigation change.

## Physical keyboard acceptance

XCUITest `typeKey` events are injected simulator events. They do not prove a real keyboard connection, key delivery, discovery overlay/menu, hardware layout, focus traversal, or iPad window resizing. No physical keyboard was connected or tested in this task. On an actual iPad with a keyboard, verify the command menu/discovery, Tab/arrow movement, Command-N/E/Shift-Return and editor Command-Return, multiple visible Upcoming appearances, project/custom view changes, and narrow/wide window transitions. Preserve and report that evidence separately from CI results.
