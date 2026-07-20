#!/usr/bin/env python3
"""Rollback-only execution test for migration 037 against guarded staging."""
from __future__ import annotations
import json
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "_staging_test_tools")]
from staging_conn import get_conn  # type: ignore  # noqa: E402
from staging_env import assert_staging_target, required  # type: ignore  # noqa: E402

SQL = (ROOT / "supabase" / "migrations" / "037_shared_navision_backend_store.sql").read_text(encoding="utf-8")
TABLES = (
    "navision_backend_revision", "navision_import_batches", "navision_backend_records",
    "navision_import_items", "navision_operation_receipts", "navision_rollback_items",
    "navision_backend_audit",
)

def rpc(cur, name, args):
    cur.execute(f"select public.{name}(" + ",".join(["%s"] * len(args)) + ")", args)
    return cur.fetchone()[0]

def impersonate(cur, user_id, email="rollback-only@example.invalid"):
    cur.execute("select set_config('request.jwt.claims',%s,true),set_config('role','authenticated',true)",
                (json.dumps({"sub": str(user_id), "email": email, "role": "authenticated"}),))

def postgres(cur):
    cur.execute("select set_config('role','postgres',true)")

def admin(cur):
    cur.execute("select auth_user_id,email from public.pdc_user_roles where active and account_status='approved' and role::text='administrator' and auth_user_id is not null order by email limit 1")
    row = cur.fetchone()
    if not row:
        raise RuntimeError("No staging administrator available")
    return row

