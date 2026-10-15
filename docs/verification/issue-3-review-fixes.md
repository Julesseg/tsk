# Final review fixes for issue3

The review batch addresses the accepted two standards findings, three spec
findings and the28 failures in canonical CI run38667195875 at851c2169.
That run predates Share, Widget, Spotlight, Calendar and notification runtime
coverage. Its failures are historical evidence, not results for this batch.

## Core and native behavior

- Series transition defaults and selected-date-to-offset conversion now use
  `TaskSeriesTransitionDefaults` and `TaskSeriesOffsetChange.setting`. Portable
  public tests cover future unfinished selection, unrelated/completed/overdue
  exclusions, template offsets, fallback dates and invalid offsets. Atomic
  preview/apply and external generation remain unchanged.
- Native notification, Spotlight and continuous-import stores use one
  cancellable lease acquisition helper. Each retains its own lock filename and
  release scope. Existing process/concurrency/cancellation tests remain intact.
- Accepted finite numeric UDAs beyond Float range can be filtered. The pinned
  client narrows stored numeric values to Float, including infinity/underflow,
  while operands retain their existing types. Modifier, direct and computed
  paths preserve that contract. Isolated Taskwarrior3.5 and native/Core tests
  cover1e100/-1e100/1e-100 and finite precision boundaries16777217/1.00000001.
  Eight-digit bare operands retain UUID/text precedence;16777216.0 explicitly
  selects the numeric interpretation. Urgency and duration contracts are intact.
- EventKit expands derived start fields on an owned unsaved reminder while
  leaving those fields absent from an equivalent due date. Structural component
  equality therefore rejects equal anchors. Core now builds Gregorian09:00GMT
  anchors from primary fields and validates every supplied derived field against
  that date. Contradictory weekdays/week numbers/quarters remain rejected, as do
  unsafe recurrence selectors, interval/end/source rules and independent dates.
  Actual unsaved EventKit getters plus public native import/reopen pass without
  authorization or calendar access. Stored iOS copy/move and source-history
  preservation still need the canonical disposable fixture run. Its JSON now
  includes all component/calendar fields, structural equality and guard results.

## Native interactions and keyboard routing

Keyboard declarations are installed on the owning controller of each active
SwiftUI scope, including modal presentations. Availability no longer assumes
that the sender is a UIKeyCommand; execution validates router, command identity,
input and modifiers. Workspace first-responder setup preserves focused text
input. This follows Apple's [sender contract](https://developer.apple.com/documentation/uikit/uiresponder/canperformaction(_:withsender:))
and [responder-chain command contract](https://developer.apple.com/documentation/uikit/uiresponder/keycommands).
These source fixes do not establish a simulator or physical-keyboard pass.

The CI interaction fixes use stable row/status/template identities, compact
navigation, explicit text focus and verified complete replacement. Membership
assertions wait for the editor to dismiss. Control activation checks actual
visible frames and native hittability; scrolling uses bounded drags within the
presented form's viewport. Failure attachments retain geometry/hierarchy and a
real screenshot. Existing assertions, deadlines and all19 iPad classes remain.

Continuous-import status, pause and result summaries remain visible while the
form scrolls. Disposable fixtures read persisted Core pause/configuration and
retain the controller outcome/error in JSON; permission/lifecycle failures are
not classified as success. Scoped keyboard JSON records declarations, host
controllers, responder chains, availability and dispatch. Both JSON families
join the existing cleanup-time harvest. Share-first execution, both result
bundles, real-server/peer verification and signing gates are preserved.

## Verification boundary

Core152 and full Native109 tests across4 suites pass on the review source with
the matching #31 bridge and a fresh isolated encrypted server. The pinned
80-query computed/urgency suite, clock regression, recurrence/interoperability
and original5-second held-response gates pass. Signed arm64 generic App, Widget,
Share, source fixture and XCUITest compilation passes; embedded entitlements,
intent/widget/share metadata and deep strict codesign verification pass.

No local simulator was booted. Canonical iPhone/iPad execution must verify
workspace CmdN, modal CmdReturn, stored recurring Reminders conversion/history,
all28 historical paths and the newer system integrations. There is no new
physical-input, personal-account, Focus/background delivery or distribution
provisioning claim. The distribution profiles still need their real capabilities;
required entitlements and release gates remain enabled.
