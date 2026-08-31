from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/"supabase/staging_only/20260831230000_857_attachment_claim_839_scope_compatibility_successor.sql").read_text(encoding="utf-8")
LOWER=SQL.lower()
class MonitorAttachment857Tests(unittest.TestCase):
 def test_append_only_and_exact_predecessor(self):
  self.assertEqual(SQL.count("BEGIN;"),1); self.assertEqual(SQL.count("COMMIT;"),1)
  self.assertIn("20260831220000",SQL); self.assertIn("856_active_scope_enabled_pilot_compatibility_successor",LOWER)
  self.assertIn("20260831230000",SQL); self.assertNotIn("drop table",LOWER); self.assertNotIn("delete from",LOWER)
 def test_claim_scope_and_replay_guards(self):
  for marker in ("get_pdc_monitor_intake_attachments_735","pdc_monitor_authenticated_active_scope_839","p_claim_token","p_gateway_instance_id","locked_at>=clock_timestamp()-interval '10 minutes'","pdc_email_monitor_storage_reconciliations_735","grant execute","authenticated"):
   self.assertIn(marker,LOWER)
  self.assertNotIn("pdc_monitor_authenticated_active_scope_674",LOWER)
if __name__=="__main__": unittest.main(verbosity=2)
