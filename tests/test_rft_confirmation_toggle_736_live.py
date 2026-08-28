from __future__ import annotations

import importlib.util
import json
import os
import unittest
import uuid
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
from psycopg2.extras import Json, register_uuid

RUN_LIVE = os.environ.get('PDC_RUN_RFT_CONFIRMATION_736_LIVE_TESTS') == '1'
ACTOR = '8a83b715-8d79-4b0e-95b2-02b55da6e8d7'
EMAIL = 'craig.watson@broometoyota.com.au'
NAMESPACE = uuid.UUID('73600000-0000-5000-8000-000000000736')


@unittest.skipUnless(RUN_LIVE, 'set PDC_RUN_RFT_CONFIRMATION_736_LIVE_TESTS=1 for authorised staging integration')
class RftConfirmation736LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bootstrap_path = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
        spec = importlib.util.spec_from_file_location('bootstrap_rft_736', bootstrap_path)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(bootstrap.unprotect(Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi').read_bytes()).decode())
        bootstrap.validate(values)
        if values.get('PDC_STAGING_PROJECT_REF') != 'cdsmnqxtyyoeoznmbidd' or 'cdsmnqxtyyoeoznmbidd' not in values['PDC_STAGING_DATABASE_URL']:
            raise RuntimeError('exact staging database binding required')
        cls.conn = psycopg2.connect(str(values['PDC_STAGING_DATABASE_URL']), connect_timeout=20, application_name='pdc736_rft_confirmation_live_test')
        register_uuid()
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def setUp(self):
        self.conn.rollback()
        self.now = datetime.now(timezone.utc)
        self.vehicle_id = uuid.uuid5(NAMESPACE, 'vehicle:toggle')
        self.collected_id = uuid.uuid5(NAMESPACE, 'vehicle:collected')
        with self.conn.cursor() as cur:
            cur.execute("select count(*) from public.vehicles where id in (%s,%s) or stock_number in ('HERMES-TEST-RFT-736-ON','HERMES-TEST-RFT-736-COLLECTED')", (self.vehicle_id, self.collected_id))
            self.assertEqual(cur.fetchone()[0], 0, 'hidden HERMES-TEST fixtures must start absent')
            cur.execute("select set_config('pdc.hermes_test_wrapper_vehicle_365',%s,true)", (str(self.vehicle_id),))
            cur.execute(
                """insert into public.vehicles(
                  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,
                  visible_on_board,current_location,rft_transferred_at,rft_collected_at,
                  source_payload,version,source_system,source_batch_id,source_record_id,
                  date_to_rft,created_by,updated_by)
                values(%s,%s,%s,%s,'rft',true,'RFT',%s,null,'{}',1,
                  'hermes_test_736','HERMES-TEST-736','HERMES-TEST-736-ON',%s,%s,%s)""",
                (self.vehicle_id, 'HERMES-TEST-PERM-736-ON', 'HERMES-TEST-RFT-736-ON', 'HERMES-TEST-JOB-736-ON', self.now, self.now.date(), ACTOR, ACTOR),
            )
            cur.execute("select set_config('pdc.hermes_test_wrapper_vehicle_365',%s,true)", (str(self.collected_id),))
            cur.execute(
                """insert into public.vehicles(
                  id,permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,
                  visible_on_board,current_location,rft_transferred_at,rft_collected_at,
                  rft_confirmed_at,source_payload,version,source_system,source_batch_id,
                  source_record_id,date_to_rft,created_by,updated_by)
                values(%s,%s,%s,%s,'rft',false,'Collected',%s,%s,%s,'{}',1,
                  'hermes_test_736','HERMES-TEST-736','HERMES-TEST-736-COLLECTED',%s,%s,%s)""",
                (self.collected_id, 'HERMES-TEST-PERM-736-COLLECTED', 'HERMES-TEST-RFT-736-COLLECTED', 'HERMES-TEST-JOB-736-COLLECTED', self.now, self.now, self.now, self.now.date(), ACTOR, ACTOR),
            )
            claims = json.dumps({'sub': ACTOR, 'email': EMAIL, 'role': 'authenticated'})
            cur.execute("select set_config('request.jwt.claim.sub',%s,true),set_config('request.jwt.claims',%s,true)", (ACTOR, claims))

    def call_toggle(self, vehicle_id, version, confirmed, key):
        with self.conn.cursor() as cur:
            cur.execute('select public.set_rft_confirmation_736(%s,%s,%s,%s)', (vehicle_id, version, confirmed, key))
            return cur.fetchone()[0]

    def test_tick_untick_replay_stale_and_irreversible_guards(self):
        on_key = uuid.uuid5(NAMESPACE, 'idempotency:on')
        off_key = uuid.uuid5(NAMESPACE, 'idempotency:off')
        checked = self.call_toggle(self.vehicle_id, 1, True, on_key)
        self.assertTrue(checked['ok'], repr(checked))
        self.assertEqual(checked['code'], 'rft_confirmed')
        self.assertTrue(checked['data']['rft_confirmed'])
        self.assertIsNotNone(checked['data']['dealer_transit_started_at'])
        self.assertEqual(checked['data']['vehicle_version_after'], 2)

        replay = self.call_toggle(self.vehicle_id, 1, True, on_key)
        self.assertTrue(replay['ok'])
        self.assertTrue(replay['replay'])
        self.assertEqual(replay['data']['vehicle_version_after'], 2)

        unchecked = self.call_toggle(self.vehicle_id, 2, False, off_key)
        self.assertTrue(unchecked['ok'])
        self.assertEqual(unchecked['code'], 'rft_unconfirmed')
        self.assertFalse(unchecked['data']['rft_confirmed'])
        self.assertIsNone(unchecked['data']['dealer_transit_started_at'])
        self.assertEqual(unchecked['data']['vehicle_version_after'], 3)

        with self.conn.cursor() as cur:
            cur.execute('select public.book_rft_transport_734(%s,%s,%s)', (self.vehicle_id, 3, uuid.uuid5(NAMESPACE, 'idempotency:booking-before-rft')))
            booking_before_confirmation = cur.fetchone()[0]
        self.assertFalse(booking_before_confirmation['ok'])
        self.assertEqual(booking_before_confirmation['code'], 'rft_confirmation_required')

        stale = self.call_toggle(self.vehicle_id, 1, True, uuid.uuid5(NAMESPACE, 'idempotency:stale'))
        self.assertFalse(stale['ok'])
        self.assertEqual(stale['code'], 'rft_confirmation_stale_version')

        checked_again = self.call_toggle(self.vehicle_id, 3, True, uuid.uuid5(NAMESPACE, 'idempotency:on-again'))
        self.assertTrue(checked_again['ok'])
        self.assertEqual(checked_again['data']['vehicle_version_after'], 4)

        booking_receipt = uuid.uuid5(NAMESPACE, 'legacy-booking-receipt')
        with self.conn.cursor() as cur:
            cur.execute(
                """insert into public.pdc_rft_transport_lifecycle_receipts_734(
                  receipt_id,vehicle_id,action,actor_id,actor_email,idempotency_key,
                  request_sha256,request_payload,before_state,after_state,evidence,response)
                values(%s,%s,'rft_booked',%s,%s,%s,%s,'{}','{}','{}','{}','{}')""",
                (booking_receipt, self.vehicle_id, ACTOR, EMAIL, uuid.uuid5(NAMESPACE, 'legacy-booking-idem'), 'a' * 64),
            )
        blocked_email = self.call_toggle(self.vehicle_id, 4, False, uuid.uuid5(NAMESPACE, 'idempotency:blocked-email'))
        self.assertFalse(blocked_email['ok'])
        self.assertEqual(blocked_email['code'], 'rft_confirmation_irreversible')

        blocked_collected = self.call_toggle(self.collected_id, 1, False, uuid.uuid5(NAMESPACE, 'idempotency:blocked-collected'))
        self.assertFalse(blocked_collected['ok'])
        self.assertEqual(blocked_collected['code'], 'rft_confirmation_irreversible')

        with self.conn.cursor() as cur:
            cur.execute("select action,count(*) from public.pdc_rft_confirmation_receipts_736 where vehicle_id=%s group by action order by action", (self.vehicle_id,))
            self.assertEqual(cur.fetchall(), [('rft_confirmed', 2), ('rft_unconfirmed', 1)])
            cur.execute("select rft_confirmed_at,dealer_transit_started_at,version,current_location from public.vehicles where id=%s", (self.vehicle_id,))
            confirmed_at, timer_start, version, location = cur.fetchone()
            self.assertIsNotNone(confirmed_at)
            self.assertIsNotNone(timer_start)
            self.assertEqual((version, location), (4, 'RFT'))
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is null")
            self.assertTrue(cur.fetchone()[0])

        self.conn.rollback()


if __name__ == '__main__':
    unittest.main(verbosity=2)
