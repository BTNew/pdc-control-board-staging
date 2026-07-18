"""Guarded staging verification for migration 031 C2a identity export.

All vehicle/alias fixtures are created in one transaction and rolled back. The
suite refuses every project except the dedicated staging ref.
"""
from __future__ import annotations

import json
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGING_TOOLS = ROOT / "_staging_test_tools"
STAGING_REF = "cdsmnqxtyyoeoznmbidd"


class Stage2BImporterIdentityExportStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        project_ref = (ROOT / "supabase" / ".temp" / "project-ref").read_text(encoding="utf-8").strip()
        if project_ref != STAGING_REF:
            raise unittest.SkipTest(f"refusing non-staging project {project_ref!r}")
        try:
            import psycopg2  # noqa: F401
        except ImportError as exc:
            raise unittest.SkipTest("psycopg2 is unavailable") from exc
        sys.path.insert(0, str(STAGING_TOOLS))
        from staging_conn import get_conn

        cls.get_conn = staticmethod(get_conn)
        cls.conn = get_conn()
        cls.conn.autocommit = False
        cls.cur = cls.conn.cursor()
        cls.token = uuid.uuid4().hex[:10].upper()
        cls.source = "stage2b_c2a_test"
        cls.batch = f"C2A-{cls.token}"
        cls.ids = sorted(str(uuid.uuid4()) for _ in range(3))
        cls.stock = [f"C2A-{cls.token}-{index}" for index in range(1, 4)]
        cls.vins = [
            (prefix + cls.token + "12345678901234567")[:17]
            for prefix in ("JTN", "JTD", "JTE")
        ]
        cls.role_users = {}
        cls.cur.execute(
            "select count(*) from public.pdc_user_roles where active and role='importer'"
        )
        if cls.cur.fetchone()[0] == 0:
            cls.cur.execute(
                """
                select email from public.pdc_user_roles
                where active and role='administrator'
                order by email
                """
            )
            admin_rows = cls.cur.fetchall()
            if len(admin_rows) < 2:
                raise unittest.SkipTest("staging needs a second synthetic administrator to exercise importer-only access")
            cls.cur.execute(
                "update public.pdc_user_roles set role='importer' where email=%s",
                (admin_rows[-1][0],),
            )
        cls.cur.execute(
            """
            select r.role::text, r.email, u.id::text
            from public.pdc_user_roles r
            join auth.users u on lower(u.email) = lower(r.email)
            where r.active and r.role in ('viewer', 'operator', 'importer', 'administrator')
            order by r.role::text, r.email
            """
        )
        for role, email, user_id in cls.cur.fetchall():
            cls.role_users.setdefault(role, (email, user_id))
        for role in ("viewer", "operator", "importer", "administrator"):
            if role not in cls.role_users:
                raise unittest.SkipTest(f"staging lacks active {role} fixture")

        for index, vehicle_id in enumerate(cls.ids):
            cls.cur.execute(
                """
                insert into public.vehicles (
                  id, permanent_vehicle_id, stock_number, vin, job_card_number,
                  toyota_order_number, source_system, source_batch_id,
                  source_record_id, lifecycle_state, version, visible_on_board
                ) values (%s,%s,%s,%s,%s,%s,%s,%s,%s,'active',%s,false)
                """,
                (
                    vehicle_id, f"PERM-{cls.token}-{index + 1}", cls.stock[index], cls.vins[index],
                    f"JC-{cls.token}-{index + 1}", f"ORDER-{cls.token}-{index + 1}",
                    cls.source, cls.batch, f"ROW-{cls.token}-{index + 1}", index + 1,
                ),
            )
        cls.cur.execute(
            """
            insert into public.vehicle_aliases (
              vehicle_id, alias_type, alias_value, active, source_system, source_batch_id
            ) values (%s, 'stock_number', %s, true, %s, %s)
            """,
            (cls.ids[0], f"ALIAS-{cls.token}", cls.source, cls.batch),
        )
        cls.cur.execute(
            """
            insert into public.vehicle_master_source_records (
              vehicle_id, source_system, source_batch_id, source_record_id,
              source_metadata, original_evidence
            ) values (%s,%s,%s,%s,'{}'::jsonb,'{}'::jsonb)
            """,
            (cls.ids[1], cls.source, cls.batch, f"ROW-{cls.token}-1"),
        )
        cls.cur.execute(
            "update public.vehicles set deleted_at=now(), deleted_reason='synthetic C2a archive test' where id=%s",
            (cls.ids[2],),
        )

    @classmethod
    def tearDownClass(cls):
        if not hasattr(cls, "conn"):
            return
        cls.conn.rollback()
        cls.cur.close()
        cls.conn.close()
        verify = cls.get_conn()
        try:
            q = verify.cursor()
            q.execute("select count(*) from public.vehicles where source_system=%s and source_batch_id=%s", (cls.source, cls.batch))
            vehicles = q.fetchone()[0]
            q.execute("select count(*) from public.vehicle_aliases where source_batch_id=%s", (cls.batch,))
            aliases = q.fetchone()[0]
            q.execute("select count(*) from public.vehicle_master_source_records where source_batch_id=%s", (cls.batch,))
            source_records = q.fetchone()[0]
            q.execute("select count(*) from information_schema.schemata where schema_name like 'restore_test_c2a_%'")
            schemas = q.fetchone()[0]
            if any((vehicles, aliases, source_records, schemas)):
                raise AssertionError(
                    f"031 cleanup failed: vehicles={vehicles}, aliases={aliases}, "
                    f"source_records={source_records}, schemas={schemas}"
                )
        finally:
            verify.close()

    def _as_claims(self, role):
        email, user_id = self.role_users[role]
        self.cur.execute("set local role authenticated")
        self.cur.execute(
            "select set_config('request.jwt.claims', %s, true)",
            (json.dumps({"email": email, "sub": user_id, "role": "authenticated"}),),
        )

    def _rpc(self, role, after=None, size=200, expected=None):
        self._as_claims(role)
        try:
            self.cur.execute(
                "select public.export_workshop_legacy_vehicle_identities(%s,%s,%s)",
                (after, size, expected),
            )
            return self.cur.fetchone()[0]
        finally:
            self.cur.execute("reset role")

    def test_01_ledger_grants_and_exact_role_matrix(self):
        self.cur.execute("select version from supabase_migrations.schema_migrations where version='031'")
        self.assertEqual(self.cur.fetchone(), ("031",))
        for role in ("viewer", "operator"):
            self.assertEqual(self._rpc(role), {"outcome": "unauthorized"})
        for role in ("importer", "administrator"):
            self.assertEqual(self._rpc(role)["outcome"], "exported")
        self.cur.execute(
            """
            select
              has_function_privilege('public', 'public.export_workshop_legacy_vehicle_identities(text,integer,bigint)', 'EXECUTE'),
              has_function_privilege('anon', 'public.export_workshop_legacy_vehicle_identities(text,integer,bigint)', 'EXECUTE'),
              has_function_privilege('authenticated', 'public.export_workshop_legacy_vehicle_identities(text,integer,bigint)', 'EXECUTE')
            """
        )
        self.assertEqual(self.cur.fetchone(), (False, False, True))

    def test_02_narrow_projection_uuid_identifiers_alias_and_archive(self):
        result = self._rpc("importer")
        rows = {row["vehicle_id"]: row for row in result["items"] if row["vehicle_id"] in self.ids}
        self.assertEqual(set(rows), set(self.ids))
        self.assertEqual(set(rows[self.ids[0]]), {"vehicle_id", "version", "is_archived", "identifiers"})
        self.assertEqual(rows[self.ids[0]]["version"], 1)
        self.assertTrue(rows[self.ids[2]]["is_archived"])
        claims = rows[self.ids[0]]["identifiers"]
        claim_types = {row["identifier_type"] for row in claims}
        self.assertTrue({"stock_number", "vin", "job_card_number", "permanent_vehicle_id", "toyota_order_number", "source_record_id"}.issubset(claim_types))
        self.assertTrue(any(row["origin"] == "alias" and row["value"] == f"ALIAS-{self.token}" for row in claims))
        evidence = rows[self.ids[1]]["identifiers"]
        self.assertTrue(any(
            row["origin"] == "source_evidence"
            and row["identifier_type"] == "source_record_id"
            and row["value"] == f"ROW-{self.token}-1"
            for row in evidence
        ))
        forbidden = {"customer_name", "parts_required", "notes", "workshop_status", "current_location", "pmb_stage", "salesperson_id"}
        self.assertFalse(forbidden.intersection(rows[self.ids[0]]))

    def test_03_deterministic_pagination_retry_and_stale_revision(self):
        first = self._rpc("importer", size=1)
        repeated = self._rpc("importer", size=1)
        self.assertEqual(first, repeated)
        self.assertEqual(len(first["items"]), 1)
        self.assertTrue(first["has_more"])
        self.assertEqual(first["next_cursor"], first["items"][0]["vehicle_id"])
        second = self._rpc("administrator", after=first["next_cursor"], size=1, expected=first["export_revision"])
        self.assertEqual(second["outcome"], "exported")
        self.assertGreater(second["items"][0]["vehicle_id"], first["items"][0]["vehicle_id"])
        stale = self._rpc("importer", expected=first["export_revision"] - 1)
        self.assertEqual(stale["outcome"], "stale_export")
        self.assertEqual(self._rpc("importer", after="not-a-uuid")["outcome"], "invalid_input")
        self.assertEqual(self._rpc("importer", size=0)["outcome"], "invalid_input")

    def test_04_duplicate_and_canonical_alias_conflicts_are_exported(self):
        self.cur.execute("set local session_replication_role = replica")
        try:
            self.cur.execute(
                "update public.vehicles set job_card_number=%s where id in (%s,%s)",
                (f"DUP-{self.token}", self.ids[0], self.ids[1]),
            )
            self.cur.execute(
                """
                insert into public.vehicle_aliases (
                  vehicle_id, alias_type, alias_value, active, source_system, source_batch_id
                ) values (%s, 'stock_number', %s, true, %s, %s)
                """,
                (self.ids[1], self.stock[0], self.source, self.batch),
            )
        finally:
            self.cur.execute("set local session_replication_role = origin")
        result = self._rpc("administrator")
        relevant = [row for row in result["conflicts"] if self.token in row["normalized_value"]]
        classifications = {row["classification"] for row in relevant}
        self.assertIn("ambiguous_normalized_identity", classifications)
        self.assertIn("canonical_alias_conflict", classifications)
        self.assertIn("canonical_source_evidence_conflict", classifications)
        for conflict in relevant:
            self.assertEqual(conflict["vehicle_ids"], sorted(conflict["vehicle_ids"]))
            self.assertGreater(len(conflict["vehicle_ids"]), 1)


if __name__ == "__main__":
    unittest.main()
