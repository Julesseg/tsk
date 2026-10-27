# Moss app icon

The app uses `App/Tsk/AppIcon.icon`, the selected Moss / Soft split artwork.
The existing `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` setting in both
Debug and Release selects this document through the app's synchronized group.
The empty legacy `AppIcon.appiconset` is removed. This follows
[Apple’s Icon Composer integration](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer#Add-your-Icon-Composer-file-to-an-Xcode-project).

The 1024-unit artwork preserves the chosen +28% horizontal, +15% vertical,
+21-degree rotation and 114% scale. The circle is an unfilled ring; the check
has rounded corners and a narrow split. Default uses background `#E2E8D5`,
check `#2E4B3A` and ring `#718569`. Dark uses `#19251D`, `#DFE8D2` and
`#8EA485`. Monochrome overrides preserve check/ring contrast for the clear
and user-selected tinted appearances.

Edit the layered document in Icon Composer. Do not round the outer artwork
or replace the native clear/tinted materials with flattened PNGs.

## Verification

- Baseline and changed unsigned simulator builds passed with Xcode 27.1
  (27A9275), SDK 27.1, arm64, and deployment target 26.0.
- The changed build's asset compiler consumed `AppIcon.icon` with
  `--app-icon AppIcon --target-device iphone --target-device ipad`.
- The built iPhone and iPad primary icon dictionaries both name `AppIcon`.
- Installed on iPhone 17 and iPad Pro 11-inch (M5), both on OS 27.0:
  the placeholder is replaced by Moss in the same home-screen slot.
- The production document matches the selected prototype byte for byte.
  Native exports cover Default, Dark, Clear Light/Dark and Tinted Light/Dark.
- Local builds used an existing simulator TaskChampion archive from the
  `placid-hippo` checkout. All tracked `Native/Bridge` source and lockfile bytes
  matched this branch. Local Rust compilation was not performed because the
  installed Homebrew toolchain lacks rustup and the iOS simulator standard
  library. CI builds the bridge from source.

The [mobile report](moss-app-icon.html) distinguishes installed screenshots
from native artwork exports and lists capture limits. Physical devices,
distribution signing and the complete XCUITest suite are not verified locally.
The PR's canonical iPhone/iPad smoke and Core/Native CI gates remain required.

The mobile report was checked at 390 px and 320 px, including every image and
tap-to-enlarge. Its runtime comparisons use matching crops of the app grids;
the unmodified screenshots and build logs are retained at
`/tmp/tsk-moss-install-verification/`. Both task-owned simulators were shut down.
