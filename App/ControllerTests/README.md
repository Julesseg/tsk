# Calendar controller regression checks

The macOS CI jobs run this package after building the host TaskChampion bridge
and before creating their simulator.

Run on macOS 14 or later with the matching TaskChampion bridge:

```sh
TSK_TASKCHAMPION_LIBRARY=/path/to/libtsk_taskchampion.dylib swift test --package-path App/ControllerTests
```

The test target compiles the actual app controller through a relative symlink. It replaces only its passive diagnostic sink with a phase recorder, and injects a controlled Calendar source and an owned temporary TaskChampion manager. No EventKit access request, Calendar read or personal store operation runs. These checks cover refresh ordering; canonical device tests still verify actual authorization and UI behavior.

A second dependency-free target compiles the exact UI-test readiness coordinator
through its own relative symlink. Its controlled clock, samples and action sink
check one five-second budget, accepted geometry and at-most-once action selection.
It imports standard CoreGraphics geometry without making UI or provider calls.
These checks do not establish native input delivery or application response.

A third dependency-free target compiles the actual keyboard registration decision
through a relative symlink. It checks declaration changes, weak host ownership and
unchanged-update suppression. UIKit installation and current-scope action dispatch
remain separate source and canonical iOS checks.

The readiness target also compiles the actual UI-test reveal scroll decision
through a relative symlink. It checks that an absent target retains the caller's
or last observed direction across the existing scroll budget, and that observed
target geometry can redirect the search. It does not establish native scrolling
progress, boundary detection or target revelation.

The keyboard command target compiles the exact Foundation portion of the UI-test
command helper through a relative symlink. It checks fixed phase order, complete
nonce-bound acknowledgements, expiry/abort rejection, explicit driver ownership
and atomic runner-file boundaries. The UIKit adapter, host relay integration and
actual native key delivery require separate compilation and canonical UI checks.
