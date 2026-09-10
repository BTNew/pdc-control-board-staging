# QC/RFT snapshot reconciliation — STAGING

The mobile sign-off succeeded. Stocks 13061263 and 13075150 have canonical QC completion, RFT transfer, and receipt-backed photos. Both remain uncollected.

The Vehicle Locations snapshot omitted qc_completed_at and rft_transferred_at, despite projecting current_location=RFT. mapServerVehicle consequently produced pdcQcComplete=false and an empty rftTransferredAt; the RFT controls correctly refused to show readiness.

The snapshot now joins its existing rows to vehicles by canonical UUID and projects qc_completed_at, qc_completed_by, and rft_transferred_at. Explicit nulls remain null, so fresh reinspection cannot inherit an old completion. Snapshot membership, permissions, operation lines, photos and all other fields are preserved. No business records are updated.

Validation:
- 297 Node tests passed, including five new feed/mapping/reconciliation/control regressions.
- Transactional STAGING regression compared every returned row against canonical fields as operator and administrator, with signed and unsigned cases; anon EXECUTE remains denied.
- Transactional before/after comparison proved identical snapshot membership and unrelated fields, and unchanged hashes of every vehicle record.
- Post-apply regression passed; both target vehicles retain their original versions (39 and 17), sign-off timestamps and uncollected state.
- Frontend secret scan: 54 tracked files, zero findings; JavaScript syntax checks passed.
- Security advisor category counts unchanged from baseline; existing advisories were not introduced by this repair.
- No real vehicle was re-signed, moved, collected, or assigned test evidence. No emails were sent and Production was not accessed or modified.

Migration applied only to cdsmnqxtyyoeoznmbidd, ledger version 20260910002538.
The existing website consumes the repaired feed; reload Vehicle Locations to refresh the snapshot.