def main():
    assert_staging_target(database_url=required("PDC_STAGING_DATABASE_URL"))
    conn = get_conn()
    cur = conn.cursor()
    evidence = {}
    try:
        cur.execute("select count(*) from information_schema.tables where table_schema='public' and table_name=any(%s)", (list(TABLES),))
        if cur.fetchone()[0] != 0:
            raise RuntimeError("Rollback-only migration test requires 037 to be unapplied")
        cur.execute(SQL)
        cur.execute(SQL)
        cur.execute("select count(*) from information_schema.tables where table_schema='public' and table_name=any(%s)", (list(TABLES),))
        evidence["tables_after_double_execute_inside_transaction"] = cur.fetchone()[0]

        admin_id, admin_email = admin(cur)
        impersonate(cur, admin_id, admin_email)
        null_preview = rpc(cur, "preview_navision_backend_import", [None, "null.json", None])
        evidence["null_rows_code"] = null_preview.get("code")
        unknown_id = uuid.uuid4()
        impersonate(cur, unknown_id)
        unauthorized = rpc(cur, "get_navision_backend_snapshot", [None, 10, None])
        evidence["unapproved_user_code"] = unauthorized.get("code")

        # Apply a sentinel as administrator, then prove operator projection omits it.
        impersonate(cur, admin_id, admin_email)
        rows = [{"id": "AA-SENTINEL", "customer_secret": "PII-SENTINEL-DO-NOT-LEAK"}]
        preview = rpc(cur, "preview_navision_backend_import", [json.dumps(rows), "sentinel.json", None])
        pdata = preview["data"]
        applied = rpc(cur, "apply_navision_backend_import", ["tx-apply-sentinel", json.dumps(rows), "sentinel.json", None,
                                                               pdata["source_hash"], pdata["preview_hash"], pdata["base_revision"]])
        bulk_rows = [{"id": f"TX-BULK-{index:04d}", "stock": f"TXS{index:06d}"} for index in range(501)]
        bulk_preview = rpc(cur, "preview_navision_backend_import", [json.dumps(bulk_rows), "bulk.json", None])
        bdata = bulk_preview["data"]
        bulk_applied = rpc(cur, "apply_navision_backend_import", [
            "tx-apply-bulk", json.dumps(bulk_rows), "bulk.json", None,
            bdata["source_hash"], bdata["preview_hash"], bdata["base_revision"],
        ])
        postgres(cur)
        cur.execute("select count(*),count(row_index),count(distinct row_index) from public.navision_import_items where batch_id=%s", (bulk_applied["data"]["batch_id"],))
        reconciliation_counts = cur.fetchone()
        impersonate(cur, admin_id, admin_email)
        cursor = None
        paged_items = 0
        page_count = 0
        while True:
            report = rpc(cur, "get_navision_reconciliation_report", [bulk_applied["data"]["batch_id"], cursor, 500])
            page_count += 1
            paged_items += len(report["data"]["items"])
            cursor = report["data"].get("next_row_index")
            if not report["data"].get("has_more"):
                break
        evidence["reconciliation_item_counts"] = list(reconciliation_counts)
        evidence["reconciliation_paged_items"] = paged_items
        evidence["reconciliation_page_count"] = page_count
        postgres(cur)
        cur.execute("update public.pdc_user_roles set role='operator' where auth_user_id=%s", (admin_id,))
        impersonate(cur, admin_id, admin_email)
        operator_snapshot = rpc(cur, "get_navision_backend_snapshot", [None, 10, None])
        evidence["operator_payload_sentinel_absent"] = "PII-SENTINEL" not in json.dumps(operator_snapshot)
        evidence["operator_data_access"] = operator_snapshot.get("data", {}).get("data_access")
        evidence["operator_snapshot_code"] = operator_snapshot.get("code")
        evidence["operator_snapshot_keys"] = sorted(operator_snapshot.keys())
        postgres(cur)
        cur.execute("update public.pdc_user_roles set role='administrator' where auth_user_id=%s", (admin_id,))
        impersonate(cur, admin_id, admin_email)
        admin_export = rpc(cur, "export_navision_backend_records", [None, 10, bulk_applied["data"]["result_revision"]])
        evidence["admin_export_contains_sentinel"] = "PII-SENTINEL-DO-NOT-LEAK" in json.dumps(admin_export)

        # Prove row-level drift blocks rollback before receipt/revision mutation.
        postgres(cur)
        cur.execute("update public.navision_backend_records set normalized_data=normalized_data||%s::jsonb where source_record_id='TX-BULK-0000'", (json.dumps({"drift": True}),))
        cur.execute("select revision from public.navision_backend_revision where singleton")
        before_revision = cur.fetchone()[0]
        cur.execute("select count(*) from public.navision_operation_receipts")
        before_receipts = cur.fetchone()[0]
        impersonate(cur, admin_id, admin_email)
        drift = rpc(cur, "rollback_navision_backend_import", ["tx-drift-rollback", bulk_applied["data"]["batch_id"], before_revision])
        postgres(cur)
        cur.execute("select revision from public.navision_backend_revision where singleton")
        after_revision = cur.fetchone()[0]
        cur.execute("select count(*) from public.navision_operation_receipts")
        after_receipts = cur.fetchone()[0]
        evidence["rollback_drift_code"] = drift.get("code")
        evidence["rollback_drift_no_revision_or_receipt"] = before_revision == after_revision and before_receipts == after_receipts

        checks = {
            "tables": evidence["tables_after_double_execute_inside_transaction"] == 7,
            "null": evidence["null_rows_code"] == "invalid_input",
            "auth": evidence["unapproved_user_code"] == "unauthorized",
            "operator": evidence["operator_payload_sentinel_absent"] and evidence["operator_data_access"] == "metadata_only",
            "admin": evidence["admin_export_contains_sentinel"],
            "pagination": evidence["reconciliation_item_counts"] == [502, 502, 502] and evidence["reconciliation_paged_items"] == 502 and evidence["reconciliation_page_count"] == 2,
            "drift": evidence["rollback_drift_code"] == "rollback_state_drift" and evidence["rollback_drift_no_revision_or_receipt"],
        }
        if not all(checks.values()):
            raise RuntimeError(f"Rollback-only migration assertions failed: {evidence}")
    finally:
        conn.rollback()
        cur = conn.cursor()
        cur.execute("select count(*) from information_schema.tables where table_schema='public' and table_name=any(%s)", (list(TABLES),))
        evidence["tables_after_outer_rollback"] = cur.fetchone()[0]
        conn.close()
    if evidence["tables_after_outer_rollback"] != 0:
        raise RuntimeError(f"Migration transaction leaked objects: {evidence}")
    print(json.dumps(evidence, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()
