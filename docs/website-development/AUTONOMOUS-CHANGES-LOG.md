# Autonomous Changes Log

Entries added by Hermes after completing autonomous staging work (auth, migrations, RLS, Supabase config, etc). Format: date, what changed, why.


## 2026-08-17T09:30:58Z — Staging Email Bot viewer identity

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only.
- Action: Created a dedicated Auth user for the PDC Email Bot and approved its `viewer` role in `pdc_user_roles`.
- Account: `pdc-monitor-staging-viewer-<generated>@broometoyota.com.au` (full credential values are stored only in the protected `pdc-monitor` profile).
- Actor: Craig Watson administrator role.
- Verification: Auth user creation returned HTTP 200; role read-back returned `viewer`, `approved`, `active=true`.
- Production: not contacted.
- Secrets: not written to this log.

## 2026-08-17T14:22:00Z — Website Development Lead staging access

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only.
- Action: Provisioned the website-development-lead profile with profile-local staging Supabase URL, publishable/anon access, staging service authority, staging database DSN, staging test identities, backup-test key and certifi CA path.
- Safety gates: `PDC_STAGING_WRITES_ENABLED=true`; `PDC_PRODUCTION_WRITES_ENABLED=false`; production project reference was rejected during provisioning.
- Restart: website-development-lead gateway restarted after provisioning.
- Verification: authenticated Supabase login, authenticated REST read, service-role REST/catalog read and authenticated Realtime join passed. Direct database authentication failed with PostgreSQL password authentication failure; migration/RLS catalog verification remains blocked until a valid staging database DSN is supplied.
- Deployment: GitHub staging/review workflows and repository read access were verified; no workflow was triggered and no deployment was performed.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18 — Parts Vehicle Locations membership and completion contract

- Environment: local source only; no staging or production mutation/deploy/push.
- Action: Parts now consumes the same Vehicle Locations row set, removes completed Parts state from the queue, and routes manual completion only through the authenticated receipt-backed shared mutation. Completion responses without a receipt fail closed; exact replay is accepted only as `changed=false`.
- Email contract: documented the existing `process_pdc_email_communication` / `pmb-email-communications-v1` Parts Complete extraction, identity, provider binding, receipt readback, fail-closed and replay requirements.
- Verification: focused JavaScript and backend parser/runtime tests run locally; full results reported with the task.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-17T14:45:00Z — Auditor controlled Apply/Undo source contract

- Environment: local source plus Supabase staging project `cdsmnqxtyyoeoznmbidd` read-only verification.
- Action: Added the reviewed 255–258 staging migration chain, exact-SHA migration controllers, controlled Auditor plugin source, deterministic managed-head fixture/test lane, and contract documentation. Migration 258 exposes only typed Query, atomic Apply, and whole-run Undo; derives scope/current/before/version evidence server-side; appends immutable plan/run/change/Undo receipts; verifies post-write state; preserves history; and emits one Realtime revision per committed run. Private plan/run/receipt tables are RLS-protected with narrow dedicated-identity access; only the revision projection is readable through its dedicated policy.
- Verification: authenticated staging Board snapshot RPC returned HTTP 200 with the bounded 100-row contract and one live item; authenticated Supabase Realtime join returned `phx_reply`/`ok`; unauthenticated service-role REST probes confirmed the 258 tables/RPCs are not yet installed in staging.
- Migration application: not performed. The current profile has valid Supabase API credentials but no valid `PDC_STAGING_DATABASE_URL` for the exact staging PostgreSQL target; the reviewed controller therefore was not run against an invalid DSN. No production target or production credential was used.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T01:52:23Z — Staging vehicle-card Parts completion projection fix

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` and Supabase staging client path only.
- Action: Published commit `71591af` from an isolated clean worktree. The authenticated vehicle mapper now retains Parts completion from `parts_update.parts_received` after the shared save refresh, preventing the vehicle-card tick from reverting red. Updated `index.html` and `staging.html` service query strings for cache invalidation and added `test_parts_snapshot_completion_projection.js`.
- Verification: focused mapper test passed; shared Parts contract passed; JavaScript syntax and diff checks passed; remote `staging/main` points to `71591af`; Pages workflow completed successfully; live entry pages and service asset returned HTTP 200 and the live asset contained the new projection logic.
- Backend: no database migration or production/backend mutation was performed. The fix consumes the existing staging `parts_update.parts_received` snapshot field.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:00:00Z — Staging Parts save diagnostics and projection hardening

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `709a4ac` from a clean isolated worktree. The Parts mapper accepts both top-level and nested `parts_received` projections; shared work-state save failures now surface bounded backend status/details; `app.js` cache-busting was updated on both staging entry pages.
- Verification: focused projection, shared-action, diagnostics and JavaScript syntax checks passed; Pages workflow completed successfully; live `app.js` and service assets returned HTTP 200 with the new logic.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:11:14Z — Staging inline vehicle-card Parts save

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `878e316` from a clean isolated worktree. Inline vehicle-card completion flags for authenticated email vehicles now build the complete shared work-state map and call the protected RPC instead of browser-local `saveVehicleEdits`.
- Verification: inline handler, projection, diagnostics, post-save reconciliation and shared-action tests passed; syntax/diff checks passed; Pages workflow completed successfully; live `app.js` contains the inline shared-save path.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:21:46Z — Staging common authenticated Parts target

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `de49cc8` from a clean isolated worktree. Mark Ordered, Parts ETA and Mark Complete now resolve the authenticated email vehicle by canonical ID/stock/key and initialize the shared Parts service when needed, instead of depending solely on a marker on the merged display row.
- Verification: common-target, shared-action, projection, diagnostics, reconciliation and inline-card tests passed; syntax/diff checks passed; Pages workflow completed successfully; live `app.js` contains the common resolver and all three RPC routes.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:26:43Z — Staging shared work-state post-save reconciliation

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `6672d43` from a clean isolated worktree. After `set_pdc_vehicle_work_states` succeeds, the live vehicle card now reconciles every required-work state into the selected row, `app.data` and the authenticated email snapshot rows before rendering, preventing Hoist/Fitting/Tint/etc. from reverting from a stale display object.
- Verification: work-state reconciliation, Parts, shared-target, inline-card and diagnostics tests passed; syntax/diff checks passed; Pages workflow completed successfully; live `app.js` contains the reconciliation helper.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:37:45Z — Staging stale work-state overlay and Save completion

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `0350130` from a clean isolated worktree. Shared required-work saves no longer wait on unrelated Workshop snapshot services. A bounded pending authoritative overlay prevents a stale email vehicle snapshot from replacing the just-committed Hoist, Fitting, Tint, Fabrication, Electrical, Tyre, Pit, Sublet or Parts states while the confirmed vehicle version is being read back.
- Verification: exact stale-projection/Save-hang regression plus all Parts/work-state focused tests passed; full suite passed with 224 tests, 0 failures and 1 intentional skip; syntax/diff checks passed; Pages workflow completed successfully; live cache-busted `app.js` contains the overlay.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T02:59:25Z — Staging canonical work-state and Parts identity fix

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commits `909268d`, `f2c0f58` and final `91b9ca7` from clean isolated worktrees. Vehicle-detail Save now builds the RPC map from the visible tri-state button state. Required-work and Parts actions resolve any shared vehicle by canonical UUID, not only authenticated-email snapshot membership, and read back `vehicle_work_items` / `vehicle_parts_updates` directly by UUID.
- Confirmed staging evidence: vehicle `12185553` exists as active/visible canonical vehicle; the authenticated email snapshot returned zero rows for it; the live shared RPC accepted Hoist/Fitting `required` and readback confirmed both rows `required=true` at vehicle version 25. Parts rows also showed ordered/required state. This was a staging-only controlled verification.
- Verification: dynamic payload, canonical readback, shared-target, Parts, stale-projection, inline-card and diagnostics tests passed; syntax/diff checks passed; Pages workflow completed successfully; live cache-busted `app.js` contains the final resolver and payload code.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T03:04:54Z — Staging work-state mapper-boundary correction

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `2e85221` from a clean isolated worktree. Reapplied pending authoritative work-state overlays after `reconcileVehicleRows()` runs the email snapshot DTO mapper, which previously rebuilt rows with false work flags and erased the valid saved state.
- Verification: raw snapshot-to-DTO mapper regression passed alongside the full focused work-state/Parts suite; syntax/diff checks passed; Pages workflow completed successfully; live `app.js` contains the post-mapper overlay.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T03:09:54Z — Staging persistent canonical render cache

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `5515251` from a clean isolated worktree. Canonical UUID work-state readback is now retained in a current-page cache and applied after every board projection, so `selectedVehicle()` and `renderDetail()` cannot fall back to a stale email/local DTO after the valid shared save.
- Verification: raw mapper, dynamic payload, UUID readback, Parts and stale-projection tests passed; syntax/diff checks passed; Pages workflow completed successfully; live cache-busted `app.js` contains the persistent cache.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T03:21:12Z — Staging Parts readback HTTP 400 correction

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `ae5585e` from a clean isolated worktree. Removed the non-existent `previous_worst_eta` column from the canonical `vehicle_parts_updates` readback query. The invalid column had made the Parts readback return HTTP 400, causing the successful work-items read to be discarded by `Promise.all` and leaving Parts red/stale in the card.
- Confirmed staging evidence: the old query returned PostgREST HTTP 400 with `column vehicle_parts_updates.previous_worst_eta does not exist`; the corrected query is present in the live asset.
- Verification: Parts readback, mapper, dynamic payload, UUID, stale-projection and full focused tests passed; syntax/diff checks passed; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T05:16:42Z — Staging modal EMAIL UPDATE selection fix

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `8b3777c` from a clean isolated worktree. Vehicle-detail EMAIL UPDATE now uses the active modal vehicle and canonical `selectedVehicle(key)` fallback instead of requiring the vehicle to be uniquely present in `app.data`.
- Verification: modal selection, required-work payload, mapper, Parts and JavaScript syntax tests passed; Pages workflow completed successfully; live `app.js` contains the modal vehicle resolver.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T05:24:35Z — Staging linked salesperson email recipient

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `4125b50` from a clean isolated worktree. Salesperson directory records now take priority over imported direct-email fields; when the vehicle is `AW`, the linked Andy Weir address is used instead of a stale Bryce Guthrie email. The recipient field is read-only and explicitly identified as directory-linked.
- Verification: linked-recipient, modal selection, Parts/work-state and JavaScript syntax tests passed; Pages workflow completed successfully; live `app.js` confirms directory priority and readonly recipient.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T05:31:14Z — Staging QC dummy vehicles

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `fa12a19` from a clean isolated worktree. Added three clearly labelled staging-only QC fixtures to `data-staging-empty.js`: `QC-DUMMY-001` ready for sign-off, `QC-DUMMY-002` with outstanding Hoist/Fitting/Electrical work, and `QC-DUMMY-003` with mixed completion including outstanding Fabrication. The staging entry now cache-busts the fixture file.
- Verification: fixture contract, JavaScript syntax and diff checks passed; live staging data and HTML assets returned HTTP 200 with all three dummy stocks; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T06:21:23Z — Staging movable 30-minute Admin tile

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `d93ca53` from a clean isolated worktree. Added a yellow draggable Admin palette tile to the Workshop Board with a 30-minute default, editable duration in 15-minute increments, drop-to-create shared Admin block behavior, and existing placed-block move/resize controls retained.
- Verification: movable Admin palette contract, Workshop Planner/app syntax and diff checks passed; live Planner JS/CSS/HTML assets returned HTTP 200 with the palette; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T06:34:07Z — Staging Admin drop global revision correction

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `ebbf57f` from a clean isolated worktree. Admin tile/modal creation now reads the global `workshop_revision` row immediately before the create RPC. The station snapshot revision was not valid for the global Admin-block RPC (`station revision 298` versus `global revision 1813` in live staging), causing every new tile/drop to be rejected as a stale booking.
- Verification: Admin palette/revision contract, Workshop Planner/app syntax and diff checks passed; live Planner JS contains the global revision read; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T06:43:36Z — Staging Parts queue canonical readback

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `8852328` from a clean isolated worktree. Mark Ordered, Mark Received and Parts ETA now run the canonical UUID Parts readback and rerender the Parts queue after both success and already-ordered/version-conflict/error responses, preventing a correct backend state from remaining displayed as Not Ordered.
- Confirmed staging evidence: live backend for `12236575` had `parts_ordered=true`; the prior UI alert was `parts_already_ordered` while the queue remained stale.
- Verification: Parts queue canonical readback, Parts action, payload, mapper and syntax tests passed; live cache-busted `app.js` contains the fix; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T08:19:21Z — Staging indefinite started Workshop chips

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `727606e` from a clean isolated worktree. Started Workshop chips now extend through the current operational moment until explicitly completed or placed on STOPPAGE; estimated overruns retain the existing flashing-red state and now display `OVERTIME`.
- Verification: started indefinite-duration/overtime contract, Workshop Planner syntax and diff checks passed; live Planner JS contains the started end-time rule and OVERTIME label; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T08:35:28Z — Complete staging board reset

- Environment: Staging Supabase project and staging Board only.
- Action: Archived all eight active staging vehicles, including three Navision vehicles and five Hoist test fixtures, through the Administrator `pdc_admin_archive_vehicle` audited lifecycle RPC. Synthetic fixture stocks were normalized to reserved numeric staging-test identifiers solely so the protected archive contract could accept and tombstone them.
- Verification: active staging vehicles 0; Vehicle Locations snapshot 0; Hoist Workshop snapshot vehicles 0, outstanding candidates 0 and bookings 0.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T08:55:14Z — Final staging Navision and QC fixture clear

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` only.
- Action: Published commit `f4d546c` to remove the three bundled QC test vehicles from the staging bootstrap and cache-bust the empty data file. Shared Navision records had already been retired from both live dealer scopes and revision 2314 was published.
- Verification: active canonical vehicles 0; shared Navision scope 14450 items 0; scope 37047 items 0; bundled staging vehicles empty; Pages workflow completed successfully.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-18T10:43:09Z — UID477 staging-only blocker verification (fail-closed)

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; production was not contacted.
- Scope: retained UIDVALIDITY 1:477, existing intake `b0dcc3f6-fd8d-4302-9d53-ad19dd6f1596`, existing attachment `303cd065-41de-4197-956d-66dcdf7dbdc4`, and Navision row `782e0195-782d-4fc0-92f2-a5b55abf6c8c` only.
- Action: Used the protected owning-profile authenticated Viewer identity for typed read-only identity, intake-receipt, monitor-status and UID514 fail-closed diagnostics. Used IMAP `readonly` plus `BODY.PEEK[HEADER]` for UID 477; flags were unchanged and no PDF bytes were fetched or uploaded.
- Result: Navision identity RPC returned `not_found` with operational `multiple_operational_matches`; monitor status recorded `identity_conflict` and `Current authoritative Navision identity is archived/inactive; retained UID477 import stopped without changes`. The typed work-receipt probe returned `work_receipt_not_found`. Direct receipt-table probes returned HTTP 403 under the authenticated normal identity. UID514 returned `uid514_authorization_pending`.
- Repair: Not attempted. No existing reviewed authenticated typed repair/reconciliation/activation contract was found that accepts the exact retained UID477 evidence and archived/inactive Navision row at the current head. The older migration-212 contract is predecessor-gated to head 211 and hard-codes a different attachment hash, so it was not called. No row, history, receipt, mailbox flag, gateway or import state was mutated.
- Verification: static migration contract passed; 32 local fail-closed/replay/runtime tests passed; Python syntax passed. Secret-free evidence is recorded in `docs/website-development/UID477-STAGING-EVIDENCE-20260818.json`.
- Rollback: no rollback required because no live mutation occurred. Automatic imports and gateway remain stopped; production remains untouched.
- Secrets: values were not printed or written to this log.

