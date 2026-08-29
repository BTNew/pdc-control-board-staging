from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1];SQL=ROOT/'supabase/staging_only/20260829151000_752_reactivate_exact_email_monitor_after_751.sql'
class Reactivation752Contract(unittest.TestCase):
 def test_exact_serialized_reactivation(self):
  s=SQL.read_text().lower()
  for x in ('751_authenticated_parts_received_contract','pdc_email_monitor_reactivation_752','pdc_monitor_stage_activation_writers','pdc_qc_retest_photo_evidence_747','pdc_stock_13000769_recovery_receipts_747','pdc_email_monitor_reactivation_rolled_back_752','pmbcontroller@gmail.com','sales@broometoyota.com.au'):
   self.assertIn(x,s)
  self.assertIn('task_enabled boolean not null check(not task_enabled)',s);self.assertIn('mailbox_flags_changed boolean not null check(not mailbox_flags_changed)',s)
  self.assertNotIn('delete from public.monitored_mailboxes',s);self.assertNotIn('truncate ',s)
if __name__=='__main__':unittest.main(verbosity=2)
