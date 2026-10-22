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
survives content changes between task columns and compact navigation. The
inherited keyboard router crosses the hosting boundary; UIKit traits provide
each host’s system environment. Removed catalog entries release their cached
tabs and controllers.

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

On iPadOS 27.0, UIKit could automatically select a sidebar group during live
compact adaptation even with that filter, leaving the selected current controller
outside its compact child collection. A control run without catalog groups
retained both content and the correct selected indicator. The shell therefore
removes cached catalog groups from the native root collection at resize start,
before compact trait adoption, and restores them after regular traits return.
Compact navigation keeps the complete catalog in Views. Cached tabs and hosts
retain their identity across this change in root membership.

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

Compact direct-project content places its heading and sync indicator below the
navigation bar. This leaves room for the native back button, Views, capture and
Settings while keeping exact project context visible. Other workspace titles
retain their toolbar placement.

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

## Verification record — 2026-10-22

The final app source is `951670e`. The clean canonical adaptive
navigation journey passed in 126.769 seconds, including direct project selection,
actual compact/regular resizing, portrait Views access, unchanged favorite
capacity and both presentation preferences after relaunch. The compact journey
passed in 88.973 seconds, including an unfavorited current view, the last favorite,
capture/cancel, live Settings after expansion and the preference after relaunch.
Returned app frames were 1376 × 1032 → 375 × 940.5 → 1376 × 1032 points; the
portrait app/window was 1032 × 1376. These are actual system window transitions.
The compact run used the same app source before the final test-only portrait
Views-opener change; that opener is not called by the compact journey.

All 161 Core tests and the UI-selection/CI-routing regressions (14 and 12 tests)
passed. The five shared iPhone workspace/Settings journeys passed at `75ad178`;
later production changes are confined to iPad navigation.

Seven final iPad regression journeys passed: capture/all Settings destinations,
project navigation/appearance, largest-text Settings, title-adjacent sync
progress, favorite capacity/order/relaunch, custom views at accessibility text
sizes, and project/Today/Waiting/Upcoming/portrait task identity. Six passed in
`proposed-native-broad-final.xcresult`; the favorite journey passed separately in
91.017 seconds after the test-only `eb8b90a` change reacquired cells after the
successful native drag. The gesture, relative-order check, five-second deadline
and relaunch assertions were retained. Original failures remain in the evidence
directory rather than being represented as passing runs.

The single local HTML report contains 103 captures, including all planned
baseline/proposed pairs, and measures 2,896,993 bytes:
`~/.local/share/ui-reports/tsk/integrate-spec-53/20261022T135500Z.html`.
At 390 × 844, all 103 images decoded, no horizontal overflow occurred, pairs
remained adjacent in one column, and enlargement, scrolling and click-to-close
worked. Original screenshots, result bundles and logs remain in
`/tmp/tsk-spec53-evidence`. Sync progress passed runtime assertions but has no
matched screenshot attachments. New sidebar/Views interfaces have proposed-only
captures alongside surrounding baseline/proposed workspaces.

Only the unblocked #55 slice of #53 is included. #56–#58 remain blocked on
unmerged #44/#45; their main canvas, inline capture and edit-navigation behavior
is not claimed by the existing task-detail and capture-sheet evidence.

Local injected Cmd-Return did not reach the editor save handler on either the
untouched `a632410` baseline or the proposed app. Cmd-N opened capture. Canonical
CI HID results are separate acceptance evidence. Physical keyboard/touch,
VoiceOver, account services and distribution were not exercised. The local
simulator TaskChampion library was reused after confirming matching bridge
sources and lockfile; the fresh native build remains a CI check.
