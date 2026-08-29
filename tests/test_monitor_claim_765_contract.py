from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/staging_only/20260830040000_765_authenticated_exact_claim_floor_640_successor.sql').read_text(encoding='utf-8')
class MonitorClaim765ContractTests(unittest.TestCase):
 def test_exact_floor_successor_is_guarded_and_narrow(self):
  for marker in ('20260830030000','exact_manual_reimport_manifest_order_alias_fix','4912b9bb8dcb60af9c33cba9d7b46d154734e83288104a6fce28b972cef6f4c9','minimum_uid=640','PDC_732_EXACT_ACTOR_RUNTIME_UNAUTHORIZED','UID514','pmbcontroller@gmail.com','pdc-monitor-staging-sales-uid509-v1','GRANT EXECUTE ON FUNCTION public.claim_pdc_email_intake_authenticated_exact_732'):
   self.assertIn(marker,SQL)
  self.assertNotIn("minimum_uid=639",SQL)
  self.assertIn("to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL",SQL)
if __name__=='__main__': unittest.main(verbosity=2)
