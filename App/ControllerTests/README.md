# Calendar controller regression checks

Run on macOS 14 or later with the matching TaskChampion bridge:

```sh
TSK_TASKCHAMPION_LIBRARY=/path/to/libtsk_taskchampion.dylib swift test --package-path App/ControllerTests
```

The test target compiles the actual app controller through a relative symlink. It replaces only its passive diagnostic sink with a phase recorder, and injects a controlled Calendar source and an owned temporary TaskChampion manager. No EventKit access request, Calendar read or personal store operation runs. These checks cover refresh ordering; canonical device tests still verify actual authorization and UI behavior.
