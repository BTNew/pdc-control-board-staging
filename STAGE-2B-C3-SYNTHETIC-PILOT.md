# Stage 2B C3 synthetic import and reconciliation pilot

## Scope

This change proves the migration 029 import chain, migration 031 typed identity export, C2b offline consumers, deterministic reconciliation, revision-locked rollback and complete cleanup using only `stage2b_c3_synthetic_pilot` records on guarded staging project `cdsmnqxtyyoeoznmbidd`.

It does not add migration 032, change browser/frontend authority, retire direct reads, import real vehicles, enable AI, deploy, merge or contact production.

## Portable verification

```bash
cp pdc-supabase-config.example.js pdc-supabase-config.js
node test_all.js
PYTHONPATH=scripts python -m unittest \
  backend.test_stage2b_offline_vehicle_reference_artifact \
  backend.test_stage2b_importer_identity_export_foundation \
  backend.test_stage2b_importer_identity_export_adapter \
  backend.test_stage2b_c3_reconciliation \
  backend.test_stage2b_c3_synthetic_pilot -v
python -m py_compile scripts/stage2b_c3_reconciliation.py scripts/stage2b_c3_synthetic_pilot.py
node --check scripts/workshop_vehicle_reference_artifact.js
node --check scripts/workshop_planner_legacy_validate.js
```

The staging pilot is intentionally excluded from non-secret review execution. It refuses any project other than the exact guarded staging ref and requires an injected staging DSN.

## Evidence

See `review-evidence/stage2b-c3/` for sanitized preview/apply/replay, typed-artifact, reconciliation, rollback, encrypted-backup, test and zero-residue cleanup evidence. Evidence contains no credentials, URLs, customer data or operational payloads.
