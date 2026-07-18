"""Guarded staging verification for migration 030 C1 lifecycle resolver.

All resolver fixtures and the temporary trigger-bypass conflict proof live in
one uncommitted transaction and are rolled back. A fresh connection proves
that no C1 fixtures or temporary schemas remain.
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


class Stage2BLifecycleIdentityResolverStagingTests(unittest.TestCase):
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
        cls.source = "stage2b_c1_test"
        cls.batch = f"C1-{cls.token}"
        cls.role_users: dict[str, tuple[str, str]] = {}
        cls.ids = [str(uuid.uuid4()) for _ in range(3)]
        cls.stock = [f"C1-{cls.token}-{n}" for n in range(1, 4)]
        cls.vins = [
            (prefix + cls.token + suffix)[:17]
            for prefix, suffix in (
                ("JTN", "12345678901234567"),
                ("JTD", "23456789012345678"),
                ("JTE", "34567890123456789"),
            )
        ]

        cls.cur.execute(
            """
            select r.role::text, r.email, u.id::text
            from public.pdc_user_roles r
            join auth.users u on lower(u.email) = lower(r.email)
            where r.active and r.role in ('viewer', 'operator', 'administrator')
            order by r.role::text, r.email
            """
        )
        for role, email, user_id in cls.cur.fetchall():
            cls.role_users.setdefault(role, (email, user_id))
        for role in ("viewer", "operator", "administrator"):
            if role not in cls.role_users:
                raise unittest.SkipTest(f"staging lacks active {role} fixture")

        cls.cur.execute("select revision from public.vehicle_lifecycle_resolver_revision where singleton")
        cls.start_revision = cls.cur.fetchone()[0]
        for index, vehicle_id in enumerate(cls.ids):
            cls.cur.execute(
                """
                insert into public.vehicles (
                  id, permanent_vehicle_id, stock_number, vin,
                  job_card_number, toyota_order_number,
                  source_system, source_batch_id, source_record_id,
                  lifecycle_state, version, visible_on_board
                ) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, 'active', 1, false)
                """,
                (
                    vehicle_id,
                    f"PERM-{cls.token}-{index + 1}",
                    cls.stock[index],
                    cls.vins[index],
                    f"JC-{cls.token}-{index + 1}",
                    f"ORDER-{cls.token}-{index + 1}",
                    cls.source,
                    cls.batch,
                    f"ROW-{cls.token}-{index + 1}",
                ),
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
            q.execute(
                "select count(*) from public.vehicles where source_system = %s and source_batch_id = %s",
                (cls.source, cls.batch),
            )
            vehicles = q.fetchone()[0]
            q.execute(
                "select count(*) from public.vehicle_aliases where source_batch_id = %s",
                (cls.batch,),
            )
            aliases = q.fetchone()[0]
            q.execute(
                "select count(*) from public.vehicle_master_source_records where source_batch_id = %s",
                (cls.batch,),
            )
            sources = q.fetchone()[0]
            q.execute("select count(*) from information_schema.schemata where schema_name like 'restore_test_c1_%'")
            schemas = q.fetchone()[0]
            if any((vehicles, aliases, sources, schemas)):
                raise AssertionError(
                    f"030 cleanup failed: vehicles={vehicles}, aliases={aliases}, sources={sources}, schemas={schemas}"
                )
        finally:
            verify.close()

    def _as_claims(self, email: str, user_id: str):
        self.cur.execute("set local role authenticated")
        self.cur.execute(
            "select set_config('request.jwt.claims', %s, true)",
            (json.dumps({"email": email, "sub": user_id, "role": "authenticated"}),),
        )

    def _rpc(self, role: str, **params):
        email, user_id = self.role_users[role]
        self._as_claims(email, user_id)
        try:
            self.cur.execute(
                """
                select public.resolve_vehicle_lifecycle_identity(
                  %(p_vehicle_id)s, %(p_stock_number)s, %(p_vin)s,
                  %(p_job_card_number)s, %(p_permanent_vehicle_id)s,
                  %(p_toyota_order_number)s, %(p_source_system)s,
                  %(p_source_record_id)s
                )
                """,
                {
                    "p_vehicle_id": None,
                    "p_stock_number": None,
                    "p_vin": None,
                    "p_job_card_number": None,
                    "p_permanent_vehicle_id": None,
                    "p_toyota_order_number": None,
                    "p_source_system": None,
                    "p_source_record_id": None,
                    **params,
                },
            )
            return self.cur.fetchone()[0]
        finally:
            self.cur.execute("reset role")

    def test_01_ledger_security_roles_and_viewer_projection(self):
        self.cur.execute("select version from supabase_migrations.schema_migrations where version = '030'")
        self.assertEqual(self.cur.fetchone(), ("030",))
        expected_keys = {
            "outcome", "vehicle_id", "version", "qc_completed_at",
            "lifecycle_state", "is_archived", "resolver_revision", "matched_by",
        }
        for role in ("viewer", "operator", "administrator"):
            result = self._rpc(role, p_vehicle_id=self.ids[0])
            self.assertEqual(result["outcome"], "resolved")
            self.assertEqual(set(result), expected_keys)
            self.assertEqual(result["vehicle_id"], self.ids[0])
            self.assertNotIn("customer_name", result)
            self.assertNotIn("current_location", result)
            self.assertNotIn("workshop_status", result)

        random_id = str(uuid.uuid4())
        self._as_claims(f"unapproved-{self.token}@invalid.test", random_id)
        try:
            self.cur.execute("select public.resolve_vehicle_lifecycle_identity(p_stock_number => %s)", (self.stock[0],))
            self.assertEqual(self.cur.fetchone()[0], {"outcome": "unauthorized"})
        finally:
            self.cur.execute("reset role")

        self.cur.execute(
            """
            select count(*) from information_schema.role_table_grants
            where table_schema='public' and table_name='vehicles'
              and grantee='authenticated' and privilege_type='SELECT'
            """
        )
        self.assertGreaterEqual(self.cur.fetchone()[0], 1)

    def test_02_uuid_canonical_job_source_and_alias_resolution(self):
        uuid_result = self._rpc("viewer", p_vehicle_id=self.ids[0])
        self.assertEqual(uuid_result["matched_by"], ["vehicle_id"])

        stock_variant = self.stock[0].lower().replace("-", " ")
        self.assertEqual(self._rpc("viewer", p_stock_number=stock_variant)["vehicle_id"], self.ids[0])
        vin_variant = f" {self.vins[0][:8]}-{self.vins[0][8:]} ".lower()
        self.assertEqual(self._rpc("operator", p_vin=vin_variant)["vehicle_id"], self.ids[0])
        self.assertEqual(
            self._rpc(
                "administrator",
                p_job_card_number=f" {('JC-' + self.token + '-1').lower()} ",
                p_source_system=self.source.upper(),
            )["vehicle_id"],
            self.ids[0],
        )
        self.assertEqual(
            self._rpc(
                "viewer",
                p_source_system=self.source,
                p_source_record_id=f" row-{self.token.lower()}-1 ",
            )["vehicle_id"],
            self.ids[0],
        )

        alias_value = f"ALIAS-{self.token}"
        self.cur.execute(
            """
            insert into public.vehicle_aliases (
              vehicle_id, alias_type, alias_value, active,
              source_system, source_batch_id
            ) values (%s, 'stock_number', %s, true, %s, %s)
            """,
            (self.ids[0], alias_value, self.source, self.batch),
        )
        alias = self._rpc("viewer", p_stock_number=alias_value.lower())
        self.assertEqual(alias["outcome"], "resolved")
        self.assertEqual(alias["vehicle_id"], self.ids[0])

    def test_03_zero_invalid_and_inactive_archived_handling(self):
        self.assertEqual(self._rpc("viewer", p_stock_number=f"MISSING-{self.token}")["outcome"], "not_found")
        placeholder_id = str(uuid.uuid4())
        self.cur.execute(
            """
            insert into public.vehicles (
              id, permanent_vehicle_id, stock_number, source_system,
              source_batch_id, source_record_id, lifecycle_state, version, visible_on_board
            ) values (%s, %s, 'NEW-123', %s, %s, %s, 'active', 1, false)
            """,
            (placeholder_id, f"PERM-PLACEHOLDER-{self.token}", self.source, self.batch, f"PLACEHOLDER-{self.token}"),
        )
        self.assertEqual(self._rpc("viewer", p_stock_number="NEW 123")["outcome"], "not_found")
        for params in (
            {},
            {"p_vehicle_id": "not-a-uuid"},
            {"p_stock_number": "N/A"},
            {"p_vin": "BADVIN"},
            {"p_job_card_number": "JC-ONLY"},
            {"p_source_system": self.source},
        ):
            self.assertEqual(self._rpc("viewer", **params)["outcome"], "invalid_input")

        self.cur.execute(
            "update public.vehicles set deleted_at=now(), deleted_reason='synthetic C1 archive proof', version=version+1 where id=%s",
            (self.ids[2],),
        )
        archived = self._rpc("viewer", p_stock_number=self.stock[2])
        self.assertEqual(archived["outcome"], "resolved")
        self.assertTrue(archived["is_archived"])
        self.assertEqual(archived["version"], 2)

    def test_04_multiple_normalized_matches_and_conflicts_fail_closed(self):
        ambiguous_record = f"AMB-{self.token}"
        for vehicle_id in self.ids[:2]:
            self.cur.execute(
                """
                insert into public.vehicle_master_source_records (
                  vehicle_id, source_system, source_batch_id, source_record_id, original_evidence
                ) values (%s, %s, %s, %s, '{"synthetic":true}'::jsonb)
                """,
                (vehicle_id, self.source, self.batch, ambiguous_record),
            )
        ambiguous = self._rpc(
            "viewer", p_source_system=self.source, p_source_record_id=ambiguous_record.lower()
        )
        self.assertEqual(ambiguous["outcome"], "ambiguous")
        self.assertNotIn("vehicle_id", ambiguous)

        mixed = self._rpc("viewer", p_stock_number=self.stock[0], p_vin=self.vins[1])
        self.assertEqual(mixed["outcome"], "conflict")
        self.assertEqual(mixed["reason"], "conflicting_identifiers")
        self.assertNotIn("vehicle_id", mixed)

        # Build a deliberately inconsistent canonical-vs-alias fixture while
        # holding an exclusive table lock. The guard trigger is disabled only
        # inside this uncommitted transaction, re-enabled immediately, and the
        # whole transaction is rolled back by tearDownClass.
        self.cur.execute("lock table public.vehicle_aliases in access exclusive mode")
        self.cur.execute("alter table public.vehicle_aliases disable trigger vehicle_aliases_enforce_master_identity_uniqueness")
        try:
            self.cur.execute(
                """
                insert into public.vehicle_aliases (
                  vehicle_id, alias_type, alias_value, active,
                  source_system, source_batch_id
                ) values (%s, 'stock_number', %s, true, %s, %s)
                """,
                (self.ids[1], self.stock[0], self.source, self.batch),
            )
        finally:
            self.cur.execute("alter table public.vehicle_aliases enable trigger vehicle_aliases_enforce_master_identity_uniqueness")
        canonical_alias = self._rpc("administrator", p_stock_number=self.stock[0])
        self.assertEqual(canonical_alias["outcome"], "conflict")
        self.assertEqual(canonical_alias["reason"], "canonical_alias_conflict")
        self.assertNotIn("vehicle_id", canonical_alias)

    def test_05_version_and_revision_refresh(self):
        before = self._rpc("viewer", p_vehicle_id=self.ids[1])
        self.cur.execute(
            "update public.vehicles set qc_completed_at=now(), version=version+1 where id=%s",
            (self.ids[1],),
        )
        after = self._rpc("viewer", p_vehicle_id=self.ids[1])
        self.assertGreater(after["version"], before["version"])
        self.assertGreater(after["resolver_revision"], before["resolver_revision"])
        self.assertIsNotNone(after["qc_completed_at"])
        self.cur.execute("select revision from public.vehicle_lifecycle_resolver_revision where singleton")
        self.assertGreater(self.cur.fetchone()[0], self.start_revision)


if __name__ == "__main__":
    unittest.main()
