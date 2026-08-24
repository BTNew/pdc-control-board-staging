import importlib.util,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parent
CTRL=ROOT/'scripts/pdc_staging_apply_owner_jobcard_area_rules.py';MIG=ROOT/'supabase/staging_only/20260824190000_358_craig_owner_jobcard_area_rules.sql'
MIG2=ROOT/'supabase/staging_only/20260824200000_359_defer_past_planned_booking_duration_sync.sql'
spec=importlib.util.spec_from_file_location('owner_rules',CTRL);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class OwnerJobcardAreaRuleTests(unittest.TestCase):
 def test_owner_examples(self):
  cases={
   'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Smart Pin':('fitting','towbar'),
   'ARB FRONTIER LONG RANGE FUEL TANK - SUB TANK REPLACEM':('hoist','long_range'),
   '1.5 KG FIRE EXT TO CARGO BARRIER or L/H Tray Head Boa':('fitting','fire'),
   'SUPPLY AND FIT DUAL 12V ACC SOCKET IN MODULE':('electrical','socket'),
   'Supply and Fit 12v PLUG To Rear':('electrical','socket'),
   'ARB Battery Box Mounted in Tray - BCDC1225D - 100Ah':('electrical','battery'),
   'FIT XRS 370c -Select Aerial additional Job Line':('electrical','xrs'),
   'Fit Navman IVMS with Cardex Interface system':('electrical','navman')}
  for d,e in cases.items():self.assertEqual(e,m.classify(d))
 def test_towbar_precedes_flat_plug(self):self.assertEqual(('fitting','towbar'),m.classify('Tow Bar Tongue Kit (Long) with Flat Plug'))
 def test_exact_scope_counts_are_frozen(self):
  self.assertEqual(200,m.EXPECTED_WRONG);self.assertEqual({'electrical':25,'fitting':146,'hoist':29},m.TARGET_COUNTS)
 def test_migration_is_versioned_and_alias_complete(self):
  s=MIG.read_text(encoding='utf-8')
  for x in ['towbars_fitting','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical','long_range_tanks_hoist','fire extinuisher','bcdc1225d','sub tank replacem','original_telegram_instruction','pdc_supervised_rule_events'] :self.assertIn(x,s)
 def test_past_planned_booking_duration_is_preserved_and_audited(self):
  s=MIG2.read_text(encoding='utf-8');u=s.upper()
  for x in ['cea8497d2a1b6636d433f267f9ae826d94e6b1a298d55ebdb28d5ba3775d100b','operation_estimate_duration_reconcile_deferred','preserve already-started queued/planned booking window',"v_booking.scheduled_start_at<=clock_timestamp()",'20260824190000'] :self.assertIn(x,s)
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
 def test_staging_guards_and_no_broad_authority(self):
  s=MIG.read_text(encoding='utf-8');u=s.upper()
  for x in ['cdsmnqxtyyoeoznmbidd','PDC_PRODUCTION_ENVIRONMENT_SENTINEL','20260824180000','MONITORED_MAILBOXES','PDC_MONITOR_STAGE_ACTIVATION_WRITERS']:self.assertIn(x,u if x.isupper() else s)
  for x in ['TRUNCATE ','DISABLE TRIGGER','GRANT ALL',' ON DELETE CASCADE']:self.assertNotIn(x,u)
if __name__=='__main__':unittest.main()
