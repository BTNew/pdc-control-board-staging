from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get('PDC_RUN_732_EXACT_CLAIM_LIVE_TESTS') == '1'
ACTOR = 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
EMAIL = 'sales@broometoyota.com.au'
GATEWAY = 'pdc-monitor-staging-sales-uid509-v1'
MAILBOX = '12fe383d-5c1e-5801-96e4-f67cf3e3bb57'


@unittest.skipUnless(RUN_LIVE, 'set PDC_RUN_732_EXACT_CLAIM_LIVE_TESTS=1 for authorised staging integration')
class BoundedExactClaim732LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
        spec = __import__('importlib.util', fromlist=['spec_from_file_location']).spec_from_file_location('bootstrap732', spec_path)
        bootstrap = __import__('importlib.util', fromlist=['module_from_spec']).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode())
        bootstrap.validate(values)
        cls.conn = psycopg2.connect(str(values['PDC_STAGING_DATABASE_URL']), connect_timeout=20, application_name='pdc732_exact_claim_live_test')
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self, sub=ACTOR, email=EMAIL, role='authenticated'):
        with self.conn.cursor() as cur:
            claims = json.dumps({'sub': sub, 'email': email, 'role': role})
            cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)", (sub, claims))

    def expect_scope_error(self, gateway=GATEWAY, sub=ACTOR, email=EMAIL, role='authenticated'):
        self.set_claims(sub, email, role)
        with self.conn.cursor() as cur:
            with self.assertRaises(psycopg2.Error) as raised:
                cur.execute('select public.claim_pdc_email_intake_authenticated_exact_732(1,%s)', (gateway,))
        self.assertEqual(raised.exception.pgcode, '42501')
        self.conn.rollback()

    def test_exact_actor_claim_returns_only_current_server_bound_rows(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute('select public.claim_pdc_email_intake_authenticated_exact_732(1,%s)', (GATEWAY,))
            result = cur.fetchone()[0]
        self.assertTrue(result['ok'])
        for item in result['items']:
            self.assertNotEqual(item['provider_uid'], 'imap_uid:514')
            uid = int(str(item['provider_uid']).split(':', 1)[1])
            self.assertGreaterEqual(uid, 639)
            self.assertLess(uid, 100000)
            self.assertEqual(item['gateway_instance_id'], GATEWAY)
            self.assertRegex(item['source_hash'], r'^[a-f0-9]{64}$')
        self.conn.rollback()

    def test_wrong_actor_gateway_and_role_fail_closed(self):
        self.expect_scope_error(gateway='wrong-gateway')
        self.expect_scope_error(sub='557dba7f-fd70-4b9e-aa7b-b83b717682a7', email='administrator2@staging.pdc-workshop.example.com')
        self.expect_scope_error(role='pdc_email_monitor')

    def test_privilege_matrix_and_uid514_exclusion(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select has_function_privilege('authenticated','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('anon','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('service_role','public.claim_pdc_email_intake_authenticated_exact_732(integer,text)','execute'),has_function_privilege('authenticated','public.claim_pdc_email_intake_batch(integer,text)','execute'),has_function_privilege('authenticated','public.claim_pdc_email_intake_authenticated_exact_731(integer,text)','execute')")
            self.assertEqual(cur.fetchone(), (True, False, False, False, False))
            cur.execute("select count(*) from public.ai_email_intake where provider_uid='imap_uid:514' and monitored_mailbox_id=%s", (MAILBOX,))
            self.assertEqual(cur.fetchone()[0], 1)
        self.conn.rollback()

    def test_terminal_replay_and_temporary_recovery_are_claim_bound(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute('select public.claim_pdc_email_intake_authenticated_exact_732(1,%s)', (GATEWAY,))
            result = cur.fetchone()[0]
            if not result['items']:
                self.skipTest('no current eligible queue row available for rollback rehearsal')
            item = result['items'][0]
            args = (item['id'], item['claim_token'], GATEWAY)
            cur.execute('select public.record_pdc_email_intake_result(%s,%s,%s,true,%s::jsonb,%s,%s,false,%s::jsonb)', (*args, json.dumps({'code':'review_required'}), 'review_required', 'bounded review rehearsal', '{}'))
            self.assertTrue(cur.fetchone()[0]['ok'])
            with self.assertRaises(psycopg2.Error) as replay:
                cur.execute('select public.record_pdc_email_intake_result(%s,%s,%s,true,%s::jsonb,%s,%s,false,%s::jsonb)', (*args, json.dumps({'code':'review_required'}), 'review_required', 'replay', '{}'))
            self.assertEqual(replay.exception.pgcode, '42501')
        self.conn.rollback()


if __name__ == '__main__':
    unittest.main(verbosity=2)
