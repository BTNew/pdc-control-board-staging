from pathlib import Path
import re
MIGRATION=Path(__file__).resolve().parents[1]/"supabase/staging_only/20260829130000_746_purge_stock_13000769.sql"
CONTROLLER=Path(__file__).resolve().parents[1]/"scripts/apply_migration_746_staging.py"
def test_purge_746_contract():
 s=MIGRATION.read_text(encoding="utf-8")
 for marker in ("20260829120000","745_controller_parts_received_eta_repair","20260829130000','746_purge_stock_13000769'","PDC_746_TARGET_HEAD_SCOPE_OR_RECREATION_GUARD_FAILED","pdc_email_replay_fences_746","pdc_stock_purge_receipts_746","d777b071-a2b0-5367-893b-aa83a07fcfce","de800087-d086-4f7b-9569-bb8a88660475"):
  assert marker in s
 assert "to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL" in s
 assert "ALTER TABLE public.%I DISABLE TRIGGER USER" in s
 assert "NOTIFY pgrst,'reload schema'" in s
def test_purge_746_safety():
 s=MIGRATION.read_text(encoding="utf-8").lower()
 assert "truncate" not in s and "storage." not in s and "auth." not in s
 assert "pdc745_" not in s and "pdc746_" in s
def test_purge_746_controller():
 s=CONTROLLER.read_text(encoding="utf-8")
 for marker in ("PDC_BACKUP_ENCRYPTION_KEY","decrypt_backup","file_sha256","status='success'","encrypted","PDC_STAGING_DATABASE_URL"):
  assert marker in s
 assert re.search(r'head!=\("20260829120000","745_controller_parts_received_eta_repair"\)',s)
