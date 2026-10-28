# PR61 diagnostic command-inspection comparison

This disposable branch tests whether synchronous command inspection in
`TaskKeyboardRouter.diagnosticReturnCommands` contributes to the observed
post-delete animation-idle stall. It is not canonical coverage or an app fix.

One build runs the unchanged independent native control and complete durable
row journey. Control enables diagnostic inspection. Treatment omits only the
diagnostic `keyCommands`, `canPerformAction` and `target(forAction:)` queries.
Responder capture/traversal, notification observers, recording, registration,
actual input, assertions, ownership and deadlines stay identical. Omitted
runtime observations are null and explicitly marked `not-inspected`.

Treatment starts once only if control fails, the independent native control
passed, inspection was confirmed, and the console reproduces an animation-idle
timeout before space insertion after title deletion. Otherwise stop as
inconclusive. A menu miss does not admit treatment. There are no retries or
automatic follow-on experiments.

Treatment supports a candidate only with two complete public XCTest passes,
confirmed omitted inspection and no animation-idle timeouts. Otherwise the
hypothesis is unsupported. The workflow remains unsuccessful because control
failed; inspect `decision.json` and each arm's original results. Neither a
favorable pair nor incomplete bundles establish canonical acceptance.

Both arms use fresh owned devices of the same type/runtime on one runner and
reuse build products and fixture prerequisites. The existing 600-second method,
12-second request, five-second dispatch, 45-minute execution and 60-minute job
limits remain. Final publication still requires an untraced candidate passing
canonical smoke and full coverage on both families.
