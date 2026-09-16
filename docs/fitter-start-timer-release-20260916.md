# Fitter Start confirmation and work timer

Fitter Start now confirms the canonical booking status and actual start used by both workshop planner views. The selected job shows Starting while saving, Running with an elapsed work timer after confirmation, and Paused during stoppage or outside workshop hours. Pending and uncertain saves retain the currently displayed time; retries reuse the original request and cannot start a job twice.

The timer counts workshop opening time and excludes recorded stoppages, nights, weekends and configured breaks. Older bookings without complete stoppage history are labelled approximate. The screen updates the clock without rebuilding the job list, and requires fresh server timing before continuing after a stale connection.

A blocked start identifies the other department, bay, planned/running/stopped state and Perth time. Existing booking order and the one-hour vehicle handover remain enforced. Starting a later planned station ahead of an earlier unstarted station remains blocked; this release does not silently reorder that work.

Visible station planners check only the authenticated stage revision every ten seconds, repairing missed live events. Unchanged revisions fetch no bookings and cause no repaint. Confirmed fitter saves invalidate open boards and same-origin tabs; recipients read fresh data under their own permissions. Slim planner pills explicitly show Running or Stopped without increasing their height.

## Verification

- 873 JavaScript regression tests passed across 293 files.
- 35 database rollback checks cover Start, fresh station/all-bay reads, revisions, idempotency, stale versions, assignment guards, seconds precision, overnight stoppage, closed periods and break boundaries.
- The installed migration passed a further 16 confirmation checks. All synthetic data rolled back; existing operational vehicles and bookings were unchanged by these tests.
- Desktop and 390px phone browser checks covered pending Start, running clock, pause, resume, lost-response retry and layout fit.
- Security advisor findings unchanged from baseline (978 findings; no additions).

Applied staging migration: `20260916012807_fitter_start_confirmation_and_work_timer`. Frontend fitter cache version: `2026.09.16.03`.
