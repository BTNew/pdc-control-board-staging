# Shared Files

## PDC Email AI v2 exact sender enrollment — 2026-09-02

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260902261000_pdc_email_ai_v2_karratha_toyota_sender_enrollment_20260902.sql` | Serialized STAGING authority/remediation lane | Exact SHA-256 enrollment for retained UID `1:709`; immutable predecessor/table-state hash history; no domain-wide trust or operational dispatch | Protected STAGING apply/readback passed; exact unapproved-sender negative, ACL, forced-RLS and rollback probes passed. Parent domain-allowlist repair remains separate. |
| `scripts/apply_pdc_email_ai_v2_karratha_toyota_sender_enrollment_staging.py`, `tests/test_pdc_email_ai_v2_karratha_toyota_sender_enrollment.py`, `review-evidence/v2-controlled/karratha-toyota-sender-enrollment-apply-proof.json` | STAGING installation/proof | Hash-gated connector and authoritative enrollment read-back | Focused contract `4/4`, SQL parse `18`, Python compilation, `npm run test` `222/0/1`, and `npm run check` `222/0/1` passed. |

## Latest-100 attachment work-receipt compatibility successor — 2026-09-01

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260901010000_latest100_attachment_work_receipt_successor.sql` | Staging email monitor | Append-only attachment-scoped work receipt, legacy audit preservation, exact duplicate/conflict handling and bounded schema reload | STAGING head `20260901010000`; SHA-256 `7e2e7ad49045698b72780404d1e246f182bfc4f6d3945ec383ca1fd31d2b8cc3`; Production/mailbox/outbound untouched |
| `scripts/apply_latest100_attachment_work_successor_20260901.py`, `scripts/verify_latest100_attachment_work_successor_20260901.py` | Staging management | Exact staging guards, catalog/ACL/RLS readback and only UIDs 680/681 acceptance | Apply and live verifier passed |
| `tests/test_latest100_attachment_work_successor_20260901.py`, `tests/test_latest100_runner_response_contract_20260901.py` | Regression | Schema discovery, hostile identity, immutable audit, zero-add duplicate and direct/fallback contracts | Included in 22 focused assertions |
| `handoffs/PDC_EMAIL_LATEST100_TARGETED_RESUME_20260901_FINAL.json` | PDC email monitor | Hash-bound handoff containing only UIDs 680/681 | pdc-emails retains real import ownership; 43 excluded actions remain contained |

## Latest-100 targeted resume repair successors — 2026-09-01

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260831460000_latest100_resume_repair.sql`, `supabase/staging_only/20260831461000_latest100_force_rls_successor.sql` | Staging email monitor | Viewer capability versus exact sender enrollment, pre-310 capability propagation, deprecated auth-flag compatibility, one-row binding contract, capability-scoped AI Intake parent audit, forced RLS and immutable child receipts | Live STAGING head `20260831461000`; production/mailbox/outbound untouched |
| `scripts/apply_latest100_resume_repair_20260901.py`, `scripts/apply_latest100_force_rls_20260901.py` | Staging management | Exact project/head/hash/owner guards and catalog/readback postconditions; no service-role runtime | Both apply/readback controllers passed; credentials remain protected |
| `tests/test_latest100_resume_repair_20260901.py`, `tests/test_latest100_force_rls_20260901.py` | Staging regression | Hostile sender/spoof, authorization separation, invalid-input compatibility, migration-260 binding, multi-attachment sibling isolation, readback and RLS | Included in focused 18-test run; pdc-emails owns the real import handoff |
| `handoffs/PDC_EMAIL_LATEST100_TARGETED_RESUME_20260901.json` | PDC email monitor handoff | Hash-bound continuation containing only exact eligible UIDs 680/681 and their parent/attachment/provider/Navision evidence | Real imports remain owned by pdc-emails; all other 43 action records remain excluded |
| `docs/website-development/AUTONOMOUS-CHANGES-LOG.md` | Website management | Secret-free repair, verification and handoff record | Register only this targeted stream; preserve unrelated dirty work |

## Latest-100 email monitor capability and sender-chain repair — 2026-09-01

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260831450000_pdc_email_monitor_viewer_receipt_read_successor.sql` | Staging email monitor | Exact enrolled Viewer capability reaches the actor-owned receipt reader; attachment-scoped child receipt and immutable/RLS guards | `tests/test_pdc_email_monitor_viewer_receipt_read_20260901.py`; live staging ACL, typed receipt-not-found and negative importer probes |
| `tests/test_pdc_email_sender_chain_20260901.py`, `tests/test_pdc_latest100_resume_contract.py` | PDC email monitor | Gmail receiver/ARC alignment, spoof/duplicate rejection and exact UID/source-hash replay contract | Python focused suite; retained RFC822 header verification matched 32 inventory messages |
| `scripts/build_pdc_latest100_resume_manifest.py`, `handoffs/PDC_EMAIL_LATEST100_STAGING_RESUME_20260901.json` | PDC email monitor handoff | Exact UIDVALIDITY 1 / UID / source-hash frozen latest-100 resume manifest and worker commands | Generated 100-message manifest with 42 new-build messages; pdc-emails owns operational import |

