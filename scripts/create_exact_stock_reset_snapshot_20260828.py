from __future__ import annotations

import gzip
import hashlib
import importlib.util
import json
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
BOOTSTRAP = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
SECRETS = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi")
BACKUP_KEY = Path(r"C:/Users/nwmgr/AppData/Local/hermes/secrets/pdc_backup_key_staging.dpapi")
OUTPUT = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/stock-13080534-13017855-reset-20260828")
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
TARGET_TOKENS = [
    "13080534", "13017855", "5721cafa-2b60-4d45-b69c-ab907eaf178e",
    "e39eb741-cf03-44f2-8a75-54362ecc8a26", "7fe33693-f519-5152-bbe0-9cc799c4ae33",
    "J139125422", "MR0MABAV902402464", "1:680", "1:640", "imap_uid:680", "imap_uid:681",
    "f205342f4ff4361b88bf21b83a11e92957a796792bcc0bfa4150d0abaa5b4916",
    "d6756c523ffb7336556492fe0ef25c202d744ffd2645846b19cbbcdffed60493",
    "812c2291fe80a143e8fe8a55e34f9869476926d69d6bbddd345b61a6a5448a8a",
    "6836f01c-080f-4289-90a4-df8667a49ac9", "d89a3bbd-590b-493b-84a8-ce557bbfe512",
    "0f190df5-09df-4df6-a111-66f658318d57", "3415271f-e6df-4d1e-a763-3341f9b066f4", "91eadf28-e8d6-482a-9dd9-b3b6b7862489",
    "5d907dc4-c2c3-4eb1-b028-a771b8d447d7", "842405e4-5209-45f5-9729-0d22327daeaa", "c3786a12-18a0-4c88-8636-8b09800aed56",

]


def load_values():
    spec = importlib.util.spec_from_file_location("pdc_staging_bootstrap_target_snapshot", BOOTSTRAP)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    values = json.loads(module.unprotect(SECRETS.read_bytes()).decode())
    module.validate(values)
    return values


def json_default(value):
    from scripts.pdc_backup import json_default as backup_default
    return backup_default(value)


def table_columns(cur, table):
    cur.execute("select column_name from information_schema.columns where table_schema='public' and table_name=%s order by ordinal_position", (table,))
    return [row[0] for row in cur.fetchall()]


def main():
    values = load_values()
    dsn = values["PDC_STAGING_DATABASE_URL"]
    if PROJECT_REF not in dsn or "vjdtsswhroyguxyfjdkt" in dsn:
        raise RuntimeError("exact staging target guard failed")
    import win32crypt
    from cryptography.fernet import Fernet
    key = win32crypt.CryptUnprotectData(BACKUP_KEY.read_bytes(), None, None, None, 0)[1]
    import psycopg2
    run_id = str(uuid.uuid4())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    conn = psycopg2.connect(dsn, sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_target_snapshot")
    try:
        conn.set_session(isolation_level="REPEATABLE READ", readonly=True, autocommit=False)
        cur = conn.cursor()
        cur.execute("select version,name from supabase_migrations.schema_migrations order by case when version~'^[0-9]{14}$' then version::bigint else 0 end desc,version desc limit 1")
        head = cur.fetchone()
        cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
        if cur.fetchone() != (PROJECT_REF,):
            raise RuntimeError("staging sentinel mismatch")
        snapshot = {
            "format": "pdc-exact-stock-reset-encrypted-closure-v1",
            "environment": "staging",
            "project_ref": PROJECT_REF,
            "backup_run_id": run_id,
            "snapshot_head": list(head),
            "target_stocks": ["13080534", "13017855"],
            "target_tokens": sorted(TARGET_TOKENS),
            "tables": {},
        }
        cur.execute("select table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE' order by table_name")
        tables = [row[0] for row in cur.fetchall()]
        for table in tables:
            columns = table_columns(cur, table)
            cur.execute(
                f'''select row_to_json(x) from public."{table}" x where exists (
                    select 1 from unnest(%s::text[]) as wanted(token)
                    where jsonb_path_exists(to_jsonb(x), '$.** ? (@ == $token)', jsonb_build_object('token', to_jsonb(wanted.token)))
                ) order by to_jsonb(x)::text''',
                (TARGET_TOKENS,),
            )
            rows = [row[0] for row in cur.fetchall()]
            if rows:
                canonical = "\n".join(json.dumps(row, default=json_default, sort_keys=True, separators=(",", ":")) for row in rows).encode()
                snapshot["tables"][table] = {"columns": columns, "rows": rows, "row_count": len(rows), "rows_sha256": hashlib.sha256(canonical).hexdigest()}
        conn.rollback()
    finally:
        conn.close()
    raw = json.dumps(snapshot, default=json_default, sort_keys=True, separators=(",", ":")).encode()
    encrypted = Fernet(key).encrypt(gzip.compress(raw, compresslevel=6))
    artifact = OUTPUT / f"pdc_exact_stock_reset_{run_id}.bin"
    artifact.write_bytes(encrypted)
    artifact_sha = hashlib.sha256(encrypted).hexdigest()
    manifest = {
        "format": snapshot["format"], "environment": "staging", "project_ref": PROJECT_REF,
        "backup_run_id": run_id, "snapshot_head": head,
        "target_stocks": snapshot["target_stocks"], "artifact": artifact.name,
        "artifact_sha256": artifact_sha, "encrypted": True,
        "table_row_counts": {t: d["row_count"] for t, d in snapshot["tables"].items()},
        "table_rows_sha256": {t: d["rows_sha256"] for t, d in snapshot["tables"].items()},
        "target_token_count": len(TARGET_TOKENS),
        "closure_table_count": len(snapshot["tables"]),
        "closure_row_count": sum(d["row_count"] for d in snapshot["tables"].values()),
        "mailbox_messages_preserved": True, "production_contacted": False,
    }
    manifest_path = OUTPUT / f"{artifact.name}.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
    manifest_sha = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    conn = psycopg2.connect(dsn, sslmode="verify-full", sslrootcert=values["PDC_STAGING_SSLROOTCERT"], application_name="pdc_exact_stock_reset_snapshot_receipt")
    try:
        with conn.cursor() as cur:
            cur.execute("insert into public.backup_runs (id,environment,kind,status,started_at,finished_at,backup_version,migration_version,triggered_by,table_row_counts,file_path,file_size_bytes,file_sha256,encrypted) values (%s,'staging','manual','success',clock_timestamp(),clock_timestamp(),'exact-closure-v1',%s,'owner-exact-stock-reset-13080534-13017855',%s,%s,%s,%s,true)", (run_id, head[0], json.dumps(manifest["table_row_counts"]), str(artifact), len(encrypted), artifact_sha))
        conn.commit()
    finally:
        conn.close()
    print(json.dumps({"ok": True, "project_ref": PROJECT_REF, "backup_run_id": run_id, "snapshot_head": head, "artifact": str(artifact), "artifact_sha256": artifact_sha, "manifest": str(manifest_path), "manifest_sha256": manifest_sha, "closure_table_count": manifest["closure_table_count"], "closure_row_count": manifest["closure_row_count"], "table_row_counts": manifest["table_row_counts"], "production_contacted": False}, sort_keys=True, default=str))


if __name__ == "__main__":
    main()