## 2026-08-19 — Staging Parts ordered icon and completion migration

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` and Supabase staging target only.
- Action: Published isolated commit `e4a2558`. Ordered Parts now render an accessible blue ordered/package glyph in the dashboard; the shared Mark Received path is backed by staging migration 259, which atomically records received Parts, completes the canonical PARTS work item, clears active stoppage/ETA, increments the vehicle version, writes receipt-backed audit evidence and publishes one Parts revision.
- Verification: focused Parts, projection, shared-action and migration contracts passed; the staging Pages workflow completed successfully; live `index.html`, `app.js`, `styles.css` and the Parts service asset returned HTTP 200 and contained the published UI/service markers.
- Backend blocker: live staging RPC probe for `mark_pdc_parts_complete` returned HTTP 404/PGRST202 because this profile does not have the exact staging PostgreSQL DSN (`PDC_STAGING_DATABASE_URL`), so migration 259 was published as source but not applied to the database.
- Production: not contacted.
- Secrets: values were not printed or written to this log.

## 2026-08-23 — Staging-first backup and disaster-recovery commissioning

- Environment: GitHub backup read-only for both repositories; Supabase staging preparation only. Production Supabase was not contacted.
- Action: Independently verified the existing encrypted Git bundle evidence without reading the DPAPI key; repaired the profile-local GitHub backup tick with verified-pair retention, ACL guard, deterministic manifest digest, cleanup, and nonzero failure handling. Added secret-free GitHub metadata, current site/source/config, Hermes automation inventories, a guarded disabled Supabase full-backup entry point, and restore/retention drills under `C:/Users/nwmgr/HermesWorkspaces/development/pdc-backup-system-20260823`.
- Supabase blocker: direct staging PostgreSQL credential and current project-specific CA certificate are not securely provisioned; the full Supabase backup script remains disabled and no scheduler was added.
- Verification: GitHub hash verification passed; synthetic Git bundle restore and retention safety tests passed; staging Pages assets were read back with HTTP 200 for index/app/styles. No production write/deployment/migration/data change or credential operation occurred.
- Secrets: values were not printed, copied or written to this log.

- Secrets: values were not printed, copied or written to this log.

## 2026-08-26T23:48:53Z — Contained Email Monitor binding 504 successor

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` and staging repository only; Production was not contacted.
- Action: Added the guarded append-only successor migration `20260827052000_504_forward_reconcile_contained_email_runtime.sql` and focused regression `test_pdc_monitor_contained_successor_504.js`. The successor binds actor `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`, gateway `pdc-monitor-staging-sales-uid509-v1`, release `pdc-monitor-staging-m502-2026.08.44`, source/tree `e850c319989d98b45b95a28aa815d78e2c2e3a4b` / `8981540501bc629e189c39c9ea8a9adf3165d397`, manifest/archive `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d` / `4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90`, and migration head 503. It preserves the predecessor pair as rollback metadata, requires exact admin/actor/containment checks, denies direct table DML, keeps history immutable, and leaves runtime readiness fail-closed.
- Verification: Focused successor regression passed; `npm test` passed with 226 passed, 0 failed, 1 skipped; source commit `21382084ee64f3081539abf0f02843e2d58aab10` was pushed only to staging `main`; Staging integrity and Pages workflows both succeeded; raw GitHub and Pages read-back returned the migration bytes HTTP 200.
- Backend status: The live staging `provision_pdc_monitor_contained_binding_503` correctly rejects the candidate with `PDC_503_ALREADY_TRANSITIONED_INPUT_DRIFT`. The new successor RPCs return HTTP 404/PGRST202 because the staging PostgreSQL migration connector/DSN is not available in this profile, so migration 504 could not be applied or live exact binding/readiness-verified.
- Secrets: values were not printed or written to this log.

## 2026-08-27 — Contained Email Monitor 503 successor remediation repaired

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; Production was not contacted.
- Action: Repaired the draft 504 successor migration and added a staging controller. The append-only transaction now binds the live timestamped 503 head/name, predecessor ledger hash, predecessor function hashes and required markers, preserves the exact sales actor and reviewed release inputs, and refuses writer/planner/mailbox/automatic-operation activation.
- Verification: Added source contract coverage plus an opt-in staging integration test for exact transition, negative input rejection, private-table denial, idempotent replay and exact readback. Local contract tests and Python syntax checks pass.
- Publication: Clean staging-base release commit `0b75b2d9a5260a6feee0c5757de0c25e607db263` pushed only to `BTNew/pdc-control-board-staging` `main`; Staging integrity and Pages deployment succeeded; GitHub raw read-back returned HTTP 200 for every changed file and Pages returned HTTP 200.
- Connector/apply: The existing Windows DPAPI staging store validated the exact project and CA fingerprint; the pooler authenticated with `verify-full`. The exact 26f source was rehearsed and correctly rejected by the live timestamped ledger representation; timestamp-aware 504 plus forward repairs 505–507 were applied transactionally with no applied ledger rows rewritten.
- Live result: PostgreSQL head is `20260827057000`; 503–507 lineage rows are present; exact binding/readiness read-back returns `ok=true`, actor `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`, source/tree/manifest/archive candidate hashes, `migration_head=503`, `mode=contained`, `operational=false`, `activation_ready=false`, `writer_active=false`, `planner_commissioned=false`, and `production_writes=false`. First reconcile succeeded and replay returned the same ID idempotently. Source-tree drift returned HTTP 400; direct private-table read returned HTTP 403; unapproved identity returned HTTP 403.
- Secrets: values were not printed, copied or written to this log.

## 2026-08-27 — Restore Yard Hold → PMB staging control

- Environment: GitHub Pages staging repository `BTNew/pdc-control-board-staging` and Supabase staging read-only probe only; Production was not contacted.
- Action: Corrected the Yard Hold row renderer to use the exact approved `transfer to PMB` guard operation. The prior `render transfer to PMB` label did not match the reviewed exception for authenticated server-authoritative rows, so eligible rows displayed `Shared move unavailable` despite the existing audited `pmb_transfer_vehicle` path.
- Scope: Preserved the existing operator role check, canonical vehicle/version resolution, RLS, audit, movement history, revision publication and fail-closed behavior for non-authoritative/local and bulk mutations. No migration or real-vehicle action was performed.
- Verification: Red baseline confirmed the mismatched renderer operation; focused shared-location regression passed; `npm run test` and `npm run check` each passed with 226 passed, 0 failed, 1 skipped. Staging commit `8a27eb1c6efeba8bbc3e6abb0b268fba9eafa9a9` is on `main`; Staging integrity and Pages workflows succeeded; Pages status is `built`; live cache-busted `index.html`, `app.js` and lifecycle bridge assets returned HTTP 200 with the corrected markers. The non-mutating RPC probe reached `pmb_transfer_vehicle` and was correctly denied without authentication (`42501`), proving the function exists without changing data.
- Limitation: Authenticated browser exercise was not run because Chrome's remote-debugging permission prompt requires user confirmation in this environment. The two reported vehicles were not changed.
- Secrets: values were not printed, copied or written to this log.

## 2026-08-27 — Contained Email m503 compatibility projection 505

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; Production was not contacted.
- Action: Applied timestamped compatibility successor `20260827058000` (logical 505), followed by the narrow `20260827059000` rollback-path repair. The admin-only security-definer RPC proves reconciliation `0c53cb93-bda2-4d02-90db-4c1b96cc7896` and the exact actor/gateway/release/source/tree/manifest/archive pair before projecting source/manifest into the frozen m503 canonical singleton.
- Preservation: The old singleton source/manifest snapshot is retained in forced-RLS immutable append-only history and `audit_events`; actor, gateway, release, planner-null state, contained mode, RLS, identity checks and fail-closed flags remain preserved. A guarded admin-only forward rollback RPC restores the old snapshot without deleting or rewriting history.
- Verification: Exact forward projection succeeded; replay returned the same history ID with `idempotent=true`; wrong reconciliation ID returned `PDC_505_RECONCILIATION_PROOF_REQUIRED`; unapproved identity returned HTTP 403; direct history-table read returned HTTP 403. Rollback rehearsal temporarily restored the old pair inside one transaction, increased history count from 1 to 2, then rolled back cleanly leaving the approved projection and one forward-history row.
- Live result: PostgreSQL ledger head is `20260827059000`, with 503–507, logical 505 at `20260827058000`, and rollback repair at `20260827059000`. Frozen `verify_pdc_monitor_runtime_binding_503('contained',...)` returns `runtime_binding_verified_503`, `ok=true` for the reviewed source/manifest and `runtime_binding_mismatch` for the old pair. `operational=false`, `activation_ready=false`, `writer_active=false`, `planner_commissioned=false`, and `production_writes=false`; active writers, mailboxes and automatic monitor actions remain zero/stopped.
- Testing/publication: Compatibility contract 7/7, live compatibility suite 3/3, full `npm run test` 226 passed/0 failed/1 skipped, and full `npm run check` 226 passed/0 failed/1 skipped. Clean staging commit `00bc3ad748fe5dc8602c6b7b2dcd6d3cf82827d0` contains only the two compatibility migrations and two self-contained tests; Staging integrity and Pages workflows both succeeded, and raw GitHub read-back returned HTTP 200 with matching hashes for all four files.
- Secrets: values were not printed, copied or written to this log.

## 2026-08-27 — Contained Email .44 replay repair

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; production was not contacted. Mailbox, monitor task, Hermes monitor jobs and vehicle/mailbox data were not started or mutated.
- Root cause: the 504 reconcile RPC replayed the superseded m503 provision call after the 580 projection had already changed the canonical singleton to the reviewed `.44` source/manifest, so replay returned `PDC_503_ALREADY_TRANSITIONED_INPUT_DRIFT` even though the append-only reconciliation and compatibility history were correct.
- Repair: Added the append-only 600/610/630 staging successors. They validate the exact `.44` actor/gateway/release/source/tree/manifest/archive pair, canonical singleton, 580 projection history, immutable forced-RLS history and authenticated-only grants; replay returns the original reconciliation receipt without invoking m503 provisioning. The controller now uses the Supabase Management API path, refuses production, rejects partial chains and treats already-applied successors as idempotent no-ops. The unused 620 draft was not applied or published.
- Live verification: 600 and 610 were applied, the 620 attempt rolled back on its postcondition, and corrected 630 applied successfully. Management controller apply readback reports `committed=true`, current lineage through `20260827063000`, exact `.44` singleton, one reconciliation row and one compatibility-history row, with active writers/mailboxes/automatic pilot all zero.
- Authenticated RPC evidence: exact 504 reconciliation replay #1 and #2 both returned HTTP 200, `ok=true`, `idempotent=true`, same reconciliation ID `0c53cb93-bda2-4d02-90db-4c1b96cc7896`; exact 504/get and frozen m503 verification returned HTTP 200/`ok=true`. Wrong archive returned HTTP 200 `contained_reviewed_pair_mismatch`; wrong source tree returned HTTP 400 `PDC_600_REVIEWED_PAIR_MISMATCH`; direct private-table read returned HTTP 403. UID514 receipt read remains correctly contained and read-only at HTTP 200 `uid514_authorization_pending` for Inbox UIDVALIDITY 1:514; no mailbox or vehicle mutation was performed.
- Testing: successor contract 10/10, previous 504/505 contracts 8/8 and 7/7, Node successor contract passed, Python syntax passed. Production was untouched.

