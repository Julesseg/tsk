# Task row motion prototype — throwaway

Question: compare three spacing/anchor/curve strategies for the existing task list,
with tighter compact spacing and one simultaneous reveal/dimming clock.

Open `prototype.html` directly, or run from the repository root:

```sh
python3 -m http.server 8766 --directory App/Prototypes/task-row-motion
```

Then open `http://localhost:8766/prototype.html?variant=A` (also `B` and `C`).
The floating switcher and left/right keys select variants. Tap a task to toggle;
Replay plays the same open/close cycle. Quarter speed is for inspecting motion.

- A: fixed title, 12 pt upward nudge for earlier tasks, 180/140 ms ease-out.
- B: 10 pt title lift, more surrounding space, 240/180 ms restrained spring.
- C: hold the card center, 54 pt title travel, 220/160 ms ease-out.

All use 4 pt compact edge padding and simultaneous dimming/spacing/reveal.
Values near the top of the list clamp to keep the selected task visible.
The data is the task-row UI-test fixture; state is in memory. This sketch does
not verify SwiftUI List behavior, native glass/pickers or device frame pacing.

This native repository has no browser route, so the study lives next to `Tsk/`
in a standalone prototype folder. It is outside the Xcode synchronized target
groups and is not bundled with the app. Production source is unchanged. Keep
these variants out of the implementation PR; after the user's choice, capture
them on a throwaway branch and implement only the chosen behavior in SwiftUI.

## Verdict — 2026-10-25

The user chose A: “I prefer A I think”. This settles the spacing and motion
question in favor of a fixed title/checkbox, a 12-point upward nudge for earlier
tasks, 4-point compact edge padding and a shared 180/140 ms quartic ease-out
clock for reveal, surrounding space and dimming. B and C are retained only as
the alternatives the user compared. The native implementation belongs on PR
#61 for issue #41; this branch is an archive of the throwaway study.
