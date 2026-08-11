"""Apply staging-only Migration 156 with its hash-bound Workshop-history restoration.

Usage:
  set PDC_MIGRATION_156_BACKUP_MANIFEST=<absolute manifest.json path>
  python apply_migration_156_with_history_restore.py \
    "APPLY STAGING MIGRATION 156 <first-eight-SHA256-uppercase>"

The SQL migration deliberately fails its final verification unless this applicator
has restored the exact retained pre-clear history evidence in the same transaction.
"""
import gzip
import hashlib
import json
import os
import sys
from pathlib import Path

import psycopg2
from psycopg2.extras import Json, execute_values

from staging_env import assert_staging_target, load_local_env

EXPECTED_RAW_SHA = "1912754a3ca831d139d4a8419254d9fcbd6cec5bcc62925d574930b574812b24"
EXPECTED_GZIP_SHA = "07d8840916d9e954a24339fa64cdb34796cd02a8381aa774e770f831fbb5eec3"
EXPECTED_ROWS = 211
EXPECTED_SOURCE_ROWS_SHA = "08b3ae192d22f8202080923efffde76ba207590f83184e80479fef74ad176e7f"
EXPECTED_RESTORED_ROWS_SHA = "b28f5f4edc75be3d3bd8db479b822d26d4c71cbdb4c454bfab80865841c431e7"
EXPECTED_RAW_BYTES = 2147833

repo = Path(__file__).resolve().parents[1]
migration = repo / "supabase" / "staging_only" / "156_monitor_parts_and_complete_purge_review_remediation.sql"
sql = migration.read_text(encoding="utf-8")
migration_sha = hashlib.sha256(migration.read_bytes()).hexdigest()
confirmation = f"APPLY STAGING MIGRATION 156 {migration_sha[:8].upper()}"
if sys.argv[1:] != [confirmation]:
    raise SystemExit(f"confirmation mismatch; required: {confirmation}")

lower_sql = sql.lower()
start = lower_sql.find("begin;")
end = lower_sql.rfind("commit;")
if start < 0 or end < start:
    raise SystemExit("transaction wrapper missing")
body = sql[start + 6 : end]
verify_at = body.find("do $verify$")
if verify_at < 0:
    raise SystemExit("restoration verification split marker missing")

manifest_path_text = os.getenv("PDC_MIGRATION_156_BACKUP_MANIFEST")
if not manifest_path_text:
    raise SystemExit("PDC_MIGRATION_156_BACKUP_MANIFEST is required")
manifest = json.loads(Path(manifest_path_text).read_text(encoding="utf-8"))
backup_path = Path(manifest["backup_path"])
compressed = backup_path.read_bytes()
raw = gzip.decompress(compressed)
raw_sha = hashlib.sha256(raw).hexdigest()
gzip_sha = hashlib.sha256(compressed).hexdigest()
if manifest.get("environment") != "staging" or raw_sha != EXPECTED_RAW_SHA or gzip_sha != EXPECTED_GZIP_SHA:
    raise SystemExit("backup environment/hash mismatch")
if manifest.get("sha256_uncompressed") != raw_sha or manifest.get("sha256_gzip") != gzip_sha:
    raise SystemExit("manifest/archive hash mismatch")
if len(raw) != EXPECTED_RAW_BYTES or manifest.get("counts", {}).get("workshop_booking_history") != EXPECTED_ROWS:
    raise SystemExit("manifest byte/count mismatch")

