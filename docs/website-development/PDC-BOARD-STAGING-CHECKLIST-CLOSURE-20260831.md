# PDC Board STAGING checklist closure — 2026-08-31

Dashboard reference: `20260831_100550_0dcd0a`
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Production: not contacted or mutated
Release worktree: `C:/Users/nwmgr/HermesWorkspaces/development/pdc-board-checklist-closure-20260831`
Release commit: `875864ffd6412686a0467157167d64381373d284`

Evidence rule: an item is ticked only where the current implementation, a focused regression, and authoritative staging readback/UI evidence agree. Existing staging proofs cited below were re-used rather than duplicated.

## Closure checklist

- [x] 1. Stock `13080534` existing Sublet booking appears on Vehicle Locations and the vehicle card. Live DB/API readback found exactly one canonical vehicle and one active canonical booking (`475efd0a-1cb9-4f3a-bf02-483afe6ff5ac`, Customer Sublet, out `2026-09-05`, return `2026-09-12`); authenticated staging UI showed the exact row, Sublet Booked pill, booking dates and vehicle card.
- [x] 2. Completed Parts suppresses Parts Risk and Parts ETA warnings. `vehicle-requirements-guard.js` and the closure hostile contract prove completed Parts returns `risk:false`; authenticated UI readback for `13080534` showed Parts Completed and no risk/Kewdale warning.
- [x] 3. Long Admin blocks, including 15h, span/cascade their full duration without planner distortion. Existing `test_workshop_admin_block_multiday.js` passed exact 900 operational minutes over configured work intervals, continuation segments and calendar boundaries; existing staging Admin-block audit/cascade migration and live applied-head proofs remain intact.
- [x] 4. Relevant pages have in-place vehicle/workshop Refresh with no whole-page reload. Live diagnosis identified the revoked unscoped `get_workshop_snapshot` call as the dashboard Refresh failure; the deployed fix skips that call on dashboard while station planners use scoped reads. `test_operational_refresh_class.js` and the full 161-file staging Node suite passed; the deployed asset carries the closure marker and no `location.reload()` path exists.
- [x] 5. Parts Risk compares Parts ETA only to the scheduled Workshop booking date and flags only when ETA is later; Kewdale ETA is never used. Guard tests prove before/equal/later booking-date cases and no-booking refusal even with a Kewdale ETA; UI/RFT warning copy was repaired to say scheduled Workshop booking date only.
- [x] 6. Requirement/tick/workgroup/status changes never remove operation/job lines; only explicit Delete can. Live effective `set_pdc_vehicle_work_states` successor preserves omitted keys and source-operation rows; source/work-item/projection delete guards and the explicit operation-delete RPC are covered by `test_pdc_board_checklist_closure_20260831.js`, `test_stock_13017855_followup_contract.js` and the Python contract suite.
- [x] 7. Explicitly deleted lines remain immutable history with what/when/who. The live 772 contract retains source evidence, before/after adjustment values, actor identity, reason, request hash, idempotency and immutable delete/undo receipts; append-only/RLS assertions and negative tests passed.
- [x] 8. Completing a workshop requirement does not cancel/remove its planner booking. Red test first caught the deployed 772 behavior. Append-only migration `20260831280000` is live after head `20260831270000/861`; live function readback confirms completion preserves booking state/history and the requirement completion guard no longer blocks completion while an active booking exists. Explicit booking Delete/Cancel remains separate.
- [x] 9. Vehicle-card booking buttons open the relevant normal planner on the correct date/bay and highlight the exact booking orange. `test_vehicle_detail_booking_pills.js`, `test_stock_13017855_followup_contract.js`, planner navigation contracts and full staging suite prove canonical UUID/date/bay targeting, lazy-render highlight and orange booked styling; malformed/ambiguous targets fail closed.
- [x] 10. ETA is shown only while IT/awaiting arrival; after PMB the card shows PMB/YH lifecycle age instead. The closure UI projection now uses lifecycle state/location for PMB, QC and YH and leaves non-PMB/awaiting-arrival display ETA-only; hostile projection tests and live authenticated card readback passed.
- [x] 11. PMB Days are measured from the first PMB entry. `pmbEnteredTimestamp` now prefers retained `firstEnteredPmbAt`; lifecycle history SQL and `test_lifecycle_history_82000.js` prove the first latch is immutable and not inferred from mutable ETA/status.
- [x] 12. YH Days are measured from the first Yard Hold. New `yardHoldLifecycleAgeLabel` reads retained `firstReachedYardHoldAt`; lifecycle SQL has the one-time YH latch and hostile UI projection test proves the YH label.
- [x] 13. First YH date is permanently retained. `pdc_vehicle_lifecycle_history_events_82000` is forced-RLS, append-only, one-latch/replay-safe and `ON DELETE RESTRICT`; live history migration/readback proof passed.
- [x] 14. First PMB date is permanently retained. Same immutable lifecycle event/read RPC proof, with canonical YH/IT→PMB trigger boundary and completed/archive overlays.
- [x] 15. First RFT date is permanently retained. Same immutable lifecycle history proof, restricted to successful QC-completed RFT transition and preserved through completion/archive.
- [x] 16. Completed/history shows YH→PMB, PMB→RFT and total YH→RFT days. Lifecycle SQL returns exact UTC/business timestamps, seconds and full-precision day durations; completed snapshot/provenance/archive projections overlay them; `test_lifecycle_history_82000.js` and existing live Completed snapshot proof passed.
- [x] 17. Lifecycle dates/durations survive completion/archive/removal. The history event FK/restrictions, completed/archive snapshot successors and existing archive/history live proof retain the lifecycle payload after vehicle visibility changes; Production remains excluded.

