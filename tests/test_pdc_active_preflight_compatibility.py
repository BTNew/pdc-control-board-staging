from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/pdc_active_preflight_compatibility.py"
RUNNER_PATH = ROOT / "scripts/run_current_active_compatibility.ps1"
INSTALLER_PATH = ROOT / "scripts/install_pdc_active_preflight_compatibility.ps1"
MIGRATION_670 = ROOT / "supabase/staging_only/20260827067000_670_email_monitor_active_capability_uid514_seven_part_reconciliation.sql"
MIGRATION_671 = ROOT / "supabase/staging_only/20260827067100_671_email_monitor_active_planner_rotation_after_670.sql"
SPEC = importlib.util.spec_from_file_location("active_preflight_compatibility", MODULE_PATH)
assert SPEC and SPEC.loader
compat = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compat)


class ActivePreflightCompatibilityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="hermes-verify-active-preflight-")
        base = Path(self.temp.name)
        self.release = base / "release"
        self.trust = base / "trust"
        self.control = base / "control" / "active-preflight-compatibility.py"
        self.release.mkdir()
        self.trust.mkdir()
        self.control.parent.mkdir()
        self.planner_source = ROOT / "backend/pdc_active_semantic_planner.py"
        shutil.copy2(self.planner_source, self.trust / "pdc_active_semantic_planner.py")
        self.planner_sha = hashlib.sha256(self.planner_source.read_bytes()).hexdigest()
        self.trust_sha = "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227"
        shutil.copy2(
            ROOT / "runtime_release/pdc-active-semantic-planner-trust-receipt.json",
            self.trust / "pdc-active-semantic-planner-trust-receipt.json",
        )
        self.manifest = {
            "release_name": compat.EXPECTED_RELEASE_NAME,
            "release_version": compat.EXPECTED_RELEASE_VERSION,
            "supported_migration_head": compat.EXPECTED_HEAD,
            "gateway_instance_id": compat.EXPECTED_GATEWAY,
            "active_actor_id": compat.EXPECTED_ACTOR_ID,
            "active_actor_email": compat.EXPECTED_ACTOR_EMAIL,
            "active_actor_email_prefix": "sales@",
            "release_series": compat.EXPECTED_RELEASE_SERIES,
            "agentic_active_planner_interface": compat.EXPECTED_INTERFACE,
            "agentic_active_planner_trust_receipt_sha256": None,
            "source_sha": "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
        }
        manifest_bytes = (json.dumps(self.manifest, sort_keys=True) + "\n").encode()
        (self.release / "release-manifest.json").write_bytes(manifest_bytes)
        (self.trust / "MANIFEST_SHA256").write_text(hashlib.sha256(manifest_bytes).hexdigest(), encoding="ascii")
        self.env = {
            "PDC_AGENTIC_PLANNER_COMMAND": json.dumps([sys.executable, str(self.trust / "pdc_active_semantic_planner.py")]),
            "PDC_AGENTIC_PLANNER_SHA256": self.planner_sha,
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT": str(self.trust / "pdc-active-semantic-planner-trust-receipt.json"),
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256": self.trust_sha,
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_exact_digest_match_uses_external_671_receipt_even_when_sealed_spec_is_null(self):
        manifest, paths = compat.validate_release(self.release, self.trust)
        planner = compat.validate_external_planner(self.env, paths, manifest)
        self.assertEqual(planner, {
            "planner_sha256": self.planner_sha,
            "trust_receipt_sha256": self.trust_sha,
        })
        self.assertIsNone(manifest["agentic_active_planner_trust_receipt_sha256"])

    def test_planner_or_trust_digest_mismatch_fails_closed(self):
        manifest, paths = compat.validate_release(self.release, self.trust)
        mismatched = dict(self.env, PDC_AGENTIC_PLANNER_SHA256="0" * 64)
        with self.assertRaisesRegex(compat.CompatibilityError, "planner environment digest mismatch"):
            compat.validate_external_planner(mismatched, paths, manifest)
        mismatched = dict(self.env, PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256="0" * 64)
        with self.assertRaisesRegex(compat.CompatibilityError, "planner trust receipt environment digest mismatch"):
            compat.validate_external_planner(mismatched, paths, manifest)

    def test_release_binding_is_exact_2026_08_44(self):
        manifest, _ = compat.validate_release(self.release, self.trust)
        self.assertEqual(manifest["release_name"], compat.EXPECTED_RELEASE_NAME)
        changed = dict(self.manifest, release_name="pdc-monitor-staging-m502-2026.08.45")
        raw = (json.dumps(changed, sort_keys=True) + "\n").encode()
        (self.release / "release-manifest.json").write_bytes(raw)
        (self.trust / "MANIFEST_SHA256").write_text(hashlib.sha256(raw).hexdigest(), encoding="ascii")
        with self.assertRaisesRegex(compat.CompatibilityError, "sealed \.44 release binding mismatch"):
            compat.validate_release(self.release, self.trust)

    def test_path_constraints_reject_nested_trust_and_symlink_like_layout(self):
        nested = self.release / "trust"
        nested.mkdir()
        with self.assertRaisesRegex(compat.CompatibilityError, "trust root|sealed release"):
            compat.validate_external_paths(self.release, nested, self.control)
        with self.assertRaisesRegex(compat.CompatibilityError, "exact relative child"):
            compat.child_path(self.trust, "../planner.py", "external planner")

    def test_acl_constraints_allow_only_system_admin_and_local_service_read(self):
        compat.validate_acl_snapshot(
            "O:SYG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;0x1200a9;;;LS)(A;OICI;FA;;;BA)"
        )
        with self.assertRaisesRegex(compat.CompatibilityError, "unapproved principal"):
            compat.validate_acl_snapshot(
                "O:SYG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;0x1200a9;;;LS)(A;OICI;FA;;;BA)(A;OICI;R;;;WD)"
            )
        with self.assertRaisesRegex(compat.CompatibilityError, "read/execute only"):
            compat.validate_acl_snapshot(
                "O:SYG:SYD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;LS)(A;OICI;FA;;;BA)"
            )

    def test_live_attestation_digest_mismatch_fails_closed(self):
        manifest, paths = compat.validate_release(self.release, self.trust)
        planner = compat.validate_external_planner(self.env, paths, manifest)
        env = dict(self.env, **{
            "SUPABASE_URL": compat.EXPECTED_URL,
            "SUPABASE_ANON_KEY": "anon",
            "PDC_MONITOR_ACCESS_TOKEN": "token",
            "PDC_SUPERVISED_MONITOR_JWT": "supervised",
            "PDC_MONITOR_ACTOR_EMAIL": compat.EXPECTED_ACTOR_EMAIL,
            "PDC_MONITOR_GATEWAY_INSTANCE_ID": compat.EXPECTED_GATEWAY,
            "PDC_MONITOR_RELEASE_NAME": compat.EXPECTED_RELEASE_NAME,
            "IMAP_BRIDGE_HOST": "imap.gmail.com",
            "IMAP_BRIDGE_USERNAME": "pmbcontroller@gmail.com",
            "IMAP_BRIDGE_PASSWORD": "placeholder",
            "IMAP_BRIDGE_FOLDER": "Inbox",
            "IMAP_BRIDGE_MINIMUM_UID": "515",
            "IMAP_BRIDGE_UIDVALIDITY": "1",
            "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID": "514",
            "IMAP_BRIDGE_MARK_READ": "false",
            "PDC_OUTBOUND_EMAIL_ENABLED": "false",
            "PDC_AGENTIC_EMAIL_ENABLED": "true",
            "PDC_EXPECTED_MANIFEST_SHA256": hashlib.sha256((self.release / "release-manifest.json").read_bytes()).hexdigest(),
        })
        fake = {
            "ok": True, "migration_head": compat.EXPECTED_HEAD, "mode": "active",
            "actor_id": compat.EXPECTED_ACTOR_ID, "gateway_instance_id": compat.EXPECTED_GATEWAY,
            "release_name": compat.EXPECTED_RELEASE_NAME,
            "manifest_sha256": hashlib.sha256((self.release / "release-manifest.json").read_bytes()).hexdigest(),
            "source_sha": manifest["source_sha"],
            "semantic_planner_sha256": planner["planner_sha256"],
            "semantic_planner_trust_receipt_sha256": "0" * 64,
            "planner_commissioned": True, "writer_active": True, "operational": True,
            "activation_ready": True, "production_writes": False,
        }
        claims = {"role": "pdc_email_monitor", "sub": compat.EXPECTED_ACTOR_ID, "email": compat.EXPECTED_ACTOR_EMAIL}
        token = "eyJ." + "eyJ" + ".sig"
        with patch.object(compat, "jwt_payload", return_value=claims), patch.object(compat, "rpc", side_effect=[fake]):
            with self.assertRaisesRegex(compat.CompatibilityError, "live 670/671 planner"):
                compat.validate_live(env, manifest, planner, False)
        fake["semantic_planner_trust_receipt_sha256"] = planner["trust_receipt_sha256"]
        receipt = {"ok": True, "code": "uid514_receipt_terminal", "terminal": True,
                   "recovery_event_id": 25751401, "mailbox": "pmbcontroller@gmail.com",
                   "folder": "Inbox", "uidvalidity": 1, "uid": 514}
        with patch.object(compat, "jwt_payload", return_value=claims), patch.object(compat, "rpc", side_effect=[fake, receipt]):
            result = compat.validate_live(env, manifest, planner, True)
        self.assertEqual(result["attestation"]["semantic_planner_trust_receipt_sha256"], compat.EXPECTED_TRUST_SHA256)
        self.assertEqual(result["uid514_receipt_status"]["code"], "uid514_receipt_terminal")

    def test_migrations_and_control_runner_bind_the_same_successor(self):
        migration_670 = MIGRATION_670.read_text(encoding="utf-8").lower()
        migration_671 = MIGRATION_671.read_text(encoding="utf-8").lower()
        source = MODULE_PATH.read_text(encoding="utf-8")
        runner = RUNNER_PATH.read_text(encoding="utf-8")
        installer = INSTALLER_PATH.read_text(encoding="utf-8")
        for digest in (compat.PREDECESSOR_PLANNER_SHA256, compat.PREDECESSOR_TRUST_SHA256):
            self.assertIn(digest, migration_670)
            self.assertIn(digest, migration_671)
        for digest in (compat.EXPECTED_PLANNER_SHA256, compat.EXPECTED_TRUST_SHA256):
            self.assertIn(digest, migration_671)
            self.assertIn(digest, source)
            self.assertIn(digest, installer)
        self.assertIn("p_mode", source)
        self.assertIn("active-preflight-compatibility.py", runner)
        self.assertIn("$AgenticMode -eq 'active'", runner)
        self.assertIn("--agentic-mode", runner)
        self.assertNotIn("Enable-ScheduledTask", installer)
        self.assertNotIn("Start-ScheduledTask", installer)
        self.assertNotIn("imap", installer.lower())

    def test_active_environment_gate_rejects_contained_or_false_switch(self):
        env = dict(self.env)
        env.update({
            "PDC_AGENTIC_EMAIL_ENABLED": "false",
            "PDC_MONITOR_ACTOR_EMAIL": compat.EXPECTED_ACTOR_EMAIL,
        })
        with self.assertRaisesRegex(compat.CompatibilityError, "CREDENTIAL_GATE_MISSING_PROTECTED_VALUES"):
            compat.validate_env(env)


if __name__ == "__main__":
    unittest.main(verbosity=2)
