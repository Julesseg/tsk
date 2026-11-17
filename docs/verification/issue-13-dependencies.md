# Dependency management retired

The user removed task dependency management from the product on 2026-11-17.
The dependency picker, linked-task actions, blocked/diagnostic presentation,
Core add/remove APIs and their dedicated Core, Native and UI tests are removed.
The UI test failure in full run 44102596333 remains historical failed evidence;
retiring the feature does not establish a fix for its accessibility failure.

Existing imported `dep_` and `depends` fields remain untouched by unrelated edits.
Read-only Taskwarrior filter and urgency semantics retain their pinned
compatibility tests, using stored fixtures rather than a dependency mutation API.
Waiting dates and external URL/Spotlight task navigation remain supported.
