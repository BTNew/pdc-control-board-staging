"""Guarded live staging verification for migration 029.

Every synthetic operation runs in one transaction and is rolled back. A fresh
connection then proves no Stage 2B operation fixtures remain.
"""
from __future__ import annotations

import json
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAGING_TOOLS = ROOT / "_staging_test_tools"


class Stage2BVehicleMasterOperationsStagingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import psycopg2  # noqa: F401
        except ImportError as exc:
            raise unittest.SkipTest("psycopg2 is unavailable") from exc
        sys.path.insert(0, str(STAGING_TOOLS))
        try:
            from staging_conn import get_conn
            cls.get_conn = staticmethod(get_conn)
            cls.conn = get_conn()
        except Exception as exc:
            raise unittest.SkipTest(f"guarded staging connection unavailable: {exc}") from exc
        cls.conn.autocommit = False
        cls.cur = cls.conn.cursor()
        cls.token = uuid.uuid4().hex[:12].upper()
        cls.source = "stage2b_029_test"
        cls.batch = f"BATCH-{cls.token}"
        cls.created_ids: list[str] = []
        cls.role_emails: dict[str, str] = {}
        cls.role_user_ids: dict[str, str] = {}

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
            if role not in cls.role_emails:
                cls.role_emails[role] = email
                cls.role_user_ids[role] = user_id
        for role in ("viewer", "operator", "administrator"):
            if role not in cls.role_emails:
                raise unittest.SkipTest(f"staging lacks active {role} fixture")

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
                "select count(*) from public.vehicle_aliases where source_system in (%s, 'manual_edit') and source_batch_id = %s",
                (cls.source, cls.batch),
            )
            aliases = q.fetchone()[0]
            q.execute(
                "select count(*) from public.vehicle_master_source_records where source_system = %s and source_batch_id = %s",
                (cls.source, cls.batch),
            )
            sources = q.fetchone()[0]
            q.execute(
                "select count(*) from public.vehicle_master_operation_receipts where scope_key in (%s, %s)",
                (cls.source, cls.created_ids[0] if cls.created_ids else "none"),
            )
            receipts = q.fetchone()[0]
            if vehicles or aliases or sources or receipts:
                raise AssertionError(
                    f"029 cleanup failed: vehicles={vehicles}, aliases={aliases}, "
                    f"sources={sources}, receipts={receipts}"
                )
        finally:
            verify.close()

    def _as_role(self, role: str):
        self.cur.execute("set local role authenticated")
        self.cur.execute(
            "select set_config('request.jwt.claims', %s, true)",
            (json.dumps({"email": self.role_emails[role], "sub": self.role_user_ids[role], "role": "authenticated"}),),
        )

    def _reset_role(self):
        self.cur.execute("reset role")

    def _rpc(self, role: str, sql: str, params: tuple):
        self._as_role(role)
        try:
            self.cur.execute(sql, params)
            return self.cur.fetchone()[0]
        finally:
            self._reset_role()

    def test_01_ledger_and_security(self):
        self.cur.execute("select version from supabase_migrations.schema_migrations where version = '029'")
        self.assertEqual(self.cur.fetchone(), ("029",))
        self.cur.execute(
            """
            select grantee, privilege_type
            from information_schema.role_table_grants
            where table_schema = 'public' and table_name = 'vehicle_master_operation_receipts'
              and grantee in ('anon', 'authenticated')
            """
        )
        self.assertEqual(self.cur.fetchall(), [])
        self.cur.execute(
            """
            select proname, prosecdef
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public'
              and proname in (
                'preview_vehicle_master_import', 'upsert_vehicle_master_import',
                'apply_vehicle_master_import', 'edit_vehicle_master'
              )
            order by proname
            """
        )
        self.assertEqual(len(self.cur.fetchall()), 4)

    def test_02_preview_apply_retry_update_and_manual_edit(self):
        record = f"REC-{self.token}-A"
        stock = f"S2B029-{self.token}-A"
        vin = ("JTN" + self.token + "12345678901234567")[:17]
        payload = {
            "stock_number": stock,
            "vin": vin,
            "job_card_number": f"JC-{self.token}-A",
            "customer_name": "Synthetic 029 Customer",
            "vehicle_description": "Synthetic Hilux",
            "make": "Toyota",
            "model": "Hilux",
        }
        preview = self._rpc(
            "administrator",
            "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
            (self.source, self.batch, record, json.dumps(payload), None),
        )
        self.assertTrue(preview["ok"], preview)
        self.assertEqual(preview["data"]["action"], "insert")
        vehicle_id = preview["data"]["vehicle_id"]
        self.created_ids.append(vehicle_id)

        applied = self._rpc(
            "administrator",
            "select public.apply_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
            (self.source, self.batch, record, json.dumps(payload), None, f"APPLY-{self.token}-A"),
        )
        self.assertTrue(applied["ok"], applied)
        self.assertEqual(applied["code"], "applied")
        self.assertEqual(applied["data"]["preview"], preview["data"])
        self.assertEqual(applied["data"]["vehicle_id"], vehicle_id)
        self.assertEqual(applied["data"]["version"], 1)

        retry = self._rpc(
            "administrator",
            "select public.apply_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
            (self.source, self.batch, record, json.dumps(payload), None, f"APPLY-{self.token}-A"),
        )
        self.assertEqual(retry, applied)
        self.cur.execute(
            "select version from public.vehicles where id = %s",
            (vehicle_id,),
        )
        self.assertEqual(self.cur.fetchone(), (1,))
        self.cur.execute(
            "select count(*) from public.vehicle_master_operation_receipts where operation_kind = 'import_apply' and vehicle_id = %s",
            (vehicle_id,),
        )
        self.assertEqual(self.cur.fetchone()[0], 1)

        idempotency_conflict = self._rpc(
            "administrator",
            "select public.apply_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
            (self.source, self.batch, record, json.dumps({**payload, "model": "Changed"}), None, f"APPLY-{self.token}-A"),
        )
        self.assertFalse(idempotency_conflict["ok"])
        self.assertEqual(idempotency_conflict["code"], "idempotency_conflict")

        update_payload = {**payload, "customer_name": "Synthetic 029 Updated"}
        update_preview = self._rpc(
            "administrator",
            "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
            (self.source, self.batch, record, json.dumps(update_payload), 1),
        )
        self.assertTrue(update_preview["ok"], update_preview)
        self.assertEqual(update_preview["data"]["action"], "update")
        updated = self._rpc(
            "administrator",
            "select public.upsert_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
            (self.source, self.batch, record, json.dumps(update_payload), 1, f"APPLY-{self.token}-B"),
        )
        self.assertTrue(updated["ok"], updated)
        self.assertEqual(updated["data"]["preview"], update_preview["data"])
        self.assertEqual(updated["data"]["version"], 2)

        stale = self._rpc(
            "operator",
            "select public.edit_vehicle_master(%s, %s, %s::jsonb, %s, %s)",
            (vehicle_id, 1, json.dumps({"customer_name": "Stale clobber"}), "stale test", f"EDIT-{self.token}-STALE"),
        )
        self.assertFalse(stale["ok"])
        self.assertEqual(stale["code"], "stale_version")

        edited = self._rpc(
            "operator",
            "select public.edit_vehicle_master(%s, %s, %s::jsonb, %s, %s)",
            (vehicle_id, 2, json.dumps({"customer_name": "Synthetic manual edit"}), "029 manual evidence test", f"EDIT-{self.token}-A"),
        )
        self.assertTrue(edited["ok"], edited)
        self.assertEqual(edited["data"]["version"], 3)
        edit_retry = self._rpc(
            "operator",
            "select public.edit_vehicle_master(%s, %s, %s::jsonb, %s, %s)",
            (vehicle_id, 2, json.dumps({"customer_name": "Synthetic manual edit"}), "029 manual evidence test", f"EDIT-{self.token}-A"),
        )
        self.assertEqual(edit_retry, edited)

        self.cur.execute(
            """
            select source_system, original_evidence
            from public.vehicle_master_source_records
            where vehicle_id = %s order by created_at
            """,
            (vehicle_id,),
        )
        evidence = self.cur.fetchall()
        self.assertTrue(any(row[0] == self.source and row[1].get("stock_number") == stock for row in evidence))
        self.assertTrue(any(row[0] == "manual_edit" and row[1].get("changes", {}).get("customer_name") == "Synthetic manual edit" for row in evidence))
        self.cur.execute(
            "select count(*) from public.audit_events where vehicle_id = %s and metadata ->> 'stage' = 'stage2b_029'",
            (vehicle_id,),
        )
        self.assertGreaterEqual(self.cur.fetchone()[0], 3)
        self.cur.execute(
            "select count(*) from public.vehicle_master_history where vehicle_id = %s",
            (vehicle_id,),
        )
        self.assertGreaterEqual(self.cur.fetchone()[0], 3)

    def test_03_ambiguous_and_conflicting_matches_fail_closed(self):
        orphan_record = f"REC-{self.token}-ORPHANED"
        self.cur.execute(
            """
            insert into public.vehicle_master_source_records (
              vehicle_id, source_system, source_batch_id, source_record_id, original_evidence
            ) values (null, %s, %s, %s, '{"retained":"after-delete"}'::jsonb)
            """,
            (self.source, self.batch, orphan_record),
        )
        orphaned = self._rpc(
            "administrator",
            "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
            (self.source, self.batch, orphan_record, "{}", None),
        )
        self.assertFalse(orphaned["ok"])
        self.assertEqual(orphaned["code"], "unlinked_source_evidence")

        def apply_record(suffix: str, stock: str, vin: str):
            payload = {
                "stock_number": stock,
                "vin": vin,
                "customer_name": f"Synthetic {suffix}",
            }
            preview = self._rpc(
                "administrator",
                "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
                (self.source, self.batch, f"REC-{self.token}-{suffix}", json.dumps(payload), None),
            )
            result = self._rpc(
                "administrator",
                "select public.apply_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
                (self.source, self.batch, f"REC-{self.token}-{suffix}", json.dumps(payload), None, f"APPLY-{self.token}-{suffix}"),
            )
            self.assertTrue(result["ok"], result)
            self.assertEqual(result["data"]["preview"], preview["data"])
            self.created_ids.append(result["data"]["vehicle_id"])
            return result["data"]["vehicle_id"]

        first_stock = f"S2B029-{self.token}-C1"
        second_stock = f"S2B029-{self.token}-C2"
        first_vin = ("JTD" + self.token + "11111111111111111")[:17]
        second_vin = ("JTE" + self.token + "22222222222222222")[:17]
        first_id = apply_record("C1", first_stock, first_vin)
        second_id = apply_record("C2", second_stock, second_vin)

        conflict = self._rpc(
            "administrator",
            "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
            (
                self.source, self.batch, f"REC-{self.token}-CONFLICT",
                json.dumps({"stock_number": first_stock.lower().replace("-", " "), "vin": second_vin}), None,
            ),
        )
        self.assertFalse(conflict["ok"])
        self.assertEqual(conflict["code"], "conflicting_match")
        self.assertEqual(set(conflict["data"]["candidate_ids"]), {first_id, second_id})

        ambiguous_job = f"AMB-JC-{self.token}"
        self.cur.execute(
            "update public.vehicles set job_card_number = %s where id in (%s, %s)",
            (ambiguous_job, first_id, second_id),
        )
        ambiguous = self._rpc(
            "administrator",
            "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
            (self.source, self.batch, f"REC-{self.token}-AMB", json.dumps({"job_card_number": ambiguous_job}), None),
        )
        self.assertFalse(ambiguous["ok"])
        self.assertEqual(ambiguous["code"], "ambiguous_match")

        self.cur.execute("select count(*) from public.vehicles where id in (%s, %s)", (first_id, second_id))
        self.assertEqual(self.cur.fetchone()[0], 2)

    def test_04_roles_and_viewer_mutation_denial(self):
        self._as_role("viewer")
        try:
            with self.assertRaises(Exception) as ctx:
                self.cur.execute(
                    "select public.apply_vehicle_master_import(%s, %s, %s, %s::jsonb, %s, %s)",
                    (self.source, self.batch, f"REC-{self.token}-VIEWER", "{}", None, f"VIEWER-{self.token}"),
                )
            self.assertEqual(getattr(ctx.exception, "pgcode", None), "42501")
            self.cur.execute("rollback to savepoint viewer_denied") if False else None
        finally:
            # The permission exception aborts the transaction; use a savepoint
            # in the explicit operator-denial check below instead. This test is
            # retained as a role assertion only when run last.
            self.conn.rollback()
            self.cur = self.conn.cursor()

        self.cur.execute("savepoint operator_import_denied")
        self._as_role("operator")
        try:
            with self.assertRaises(Exception) as ctx:
                self.cur.execute(
                    "select public.preview_vehicle_master_import(%s, %s, %s, %s::jsonb, %s)",
                    (self.source, self.batch, f"REC-{self.token}-OP", "{}", None),
                )
            self.assertEqual(getattr(ctx.exception, "pgcode", None), "42501")
            self.cur.execute("rollback to savepoint operator_import_denied")
        finally:
            self._reset_role()


if __name__ == "__main__":
    unittest.main()
