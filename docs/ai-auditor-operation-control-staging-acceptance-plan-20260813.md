# Proposed staging acceptance — AI Auditor operation control

**Status:** NO-GO — planning only. This file does not authorize installation, migration 251 use or modification, migration 253 application, identity/key provisioning, Pages deployment, staging mutation, pdc-monitor access, pilot activation or production work.

## Identity lock

Acceptance must bind all of the following before any preflight:

- final independently approved feature SHA;
- exact SHA-256 of draft migration 253 and independent proof that migration 251 remains baseline-identical and unused;
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
2. Verify migration 253 in a disposable environment faithfully representing its documented predecessor contract, without using, installing, copying, or modifying migration 251.
3. Inspect RLS, exact function signatures and grants.
4. Prove direct table DML denial for Viewer, Monitor, Importer, ordinary authenticated and service-role test principals.
5. Prove denial for all revoked generic migrations 176/178/189/201 RPCs and Administrator/booking/lifecycle functions.
6. Run typed fixtures for add, edit, split, combine, reorder and duplicate removal.
7. Prove complete ordered-set, aggregate-hours, department-hours and required-work receipts.
8. Prove protected manual/completed values and live bookings remain byte-identical.
9. Prove invalid/expired signatures and duplicate nonces/deliveries fail; exact replay returns only its immutable prior result.
10. Prove all-or-nothing failed Apply and failed Undo leave every mutable and audit surface unchanged.
11. Prove successful Undo restores exact ordering, effective values, aggregates and required-work identifiers.
12. Roll back, then verify database head and all sampled state are unchanged.

## Separately authorised installation acceptance

After successful rehearsal and a fresh approval:

1. Apply reviewed migration bytes in order and read back ledger/hash/grants/RLS.
2. Provision the scoped Viewer identity and gateway key through audited ceremonies; never use Monitor credentials.
3. Exercise Review with no mutation, explicit Apply confirmation, one batch Apply and strict Undo using disposable staging fixtures.
4. Open two independently authenticated browser sessions. Prove each consumes `pdc_auditor_workshop_revisions`, invalidates once per run revision and refetches authoritative snapshots without exposing instruction content.
5. Test duplicate delivery and restart recovery through the real owning gateway.
6. Compare before/after vehicle, booking, location, user, completion and production-sentinel snapshots; all forbidden surfaces must be identical.
7. Capture receipts, revision IDs, timings, logs with secrets redacted, and exact source/runtime/database identities.

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