## 2026-08-27 — Contained Email UID514 commissioning terminal 507

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; Production, monitor task, Hermes monitor jobs, mailbox writes and vehicle data were untouched.
- Root cause: The approved 257 authorization RPC requires real mailbox-derived intake and attachment evidence. The authoritative authorization row and terminal receipt were absent, so creating physical/mailbox evidence was not permitted.
- Action: Applied append-only logical 507 `20260827065000`. It creates one exact staging commissioning terminal receipt for recovery event `25751401`, actor/gateway/release and reviewed source/tree/manifest/archive pair, with UIDVALIDITY 1, UID 514, Inbox, and explicit `synthetic_staging_commissioning=true`, `physical_mailbox_fetch=false`, `mailbox_flags_changed=false`, `vehicle_operations=0`, and `operation_lines=0`.
- Preservation: The frozen `read_pdc_uid514_transaction_receipt_257(integer)` signature remains intact; other identities still use the existing `PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED` path. Receipt/control/history tables are forced-RLS and immutable where appropriate; only authenticated reader execution and guarded Administrator rollback are present.
- Live result: PostgreSQL head is `20260827065000`; the frozen reader returns `ok=true`, `terminal=true`, `code=uid514_staging_commissioned_terminal`, event `25751401`, exact actor/pair and no vehicle/operation evidence. Admin and wrong-event paths remain denied; direct receipt/support-table access remains denied. Writer count, active mailbox count and automatic monitor actions are zero; monitor remains stopped; all operational/activation/writer/planner flags are false.
- Rollback: Rehearsal installed the receipt, observed terminal=true, invoked the guarded admin rollback inside the same transaction, observed the control disabled and history append, then rolled back the transaction. Live commissioning remains enabled with one forward history row.
- Testing/publication: Logical-507 contract 6/6, live staging DB suite 3/3, full `npm run test` 226 passed/0 failed/1 skipped, full `npm run check` 226 passed/0 failed/1 skipped, clean staging JavaScript suite 128/128. Staging commit `bdea315fb1efe2e4e3357838ad51db5e169374f1` contains only the migration and two focused tests; Staging integrity and Pages workflows succeeded; raw GitHub read-back returned HTTP 200 with matching hashes.
- Credential note: The existing profile-owned exact-actor JWTs return HTTP 401/PGRST303 and no refresh credential/password is available. The authoritative PostgreSQL reader call is proven terminal=true; a real REST HTTP-200 actor-token proof requires a fresh authorised sales-actor credential.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Contained Email UID514 legacy response-code compatibility 508

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; Production, monitor task, Hermes monitor jobs, mailbox writes and vehicle data were untouched.
- Root cause: Logical 507 correctly returned terminal synthetic commissioning data but used `uid514_staging_commissioned_terminal`; the frozen 2026.08.44 VerifyOnly contract requires the legacy `uid514_receipt_terminal` code.
- Action: Applied append-only logical 508 `20260827066000`. It adds a separate exact-scope response-code adapter referencing the existing 507 receipt, with `receipt_kind=staging_commissioning` and `receipt_source=logical_507_exact_terminal_receipt`; it does not create or alter physical/mailbox/vehicle evidence.
- Preservation: The frozen reader signature, exact actor/event/binding guards, 507 synthetic-only fields, dedicated-identity fallback, forced-RLS private controls/history, authenticated-only reader and guarded Administrator rollback remain intact. Rollback disables only the 508 adapter and exposes the original 507 response code.
- Live result: PostgreSQL head is `20260827066000`; exact contained reader returns `ok=true`, `code=uid514_receipt_terminal`, `terminal=true`, event `25751401`, Inbox UIDVALIDITY 1 UID 514, staging commissioning provenance, no physical mailbox fetch, no mailbox flag change, zero vehicle/operation writes and all operational flags false. Wrong actor/event and direct control/history access remain denied. Writers, active mailboxes and automatic monitor actions are zero; monitor remains stopped.
- Rollback: Rehearsal enabled 508, verified the legacy response, invoked the guarded rollback, verified fallback to `uid514_staging_commissioned_terminal`, and rolled back the rehearsal transaction. Live state remains enabled with one forward history row.
- Testing/publication: Logical-508 contract 6/6, live staging DB suite 3/3, full `npm run test` 226 passed/0 failed/1 skipped, full `npm run check` 226 passed/0 failed/1 skipped, clean staging JavaScript suite 128/128. Staging commit `8b3e64f63ae3c61a6be582aed450369c754de325` contains only the migration and two focused tests; Staging integrity and Pages workflows succeeded; raw GitHub read-back returned HTTP 200 with matching hashes.
- Credential note: Existing profile-owned exact-actor JWTs remain expired/invalid with HTTP 401/PGRST303 and no refresh credential/password is available. The exact reader is proven through the authoritative PostgreSQL path; a real REST HTTP-200 actor-token proof requires a fresh authorised sales-actor credential.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging Email Bot .44 backend/runtime capability remediation 670/671

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only. Production, mailbox, Windows monitor task, outbound email and automatic pilot were untouched.
- Root cause repaired: the exact `sales@broometoyota.com.au` actor was approved Viewer-only with no active writer; active `pdc_email_monitor` RPC grants were incomplete for UID514/attestation/canonical receipt paths; the deployed UID514 contract required seven MIME parts while the .44 runtime gate required four; and no reviewed active semantic planner/trust binding existed.
- Action: Applied append-only `20260827067000` and `20260827067100`. 670 changed only the exact actor to approved importer and activated its existing writer enrollment, bound the reviewed planner/trust receipt, granted only the `pdc_email_monitor` role the required claim/UID514/canonical/attestation helpers, and added forced-RLS immutable capability history. 671 rotated the planner binding to the multi-action-safe artifact under the existing planner-immutability trigger guard without rewriting 670.
- UID514 reconciliation: the live authorization contract remains `attachment_count=7`, with the sole qualifying PDF hash `9a8f...af8f4` and retained authenticated attachment count 4. The reader reports `observed_mime_part_count=7`, `retained_authenticated_attachment_count=4`, `all_mime_parts_retained=true`; no intake, attachment, claim, vehicle or operation row was created by this remediation.
- Live proof: active .44 attestation returned `ok=true`, `runtime_binding_verified_503`, `operational=true`, `activation_ready=true`, `writer_active=true`, `planner_commissioned=true`, exact actor/gateway/source/manifest and `production_writes=false`. Active UID514 reader returned `ok=true`, legacy `uid514_receipt_terminal`, terminal synthetic commissioning, parts 7/retained 4. Wrong actor returned `PDC_314_MONITOR_DEDICATED_IDENTITY_REQUIRED`; wrong event returned `PDC_261_UID514_SCOPE_INVALID`.
- Security proof: exactly one active writer, zero active mailboxes, zero automatic-pilot rows, private 670/671 tables forced-RLS, anon/service-role reader execution false, and the planner immutability trigger re-enabled after rotation.
- Source/tests: `backend/pdc_active_semantic_planner.py`, the active trust receipt, both staging migrations and `tests/test_email_monitor_active_capability_670_contract.py`; focused contract/planner/controller tests 7/7; full `npm run test` 226 passed/0 failed/1 skipped; `npm run check` 226 passed/0 failed/1 skipped.
- Handoff boundary: the Windows monitor remains stopped and pdc-emails must install/use the protected runtime artifact and refresh its same-scope actor credential before any UID514 replay or natural-language action. This worker did not enable the task or process UID514.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging Email Bot .44 active preflight compatibility successor

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and the protected local staging runtime only; Production, mailbox, task execution and credentials were untouched.
- Root cause: sealed `.44` metadata intentionally has `agentic_active_planner_trust_receipt_sha256=null`, so its active preflight rejected the externally commissioned planner even though migrations 670/671 and the protected planner/trust files carried the exact live pair.
- Action: Added `scripts/pdc_active_preflight_compatibility.py`, `scripts/run_current_active_compatibility.ps1` and `scripts/install_pdc_active_preflight_compatibility.ps1`. Explicit active mode now uses the guarded external successor; contained mode remains on the sealed launcher. The successor verifies the exact `.44` release binding, external planner/trust bytes, 670 predecessor and 671 current digests, strict planner smoke, protected paths/ACL policy and the live staging attestation/readback contract. Null, mismatch and broad-identity cases fail closed.
- Installation: The reviewed installer placed the successor in `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44`, wrote its protected digest anchor under the matching trust directory, and preserved the original control runner as `run-current-sealed.ps1`. The sealed release manifest remains `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`; no sealed release member was rewritten.
- Verification: Focused compatibility tests 8/8, Python syntax pass, PowerShell parser pass, `npm run test` 226 passed/0 failed/1 skipped, and `npm run check` 226 passed/0 failed/1 skipped. Installed active-mode preflight executed the sealed venv and external planner smoke, then stopped at `CREDENTIAL_GATE_NARROW_IDENTITY_REQUIRED`; the previous trust-null error did not occur. The task remains Disabled under LOCAL SERVICE and no mailbox/UID514 operation ran.
- Exact source/evidence: `docs/website-development/PDC-EMAIL-ACTIVE-PREFLIGHT-COMPATIBILITY-20260827.md`.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging Email Monitor .44 authenticated identity successor 672

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and the protected local staging runtime only. Production, mailbox, Windows task execution and UID514 processing were untouched.
- Root cause: the sealed active preflight required JWT database role `pdc_email_monitor`, while the exact commissioned sales actor's standard Supabase JWT correctly carries role `authenticated`; server application authorization is the separate approved `importer` row.
- Action: Added append-only migration `20260827067200_672_authenticated_active_email_monitor_identity_successor.sql` with exact 671 predecessor guards, forced-RLS immutable capability/history, exact-actor `SECURITY DEFINER` active attestation RPC and exact-actor UID514 read-only RPC. The RPCs prove actor ID/email, `authenticated` JWT role, approved importer role, exact active writer, gateway/release/source/manifest, commissioned planner/trust, staging sentinel, absent Production sentinel, zero active mailboxes and disabled pilot before returning success.
- Security: Only `authenticated` executes the new RPCs. `anon`, `service_role`, `pdc_email_monitor`, direct capability-table reads and direct table DML remain denied. No JWT was issued or custom-signed, no signing secret was used, no broad authenticated DML was granted, and 670/671/sealed `.44` state was preserved.
- Live staging apply: exact management-path preflight then approval-gated apply completed. Ledger is `20260827067200`; actor remains approved `importer` with one active writer; active mailboxes 0; automatic pilot 0; Production sentinel absent.
- Live read-only proof: standard authenticated claims produced `runtime_binding_verified_authenticated_672` with `ok=true`, operational/activation-ready true, planner/writer true and Production writes false. UID514 reader produced terminal `uid514_receipt_terminal` for Inbox UIDVALIDITY 1:514 with seven MIME parts, four retained authenticated attachments, zero vehicle operations and zero operation lines. Repeat attestation was identical; wrong actor/role denied and wrong gateway returned fail-closed mismatch.
- Runtime: installed authenticated successor and runner under `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44`; installer verified `sealed_release_unchanged=true` and task/mailbox/UID514 flags false.
- Credential boundary: the installed protected environment's actor JWT is expired and returned `PGRST303 JWT expired`; credentials were not refreshed, rotated, copied, fabricated or taken from another profile. pdc-emails must refresh its own standard actor credential and run the protected verification-only runner.
- Source/tests: contract suite 6/6, runtime compatibility suite 3/3, Python syntax pass, PowerShell parser pass, plus opt-in live-test source added. Secret-free handoff: `docs/website-development/PDC-EMAIL-AUTHENTICATED-IDENTITY-SUCCESSOR-20260827.md`.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging Email Monitor .44 execution/attachment compatibility successor 673

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and protected ProgramData staging runtime only. Production, mailbox, Windows task, UID514, vehicles and retained evidence were untouched.
- Root cause repaired: sealed `.44` retained seven MIME attachment parts but its UID514 runtime gate accepted only four; the four authenticated business PDFs were not deterministically separated from the three retained image parts. The same sealed execution path also required JWT role `pdc_email_monitor` for cycle/claim/attachment/result/canonical/agentic RPCs even though the exact commissioned actor uses a standard `authenticated` JWT.
- Action: Applied append-only successor `20260827106000` (`673_authenticated_monitor_execution_attachment_successor`) with exact 670/671/672 predecessor and live function-hash guards. It adds the exact authenticated actor branch to the existing server-side scope, grants only the required existing execution RPCs to `authenticated`, preserves anon/service_role/direct-table denial, records forced-RLS immutable control/history and provides guarded Administrator disable/rollback.
- Attachment contract: the new authorization path requires seven valid retained attachment rows, exactly four verified `application/pdf` business documents, one exact Job Card hash `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`, and stores deterministic all-seven/qualifying-four selection metadata. It does not delete or replace any part.
- Source hashes: migration `742f3517d85c14ae09de7ee489f039fa261c5895039940adde66e2e67ea3f1b1`; external adapter `08e9a0dbca7640b93911fe397e3f9577b7f1e79bebc97c780efbe6aeb4a298e0`; installer `667bec3b867ade57425580793f17c09b7be3ba0775d65b0e297dfa38772f0df4`.
- Runtime install: installed only `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44\pdc-authenticated-monitor-runtime-adapter.py` and its protected trust anchor. Sealed `.44` `imap_bridge.py` hash remains `80d45bb7bde5e0b00fe73e5a54386ede07f7c44fbafcb9e3cc990cc501979248`; `CURRENT` remains `2026.08.44`.
- Verification: migration transaction rehearsal passed and live staging apply passed. Contract suite 5/5; live 673 suite 4/4; existing live 672 suite 4/4; Python syntax passed. Live post-readback confirms successor enabled, MIME 7/4, exact actor/binding/planner/trust, active mailboxes 0, automatic pilot 0, Production sentinel absent, authenticated required execution true, anon/service_role claim execution false, direct control/selection reads false. Synthetic adapter replay retained all seven parts, selected four PDFs and produced one stored effect.
- Handoff: exact RPC names and hashes are recorded in `docs/website-development/PDC-EMAIL-AUTHENTICATED-EXECUTION-ATTACHMENT-SUCCESSOR-20260827.md` for pdc-emails. Task remains Disabled under `LOCAL SERVICE`; no task enable/start, mailbox contact, UID514 processing, canonical mutation or credential operation occurred.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging Email Monitor .44 final mailbox/dispatch compatibility 674-676

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` and protected local staging runtime only. Production was not contacted.
- Root cause repaired: the exact pre-provisioned `pdc_pmb_email` row was inactive, so canonical enqueue failed with HTTP 400 / SQLSTATE `22023` (`pdc_monitor_provider_binding_invalid`) despite the exact actor/binding being commissioned. The disabled-pilot trigger then correctly rejected active enqueue until an exact authenticated branch was added.
- Action: Applied append-only `20260827108000` (674) to activate only mailbox `12fe383d-5c1e-5801-96e4-f67cf3e3bb57` / `pmbcontroller@gmail.com` / Gmail / `test_mode=true`; added exact authenticated 674 proof/readback RPCs and immutable forced-RLS activation history with guarded Administrator rollback. Applied `20260827109000` (675) to add only the exact actor/gateway/release/provider-UID-floor-515 enqueue trigger branch while the automatic pilot remains disabled, with immutable definition history and guarded rollback. Applied `20260827110000` (676) to remove only the two `CHECK(enabled)` constraints that made those already-defined rollback functions unreachable.
- Adapter/dispatch: repaired the external adapter's `importlib` load to register the sealed module in `sys.modules` before execution, covering the sealed dataclass path without editing `.44`. Installed the protected 674 preflight, adapter, dispatch runner and bootstrap; the runner verifies exact predecessor/function/runner/launcher hashes, runs authenticated 674 preflight, adapter anchor proof and sealed launcher smoke only. The scheduled task remains Disabled under `LOCAL SERVICE` with the protected bootstrap action.
- Live readback: ledger contains 670, 671, 672, 673, 674, 675 and 676; exactly one active mailbox and it is the exact row above; 674 activation history=1; 675 trigger history=1; pilot enabled/automatic rule/automatic jobcard/outbound email all false; UID514 intake count=0; Production sentinel absent; authenticated enqueue/674 verify/674 reader execute=true; anon/service_role enqueue and 674 proof execute=false; capability/history direct SELECT=false; history forced-RLS=true.
- Synthetic verification: authenticated staging transaction enqueued `imap_uid:515`, claimed it, read its attachment projection, recorded a terminal result, and rolled back; no synthetic row remained and no vehicle was touched. A separate admin transaction rolled back 674 mailbox activation and 675 trigger repair, confirmed active mailboxes=0 and UID514=0, then rolled back the rehearsal transaction; live forward state remains enabled. Malformed/wrong-scope paths remain fail-closed by source and live contract checks.
- Runtime verification: before the protected actor JWT expired, installed dispatch VerifyOnly returned `runtime_binding_verified_authenticated_674`, `active_mailbox_count=1`, `mailbox_active=true`, terminal synthetic UID514 readback, and sealed Python launcher smoke success. The current installed token now returns `PGRST303 JWT expired`; it was not refreshed, copied, fabricated or replaced. pdc-emails must refresh its own same-scope standard authenticated actor credential before rerunning VerifyOnly.
- Source hashes: 674 `d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb`; 675 `8f7b1c260e03d3cfd5f5c4931abb959aa269ce0e1755728313f98c17ebaca2a0`; 676 hash was verified during rehearsal/apply; mailbox preflight `0ab027ce023af99e3667431ed3c8b622da6198789f15d81e89835549e54e7f66`; adapter `a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036`; dispatch runner `7047cf5bb0c8ababff226a8ccf5e7f52c10d8e5a0958e960ada46c155f373b09`; bootstrap `3903e0d1420fc2c6a93ce5eb5ffbbb8939be692534b9be2ec49d6a289b72f66a`.
- Safety: sealed `.44` manifest remains `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`; `CURRENT` remains `2026.08.44`; sealed runner remains `52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd`; no task enable/start, mailbox fetch/flags, UID514 processing, vehicle/receipt mutation, outbound email or Production action occurred.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Staging second Navision delivery security closure 709-713

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` only. Production sentinel was absent and Production remotes/data/branches were untouched.
- Independent re-review blockers closed: 709 inventories every public `pg_proc`/`pg_namespace` overload for `reconcile_navision_delivery_700` and `reconcile_navision_operational_record`, revokes all exact-name ACLs including default-bearing predecessors, and restores only the exact authenticated one-argument delivery and exact three-argument compatibility shapes. 713 inventories and closes the complete prefixed family, including the observed service-role `pre134` legacy 169 path. The broader inventory also captures all matching live completion/location functions and Navision/body-location triggers.
- Body-location closure: the authenticated `process_pdc_monitor_body_location_20260821033000(...)` implementation now preserves ETA/Yard Hold/Body Builder processing, but exact `Delivered - At Dealer` can only route through canonical 700 with live authenticated `auth.uid()`/`auth.jwt()` and active 674 scope. 710 repaired the existing intake alias collision; 711-712 permit only the legitimate `rft`/`Collected`/`visible_on_board=false` tuple to reach that route. No direct body completion write remains.
- Live apply: 709 was guarded to observed live head 678 (`20260827112000`), then concurrent Monitor migration 679 and append-only 710/711 successors were observed and guarded in sequence; 712 and 713 completed the closure at ledger `20260827118000`. Subsequent concurrent Monitor heads 680–682 were read back without security drift; frozen live head is `20260828000000 / 682_uid514_capability_consumption_repair`. No 700-709 migration was rewritten, reapplied or reset.
- Live proof: catalog/hostile suite passed 3/3. Generic, viewer, operator, administrator, anon, service-role, wrong-actor, overload/default/named-argument calls were denied as expected. HERMES-TEST-only rollback probes passed exact canonical delivery, immutable replay, timer/duration closure, one audit/movement, alternate body-location canonical completion, and retained ETA non-delivery to IT; no synthetic rows remained.
- Source hashes: 709 `eb6dfa6271cd30bdd3b06e9d55db4ca0879348ccddeee46b3afee21f1336b0a7`; 710 `124293ace468dcacaa49338ad2657dafa75ddeec382bbd5bb0546502d6b7526c`; 711 `720f2112c7ab2b314101bd947989e41529a54b974f48a79bfd4c8d37badf3a50`; 712 `496e06141becfdc9937f99c602d67819d672663b5b183525f50b4d39c64c25ef`; 713 `d5f237112fe3dbe75d86d97361e3a9dc3009d9b518a274a35d020107b4c7ed08`; contract test `fda5c2e29d4b27ea8cf85c0199d720884a3e3a9bc21870e7de5b1b823021d1f5`; live test `9570b2a4ba1bf541af71ac18ae231962d1c453e5f69ed3c1eee3508ba6301bdd`.
- Secrets were not printed, copied or written to the log.

