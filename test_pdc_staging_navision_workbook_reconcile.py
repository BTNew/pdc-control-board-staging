import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parent
MIG=ROOT/'supabase/staging_only/20260824160000_355_attach_existing_workbook_vehicle_to_navision.sql'
CTRL=ROOT/'scripts/pdc_staging_reconcile_workbook_navision.py'
class NavisionWorkbookReconcileTests(unittest.TestCase):
 def setUp(self):self.sql=MIG.read_text(encoding='utf-8');self.py=CTRL.read_text(encoding='utf-8')
 def test_candidate_is_exact_and_fail_closed(self):
  for x in ["cardinality(owner_ids)=1","source_system_normalized='pdc_pmb_workbook'","attach_exact_existing_workbook_vehicle","current_navision_stock_not_exactly_one","target_vin IS NULL OR v.vin_normalized IS NULL OR v.vin_normalized=target_vin","protected_backend_completed"]:self.assertIn(x,self.sql)
 def test_candidate_remains_private_and_governed(self):
  self.assertIn('REVOKE ALL ON FUNCTION public.pdc_pmb_workbook_canonical_candidate(uuid) FROM public,anon,authenticated,service_role',self.sql)
  self.assertIn('Manager + independent Administrator',self.sql)
 def test_migration_avoids_broad_or_destructive_shortcuts(self):
  upper=self.sql.upper();self.assertNotIn('TRUNCATE ',upper);self.assertNotIn('DISABLE TRIGGER',upper);self.assertNotIn(' ON DELETE CASCADE',upper);self.assertNotIn('GRANT ALL',upper)
 def test_controller_is_backup_and_target_bound(self):
  for x in ['0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0','7e1ba89c675c7afb3fafdd072f20aa0145096ad03672b2de7b283b9f551c9d16','EXPECTED_BATCH_COUNTS={"14450":736,"37047":234}','PRODUCTION_REF in base','microsoft_navision']:self.assertIn(x,self.py)
 def test_controller_preserves_unmatched_and_revokes_access(self):
  for x in ['eligible_pair_count":127','eligible_unique_stock_count":116','ineligible_pair_count":39','ineligible_unique_stock_count":37','viewer_restored','writer_revoked','zero_add_replay']:self.assertIn(x,self.py)
 def test_controller_requires_owner_confirmation(self):self.assertIn('CRAIG DIRECTED STAGING NAVISION STOCK MATCH REPAIR',self.py)
if __name__=='__main__':unittest.main()
