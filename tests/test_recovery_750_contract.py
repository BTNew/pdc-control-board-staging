from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/20260829143000_750_project_recovered_stock_qc_operation_lines.sql"


def test_snapshot_750_exact_scope_and_projection():
    sql = SQL.read_text(encoding="utf-8")
    for marker in (
        "20260829142000",
        "749_append_qc_retest_photo_evidence",
        "20260829143000','750_project_recovered_stock_qc_operation_lines'",
        "get_pdc_email_vehicle_location_snapshot_pre_750",
        "get_pdc_email_vehicle_location_snapshot()",
        "pdc_qc_operation_lines_379",
        "d777b071-a2b0-5367-893b-aa83a07fcfce",
        "'operation_lines'",
        "'qc_retest'",
        "PDC_750_STAGING_OR_PREDECESSOR_GUARD_FAILED",
        "to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL",
    ):
        assert marker in sql
    assert "No other vehicle projection" in sql


def test_snapshot_750_does_not_mutate_evidence_or_other_vehicles():
    sql = SQL.read_text(encoding="utf-8").lower()
    assert "update public.pdc_qc_finalization" not in sql
    assert "delete from public.pdc_qc" not in sql
    assert "insert into public.pdc_qc" not in sql
    assert "pdc_stock_13000769_recovery_receipts_747" not in sql
    assert "case when (x->>'id')='d777b071-a2b0-5367-893b-aa83a07fcfce'" in sql
