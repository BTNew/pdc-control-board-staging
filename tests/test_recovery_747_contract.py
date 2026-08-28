from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/20260829140000_747_restore_stock_13000769_qc_retest.sql"
CONTROLLER = ROOT / "scripts/apply_migration_747_staging.py"


def test_recovery_747_exact_scope_and_predecessor():
    sql = SQL.read_text(encoding="utf-8")
    for marker in (
        "20260829130000",
        "746_purge_stock_13000769",
        "20260829140000','747_restore_stock_13000769_qc_retest'",
        "20260828_161016_aa9508",
        "13000769",
        "d777b071-a2b0-5367-893b-aa83a07fcfce",
        "de800087-d086-4f7b-9569-bb8a88660475",
        "847b7b9a-7f25-4a13-868d-fb3a95b9e447",
        "7326179925f024eb3f295bdc504aa84b15f416c6e37cf71b777f7946958a817d",
        "949a8fa7274364b43ecd1fb5248af9f7628f6350cc8196b41733f6322fb8d0e7",
        "pdc_admin_recover_stock_13000769_to_qc_747",
        "record_pdc_qc_retest_photo_747",
        "finalize_pdc_qc_retest_to_rft_747",
        "PDC_747_RECOVERED_STOCK_DELETE_BLOCKED",
        "PDC_747_FRESH_QC_PHOTO_REQUIRED_BEFORE_RFT",
        "pdc_qc_retest_supersessions_747",
        "pdc_email_replay_fences_746:uidvalidity-1-uid-639-stock-13000769",
    ):
        assert marker in sql
    assert "pdc_qc_salesperson_update_outbox_399" in sql
    assert "excluded_pending_outbox_count integer NOT NULL CHECK(excluded_pending_outbox_count=1)" in sql
    assert "PDC_747_STAGING_OR_PREDECESSOR_GUARD_FAILED" in sql
    assert "to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL" in sql


def test_recovery_747_is_append_only_and_not_broad_capability():
    sql = SQL.read_text(encoding="utf-8").lower()
    assert "truncate" not in sql
    assert "drop table" not in sql
    assert "delete from public.pdc_stock_purge_receipts_746" not in sql
    assert "update public.pdc_stock_purge_receipts_746" not in sql
    assert "delete from public.pdc_email_replay_fences_746" not in sql
    assert "update public.pdc_email_replay_fences_746" not in sql
    assert "pdc.747_retest_signoff" in sql
    assert "p_vehicle_id is distinct from 'd777b071-a2b0-5367-893b-aa83a07fcfce'" in sql


def test_recovery_747_controller_is_hash_bound_and_staging_only():
    source = CONTROLLER.read_text(encoding="utf-8")
    for marker in (
        "pdc_backup.decrypt_backup",
        "pdc_restore.load_table_rows",
        "CryptUnprotectData",
        "PDC_STAGING_DATABASE_URL",
        "STAGING_REF",
        "PRODUCTION_REF",
        "pdc-staging-747-recover-stock-13000769",
        "20260829130000",
        "20260829140000",
        "restored_row_count",
    ):
        assert marker in source
    assert re.search(r'EXCLUDED=\{\"pdc_qc_salesperson_update_outbox_399\"\}', source)
    assert "production_contacted" in source
    assert "PDC_PRODUCTION" not in source
