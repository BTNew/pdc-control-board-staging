# PDC-EMAIL historical reconciliation — final technical handoff

Date: 2026-08-31
Environment: STAGING only (`cdsmnqxtyyoeoznmbidd`)
Destination: pdc-emails session `20260828_191237_5e0e90`
Production: not contacted

## Outcome

The historical reconciliation technical path is live through migration `20260830254000 / 833_historical_operation_hours_correction_successor`.

The real public-wrapper rollback/replay regression passed `4/4` tests:

- all five renewed UIDs (`1:133`, `1:134`, `1:137`, `1:168`, `1:172`) through the public wrapper;
- exact replay with stable receipt/proposal identity;
- malformed authentication, wrong actor and wrong gateway fail-closed denial;
- zero persistent drift after rollback-only execution;
- UID `1:134` all-unknown-hours evidence readback.

No mailbox was accessed. No outbox was created or reused. No outbound email was sent. No Production endpoint or Production data was contacted.

## Unknown-hours correction

UID `1:134` has nine valid operation lines and every per-line `estimated_hours` value is NULL.

The immutable legacy child receipt retains its historical `estimated_hours_sum=0` as provenance only; it was not updated or deleted. Migration 833 adds the restricted, forced-RLS correction evidence table and public-wrapper readback overlay:

- authoritative estimated-hours sum: NULL;
- known-hours sum: NULL;
- known-hours count: 0;
- unknown-hours count: 9;
- hours coverage: 0;
- per-line hours remain NULL;
- explicit numeric zero remains distinguishable from unknown values.

The correction evidence row is protected by a BEFORE UPDATE OR DELETE immutable trigger and its postcondition. The canonical importer dependency is pinned by SHA-256 in the migration guard.

## Successors applied

- `831_historical_navision_refresh_successor`: narrow historical `pre171` to approved linked `pre_700` Navision refresh substitution.
- `833_historical_operation_hours_correction_successor`: immutable all-unknown-hours correction/readback overlay.

The 833 migration passed a real staging transaction dry-run with rollback before application. Relevant source commits include `b8d10b05`, `ddf2c180`, and `d3d6eed4`.

## Live security and containment readback

- staging guard: true;
- Production sentinel: absent;
- active renewal rows: 5;
- historical receipts: 5, exact renewed UID set;
- provider observations: 24;
- domain readbacks: 5;
- active monitored mailboxes: 0;
- UID514 terminal receipt: present, one row;
- public wrapper execute: authenticated only;
- anonymous/service-role wrapper execute: denied;
- protected historical table SELECT grants to authenticated: denied;
- protected historical tables: FORCE RLS enabled;
- authenticated 802 runtime: `historical_runtime_binding_verified_contained_802`;
- runtime task_enabled: false;
- runtime mailbox_active: false;
- runtime mailbox_contacted: false;
- runtime production_writes: false;
- runtime uid514_processed: false;
- ten material conflict UIDs remain pending and fail-closed: `1:21`, `1:22`, `1:23`, `1:26`, `1:40`, `1:57`, `1:85`, `1:93`, `1:95`, `1:96`.

The Windows task `PDC-PMB-Email-Monitor-Staging` is now disabled, runs as `LOCAL SERVICE`, and retains its five-minute schedule. Its observed prior `LastResult` is `1`, not the historical required `267014`; the task was not run to manufacture a result.

## Verification

- Relevant static successor contracts: `16 passed`.
- Real live public-wrapper regression: `4 passed`.
- 833 staging dry-run: passed and rolled back with no persistent change.
- Final live source/RLS/auth/UID514/containment readback: passed except the Windows task LastResult mismatch above.

## Final review status

A fresh independent review was requested after the immutable-trigger and canonical-importer-pin repair. The technical evidence is complete, but a defensible `ready_for_apply=true` / `blockers=[]` final review cannot be claimed while the Windows task LastResult remains `1` instead of `267014`. Do not enable or run the task, access the mailbox, create an outbox, send email, perform historical Apply, or contact Production to resolve this.
