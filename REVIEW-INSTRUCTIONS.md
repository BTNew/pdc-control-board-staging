# Independently Runnable Stage 2A Review Instructions

The ZIP is an allow-list export of the recorded source commit plus an exact
archive of staging deployment commit
`ee9d7419f3f1926ca9634dd4f49d314756ab4e7e` and secret-free evidence.
Run commands from the extracted package root.

## 1. Verify package integrity

```bash
python scripts/verify_stage2a_review_package.py
```

This verifies `SHA256SUMS.txt`, required files, deployment snapshot hashes,
prohibited paths/content, and source/deployment metadata. It requires only the
Python standard library.

## 2. Install exact review dependencies

Python 3.11 was used for final verification.

```bash
python -m venv .review-venv
# Windows Git Bash:
source .review-venv/Scripts/activate
# Linux/macOS:
# source .review-venv/bin/activate
python -m pip install -r requirements-review.txt
```

Node.js 24.14.1 was used for the final non-browser JavaScript tests; those tests
require no npm install.

## 3. Non-secret local tests

```bash
node test_all.js
node test_workshop_reference_data_service.js
python -m unittest discover -s backend -p "test_*.py" -v
python test_pdc_backup_retention.py
python test_pdc_backup_scheduled_tick.py
python -m unittest backend.test_build_review_export -v
python -m py_compile _staging_test_tools/*.py
node --check scripts/stage2a_live_acceptance.js
git diff --check  # when reviewing from a Git checkout
```

Expected final totals are recorded in
`review-evidence/FINAL-REGRESSION-AND-BROWSER-ACCEPTANCE.md`.

## 4. Optional live staging regression

These tests mutate only controlled staging fixtures and refuse any endpoint
that does not contain the approved staging project ref
`cdsmnqxtyyoeoznmbidd`. They require reviewer-supplied staging credentials.
Never provide production credentials.

```bash
cp _staging_test_tools/.env.example _staging_test_tools/.env
# Populate only the approved staging values locally; .env is prohibited from ZIPs.

python _staging_test_tools/test_account_approval_staging.py
python _staging_test_tools/test_backup_restore_fk_hardening_staging.py
python _staging_test_tools/test_own_row_lockout_staging.py
python _staging_test_tools/test_pdc_user_roles_lockdown_staging.py
python _staging_test_tools/test_privilege_hardening_staging.py
python _staging_test_tools/test_qc_rft_collected_staging.py
python _staging_test_tools/test_role_access_matrix_staging.py
python _staging_test_tools/test_stage2a_backup_restore_staging.py
python _staging_test_tools/test_stage2a_importer_staging.py
python _staging_test_tools/test_stage2a_workshop_reference_data_staging.py
python _staging_test_tools/test_vehicle_notification_worker_staging.py
python _staging_test_tools/reset_workshop_test_fixtures.py
python _staging_test_tools/test_workshop_staging_integration.py
python _staging_test_tools/reset_workshop_test_fixtures.py
```

The final completed staging run was 191 passed, 0 failed, including workshop
integration at 34 passed, 0 failed. Do not rerun against production.

## 5. Optional two-browser acceptance

Install the exact optional dependency without adding it to source:

```bash
npm install --no-save --package-lock=false playwright-core@1.55.0
set -a; source _staging_test_tools/.env; set +a
node scripts/stage2a_live_acceptance.js
```

Set `PDC_CHROME_EXECUTABLE` if Chrome/Chromium is not at the documented default.
The script refuses a non-staging site, records every request host, fails on any
production-project request, and restores its temporary setting mutation.

The already-completed machine-readable result is
`review-evidence/post-resume/two-browser-realtime-acceptance.json`.

## 6. Rebuild the review ZIP

From a clean Git checkout at the recorded source HEAD, with the staging deploy
repository available at its recorded commit:

```bash
python scripts/build_review_export.py --output-dir ..
```

The exporter fails closed on a dirty source tree, wrong branch/deployment
commit, forbidden path/content, missing dependency, or checksum mismatch.