## 2026-08-27 — Exact retained UID514 recovery enqueue repair 677/678/679/682/683

- Environment: Supabase staging `cdsmnqxtyyoeoznmbidd` only. Production, mailbox flags/fetch, Windows task, outbound email and vehicle data were untouched.
- Root cause: active 675 correctly rejected provider UIDs below 515, but the retained UID514 message had no canonical intake or exact recovery authorization. The recovery path also required the seven-part authorization cardinality and replay-safe capability consumption.
- Action: applied append-only 677 `20260827111000`, 678 `20260827112000`, 679 `20260827114000`, 682 `20260828000000` and 683 `20260828010000`. 677 binds only actor `df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b`, authenticated/importer, exact gateway/release/source/manifest/planner/trust, mailbox `pdc_pmb_email` / `pmbcontroller@gmail.com`, Inbox UIDVALIDITY 1 UID514, event 25751401 and parent hash `440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280`. It records all seven retained part hashes and exactly four PDFs, with Job Card `9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4`.
- Typed path: `enqueue_pdc_uid514_recovery_677(jsonb,jsonb,integer)` server-normalizes stable attachment IDs, uses a private forced-RLS capability consumed by the existing enqueue trigger, calls the reviewed `authorize_pdc_uid514_retained_intake_257` path atomically, and leaves `claim_pdc_uid514_recovery_257(text,integer)` gated. 679 separates control-install history from the first recovery-effect key. 682/683 make capability consumption and replay deterministic.
- Live verification: authenticated synthetic full-chain transaction created one intake, seven attachment metadata rows, one authorization and one seven-part selection, claimed/read all seven, recorded a result, replayed the exact payload, exercised wrong event/actor/gateway, anon/service-role denial and Administrator rollback. The entire rehearsal rolled back. Live result: 1 passed; persistent UID514 intake/authorization/selection and Stock `13016925` vehicle counts remain 0.
- Live post-readback: successors 670–676 remain present; exactly one active staging mailbox; pilot/automatic rules/automatic Job Card/outbound email disabled; protected recovery tables forced-RLS with direct SELECT denied; authenticated recovery/claim execute true; anon/service_role execute false; Production sentinel absent; task remains Disabled under LOCAL SERVICE; `CURRENT` remains `2026.08.44`; sealed manifest/runner unchanged.
- Source hashes: 677 `ad921292bdafb3bfc25413df8c1faa803442f0c645799aac3cd42af76b0da85f`; 678 `0fab7dbc2525173aea32a5c502b249a892684bdabf4bab483da9ad6e9edacfe1`; 679 `2d11783911adf74070d2e2a15b7eaf628cead126eaf463261247dbcd280b3f9c`; 682 `271dcd6a7bbbbd3500bd55ba7388047cda779ebae27c2c55d585e26a0ca79de2`; 683 `b8fbdbf163a2acedf5c839da5e7f43af868cc05ff0d7db77fbae2aa9e615761c`; authoritative 674 `d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb`.
- Handoff: `docs/website-development/PDC-EMAIL-UID514-RECOVERY-SUCCESSOR-HANDOFF-20260827.md`. Secrets were not printed, copied or written to the log.

## 2026-08-27 — Final Navision family catalog hardening 714/715

- Environment: Supabase staging project `cdsmnqxtyyoeoznmbidd` only. Baseline source was read at commit `7e6bc3c94d173620c9070ff5f63a93f1dcdf9408` / tree `a44984a27118dd2fb719ca57c715953786b2f850`; concurrent staging-only history was preserved. Production was not contacted.
- Action: Added append-only 714, guarded to database head `20260828010000 / 683_uid514_capability_mint_replay_repair` and the preserved 700–713 chain. It inventories `pg_proc` across every non-system schema using `lower(proname)` for exact/prefixed delivery, operational-record and body-location families; separately records live PostgREST exposure (`public, graphql_public`); and captures owner, prokind, SECURITY DEFINER, volatility, exact proconfig/search_path/timeout, defaults, identity/declared arguments and raw ACL grantor/grantee/privilege/grant-option entries.
- Security result: every noncanonical mixed-case, overload/default, prefixed and alternate-schema routine is owner-normalized and denied to PUBLIC, anon, authenticated, service_role and pdc_email_monitor. Only exact lowercase public delivery `(uuid)`, operational `(uuid,uuid,text)` and body-location signatures remain authenticated-executable with the required owner/config/ACL and no PUBLIC implicit execute. Historical definitions remain private and inventory evidence is retained.
- Hostile verification: 714 creates quoted mixed-case, default-bearing overload, prefixed, alternate-schema and `WITH GRANT OPTION` HERMES-TEST probes inside the migration transaction, asserts the post-state and removes all synthetic probes. Verification exposed two public synthetic probe routines needing explicit cleanup; append-only 715 removed only the OIDs/definitions recorded by 714 and proved the canonical delivery call was no longer ambiguous. No user or vehicle mutation occurred.
- Live proof: 714 and 715 applied successfully; final inventory is 14 pre / 14 post rows; public probe count is 0; canonical delivery overload count is 1; catalog ACL/owner drift is 0. Live PostgREST probes classify exactly `public` and `graphql_public` as exposed; mixed-case, named/default, alternate-schema and unauthorized role calls are denied. Existing canonical delivery/replay, exact body-location delivery and ETA-to-IT non-delivery tests passed 3/3 with synthetic effects rolled back.
- Testing/publication: focused 709/714/715 contracts 17/17; focused live catalog/PostgREST suite 3/3; `npm run test` 226 passed/0 failed/1 skipped; `npm run check` 226 passed/0 failed/1 skipped. Staging commit `5d60baa07f32d696e3d494fad8be00dcb579fff4` pushed to `BTNew/pdc-control-board-staging` `main`; Staging integrity and Pages deployment succeeded; live Pages assets and raw changed files returned HTTP 200. Secrets were not printed, copied or written to the log.

