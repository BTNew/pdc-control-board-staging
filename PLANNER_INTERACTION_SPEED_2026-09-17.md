# Planner interaction performance — 17 September 2026

Dragging, resizing and post-move refreshes did more work than necessary. This release batches pointer previews to animation frames, reuses render-local calculations and avoids downloading a station snapshot again when the successful readback already contains its realtime revision.

Final release coordinates are resolved synchronously. Mandatory reads issued after a saved command, newer or unknown revisions, permission failures, server conflict checks and booking version checks remain in place. A delayed foreground network failure cannot disable a newer successful snapshot in the same session and scope. Permission failures and empty authorization results still invalidate access.

## Changes and measurements

- Daily/weekly dragging, touch previews and resizing update once per animation frame; unchanged snapped positions do not repaint. A synthetic 43-bay, 960-event test reduced geometry reads from 960 to 240 and preview writes from 2,880 to 720. These are operation counts, not measured browser frame rates.
- A simulated move followed by 29 realtime notifications already covered by its readback required one station download and one redraw notification instead of two. A genuinely newer revision still triggers another read.
- Focus and visibility return share an authenticated revision check. An unchanged station needs no full booking download.
- Rendering groups bookings once per bay. In a 13-bay/260-tile fixture, each date segment and time label is calculated once instead of twice; shared calendar and admin-block reads occur once instead of 13 times. Reuse ends after each render.
- The private database candidate-hours helper evaluates authoritative approved hours once per candidate. Four post-deployment Fitting comparisons measured 757–781 ms before and 260–262 ms after for 141 candidates, with exact complete JSON parity. These warm database timings exclude network and other snapshot work.

## Validation

- 1,099 automated JavaScript regression checks passed, including exact release coordinates, scrolling geometry, daily/weekly/touch movement, resize direction, cancellation, refresh races and permission invalidation.
- Browser check with synthetic data: moved a tile between bays, shortened it and extended it using actual planner handlers; saved destination, exact time, duration and expected version were verified. No real booking was moved.
- Exact old/new rendered HTML across 45 cases, including continuation, stoppage/live work, warnings, progress bars, missing vehicles and invalid bays.
- 28 database checks passed both before and after deployment: exact JSON across all seven departments, edge cases, private function access and unchanged business-row fingerprints.
- Security advisor results unchanged after the migration. No new API grants, indexes, server size or billing changes.

Applied staging migration: `20260917015048_planner_candidate_hours_once.sql`.
Browser asset marker: `planner-speed=2026.09.17.02`.

Initial full-board loading and network latency remain separate costs. Synthetic interaction checks do not claim a fixed percentage improvement for every browser or every action.
