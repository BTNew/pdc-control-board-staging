from __future__ import annotations
import importlib.util,json,unittest
from pathlib import Path
import psycopg2
ACTOR='df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b';EMAIL='sales@broometoyota.com.au';GATEWAY='pdc-monitor-staging-sales-uid509-v1';RELEASE='pdc-monitor-staging-m502-2026.08.44';SOURCE='e850c319989d98b45b95a28aa815d78e2c2e3a4b';MANIFEST='d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d';PLANNER='7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348';TRUST='e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227'
class FinalActivationLiveTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  s=importlib.util.spec_from_file_location('b',Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py'));b=importlib.util.module_from_spec(s);assert s and s.loader;s.loader.exec_module(b);v=json.loads(b.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode());b.validate(v);cls.conn=psycopg2.connect(v['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=v['PDC_STAGING_SSLROOTCERT'],connect_timeout=20,application_name='pdc-final-activation-live-test');cls.conn.autocommit=False
 @classmethod
 def tearDownClass(cls): cls.conn.rollback();cls.conn.close()
 def set_claims(self,sub=ACTOR,email=EMAIL,role='authenticated'):
  with self.conn.cursor() as c:c.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)",(sub,json.dumps({'sub':sub,'email':email,'role':role})))
 def att(self,gateway=GATEWAY):
  with self.conn.cursor() as c:c.execute("select public.verify_pdc_monitor_runtime_binding_authenticated_674(%s,%s,%s,%s,%s,%s,%s)",('active',gateway,RELEASE,SOURCE,MANIFEST,PLANNER,TRUST));return c.fetchone()[0]
 def test_repeated_attestation_and_terminal_uid514_are_stable(self):
  self.set_claims();a=self.att();b=self.att();self.assertEqual(a,b);self.assertTrue(a['ok']);self.assertEqual(a['code'],'runtime_binding_verified_authenticated_674');self.assertTrue(a['mailbox_active']);self.assertEqual(a['active_mailbox_count'],1);self.assertTrue(a['writer_active']);self.assertFalse(a['production_writes']);self.assertFalse(a['task_enabled']);self.assertFalse(a['mailbox_contacted']);self.assertFalse(a['uid514_processed'])
  with self.conn.cursor() as c:c.execute("select public.read_pdc_uid514_transaction_receipt_authenticated_674(25751401)");r=c.fetchone()[0]
  self.assertEqual(r['code'],'uid514_receipt_terminal');self.assertTrue(r['terminal']);self.assertEqual((r['mailbox'],r['folder'],r['uidvalidity'],r['uid']),('pmbcontroller@gmail.com','Inbox',1,514));self.assertTrue(r['physical_mailbox_fetch']);self.assertFalse(r['mailbox_flags_changed']);self.assertFalse(r['synthetic_staging_commissioning']);self.assertEqual((r['vehicle_operations'],r['operation_lines']),(5,5));self.assertNotIn('attempt_metadata',r)
  self.conn.rollback()
 def test_empty_replay_claim_and_direct_boundaries(self):
  self.set_claims()
  with self.conn.cursor() as c:
   c.execute("select public.claim_pdc_email_intake_authenticated_exact_732(10,%s)",(GATEWAY,));r=c.fetchone()[0];self.assertTrue(r['ok']);self.assertEqual(r['count'],0);self.assertEqual(r['items'],[])
   c.execute("select has_function_privilege('authenticated','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('anon','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('service_role','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('authenticated','public.claim_pdc_email_intake_batch(integer,text)','execute'),has_table_privilege('authenticated','public.pdc_email_monitor_authenticated_mailbox_activation_controls_674','select'),(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_email_monitor_authenticated_mailbox_activation_controls_674'::regclass)")
   self.assertEqual(c.fetchone(),(True,False,False,False,False,True))
  self.conn.rollback()
 def test_wrong_identity_and_gateway_fail_closed(self):
  self.set_claims()
  with self.assertRaises(psycopg2.Error) as gw:self.att('wrong-gateway')
  self.assertEqual(gw.exception.pgcode,'42501');self.conn.rollback();self.set_claims('557dba7f-fd70-4b9e-aa7b-b83b717682a7','administrator2@staging.pdc-workshop.example.com')
  with self.assertRaises(psycopg2.Error) as x:self.att()
  self.assertEqual(x.exception.pgcode,'42501');self.conn.rollback()
if __name__=='__main__':unittest.main(verbosity=2)