## PDC Email canonical importer capability repair — 2026-08-31

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260831420000_pdc_email_canonical_import_capability.sql` | Staging email monitor | Exact `pmbcontroller+pdc-viewer-staging-20260830@gmail.com` capability for `import_pdc_jobcard_attachment_canonical`; no writer grant or direct table DML | Live staging capability/readback and disable-only rollback rehearsal |
| `supabase/staging_only/20260831430000_pdc_email_canonical_import_nested_context.sql`, `supabase/staging_only/20260831440000_pdc_email_canonical_import_activation_context.sql` | Staging email monitor | Transaction-local capability context through canonical activation helpers; direct helper execution remains denied | Live staging source/readback; existing canonical Stock/ambiguity/idempotency/lifecycle guards retained |
| `tests/test_pdc_email_canonical_import_capability_20260831.py`, `tests/test_pdc_email_canonical_nested_context_20260831.py` | Staging backend regression | Migration identity, exact ACL, forced-RLS, rollback, nested context and no-broadening contracts | Focused Python suite plus `npm run test` and `npm run check` |

## Sublet workgroup-only Vehicle Locations presentation — 2026-08-31

- `app.js`, `pdc-email-vehicle-location-service.js` — remove the duplicate `SUBLET Booked` vehicle/model badge, project the canonical active Sublet booking into the existing orange workgroup state, and derive active count from canonical rows without changing completed/returned/cancelled semantics.
- `index.html` — cache-busts the changed app and DTO service assets with `sublet-workgroup=2026.08.31.3300` and `sublet-canonical-count=2026.08.31.3300`.
- `test_sublet_projection_contract.js`, `test_sublet_workgroup_projection_20260831.js` — DOM/source regressions for exact Stock `13080534`, active/no-booking/cancelled/returned/completed Sublet states and Parts preservation.

## PDC Board checklist closure — 2026-08-31

- `app.js`, `index.html`, `deployment-identity.json` — PMB/YH lifecycle-age display now uses retained first-transition history, Parts Risk copy is explicitly based on the scheduled Workshop booking date, dashboard Refresh avoids the revoked unscoped Workshop RPC, and staging assets carry the closure cache marker.
- `supabase/staging_only/20260831280000_pdc_checklist_completion_booking_preservation.sql` — append-only staging successor after live 861. Completing a requirement no longer conflicts with or removes an active planner booking; the Administrator department-completion path preserves the booking while retaining explicit Delete/Cancel controls.
- `supabase/staging_only/20260831310000_pdc_checklist_completion_history_preservation.sql` — append-only successor after the independent live 3000 head; preserved booking history records `purged_booking_id NULL` and retains the completion function's lock/idempotency/security identity.
- `scripts/apply_migration_2800_staging.py`, `scripts/apply_migration_3100_staging.py`, `scripts/verify_pdc_board_checklist_live_20260831.py` — secure staging installers and authoritative exact Stock `13080534` DB/API readback with staging/Production sentinel checks.
- `test_pdc_board_checklist_closure_20260831.js` — hostile requirement/booking/risk/lifecycle/refresh/navigation regression contract.

## Workshop Admin-block audit successor after 771 collision — 2026-08-30

- `workshop-data-service.js`, `app.js`, `index.html` — successor RPC binding and cache-busted Workshop module assets.
- `supabase/staging_only/20260830100000_771_workshop_admin_block_audit_projection_successor.sql` — append-only current-head successor with server-derived dealer scope, exact station/bay/date filtering, persisted interval/version, configured calendar, continuation windows, revisions, planned bookings and immutable cascade/history/receipt evidence; no direct-table grants or mutation path.
- `test_workshop_admin_block_multiday.js`, `test_workshop_dedicated_clean_shell.js`, `test_workshop_timeline_duration_geometry.js` — successor RPC, dealer-scope and cache-marker contract coverage.

## Stock 13080534 canonical Sublet projection closure — 2026-08-30

- `app.js`, `pdc-email-vehicle-location-service.js` — canonical multi-provider Sublet requirement mapping, Vehicle Locations booking pill/detail, and exact authenticated ledger-read client bridge.
- `supabase/staging_only/20260830090000_sublet_auditor_read_ledger.sql`, `20260830091000_sublet_auditor_read_ledger_volatility_repair.sql`, `20260830092000_sublet_auditor_read_ledger_uuid_text_cast_repair.sql` — staging-only exact UUID/Stock/Job Card, dealer-scoped read RPC for Sublet instance/history/receipt ledgers, the append-only PostgreSQL `FOR SHARE` volatility repair, and the UUID/text-safe dealer-binding repair; direct table SELECT remains denied and no repair mutation is included.
- `scripts/apply_migration_900_staging.py`, `scripts/apply_migration_901_staging.py`, `scripts/apply_migration_902_staging.py` — shared-lock, exact-live-predecessor, sentinel and Production-blocked installers with post-apply catalog/ACL proof.
- `test_sublet_projection.js`, `test_sublet_projection_contract.js`, `test_sublet_audit_read_service.js` — active/returned/cancelled-only mapper regression and SQL/service/card boundary contracts.

## Workshop Admin-block calendar continuation audit 771 — 2026-08-30

- `workshop-planner.js`, `workshop-planner.css` — configured-calendar daily/weekly Admin-block continuation projection, explicit total/continuation labels, and wrapped compact planner controls.
- `workshop-data-service.js` — authenticated Operator/Administrator bridge for the narrow `get_workshop_admin_block_audit_771_successor` read RPC; no direct-table fallback.
- `supabase/staging_only/20260830073000_771_workshop_admin_block_audit_projection.sql` — exact-head-guarded staging read projection for persisted Admin-block rows, calendar windows, revisions, planned cascade evidence, immutable history and receipts; no mutation or generic table grants.
- `index.html`, `app.js` — related cache-busted Planner/module asset loading; `test_workshop_admin_block_multiday.js` and cache-marker assertions cover continuation, breaks/closures, exact totals, replay/cascade contract markers and responsive wrapping.

## Navision preflight and SQLSTATE 23514 repair — 2026-08-30

- `app.js` — client-side deterministic candidate preflight, Stock/field/reason preview labels, actionable domain-error translation and preserved no-localStorage shared apply path.
- `supabase/staging_only/20260830072000_navision_import_preflight_contract.sql` — server-side duplicate identity/status/date/location classification and parity-safe linked-source projection refresh; atomic apply, RLS and existing constraint trigger remain authoritative.
- `test_navision_import_preflight_768.js`, `tests/test_navision_import_preflight_769_contract.py` — exact Stock `13080534` duplicate fixture, invalid field, wrong dealer, valid sibling, atomic, replay, security and browser-local authority regressions.

## Sublet Calendar Month clean-session default — 2026-08-30

- `app.js`, `index.html` — Calendar → Month clean-session defaults and matching initial control state; existing explicit view controls and authoritative booking/calendar render paths are unchanged.
- `test_sublet_calendar_default.js` — default, direct-navigation, clean refresh/session, explicit switching, current-month, authoritative event and unrelated-route regression contract.

## Atomic Job Card hours batch editing 768 — 2026-08-30

- `app.js`, `pdc-email-vehicle-location-service.js`, `styles.css`, `index.html` — one modal-level Save all hours draft form, stable operation UUID payloads, stale-draft preservation, authoritative readback and Parts no-hour/no-booking presentation.
- `supabase/staging_only/20260830070000_768_vehicle_workshop_hours_batch.sql` — staging-only atomic authenticated RPC, immutable request receipts, exact identity/version validation, before/after audit evidence and one vehicle-version increment.
- `test_vehicle_workshop_hours_batch_768.js`, `test_vehicle_workshop_hours_batch_768_regression.js` — service, UI, identity, zero/null, Parts, replay/conflict, atomic rollback, version and loading-recovery contract coverage.

## Vehicle Locations slimline status bar — 2026-08-30

- `styles.css` — explicit desktop Grid placement for the title/status/Refresh row, reduced bar spacing, and mobile row reset without reducing the 42px touch target.
- `test_vehicle_locations_refresh_dom_click.js` — regression assertions for single-row desktop layout, compact height, mobile wrapping and existing click semantics.

## Vehicle Locations Refresh click-path repair — 2026-08-29

- `app.js`, `pdc-email-vehicle-location-service.js`, `vehicle-modal-identity.js`, `vehicle-locations-refresh.js` — collision-safe classic-script exports, one-time delegated click wiring, immediate busy/error handling and preserved authoritative refresh fan-in.
- `vehicle-locations-refresh-ui.js`, `index.html`, `styles.css` — staging-only DOM click controller, cache-busted script order and slimmer responsive green status bar.
- `test_vehicle_locations_refresh_dom_click.js`, `test_vehicle_modal_identity_recovery.js`, `test_vehicle_modal_save_rebind.js` — loaded-module DOM click, missing/auth failure, double-click, render replacement, cache and no-reload regressions.

## Durable authenticated Parts check-off successor 751 — 2026-08-29

- `supabase/staging_only/20260829144000_751_authenticated_parts_received_contract.sql` — append-only staging contract after the settled recovery 750 head; exact UUID + Stock + version + idempotency, Administrator/non-Administrator authorization split, Parts ETA invariant repair, receipt/audit/revision/version postconditions and forced-RLS immutable receipt history.
- `scripts/apply_migration_751_staging.py`, `scripts/run_parts_received_751_staging.py` — staging-only shared-lock installer and exact Stock `13017855` Administrator mutation/readback verifier with negative identity/version/idempotency/role/dealer/RLS/Production checks.
- `app.js`, `pdc-email-vehicle-location-service.js`, `index.html` — durable 751 RPC dispatch, Stock-bound request/receipt validation, actionable shared error messages and cache-busted staging assets; no local persistence fallback.
- `test_authenticated_parts_received_751.js`, `test_parts_shared_actions.js`, `test_parts_received_shared_identity.js`, `test_pdc_auditor_parts_received_738.js` — class-level source, HTTP/service body, canonical identity, replay and fail-closed UI regression coverage.

## Exact Parts controller correction 742/745 — 2026-08-28

- `supabase/staging_only/20260829090000_742_controller_parts_received_correction.sql` — one-time expiring Craig owner-instruction Administrator/controller authorization and exact target receipt/audit path; no persistent Auditor dealer grant.
- `supabase/staging_only/20260829120000_745_controller_parts_received_eta_repair.sql` — append-only successor preserving the authoritative Parts ETA required by the live trigger when no stoppage is active.
- `scripts/apply_migration_742_staging.py`, `scripts/apply_migration_745_staging.py` — serialized, shared-lock, exact-head, Production-blocked staging installers.
- `test_pdc_controller_parts_correction_742.js`, `test_pdc_controller_parts_correction_745.js` — owner instruction, target, expiry, consumption, immutable receipt, least-privilege and ETA repair source contracts.
- Live controller matrix — one exact receipt/audit and version increment; replay, wrong actor/vehicle/dealer/version and unrelated-digest checks passed; Production untouched.

## Exact Stock 13016925 Parts Auditor receipt successor 738 — 2026-08-28

- `supabase/staging_only/20260829050000_738_authenticated_parts_received_auditor_wrapper.sql` — staging-only exact-target authenticated Auditor receipt wrapper, immutable forced-RLS receipt history, scoped UUID/version/idempotency guards, Parts-only state transition, audit and shared-revision publication.
- `scripts/apply_migration_738_staging.py` — fail-closed staging installer; holds the shared migration advisory lock, re-reads the live head, blocks the known concurrent 736 worker/session, rejects Production, and records post-apply privilege/RLS proof.
- `app.js`, `pdc-email-vehicle-location-service.js` — authoritative Parts Received route now calls the 738 Auditor wrapper with canonical UUID/version/idempotency and duplicate-dispatch protection; no local persistence fallback.
- `test_pdc_auditor_parts_received_738.js`, `test_parts_shared_actions.js`, `test_parts_received_shared_identity.js` — wrapper security, negative-path, receipt/replay, exact payload and UI dispatch contracts.
- Live migration application is complete; the exact target mutation remains fail-closed until an approved active Auditor enrollment for authoritative dealer `37047` is available. Production remains untouched.

## Final authoritative RFT lifecycle 700-706 — 2026-08-27

- `app.js`, `pdc-email-vehicle-location-service.js`, `index.html`, `pdc-supabase-config.staging.js` — QC → RFT → Booked → Collected → Delivered UI/service wiring, Collected projection, final 700 RPC clients, and 706 cache-busted staging assets.
- `supabase/staging_only/20260827101000_700_authoritative_pdc_lifecycle.sql` through `20260827105000_704_delivery_wrapper_case_safe_normalization_repair.sql` — applied append-only final lifecycle and forward QC, Collected, and delivery-wrapper repairs; these files are preserved as applied history and are not re-applied.
- `supabase/staging_only/20260827107000_706_final_booked_synthetic_payload_identity_repair_after_673_collision.sql` — minimal successor consolidating the unapplied 705 draft after the live 20260827106000 ledger collision; switches only the synthetic identity predicate from dealer batch to bounded HERMES-TEST stock.
- `deployment-identity.json`, `test_final_authoritative_pdc_lifecycle_700.js`, `test_final_authoritative_pdc_lifecycle_706.js`, `test_acceptance_closure_contract.js`, `test_stoppage_rft_transport_412.js` and updated release-marker tests — lifecycle, collision, no-email/no-timer, Collected separation, security and cache-bust regression coverage.
- `scripts/manage_final_pdc_lifecycle_700_staging.py`, `scripts/manage_final_pdc_lifecycle_701_staging.py` — preserved staging management provenance for the original 700/701 chain; no production path.

## Parts Received canonical Navision identity repair — 2026-08-27

- `app.js` — shared Navision projection now retains the linked canonical vehicle UUID for Parts actions.
- `vehicle-lifecycle-actions.js` — lifecycle identity resolution accepts the shared Navision canonical UUID.
- `index.html`, `pdc-supabase-config.staging.js` — cache-busted changed app/config and lazy resolver assets.
- `test_parts_received_shared_identity.js` — canonical/Navision/email Parts Received identity and payload regression coverage.

## Synthetic containment drift repair — 2026-08-26

- `supabase/staging_only/20260826215000_436_current_containment_read_repair.sql` — append-only staging contract repair for current read containment and exact protected/notification/outbound synthetic write postconditions.
- `supabase/staging_only/20260826220000_437_registered_replay_containment_repair.sql` — append-only registered synthetic replay repair that removes the stale receipt-vs-current protected-state comparison while retaining current containment and exact write postconditions.
- `supabase/staging_only/20260826221000_438_acceptance_stale_fast_path.sql` — append-only registered acceptance stale-version fast rejection before the expensive containment lock path; normal writes retain exact protected/notification/outbound postconditions.
- `supabase/staging_only/20260826222000_439_acceptance_stale_before_binding.sql` — append-only stale-version rejection before registry binding/idempotency/containment work.
- `supabase/staging_only/20260826223000_440_acceptance_stale_nonretryable.sql` — append-only non-retryable SQLSTATE repair for the pre-binding stale branch; the locked authoritative concurrency check remains SQLSTATE 40001.
- `test_staging_containment_drift_repair_436.js` — migration, effective-function repair and protected-boundary regression coverage.
- `test_registered_replay_containment_repair_437.js` — registered replay containment and protected-boundary regression coverage.
- `test_acceptance_stale_fast_path_438.js`, `test_acceptance_stale_before_binding_439.js`, `test_acceptance_stale_nonretryable_440.js` — stale rejection ordering, non-retryable error, containment, ACL and protected-boundary regression coverage.
- `deployment-identity.json` — exact 440 staging migration provenance.

## Receipt-backed QC photo finalization and canonical Sublet provider writes — 2026-08-26

- `app.js` — QC receipt-backed photo upload/finalization flow, already-QC-completed-at-QC support, legacy QC action replacement, canonical Sublet booking identity routing, and modal open/close interaction hooks.
- `pdc-email-vehicle-location-service.js` — compressed photo upload/storage receipt client, atomic finalization client, QC finalization projection mapper, and exact booking UUID/version provider-reassignment client.
- `styles.css` — top vehicle-modal stacking context and temporary background Sublet native-select suppression while the modal is open.
- `index.html`, `deployment-identity.json` — cache-busted staging asset release identity and uncommissioned 399 migration provenance.
- `supabase/staging_only/20260826140000_399_qc_finalization_photo_rft_salesperson_outbox.sql` — additive staging candidate migration for private photo evidence, atomic QC/RFT/outbox receipts and canonical Sublet provider updates.
- `test_qc_finalization_399.js`, `test_sublet_canonical_provider_mutation_399.js`, `test_sublet_modal_layering.js`, plus updated QC contract tests — focused regression coverage.

## Canonical Workshop booking snapshot authority — 2026-08-25

- `supabase/staging_only/20260826130000_397_canonical_workshop_booking_snapshot_authority.sql` — exact-head-guarded staging-only projection wrapper overlaying canonical booking scheduling/live fields by stable UUID while preserving snapshot shape and mutation authority.
- `test_workshop_canonical_booking_snapshot_authority_397.js` — canonical geometry, protected read-only evidence, synthetic acceptance, fixed overlap/nearest slot, receipt/replay/undo, cascade/resize, bay isolation and zero-notification regression coverage.

## Owner-supplied Job Card intake authority — 2026-08-25

- `supabase/staging_only/20260826120000_396_owner_supplied_document_jobcard_intake.sql` — additive staging-only exact-owner/Task/Stock/Job Card contract, immutable document and operation evidence, unknown-hour review rows, idempotency, audit and undo RPCs; no provider-email or mailbox dependency.
- `test_owner_supplied_document_jobcard_396.js` — exact provenance, identity, 18-row 14-explicit/4-unknown hour model, zero-vs-null, ACL, forged-email rejection, side-effect and undo contract coverage.

## Receipt-first salesperson readback race repair — 2026-08-25

- `app.js` — receipt-first canonical UUID/version application, in-memory pending receipt overlay, bounded targeted authoritative readback, contradiction handling, and delayed-save status.
- `test_salesperson_readback_race.js` — focused receipt/readback race, stale/eventual/immediate/contradictory snapshot, poisoned-state, replay and combined-save regression coverage.

## Restore Mobile QC operation-line projection — 2026-08-25

- `app.js` — QC operation-line rendering now distinguishes a missing server projection and shows a precise loading message.
- `pdc-email-vehicle-location-service.js` — QC snapshot mapper preserves a projection-presence signal while remaining fail-closed on missing data.
- `index.html` — cache-busted staging references for the QC projection asset release.
- `supabase/staging_only/20260826110000_395_restore_qc_operation_projection.sql` — additive, exact-head-guarded snapshot wrapper preserving the existing contract and canonical QC 379 lines.
- `test_qc_operation_projection_395.js`, `test_qc_operation_completion_379.js` — migration and missing-projection regression coverage.

## Focused booking and future-only Workshop corrections — 2026-08-25

- `app.js` — focused vehicle-card booking entry, canonical Parts projection/focus, and raw-baseline lifecycle guard for shared detail saves.
- `workshop-planner.js` — focused canonical booking mode, exact operation-line display, source-line adjustment projection, no local shared assignments, and exact candidate pill model/hours.
- `workshop-data-service.js` — authoritative future-only recovery before trusted snapshots.
- `workshop-planner.css` — focused booking operation/error layout.
- `supabase/staging_only/20260826093000_393_future_only_workshop_recovery.sql` — staging-only future scheduling enforcement and recovery.
- `supabase/staging_only/20260826100000_394_admin_compaction_and_duration_bounds.sql` — staging-only exact multi-day Admin duration and now-forward compaction correction.
- `test_workshop_focused_booking.js`, `test_workshop_owner_corrections.js` — focused UI, projection, future-only and raw-baseline contract coverage.

## Atomic Admin block insertion and cascade — 2026-08-25

- `workshop-planner.js` — Admin drop request state, request-id dispatch, placed/cascaded summary, and fixed blocker/nearest-slot feedback.
- `workshop-shared-actions.js` — request-id metadata for the protected Admin creation RPC.
- `workshop-planner.css` — responsive pending/success/error feedback styling.
- `supabase/staging_only/20260826090000_392_workshop_admin_block_atomic_cascade.sql` — staging-only atomic cascade, idempotent receipt, fixed blocker/nearest-slot contract and revision publication.
- `test_admin_block_atomic_cascade.js` — migration, bridge and UI contract coverage.

## Authoritative Vehicle detail saves — 2026-08-25

- `app.js` — shared Vehicle detail Save orchestration, receipt-backed salesperson/detail RPC dispatch, authoritative reconciliation, and poisoned legacy consultant cleanup.
- `pdc-email-vehicle-location-service.js` — canonical snapshot mapping plus salesperson and allowlisted detail RPC clients.
- `index.html` — cache-busted staging asset references for the authoritative detail tranche.
- `supabase/staging_only/20260825230000_386_authoritative_salesperson_assignment.sql` through `20260825235000_391_detail_stale_receipt_repair.sql` — staging-only authoritative detail contracts, synthetic route containment, snapshot convergence, and stale receipt repair.
- `test_authoritative_salesperson_assignment_386.js`, `test_email_authoritative_board.js` — contract, RPC-body, and poisoned-local-storage negative coverage.

## Parts ordered authority closure — 2026-08-25

- `app.js` — shared Parts projection, queue rendering and mutation handlers; this change keeps canonical Parts requirement and viewer access fail-closed.
- `pdc-email-vehicle-location-service.js` — shared Parts RPC error normalization.
- `styles.css` — not changed by this task.
- `supabase/staging_only/20260825220000_385_parts_order_authority.sql` — append-only staging trigger correction for ordered Parts writes.

## Email Monitor .44 authenticated identity successor 672 — 2026-08-27

- `supabase/staging_only/20260827067200_672_authenticated_active_email_monitor_identity_successor.sql` — exact 671-gated append-only authenticated identity successor with forced-RLS immutable capability history and exact-actor SECURITY DEFINER attestation/UID514 read RPCs.
- `scripts/pdc_active_preflight_authenticated_compatibility.py`, `scripts/run_current_active_authenticated_compatibility.ps1`, `scripts/install_pdc_active_preflight_authenticated_compatibility.ps1` — protected standard `authenticated` JWT runtime successor; sealed `.44` release remains unchanged and task/mailbox/UID514 actions remain disabled.
- `scripts/manage_monitor_authenticated_active_successor_staging.py` — exact staging management preflight/apply/post-readback controller.
- `tests/test_monitor_authenticated_active_successor_672_contract.py`, `tests/test_pdc_active_preflight_authenticated_compatibility.py`, `tests/test_monitor_authenticated_active_successor_672_live.py` — contract, negative, idempotent and opt-in live coverage.
- `docs/website-development/PDC-EMAIL-AUTHENTICATED-IDENTITY-SUCCESSOR-20260827.md` — secret-free pdc-emails handoff.
|
|## Email Monitor .44 final mailbox and dispatch compatibility 674-676
|
|- `supabase/staging_only/20260827108000_674_authenticated_monitor_mailbox_activation_transition.sql` — exact existing `pdc_pmb_email` activation, authenticated 674 proof/readback and immutable guarded rollback; 670-673 remain preserved.
|- `supabase/staging_only/20260827109000_675_authenticated_monitor_enqueue_trigger_compatibility.sql` — exact authenticated enqueue branch through the disabled-pilot trigger, UID floor 515, immutable trigger history and rollback.
|- `supabase/staging_only/20260827110000_676_authenticated_monitor_rollback_control_repair.sql` — additive repair making the 674/675 enabled controls rollbackable.
|- `scripts/pdc_active_preflight_authenticated_mailbox_compatibility.py`, `scripts/run_current_authenticated_monitor_dispatch.ps1`, `scripts/pdc_authenticated_monitor_dispatch_bootstrap.ps1`, `scripts/install_pdc_authenticated_monitor_dispatch.ps1` — protected authenticated 674 preflight and task bootstrap/runner with exact adapter and sealed-launcher hash anchors; task remains disabled.
|- `scripts/pdc_authenticated_monitor_runtime_adapter.py` — external sealed-module loader repair registering `imap_bridge` in `sys.modules` before execution, retaining the 7/4 MIME contract without editing `.44`.
|- `tests/test_monitor_authenticated_mailbox_activation_674_contract.py`, `tests/test_monitor_authenticated_enqueue_trigger_675_contract.py`, `tests/test_monitor_authenticated_runtime_successor_contract.py` — mailbox, trigger, adapter, dispatch, malformed and synthetic rollback contract coverage.
|- `docs/website-development/PDC-EMAIL-ACTIVATION-COMPATIBILITY-HANDOFF-20260827.md` — exact secret-free pdc-emails handoff and current JWT expiry boundary.

## Navision Delivered-at-Dealer identity security successor 707 — 2026-08-27

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260827109100_707_navision_delivery_monitor_identity_security_successor.sql` | Staging backend security | Exact live 675-head append-only successor; private predecessor for the actor-accepting delivery RPC; one-argument server-derived canonical Monitor/import route; exact operational-wrapper gate; ACL/postcondition audit | Staging-only migration; no 700-706 rewrite/reapply, no vehicle mutation, Production excluded. |
| `supabase/staging_only/20260827110100_708_navision_delivery_scope_674_alignment_successor.sql` | Staging backend security | Exact live 676-head append-only successor while preserving 707 and 700-706 lifecycle history; aligns the effective delivery gate with active 674 Monitor/import binding | Staging-only migration; no 700-707 rewrite/reapply, no vehicle mutation, Production excluded. |
| `pdc-email-vehicle-location-service.js` | Frontend/service boundary | Removes direct browser `reconcileNavisionDelivery700` export and caller-supplied actor payload | `test_navision_delivery_security_successor_707.js`; canonical delivery remains server-owned. |
| `index.html` | Staging cache marker | Adds a dedicated Navision-delivery security successor cache marker to the changed service asset URL | Pages read-back must include `navision-delivery-security=2026.08.27.707-708`. |
| `scripts/manage_navision_delivery_security_707_staging.py` | Staging management | Exact live 675 preflight, rollback rehearsal, approval-gated apply and live ACL/object read-back | Uses staging project ref only; evidence path is external to the repository. |
| `scripts/manage_navision_delivery_scope_alignment_708_staging.py` | Staging management | Exact live 676 preflight, rollback rehearsal, approval-gated apply and live ACL/object read-back | Uses staging project ref only; evidence path is external to the repository. |
| `test_navision_delivery_security_successor_707.js`, `tests/test_navision_delivery_security_successor_707_live.py` | Hostile security coverage | Generic authenticated, viewer/operator/admin, anonymous, wrong actor/email zero-mutation, exact monitor identity, immutable replay hook, alternate wrapper and PostgREST grant surface | Node contract runs by default; Python live lane is opt-in and transaction-contained. |

