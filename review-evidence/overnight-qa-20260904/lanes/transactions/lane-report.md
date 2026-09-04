# Overnight PDC QA / Acceptance Report — 2026-09-04

## Executive summary

Result: PASS

- Target: staging Supabase project `cdsmnqxtyyoeoznmbidd`
- Deployed UI: `https://btnew.github.io/pdc-control-board-staging/`
- Deployed SHA independently verified by the release lane: `85bdc68513e0c1c6efee110712731e9be958374b`; this lane exercised the live STAGING database and current deployed UI
- Synthetic prefix: `QA-OVERNIGHT-20260904`
- Synthetic vehicles: 15
- Scored functional assertions: 26 passed / 26 total (100%)
- Critical issues: 0
- High issues: 0
- Medium issues: 0
- Low issues: 0
- Production contacted: no
- Cleanup: verified; zero matching rows remain

The staging-only synthetic fleet exercised import/idempotency, canonical identity edits, location movement, Monday workshop booking and rescheduling, admin blocks, parts/work/sublet state, overlap behavior, Pit/QC gating, lifecycle archive/restore, authorization denial, stale-version denial, and idempotent replay. An approved temporary staging administrator then authenticated against the deployed UI at 360, 768, and 1440 px widths. The AUD-001 correction run subsequently captured a fixture-specific authenticated card and full transaction/read-back evidence for sampled assertions A04, A16, A21, A22, A23, and A26 before deleting its bounded synthetic fixture and actor residue.

## Functional coverage

Detailed assertion-level results are in `transaction-ledger.json`.

| Area | Result | Evidence summary |
|---|---|---|
| Import and idempotency | Pass | 15 uniquely tagged records; duplicate replay did not add a vehicle |
| Identity and detail edits | Pass | Canonical IDs retained; versioned edits and receipts persisted |
| Locations / Yard Hold / PMB / QC | Pass | Movement history and expected board state persisted |
| Workshop booking | Pass | Monday 2026-09-07 booking and reschedule history persisted |
| Admin blocks | Pass | Create, update, remove, history and receipt paths exercised |
| Parts / work / sublet | Pass | Required-state, parts updates, workshop items/adjustments and sublet instance history persisted |
| Pit and QC gates | Pass | Incomplete-work/Pit finalization failed closed; eligible paths advanced to QC |
| Archive / restore | Pass | Deleted-completed evidence created; restore returned the same canonical vehicle to active state |
| Authorization | Pass | Anonymous work-state RPC rejected; authenticated call succeeded |
| Concurrency / replay | Pass | Stale version rejected; valid mutation advanced to version 2; repeated key returned prior receipt |
| Live deployed UI | Pass | Approved administrator auth and dashboard load at all three required widths |
| Cleanup | Pass | 264 tagged pre-cleanup rows removed; temporary browser actor removed; final global count zero |

Expected negative results were counted as passes only when the operation failed closed at the intended boundary: anonymous authorization, stale expected version, QC finalization with incomplete required work/Pit, and an invalid workshop adjustment constraint probe.

## AUD-001 evidence remediation

Task `t_83f220c9` reran one deterministic STAGING-only fixture under the existing `QA-OVERNIGHT-20260904` prefix. The pre-mutation manifest is `aud001-remediation-fixture-manifest.json`; complete sanitized machine evidence is `aud001-transaction-evidence.json`.

- A04 / A23: the accepted edit advanced version 1 to 2; identical idempotency replay returned the receipt-backed success and left version 2 unchanged.
- A16: `mark_vehicle_ready_for_qc` returned a typed denial while fabrication remained incomplete; version 3 and PMB location were unchanged.
- A21: anonymous work-state mutation was denied without changing version 2; the authenticated request created one requirement receipt/audit event and advanced to version 3.
- A22: the valid expected-version request succeeded; a distinct stale version-1 request returned `stale_version` while authoritative state remained version 2.
- A26: the global pre-cleanup scan found 13 rows across tagged vehicle, receipt/history/audit/work-state, temporary role/auth, and identity relations. The bounded cleanup deleted those 13 rows; the post-cleanup public/auth/storage scan returned zero, real and active vehicle cardinality returned to 2, notifications remained zero, and protected control fingerprints matched baseline.
- UI: authenticated snapshot read-back contained the exact fixture; the exact stock locator was visible in the PMB bucket and captured at `screenshots/transactions/aud001-fixture-card.png` with no page errors or production requests.

