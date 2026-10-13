# tsk

An iOS Taskwarrior client with TaskChampion as its intended backend.

Bootstrapped from [iOS-Swift-app-template](https://github.com/Julesseg/iOS-Swift-app-template).
The app currently runs the template greeting screen. TaskChampion integration,
task management, and synchronization are yet to be implemented.

## Development

- Open `App/Tsk.xcodeproj` in Xcode and select the `Tsk` scheme.
- Run Core tests: `cd Core && swift test`.
- App display name: `tsk`; bundle identifier: `com.julesseguin.tsk`.
- Targets iOS/iPadOS 26.0 and later, with Swift 6.

## Layout

- `Core/`: `TskCore`, the SwiftPM package for business logic and unit tests.
- `App/`: the SwiftUI app and XCUITest smoke suite.
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
