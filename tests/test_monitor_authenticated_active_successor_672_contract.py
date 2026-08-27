from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827067200_672_authenticated_active_email_monitor_identity_successor.sql"
CONTROLLER = ROOT / "scripts/manage_monitor_authenticated_active_successor_staging.py"
RUNNER = ROOT / "scripts/run_current_active_authenticated_compatibility.ps1"
INSTALLER = ROOT / "scripts/install_pdc_active_preflight_authenticated_compatibility.ps1"
PREFLIGHT = ROOT / "scripts/pdc_active_preflight_authenticated_compatibility.py"


class AuthenticatedActiveSuccessor672ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_exact_671_predecessor(self):
        self.assertRegex(self.sql, r"(?is)^\s*--.*?\nBEGIN;.*LOCK TABLE supabase_migrations\.schema_migrations IN EXCLUSIVE MODE;")
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        body = re.split(r"(?im)^BEGIN;\s*$", self.sql, maxsplit=1)[1]
        body = re.split(r"(?im)^COMMIT;\s*$", body, maxsplit=1)[0]
        self.assertNotRegex(body, r"(?im)^\s*(?:START\s+TRANSACTION|BEGIN|COMMIT|ROLLBACK)\s*;")
        self.assertIn("20260827067100", self.sql)
        self.assertIn("671_email_monitor_active_planner_rotation_after_670", self.lower)
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())

    def test_exact_authenticated_actor_contract(self):
        for marker in (
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "sales@broometoyota.com.au",
            "authenticated",
            "importer",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "pdc_identity_type",
            "non_human_monitor",
            "role::text='importer'",
            "writer_active",
            "semantic_planner_commissioned_at",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_exact_actor_security_definer_rpcs_and_no_broad_execute(self):
        for marker in (
            "pdc_monitor_authenticated_active_scope_672",
            "verify_pdc_monitor_runtime_binding_authenticated_672",
            "read_pdc_uid514_transaction_receipt_authenticated_672",
            "security definer",
            "pdc_672_authenticated_active_identity_required",
            "pdc_672_uid514_scope_invalid",
            "grant execute on function public.verify_pdc_monitor_runtime_binding_authenticated_672",
            "grant execute on function public.read_pdc_uid514_transaction_receipt_authenticated_672",
            "revoke all on function public.verify_pdc_monitor_runtime_binding_authenticated_672",
            "revoke all on function public.read_pdc_uid514_transaction_receipt_authenticated_672",
            "has_function_privilege('anon'",
            "has_function_privilege('service_role'",
            "force row level security",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("grant insert", self.lower)
        self.assertNotIn("grant update", self.lower)
        self.assertNotIn("grant delete", self.lower)

    def test_uid514_is_read_only_and_no_processing_side_effects(self):
        for marker in (
            "25751401",
            "uid514_receipt_terminal",
            "uid514_receipt_pending",
            "synthetic_staging_commissioning",
            "physical_mailbox_fetch",
            "mailbox_flags_changed",
            "vehicle_operations",
            "operation_lines",
            "all_mime_parts_retained",
            "production_writes",
            "pdc_email_monitor_pilot",
            "active_mailboxes",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("insert into public.ai_email_intake", self.lower)
        self.assertNotIn("update public.ai_email_intake", self.lower)
        self.assertNotIn("send_email", self.lower)

    def test_control_and_runtime_sources_bind_successor(self):
        for path in (CONTROLLER, RUNNER, INSTALLER, PREFLIGHT):
            self.assertTrue(path.is_file(), path)
        source = PREFLIGHT.read_text(encoding="utf-8").lower()
        runner = RUNNER.read_text(encoding="utf-8").lower()
        installer = INSTALLER.read_text(encoding="utf-8").lower()
        controller = CONTROLLER.read_text(encoding="utf-8").lower()
        for text in (source, runner, installer, controller):
            self.assertIn("authenticated", text)
            self.assertIn("2026.08.44", text)
            self.assertNotIn("service_role_key", text)
        self.assertIn("verify_pdc_monitor_runtime_binding_authenticated_672", source)
        self.assertIn("read_pdc_uid514_transaction_receipt_authenticated_672", source)
        self.assertIn("active-preflight-authenticated-compatibility.py", runner)
        self.assertIn("active-prefllight-authenticated-compatibility.py", installer.replace("preflight", "prefllight"))
        self.assertIn("20260827067100", controller)
        self.assertIn("20260827067200", controller)
        self.assertNotIn("enable-scheduledtask", installer)
        self.assertNotIn("start-scheduledtask", installer)

    def test_source_hash_is_deterministic(self):
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
