# QC-only phone interface — 9 September 2026

Craig authorised publication of the mobile QC interface to the existing STAGING website. No Production release or database migration is part of this change.

## Delivered behaviour

The canonical entry loads versioned `pdc-qc-mobile.js` and `pdc-qc-mobile.css`. On phone-sized viewports the existing authenticated website opens directly to a full-width QC queue without the desktop sidebar. The desktop interface is retained. OAuth and password-recovery fragments are not overwritten and the sign-in gate is not bypassed.

A vehicle opens a touch-sized checklist with progress. Each operation has a Not fitted action. Confirmation names the item in the rejection reason and invokes the existing protected QC-to-PMB-stoppage action. An already-checked missing item is first unchecked through the existing versioned checkbox writer; if the rejection step fails, the interface reports failure and does not sign off or move to RFT. Cancellation makes no change.

The photo input lives outside the rerendered host so a foreground refresh cannot replace an open camera/library picker. Upload status, preview, accepted receipt and retry states are explicit. Photo metadata is retained in sessionStorage for the same actor/vehicle/cycle for up to eight hours; image bytes and credentials are not stored there. Finalisation remains server-validated and requires all eligible checklist operations and an accepted photo receipt.

## Verification before publication

- Recovered mobile JavaScript and entry script matched the prepared Git blobs exactly (`0b3e78d057f79c466b44afcaa0e4a88aa0977730` and `39ee9c894374518335885a25557e1eb896ed328d`).
- Local deployed-base regression run plus six new entry/layout contract tests: 218 PASS, zero failures. The repository CI additionally includes the four Pilbara QC tests merged in PR #66.
- Seven in-memory Chromium browser scenarios passed at 360, 390, 768 and 1440 pixel widths: QC-only queue, tap-to-open checklist, checkbox receipt application, rejection cancellation, saved missing-item rejection, stable photo input across refresh, failed/invalid upload denial, retry success, sign-off gating and unchanged desktop layout. Scenarios use simulated backend responses and synthetic vehicle identity only.
- No real vehicle was checked, rejected or signed off. No actual completion photo was uploaded. Physical iPhone camera/library plus authenticated live upload verification remains a staff-device check, not a claim made by the automated tests.

## Release scope and rollback

Frontend presentation only: no database, credentials, mailbox, outbound email, scheduler or Production mutation. Existing Supabase role, version, evidence, photo and QC-finalisation checks remain authoritative. Revert this PR to restore the previous entry/layout; retained business records and existing QC receipts remain untouched.
