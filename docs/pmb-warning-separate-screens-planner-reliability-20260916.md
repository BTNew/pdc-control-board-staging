# PMB release caution, separate staff screens and planner reliability

Date: 16 September 2026

## User-facing changes

- Releasing a vehicle to PMB warns when required Parts are incomplete. The warning covers single and bulk Yard Hold release, manual vehicle-card location changes and location overrides. Cancelling leaves the vehicle unchanged. The controller can confirm an intentional release.
- Fitters Bay and QC remain separate screens with separate navigation. Opening QC as a fitter-only user now lands on a visible Fitters screen. Hidden QC refreshes no longer repaint or fetch behind Fitters Bay.
- Planner actions wait for the current shared snapshot without repeatedly requesting another read. A confirmed save waits for its post-save readback before normal success is shown.
- Duplicate or conflicting actions for the same booking are blocked while its current action finishes. Start, stoppage, resume, completion, moves and resizing share this protection; actions on different bookings remain independent.
- Confirmed saves with a failed refresh are reported as saved and awaiting refresh. Network outcomes that cannot be confirmed ask the user to refresh, rather than incorrectly saying no update was saved. Mutations are never automatically retried.
- The timeline minute update works when dialogs are hidden. Visible dialogs, editing, dragging and resizing remain protected from disruptive redraws, and hidden pages avoid unnecessary clock work.

## Parts data correction

The warning uses required/received Parts data, not the colour of the imported-parts pill. Explicit current receipt values override stale legacy fields. Reconciliation also clears stale not-required projections when the latest snapshot no longer supplies one.

## Verification

- Full integrated local suite: 1,001 tests passed, zero failed or skipped.
- Changed JavaScript passed syntax checks; all 53 local script/style assets referenced by the entry page were present.
- Independent reviews covered Parts state reconciliation, route separation, mutation ownership, refresh barriers, authority changes and failed readback.
- Deferred-response tests cover revision bursts, bounded snapshot waits, logout/session and role changes, teardown, late responses and confirmed writes whose readback fails.
- A synthetic reproduction with 250 ms snapshot reads changed from 2,180 ms, ten reads and a blocked action to 503 ms, three reads and a successful action. This is a controlled reproduction, not a whole-site speed benchmark.

## Scope

This is a frontend update. It makes no database migration or live booking/time changes. Workshop hours and scheduling rules are unchanged. Email delivery and the proposed QC/RFT destination notification sequence are unchanged pending the user's workflow and delivery choices. No emails were sent. Physical iPad testing and a manual inspection of every live page are not claimed by these automated results.