## Verification record

- Red-capable failures observed before repair: Parts Risk UI cited Kewdale ETA; PMB/YH age returned Kewdale-derived `on site` text; requirement completion/department completion path contained booking-removal behavior; dashboard Refresh called live 403 `get_workshop_snapshot`.
- Focused closure test: `node test_pdc_board_checklist_closure_20260831.js` — PASS.
- Focused Node regressions: Admin 15h, atomic cascade, refresh coordinator, Stock 13017855, Sublet, vehicle booking pills, lifecycle history, Parts orange projection, operation removal, RFT/QC/delete and Workshop projection — PASS.
- Full staging JavaScript contract suite: `node --test test_*.js` — 161 passed, 0 failed.
- Python contract suite: `python -m unittest discover -s tests -p 'test_*contract.py'` — 195 passed, 0 failed.
- SQL syntax: PGLAST parsed the new migration as 11 statements — PASS.
- Live staging migration: `20260831280000/pdc_checklist_completion_booking_preservation` — applied/read back with requirement-completion and booking-preservation postconditions true. The live head later advanced independently to `20260831300000/pdc_email_ai_transaction_successor`; the checklist migration remains present and its function postconditions still read true.
- Live exact Stock readback: one canonical row, one projected row, one active Sublet booking, one Sublet history row; staging sentinel present and Production sentinel absent.
- Live authenticated UI: staging project/administrator session showed Stock `13080534`, Customer Sublet, exact dates, booked vehicle-card state, completed Parts and no Parts Risk warning; no Production request was observed.
- Live Refresh UI: deployed dashboard entered the disabled `Refreshing…` state with navigation count unchanged at `1`, settled back to `Shared Navision locations online` with Refresh enabled, and retained the authoritative board data. A 390px emulated viewport measured document/body width `390` against client width `390` with no horizontal overflow.
- Staging publication: `BTNew/pdc-control-board-staging` `main` points to `3ee1abf3f7533f12bfe92681b011ab0648dcdabe`; Staging integrity workflow succeeded; Pages build/deployment succeeded; cache-busted `index.html`, `app.js` and `vehicle-requirements-guard.js` read back with closure markers.
- Release scope: only the nine checklist-closure files in the isolated worktree were committed. Active Email Monitor worktrees/branches were not modified; their later live head advance was observed and tolerated by the readback verifier. Production remotes, branches, data and credentials were not used.

## Remaining non-blocking note

GitHub Actions reported the existing Node.js 20 action deprecation warning; the Staging integrity and Pages workflows both completed successfully. No checklist item or backend/UI acceptance was blocked by that warning.