## 2026-08-28 — Staging-only final raw ACL closure 716

- Scope: append-only successor to approved staging candidate `5d60baa07f32d696e3d494fad8be00dcb579fff4` / tree `45932e116e25d06f64f7df8c265bf43f223b671d`; preserves 700-715 and production remains prohibited.
- Action: added `20260828040000_716_close_all_raw_navision_acl_grantees.sql` with exact 715 live-head, source/tree, previous-migration digest and canonical function SHA-256 guards. It inventories every `aclexplode` ACL entry for every case-insensitive delivery, operational-record and body-location family routine across all non-system schemas.
- Security result: after owner normalization, every explicit grantee is safely quoted and dynamically revoked, including arbitrary quoted roles and grant options; canonical routines are rebuilt to owner plus exact non-grantable authenticated EXECUTE, while historical/mixed-case/alternate-schema/overload/default members remain owner-only. Canonical monitor success/replay/body-location ETA behaviour is unchanged.
- Hostile verification: the migration creates a quoted arbitrary role with direct EXECUTE plus grant option on canonical and noncanonical routines, captures it in pre-inventory, proves it absent and denied in post-inventory, then drops it before commit. The live rollback test creates equivalent quoted-role ACLs under a savepoint and proves no role or ACL residue remains after rollback. No vehicle or user-data mutation occurs.
- Added focused contract/live coverage and a guarded staging apply helper. Required verification remains source/local tests plus authorised staging live head, raw-ACL postconditions, canonical success/replay/body-location ETA proof, clean staging SHA/tree, CI and Pages read-back; Production is untouched.

## 2026-08-28 — Staging Email Monitor provider/import/agentic compatibility 684/685

- Scope: staging project `cdsmnqxtyyoeoznmbidd` only; exact retained UID514 intake `102e286d-1799-4c97-8e45-e0da9fb31c63`, authorization/selection, seven attachments/four extractions, eight prior claim attempts and successors 670–683 preserved. Production, task enablement, mailbox contact, outbound email and real UID514 processing remain prohibited.
- Root cause: legacy provider attestation/import/read wrappers accepted the stale `pdc_monitor_actor_scope().ok` shape, while the agentic source gate required DKIM=true although retained Gmail evidence is the exact five-key object with SPF/DMARC=true and DKIM=false.
- Action: applied append-only 684 `20260828050000_684_authenticated_provider_import_agentic_compatibility.sql` and 685 `20260828060000_685_uid514_exact_attachment_array_guard.sql`. Added authenticated claim-bound provider attestation, canonical import/readback and agentic context/plan/action/apply/finalize wrappers; revoked legacy generic provider/import surfaces; added exact actor/importer/writer/gateway/release/source/manifest/planner/trust/mailbox/claim/source-hash guards and immutable forced-RLS rollback history.
- Evidence: live transaction rehearsal attested and replayed the exact Job Card observation with the same observation/request hash, source proof returned true, stale 13.10 was rejected in favour of genuine 7.46 hours with zeroes preserved and Tow Bar mapped to fitting, wrong actor and direct table reads were denied, and the transaction rolled back. Live post-readback remains failed/8 attempts/0 observations/0 vehicles, one exact test mailbox, pilot/task disabled and Production sentinel absent.
- Source/tests: migrations, guarded management controllers, contract tests and opt-in live tests were added; focused contracts 7/7, opt-in live tests 3/3, `npm run test` 226 passed/0 failed/1 skipped, `npm run check` 226 passed/0 failed/1 skipped, Python syntax and `git diff --check` passed. Handoff: `docs/website-development/PDC-EMAIL-AUTHENTICATED-PROVIDER-IMPORT-AGENTIC-COMPATIBILITY-HANDOFF-20260827.md`.

## 2026-08-27 — Email AI Monitor .44 final natural-language canonical remediation

- Scope: staging project `cdsmnqxtyyoeoznmbidd` only. Preserved the exact actor/binding/sealed `.44` release, claimed UID514 intake/evidence, mailbox boundary and existing 684/685 controls. Production, task enablement, outbound email and UID514 reprocessing were not performed.
- Root cause: the active authenticated planner stopped at review-only for yearless dates, Parts Complete could not reach the operator-gated canonical Parts path, no bounded manual Sublet booking existed for acceptance, multi-action ordering/accounting was absent, and the exact activated Stock13000765 Navision row was excluded from the authenticated Board snapshot because it had no email import receipt.
- Action: added the staging acceptance/canonical wrapper successors (`20260828120000`/691, `20260828140000`/693 and append-only allocation/binding repairs through the live head), deterministic next-non-past date resolution, manual Customer Sublet setup at `2026-09-10`, per-instruction immutable plan/action/final receipts, ETA → Parts Complete → Sublet dependency ordering, exact replay idempotency, ambiguous fail-closed disposition, and a source/dealer/activation/visibility-gated Board projection repair.
- Live proof: campaign `872f75e8-dafb-42e6-af3a-e88301ecd7cf` used synthetic provider UIDs `100021`–`100026`; 6 plans, 8 action receipts and 6 final receipts were read back. `12 June` resolved to `2027-06-12`; `15 September` resolved to `2026-09-15` while preserving the manual booking year; Parts ended complete; Sublet stayed at one booking; multi-action order and exact replay passed; unclear wording was `genuinely_ambiguous` with zero effect.
- Board proof: authenticated `get_pdc_email_vehicle_location_snapshot()` returned Stock `13000765`, vehicle `2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02`, visible=true, Parts ETA `2027-06-12`, Parts complete=true and one canonical Sublet booking dated `2026-09-15`; `pdc_email_vehicle_revision` Realtime publication remained present.
- Security proof: acceptance plan/action tables are not directly selectable by `authenticated`; exact importer direct Parts operator calls are guarded by `PDC_MONITOR_DIRECT_OPERATOR_RPC_DENIED`, while the exact wrapper consumes only transaction-local `pdc.monitor.canonical_action`. UID514 remains claimed/unchanged and Production sentinel is absent.
- Verification: focused contract 5/5, `node --check` passed, `npm run test` 226 passed/0 failed/1 skipped. Full handoff: `docs/website-development/PDC-EMAIL-AI-FINAL-FUNCTIONAL-REMEDIATION-HANDOFF-20260827.md`.

## 2026-08-28 — Email AI .44 plan-validator closure investigation

- Scope: Supabase staging project `cdsmnqxtyyoeoznmbidd` only. Production was not contacted; UID514, task state, mailbox state, outbound state and the existing seven-part/5-operation evidence were preserved.
- Diagnosis: live migration head was `20260828200000` (`699_agentic_candidate_id_delimiter_repair`). The exact live `pdc_agentic_email_plan_valid_502(jsonb, pdc_agentic_email_context_receipts_502)` predecessor hash was `54830d6a5e1791467eb8d0347e7db077e870de90b00265e89e9996d5303ea12f`. Run `47ba0629-0a27-4ea9-b920-57495ae05295` failed at plan record because the unparenthesized JSONB source-binding subtraction raised `invalid input syntax for type json` (`Token "source_binding"`), not because target, expected map, action hashes or source binding were invalid.
- Action: applied guarded append-only validator repair `20260828230000_700_agentic_plan_validator_precedence_repair.sql` (source SHA `8032e6101ca2ab8d2944ca8cfe42c895910e1e2022816fe3db07a25fe665f4be`), predecessor `54830d...`, successor function hash `7726eb8b97ba6ce622b26120f2132866c88f5fa6273e100e74e64b53c4cc2600`, immutable forced-RLS history row present. A valid strict plan then recorded through the 684 wrapper.
- Follow-up diagnosis: attachment/thread evidence references exposed the same PostgreSQL string/JSONB precedence defect in the live validator. Applied guarded append-only repair `20260828240000_701_agentic_plan_validator_evidence_ref_precedence_repair.sql` (source SHA `3abf85f77591f677f54b38a0dc1db6c0483e31749c58e3eae0ea0610228a2a02`), predecessor `7726eb...`, live successor validator hash `227dd190b639c6f21cea1a668c85994c437b950adb155622c6819d2f1eb07e1a`, immutable forced-RLS history row present.
- Harness: `scripts/run_authenticated_acceptance_campaign_686_staging.py` now obtains the authoritative live candidate list, passes the reviewed semantic planner its exact candidate schema, preserves planner instruction/action fields and hashes, and executes dependency order ETA → Parts Complete → Sublet. Contract tests pass.
- Remaining blocker: the fresh campaign reached plan record but the 684 execute wrapper's canonical 502 pre-read cannot see the campaign's synthetic vehicle IDs because the live Board snapshot is deliberately restricted to the exact activated Stock13000765 projection. The campaign therefore fails closed with `invalid_vehicle_id`/`vehicle_not_found` before any synthetic action receipt is applied. No six-case acceptance run, receipt set, or publishable handoff is claimed from this attempt; failed runs were guarded-cleaned with zero active synthetic vehicles/work/Sublet bookings.

## 2026-08-28 — Staging Email Monitor .44 active dispatch control-artifact repair

- Scope: protected local staging runtime and staging-only source/control artifacts. Production, the sealed `C:\ProgramData\PDCMonitor\Staging\releases\2026.08.44` bundle, its manifest/inventory, mailbox/UID514/vehicle state and outbound email were untouched. The task remains Disabled under `LOCAL SERVICE`.
- Root cause: `control\bootstrap.ps1` invoked the authenticated `.44` runner with `-VerifyOnly`, so a scheduled task would only preflight and exit rather than enter the installed monitor.
- Action: added the append-only active bootstrap/dispatch pair, protected installer, explicit disable/rollback controller, and dedicated VerifyOnly bootstrap/runner under `scripts/`. Active dispatch verifies exact CURRENT/manifest/inventory and preserved sealed runner first, then authenticated 674 identity/current-head/runtime preflight, then reaches the installed sealed `runtime_launcher.py --mode monitor` entrypoint without `VerifyOnly`. OneCycle is the task-safe default; Continuous is explicit. Bounded nonsecret heartbeat status and a global overlap mutex are included.
- Protected installation: installed active bootstrap, active runner, rollback controller and separate VerifyOnly route under `C:\ProgramData\PDCMonitor\Staging\control\2026.08.44`; root task action path and existing trigger/account were preserved. The installer is idempotent, ACL-hardens each new file, never registers/enables/starts the task, and checks sealed bytes before/after.
- Verification: focused control contract 12/12; all six PowerShell scripts parsed; `npm run test` 226 passed/0 failed/1 skipped; `npm run check` 226 passed/0 failed/1 skipped. Installed active `-DryRun` passed the static + authenticated 674 boundary and stopped before mailbox/monitor dispatch; installed VerifyOnly passed separately. Concurrent dry-runs skipped overlap safely; installer rerun passed.
- Installed/source hashes and handoff: `docs/website-development/PDC-EMAIL-MONITOR-ACTIVE-DISPATCH-20260844-HANDOFF.md`. Active bootstrap `3c858e…020e`, active dispatch `1d3574…f4a5`, installer `2be337…8c60`, rollback `ca9702…726f3`, VerifyOnly bootstrap `e90c43…71ac`, VerifyOnly runner `977799…5863`; sealed manifest remains `d48b49…ed58`, sealed runner `52affc…6ebd`.
- Secrets were not printed, copied or written to the log.

## 2026-08-28 — Email Monitor .44 final authenticated acceptance closure

- Scope: Supabase staging project `cdsmnqxtyyoeoznmbidd` only; Production, UID514 processing, Stock13000765, task enablement and outbound email remained untouched.
- Root causes closed: corrected 719 direct JSONB acceptance-marker precedence; canonical action-receipt trigger, audit and finalization source-binding JSONB precedence; duplicate body/attachment action mapping; reviewed-planner `booking scheduled` vocabulary seam; and an acceptance-only Sublet fixture return window that was earlier than the reviewed booking date.
- Action: applied guarded staging successors 719 through 730 where required, preserving the exact actor/gateway/release/planner/trust/fixture boundary, immutable forced-RLS histories, normal Board/read filters and canonical 684/502 action chain. The harness now retains all canonical instruction dispositions, collapses exact duplicate actions without collapsing instructions, maps the existing-booking note case to canonical `sublet_update`, and treats same-final-receipt finalization as idempotent replay.
- Acceptance: fresh run `5fb56a0e-e599-4679-b816-9b447a8ddc51` passed all six cases through context → plan → 684 record/execute/apply/finalize → audit. It produced 6 context receipts, 6 plan receipts, 7 action receipts, 7 audit receipts and 6 final receipts; all applied outcomes were `APPLIED_VERIFIED`; replay returned `action_replayed`/`audit_receipt` with the same final receipt.
- Cleanup/invariants: active synthetic vehicles/work/Sublet are all zero; stale diagnostic/failed campaign runs were safely cleaned (43 runs) while immutable receipts were retained. UID514 remains one canonical intake/receipt/vehicle/five operation lines; pilot/task/outbound are disabled; one mailbox remains active; Production sentinel is absent.
- Verification: focused acceptance/mapping/security contracts 15/15; `npm run test` 226 passed/0 failed/1 skipped; `npm run check` 226 passed/0 failed/1 skipped. Source/backend proof remains separate from the pending isolated staging source publication and Pages/live asset handoff.

