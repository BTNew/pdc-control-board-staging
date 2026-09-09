# New Vehicle Job Card review — STAGING, 9 September 2026

## Workflow
AI Intake and AI Auditor move beneath the existing Admin disclosure. This changes navigation only, not their account/role permissions. A New Vehicles entry shows the current pending count. Open a new report vehicle, move operation tiles between stations (or use accessible dropdowns), then **Approve & add to board**. This commits the station assignments together and exposes the same canonical vehicle in Vehicle Locations. It does not create a dated bay booking or assert physical work, QC, collection or email delivery.

Newly retained Revolution/Pilbara report operations on a new canonical vehicle create one pending review per vehicle. Sibling lines share that entry; repeated report rows do not create duplicate review vehicles. Existing board, QC, workshop and source-backed vehicles were grandfathered (21 review metadata records); they were not hidden, moved or reset. A new Job Card on an already-operational vehicle stays on that existing vehicle rather than pulling it back out of production.

## Source/integration boundary
The capture hook runs on successfully retained `pdc_pilbara_service_operations` INSERTs. It does not ingest an XLSX/CSV file, read a mailbox, or bypass report preview/quarantine. The current deployed `pdc_pilbara_service_preview_v1` / `apply_v1` import functions are pinned to one previously authorised report/hash, row counts and old schema heads. They are **not** a commissioned general-purpose recurring Revolution uploader. Those source restrictions were deliberately not removed. The next real report and its importer contract must be checked separately. End-to-end parsing/import of a new real report was **not** tested in this change.

## Database behaviour
- Pending rows remain in backend inventory; canonical `visible_on_board` stays false until approval. Navision's board-activated display also excludes pending reviews, while backend retention/data are untouched.
- New scheduling and QC-entry checks reject pending reviews. Existing vehicle/version, ETA and overlap rules remain.
- The queue has no direct authenticated/anonymous table grants. Approved staff list it through a paginated RPC; only approved Operators/Administrators may approve. No credentials/grants were broadened on old endpoints.
- Approval checks the current source snapshot hash and complete, unique line-identity/station assignment set. Missing hours remain missing; explicit zero stays zero. A changed source must be re-reviewed.
- The existing source-stage move RPC is reused, with its pending-review exception allowing station choice before departments have started. Source IDs, descriptions, hours and completion state are read back. Source rows are never overwritten.
- The whole approval is transactional. Failed assignments cannot partially release the vehicle. Repeat requests with the same actor/key/payload reuse the saved response; other repeat approvals are rejected. Audit history records the approval.
- Cancel/back in the UI makes no assignments or release writes. A successful approval refreshes both Board and Navision display and opens Vehicle Locations.

## Verification performed
- Local full Node suite: **264 passed**, including 8 new intake tests.
- In-memory Chromium: 8 checks for Admin relocation, queue/list, click-through, required station selection, drag/drop, no pre-approval write, failure preserving choices, idempotent retry and return to Vehicle Locations. Source/RPC responses and (where unavailable in the blank page) UUID generation were simulated. No authenticated user browser was operated.
- Actual STAGING database test using a wholly synthetic report row/batch/vehicle in a rollback-only transaction: insertion queued one vehicle/two operations; visibility guard prevented early exposure; queue read returned source lines; stale/incomplete plans and Viewer approval were denied; approval reused the existing stage-move action, retained 0.00 and 0.75 hours and kept the original location; retry reused the receipt; no booking or QC completion was created. Deferred constraints were checked before rollback. Customer vehicle hashes were unchanged after rollback.
- Both dealer Navision display reads and the Board snapshot still succeeded. Queue count after tests: **0**. Existing vehicles were not reseeded as new work.
- An initial approval test exposed an ambiguous PL/pgSQL `email` variable; the separate actor-binding migration fixed it, and the full database test then passed.

## Applied SQL / deployment
`20260909100949_new_vehicle_report_review_gate_20260909.sql` contains the applied review-gate DDL; `new_vehicle_approval_actor_binding_20260909.sql` contains the applied follow-up qualification fix. Deployment requires successful exact-head staging CI. Production, mailbox, outbound email, credentials and schedulers were not changed.

Rollback after new reviews exist must preserve pending/approved records and audit history. Reverting the UI loader alone does not release pending vehicles; do not silently drop their approval gate.
