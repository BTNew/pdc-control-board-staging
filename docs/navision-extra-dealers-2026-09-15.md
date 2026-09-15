# Additional Navision dealer codes — 15 September 2026

Navision uploads now support dealer codes `002345` and `001234` alongside `14450` and `37047`.
The dropdown, import client and shared visibility refresh include all four scopes.
Leading-zero codes stay canonical when spreadsheet source cells contain numeric 2345 or 1234.
Select the dealer for the file, preview it, then apply using the existing approval flow.
The first import for an empty scope still requires the existing administrator review of the exact rows.

Database migration applied to staging via the migration API, remote version `20260915090857`.
The CLI-generated source file is `20260915090359_navision_add_dealer_codes.sql`.
The migration and rollback acceptance suite ran in one transaction; failed assertions would have rolled back the schema change.
The suite was also rerun after migration.

Verification:
- 10 frontend tests passed, plus existing Navision 768 preflight regression and JavaScript syntax checks.
- Both new scopes: initial-review guard, preview, apply, changed-details reimport, idempotent retry and snapshot readback passed.
- Exact and numeric source dealer cells preserve leading zeros.
- Wrong-dealer rows, duplicates, empty imports, conflicting filenames, unsupported dealers and anonymous preview remain blocked.
- Existing dealer snapshots and workshop bookings unchanged.
- All temporary users and import rows rolled back; zero probe users/rows remain.
- Security advisors introduced no new findings.
- No real source file for the new dealers was supplied or imported.

This changes upload/storage/read scope support; it does not expand automated actor dealer permissions.
