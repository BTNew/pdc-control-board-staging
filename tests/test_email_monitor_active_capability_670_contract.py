from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827067000_670_email_monitor_active_capability_uid514_seven_part_reconciliation.sql"
ROTATION = ROOT / "supabase/staging_only/20260827067100_671_email_monitor_active_planner_rotation_after_670.sql"
PLANNER = ROOT / "backend/pdc_active_semantic_planner.py"
TRUST = ROOT / "runtime_release/pdc-active-semantic-planner-trust-receipt.json"


class EmailMonitorActiveCapability670ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_staging_transaction(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        body = self.sql.split("BEGIN;", 1)[1].rsplit("COMMIT;", 1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:BEGIN|START\s+TRANSACTION|COMMIT|ROLLBACK)\s*;")
        self.assertIn("LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE", self.sql)
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())
        self.assertNotIn("send_email", self.lower)
        self.assertIn("20260827066000", self.sql)
        self.assertIn("20260827067000", self.sql)

    def test_exact_actor_planner_and_mime_contract(self):
        for marker in (
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "sales@broometoyota.com.au",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a",
            "639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65",
            "pmb-pdc-agentic-email-plan-v1",
            "pdc-active-semantic-planner-trust-v1",
            "observed_mime_part_count integer not null default 7",
            "retained_authenticated_attachment_count integer not null default 4",
            "all_mime_parts_retained boolean not null default true",
            "v_count<>7",
            "attachment_count integer not null",
            "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_least_privilege_and_fail_closed_controls(self):
        for marker in (
            "pdc_email_monitor",
            "grant execute on function public.read_pdc_uid514_transaction_receipt_257(integer) to authenticated,pdc_email_monitor",
            "grant execute on function public.verify_pdc_monitor_runtime_binding_503",
            "revoke all on public.pdc_email_monitor_active_capability_controls_670",
            "revoke all on public.pdc_email_monitor_active_capability_history_670",
            "force row level security",
            "PDC_670_ACTIVE_CAPABILITY_HISTORY_IMMUTABLE",
            "admin_rollback_pdc_email_monitor_active_capability_670",
            "PDC_670_ADMIN_AUTHORITY_REQUIRED",
            "windows_monitor_enabled",
            "outbound_email_enabled",
            "production_writes",
            "public.pdc_email_monitor_pilot WHERE singleton",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("grant execute on function public.pdc_email_monitor_active_capability", self.lower)
        self.assertNotIn(" to anon", self.lower)
        self.assertNotIn(" to service_role", self.lower)

    def test_671_rotation_is_append_only_and_binds_new_artifact(self):
        sql = ROTATION.read_text(encoding="utf-8")
        lower = sql.lower()
        self.assertEqual(sql.count("BEGIN;"), 1)
        self.assertEqual(sql.count("COMMIT;"), 1)
        self.assertIn("20260827067000", sql)
        self.assertIn("20260827067100", sql)
        self.assertIn("d3ee4933b380cfce2712ff8804419a35f9d33d6039c1dcd3653d1fb6f923c09a", lower)
        self.assertIn("639148337b6f9708479e5a03f7fb6894665cb4372d27072087e4c777bc54bc65", lower)
        self.assertIn("7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348", lower)
        self.assertIn("e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227", lower)
        self.assertIn("disable trigger pdc_monitor_planner_binding_immutable_502", lower)
        self.assertIn("enable trigger pdc_monitor_planner_binding_immutable_502", lower)
        self.assertIn("pdc_671_exact_670_predecessor_or_collision_mismatch", lower)
        self.assertIn("pdc_671_planner_rotation_postcondition_failed", lower)
        self.assertNotIn("drop table", lower)
        self.assertNotIn("delete from", lower)
        self.assertNotIn("send_email", lower)

    def test_reader_preserves_contained_and_active_paths(self):
        for marker in (
            "CREATE OR REPLACE FUNCTION public.read_pdc_uid514_transaction_receipt_257",
            "pdc_email_monitor",
            "role::text='importer'",
            "role::text='viewer'",
            "PDC_670_ACTIVE_OR_CONTAINED_IDENTITY_MISMATCH",
            "uid514_receipt_terminal",
            "uid514_receipt_pending",
            "synthetic_staging_commissioning",
            "physical_mailbox_fetch",
            "all_mime_parts_retained",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_planner_and_trust_receipt_are_real_and_bound(self):
        self.assertTrue(PLANNER.is_file())
        self.assertTrue(TRUST.is_file())
        planner_sha = hashlib.sha256(PLANNER.read_bytes()).hexdigest()
        trust_sha = hashlib.sha256(TRUST.read_bytes()).hexdigest()
        trust = json.loads(TRUST.read_text(encoding="utf-8"))
        self.assertEqual(planner_sha, "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348")
        self.assertEqual(trust_sha, "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227")
        self.assertEqual(trust["planner_sha256"], planner_sha)
        self.assertEqual(trust["contract"], "pdc-active-semantic-planner-trust-v1")

    def test_planner_smoke_and_negative_contracts(self):
        smoke = {
            "contract_version": "pmb-pdc-agentic-planner-request-v1",
            "evidence": {"instruction_candidates": [{"instruction_id": "ins-smoke", "evidence_ref": "body", "text": "Stock 1001: mark parts complete"}]},
            "vehicle_contexts": [{"vehicle_id": "11111111-1111-1111-1111-111111111111", "identity": {"stock_number": "1001", "vin": "", "job_card_number": "", "customer": ""}}],
        }
        result = subprocess.run([sys.executable, str(PLANNER)], input=json.dumps(smoke).encode(), capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        plan = json.loads(result.stdout)
        self.assertEqual(plan["contract_version"], "pmb-pdc-agentic-email-plan-v1")
        self.assertEqual(plan["instructions"][0]["disposition"], "ACTIONABLE")
        self.assertEqual(plan["vehicles"][0]["actions"][0]["action_type"], "parts_complete")
        multi = dict(smoke)
        multi["evidence"] = {"instruction_candidates": [{"instruction_id": "ins-multi", "evidence_ref": "body", "text": "Stock 1001: Parts are complete; set ETA to 15 September 2026; add note Ready for workshop."}]}
        result = subprocess.run([sys.executable, str(PLANNER)], input=json.dumps(multi).encode(), capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        multi_plan = json.loads(result.stdout)
        self.assertEqual([item["action_type"] for item in multi_plan["vehicles"][0]["actions"]], ["parts_complete", "eta_set", "notes_set"])
        negative = dict(smoke)
        negative["evidence"] = {"instruction_candidates": [{"instruction_id": "ins-negative", "evidence_ref": "body", "text": "Stock 1001: move the booking to next Friday or Saturday"}]}
        result = subprocess.run([sys.executable, str(PLANNER)], input=json.dumps(negative).encode(), capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(result.stdout)["instructions"][0]["disposition"], "REVIEW_REQUIRED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
