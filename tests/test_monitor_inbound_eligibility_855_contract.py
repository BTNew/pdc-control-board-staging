from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/"supabase/staging_only/20260831210000_855_deterministic_inbound_sender_eligibility_successor.sql").read_text(encoding="utf-8")
LOWER=SQL.lower()
class MonitorInboundEligibility855Tests(unittest.TestCase):
 def test_append_only_and_predecessor_guard(self):
  self.assertEqual(SQL.count("BEGIN;"),1); self.assertEqual(SQL.count("COMMIT;"),1); self.assertEqual(LOWER.count("create or replace function public.enqueue_pdc_email_intake"),1)
  self.assertIn("20260831200000",SQL); self.assertIn("854_exact_claim_839_845_compatibility_successor",LOWER)
  self.assertIn("20260831210000'",SQL); self.assertNotIn("DROP TABLE",SQL.upper()); self.assertNotIn("DELETE FROM",SQL.upper())
 def test_non_enrolled_is_deterministic_review_receipt(self):
  for marker in ("pdc_monitor_inbound_eligibility_receipts_855","pdc_monitor_sender_not_enrolled","review_queued","receipt_key","on conflict(receipt_key) do nothing","board_mutations=0","mailbox_flags_changed","production_writes","pdc_855_receipt_immutable"):
   self.assertIn(marker,LOWER)
  self.assertIn("return jsonb_build_object('ok',true,'code','pdc_monitor_sender_not_enrolled'",LOWER)
  self.assertIn("'idempotent',true",LOWER)
 def test_approved_path_and_protections_remain_exact(self):
  for marker in ("pdc_monitor_authenticated_active_scope_839","v_sender_enrolled","sales@broometoyota.com.au","pmbcontroller@gmail.com","pdc-monitor-staging-sales-uid509-v1","pdc_production_environment_sentinel","p_message->>'provider_uid'","lower(coalesce(p_message->>'source_hash',''))"):
   self.assertIn(marker,LOWER)
  self.assertNotIn("pdc_monitor_actor_scope()",LOWER)
if __name__=="__main__": unittest.main(verbosity=2)
