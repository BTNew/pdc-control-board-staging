from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest
import json,os,sys
from urllib.parse import urlsplit
import psycopg2
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('campaign_mapping',ROOT/'scripts/run_authenticated_acceptance_campaign_686_staging.py');campaign=importlib.util.module_from_spec(spec);assert spec and spec.loader;spec.loader.exec_module(campaign)
class AuthenticatedAcceptancePlanMappingTests(unittest.TestCase):
 def test_exact_duplicate_body_and_attachment_actions_map_once(self):
  actions=[
   {'vehicle_id':'vehicle-1','action_type':'parts_complete','target':{'parts.complete':True},'expected':{'parts.complete':True},'evidence_refs':['body'],'instruction_ids':['body-1']},
   {'vehicle_id':'vehicle-1','action_type':'parts_complete','target':{'parts.complete':True},'expected':{'parts.complete':True},'evidence_refs':['attachment:fixture'],'instruction_ids':['attachment-1']},
  ]
  result=campaign.dedupe_planned_actions(actions)
  self.assertEqual(len(result),1)
  self.assertEqual(result[0]['instruction_ids'],['body-1'])
 def test_existing_booking_note_maps_to_canonical_sublet_update(self):
  action={'action_type':'notes_set','target':{'vehicle.notes':'Existing booking update'},'expected':{'vehicle.notes':'Existing booking update'},'instruction_ids':['body-1'],'evidence_refs':['body'],'reason':'explicit vehicle note instruction'}
  booking={'booking_id':'11111111-1111-4111-8111-111111111111','version':1,'out_date':'2026-09-01','expected_return_date':'2026-09-30','notes':'PDC acceptance synthetic fixture'}
  result=campaign.map_existing_booking_action(action,booking)
  self.assertEqual(result['action_type'],'sublet_update')
  self.assertEqual(result['target'],{'sublet.booking_id':booking['booking_id'],'sublet.version':1,'sublet.out_date':'2026-09-01','sublet.expected_return_date':'2026-09-30','sublet.notes':'Existing booking update'})
  self.assertEqual(result['instruction_ids'],['body-1'])
 def test_live_fixture_sublet_return_window_covers_reviewed_acceptance_date(self):
  bootstrap=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py');s=importlib.util.spec_from_file_location('b730',bootstrap);m=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(m);v=json.loads(m.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode());m.validate(v);u=v['PDC_STAGING_DATABASE_URL'];e=urlsplit(u);os.environ.update({k:v[k] for k in ('PDC_STAGING_SSLROOTCERT','PDC_STAGING_SSLROOTCERT_SHA256')});sys.path.insert(0,str(ROOT));from scripts.pdc_staging_runtime import trusted_sslrootcert
  c=psycopg2.connect(host=e.hostname,port=e.port or 5432,user=e.username,password=e.password,dbname='postgres',sslmode='verify-full',sslrootcert=trusted_sslrootcert(),connect_timeout=15,application_name='pdc730_red_regression')
  try:
   with c.cursor() as q:q.execute("select pg_get_functiondef('public.create_pdc_authenticated_acceptance_campaign_686()'::regprocedure)");src=q.fetchone()[0]
   self.assertIn("'2026-09-30'",src)
  finally:c.rollback();c.close()
if __name__=='__main__':unittest.main()