## Email Monitor .44 exact retained UID514 recovery successor 677/678/679/682/683

|| File | Stream | Exact surface | Tests / coordination |
||---|---|---|---|
|| `supabase/staging_only/20260827111000_677_uid514_exact_recovery_successor.sql` | Staging backend/runtime identity | Exact actor/binding/mailbox/event/parent hash, seven retained MIME parts, four PDFs, private capability, typed enqueue/authorization and gated claim | Live synthetic full-chain rehearsal rolled back; real UID514 remains untouched. |
|| `supabase/staging_only/20260827112000_678_uid514_authorize_attachment_count_repair.sql` | Staging backend/runtime identity | Exact seven-part authorization cardinality repair from 4 to 7 with immutable history | Applied/read back; no intake/vehicle mutation. |
|| `supabase/staging_only/20260827113000_679_uid514_recovery_event_key_repair.sql` | Staging backend/runtime identity | Separates 677 control-install history key from first recovery effect key | Applied/read back; no intake/vehicle mutation. |
|| `supabase/staging_only/20260828000000_682_uid514_capability_consumption_repair.sql` | Staging backend/runtime identity | Private capability consumption without nested custom-GUC dependency | Applied/read back; forced-RLS history. |
|| `supabase/staging_only/20260828010000_683_uid514_capability_mint_replay_repair.sql` | Staging backend/runtime identity | Exact capability mint on first call and replay | Applied; live idempotent rehearsal. |
|| `scripts/manage_monitor_uid514_recovery_successor_staging.py`, `scripts/manage_monitor_uid514_authorize_repair_678_staging.py`, `scripts/manage_monitor_uid514_recovery_key_repair_679_staging.py`, `scripts/manage_monitor_uid514_capability_repair_682_staging.py`, `scripts/manage_monitor_uid514_capability_mint_replay_repair_683_staging.py` | Staging management | Approval-gated source attestation/apply/read-back controllers | Staging target only; later unrelated staging heads preserved. |
|| `tests/test_monitor_uid514_recovery_677_contract.py`, `tests/test_monitor_uid514_recovery_677_live.py`, `tests/test_monitor_uid514_recovery_678_contract.py` | Staging backend/runtime identity | Exact evidence, negative, idempotent, rollback and transaction-contained full-chain rehearsal | Python contract/live lanes pass. |
|| `docs/website-development/PDC-EMAIL-UID514-RECOVERY-SUCCESSOR-HANDOFF-20260827.md` | Management handoff | Exact pdc-emails RPC payload, hashes, identity, rollback and live state | Secret-free; authoritative 674 hash corrected to d6c57dd8…. |

