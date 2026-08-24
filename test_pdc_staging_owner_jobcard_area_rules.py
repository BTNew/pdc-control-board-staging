import importlib.util,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CTRL=ROOT/'scripts/pdc_staging_apply_owner_jobcard_area_rules.py';MIG=ROOT/'supabase/staging_only/20260824190000_358_craig_owner_jobcard_area_rules.sql'
MIG2=ROOT/'supabase/staging_only/20260824200000_359_defer_past_planned_booking_duration_sync.sql'
MIG3=ROOT/'supabase'/'staging_only'/'20260824210000_360_craig_owner_jobcard_work_key_precedence.sql'
MIG4=ROOT/'supabase'/'staging_only'/'20260824230000_362_align_anderson_plugs_and_job_counts.sql'
spec=importlib.util.spec_from_file_location('owner_rules',CTRL);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
import sys
sys.path.insert(0,str(ROOT/'scripts'))
import pdc_staging_operation_workbook_import as workbook_import
class OwnerJobcardAreaRuleTests(unittest.TestCase):
 def test_owner_examples(self):
  cases={
   'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Smart Pin':('fitting','towbar'),
   'ARB FRONTIER LONG RANGE FUEL TANK - SUB TANK REPLACEM':('hoist','long_range'),
   '1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Boa':('fitting','fire'),
   'SUPPLY AND FIT DUAL 12V ACC SOCKET IN MODULE':('electrical','socket'),
   'Supply and Fit 12v PLUG To Rear':('electrical','socket'),
   '50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKET':('electrical','socket'),
   'ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah':('electrical','battery'),
   'FIT XRS 370c -Select Aerial additional Job Line':('electrical','xrs'),
   'Fit Navman IVMS with Cardex Interface system':('electrical','navman')}
  for d,e in cases.items():self.assertEqual(e,m.classify(d))
 def test_workbook_classifier_uses_same_owner_precedence(self):
  cases={
   'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Smart Pin':'fitting',
   'Tow Bar Tongue Kit (Long) with Flat Plug':'fitting',
   'ARB FRONTIER LONG RANGE FUEL TANK - SUB TANK REPLACEM':'hoist',
   '1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Boa':'fitting',
   'SUPPLY AND FIT DUAL 12V ACC SOCKET IN MODULE':'electrical',
   'ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah':'electrical',
   'FIT XRS 370c -Select Aerial additional Job Line':'electrical',
   'Fit Navman IVMS with Cardex Interface system':'electrical',
   '50A ANDERSON PLUG IN HIDRIVE CANOPY NEXT TO ACC SOCKET':'electrical'}
  for d,e in cases.items():self.assertEqual(e,workbook_import.classify(d))
  _,meta=workbook_import.payload();self.assertEqual(505,meta['mapped_operation_count']);self.assertEqual(983,meta['quarantined_operation_count'])
 def test_towbar_precedes_flat_plug(self):self.assertEqual(('fitting','towbar'),m.classify('Tow Bar Tongue Kit (Long) with Flat Plug'))
 def test_exact_scope_counts_are_frozen(self):
  self.assertEqual(200,m.EXPECTED_WRONG);self.assertEqual({'electrical':25,'fitting':146,'hoist':29},m.TARGET_COUNTS)
 def test_migration_is_versioned_and_alias_complete(self):
  s=MIG.read_text(encoding='utf-8')
  for x in ['towbars_fitting','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical','long_range_tanks_hoist','fire extinuisher','bcdc1225d','sub tank replacem','original_telegram_instruction','pdc_supervised_rule_events'] :self.assertIn(x,s)
 def test_canonical_sql_classifier_has_same_precedence(self):
  s=MIG3.read_text(encoding='utf-8');u=s.upper()
  for x in ['33791874c6f3badc1c6426dd5fbde15fc4dc3094a2383e416ecad176a15fd5c7','tow ?bars?','long range(r)?','fire ext','12v','battery box','bcdc','xrs ?370c','navman','cardex','20260824200000'] :self.assertIn(x,s)
  self.assertLess(s.index("WHEN d~'(^| )tow ?bars?"),s.index("WHEN d~'(^| )(canopy|tray|fabricat)"))
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
 def test_anderson_plug_extension_is_guarded_and_preserves_hours(self):
  s=MIG4.read_text(encoding='utf-8');u=s.upper()
  for x in ['299721a575227fe7d1a2da5b704e662d565a4c180abaafa33a50eca9be98fc73','anderson plug','accessory_12v_socket_plug_electrical','589342a7-8d42-48d5-8d3b-fde6ea878034','estimated_hours=2','hours_preserved','bookings_changed'] :self.assertIn(x,s)
  self.assertLess(s.index("WHEN d~'(^| )tow ?bars?"),s.index("WHEN d~'(^| )anderson plugs?"))
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
 def test_past_planned_booking_duration_is_preserved_and_audited(self):
  s=MIG2.read_text(encoding='utf-8');u=s.upper()
  for x in ['cea8497d2a1b6636d433f267f9ae826d94e6b1a298d55ebdb28d5ba3775d100b','operation_estimate_duration_reconcile_deferred','preserve already-started queued/planned booking window',"v_booking.scheduled_start_at<=clock_timestamp()",'20260824190000'] :self.assertIn(x,s)
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
 def test_staging_guards_and_no_broad_authority(self):
  s=MIG.read_text(encoding='utf-8');u=s.upper()
  for x in ['cdsmnqxtyyoeoznmbidd','PDC_PRODUCTION_ENVIRONMENT_SENTINEL','20260824180000','MONITORED_MAILBOXES','PDC_MONITOR_STAGE_ACTIVATION_WRITERS']:self.assertIn(x,u if x.isupper() else s)
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
if __name__=='__main__':unittest.main()
