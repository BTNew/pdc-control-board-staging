#!/usr/bin/env python3
"""Source and runner contract for staging stock-only stage-mapped workbook import."""
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parent
SQL = (ROOT / "supabase" / "staging_only" / "128_stock_only_stage_mapped_workbook_import.sql").read_text(encoding="utf-8")
RUNNER = (ROOT / "scripts" / "run_pdc_bulk_workbook_staging.py").read_text(encoding="utf-8")

for required in (
    "PDC_BULK_128_STAGING_SENTINEL_MISMATCH",
    "project_ref='cdsmnqxtyyoeoznmbidd'",
    "PDC_BULK_128_PREDECESSOR_127_IDENTITY_MISMATCH",
    "authorize_pdc_bulk_stock_stage_workbook",
    "preview_pdc_bulk_stock_stage_workbook",
    "apply_pdc_bulk_stock_stage_workbook",
    "read_pdc_bulk_stock_stage_receipt",
    "authorized_payload_sha256",
    "pmb-workshop-stages-v1",
    "protected_existing_lifecycle",
    "multiple_current_navision_stock_matches",
    "multiple_operational_stock_matches",
    "current_location",
    "'YH'",
    "'IT'",
    "completed_work_reopened',false",
    "booking_created',false",
    "parts_completion_created',false",
    "exact_stock_stage_replay",
):
    assert required in SQL, required

for forbidden in (
    "insert into public.notifications",
    "insert into public.notification",
    "send_email",
    "http_post",
    "net.http",
    "service_role",
):
    if forbidden == "service_role":
        assert "grant execute on function public.apply_pdc_bulk_stock_stage_workbook(uuid,text,text,text) to service_role" not in SQL.lower()
    else:
        assert forbidden not in SQL.lower(), forbidden

assert "alter table public.pdc_bulk_workbook_row_receipts alter column backend_record_id drop not null" in SQL
assert "check(operation_count>=0)" in SQL
assert "source JC and key numbers ignored as identity authority" in SQL
assert 'timeout=180' in RUNNER

sys.path.insert(0, str(ROOT))
from scripts import run_pdc_bulk_workbook_staging as runner

workbook = Path(r"C:\Users\nwmgr\Documents\PDC-JC-Stock-Operations-Import-20260802\Hermes_PDC_JC_Stock_Operations_Matched.xlsx")
args = runner.parser().parse_args([
    str(workbook),
    "--stage-map-policy", "pmb-workshop-stages-v1",
    "--expect-pairs", "411",
    "--expect-operations", "3483",
    "--expect-hours-count", "3280",
    "--expect-missing-hours", "203",
    "--expect-hours-total", "4310.1",
    "--expect-max-operations", "27",
])
seen = []

def fake_post(url, key, path, body, token=None):
    seen.append((path, body))
    if path.startswith("/auth/"):
        return {"access_token": "test-token"}
    if path.endswith("authorize_pdc_bulk_stock_stage_workbook"):
        return {"ok": True, "code": "stock_stage_authorized", "data": {
            "authorization_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            "workbook_sha256": body["p_workbook_sha256"],
            "payload_sha256": body["p_payload_sha256"],
            "expected_pair_count": 411,
            "expected_operation_count": 3483,
            "stage_mapping_policy": "pmb-workshop-stages-v1",
            "status": "available",
        }}
    if path.endswith("preview_pdc_bulk_stock_stage_workbook"):
        payload_sha = runner.adapt_workbook(workbook, stage_mapping_policy="pmb-workshop-stages-v1").evidence["payload_sha256"]
        return {"ok": True, "code": "stock_stage_preview_ready", "data": {
            "preview_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            "workbook_sha256": hashlib.sha256(workbook.read_bytes()).hexdigest(),
            "payload_sha256": payload_sha,
            "stage_mapping_policy": "pmb-workshop-stages-v1",
            "row_count": 411,
            "operation_count": 3483,
            "accepted_count": 411,
            "accepted_stock_count": 403,
            "quarantine_count": 0,
            "operation_quarantine_count": 0,
            "blocked_count": 0,
            "applyable": True,
        }}
    raise AssertionError(path)

env = {
    "PDC_STAGING_SUPABASE_URL": runner.EXPECTED_URL,
    "PDC_STAGING_ANON_KEY": "anon-test",
    "PDC_STAGING_ADMIN_EMAIL": "admin@example.invalid",
    "PDC_STAGING_ADMIN_PASSWORD": "not-a-real-password",
}
result = runner.execute(args, env=env, post=fake_post)
assert result["apply_performed"] is False
assert result["accepted_stock_count"] == 403
assert result["stock_only_rows"] == 11
assert seen[1][0].endswith("authorize_pdc_bulk_stock_stage_workbook")
assert seen[1][1]["p_payload_sha256"] == result["local_payload_file_sha256"]
assert seen[2][0].endswith("preview_pdc_bulk_stock_stage_workbook")
assert seen[2][1]["p_authorized_payload_sha256"] == result["local_payload_file_sha256"]
assert seen[2][1]["p_stage_mapping_policy"] == "pmb-workshop-stages-v1"
print("PDC stock-only stage-mapped workbook import contract passed.")
