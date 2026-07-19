# Stage 2B C5 — Controlled Real-Data Staging Pilot

## Completed scope

C5 imported exactly five clean deterministic browser-local source records into the guarded staging project `cdsmnqxtyyoeoznmbidd` using migration 029 operations. The records were selected from the exact approved C4 package SHA-256 `980bab0cc0bf79a8156fb78b2587df165406d3fd7d92929468fda66e2ba81016`.

This stage did not contact or link production, deploy, merge, switch frontend reads, change browser authority, clear browser-local data, retire direct `SELECT`, or begin AI feature work. The five imported staging rows are retained only as an isolated pilot; no user workflow depends on them.

## Deterministic selection

The selector recomputes the approved C4 assessment and chooses the first five `record_ref` values in UTF-8 ascending order that are:

- classified clean;
- not present in the manual-review list;
- not deleted/archived or linked to workflow, Parts, or booking data;
- free of placeholder, malformed, ambiguous, conflicting, orphaned, and parse-error classifications.

Selected source IDs are recorded in `review-evidence/stage2b-c5/selected-record-manifest.json`. The human-readable pre-apply actions and exact preview checksum are in `approval-manifest.md`.

## Backup and baseline

Immediately before apply, a fresh encrypted staging backup was created and decrypted/checksum-verified. Its ledger tip was migration 031. It restored successfully into an isolated schema with all 72 discovered foreign keys added and validated, zero skipped keys, exact row counts, and all checks passed. The restore schema was removed.

Sanitized backup metadata and baseline counts are committed in:

- `backup-restore-evidence.json`
- `before-after-row-counts.json`

The encrypted backup itself remains local and ignored; no encryption material or connection string is committed or packaged.

## Preview, apply, and replay

For all five records:

1. migration 029 preview was run twice and compared exactly;
2. all actions were deterministic inserts with zero ambiguity and zero conflict;
3. apply-embedded preview matched the approved preview exactly;
4. apply committed before replay;
5. the identical request replayed from the durable receipt without another insert;
6. one committed response was deliberately discarded, a fresh guarded connection was opened, and the identical response was recovered from the durable receipt.

Evidence:

- `preview-result.json`
- `apply-result.json`
- `replay-evidence.json`
- `operational-proof.json` (sanitized complete preview/apply/replay response bodies)

## Migration 031 and C2b reconciliation

The migration 031 typed reference artifact was generated twice at a fixed generation time and matched exactly. Each selected source record reconciled to one UUID at version 1. Stock, VIN, Toyota order, source-record claim, generated permanent identifier, original source evidence, source batch, and source system were checked against both the database and typed artifact.

The C2b classifier safely matched exactly five reference-only rows, with zero refused/review rows. The Node C2b validator passed. No C2b import was applied.

Evidence: `reconciliation-report.json` and the migration 031/C2b sections of `operational-proof.json`.

## Unrelated-state and conflict proof

Every column of every pre-pilot vehicle row was reconstructed from the encrypted backup and hashed. The complete post-pilot rows excluding the five selected UUIDs had the identical SHA-256. No unrelated vehicle changed. The imported namespace contains exactly five vehicles, five source records, five receipts, ten aliases, and zero unresolved conflicts.

## Rollback export and rehearsal

`rollback-export.json` is checksum-bound to the five pilot UUIDs and their vehicle, alias, source-evidence, receipt, history, and audit rows. It records both resolver revision and the mutable vehicle-master revision used as the database revision lock. Broad/credential values are excluded from review evidence.

A post-pilot encrypted backup was fully restored into a disposable isolated staging schema using the repository restore path. The restore reproduced the full schema/data set, 72 validated foreign keys, and indexes. Rollback locked and checked the restored `vehicle_master_revision` row, accepted the exact export revision, refused a stale revision, validated the selected rows against the export, and deleted only those rows in dependency order. Selected rows returned to zero, hashes of every unrelated row in the six rollback tables remained identical, constraints were forced immediate, the temporary schema was removed, and retained public pilot rows were verified unchanged.

Evidence: `rollback-report.json`.

## Retained state and stop point

The five pilot records remain in staging for independent review. Browser-local records remain authoritative and unchanged. A live rollback was not performed because the approved C5 state is retained-pilot, not cleanup.

Stop after independent review of the focused C5 ZIP. Do not begin a wider import or authority cutover without a separate explicit instruction.

## Verification commands

Repository-local offline tests:

```bash
python -m unittest backend.test_stage2b_c5_real_data_pilot -v
python -m py_compile scripts/stage2b_c5_real_data_pilot.py backend/test_stage2b_c5_real_data_pilot.py
git diff --check
```

The focused review ZIP has its own exact-member/checksum/content verifier, includes the exact approved C4 ZIP plus its extracted sanitized assessment needed to reproduce selection, and contains no credentials or encrypted backup payload.
