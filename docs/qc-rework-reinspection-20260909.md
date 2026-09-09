# QC rejection repair and fresh inspection — STAGING, 9 September 2026

## Requested behavior
The owner's QC.docx names Stock 13015144. Its bay screenshot also shows 13061263. A QC rejection must return the vehicle for only the unfinished/rejected work. Rebooking must not include previously accepted operations or their original labour estimate. After workshop completion, return to QC for all items to be checked again.

## Cause and repair
The planner summed all source operations. A vehicle-level QC rejection retained its stoppage even after its repair booking was marked complete. The one-photo-per-vehicle constraint also prevented a later inspection from recording fresh evidence.

One private read helper now projects the exact repair scope. New rejection receipts freeze the unchecked/rejected canonical line identities; older receipts use their existing unchecked canonical checklist, never guessed description matches. The original source estimates, adjustments, classifications and source descriptions are retained. A null estimate remains unknown and cannot fall back to the full original job. A genuine zero remains zero; a scheduling minimum is separately labelled.

The affected departments become incomplete on rejection. Existing booking create/start/complete actions remain authoritative. A return to QC requires all repair departments completed after the rejection, no active workshop booking, no unresolved Parts stoppage and no unrelated PMB stoppage. The existing audited QC-entry action clears only the exact matching rejection stoppage and resets previous QC ticks, preserving their before/after state in append-only completion history. It does not sign off physical work automatically.

The original photo records are unchanged. A new QC-entry movement ID identifies a fresh inspection, permitting one new photo receipt per attempt. The finalizers reject a photo receipt from the previous attempt. Browser photo receipt caches are invalidated only when they belong to a different inspection; in-flight uploads are not discarded.

The frontend module exposes **Return to QC** on eligible Fix First rows, shows only repair lines and their hours in the bay job card, and leaves normal first-build jobs unchanged. It loads after the existing phone QC renderer; existing authenticated actions remain the write authority.

## Verification actually performed
- Both reported vehicles retain their original version, PMB location and source/check history. The server now projects roof racks at **1.00 h** for 13015144 and nudge bar at **1.67 h** for 13061263. Their already-recorded workshop repair completions make them eligible for return; neither was moved by this repair.
- Synthetic rollback-only test: four exact unfinished lines across two departments; 2.50 h of accepted original work excluded; Fitting 1.50 h and Electrical 0.25 h, including explicit zero.
- Synthetic rollback-only test: incomplete and partially repaired work cannot return; completed repair can return; all five inspection lines become unchecked; previous completion history retained.
- Synthetic rollback-only test: old photo receipt rejected after QC return; new attempt receipt permitted without overwriting the old record; incomplete reinspection still prevents final sign-off. Storage metadata was a synthetic fixture, **not a real device upload**.
- Actual staging schedule/start/complete/return RPCs exercised on a synthetic fixture: **15-minute repair**, not its original 2.75-hour job. All fixture effects were rolled back. A first test correctly hit an occupied bay; the rerun selected a free bay without changing an existing allocation.
- Local Node suite: **247 passed**, including 13 new scope/render/cache regressions.
- In-memory Chromium renderer checks at 1440 px and 390 px: repair-only line and source hours, Return to QC event delegation, no JavaScript errors. Network was blocked and action results were stubbed. This is not authenticated live browser verification.

## Applied migrations and deployment
- `20260909075349_qc_rework_scope_and_reinspection_20260909.sql`
- `20260909080308_qc_reinspection_movement_ordering_20260909.sql`
- `20260909080622_qc_rework_exact_booking_minutes_20260909.sql`

The stored migration text hashes match these files (byte-for-byte). No authenticated/anonymous execute grant was added for the private helper. Production, mailbox, outgoing email, credentials and scheduler were not changed.

## Release / rollback
Require successful exact-head staging CI before merge. To stop the new presentation, revert the frontend loader/module commit. Do not undo the photo-attempt uniqueness or drop its key after new photos have been saved: that would lose the ability to preserve multiple inspection histories. Database rollback after use requires a reviewed forward correction, not deletion of receipts or history.