## Durable RFT transport lifecycle 734 — 2026-08-28

|| File | Stream | Exact surface | Tests / coordination |
||---|---|---|---|
|| `supabase/staging_only/20260829000000_734_durable_rft_transport_lifecycle.sql` | Staging backend/lifecycle authority | Append-only RFT Booked/Collected/Delivered receipts, intercepted MIME/photo outbox, QC/photo/email fail-closed gates, bay/allocation release, exact Delivered - At Dealer timer/statistic completion, stale-status latches, legacy RPC fences | Authenticated rollback-safe HERMES-TEST round-trip passed; 734 is applied and later overall staging head is `20260829030000`; production sentinel absent. |
|| `app.js`, `pdc-email-vehicle-location-service.js`, `index.html`, `pdc-supabase-config.staging.js`, `styles.css`, `deployment-identity.json` | Staging UI/projection/provenance | Distinct RFT Booked button, evidence-gated Collected button/section, delivered-only Completed rows/statistics, canonical 734 service payloads, cache-busted assets and applied migration identity | Node focused contract and service/projection checks pass; production config not changed. |
|| `test_durable_rft_transport_lifecycle_734.js` | Regression coverage | Service UUID/version/idempotency mapping, Collected-versus-Completed projection, HERMES-TEST/Production exclusion, UI markers and fail-closed contracts | Runs without live credentials; live transaction verifier is rollback-contained and external to the release tree. |

