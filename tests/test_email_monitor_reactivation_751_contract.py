from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SQL=ROOT/'supabase/staging_only/20260829150000_751_reactivate_exact_email_monitor_after_recovery.sql'
class Reactivation751Contract(unittest.TestCase):
 def test_guarded_exact_reactivation(self):
  s=SQL.read_text().lower()
  for x in ('750_project_recovered_stock_qc_operation_lines','pdc_email_monitor_reactivation_751','pdc_monitor_stage_activation_writers','pdc_qc_retest_photo_evidence_747','pdc_stock_13000769_recovery_receipts_747','pdc_production_environment_sentinel','pmbcontroller@gmail.com','sales@broometoyota.com.au','pdc_email_monitor_reactivation_rolled_back_751'):
   self.assertIn(x,s)
  self.assertIn("mailbox_flags_changed boolean not null check(not mailbox_flags_changed)",s)
  self.assertIn("task_enabled boolean not null check(not task_enabled)",s)
  self.assertNotIn('delete from public.monitored_mailboxes',s)
  self.assertNotIn('truncate ',s)
if __name__=='__main__':unittest.main(verbosity=2)
