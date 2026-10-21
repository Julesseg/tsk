# Throwaway Calendar prototypes for issue #39

Open `CalendarStripPrototype.html` directly in a browser. `CalendarTimelinePrototype.html` preserves the earlier exploration. Both are browser illustrations with controlled data, not native app evidence.

Question: how can Calendar occupy less visual space above Today tasks while keeping complete event titles visible?

User verdict: “I like the day overview.” Variant D in the strip prototype was selected, with the bottom explanatory line removed. The follow-up requests add configurable start and end hours in Settings and colors from the corresponding calendars in the Calendar app.

Production implementation is rewritten in SwiftUI and TskCore in PR #52. This branch preserves the prototype as a primary source and must not merge into main.