## Vehicle Locations RFT row presentation 736 — 2026-08-29

|| File | Stream | Exact surface | Tests / coordination |
||---|---|---|---|
|| `app.js`, `styles.css`, `index.html` | Staging Vehicle Locations UI | Replaces RFT row work icons and Age/ETA/Status clutter with exactly `RFT’d`, `Email Sales Person`, and `Collected`; preserves authoritative 734 handlers, role gating, receipt overlays, stale-callback protection and cache markers | `test_vehicle_locations_rft_transport_controls.js`; production untouched. |
|| `test_vehicle_locations_rft_transport_controls.js`, `test_mobile_navigation_compact_width.js` | Regression coverage | Exact three-label row presentation, absence of per-work/status clutter, role-safe disabled state, successor dispatch, transitions, stale callbacks and responsive cache marker | Node focused/full regression lanes pass. |

## Authoritative Vehicle Locations RFT confirmation toggle 736 — 2026-08-29

|| File | Stream | Exact surface | Tests / coordination |
||---|---|---|---|
|| `supabase/staging_only/20260829040000_736_authoritative_rft_confirmation_toggle.sql` | Staging backend/lifecycle authority | Append-only tick/untick receipts, exact vehicle/version/role/idempotency and stale/state guards, timer start/clear, irreversible email/Collected/Completed fence, booking-timer preservation and legacy fences | Applied to exact staging head `20260829030000`; rollback-only hidden HERMES-TEST live acceptance passed. |
|| `app.js`, `pdc-email-vehicle-location-service.js`, `index.html`, `pdc-supabase-config.staging.js`, `styles.css`, `deployment-identity.json` | Staging Vehicle Locations UI/service/provenance | Direct authoritative `RFT’d` checkbox, Email Sales Person gate, disabled reasons, authoritative readback, stale callback suppression and cache-busted 736 assets | `test_vehicle_locations_rft_transport_controls.js`, `test_rft_confirmation_toggle_736.js`; Production untouched. |
|| `tests/test_rft_confirmation_toggle_736_live.py` | Regression/live acceptance | Hidden HERMES-TEST tick, replay, permitted untick, stale version, Email-evidence and Collected irreversible guards with receipt-count and Production checks | `PDC_RUN_RFT_CONFIRMATION_736_LIVE_TESTS=1`; fixture transaction rolled back. |
|| `supabase/staging_only/20260829060000_739_rft_transport_email_draft_successor.sql`, `20260829070000_740_rft_transport_email_draft_read_lock_repair.sql`, `20260829080000_741_rft_transport_email_draft_regex_repair.sql` | Staging RFT email authority | Append-only atomic booking successor with exact QC photo bytes/reference, deterministic intercepted `.eml` artifact, staff read/download RPC, precise fail-closed evidence codes and serialized predecessor guards; 740/741 repair only effective function definitions | Applied live after existing 738 head; exact Stock 13000769 intentionally stopped on missing `NoSuchKey` QC object; no booking/outbox/draft/email created. Production untouched. |
|| `app.js`, `pdc-email-vehicle-location-service.js`, `index.html`, `pdc-supabase-config.staging.js`, `styles.css`, `deployment-identity.json` | Vehicle Locations RFT Email Sales Person UI/service/provenance | Dispatches 739 with canonical UUID/version/idempotency, private QC byte/hash validation, precise fail-closed alerts, intercepted `.eml` download and cache-busted assets | `test_rft_transport_email_draft_739.js`, `test_vehicle_locations_rft_transport_controls.js`, `test_durable_rft_transport_lifecycle_734.js`; Production untouched. |
|| `test_rft_transport_email_draft_739.js` | Regression coverage | Atomic draft RPC contract, exact payload, private storage route, MIME/readback boundary, required evidence markers and staging provenance | Focused Node contract passes; live action verifier stopped safely at missing exact QC storage bytes. |

