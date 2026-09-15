# Tune status 99 must pass through QC

A successful Tune import with Sub Status 99 previously moved a vehicle directly to RFT without a QC sign-off and marked the per-operation QC checklist complete. The mobile QC queue correctly requires the canonical QC location, so those vehicles disappeared from the phone. The RFT summary also omits operation cards, making the work appear lost.

Sub Status 99 now records workshop completion and moves the vehicle to QC. It retains the operation descriptions, hours and identifiers, while leaving inspection checks for staff. Final QC still requires the existing checklist, photo and protected sign-off process. A Tune receipt alone cannot authorize RFT.

Repeated imports cannot reset staff inspection checks, reopen signed-off RFT vehicles or override QC rejection/rework. Source Status remains separate from Sub Status: Status 99 alone does not trigger this flow. Imported work completion continues to close the active workshop bookings and associated parts/Sublet queues without inventing actual labour times.

The Vehicle Locations merge now retains location from a validated operational snapshot when the separate Navision reader has an older location. Navision source status and ETA still refresh normally. Legacy rows and identity-conflict restrictions retain their existing behavior. Eight regression scenarios cover QC, rework, genuine RFT, collection, completion, invalid snapshots and ambiguous identity matches.

The repair is restricted to the four affected vehicles and their recorded checkout receipts. It restores only unchanged automatic inspection writes, retains subsequent staff changes and keeps correction history. False RFT milestones are corrected; missing arrival dates remain unknown.

The operation source records were not deleted:

| Stock | Retained operations |
| --- | ---: |
| 13047384 | 22 |
| 13070060 | 23 |
| IS50969833 | 29 |
| IS60271021 | 13 |

Mobile regression coverage exercises the existing shared queue, real snapshot mapper, inspection rendering, versioned save handling, photo/sign-off gates and stale-action restrictions. Database verification uses transactions that roll back its test records.

Applied to the existing staging project with migration name `tune_checkout_requires_qc` and database version `20260915063323`. The CLI-generated source file is `supabase/migrations/20260915061903_tune_checkout_requires_qc.sql`, SHA-256 `16d449f7980f41194a5d9447dd8e12074f1b026bce05d22e36dbb56f0b0c1daa`. All 43 database assertions passed after application. Exact operation-source, work-item and booking fingerprints remained unchanged. A rollback test confirmed that a later staff inspection edit is retained by the repair.