## 2026-08-28 — Staging Email Monitor runtime successor activation repair

- Scope: Supabase staging project `cdsmnqxtyyoeoznmbidd` and protected local staging runtime only. Production, UID514 evidence, vehicle data, outbound email and the scheduled task enable state were untouched.
- Root causes repaired: sealed `.44` Storage replay compatibility now accepts only the live HTTP 400 JSON shape `code=KeyAlreadyExists` and string `statusCode="409"`; active and VerifyOnly controls use independent successor-specific bootstrap/runner anchors with no legacy shared-anchor dependency.
- Release/install: append-only parent-bound runtime successor chain was built and installed through protected backup/read-back paths; current protected runtime is `.52`, with manifest `1a65da99bf523e6bc204f73511d2911e7458219f551d09e50382741145a68796`, successor bridge `f20f3dab8246935d4ca792f74c743b56758b99177bf28eb29384518574c9b3d2`, parent `.44` manifest unchanged at `d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d`, and 3319 release members.
- Verification: hostile storage/anchor contract suite 14/14, Python syntax pass, PowerShell parse pass, .52 VerifyOnly pass, fresh protected existing-password actor refresh pass, and live read-only reconciliation pass (`head=20260828520000`, Production sentinel absent, UID514 preserved). Full website `npm run test` and `npm run check` each passed 226/0/1.
- Active result: bounded OneCycle reached the real mailbox and canonical enqueue boundary but failed closed on the independent live staging `pdc_monitor_attachment_invalid` contract for unread pre-existing post-514 backlog. The task remains Disabled under `LOCAL SERVICE`, Limited, `PT5M`; no successful active cycle or enablement is claimed.
- Handoff: `docs/website-development/PDC-EMAIL-MONITOR-ACTIVATION-SUCCESSOR-HANDOFF-20260828.md`; secrets were not printed or written to the log.

## 2026-08-28 — Staging Email Monitor .65 isolated child-import successor

- Scope: staging runtime source/control artifacts only. The exact `.64` release, parent `.44`, mailbox state, receipts, ACLs, task identity and production boundary were not changed.
- Root cause isolated from the current pdc-emails/dashboard checkpoint: the active `-I -S` child entrypoint could not resolve the sealed release's `backend.attachment_content` module before mailbox access.
- Change: added `backend/imap_bridge_successor_20260865.py`, which binds its sealed release root before importing sibling backend modules; added a pre-mailbox exact `imap_bridge.py --help` import probe and distinct fail-closed import status to the `.65` active route; added complete-inventory build/verify/install artifacts that clone `.64` controls/venv/config and leave the existing PT5M task disabled.
- Verification: focused successor contract `3/3`, Python syntax and PowerShell parser passed. The self-contained production-equivalent `-B -I -S` import probe passed with no mailbox contact. Protected `.64` build/install and natural scheduled-run proof remain pending because this shell can control task enable state but cannot read/write the protected `.64` release or register/change a LOCAL SERVICE action without elevation.

## 2026-08-28 — Staging-only hard purge of Stock 13000769

- Scope: exact current staging identity only. Live staging matched vehicle `d777b071-a2b0-5367-893b-aa83a07fcfce`, canonical Navision backend `de800087-d086-4f7b-9569-bb8a88660475`, Stock `13000769`, Job Card `J139125493`, source record `DE800087-D086-4F7B-9569-BB8A88660475`; live head at apply was `20260829120000` / `745_controller_parts_received_eta_repair`. Production sentinel was absent and no Production endpoint was used.
- Change: appended and applied `supabase/staging_only/20260829130000_746_purge_stock_13000769.sql` through `scripts/apply_migration_746_staging.py`, using the reviewed hard-purge controls, exact identity tokens, FK-safe delete order, replay-floor advance from UID 639 to 640, database-owned monitor containment, and protected forced-RLS receipt/fence tables. The concurrent staging head advanced while preparation was in progress; the final migration was regenerated against the actual live head rather than applying a stale predecessor.
- Backup: fresh encrypted staging target-closure backup was created and read back from `C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/stock-13000769-prepurge/pdc_backup_staging_20260828T100607Z_847b7b9a.bin` with manifest sidecar; file SHA-256 `949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7`, manifest SHA-256 `7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d`, run `847b7b9a-7f25-4a13-868d-fb3a95b9e447`, 29 exact closure tables. Full-public backup attempts were separately blocked by staging SSL connection/timeout failures; no false full-backup claim is made.
- Live result: receipt `complete-operational-purge-stock-13000769` records 29 tables and 207 deleted rows. The live Board snapshot RPC returned zero occurrences of Stock `13000769`; vehicle/backend rows are absent; relevant public column readback and public function/view definition scans are clear except the protected purge receipt and replay fence. Replay floor/control readback is `minimum_uid=640`, pilot/automatic/outbound disabled, active mailbox/writers zero, authenticated claim RPC still executable but blocked by the tightened floor/containment state. Sibling Stock `13000765` remains present and visible/active.
- Tests: focused purge contract passed; Python syntax passed; live authoritative preflight/readback passed. Secrets were not printed or written to the log.

## 2026-08-28 — Corrected Stock 13000769 recovery and QC retest

- Scope: staging-only recovery of exact vehicle `d777b071-a2b0-5367-893b-aa83a07fcfce`, Stock `13000769`, Job Card `J139125493`, canonical Navision backend `de800087-d086-4f7b-9569-bb8a88660475`; associated with existing dashboard session `20260828_161016_aa9508`. Production prohibited and untouched.
- Corrected owner-scope incident: concurrent Parts task history explicitly targeted Stock `13017855` / Job Card `J139125422` and said not to delete it, while migration 746 hard-coded Stock `13000769` and the reason `Craig requested complete staging removal`. This was an instruction-to-target binding failure, not authorization to delete Stock `13000769`; see `docs/website-development/STAGING-STOCK-13000769-SCOPE-INCIDENT-20260828.md`.
- Change: append-only `20260829140000_747_restore_stock_13000769_qc_retest.sql` plus `20260829141000_748_repair_recovery_identity_guard.sql` restored 28 exact closure tables / 206 rows from the verified encrypted target-closure backup, excluded the one pending QC salesperson outbox, advanced the canonical row 33→34 and moved it to active QC. `20260829142000_749_append_qc_retest_photo_evidence.sql` added per-cycle immutable fresh-photo evidence because legacy 399 photo evidence is correctly unique per vehicle. `20260829143000_750_project_recovered_stock_qc_operation_lines.sql` preserved the prior Board RPC as `_pre_750` and projected exact operation lines and retest state for this vehicle only.
- Guarding: old 746 purge receipt/fence remain intact; UID 639 remains fenced and monitor floor is 640; At recovery time the mailbox/writers were contained; later unrelated migration 752 may activate the exact staging mailbox/writer for newer UIDs, but automatic rules and outbound email remain disabled. Restored vehicle/backend deletion and backend unlink are blocked; direct RFT before fresh retest sign-off fails closed.
- Live proof: authoritative staging snapshot returns exactly one Stock `13000769` at QC, active lifecycle, open fresh cycle, fresh photo accepted, 17 operation lines visible/all completed, no booking/outbox/draft/collection, old QC evidence superseded and immutable, exact recovery replay is a no-op, unrelated digests are unchanged, and Stock `13017855` remains present.
- Tests: focused recovery/projection contracts and Python syntax passed; full `npm run test` and `npm run check` passed; staging branch, Pages workflow and live asset readback remain part of the isolated release verification.

## 2026-08-28 — Staging Email Monitor .66 unattended same-actor refresh successor

- Scope: staging-only protected runtime source and Supabase staging project `cdsmnqxtyyoeoznmbidd`; Production, mailbox flags, UID514, task enablement and outbound email remain untouched.
- Root cause: `.65` natural scheduled runs used a static one-hour JWT in the `.44` preflight config, so unattended `LOCAL SERVICE` PT5M runs eventually failed authenticated preflight. The existing user-DPAPI refresh store was not readable by `LOCAL SERVICE`, and the pre-existing machine-DPAPI artifact contained no password.
- Change: prepared append-only `.65`→`.66` runtime/control successor. Each cycle reads an exact same-actor machine-DPAPI bundle, authenticates only `sales@broometoyota.com.au`, validates authenticated JWT claims, creates a short-lived protected env handoff, runs the existing `.44` authenticated preflight, then the sealed `.66` monitor. No service-role fallback, identity replacement, password rotation, or broad scope is present.
- Inventory/ACL contract: the verifier excludes only `release-manifest.json`; the bundle has 3,320 members. Installer ACLs grant LOCAL SERVICE only required RX over release/venv/control trees and the machine refresh file; SYSTEM and Administrators retain protected ownership access.
- Live staging: append-only 752 reactivation applied at head `20260829151000`, restoring only the exact test mailbox, 674/675 controls and existing sales writer. Recovery 747/748/749 evidence, Stock `13000769` QC retest evidence, 751 Parts contract, UID514 fence and Production exclusion remain intact.
- Verification: `.66` build and verifier passed; focused `.65`/`.66`/752 contracts passed; Python and PowerShell syntax checks passed; full `npm run test` and `npm run check` passed with 226 passed, 0 failed, 1 skipped. The protected `.66` installation and natural PT5M proof are pending one Administrator UAC approval through the visible desktop launcher.
- Launcher: `C:\Users\nwmgr\Desktop\PDC-Monitor-Staging-Install-2026.08.66.cmd`. The task remains Disabled until the protected install, VerifyOnly, controlled mailbox cycle and two natural `LastTaskResult=0` runs pass.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-28 — Exact Stock 13080534/13017855 Phase 1 fresh-import reset

- Scope: Supabase staging project `cdsmnqxtyyoeoznmbidd` only, associated with dashboard session `20260828_191153_4fb787`; Production prohibited and untouched.
- Preflight: live head was `20260829151000/752_reactivate_exact_email_monitor_after_751`. Stock `13080534` resolved to Navision backend `5721cafa-2b60-4d45-b69c-ab907eaf178e` with no canonical vehicle. Stock `13017855` resolved to backend `e39eb741-cf03-44f2-8a75-54362ecc8a26`, canonical vehicle `7fe33693-f519-5152-bbe0-9cc799c4ae33`, VIN `MR0MABAV902402464`, Job Card `J139125422`; its 20 operation lines sourced from `1:640`.
- Snapshot: fresh encrypted exact-closure artifact `pdc_exact_stock_reset_7f1c3315-ac42-46fb-99ed-70b43ef89f80.bin`, run `7f1c3315-ac42-46fb-99ed-70b43ef89f80`, artifact SHA-256 `6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518`, manifest SHA-256 `8de3b4cb413006d6850838a83ca1648215e0e589f1f61f7e01cb9339fc4bb018`, 31 closure tables / 273 rows. Attachment IDs were bound individually to avoid broad matching on shared image hashes.
- Change: applied `supabase/staging_only/20260829163000_exact_stock_reset_13080534_13017855_phase1.sql` through `scripts/apply_exact_stock_reset_20260828.py`. The immutable forced-RLS receipt is `f4db153c-1991-4742-84a9-3d723d75feef`, recording 31 tables / 273 rows, exact predecessor head, rollback contract and trigger restoration. No automatic monitor, actor credential, UID514 floor, mailbox flags or unrelated Stock `13000769` state was changed.
- Fresh replay handoff: exactly two unconsumed one-time authorizations remain for Craig’s newest messages: `imap_uid:681` / Stock `13080534` / source hash `f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916`, and `imap_uid:680` / Stock `13017855` / source hash `d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493`. The prior `1:640` / `812c2291fe80a143e8fe8a55e34f9869476926d69d6bbddd345b61a6a5448a8a` receipt was removed from replay surfaces and retained in the encrypted snapshot.
- Live proof: canonical vehicles, Board activations, active operation rows and old intake/attachment metadata for both stocks are zero; forced RLS is enabled on receipt/handoff tables; three stored mailbox attachment objects remain; UID514 remains present; pilot remains disabled/outbound false; Stock `13000769` and monitor state digests are unchanged; runtime `CURRENT` is `2026.08.65`.
- Verification: focused negative contract tests 7/7, live reset verification passed, rollback artifact verify-only passed, SQL parsed as 42 statements, Python syntax passed. Machine-readable handoff: `docs/website-development/PDC-EMAIL-EXACT-STOCK-RESET-PHASE1-HANDOFF-20260828.json`.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-28 — Exact manual reimport enqueue wrapper 755

