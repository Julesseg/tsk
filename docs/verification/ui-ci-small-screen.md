# Small-screen editor and synchronization corrections

The canonical iPhone SE (3rd generation), iOS 26.2 run for `2167c88` failed six UI scenarios. Its screenshots, accessibility descriptions, and screen recordings distinguish three causes:

- Planned-day switches had frames starting at y=522.5 while the keyboard covered the lower screen. The previous helper relied on `isHittable`, then tapped that covered frame. The recording shows the touch inserting `L` into the description. The editor now provides Done above the keyboard for all its text fields. The date helper dismisses the keyboard, waits for it to disappear, scrolls the form until the switch has a finite frame within the visible content, and then verifies the requested state.
- Empty-description errors were appended after the expanded organization and date sections, below the visible form. The editor now keeps validation and write failures above the scrolling form and dismisses text input on Save. Failed saves still retain the draft.
- Disconnect was below the long synchronization error and explanatory sections and was absent from the visible accessibility hierarchy. It now remains in the synchronization toolbar while a connection is configured, retaining its existing busy-state guard and local-task preservation.

The organization test assumed tapping an existing field would put its cursor at the end. The recorded task correctly persisted `.subWork` after the test inserted `.sub` at the beginning. The test now selects the existing single-word project, replaces it with `Work.sub`, and asserts the exact field value before saving. The production project semantics and all existing test expectations remain unchanged.

Generic arm64 `build-for-testing` passed for the app and XCUITest targets. No business behavior changed and no simulator was booted locally. The original failing scenarios must run again on canonical CI before these corrections can be called execution-verified. The skipped successful-server UI scenario still needs a real isolated server fixture.

Actual before screenshots, touch events, accessibility descriptions, and recordings are preserved outside the repository in `/tmp/tsk-issue-3/ui-ci-2-planning`, `ui-ci-2-capture`, `ui-ci-2-sync`, and `ui-ci-2-organization`. The single-file report is `/tmp/tsk-issue-3/ui-ci-2-report.html`; it labels missing after captures explicitly. Build evidence is `/tmp/tsk-issue-3/ui-ci-2-fix-build.log`.
