from __future__ import annotations

import importlib.util
import json
import os
import unittest
from pathlib import Path

import psycopg2


RUN_LIVE = os.environ.get("PDC_RUN_NAVISION_DELIVERY_716_LIVE_TESTS") == "1"
PROBE_ROLE = "HERMES-TEST-716-ACL"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_NAVISION_DELIVERY_716_LIVE_TESTS=1 for authorised staging probes")
class NavisionDelivery716LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = importlib.util.spec_from_file_location("bootstrap716live", spec_path)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(
            bootstrap.unprotect(
                Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()
            ).decode()
        )
        bootstrap.validate(values)
        cls.conn = psycopg2.connect(
            values["PDC_STAGING_DATABASE_URL"],
            host=None,
            connect_timeout=15,
            application_name="pdc716_acl_security_live",
            sslmode="verify-full",
            sslrootcert=values["PDC_STAGING_SSLROOTCERT"],
        )
        cls.conn.autocommit = False

    @classmethod
    def tearDownClass(cls):
        cls.conn.rollback()
        cls.conn.close()

    def setUp(self):
        self.conn.rollback()

    def db(self, sql, params=()):
        with self.conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()

    def test_live_head_inventory_and_every_raw_acl_entry_are_closed(self):
        self.assertEqual(
            self.db("select version,name from supabase_migrations.schema_migrations where version='20260828040000'"),
            [("20260828040000", "716_close_all_raw_navision_acl_grantees")],
        )
        self.assertEqual(
            self.db("select phase,count(distinct proc_oid) from public.pdc_navision_raw_acl_inventory_716 group by phase order by phase"),
            [("post", 10), ("pre", 10)],
        )
        hostile_pre = self.db(
            """select count(*) from public.pdc_navision_raw_acl_inventory_716
                where phase='pre' and acl_grantee_name=%s and privilege_type='EXECUTE' and is_grantable""",
            (PROBE_ROLE,),
        )
        self.assertGreaterEqual(hostile_pre[0][0], 2)
        self.assertEqual(
            self.db(
                """select count(*) from public.pdc_navision_raw_acl_inventory_716
                    where phase='post' and acl_grantee_name=%s""",
                (PROBE_ROLE,),
            ),
            [(0,)],
        )
        self.assertEqual(
            self.db(
                """select count(*) from public.pdc_navision_raw_acl_inventory_716
                    where phase='post' and is_grantable"""
            ),
            [(0,)],
        )
        self.assertEqual(
            self.db(
                """select count(*) from public.pdc_navision_raw_acl_inventory_716
                    where phase='post' and (
                      (is_canonical and (acl_grantee_name not in ('postgres','authenticated')
                        or acl_grantor_name<>'postgres' or privilege_type<>'EXECUTE'))
                      or (not is_canonical and (acl_grantee_name<>'postgres'
                        or acl_grantor_name<>'postgres' or privilege_type<>'EXECUTE'))
                    )"""
            ),
            [(0,)],
        )
        self.assertEqual(self.db("select count(*) from pg_roles where rolname=%s", (PROBE_ROLE,)), [(0,)])

    def test_rollback_cleanup_leaves_no_quoted_role_or_acl_residue(self):
        with self.conn.cursor() as cur:
            cur.execute("savepoint hostile_716_rollback")
            cur.execute('create role "HERMES-TEST-716-ROLLBACK" nologin nosuperuser nocreatedb nocreaterole noinherit')
            cur.execute(
                'grant execute on function public.reconcile_navision_delivery_700(uuid) to "HERMES-TEST-716-ROLLBACK" with grant option'
            )
            cur.execute(
                'grant execute on function public.reconcile_navision_operational_record(uuid,uuid,text) to "HERMES-TEST-716-ROLLBACK" with grant option'
            )
            cur.execute("rollback to savepoint hostile_716_rollback")
            cur.execute("release savepoint hostile_716_rollback")
            cur.execute("select count(*) from pg_roles where rolname='HERMES-TEST-716-ROLLBACK'")
            self.assertEqual(cur.fetchone(), (0,))
        self.conn.rollback()


if __name__ == "__main__":
    unittest.main(verbosity=2)
