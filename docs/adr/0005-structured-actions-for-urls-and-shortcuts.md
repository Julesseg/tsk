# Share named actions across URLs and Shortcuts

We will expose Add Task, Modify Task, Delete Task, Find Tasks, Complete Task, Open Task, and Open View through both Shortcuts and the URL scheme, with named inputs and shared task behavior. We choose structured inputs over Taskwarrior command and filter syntax because tsk's purpose is to make Taskwarrior-compatible tasks comfortable to use on mobile; callers should not need command syntax to automate the same work.

Custom views retain their Taskwarrior-filter contract; structured action inputs do not narrow that separate capability.

URLs use simple, unversioned routes such as `tsk://add` and `tsk://open-task?id=…`; future additions must preserve the meanings of existing links. Mutations target one task using its full UUID in URLs or a task entity in Shortcuts, with Find and explicit iteration for bulk workflows. Each interface retains its native execution and results rather than implementing Shortcuts as wrappers that open custom URLs.

Mutation success acknowledges durable local storage, including offline use, rather than server acknowledgement. Optional URL callbacks return structured JSON; failed callback delivery neither undoes a saved change nor retries the action automatically. Rebuild the existing Shortcuts actions without a requirement to preserve old saved workflows or intent identities; do not retain a compatibility Reschedule action, since Modify Task covers rescheduling.

This records the agreed design. The complete field, query, navigation, and verification requirements are tracked in [Add Task #65](https://github.com/Julesseg/tsk/issues/65), [Find Tasks #66](https://github.com/Julesseg/tsk/issues/66), [Modify Task #67](https://github.com/Julesseg/tsk/issues/67), [Complete Task #68](https://github.com/Julesseg/tsk/issues/68), [Delete Task #69](https://github.com/Julesseg/tsk/issues/69), and [Open Task and Open View #70](https://github.com/Julesseg/tsk/issues/70).
