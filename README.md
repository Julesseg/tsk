# tsk

A native iOS and iPadOS Taskwarrior client backed by TaskChampion. Task data is
stored locally in a shared App Group and synchronized through TaskChampion's
encrypted protocol. `TskCore` owns task behavior; `TskNative` connects storage and
system services; SwiftUI presents the app, Share extension and widgets.

Implemented workflows include task editing, projects/tags, Today/Upcoming,
Taskwarrior filters and saved views, recurring templates and occurrence/series
editing, Shortcuts, sharing, widgets, Spotlight, Calendar display, Reminders
import and task-date notifications. The designated desktop Taskwarrior client
creates recurring occurrences after sync and a recurrence-enabled report.

Portable Core tests, real native/Taskwarrior interoperability checks and signed
generic builds cover the implementation. Canonical iPhone/iPad XCUITest is the
runtime gate; current failures still require fixes and another run. Distribution
requires App Group-capable profiles for the app and both extensions. Physical
keyboard, personal-account, Focus and background behavior require separate
acceptance evidence; compiled targets and registered requests do not prove it.

Bootstrapped from [iOS-Swift-app-template](https://github.com/Julesseg/iOS-Swift-app-template).

The [PRD](docs/prd.md) defines the initial product requirements, implementation
decisions, and testing seams. The [product brief](docs/product-direction.md)
summarizes the agreed direction, with shared terms in [GLOSSARY.md](GLOSSARY.md),
decisions in [docs/adr](docs/adr/), and source-based feasibility findings in
[docs/research](docs/research/).

The PRD is published as [spec #3](https://github.com/Julesseg/tsk/issues/3) in
the issue tracker for implementation planning.

## Development

- Open `App/Tsk.xcodeproj` in Xcode and select the `Tsk` scheme.
- Run Core tests: `cd Core && swift test`.
- App display name: `tsk`; bundle identifier: `com.julesseguin.tsk`.
- Targets iOS/iPadOS 26.0 and later, with Swift 6.

## Layout

- `Core/`: `TskCore`, the SwiftPM package for business logic and unit tests.
- `Native/`: TaskChampion bridge and platform adapters.
- `App/`: SwiftUI app, Share extension, widgets, owned test host and XCUITest.
- `.github/workflows/`: Core/UI CI, release pipelines, and optional agent dispatch.
- `docs/agents/`: GitHub issue workflow, default triage labels, and domain-doc rules.

## Engineering workflow

Track work in [GitHub Issues](https://github.com/Julesseg/tsk/issues).
The Matt Pocock engineering skills read configuration from `docs/agents/*.md`;
edit those files directly to change the setup. `AGENTS.md` is canonical and
`CLAUDE.md` imports it.

The default triage labels are `needs-triage`, `needs-info`, `ready-for-agent`,
`ready-for-human`, and `wontfix`. Domain documentation uses a root `GLOSSARY.md`
and `docs/adr/`, created when terms or architecture decisions need recording.

CI runs Core tests and XCUITest on pull requests. Signing, TestFlight,
installable PR builds, and agent dispatch need their own configuration;
see [template setup](docs/template-setup.md),
[release pipeline docs](ci/README.md), and
[agent dispatch setup](docs/agents/auto-dispatch.md).
