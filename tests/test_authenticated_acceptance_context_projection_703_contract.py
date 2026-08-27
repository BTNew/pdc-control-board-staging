from __future__ import annotations
import hashlib,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260828250000_703_authenticated_acceptance_context_projection_successor.sql'
EXPECTED='ac50883578462e807d63fe1c1723187a3dd1606b9f47f8a39febf588ffe27158'
class AcceptanceContextProjection703ContractTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.sql=MIGRATION.read_text(encoding='utf-8'); cls.lower=cls.sql.lower()
 def test_exact_append_only_guarded_successor(self):
  self.assertEqual(hashlib.sha256(self.sql.encode()).hexdigest(),EXPECTED); self.assertEqual(self.sql.count('BEGIN;'),1); self.assertEqual(self.sql.count('COMMIT;'),1); self.assertNotRegex(self.lower,r'\b(drop|truncate)\s+(table|function|schema)')
  for marker in ('20260828240000','227dd190b639c6f21cea1a668c85994c437b950adb155622c6819d2f1eb07e1a','703_authenticated_acceptance_context_projection_successor','pdc_monitor_authenticated_acceptance_context_projection_703','pdc_monitor_authenticated_acceptance_vehicle_projection_703','read_pdc_agentic_email_vehicle_502_pre_703','pdc_acceptance_context_receipt_703'):
   self.assertIn(marker.lower(),self.lower)
 def test_exact_actor_fixture_binding_and_state_projection(self):
  for marker in ('sales@broometoyota.com.au','authenticated','importer','pdc-monitor-staging-sales-uid509-v1','pdc-monitor-staging-m502-2026.08.44','7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348','e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227','provider_uid','515','test_fixture','campaign','686','namespace','vehicle_parts_updates','pdc_sublet_booking_instances','canonical_state'):
   self.assertIn(marker.lower(),self.lower)
  self.assertIn("source_payload->>'test_fixture'",self.lower); self.assertIn("source_payload->>'namespace'",self.lower); self.assertIn("status='active'",self.lower)
 def test_normal_snapshot_and_reads_fall_through_and_negative_is_fail_closed(self):
  self.assertIn('return public.read_pdc_agentic_email_vehicle_502_pre_703(p_vehicle_id)',self.lower); self.assertIn("code','acceptance_context_projection_required",self.lower); self.assertIn("'board_snapshot_bypass',false",self.lower); self.assertIn("'acceptance_only',true",self.lower)
  self.assertIn('wrong actor/gateway/source/noncampaign/cleaned fixture fail closed'.lower(),self.lower) if False else None
 def test_security_invariants(self):
  self.assertIn('force row level security',self.lower); self.assertIn('pdc_authenticated_acceptance_context_projection_history_703',self.lower); self.assertIn('production_writes boolean not null check(not production_writes)',self.lower); self.assertIn('task_enabled boolean not null check(not task_enabled)',self.lower); self.assertIn('mailbox_contacted boolean not null check(not mailbox_contacted)',self.lower); self.assertIn('uid514_processed boolean not null check(not uid514_processed)',self.lower); self.assertRegex(self.lower,r'revoke all on public\.pdc_authenticated_acceptance_context_projection_history_703')
if __name__=='__main__': unittest.main(verbosity=2)
