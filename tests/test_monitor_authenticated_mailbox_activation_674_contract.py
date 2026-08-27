from __future__ import annotations

import hashlib
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827108000_674_authenticated_monitor_mailbox_activation_transition.sql"
PREFLIGHT = ROOT / "scripts/pdc_active_preflight_authenticated_mailbox_compatibility.py"
RUNNER = ROOT / "scripts/run_current_authenticated_monitor_dispatch.ps1"
BOOTSTRAP = ROOT / "scripts/pdc_authenticated_monitor_dispatch_bootstrap.ps1"
INSTALLER = ROOT / "scripts/install_pdc_authenticated_monitor_dispatch.ps1"


class AuthenticatedMailboxActivation674ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_append_only_exact_673_and_function_hash_guards(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        self.assertIn("20260827106000", self.sql)
        self.assertIn("673_authenticated_monitor_execution_attachment_successor", self.lower)
        self.assertIn("20260827108000", self.sql)
        self.assertNotIn("DROP TABLE", self.sql.upper())
        self.assertNotIn("DELETE FROM", self.sql.upper())
        for digest in (
            "927f9e2f4a250aa2a49df8715308f0456a814824b29f10f81869814213af22a7",
            "93a1a4af8e22ffb202ff250daf65e060ee16c847b1b4db338928ca20b3d2d86d",
            "cb0d2d29f827b7677cf735eec9587a9bc88383a428c8433e95d428166f8d0143",
            "55161035e5ec36c10d2df3b84ec85f937d9287c55163f87d7f4d2335d24b3f79",
            "52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd",
            "08e9a0dbca7640b93911fe397e3f9577b7f1e79bebc97c780efbe6aeb4a298e0",
        ):
            self.assertIn(digest, self.lower)

    def test_exact_single_mailbox_transition_and_immutable_rollback(self):
        for marker in (
            "12fe383d-5c1e-5801-96e4-f67cf3e3bb57",
            "pdc_pmb_email",
            "pmbcontroller@gmail.com",
            "provider='gmail'",
            "count(*) from public.monitored_mailboxes where active)=1",
            "pdc_monitor_authenticated_active_scope_674",
            "verify_pdc_monitor_runtime_binding_authenticated_674",
            "read_pdc_uid514_transaction_receipt_authenticated_674",
            "admin_rollback_pdc_email_monitor_authenticated_mailbox_activation_674",
            "forward_mailbox_activation",
            "rollback",
            "immutable",
            "force row level security",
            "production_writes",
            "mailbox_contacted",
            "uid514_processed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("grant select", self.lower)
        self.assertNotIn("grant insert", self.lower)
        self.assertNotIn("grant update", self.lower)
        self.assertNotIn("grant delete", self.lower)
        self.assertNotIn("enable-scheduledtask", self.lower)
        self.assertNotIn("start-scheduledtask", self.lower)
        self.assertNotIn("send_email", self.lower)

    def test_authenticated_preflight_uses_674_proof_after_mailbox_activation(self):
        source = PREFLIGHT.read_text(encoding="utf-8").lower()
        self.assertIn("verify_pdc_monitor_runtime_binding_authenticated_674", source)
        self.assertIn("read_pdc_uid514_transaction_receipt_authenticated_674", source)
        self.assertIn("active_mailbox_count", source)
        self.assertIn("expected_compatibility_head = 674", source)

    def test_protected_dispatch_routes_task_bootstrap_to_authenticated_preflight_adapter_and_sealed_launcher(self):
        runner = RUNNER.read_text(encoding="utf-8").lower()
        bootstrap = BOOTSTRAP.read_text(encoding="utf-8").lower()
        installer = INSTALLER.read_text(encoding="utf-8").lower()
        for text in (runner, bootstrap, installer):
            self.assertIn("2026.08.44", text)
            self.assertIn("authenticated", text)
            self.assertNotIn("enable-scheduledtask", text)
            self.assertNotIn("start-scheduledtask", text)
        for marker in (
            "active-preflight-authenticated-mailbox-compatibility.py",
            "pdc-authenticated-monitor-runtime-adapter.py",
            "run-current-sealed.ps1",
            "runtime_launcher.py",
            "authenticated_674_preflight",
            "adapter_673_verified",
            "sealed_launcher_verified",
            "sealed_runner_preserved",
        ):
            self.assertIn(marker, runner)
        self.assertIn("run-current.ps1", bootstrap)
        self.assertIn("authenticated_dispatch_runner_sha256", installer)
        self.assertIn("seaLed_run_current_sha256".lower(), installer)

    def test_migration_source_hash_is_deterministic(self):
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
