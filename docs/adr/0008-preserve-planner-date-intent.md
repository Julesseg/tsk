# Preserve planner date intent over Taskwarrior timestamps

Accepted design, 2026-11-15; implementation pending. Retain Taskwarrior's `scheduled` and `due` mappings from [ADR 0003](0003-share-taskwarrior-planning-and-deadline-fields.md), but let Scheduled alone control planner placement whenever present, using Deadline only as a fallback. This gives each unfinished task one actionable planner placement and respects an explicit scheduling choice even when its Deadline is overdue.

Scheduled distinguishes a day without a time from an explicit time, including midnight. Taskwarrior timestamps alone cannot retain that distinction, so add compatible task metadata rather than encoding manual order or untimed intent through artificial clock values. For existing or external values without that metadata, interpret midnight as untimed and other times as timed while preserving timestamps; the metadata format remains an implementation decision.

The [planner brief](../planner-redesign.md) supersedes ADR 0006's conflicting date display, Today/Upcoming, and notification rules. In particular, untimed Scheduled tasks have no individual Scheduled alert, while explicit midnight remains a valid timed alert. Accepting this legacy interpretation trades perfect recovery of past midnight intent for genuine untimed planning going forward.