backup = json.loads(raw)
history_rows = backup["tables"]["workshop_booking_history"]
booking_vehicle = {row["id"]: row["vehicle_id"] for row in backup["tables"]["workshop_bookings"]}
rows_sha = hashlib.sha256(
    json.dumps(history_rows, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
if len(history_rows) != EXPECTED_ROWS or rows_sha != EXPECTED_SOURCE_ROWS_SHA:
    raise SystemExit("Workshop history count/hash mismatch")
if any(row["booking_id"] not in booking_vehicle for row in history_rows):
    raise SystemExit("Workshop history booking/vehicle identity mismatch")

load_local_env()
dsn = os.getenv("PDC_STAGING_DIRECT_DATABASE_URL") or os.getenv("PDC_STAGING_DATABASE_URL")
assert_staging_target(database_url=dsn)
connection = psycopg2.connect(dsn)
try:
    with connection.cursor() as cursor:
        cursor.execute("begin")
        cursor.execute(
            "select auth_user_id,email from public.pdc_user_roles "
            "where active and account_status='approved' and role='administrator' "
            "and auth_user_id is not null order by created_at,id limit 1"
        )
        administrator_id, administrator_email = cursor.fetchone()
        cursor.execute(body[:verify_at])
        claims = json.dumps(
            {"sub": str(administrator_id), "email": administrator_email, "role": "authenticated"}
        )
        cursor.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
        cursor.execute(
            "insert into public.pdc_staging_verified_backup_manifests"
            "(backup_manifest_sha256,backup_gzip_sha256,raw_bytes,table_counts,verified_by) "
            "values(%s,%s,%s,%s,%s)",
            (raw_sha, gzip_sha, len(raw), Json(manifest["counts"]), administrator_id),
        )

        history_ids = [row["id"] for row in history_rows]
        cursor.execute(
            "select count(*) from public.workshop_booking_history where id=any(%s::uuid[])",
            (history_ids,),
        )
        existing = cursor.fetchone()[0]
        if existing:
            raise RuntimeError(("history_restore_id_conflict", existing))

        values = [
            (
                row["id"],
                row["booking_id"],
                booking_vehicle[row["booking_id"]],
                row["event_type"],
                Json(row["before_data"]) if row["before_data"] is not None else None,
                Json(row["after_data"]) if row["after_data"] is not None else None,
                Json(row["metadata"]),
                row["actor_user_id"],
                row["actor_email"],
                row["created_at"],
            )
            for row in history_rows
        ]
        execute_values(
            cursor,
            "insert into public.workshop_booking_history"
            "(id,booking_id,purged_booking_id,vehicle_id,event_type,before_data,after_data,metadata,actor_user_id,actor_email,created_at) values %s",
            values,
            template="(%s,null,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
        )
        cursor.execute(
            "select count(*) from public.workshop_booking_history "
            "where id=any(%s::uuid[]) and booking_id is null "
            "and purged_booking_id is not null and vehicle_id is not null",
            (history_ids,),
        )
        restored = cursor.fetchone()[0]
        if restored != EXPECTED_ROWS:
            raise RuntimeError(("history_restore_count", restored, EXPECTED_ROWS))
        cursor.execute(
            "select encode(extensions.digest(convert_to(coalesce(jsonb_agg(to_jsonb(h) order by h.id),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex') "
            "from public.workshop_booking_history h where h.id=any(%s::uuid[])",
            (history_ids,),
        )
        restored_rows_sha = cursor.fetchone()[0]
        if restored_rows_sha != EXPECTED_RESTORED_ROWS_SHA:
            raise RuntimeError(("history_restore_content_hash", restored_rows_sha, EXPECTED_RESTORED_ROWS_SHA))

        cursor.execute(
            "insert into public.pdc_staging_backup_restoration_receipts"
            "(backup_manifest_sha256,backup_gzip_sha256,restored_table,source_rows,source_rows_sha256,restored_rows,restored_rows_sha256,applied_by) "
            "values(%s,%s,'workshop_booking_history',%s,%s,%s,%s,%s)",
            (raw_sha, gzip_sha, EXPECTED_ROWS, rows_sha, restored, restored_rows_sha, administrator_id),
        )
        cursor.execute(
            "insert into public.audit_events(action,table_name,actor_id,actor_email,before_data,after_data,metadata) "
            "values('insert'::public.audit_action,'workshop_booking_history',%s,%s,null,null,"
            "jsonb_build_object('source','hash_bound_preclear_history_restore_156',"
            "'backup_manifest_sha256',%s,'backup_gzip_sha256',%s,'rows_restored',%s,"
            "'source_rows_sha256',%s,'restored_rows_sha256',%s,'production_unchanged',true))",
            (administrator_id, administrator_email, raw_sha, gzip_sha, restored, rows_sha, restored_rows_sha),
        )
        cursor.execute(body[verify_at:])
    connection.commit()
    print(
        f"APPLIED: migration_sha={migration_sha} restored={restored} "
        f"source_rows_sha256={rows_sha} restored_rows_sha256={restored_rows_sha}"
    )
except Exception:
    connection.rollback()
    raise
finally:
    connection.close()
