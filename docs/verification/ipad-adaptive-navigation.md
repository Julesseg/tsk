# Native iPad adaptive navigation

The iPad workspace uses SwiftUI's native sidebar-adaptable TabView. Favorites
retain their existing local persistence and order; the complete sidebar catalog
and Views menu can select unfavorited views without changing favorites. Exact
project links and No project are available in both navigation presentations;
the Views menu checks the current direct project as well as saved/custom views. The
regular tab/sidebar preference is local to the device. Compact presentation does
not write that preference.

## Compact native tab filter

The sidebar catalog also participates in UIKit's default compact tab collection,
which produced a More tab and a nil-item exception inside
`UITabBarController._tabs_rebuildTabBarItemsAnimated` during live expansion on the
iPadOS 27.0 simulator. Removing placement observation did not prevent the crash;
the previous bottom-only navigation passed the same resize sequence.

Favorites have stable SwiftUI customization IDs. A small UIKit ancestor adapter
applies the public
[`compactTabIdentifiers`](https://developer.apple.com/documentation/uikit/uitabbarcontroller/compacttabidentifiers)
filter so the native compact bar contains only favorite root tabs. Apple's default
is nil, which includes all tabs. Runtime diagnostics confirmed the native root IDs
match the supplied favorite IDs. The adapter applies configuration after lifecycle
attachment and only changes the native property when its value differs. It does
not replace the native sidebar, tabs, selection delegate or project behavior.

## Runtime verification

Canonical iPad XCUITest covers initial top tabs, complete sidebar/project access,
unfavorited custom selection, menu checkmarks, favorite capacity/order, Settings,
regular presentation after relaunch, largest accessibility text, keyboard commands
and actual window resizing. The compact journey checks an empty Today window and
an unfavorited custom view, upper-toolbar capture, unchanged favorites and a live
Settings interaction after expansion. Frozen screenshots alone do not establish
successful recovery from a layout transition.

Run `WorkspaceSettingsUITests` and `iPadWorkspaceUITests` through
`scripts/run-ui-tests.sh` on the owned iPad simulator. The shared Settings journeys
also cover iPhone navigation. Source/build checks do not establish physical
keyboard delivery, hardware behavior, account services or distribution.