`validate_transaction_evidence.py` is agent-runnable and checks all required fields, sampled assertion membership, path containment/resolution, and functional summary totals. It was demonstrated RED against the deficient ledger before remediation and GREEN against both canonical and lane ledgers after remediation.

## Browser and responsive evidence

Live-browser result: `live-browser-verification.json` (`ok: true`).

- 360 × 800: authenticated dashboard, staging project ref, no horizontal overflow, no browser/network errors.
- 768 × 900: authenticated dashboard, staging project ref, no horizontal overflow, no browser/network errors.
- 1440 × 1000: authenticated desktop navigation and dashboard, no clipping/overlap observed, no browser/network errors.

Screenshots:

- `screenshots/staging-post-cleanup-360x800.png`
- `screenshots/staging-post-cleanup-768x900.png`
- `screenshots/staging-post-cleanup-1440x1000.png`

The compact 360 px header uses abbreviated navigation labels and truncates the long account name, but the controls remained legible/operable and the document reported no horizontal overflow. No severity-rated defect was opened from the visual review.

## Cleanup proof

Pre-cleanup inventory found 264 tagged rows across 22 public/auth tables, including 15 vehicles and their audit, aliases, master-source/history/receipt, movement, parts, work-item, workshop adjustment, booking, admin-block, lifecycle, and sublet-instance records.

Cleanup used exact matches for the globally unique synthetic prefix, deterministic actor UUID, and exercised vehicle UUID across `public`, `auth`, and `storage`, inside one bounded staging transaction. The temporary browser actor was also removed after the authenticated UI run.

Final read-back at `2026-09-04T14:13:38.180287Z`:

- Matching tables: 0
- Matching rows: 0
- Synthetic vehicles: 0
- Synthetic auth actor: 0
- Real/source-backed vehicle cardinality: 2 before and 2 after
- Protected controls: `[REDACTED_STOCK_A]` remained version 12 with a pre-run `updated_at`; `[REDACTED_STOCK_B]` matched the independent release-lane version-3 identity/state baseline

See `cleanup-verification.json` for the table-level pre-cleanup inventory and final zero-state, and `protected-controls.json` for the read-only control verification.

## Testing notes and exclusions

- External email and Telegram delivery were intentionally not sent to avoid contacting real recipients. Persistent database/outbox/receipt seams were used where applicable.
- The original lane did not capture a fixture card before teardown. AUD-001 remediation now supplies the exact authenticated fixture card plus snapshot/RPC, transaction, receipt/history/audit, and post-cleanup evidence without altering the retained failed audit result.
- Production was not queried, written, deployed, or contacted.
- No repository application code, migrations, or staging deployment were changed by this QA task. Evidence files only were added in this worktree.

## Evidence index

- `fixture-manifest.json`
- `transaction-ledger.json`
- `cleanup-verification.json`
- `protected-controls.json`
- `issue-register.json`
- `console-network-log.json`
- `live-browser-verification.json`
- `live-browser-verification.py`
- `visual-observations.json`
- `aud001-remediation-fixture-manifest.json`
- `aud001-transaction-evidence.json`
- `validate_transaction_evidence.py`
- `screenshots/transactions/aud001-fixture-card.png`
- `screenshots/staging-post-cleanup-360x800.png`
- `screenshots/staging-post-cleanup-768x900.png`
- `screenshots/staging-post-cleanup-1440x1000.png`