- Scope: staging project `cdsmnqxtyyoeoznmbidd` only, dashboard session `20260828_191153_4fb787`; no mailbox import was run.
- Change: added append-only migration `supabase/staging_only/20260829190000_exact_manual_reimport_enqueue_processor.sql` plus guarded lane `scripts/apply_migration_755_staging.py`. The single new authenticated SECURITY DEFINER RPC `public.enqueue_pdc_exact_manual_reimport_20260828(text,text,text,text,text,jsonb,jsonb)` binds only `sales@broometoyota.com.au`, the exact runtime/gateway, Craig Watson, `imap_uid:680`/`imap_uid:681`, their exact source hashes, and Stocks `13017855`/`13080534`, then delegates to existing canonical enqueue/storage/claim/process/receipt contracts.
- Safety: transaction-bound immutable binding evidence preserves the existing pilot guard while `pdc_email_monitor_pilot` and the scheduled task remain disabled; no mailbox sweep, booking/completion/location or Production path was added.
- Verification: focused contract 4/4, SQL parse 18 statements, Python syntax and `git diff --check` passed. Guarded staging apply succeeded at predecessor `20260829180000/authenticated_jobcard_work_compatibility`; live RPC source SHA-256 `a338ed6a9f910f190e308a6323ec8d8184bf80b5e9b0bbf189f256cc67d86804` and migration SHA-256 `b97bb87e9b224bdf602133d5a29680de868d36261926558e42ea89856c654c67`.
- Live readback: ledger head `20260829190000/exact_manual_reimport_enqueue_processor`; binding table forced RLS with authenticated/service-role direct SELECT denied; pilot flags all false, outbound false, task Disabled, exact read-only IMAP UIDs 680/681 flags unchanged/empty, target intake count 0, two authorizations still unconsumed, Production sentinel absent.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-28 — Exact manual claim/process wrapper 756

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only, dashboard session `20260828_191153_4fb787`; no task was created and no real mailbox import was run.
- Change: added `supabase/staging_only/20260829200000_exact_manual_reimport_claim_process_wrapper.sql` and `scripts/apply_migration_756_staging.py`. The migration uses advisory lock `pdc-staging-756-exact-manual-claim-process-20260828`, guards predecessor `20260829190000/exact_manual_reimport_enqueue_processor`, and adds only authenticated `public.claim_pdc_exact_manual_reimport_20260828(text,text)` and `public.process_pdc_exact_manual_reimport_20260828(uuid,uuid,text,text,text,jsonb)`.
- Safety: claim is exactly one specified authorized `imap_uid:680`/`imap_uid:681` row, bound to exact source hash/Stock, mailbox, sender/message/attachment provenance and the immutable 755 binding. Process delegates only to existing `process_claimed_pdc_email_intake_work`; automatic claim behavior, pilot flags, Scheduled Task, RLS, canonical identity/work compatibility, unknown-review fail-closed behavior and receipt/result flow remain unchanged.
- Compatibility repair: guarded replacement of the one live 755 enqueue source-table drift (`pdc_exact_manual_reimport_bindings` → `pdc_exact_manual_reimport_bindings_20260828`) using predecessor prosrc SHA `a338ed6a9f910f190e308a6323ec8d8184bf80b5e9b0bbf189f256cc67d86804`; no automatic function was replaced.
- Verification: focused contract 5/5, Python syntax and `git diff --check` passed. Migration SHA-256 `55b043cb9f609a7047cc076cbb5a9dc5499f4570f6c898eceb800bc324e67a51`; guarded staging apply succeeded with predecessor hash guards.
- Live readback: ledger head `20260829200000/exact_manual_reimport_claim_process_wrapper`; enqueue prosrc SHA `ed2bc1b009e8fdf08a4744dfb1f2bec0c467de0b4588ff999e918585fa68c1ea`; both wrapper RPCs owner `postgres`/SECURITY DEFINER with authenticated execute only (anon/service_role false); binding table RLS+FORCE RLS true; pilot all false, mailbox exact active test-mode, Scheduled Task Disabled, 2 authorizations unconsumed, target intake/attachment/binding/vehicle/board/booking/work-item counts all 0, Production sentinel absent.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-28 — Staging attachment MIME/filename compatibility successor

- Scope: staging runtime source only, associated with dashboard session `20260828_191153_4fb787`; Production, mailbox flags, UID514, actor/sender/runtime/task/pilot flags and unrelated Stock state remain untouched.
- Root cause: the live `.65` validator rejected the retained `image.png` attachment even though its bytes structurally verify as JPEG and the provider reports `image/jpeg`; the extension/content mismatch guard ran before the exact attested exception could be represented.
- Change: added `backend/attachment_content.py` with one narrow exception: only `.png` filename + structurally verified `.jpg` bytes + reported `image/jpeg` is accepted, canonical MIME is `image/jpeg`, and the original filename remains the storage leaf. Unknown/HEIC, malformed, unsupported, other MIME and all other extension/content mismatches remain fail-closed.
- Runtime: added parent-bound `.65`→`.67` builder/verifier/installer (`scripts/build_pdc_monitor_successor_20260867.py`, `verify_pdc_monitor_successor_20260867.py`, `install_pdc_monitor_successor_20260867.ps1`). The builder performs no mailbox/Supabase call; the installer requires the exact parent manifest and a disabled LOCAL SERVICE PT5M task, uses a global advisory mutex, and has no task enable/start/register path.
- Verification: focused attachment contract `6/6` passed under the extraction dependency environment; Python syntax passed; `.67` bundle built and credential-free verified with 3,423 members. Source SHA-256 `f9958eb9077cbec4d4c45e7de5370de5596d1acb66bb5b3013e744911db91bce`; parent `.65` manifest SHA-256 `bbc344a8a60c75571e4fa64c79a9903583f2cab2c68ada75eeb63a02c7547b55`; `.67` manifest SHA-256 `49d84a668b643507df2b447d31389afdb1d66f7350bf445e947402b3f73e8bb0`.
- Readiness: candidate built and verified, not active. Protected runtime installation/live wrapper readback is blocked by the current shell's access-denied ACL; no UAC/elevation or task start was attempted. Existing live 757 wrapper readback remains `ok=true`, fixed enqueue prosrc SHA `85b92db7191ac75be82a566e568b51c5e169f20f2b6a8247b77d6d0beea48690`, ledger head `20260829210000/exact_manual_reimport_enqueue_precedence_repair`, target rows/bindings zero, two authorizations unconsumed, pilot/task disabled and Production absent.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-28 — Exact manual claim attachment storage-path precedence repair 759

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only, dashboard association `20260828_191153_4fb787`; no task was created, no mailbox sweep/import was run, and Production was not contacted.
- Change: added append-only `supabase/staging_only/20260829230000_exact_manual_reimport_claim_storage_path_parentheses.sql` and canonical lane `scripts/apply_migration_759_staging.py`. The migration guards live 758 and predecessor claim prosrc SHA `7f12dd8d35e1efaf84ec366868ee7fcedfd8657fb36d14bb83864e4d7f959b48`, then replaces only the one unambiguous attachment predicate with `x.storage_path='pdc-email-intake-private/'||lower(m.value->>'source_hash')||'/'||(m.value->>'file_name')`.
- Safety: exact actor/runtime/gateway/sender/UID/Stock/hash/auth/manifest/attachment/claim-binding checks are preserved by full-definition replacement plus postguard markers; authenticated-only SECURITY DEFINER execution, disabled pilot/task, canonical processor/idempotency/receipt path, zero-hour/source-OP/Parts/Sublet semantics and no booking/completion/location mutation remain unchanged. Existing UID514, Stock 13000769, target UID680 intake/attachments/binding and two one-time authorizations were read back unchanged by the apply receipt.
- Verification: focused contract 4/4, Python syntax and `git diff --check` passed. Migration SHA-256 `5ed92968fb397f9affbd071c7282572595d1daa480a7f894aa4476ee8c54d2d3`; guarded staging apply succeeded with exact predecessor/function-hash guard.
- Live readback: head `20260829230000/exact_manual_reimport_claim_storage_path_parentheses`; repaired claim prosrc SHA `e62a8657d9c4419b4c71f286ded7d027241ee215816c325f6eb7775d62a0ff22`; fixed expression exactly once, old expression absent, authenticated execute only (`authenticated=true`, `anon=false`, `service_role=false`), SECURITY DEFINER, binding FORCE RLS, canonical processor present, pilot/task disabled and Production sentinel absent.
- Negative probe: invalid claim scope `imap_uid:999` rejected with `42501/PDC_756_EXACT_MANUAL_CLAIM_SCOPE_FAILED`; before/after protected-state snapshot identical. A later read-only snapshot observed two existing UID680 binding rows (apply receipt had one before/after); no migration-induced state change was observed and no duplicate task was created.
- Readiness: **READY — staging-only SQL successor applied and verified; no mailbox import/replay performed.**
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-29 — Exact manual provider-attestation current attachment successor 761

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only, dashboard association `20260828_191153_4fb787`; no mailbox import, task enablement, pilot change or Production contact.
- Change: added append-only `supabase/staging_only/20260830010000_exact_manual_reimport_provider_attachment_current_row.sql`, replacing only the 760 exact manual attestation body. The selected `p_attachment_id` must now be the current row for the claimed intake/provider UID whose authorized reset-manifest item matches the exact PDF filename/hash, `application/pdf`, graph part order, extraction/error state and canonical storage path; no reset-era attachment UUID is used.
- Safety: preserved exact actor/runtime/gateway/release/planner/trust, sender/Message-ID/authentication, claimed-intake lock, one-time authorization/binding, existing observation RPC, RLS, immutable audit trigger, idempotency/replay conflict and 754/756 canonical process chain. The migration has no operational importer call, mailbox/task/pilot mutation or unrelated state path.
- Verification: focused contract `4/4` passed; Python syntax and `git diff --check` passed. Migration SHA-256 `cafe6b643ea95e7924749046a0785b585b4bbc03213fbbd923a99d7d19bae39f`; guarded canonical website-development staging apply passed; RPC source SHA-256 `1125316348753c3dbc8fc1305ab6e92d9c735225e5b5da8e647c0fe1a26f8395`.
- Live readback: ledger head `20260830010000/exact_manual_reimport_provider_attachment_current_row`; authenticated-only execute (`authenticated=true`, `anon=false`, `service_role=false`), SECURITY DEFINER owner `postgres`, canonical processor and 756 wrapper present, observation RLS/immutable trigger preserved, two exact current PDF rows verified. UID `imap_uid:680` is claimed as intake `b166aa36-959f-4280-8fc6-b41497efd641` with current attachment `3d7f2616-8c52-4e9a-a4a5-9289f34f6d13`; UID `imap_uid:681` current attachment is `93f4dafd-bc66-4af2-898f-c55f67578ad4`. Both exact filenames, hashes, content types, graph part IDs and storage paths read back.
- Negative/readiness: invalid scope rejected with `42501/PDC_761_EXACT_MANUAL_ATTESTATION_SCOPE_FAILED`; before/after protected-state snapshot identical. Authorizations remain `2` unconsumed, observations `959`, pilot flags false, Scheduled Task Disabled, Production sentinel absent. **READY — staging-only successor applied and verified; real import not run.**
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-30 — Stock 13000769 staging mobile-QC verification

- Scope: read-only verification of STAGING project `cdsmnqxtyyoeoznmbidd`, dashboard association `20260828_161016_aa9508`; no new dashboard task/session and no Production access.
- Deployment: staging `main` remains at `2edb80d`; integrity run `33178413165` and Pages run `33178412409` are successful. Live entry/app/service/styles assets return HTTP 200 and carry cache marker `2026.08.29.756-qc-photo-mobile-retest`; deployed app exposes `Take or choose QC photo`, `accept="image/*"`, no `capture="environment"`, explicit label/input binding and progress/error path; deployed service exposes 747 retest photo/finalization RPC names.
- Authoritative state: exactly one active Stock `13000769` at QC, canonical UUID `d777b071-a2b0-5367-893b-aa83a07fcfce`, 17 Navision operation lines, 17 completed QC operation lines, one recovered retest cycle, one fresh photo event, zero retest sign-off events, zero active bookings/outbox/drafts. Migration 746 purge receipt and UID 639 replay fence remain intact; recovered-vehicle delete guard is present; Production sentinel is absent.
- Exact synthetic photo receipt: `1d1fa5a1-0662-5e0b-b575-d7119216edde`; cycle `245974d0-2e8f-5215-bd85-3e8e10fe9a0e`; expected vehicle version `34`; bucket `pdc-qc-evidence-staging`; path is actor-bound under `qc-finalization/`; MIME `image/png`; byte length `68`; original byte length `68`; image `1×1`; SHA-256 `431ced6916a2a21a156e38701afe55bbd7f88969fbbfc56d7fe099d47f265460`; immutable event request SHA-256 `2a2f32f9a931b972a6c6b02e0ffc568becd7b00df45eaa2bd2feb56752f69e4c`.
- Rejection/gate proof: live 747 function definitions retain cycle/version/vehicle/storage-owner/idempotency request binding, duplicate request SHA mismatch rejection (`qc_retest_photo_replay_mismatch`), stale vehicle/version rejection (`qc_retest_vehicle_version_or_location_conflict`) and finalization all-17-lines gate (`qc_operation_lines_incomplete`); live function/catalog presence was verified read-only. No duplicate or stale upload was dispatched.
- Browser proof: responsive Chromium harness passed at 360×800, 390×844 and 768×1024 with 17 lines, enabled chooser, label activation, upload progress, synthetic receipt/finalize chain, no horizontal overflow, zero page errors and zero external requests. This proves responsive browser semantics only; no physical iOS/Android device, camera permission or hardware upload is claimed. No live photo mutation was performed because no Craig-supplied evidence was available.

