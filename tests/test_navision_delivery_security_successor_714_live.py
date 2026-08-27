from __future__ import annotations

import importlib.util
import json
import os
import urllib.error
import urllib.request
import unittest
import uuid
from pathlib import Path

import psycopg2

RUN_LIVE = os.environ.get("PDC_RUN_NAVISION_DELIVERY_714_LIVE_TESTS") == "1"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_NAVISION_DELIVERY_714_LIVE_TESTS=1 for authorised staging probes")
class NavisionDelivery714LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec_path = Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py")
        spec = importlib.util.spec_from_file_location("bootstrap714live", spec_path)
        bootstrap = importlib.util.module_from_spec(spec)
        assert spec and spec.loader
        spec.loader.exec_module(bootstrap)
        values = json.loads(
            bootstrap.unprotect(
                Path(r"C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi").read_bytes()
            ).decode()
        )
        bootstrap.validate(values)
        cls.base = f"https://{values['PDC_STAGING_PROJECT_REF']}.supabase.co"
        cls.anon_key = values["PDC_STAGING_SUPABASE_ANON_KEY"]
        cls.conn = psycopg2.connect(
            values["PDC_STAGING_DATABASE_URL"],
            host=None,
            connect_timeout=15,
            application_name="pdc714_security_live",
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

    def http(self, path, body=None, profile=None):
        headers = {
            "apikey": self.anon_key,
            "Authorization": f"Bearer {self.anon_key}",
            "Accept": "application/json",
        }
        if profile:
            headers["Content-Profile" if body is not None else "Accept-Profile"] = profile
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method="POST" if body is not None else "GET", headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                parsed = json.loads(raw)
            except Exception:
                parsed = raw.decode("utf-8", "replace")
            return error.code, parsed

    def test_live_catalog_is_strict_and_inventory_is_complete(self):
        migration = self.db("select version,name from supabase_migrations.schema_migrations where version='20260828030000'")
        self.assertEqual(migration, [("20260828030000", "715_remove_leaked_navision_714_test_probes")])
        counts = self.db("select phase,count(*) from public.pdc_navision_function_security_inventory_714 group by phase order by phase")
        self.assertEqual(dict(counts), {"pre": 14, "post": 14})
        exposed = self.db("select schema_name,postgrest_exposed from public.pdc_navision_postgrest_schema_inventory_714 where postgrest_exposed order by schema_name")
        self.assertEqual(exposed, [("graphql_public", True), ("public", True)])
        drift = self.db("""
            select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname !~ '^pg_' and n.nspname<>'information_schema'
              and (lower(p.proname) like concat('reconcile_navision_delivery_700', chr(37))
               or lower(p.proname) like concat('reconcile_navision_operational_record', chr(37))
               or lower(p.proname) like concat('process_pdc_monitor_body_location_20260821033000', chr(37)))
              and (has_function_privilege('public',p.oid,'execute')
               or has_function_privilege('anon',p.oid,'execute')
               or has_function_privilege('service_role',p.oid,'execute')
               or has_function_privilege('pdc_email_monitor',p.oid,'execute'))
              and not (n.nspname='public' and p.oid in (
                'public.reconcile_navision_delivery_700(uuid)'::regprocedure,
                'public.reconcile_navision_operational_record(uuid,uuid,text)'::regprocedure,
                'public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)'::regprocedure))
        """)
        self.assertEqual(drift, [(0,)])
        probes = self.db("""
            select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname='public' and (p.proname='Reconcile_Navision_Delivery_700'
               or (p.proname='reconcile_navision_delivery_700'
                   and pg_get_function_identity_arguments(p.oid)='p_backend_record_id uuid, p_probe text'))
        """)
        self.assertEqual(probes, [(0,)])

    def test_live_postgrest_config_and_named_default_alternate_denials(self):
        schemas = [row[0] for row in self.db("""
            select nspname from pg_namespace
            where nspname !~ '^pg_' and nspname<>'information_schema' order by nspname
        """)]
        self.assertIn("public", schemas)
        self.assertIn("graphql_public", schemas)
        for schema in schemas:
            status, body = self.http(f"/rest/v1/hermes_probe_714_{schema}", profile=schema)
            if schema in {"public", "graphql_public"}:
                self.assertEqual(status, 404, (schema, status, body))
            else:
                self.assertEqual(status, 406, (schema, status, body))
                self.assertIn("public, graphql_public", str(body))

        status, body = self.http("/rest/v1/rpc/reconcile_navision_delivery_700", body={})
        self.assertGreaterEqual(status, 400)
        self.assertIn("PGRST202", str(body))
        status, body = self.http("/rest/v1/rpc/Reconcile_Navision_Delivery_700", body={})
        self.assertGreaterEqual(status, 400)
        self.assertIn("PGRST202", str(body))
        status, body = self.http(
            "/rest/v1/rpc/reconcile_navision_delivery_700",
            body={"p_backend_record_id": str(uuid.uuid4()), "p_probe": "HERMES-TEST-714"},
        )
        self.assertGreaterEqual(status, 400, body)
        status, body = self.http(
            "/rest/v1/rpc/reconcile_navision_operational_record",
            body={"p_backend_record_id": str(uuid.uuid4()), "p_actor_id": str(uuid.uuid4())},
        )
        self.assertGreaterEqual(status, 400, body)
        status, body = self.http(
            "/rest/v1/rpc/reconcile_navision_operational_record",
            body={"p_backend_record_id": str(uuid.uuid4()), "p_actor_id": str(uuid.uuid4()), "p_actor_email": "x@example.invalid"},
            profile="pdc_hermes_security_probe_714",
        )
        self.assertEqual(status, 406, body)

    def test_database_named_default_and_role_surfaces_are_denied_without_mutation(self):
        uuid_arg = str(uuid.uuid4())
        cases = (
            ("anon", "select public.reconcile_navision_delivery_700(%s::uuid)", (uuid_arg,)),
            ("service_role", "select public.reconcile_navision_delivery_700(%s::uuid)", (uuid_arg,)),
            ("authenticated", "select public.reconcile_navision_operational_record_pre134(p_backend_record_id => %s::uuid,p_actor_id => %s::uuid,p_actor_email => %s)", (uuid_arg, uuid_arg, "x@example.invalid")),
            ("authenticated", "select public.reconcile_navision_delivery_700(%s::uuid,%s::text)", (uuid_arg, "HERMES-TEST-714")),
        )
        with self.conn.cursor() as cur:
            for role, sql, params in cases:
                cur.execute("savepoint hostile_714")
                try:
                    cur.execute(f"set local role {role}")
                    with self.assertRaises(psycopg2.Error) as raised:
                        cur.execute(sql, params)
                    self.assertIn(raised.exception.pgcode, ("42501", "42883"), (role, sql, raised.exception))
                finally:
                    cur.execute("rollback to savepoint hostile_714")
                    cur.execute("release savepoint hostile_714")
        self.conn.rollback()


if __name__ == "__main__":
    unittest.main(verbosity=2)
