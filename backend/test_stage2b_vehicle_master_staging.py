"""Live staging verification for migration 028.

Skipped by credential-free local runs. When psycopg2 and the ignored staging
connection configuration are available, this test connects only through the
repository's staging_conn safety gate, wraps every synthetic row in one
transaction, and rolls it back.
"""
from __future__ import annotations

import json
import sys
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STAGING_TOOLS = ROOT / "_staging_test_tools"

APPROVED_CORE_FIELDS = {
    "id",
    "permanent_vehicle_id",
    "stock_number",
    "vin",
    "toyota_order_number",
    "job_card_number",
    "key_number",
    "customer_name",
    "vehicle_description",
    "salesperson_id",
    "salesperson_reference",
    "make",
    "model",
    "registration",
    "eta_to_kewdale",
    "arrival_reference_date",
    "source_system",
    "source_batch_id",
    "source_record_id",
    "version",
    "created_at",
    "updated_at",
    "is_archived",
}
FORBIDDEN_SNAPSHOT_FIELDS = {
    "source_metadata",
    "source_payload",
    "parts_stoppage",
    "visible_on_board",
    "current_location",
    "pmb_stage",
    "lifecycle_state",
    "active_workshop_booking_id",
    "workshop_status",
    "rft_collected_at",
}


def _savepoint(cur, name, statement, params=()):
    cur.execute(f"savepoint {name}")
    try:
        cur.execute(statement, params)
    except Exception as exc:  # caller asserts the concrete PostgreSQL code
        cur.execute(f"rollback to savepoint {name}")
        return exc
    cur.execute(f"release savepoint {name}")
    return None


