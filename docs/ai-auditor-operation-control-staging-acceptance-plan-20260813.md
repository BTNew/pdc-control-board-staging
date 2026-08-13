# Proposed staging acceptance — AI Auditor operation control

**Status:** candidate procedure only. It does not authorize migration 253 installation, migration 254 containment, identity/key provisioning, Pages deployment, pdc-monitor access, pilot activation or production work. Migration 251 remains unused and migration 252 is not an installation predecessor.

## Identity lock

Acceptance must bind all of the following before any preflight:

- final independently approved feature SHA;
- exact immutable Git blob and SHA-256 of migration 253, installer, forward-containment migration 254 and independent proof that migrations 251/252 remain unused;
- unchanged installed migration-250 blob/hash;
- authorised staging project `cdsmnqxtyyoeoznmbidd` and directly queried migration head;
- approved Pages/runtime SHA, if a later deployment is separately authorised;
- scoped ordinary Viewer service UUID/email and approved Administrator enrolment;
- gateway instance/key identifier generated through a separate audited secret-provisioning ceremony.

Any identity change invalidates the acceptance run.

## Preconditions

1. pdc-monitor UID 478 recovery and Email Monitor acceptance are complete and Craig authorises a coordinated staging window.
2. Craig separately authorises migration installation and any Pages deployment.
3. Rollback operator, observer, incident contact and stop authority confirm the whole window.
4. Current staging database backup/recovery evidence and migration ledger are captured read-only.
5. Gateway key material is generated outside source, chat and logs; only its identifier and public audit metadata enter evidence.

## Rollback-only rehearsal

In one explicit transaction that is always rolled back:

1. Verify project/staging sentinels, production-sentinel absence and exact migration head.
2. Run `scripts/apply_migration_253_staging.py --expected-commit <approved-full-sha>` in its default rollback-only mode; it must materialize immutable Git-object bytes and reject migration 251/252 state.
3. Inspect RLS, exact function signatures and grants.
4. Prove direct table DML denial for Viewer, Monitor, Importer, ordinary authenticated and service-role test principals.
5. Prove denial for all revoked generic migrations 176/178/189/201 RPCs and Administrator/booking/lifecycle functions.
6. Run typed fixtures for add, edit, split, combine, reorder and duplicate removal.
7. Prove complete ordered-set, aggregate-hours, department-hours and required-work receipts.
8. Prove protected manual/completed values and live bookings remain byte-identical.
9. Prove invalid/expired signatures and duplicate nonces/deliveries fail; exact replay returns only its immutable prior result; the same Telegram message/update re-signed under a fresh delivery UUID and nonce is denied by the global migration-230 registry.
10. Prove all-or-nothing failed Apply and failed Undo leave every mutable and audit surface unchanged.
11. Prove successful Undo restores exact ordering, effective values, aggregates and required-work identifiers.
12. Roll back, then verify database head and all sampled state are unchanged.

## Separately authorised installation acceptance

After successful rehearsal and a fresh approval:

1. Apply migration 253 only through the exact-SHA installer with named change/window/operator/observer/stop-authority and one-window confirmation; read back ledger, hashes, owners, grants, RLS, policies and publication state.
2. Provision the scoped Viewer identity and gateway key through audited ceremonies; never use Monitor credentials.
3. Exercise Review with no mutation, explicit Apply confirmation, one batch Apply and strict Undo using disposable staging fixtures.
4. Open two independently authenticated browser sessions. Prove each consumes `pdc_auditor_workshop_revisions`, invalidates once per run revision and refetches authoritative snapshots without exposing instruction content.
5. Test duplicate delivery and restart recovery through the real owning gateway.
6. Compare before/after vehicle, booking, location, user, completion and production-sentinel snapshots; all forbidden surfaces must be identical.
7. Capture receipts, revision IDs, timings, logs with secrets redacted, and exact source/runtime/database identities. Installation must leave the gateway-key table empty; key provisioning and runtime activation need a separate audited ceremony.

## Forward containment / rollback procedure

Before commit, rollback means aborting the installer transaction; its default rehearsal proves zero durable state. After migration 253 commits, do not delete the ledger or run ad-hoc down SQL. The reviewed recovery path is forward migration `254_disable_ai_auditor_typed_operation_control.sql` in a new approved window:

1. Stop the owning gateway and prevent queued retries; name operator, observer and stop authority.
2. Verify exact staging project, exact migration-253 head/name/statements/catalog and no 251/252/254/later row.
3. Rehearse migration 254 on a faithful clone or always-rolled-back staging transaction.
4. Apply 254 from an approved immutable SHA. It drains 253 work under bounded locks, records and deactivates every key, replaces public RPC bodies with fail-closed stubs, revokes all 253 API execution, removes revision Realtime access, and retains every delivery, plan, run, receipt, revision and operational overlay.
5. Reactivation or controlled recovery requires a later separately reviewed forward migration; never reset the ledger or silently restore old RPC bodies.

## Immediate stop conditions

- sentinel, project, migration-head, SHA or identity mismatch;
- any direct-table grant or callable revoked/generic RPC;
- any booking, vehicle lifecycle/location, user or completed-work mutation;
- partial Apply or partial Undo;
- signature/replay bypass;
- Realtime cross-dealer leakage, duplicate refetch storm or instruction-content publication;
- pdc-monitor contention or any need to inspect its state;
- any production or `main` impact.

On a stop condition: abort/roll back, preserve evidence, make no retry with changed bytes or identities, and request a fresh review/approval.
