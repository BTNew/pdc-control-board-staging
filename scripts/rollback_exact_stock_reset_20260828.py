from __future__ import annotations

import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path

BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
ARTIFACT = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/stock-13080534-13017855-reset-20260828/pdc_exact_stock_reset_7f1c3315-ac42-46fb-99ed-70b43ef89f80.bin")
EXPECTED_ARTIFACT_SHA = "6887bad60ba612c83584cb628829b70dcb0f2e6c8a08de64e46b2c7de3a77518"
EXPECTED_RUN = "7f1c3315-ac42-46fb-99ed-70b43ef89f80"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"


def load_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap_rollback_check", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec); assert spec and spec.loader; spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode()); module.validate(values); return values


def main():
    parser = argparse.ArgumentParser(description="Verify the exact staging reset rollback artifact without mutating staging.")
    parser.add_argument("--apply", action="store_true", help="Reserved for a separately approved restore run; never enabled by Phase 1.")
    args = parser.parse_args()
    if args.apply:
        raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_REQUIRES_SEPARATE_EXPLICIT_RESTORE_APPROVAL")
    values = load_values(); dsn = values["PDC_STAGING_DATABASE_URL"]
    if PROJECT_REF not in dsn or "vjdtsswhroyguxyfjdkt" in dsn: raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_NON_STAGING_TARGET")
    if not ARTIFACT.is_file(): raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_ARTIFACT_MISSING")
    actual = hashlib.sha256(ARTIFACT.read_bytes()).hexdigest()
    if actual != EXPECTED_ARTIFACT_SHA: raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_ARTIFACT_HASH_MISMATCH")
    import win32crypt
    from cryptography.fernet import Fernet
    key = win32crypt.CryptUnprotectData(Path(r"C:/Users/nwmgr/AppData/Local/hermes/secrets/pdc_backup_key_staging.dpapi").read_bytes(), None, None, None, 0)[1]
    payload = json.loads(gzip.decompress(Fernet(key).decrypt(ARTIFACT.read_bytes())).decode())
    if payload.get("environment") != "staging" or payload.get("project_ref") != PROJECT_REF or payload.get("backup_run_id") != EXPECTED_RUN: raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_PAYLOAD_BINDING_FAILED")
    if set(payload.get("target_stocks", [])) != {"13080534", "13017855"} or not payload.get("tables"): raise RuntimeError("PDC_EXACT_RESET_ROLLBACK_CLOSURE_INCOMPLETE")
    print(json.dumps({"ok": True, "mode": "verify-only", "project_ref": PROJECT_REF, "backup_run_id": EXPECTED_RUN, "artifact": str(ARTIFACT), "artifact_sha256": actual, "closure_table_count": len(payload["tables"]), "closure_row_count": sum(len(v["rows"]) for v in payload["tables"].values()), "restore_contract": "Separate explicit staging restore only; recheck exact receipt, empty target, project sentinel, expected head, advisory lock, identity bindings and rollback all writes on any mismatch.", "production_contacted": False}, sort_keys=True))

if __name__ == "__main__":
    try: main()
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc), "production_contacted": False}, sort_keys=True)); raise SystemExit(1)