## Corrected Stock 13000769 recovery/QC retest

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `docs/website-development/STAGING-STOCK-13000769-SCOPE-INCIDENT-20260828.md` | Incident record | Corrected owner-scope binding: Parts task was Stock 13017855, purge 746 was incorrectly authored for Stock 13000769 | Existing dashboard association `20260828_161016_aa9508`; Production untouched. |
| `scripts/apply_migration_747_staging.py`, `scripts/apply_migration_749_staging.py`, `scripts/apply_migration_750_staging.py` | Staging controllers | Exact-head, encrypted-backup, idempotent recovery/photo/projection controller artifacts with no Production fallback | Focused controller syntax/contracts pass; restore not replayed after checkpoint. |
| `tests/test_recovery_747_contract.py`, `tests/test_recovery_750_contract.py` | Regression coverage | Exact UUID/head/append-only/photo/RFT guard/projection scope contracts | Focused Python suite 8/8; full development Node suite 226 passed / 1 skipped. |

## Exact Stock 13080534/13017855 Phase 1 fresh-import reset

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260829163000_exact_stock_reset_13080534_13017855_phase1.sql` | Staging migration | Exact Navision/vehicle/source binding, encrypted closure snapshot binding, scoped hard-delete/reset, forced-RLS immutable receipt and two-row one-time handoff | Applied at live head 752; 31 tables / 273 rows; Production untouched. |
| `scripts/preflight_exact_stock_reset_20260828.py`, `scripts/create_exact_stock_reset_snapshot_20260828.py`, `scripts/apply_exact_stock_reset_20260828.py`, `scripts/verify_exact_stock_reset_20260828.py`, `scripts/rollback_exact_stock_reset_20260828.py` | Staging controllers | Read-before-mutation, encrypted target closure, exact project/head/identity locks, postcondition/readback and rollback artifact verification | Focused contract 7/7; live verify pass; rollback verify-only pass. |
| `docs/website-development/PDC-EMAIL-EXACT-STOCK-RESET-PHASE1-HANDOFF-20260828.json` | pdc-emails Phase 2 handoff | UIDs 680/681, exact message IDs/hashes/attachments, canonical identity and current `.65` entrypoint | Existing dashboard session `20260828_191153_4fb787`; no duplicate dashboard task. |

## Class-level operational refresh

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `app.js`, `vehicle-locations-refresh.js`, `vehicle-locations-refresh-ui.js` | Shared operational UI coordinator | One route-aware fan-in, delegated click listener, route/generation guards, authoritative source adapters, partial-failure retention, draft/scroll/focus restoration and Realtime singleton restart | `test_operational_refresh_class.js`; Vehicle Locations refresh regressions; no operational localStorage fallback or full navigation. |
| `index.html`, `styles.css`, `workshop-planner.js` | Shared control presentation | Compact controls on Vehicle Locations, QC, Control Board, Workshop/station planners, Operations, PDC TV, Production, departments, Parts, Sublet, RFT, lifecycle lists, Back End Data and review routes | `browser_operational_refresh_route_matrix.js`; mobile 390px route/station matrix and no Production request assertion. |

## Stock 13017855 integrity and lifecycle protections — 2026-08-29

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `app.js`, `vehicle-requirements-guard.js`, `index.html`, `styles.css` | Vehicle Detail / Parts / Workshop UI | Non-destructive requirement patching, scheduled-booking-only Parts risk, evidence-only Fabrication/source projection visibility, exact booking navigation metadata and orange bounded highlight | `test_stock_13017855_followup_contract.js`; preserve canonical UUID/version and no local fallback. |
| `workshop-data-service.js`, `workshop-shared-actions.js`, `workshop-planner.js` | Shared mutation/navigation bridge | Exact operation delete/Undo identity contract, Admin department completion booking removal and focus/highlight after lazy planner rendering | `test_workshop_runtime_integration.js`; authenticated staging RPCs remain authoritative. |
| `supabase/staging_only/20260830080000_stock_13017855_integrity_and_lifecycle_guards.sql`, `20260830081000_stock_13017855_restore_navision_parity_successor.sql` | Staging backend | Append-only 772/773 guards, receipts, exact restore and Navision parity successor | `tests/test_stock_13017855_followup_backend_contract.py`; applied/read back on staging only. |
| `scripts/apply_stock_13017855_integrity_772_staging.py`, `apply_stock_13017855_restore_parity_773_staging.py` | Staging controller | Exact predecessor/target/Production gates, restore/replay and unrelated-isolation readback | Live receipt replay verified; no Production or external email. |

## Historical PMB Inbox canonical reconciliation adapter 778/1710

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260830164000_777_historical_reconciliation_canonical_adapter.sql`, `20260830165000_777_historical_reconciliation_canonical_adapter_repair.sql`, `20260830166000_777_historical_reconciliation_canonical_adapter_repair2.sql` | Staging database | Append-only 777 predecessors; immutable forced-RLS claim/receipt, current Monitor binding, frozen checkpoint, canonical parent/Job Card adapter and fail-closed identity/sibling gates | Applied in exact live predecessor chain; no Production or mailbox contact. |
| `supabase/staging_only/20260830170000_778_historical_reconciliation_enqueue_adapter.sql`, `supabase/staging_only/20260830171000_778_historical_reconciliation_security_successor.sql`, `supabase/staging_only/20260830172000_778_historical_reconciliation_receipt_and_occurrence_repair.sql` | Staging database / canonical email importer | UUID-free exact 773-derived enqueue, immutable per-attachment evidence, 24-hour expiry, replay protection, old-mail protection, receipt readback, occurrence-bound children, valid-sibling continuation and ambiguous/multi-vehicle fail-closed handling | Live staging head `20260830172000`; authenticated-only execute; receipts/observations remain zero before owner-controlled retry. |
| `pdc_historical_778_caller.py`, `scripts/apply_migration_778_staging.py`, `scripts/apply_migration_778_successor_1710_staging.py`, `scripts/apply_migration_778_successor_1720_staging.py` | Staging caller/controllers | Frozen-manifest-only caller, current actor/gateway/release binding, fresh outbox, exact staging target and migration approval/readback | Python syntax and focused caller/controller tests passed; no IMAP rescan or valid historical Apply. |
| `tests/test_historical_adapter_778_security_1710.py`, `docs/website-development/PDC-EMAIL-HISTORICAL-RECONCILIATION-778-HANDOFF-20260830.md` | Regression/handoff | Checkpoint, sender, Stock exclusion, Navision not_found, old-mail, replay, attachment isolation, canonical child and no-side-effect contract | Focused security suite 5/5; exact resume command documented for pdc-emails. |
| `supabase/staging_only/20260830173000_782_historical_reconciliation_current_head_security_successor.sql`, `supabase/staging_only/20260830174000_782_historical_reconciliation_atomic_wrapper_successor.sql` | Staging database / canonical historical importer | Exact current-head successor plus private-base wrapper: dependency and trigger-executor fingerprints, immutable kind/ordinal/hash binding, atomic post-enqueue failures, authoritative vehicle/work/operation readback, live protected-state flags and location/identity fences | Live staging head `20260830174000`; 3 binding rows, 0 observations/receipts; authenticated-only wrapper; no historical Apply. |
| `pdc_historical_778_caller.py`, `pdc_full_inbox_typed_import.py`, `scripts/apply_migration_782_successor_1740_staging.py` | Staging caller/controller | Frozen checkpoint-only caller rehydrates row-level children, emits exact attachment kind/ordinal and uses fresh bounded outbox; apply controller requires exact SHA and independent ready-for-apply gate | Frozen artifact verified as 15 rows / 58 siblings / 3 Job Cards; no IMAP rescan or outbound email. |
| `tests/test_historical_adapter_782.py`, `tests/test_historical_adapter_782_1740.py` | Regression coverage | Exact head/serialization, dependency owner/config/ACL/body/callee/trigger pin, replay/expiry/old-mail, kind substitution, atomicity, authoritative readback, RLS/grants and no-side-effect contracts | Focused suites 7/7 and 6/6; pglast 25/16 statements; full npm suites passed. |

