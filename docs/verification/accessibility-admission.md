# Accessibility admission in UI tests

The UI helper permits 20 seconds for accessibility reads to establish that a
control is enabled, hittable, and contained in its app window. This is a finite
test infrastructure budget, not an app response-time requirement. An earlier
caller deadline still takes precedence, and an attempt dispatches at most once
and never after its deadline.

The previous five-second aggregate cutoff rejected ready controls after observed
accessibility samples of 6.259, 8.749, and 11.964 seconds. Each native read is
synchronous, so that cutoff did not interrupt slow reads; it discarded their
valid results afterward. The named budget also covers the automatic-sync test's
independent capture admission checks. It can make a missing control take longer
to fail. Save, persistence, membership, relaunch, and system integration outcome
assertions retain their existing timeouts. The two-second production notification
authorization bound is separate and unchanged.

Controlled-clock regressions exercise those observed sample durations, the
20-second boundary, earlier caller deadlines, and single dispatch. The iPad
interaction corrections use the existing checked coordinate helper: native taps
had closed the filter editor, left Save undelivered, or produced a definition
named `scoreo`. Exact input and saved-definition readback now fail at setup
instead of searching indefinitely for the requested `score` control.
