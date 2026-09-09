# Pilbara mobile QC visibility repair — 9 September 2026

## Reported failure
Stock 13064619 was visible in the desktop QC bucket, but absent from the mobile QC sign-off queue.

The authenticated staging snapshot contained seven retained Pilbara Service Job Card operations for JC14124971 and `current_location: QC`, but `qc_operation_lines` was empty. The mobile queue requires a non-empty canonical QC checklist. The QC projection supported authenticated-email and audited manual lines but omitted `pdc_pilbara_service_operations`.

## Repair
Applied staging migration `20260909052957_pilbara_qc_operation_sources_20260909` updates three existing functions in place:

- `pdc_qc_operation_lines_379` includes retained Pilbara operations, using their existing operation UUID, exact vehicle/Stock binding, current classification, explicit hours and audited adjustments. The JSON records the Pilbara source contract and retained evidence ID. Existing `source:<uuid>` identities are preserved; source kind denotes an authenticated source, not a fabricated email.
- `set_pdc_qc_operation_completion_379` resolves the exact line through that canonical projection, with the existing active-QC, role, subject/email, vehicle-version, line-version, idempotency and audit checks retained.
- `reject_pdc_qc_operation_381` uses the same exact source resolution rather than a second email-only lookup.

No source rows were copied into the email table. No operational records, completion flags, photos, credentials, grants, schedulers or Production were modified by the migration. No QC sign-off or RFT transition was attempted.

## Verification
- Live administrator and operator snapshot checks returned Stock 13064619 with seven QC lines, all initially unchecked, and source Job Card JC14124971.
- Its canonical version, QC location and unsigned QC state were unchanged by the migration.
- A rollback-only transaction exercised the real checkbox writer while deliberately retaining the explicit-zero line as unchecked. The write succeeded; exact replay reused the receipt. Stale vehicle version, a different vehicle's source line and Viewer writes were rejected. Vehicle/work-item state and receipt/completion counts were unchanged after rollback.
- Four local Node regressions passed using the deployed source functions and mapper: reproduction of the old empty-list failure; mobile/desktop eligibility; actual mobile list and seven-checkbox HTML; and unchanged incomplete/unknown-hours/mapping protections.
- Finalization still requires the established per-operation checks, an accepted photo receipt and an authorised human action. It was intentionally not exercised on the customer's vehicle.

These are database-role and source-renderer checks, not a claim that an authenticated phone-browser session was operated here. Reload the staging website's **QC Sign-off** page to fetch the corrected checklist. This is a server projection fix, so no phone reinstall or browser-data reset is needed.
