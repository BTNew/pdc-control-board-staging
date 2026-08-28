# Shared Files

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