## Cycle-7 integrity remediation — 2026-08-30

| File | Stream | Exact surface | Tests / coordination |
|---|---|---|---|
| `supabase/staging_only/20260830180000_783_historical_observation_digest_repair.sql` | Historical reconciliation | Separates request and observation digests in the private 782 base while preserving frozen actor/source/attachment/replay/atomic and authenticated-only boundaries | Applied/read back at staging head 783; observations/receipts remain zero before controlled historical retry. |
| `supabase/staging_only/20260830181000_784_stage_a_integrity_projection.sql`, `pdc-ai-auditor-stage-a.js` | Stage-A authority | Complete bounded workflow history through 500, direct VIN/Job Card confirmed/unknown fields, canonical Sublet-instance confirmed/unknown projection, and explicit duration contradiction evidence without timestamp mutation | Live Stage-A readback returned Stock 13017855 workflow `114/114`, complete, with VIN/Job Card confirmed. |
| `supabase/staging_only/20260830182000_785_narrow_authenticated_contracts.sql`, `app.js`, `pdc-supabase-config.staging.js` | Authenticated access | Dealer-scoped planner detail wrapper and status-only `ai_email_intake` RPC; no direct intake table grants, no anon/service-role execute, wrong dealer denied | Live authenticated positive/negative RPC and direct-table 403 probes passed. |
| `supabase/staging_only/20260830183000_786_cycle7_contract_repair.sql` | Security review repair | Corrects the existing 778 observation contract version, seals and uniques `observation_sha256`, and revokes the old unscoped planner-detail browser grant | Applied/read back at staging head 786; old detail auth false, scoped planner auth true, observations/receipts `0/0`. |
| `supabase/staging_only/20260830184000_787_cycle7_contract_version_repair.sql` | Security review repair | Aligns the digest, observation, response and receipt contract-version assertions to the immutable 778.1 table contract | Applied/read back at staging head 787; no `782.1` assertions remain in the deployed private base. |
| `supabase/staging_only/20260830185000_788_canonical_historical_digest_contract.sql`, `pdc_historical_778_caller.py`, `pdc_full_inbox_typed_import.py` | Canonical digest repair | Shared fixed length-prefixed UTF-8 request/observation digests with server recomputation, caller echo validation, full protected snapshot check and exact 15-row handoff | Independent review `deleg_a6903a92` ready with zero blockers; live head 788, cross-language bytes equal, observations/receipts `0/0`. |
| `scripts/apply_migration_788_staging.py`, `handoffs/PDC-EMAIL-HISTORICAL-RECONCILIATION-788-READY-HANDOFF-20260830.md` | Staging apply/handoff | Idempotent guarded readback controller and exact new-outbox frozen 15-row handoff; no historical writer invocation | Live controller readback passed; PT5M remains disabled pending protected runtime repair. |
| `tests/test_cycle7_integrity_remediation_contract.py`, `scripts/verify_cycle7_live_browser.py` | Regression/live proof | SQL parsing, digest separation, Stage-A projection, access boundary and route/console/network verification | Focused contract and full website suite pass; live admin route matrix exercised without Production requests. |
| `docs/website-development/CYCLE-7-INTEGRITY-REMEDIATION-REPORT-20260830.md` | Final evidence | Exact fixes, live readback, tests, staging publication, remaining evidence-only blockers and artifact paths | Secret-free final report; Production/outbound email untouched. |
