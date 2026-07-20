#!/usr/bin/env python3
"""Guarded live verification for migration 037 on the approved staging project.

The synthetic suite exercises real RPCs and rolls back its outer transaction, so
no synthetic fixtures or revision changes survive. The safe-export mode performs
preview only and never calls the apply RPC.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "_staging_test_tools"), str(ROOT / "scripts")]

from staging_conn import get_conn  # type: ignore  # noqa: E402
from staging_env import EXPECTED_STAGING_REF, assert_staging_target, required  # type: ignore  # noqa: E402
from pdc_backup import deterministic_table_hash, export_table  # noqa: E402

EXPECTED_EXPORT_SHA256 = "a7a455bcf50266369c7aa02380c58d3264751fe5c326a47a2296a78a801fb755"
OPERATIONAL_TABLES = ("vehicles", "vehicle_work_items", "vehicle_movements")


def ensure_staging() -> None:
    assert_staging_target(database_url=required("PDC_STAGING_DATABASE_URL"))


def actor(cur, role: str):
    cur.execute(
        """select auth_user_id,email from public.pdc_user_roles
           where active and account_status='approved' and auth_user_id is not null
             and role::text=%s order by email limit 1""",
        (role,),
    )
    row = cur.fetchone()
    if not row:
        raise RuntimeError(f"No active staging {role} has an auth_user_id")
    return row


def impersonate(cur, user_id, email: str) -> None:
    cur.execute(
        "select set_config('request.jwt.claims',%s,true),set_config('role','authenticated',true)",
        (json.dumps({"sub": str(user_id), "email": email, "role": "authenticated"}),),
    )


def restore_session_role(cur) -> None:
    cur.execute("select set_config('role','postgres',true)")


def rpc(cur, name: str, args: list):
    cur.execute(f"select public.{name}(" + ",".join(["%s"] * len(args)) + ")", args)
    return cur.fetchone()[0]


def operational_hashes(cur):
    result = {}
    for table in OPERATIONAL_TABLES:
        columns, rows = export_table(cur, table)
        result[table] = {"rows": len(rows), "sha256": deterministic_table_hash(columns, rows)}
    return result


def ledger(cur):
    cur.execute("select version,name from supabase_migrations.schema_migrations order by version")
    return [(str(version), name) for version, name in cur.fetchall()]


def preflight() -> dict:
    ensure_staging()
    conn = get_conn()
    try:
        cur = conn.cursor()
        entries = ledger(cur)
        cur.execute("select table_name from information_schema.tables where table_schema='public' and table_name like 'navision_%' order by table_name")
        return {
            "project_ref": EXPECTED_STAGING_REF,
            "ledger_last": entries[-1],
            "migration_037_count": sum(version == "037" for version, _ in entries),
            "navision_tables": [row[0] for row in cur.fetchall()],
            "operational": operational_hashes(cur),
        }
    finally:
        conn.close()


def permission_denied(cur, statement: str) -> bool:
    cur.execute("savepoint navision_permission_check")
    try:
        cur.execute(statement)
    except Exception as error:  # noqa: BLE001
        cur.execute("rollback to savepoint navision_permission_check")
        cur.execute("release savepoint navision_permission_check")
        return getattr(error, "pgcode", None) == "42501"
    cur.execute("release savepoint navision_permission_check")
    return False


def synthetic_suite() -> dict:
    ensure_staging()
    conn = get_conn()
    cur = conn.cursor()
    try:
        entries = ledger(cur)
        if entries[-1][0] != "037" or sum(version == "037" for version, _ in entries) != 1:
            raise RuntimeError(f"Migration ledger is not exactly through 037: {entries[-3:]}")
        cur.execute("select count(*) from public.navision_backend_records")
        if cur.fetchone()[0] != 0:
            raise RuntimeError("Synthetic suite requires an empty Navision backend store")

        before = operational_hashes(cur)
        admin_id, admin_email = actor(cur, "administrator")
        cur.execute("select id,stock_number,toyota_order_number,vin from public.vehicles order by id limit 1")
        vehicle_id, vehicle_stock, vehicle_order, vehicle_vin = cur.fetchone()
        impersonate(cur, admin_id, admin_email)

        rows = [
            {"id": "SYN-NAV-001", "order": "SYN-O-001", "stock": "SYN-S-001", "vin": "SYNVIN00000000001", "model": "Synthetic One"},
            {"id": "SYN-NAV-002", "order": "SYN-O-002", "stock": "SYN-S-002", "vin": "SYNVIN00000000002", "model": "Synthetic Two"},
            {"id": "SYN-NAV-003", "order": "SYN-O-003", "stock": "SYN-S-003", "vin": "SYNVIN00000000003", "model": "Synthetic Three"},
            {"id": "SYN-NAV-MATCH", "order": vehicle_order, "stock": vehicle_stock, "vin": vehicle_vin, "model": "Synthetic Link Proposal"},
        ]
        preview = rpc(cur, "preview_navision_backend_import", [json.dumps(rows), "synthetic-037.json", None])
        pdata = preview["data"]
        if not preview["ok"] or pdata["blocking"] or pdata["operational_mutations"] != 0:
            raise RuntimeError(f"Synthetic preview failed: {preview}")
        apply_args = [
            "synthetic-037-apply", json.dumps(rows), "synthetic-037.json", None,
            pdata["source_hash"], pdata["preview_hash"], pdata["base_revision"],
        ]
        applied = rpc(cur, "apply_navision_backend_import", apply_args)
        replayed = rpc(cur, "apply_navision_backend_import", apply_args)
        if applied != replayed:
            raise RuntimeError("Response-loss replay did not return the exact stored response")

        restore_session_role(cur)
        cur.execute("select count(*),count(canonical_vehicle_id) from public.navision_backend_records")
        record_count, linked_count = cur.fetchone()
        if record_count != len(rows) or linked_count != 0:
            raise RuntimeError("Apply duplicated rows or automatically linked an operational vehicle")

        impersonate(cur, admin_id, admin_email)
        changed_rows = [rows[0], {**rows[1], "model": "Synthetic Two Changed"}, {"id": "SYN-NAV-NEW", "stock": "SYN-S-NEW"}]
        changed = rpc(cur, "preview_navision_backend_import", [json.dumps(changed_rows), "synthetic-changed.json", None])
        malformed_rows = [{"id": "DUP"}, {"id": "DUP"}, 42, {"model": "missing identity"}]
        malformed = rpc(cur, "preview_navision_backend_import", [json.dumps(malformed_rows), "synthetic-malformed.json", None])
        blocked_apply = rpc(cur, "apply_navision_backend_import", [
            "synthetic-blocked", json.dumps(malformed_rows), "synthetic-malformed.json", None,
            malformed["data"]["source_hash"], malformed["data"]["preview_hash"], malformed["data"]["base_revision"],
        ])
        stale = rpc(cur, "apply_navision_backend_import", [
            "synthetic-stale", json.dumps(rows), "synthetic-037.json", None,
            pdata["source_hash"], pdata["preview_hash"], pdata["base_revision"],
        ])
        large_rows = [{"id": f"SYN-LARGE-{index:04d}", "stock": f"LS{index:06d}"} for index in range(1000)]
        large = rpc(cur, "preview_navision_backend_import", [json.dumps(large_rows), "synthetic-large.json", None])

        rollback_args = ["synthetic-037-rollback", applied["data"]["batch_id"], applied["data"]["result_revision"]]
        rolled_back = rpc(cur, "rollback_navision_backend_import", rollback_args)
        rollback_replay = rpc(cur, "rollback_navision_backend_import", rollback_args)
        if rolled_back != rollback_replay:
            raise RuntimeError("Rollback response-loss replay did not return the exact stored response")

        restore_session_role(cur)
        cur.execute("select count(*) from public.navision_backend_records")
        rows_after_rollback = cur.fetchone()[0]
        after = operational_hashes(cur)

        impersonate(cur, admin_id, admin_email)
        direct_table_denied = permission_denied(cur, "select * from public.navision_backend_records limit 1")
        helper_denied = permission_denied(cur, "select public.navision_backend_normalize_row('{}'::jsonb)")
        restore_session_role(cur)
        cur.execute("""select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                       where n.nspname='public' and p.proname like '%navision%'
                         and p.prosecdef and p.proconfig @> array['search_path=pg_catalog, public, extensions']::text[]""")
        hardened_functions = cur.fetchone()[0]
        cur.execute("""select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                       where n.nspname='public' and p.proname like '%navision%' and p.prosecdef""")
        security_definer_functions = cur.fetchone()[0]
        cur.execute("""select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                       where n.nspname='public' and p.proname like '%navision%'""")
        navision_functions = cur.fetchone()[0]
        cur.execute("""select count(*) from pg_publication_tables where pubname='supabase_realtime'
                       and schemaname='public' and tablename='navision_backend_revision'""")
        revision_published = cur.fetchone()[0] == 1
        cur.execute("""select count(*) from pg_publication_tables where pubname='supabase_realtime'
                       and schemaname='public' and tablename in ('navision_backend_records','navision_import_items')""")
        payload_published = cur.fetchone()[0] != 0

        evidence = {
            "project_ref": EXPECTED_STAGING_REF,
            "preview_counts": pdata["counts"],
            "exact_apply_replay": applied == replayed,
            "records_applied": record_count,
            "automatic_links": linked_count,
            "proposed_link_for_known_vehicle": any(item.get("proposed_vehicle_id") == str(vehicle_id) for item in pdata["items"]),
            "changed_preview_counts": changed["data"]["counts"],
            "malformed_preview_counts": malformed["data"]["counts"],
            "malformed_blocking": malformed["data"]["blocking"],
            "blocked_apply_code": blocked_apply["code"],
            "stale_apply_code": stale["code"],
            "large_preview_counts": large["data"]["counts"],
            "rollback_ok": rolled_back["ok"],
            "exact_rollback_replay": rolled_back == rollback_replay,
            "records_after_rollback": rows_after_rollback,
            "operational_hashes_unchanged": before == after,
            "direct_table_denied": direct_table_denied,
            "internal_helper_denied": helper_denied,
            "security_definer_search_paths_hardened": hardened_functions == security_definer_functions,
            "security_definer_function_count": security_definer_functions,
            "navision_function_count": navision_functions,
            "revision_realtime_published": revision_published,
            "payload_realtime_not_published": not payload_published,
            "outer_transaction_rolled_back": True,
        }
        required_truths = [
            evidence["exact_apply_replay"], evidence["automatic_links"] == 0,
            evidence["malformed_blocking"], evidence["blocked_apply_code"] == "blocking_reconciliation",
            evidence["stale_apply_code"] in ("preview_changed", "stale_revision"), evidence["rollback_ok"],
            evidence["exact_rollback_replay"], evidence["records_after_rollback"] == 0,
            evidence["operational_hashes_unchanged"], evidence["direct_table_denied"],
            evidence["internal_helper_denied"], evidence["security_definer_search_paths_hardened"],
            evidence["revision_realtime_published"], evidence["payload_realtime_not_published"],
        ]
        if not all(required_truths):
            raise RuntimeError(f"Synthetic verification failed: {evidence}")
        return evidence
    finally:
        conn.rollback()
        conn.close()


def safe_preview(export_path: Path) -> dict:
    ensure_staging()
    raw = export_path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != EXPECTED_EXPORT_SHA256:
        raise RuntimeError(f"Safe export hash mismatch: {digest}")
    payload = json.loads(raw)
    rows = payload.get("vehicles")
    if not isinstance(rows, list) or len(rows) != 210:
        raise RuntimeError("Safe export must contain exactly 210 vehicles")
    conn = get_conn()
    try:
        cur = conn.cursor()
        admin_id, admin_email = actor(cur, "administrator")
        impersonate(cur, admin_id, admin_email)
        result = rpc(cur, "preview_navision_backend_import", [json.dumps(rows), export_path.name, None])
        data = result.get("data", {})
        if not result.get("ok") or data.get("blocking") or data.get("operational_mutations") != 0:
            raise RuntimeError(f"Safe export preview failed: {result}")
        return {
            "project_ref": EXPECTED_STAGING_REF,
            "export_path": str(export_path),
            "export_sha256": digest,
            "records": len(rows),
            "preview_counts": data["counts"],
            "blocking": data["blocking"],
            "operational_mutations": data["operational_mutations"],
            "records_applied": 0,
            "source_hash": data["source_hash"],
            "preview_hash": data["preview_hash"],
            "base_revision": data["base_revision"],
        }
    finally:
        conn.rollback()
        conn.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("preflight", "synthetic", "safe-preview"))
    parser.add_argument("--export", type=Path)
    parser.add_argument("--evidence", type=Path)
    args = parser.parse_args()
    if args.mode == "preflight":
        result = preflight()
    elif args.mode == "synthetic":
        result = synthetic_suite()
    else:
        if not args.export:
            parser.error("safe-preview requires --export")
        result = safe_preview(args.export)
    if args.evidence:
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