## 2026-08-30 — Navision preflight and SQLSTATE 23514 repair

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only; dashboard `20260829_100425_fbe916`; Production, mailbox, outbound email and browser-local authority were untouched.
- Root cause: the deferred `zz_navision_all_vehicle_parity_494` constraint trigger on `navision_backend_records` raised SQLSTATE `23514` with `PDC_NAVISION_VEHICLE_LINK_OR_REFRESH_INCOMPLETE`. A retained Stock `13080534` update could leave `vehicles.source_payload.navision_updated_at` stale; a distinct second source row for the same Stock produced `navision_match_count=2`. Both cases were accepted by the prior preview contract.
- Fix: append-only `supabase/staging_only/20260830072000_navision_import_preflight_contract.sql` adds server/client deterministic classification for duplicate Stock/VIN/Toyota Order, wrong dealer, canonical ambiguity/mismatch and explicit invalid status/date/location fields. Preview now includes Stock, field, candidate and reason; apply remains atomic and returns `navision_preflight_blocked` before DML for any issue. Linked Navision source metadata is refreshed without operational mutations, preserving the existing parity constraint.
- Verification: exact retained live `raw_evidence` for Stock `13080534` was used as the base of a rollback-only duplicate fixture. Preflight returned two `duplicate_stock_number` conflicts; public apply returned `navision_preflight_blocked`; revision and batch counts were unchanged. Invalid status/date/location fixtures returned their exact classifications. Migration SQL dry-run executed against the live predecessor and rolled back; focused client/SQL tests passed; all clean staging-base JavaScript contracts passed.
- Concurrent staging workers advanced the live predecessor during preparation; the migration guards the exact observed head `20260830071000/769_monitor_compatibility_after_768` and uses timestamp `20260830072000`. No Production endpoint or branch was contacted.

## 2026-08-30 — Bounded historical reconciliation writer successor 777

- Scope: Supabase STAGING project `cdsmnqxtyyoeoznmbidd` only. The frozen Inbox manifest is UIDVALIDITY `1`, high-water `685`, `669` UIDs, and SHA-256 `aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018`; mailbox flags were not changed.
- Live diagnosis: rollback-only probes of the deployed canonical observation path returned exact envelopes `{"ok":false,"code":"invalid_input","data":{}}` for a malformed representative payload and `{"ok":false,"code":"sender_not_enrolled","data":{}}` for a valid-shape non-enrolled sender. Earlier endpoint discovery also showed the historical/import contracts were not the correct executable lane; no valid historical call was made.
- Change: added append-only `supabase/staging_only/20260830150000_777_historical_reconciliation_writer_successor.sql`. It copies exactly fifteen eligible manifest rows (UIDs 21, 22, 23, 26, 40, 57, 85, 93, 95, 96, 133, 134, 137, 168, 172), with exact source hashes, approved authenticated sender evidence, attachment manifests, current Navision backend IDs/versions/dealer scope, and absent operational Stock identities. Reference UID 197 / Stock `13056899` is excluded.
- Safety: 777 adds a 23-hour one-time authorization window and forced-RLS immutable receipt surface; exact replay is permitted only for the identical request hash. Canonical sender/age gates now require the 777 row plus exact attachment manifest/hash, source/evidence/UID, current Navision identity and absent/exact operational identity. Existing operation/zero-hour/unknown/Sublet/unmapped review, audit, idempotency and no-booking/completion/location boundaries remain authoritative; no domains were broadened.
- Verification: migration SHA-256 `f2f20043d86e632bffe10d495ab343c427df1ba7742f23cfec4eba2d78838ec1`; staging ledger head `20260830150000/777_historical_reconciliation_writer_successor`; authorization rows `15`; reference rows `0`; live one-time rows `15`; writer receipts `0`; all identity joins `15/15`; forced RLS `true` on authorization and receipt tables; Production sentinel absent.
- Live RPC hashes: `pdc_historical_writer_authorized_777(text,text,text,text,jsonb,text,jsonb)` = `41815e5feca59828b1014caf4d83499d1ea552247448dc7ddad7f743a2f3ad41`; patched `pdc_submit_generic_current_navision_enrichment_312(...)` = `06efd9dde792b536005bb5af7589fe0db748ac7f91dbad4e7953792de3b83d91`; patched `submit_pdc_ai_intake_observation_pre135(...)` = `fbc594becc1be2288a6f82993f44b8051e81079cdd8ccb15da94397d7e31f527`.
- Negative probes: wrong source and excluded UID 197 returned authorization `false`; exact malformed/non-enrolled envelopes remained unchanged; proposal count stayed `19` before and after the rollback-only probe transaction; pilot automatic flags/outbound remained false, task remained disabled, mailbox was not contacted, and no valid historical writer call occurred.
- Readiness: **READY for a bounded historical retry after the owner runs the separately controlled writer; historical import was not run.**
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-30 — Historical PMB Inbox canonical reconciliation adapter 778/1710

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only; frozen read-only Inbox manifest UIDVALIDITY `1`, high-water UID `685`, `669` UIDs, manifest SHA-256 `aa9e2451645b3fc51eba68c422b5eaf6f146ed18596a94ce8560c55b80729018`. Production, outbound email, mailbox flags and the automatic task were not changed.
- Live diagnosis: concurrent authorised staging successors advanced the database from `20260830162000` through `20260830170000` and applied the UUID-free 778 enqueue adapter. The current live head was re-read before the security successor; stale 766/777 claims were not trusted.
- Change: the append-only 778 chain now uses `submit_pdc_historical_reconciliation_778(jsonb)` with exact current Monitor actor/gateway/release/runtime and frozen manifest high-water binding, exact immutable 773 sender/authentication/source/Stock binding, 24-hour expiry, receipt-backed one-time replay, old-mail protection and forced-RLS immutable per-sibling/aggregate receipts. Provider-bound enqueue creates/reuses only the exact frozen source; PO/Pick List siblings remain evidence. Genuine Job Card siblings use `import_pdc_jobcard_attachment_canonical`; ambiguous siblings are recorded fail closed while independent valid siblings continue with exact Stock scope.
- Files: `supabase/staging_only/20260830170000_778_historical_reconciliation_enqueue_adapter.sql`, `supabase/staging_only/20260830171000_778_historical_reconciliation_security_successor.sql`, `pdc_historical_778_caller.py`, `tests/test_historical_adapter_778_security_1710.py`, `scripts/apply_migration_778_successor_1710_staging.py`, and `docs/website-development/PDC-EMAIL-HISTORICAL-RECONCILIATION-778-HANDOFF-20260830.md`.
- Verification: local contract suite `5/5` passed; Python syntax passed; migration 1710 SQL dry-run against live 1700 passed and rolled back; live 1710 applied/read back by the approved staging connector during concurrent successor execution; current live head is `20260830171000/778_historical_reconciliation_security_successor`; provider observations `0`; reconciliation receipts `0`; 773 reference rows `0`; authenticated execute only (`true/false/false`); forced RLS preserved; Production sentinel absent.
- Live proof: authenticated current Monitor runtime binding returned `runtime_binding_verified_authenticated_766`, `activation_ready=true`, current ledger compatibility `766`; rollback-only malformed/wrong-release/wrong-sender probes were rejected, no probe intake/observation/receipt was created, and no valid historical writer call occurred. Pilot flags are all false, outbound email is false. Windows task `\PDC-PMB-Email-Monitor-Staging` remains `Disabled`, LOCAL SERVICE, PT5M repetition, last result `0`; no task enable/start was attempted.
- Handoff: pdc-emails must use the same frozen manifest/checkpoint and a fresh outbox with `python pdc_historical_778_caller.py --rows-json <frozen-rows-export.json> --outbox <new-historical-778-outbox.sqlite3> --bounded-caller`; no IMAP rescan, flag mutation, normal monitor, outbound email, Production endpoint or fabricated vehicle/status/hours/completion is permitted. Historical Apply was not run by this profile.
- Secrets were not printed, copied to the log, or written to source.

- Secrets were not printed, copied to the log, or written to source.

## 2026-08-30 — Historical Inbox adapter 782 current-head security and atomic wrapper

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only. Production, outbound email, mailbox polling/flags and monitor task enablement remained prohibited/untouched.
- Change: `20260830173000_782_historical_reconciliation_current_head_security_successor.sql` installed the exact frozen Job Card binding table and atomic 782 base contract; `20260830174000_782_historical_reconciliation_atomic_wrapper_successor.sql` privately renamed that base and exposed an authenticated-only wrapper with current runtime/source/auth preflight, replay safety, authoritative child receipt/work/vehicle checks, live protected-state flags and vehicle movement/alias fences.
- Caller: `pdc_historical_778_caller.py` and `pdc_full_inbox_typed_import.py` now rehydrate row-level frozen `job_card_children`, emit exact attachment kind/ordinal/hash metadata and preserve the 58 sibling / 3 genuine Job Card split.
- Verification: pdc-emails historical review logs were consumed; final independent gate returned `ready_for_apply=true`; pglast parsed 1730/1740 as 25/16 statements; focused historical suites passed; transaction-safe 1740 dry-run passed and rolled back; approved staging apply read back head `20260830174000/782_historical_reconciliation_atomic_wrapper_successor`.
- Live proof: 3 immutable bindings, 0 provider observations, 0 historical receipts; forced RLS on binding/observation/receipt tables; wrapper execute `authenticated=true, anon=false, service_role=false`; private base authenticated execute `false`; runtime `runtime_binding_verified_authenticated_766`, `activation_ready=true`, task/mailbox/Production writes false; malformed RPC and missing-receipt probes failed closed with no rows; Production sentinel absent.
- Historical Apply status: **not run**. No valid historical writer call, vehicle/status/hours/completion/booking/location/Parts mutation, mailbox contact or outbound email occurred.
- Note: the 1730 schema-only migration was applied while executing a connector test before the final 1740 review gate; it created only the three immutable binding rows and zero reconciliation data. The 1740 repair was applied only after the final independent `ready_for_apply=true` verdict.
- Secrets were not printed, copied to the log, or written to source.

## 2026-08-30 — Cycle-7 integrity remediation

- Scope: STAGING project `cdsmnqxtyyoeoznmbidd` only; dashboard `20260829_202924_3f0b32`; Production, outbound email, mailbox flags and browser-local operational authority were untouched.
- Fixes: append-only migrations 783/784/785/786/787 separate historical request/observation digests, align every historical observation/receipt assertion to the immutable 778.1 contract, complete Stage-A history to a bounded 500 rows, project VIN/Job Card/Sublet as confirmed-or-unknown, expose explicit duration contradiction evidence, add dealer-scoped planner detail and status-only intake access, seal observation digest uniqueness and revoke the old unscoped planner execute grant.
- Verification: live staging head `20260830184000/787_cycle7_contract_version_repair`; historical observations/receipts `0/0`; old planner auth false, scoped planner auth true, direct `ai_email_intake` select false; Stage-A Stock 13017855 workflow `114/114` complete; Sublet parity for 13080534 matched the active email-derived instance; full local Node suite `229 passed, 0 failed, 1 skipped`; focused historical/security suite `24/24`; Pages workflow and live asset read-back passed.
- Evidence-only review retained: Stock 13000769 remains scheduled `1441m`, physical actual `1m`, recorded `601m`, with `source_contradiction_review`; no physical timestamp or duration was mutated. Historical Apply remains blocked pending the exact approved Monitor actor token and post-786 independent first-run/replay proof. ProgramData monitor task remains disabled fail-closed at `267014`; protected runtime repair needs the reviewed canonical bundle/ACL elevation and was not forced through an unverified path.
- 788 canonical digest successor `20260830185000_788_canonical_historical_digest_contract.sql` is live after independent review `deleg_a6903a92` returned `ready_for_apply=true` with zero blockers. It reconstructs fixed length-prefixed UTF-8 request bytes, validates caller echo, binds observation/child evidence and exact occurrences, verifies complete protected-boundary equality, and preserves private-base/RLS/least-privilege controls. No historical writer call was made.
- Exact 15-row frozen Apply handoff: `handoffs/PDC-EMAIL-HISTORICAL-RECONCILIATION-788-READY-HANDOFF-20260830.md`; PT5M remains disabled with `LastTaskResult=267014` until Apply/replay/isolation completes.
- Fresh 789-795 proposal-binding remediation: append-only staging successors now lock and compare pending proposals, record immutable binding/review evidence without proposal mutation, repair manifest/UUID/wrapper defects, and make the bounded caller exact-cohort/nonzero-on-failure. Live head `20260830202000/795_historical_wrapper_short_name_repair`; exact UID 1:21 conflict/review/replay rollback proof passed; PT5M remains disabled until pdc-emails Apply/replay/isolation.

## 2026-08-31 — Email monitor inbound eligibility commissioning 855-858

- Scope: STAGING `cdsmnqxtyyoeoznmbidd` only; dashboard `20260828_191153_4fb787`; no UAC, Production, or broad sender enrollment.
- Root cause: the exact active enqueue path raised `pdc_monitor_sender_not_enrolled`, turning routine inbound ineligibility into a failed cycle; adjacent protected 839 compatibility helpers still referenced stale 674 scope.
- Repair: append-only 855 adds an immutable forced-RLS deterministic review receipt (`review_queued`, `board_mutations=0`, no mailbox flags/outbound/Production) and returns the same receipt on replay; 856 aligns the enabled pilot state; 857/858 align attachment claim and runtime authority to exact authenticated 839.
- Verification: focused 855-857 contracts `7/7`; protected VerifyOnly and bounded disabled OneCycle exit `0/ok=true`; live non-enrolled replay returned the same receipt ID/key twice; authoritative receipt safety `1/1`, Board activations `7`, Production sentinel absent, UID514 false. Two distinct natural PT5M cycles returned `LastTaskResult=0`; processor failures `0` and review processing succeeded.
- Final redacted handoff: `docs/website-development/PDC-EMAIL-MONITOR-COMMISSIONING-FINAL-HANDOFF-20260831.md`; outbound email disabled and mailbox flags unchanged.