class Stage2BVehicleMasterStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import psycopg2  # noqa: F401
        except ImportError as exc:
            raise unittest.SkipTest("psycopg2 is not installed for credential-free tests") from exc

        sys.path.insert(0, str(STAGING_TOOLS))
        try:
            from staging_conn import get_conn
            cls.get_conn = staticmethod(get_conn)
            cls.conn = get_conn()
        except Exception as exc:
            raise unittest.SkipTest(f"staging connection is unavailable: {exc}") from exc

        cls.conn.autocommit = False
        cls.cur = cls.conn.cursor()
        cls.token = uuid.uuid4().hex[:12].upper()
        cls.vehicle_ids = []

    @classmethod
    def tearDownClass(cls):
        if not hasattr(cls, "conn"):
            return
        cls.conn.rollback()
        cls.cur.close()
        cls.conn.close()

        # Verify cleanup from a fresh transaction/connection rather than
        # assuming rollback succeeded.
        verify_conn = cls.get_conn()
        try:
            verify_cur = verify_conn.cursor()
            verify_cur.execute(
                "select count(*) from public.vehicles where permanent_vehicle_id like %s",
                (f"S2B-PERM-{cls.token}%",),
            )
            remaining_vehicles = verify_cur.fetchone()[0]
            verify_cur.execute(
                "select count(*) from public.vehicle_aliases where source_system = 'stage2b_test' "
                "and source_batch_id = %s",
                (f"BATCH-{cls.token}",),
            )
            remaining_aliases = verify_cur.fetchone()[0]
            if remaining_vehicles or remaining_aliases:
                raise AssertionError(
                    f"synthetic cleanup failed: vehicles={remaining_vehicles}, aliases={remaining_aliases}"
                )
        finally:
            verify_conn.close()

    def test_01_ledger_schema_and_security_contract(self):
        self.cur.execute(
            "select version from supabase_migrations.schema_migrations where version = '028'"
        )
        self.assertEqual(self.cur.fetchone(), ("028",))

        self.cur.execute(
            """
            select column_name
            from information_schema.columns
            where table_schema = 'public' and table_name = 'vehicles'
            """
        )
        columns = {row[0] for row in self.cur.fetchall()}
        for required in {
            "id", "stock_number", "vin", "job_card_number", "key_number",
            "customer_name", "vehicle_description", "salesperson_id",
            "eta_to_kewdale", "arrival_reference_date", "source_system",
            "source_batch_id", "source_record_id", "version", "created_at", "updated_at",
        }:
            self.assertIn(required, columns)
        self.assertNotIn("source_metadata", columns)

        self.cur.execute(
            """
            select table_name, privilege_type
            from information_schema.role_table_grants
            where grantee = 'authenticated'
              and table_schema = 'public'
              and table_name in (
                'vehicles', 'vehicle_aliases', 'vehicle_master_revision',
                'vehicle_master_history', 'vehicle_master_identity_conflicts',
                'vehicle_master_source_records'
              )
            order by table_name, privilege_type
            """
        )
        grants = set(self.cur.fetchall())
        self.assertIn(("vehicles", "SELECT"), grants)
        self.assertIn(("vehicle_aliases", "SELECT"), grants)
        self.assertIn(("vehicle_master_revision", "SELECT"), grants)
        self.assertFalse(
            {
                row for row in grants
                if row[0] in {
                    "vehicle_master_history",
                    "vehicle_master_identity_conflicts",
                    "vehicle_master_source_records",
                }
            },
            grants,
        )
        self.assertFalse({row for row in grants if row[1] != "SELECT"}, grants)

        self.cur.execute(
            """
            select tablename
            from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename in ('vehicles', 'vehicle_aliases', 'vehicle_master_revision')
            order by tablename
            """
        )
        self.assertEqual(
            [row[0] for row in self.cur.fetchall()],
            ["vehicle_aliases", "vehicle_master_revision", "vehicles"],
        )
        self.cur.execute(
            """
            select c.relname, c.relreplident
            from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public'
              and c.relname in ('vehicles', 'vehicle_aliases', 'vehicle_master_revision')
            order by c.relname
            """
        )
        self.assertEqual(
            self.cur.fetchall(),
            [("vehicle_aliases", "f"), ("vehicle_master_revision", "f"), ("vehicles", "f")],
        )

    def test_02_synthetic_insert_missing_duplicate_and_conflicting_identity(self):
        first_id = str(uuid.uuid4())
        second_id = str(uuid.uuid4())
        missing_id = str(uuid.uuid4())
        self.vehicle_ids.extend([first_id, second_id, missing_id])
        stock = f"S2B-{self.token}"
        vin = f"JTDBR32E{self.token[:9]}"[:17]

        self.cur.execute(
            """
            insert into public.vehicles (
              id, permanent_vehicle_id, stock_number, vin, job_card_number,
              key_number, customer_name, vehicle_description, make, model,
              eta_to_kewdale, arrival_reference_date,
              source_system, source_batch_id, source_record_id, version
            ) values (
              %s, %s, %s, %s, %s, %s, 'Synthetic Stage2B',
              'Synthetic migration 028 fixture', 'Toyota', 'Synthetic',
              date '2026-08-01', date '2026-08-02',
              'stage2b_test', %s, %s, 1
            )
            returning id::text, stock_number_normalized, vin_normalized, version
            """,
            (
                first_id,
                f"S2B-PERM-{self.token}-1",
                stock,
                vin,
                f"JOB-{self.token}",
                f"KEY-{self.token}",
                f"BATCH-{self.token}",
                f"ROW-{self.token}-1",
            ),
        )
        inserted = self.cur.fetchone()
        self.assertEqual(inserted[0], first_id)
        self.assertEqual(inserted[1], stock.replace("-", ""))
        self.assertEqual(inserted[2], vin)
        self.assertEqual(inserted[3], 1)

        # Missing stock, VIN and job card are valid: the UUID remains canonical.
        self.cur.execute(
            """
            insert into public.vehicles (id, permanent_vehicle_id, customer_name)
            values (%s, %s, 'Synthetic missing identifiers')
            returning id::text, stock_number, vin, job_card_number
            """,
            (missing_id, f"S2B-PERM-{self.token}-MISSING"),
        )
        self.assertEqual(self.cur.fetchone(), (missing_id, None, None, None))

        invalid_vin = _savepoint(
            self.cur,
            "invalid_vin",
            """
            insert into public.vehicles (id, permanent_vehicle_id, vin)
            values (%s, %s, 'NOT-A-VALID-VIN')
            """,
            (str(uuid.uuid4()), f"S2B-PERM-{self.token}-INVALID-VIN"),
        )
        self.assertIsNotNone(invalid_vin)
        self.assertEqual(getattr(invalid_vin, "pgcode", None), "23514")

        duplicate_vin = _savepoint(
            self.cur,
            "duplicate_vin",
            """
            insert into public.vehicles
              (id, permanent_vehicle_id, stock_number, vin)
            values (%s, %s, %s, %s)
            """,
            (second_id, f"S2B-PERM-{self.token}-2", f"OTHER-{self.token}", vin.lower()),
        )
        self.assertIsNotNone(duplicate_vin)
        self.assertEqual(getattr(duplicate_vin, "pgcode", None), "23505")

        duplicate_stock = _savepoint(
            self.cur,
            "duplicate_stock",
            """
            insert into public.vehicles
              (id, permanent_vehicle_id, stock_number)
            values (%s, %s, %s)
            """,
            (second_id, f"S2B-PERM-{self.token}-2", stock.lower()),
        )
        self.assertIsNotNone(duplicate_stock)
        self.assertEqual(getattr(duplicate_stock, "pgcode", None), "23505")

        self.cur.execute(
            """
            insert into public.vehicles
              (id, permanent_vehicle_id, stock_number, source_system, source_record_id)
            values (%s, %s, %s, 'stage2b_test', %s)
            """,
            (second_id, f"S2B-PERM-{self.token}-2", f"OTHER-{self.token}", f"ROW-{self.token}-2"),
        )

        canonical_to_alias_conflict = _savepoint(
            self.cur,
            "canonical_to_alias_conflict",
            """
            insert into public.vehicle_aliases
              (vehicle_id, alias_type, alias_value, source_system)
            values (%s, 'stock_number', %s, 'stage2b_test')
            """,
            (second_id, stock.lower().replace("-", " ")),
        )
        self.assertIsNotNone(canonical_to_alias_conflict)
        self.assertEqual(getattr(canonical_to_alias_conflict, "pgcode", None), "23505")

        invalid_vin_alias = _savepoint(
            self.cur,
            "invalid_vin_alias",
            """
            insert into public.vehicle_aliases
              (vehicle_id, alias_type, alias_value, source_system)
            values (%s, 'vin', 'NOT-A-VALID-VIN', 'stage2b_test')
            """,
            (second_id,),
        )
        self.assertIsNotNone(invalid_vin_alias)
        self.assertEqual(getattr(invalid_vin_alias, "pgcode", None), "23514")

        alias_stock = f"ALIAS-{self.token}"
        self.cur.execute(
            """
            insert into public.vehicle_aliases
              (vehicle_id, alias_type, alias_value, source_system)
            values (%s, 'stock_number', %s, 'stage2b_test')
            """,
            (first_id, alias_stock),
        )
        alias_to_canonical_conflict = _savepoint(
            self.cur,
            "alias_to_canonical_conflict",
            "update public.vehicles set stock_number = %s where id = %s",
            (alias_stock.lower().replace("-", " "), second_id),
        )
        self.assertIsNotNone(alias_to_canonical_conflict)
        self.assertEqual(getattr(alias_to_canonical_conflict, "pgcode", None), "23505")
        self.cur.execute(
            """
            insert into public.vehicle_aliases
              (vehicle_id, alias_type, alias_value, source_system, source_batch_id)
            values (%s, 'job_card_number', %s, 'stage2b_test', %s)
            """,
            (first_id, f"CONFLICT-{self.token}", f"BATCH-{self.token}"),
        )
        conflicting_alias = _savepoint(
            self.cur,
            "conflicting_alias",
            """
            insert into public.vehicle_aliases
              (vehicle_id, alias_type, alias_value, source_system, source_batch_id)
            values (%s, 'job_card_number', %s, 'stage2b_test', %s)
            """,
            (second_id, f"conflict-{self.token}", f"BATCH-{self.token}"),
        )
        self.assertIsNotNone(conflicting_alias)
        self.assertEqual(getattr(conflicting_alias, "pgcode", None), "23505")

        provenance_vehicle_id = str(uuid.uuid4())
        self.cur.execute(
            """
            insert into public.vehicles (id, permanent_vehicle_id)
            values (%s, %s)
            """,
            (provenance_vehicle_id, f"S2B-PERM-{self.token}-PROVENANCE"),
        )
        self.cur.execute(
            """
            insert into public.vehicle_master_source_records
              (vehicle_id, source_system, original_evidence)
            values (%s, 'stage2b_test', '{"source":"retained"}'::jsonb)
            returning id
            """,
            (provenance_vehicle_id,),
        )
        provenance_record_id = self.cur.fetchone()[0]
        self.cur.execute("delete from public.vehicles where id = %s", (provenance_vehicle_id,))
        self.cur.execute(
            """
            select vehicle_id, original_evidence
            from public.vehicle_master_source_records where id = %s
            """,
            (provenance_record_id,),
        )
        self.assertEqual(
            self.cur.fetchone(),
            (None, {"source": "retained"}),
        )

    def test_03_optimistic_version_history_and_snapshot_roles(self):
        first_id = self.vehicle_ids[0]
        self.cur.execute(
            """
            update public.vehicles
            set customer_name = 'Synthetic Stage2B Updated', version = version + 1
            where id = %s and version = 1
            returning version
            """,
            (first_id,),
        )
        self.assertEqual(self.cur.fetchone(), (2,))
        self.cur.execute(
            """
            update public.vehicles set customer_name = 'Stale write'
            where id = %s and version = 1 returning version
            """,
            (first_id,),
        )
        self.assertIsNone(self.cur.fetchone())

        self.cur.execute(
            """
            select action, expected_version, resulting_version
            from public.vehicle_master_history
            where entity_type = 'vehicle' and entity_id = %s
            order by created_at
            """,
            (first_id,),
        )
        history = self.cur.fetchall()
        self.assertIn(("insert", None, 1), history)
        self.assertIn(("update", 1, 2), history)

        self.cur.execute(
            """
            select role::text, email
            from public.pdc_user_roles
            where active and role in ('viewer', 'operator', 'administrator')
            order by role::text, email
            """
        )
        role_emails = {}
        for role, email in self.cur.fetchall():
            role_emails.setdefault(role, email)
        for required_role in ("viewer", "operator", "administrator"):
            self.assertIn(required_role, role_emails, f"staging lacks active {required_role} role fixture")

        expected_capabilities = {
            "viewer": {"can_edit": False, "can_import": False, "can_administer": False},
            "operator": {"can_edit": True, "can_import": False, "can_administer": False},
            "administrator": {"can_edit": True, "can_import": True, "can_administer": True},
        }
        for role, expected in expected_capabilities.items():
            self.cur.execute("set local role authenticated")
            self.cur.execute(
                "select set_config('request.jwt.claims', %s, true)",
                (json.dumps({"email": role_emails[role], "sub": str(uuid.uuid4())}),),
            )
            self.cur.execute("select public.get_vehicle_core_snapshot()")
            payload = self.cur.fetchone()[0]
            self.cur.execute("reset role")

            self.assertTrue(payload["ok"], payload)
            self.assertEqual(payload["code"], "ok")
            self.assertEqual(payload["data"]["caller_role"], role)
            self.assertEqual(payload["data"]["capabilities"], expected)
            row = next(v for v in payload["data"]["vehicles"] if v["id"] == first_id)
            self.assertEqual(set(row), APPROVED_CORE_FIELDS)
            self.assertFalse(FORBIDDEN_SNAPSHOT_FIELDS & set(row))
            self.assertEqual(row["version"], 2)

        self.cur.execute("set local role authenticated")
        self.cur.execute(
            "select set_config('request.jwt.claims', %s, true)",
            (json.dumps({"email": f"unapproved-{self.token}@invalid.example"}),),
        )
        self.cur.execute("select public.get_vehicle_core_snapshot()")
        denied = self.cur.fetchone()[0]
        self.cur.execute("reset role")
        self.assertFalse(denied["ok"])
        self.assertEqual(denied["code"], "permission_denied")

    def test_99_rollback_removes_all_synthetic_rows(self):
        # The transaction rollback is the actual cleanup mechanism; this test
        # proves every created vehicle is currently bounded by that transaction.
        self.cur.execute(
            "select count(*) from public.vehicles where permanent_vehicle_id like %s",
            (f"S2B-PERM-{self.token}%",),
        )
        self.assertEqual(self.cur.fetchone()[0], 3)


if __name__ == "__main__":
    unittest.main()
