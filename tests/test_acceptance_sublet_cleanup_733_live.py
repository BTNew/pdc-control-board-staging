from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get('PDC_RUN_733_SUBLET_CLEANUP_LIVE_TESTS') == '1'
ACTOR = 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b'
EMAIL = 'sales@broometoyota.com.au'
BOOKING = '47dde42b-f768-4a3f-a680-28b6ae8f36f7'
VEHICLE = '2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02'
PROVIDER = '4cbd486c-78c2-42ce-987a-99d45d1eeaf4'
WORK = '97340bcf-b31d-48dc-921a-4d0afc87db10'


@unittest.skipUnless(RUN_LIVE, 'set PDC_RUN_733_SUBLET_CLEANUP_LIVE_TESTS=1 for authorised staging integration')
class AcceptanceSubletCleanup733LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
        spec = __import__('importlib.util', fromlist=['spec_from_file_location']).spec_from_file_location('bootstrap733', spec_path)
        bootstrap = __import__('importlib.util', fromlist=['module_from_spec']).module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode())
        bootstrap.validate(values)
        cls.conn = psycopg2.connect(str(values['PDC_STAGING_DATABASE_URL']), connect_timeout=20, application_name='pdc733_cleanup_live_test')
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def set_claims(self):
        with self.conn.cursor() as cur:
            claims = json.dumps({'sub': ACTOR, 'email': EMAIL, 'role': 'authenticated'})
            cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)", (ACTOR, claims))

    def test_cleanup_postconditions_and_board_target(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select to_jsonb(b) from public.pdc_sublet_booking_instances b where booking_id=%s", (BOOKING,)); booking = cur.fetchone()[0]
            cur.execute("select to_jsonb(v) from public.vehicles v where id=%s", (VEHICLE,)); vehicle = cur.fetchone()[0]
            cur.execute("select to_jsonb(w) from public.vehicle_work_items w where id=%s", (WORK,)); work = cur.fetchone()[0]
            cur.execute("select count(*) from public.pdc_sublet_booking_instances where vehicle_id=%s and status='active'", (VEHICLE,)); active_booking = cur.fetchone()[0]
            cur.execute("select count(*) from public.vehicle_work_items where vehicle_id=%s and lower(work_key)='sublet' and required and not completed", (VEHICLE,)); active_work = cur.fetchone()[0]
            cur.execute("select count(*) from public.pdc_acceptance_sublet_cleanup_history_733 where booking_id=%s", (BOOKING,)); history = cur.fetchone()[0]
            cur.execute("select to_jsonb(c) from public.pdc_acceptance_sublet_cleanup_controls_733 c where singleton"); control = cur.fetchone()[0]
            cur.execute("select public.get_pdc_email_vehicle_location_snapshot()"); board = cur.fetchone()[0]
        self.assertEqual((booking['status'], booking['version'], booking['returned_at'], booking['returned_by'], booking['provider_id'], booking['vehicle_id']), ('cancelled', 6, None, None, PROVIDER, VEHICLE))
        self.assertEqual((work['required'], work['completed']), (False, False))
        self.assertEqual((active_booking, active_work, history), (0, 0, 2))
        self.assertEqual((control['enabled'], control['used'], control['revoked_at']), (False, True, control['revoked_at']))
        self.assertEqual((vehicle['stock_number'], vehicle['source_system'], vehicle['source_record_id'], vehicle['current_location'], vehicle['version'], vehicle['visible_on_board']), ('13000765', 'microsoft_navision', '6ddb2053-3ca2-41aa-8ef5-0418582bcde0', 'Other', 9, True))
        rows = board.get('data', {}).get('vehicles', []) if isinstance(board, dict) else []
        target = [row for row in rows if isinstance(row, dict) and row.get('id') == VEHICLE]
        self.assertEqual(len(target), 1)
        self.assertEqual(target[0].get('stock_number'), '13000765')
        self.assertEqual(target[0].get('sublet_active_count', 0), 0)
        self.conn.rollback()

    def test_used_cleanup_and_wrong_environment_fail_closed(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            with self.assertRaises(psycopg2.Error) as used:
                cur.execute('select public.run_pdc_acceptance_sublet_cleanup_733(%s,%s)', (BOOKING, 'PDC-ACCEPTANCE-SUBLET-CLEANUP-733'))
            self.assertIn(used.exception.pgcode, {'55000', '42501'})
        self.conn.rollback()
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select set_config('app.environment','production',true)")
            with self.assertRaises(psycopg2.Error) as production:
                cur.execute('select public.run_pdc_acceptance_sublet_cleanup_733(%s,%s)', (BOOKING, 'PDC-ACCEPTANCE-SUBLET-CLEANUP-733'))
            self.assertIn(production.exception.pgcode, {'42501', '55000'})
        self.conn.rollback()

    def test_cleanup_execute_is_revoked_for_all_api_roles(self):
        self.set_claims()
        with self.conn.cursor() as cur:
            cur.execute("select has_function_privilege('authenticated','public.run_pdc_acceptance_sublet_cleanup_733(uuid,text)','execute'),has_function_privilege('anon','public.run_pdc_acceptance_sublet_cleanup_733(uuid,text)','execute'),has_function_privilege('service_role','public.run_pdc_acceptance_sublet_cleanup_733(uuid,text)','execute')")
            self.assertEqual(cur.fetchone(), (False, False, False))
        self.conn.rollback()


if __name__ == '__main__':
    unittest.main(verbosity=2)
