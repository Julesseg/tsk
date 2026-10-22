# Native iPad adaptive navigation

The iPad workspace uses UIKit's native sidebar-adaptable `UITabBarController`,
with SwiftUI workspace content. Favorites retain their local persistence and
order; the complete sidebar catalog and Views menu select unfavorited views
without changing favorites. Exact project links and No project are available in
both presentations. The Views menu checks the current direct project and saved
view. The regular tab/sidebar preference is local to the device.

## Native containment and compact tabs

The shell owns stable native tabs and a unique SwiftUI hosting controller for
each root, group and catalog entry. This follows the public
[`tabs`](https://developer.apple.com/documentation/uikit/uitabbarcontroller/tabs)
contract, including a non-nil controller for every root group. Host ownership
survives content changes between task columns and compact navigation. The inherited keyboard router crosses the hosting boundary; UIKit traits
provide each host’s system environment. Removed catalog entries release their cached tabs and controllers.

The SwiftUI adaptive shell reproduced two failures on the iPadOS 27.0 simulator:
a nil-item exception during catalog flattening and an invalid selected-controller
exception when resizing with an unfavorited current destination. An inactive
favorite also remained visually selected while different content was open.
The owned native shell uses explicit controller factories and selection instead
of relying on that generated containment.

The public
[`compactTabIdentifiers`](https://developer.apple.com/documentation/uikit/uitabbarcontroller/compacttabidentifiers)
filter limits the compact bar to favorite roots plus a temporary native current
tab when needed. The current tab disappears on choosing a favorite; it does not
change favorite membership, order or the four-favorite limit. Favorite/current
tabs use fixed placement, and catalog groups and leaves use sidebar-only
placement, so native customization cannot create a second favorite collection.
Native project identifiers encode exact UTF-8 bytes; titles and navigation retain
the original project names.

## Regular presentation during live resizing

The native window can temporarily switch between top tabs and sidebar before its
size class changes. Persisting those intermediate placements changed the regular
preference during a corner drag. The native sidebar delegate captures the event's
public scene
[`isInteractivelyResizing`](https://developer.apple.com/documentation/uikit/uiwindowscene/geometry/isinteractivelyresizing)
state before recording presentation changes. It observes
[`effectiveGeometry`](https://developer.apple.com/documentation/uikit/uiwindowscene/effectivegeometry)
using Apple's documented KVO support and restores the regular preference after
resizing ends and regular traits arrive. Observation follows the visible shell
lifecycle; stale scene/geometry events cannot overwrite a newer transition.
Preference callbacks run outside SwiftUI representable updates.

## Runtime verification

Canonical iPad XCUITest covers initial top tabs, full sidebar/project access,
unfavorited custom selection, menu checkmarks, favorite capacity/order, Settings,
regular presentation after relaunch, largest accessibility text, keyboard commands
and real window resizing. The compact journey checks empty Today and an
unfavorited custom view, toolbar capture, unchanged favorites, selected native
indicators and a live Settings interaction after expansion. Frozen screenshots
alone do not establish successful recovery from a layout transition.

Run `WorkspaceSettingsUITests` and `iPadWorkspaceUITests` through
`scripts/run-ui-tests.sh` on the owned iPad simulator. Shared Settings journeys
also cover iPhone navigation. Source/build checks do not establish physical
keyboard delivery, hardware behavior, account services or distribution.
