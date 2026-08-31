from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/"supabase/staging_only/20260831220000_856_active_scope_enabled_pilot_compatibility_successor.sql").read_text(encoding="utf-8")
LOWER=SQL.lower()
class MonitorActiveScope856Tests(unittest.TestCase):
 def test_append_only_guard_and_enabled_pilot_alignment(self):
  self.assertEqual(SQL.count("BEGIN;"),1); self.assertEqual(SQL.count("COMMIT;"),1)
  self.assertIn("20260831210000",SQL); self.assertIn("855_deterministic_inbound_sender_eligibility_successor",LOWER)
  self.assertIn("20260831220000",SQL); self.assertIn("enabled and automatic_rule_application and automatic_authenticated_jobcards",LOWER)
  self.assertNotIn("drop table",LOWER); self.assertNotIn("delete from",LOWER)
 def test_exact_scope_guards_remain(self):
  for marker in ("pdc_monitor_authenticated_active_scope_839","sales@broometoyota.com.au","pdc-monitor-staging-sales-uid509-v1","pmbcontroller@gmail.com","pdc_production_environment_sentinel","task_enabled","mailbox_contacted","uid514_processed","outbound_email_enabled"):
   self.assertIn(marker,LOWER)
if __name__=="__main__": unittest.main(verbosity=2)
