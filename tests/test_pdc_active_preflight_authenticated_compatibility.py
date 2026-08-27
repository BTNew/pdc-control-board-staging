from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts/pdc_active_preflight_authenticated_compatibility.py"
SPEC = importlib.util.spec_from_file_location("active_preflight_authenticated_compatibility", MODULE_PATH)
assert SPEC and SPEC.loader
compat = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(compat)


class AuthenticatedPreflightCompatibilityTests(unittest.TestCase):
    def test_standard_authenticated_claims_are_accepted_for_exact_actor(self):
        env = {
            "SUPABASE_URL": compat.EXPECTED_URL,
            "SUPABASE_ANON_KEY": "anon",
            "PDC_MONITOR_ACCESS_TOKEN": "access",
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
            "PDC_AGENTIC_PLANNER_COMMAND": "[\"C:/Python/python.exe\",\"C:/trust/pdc_active_semantic_planner.py\"]",
            "PDC_AGENTIC_PLANNER_SHA256": "a" * 64,
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT": "C:/trust/pdc-active-semantic-planner-trust-receipt.json",
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256": "b" * 64,
        }
        claims = {"role": "authenticated", "sub": compat.EXPECTED_ACTOR_ID, "email": compat.EXPECTED_ACTOR_EMAIL}
        with patch.object(compat.base, "jwt_payload", return_value=claims):
            result = compat.validate_env(env)
        self.assertEqual(result[0]["role"], "authenticated")
        self.assertEqual(result[1]["sub"], compat.EXPECTED_ACTOR_ID)

    def test_database_role_claims_are_rejected(self):
        env = {name: "placeholder" for name in compat.base.REQUIRED_ENV}
        env.update({
            "SUPABASE_URL": compat.EXPECTED_URL,
            "PDC_MONITOR_ACTOR_EMAIL": compat.EXPECTED_ACTOR_EMAIL,
            "PDC_MONITOR_GATEWAY_INSTANCE_ID": compat.EXPECTED_GATEWAY,
            "PDC_MONITOR_RELEASE_NAME": compat.EXPECTED_RELEASE_NAME,
            "IMAP_BRIDGE_HOST": "imap.gmail.com", "IMAP_BRIDGE_USERNAME": "pmbcontroller@gmail.com",
            "IMAP_BRIDGE_FOLDER": "Inbox", "IMAP_BRIDGE_MINIMUM_UID": "515",
            "IMAP_BRIDGE_UIDVALIDITY": "1", "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID": "514",
            "IMAP_BRIDGE_MARK_READ": "false", "PDC_OUTBOUND_EMAIL_ENABLED": "false",
            "PDC_AGENTIC_EMAIL_ENABLED": "true", "SUPABASE_ANON_KEY": "anon",
            "PDC_MONITOR_ACCESS_TOKEN": "access", "PDC_SUPERVISED_MONITOR_JWT": "supervised",
        })
        claims = {"role": "pdc_email_monitor", "sub": compat.EXPECTED_ACTOR_ID, "email": compat.EXPECTED_ACTOR_EMAIL}
        with patch.object(compat.base, "jwt_payload", return_value=claims):
            with self.assertRaisesRegex(compat.CompatibilityError, "CREDENTIAL_GATE_STANDARD_AUTHENTICATED_REQUIRED"):
                compat.validate_env(env)

    def test_active_live_path_uses_authenticated_successor_rpcs(self):
        manifest = {"source_sha": "e850c319989d98b45b95a28aa815d78e2c2e3a4b"}
        planner = {"planner_sha256": compat.EXPECTED_PLANNER_SHA256, "trust_receipt_sha256": compat.EXPECTED_TRUST_SHA256}
        env = {
            "SUPABASE_URL": compat.EXPECTED_URL,
            "SUPABASE_ANON_KEY": "anon",
            "PDC_MONITOR_ACCESS_TOKEN": "access",
            "PDC_SUPERVISED_MONITOR_JWT": "supervised",
            "PDC_MONITOR_ACTOR_EMAIL": compat.EXPECTED_ACTOR_EMAIL,
            "PDC_MONITOR_GATEWAY_INSTANCE_ID": compat.EXPECTED_GATEWAY,
            "PDC_MONITOR_RELEASE_NAME": compat.EXPECTED_RELEASE_NAME,
            "IMAP_BRIDGE_HOST": "imap.gmail.com", "IMAP_BRIDGE_USERNAME": "pmbcontroller@gmail.com",
            "IMAP_BRIDGE_PASSWORD": "placeholder", "IMAP_BRIDGE_FOLDER": "Inbox",
            "IMAP_BRIDGE_MINIMUM_UID": "515", "IMAP_BRIDGE_UIDVALIDITY": "1",
            "IMAP_BRIDGE_ACTIVATION_HIGH_WATER_UID": "514", "IMAP_BRIDGE_MARK_READ": "false",
            "PDC_OUTBOUND_EMAIL_ENABLED": "false", "PDC_AGENTIC_EMAIL_ENABLED": "true",
            "PDC_EXPECTED_MANIFEST_SHA256": "m" * 64,
            "PDC_AGENTIC_PLANNER_COMMAND": "[\"C:/Python/python.exe\",\"C:/trust/pdc_active_semantic_planner.py\"]",
            "PDC_AGENTIC_PLANNER_SHA256": "a" * 64,
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT": "C:/trust/pdc-active-semantic-planner-trust-receipt.json",
            "PDC_AGENTIC_PLANNER_TRUST_RECEIPT_SHA256": "b" * 64,
        }
        claims = {"role": "authenticated", "sub": compat.EXPECTED_ACTOR_ID, "email": compat.EXPECTED_ACTOR_EMAIL}
        attestation = {
            "ok": True, "code": "runtime_binding_verified_authenticated_672", "mode": "active",
            "actor_id": compat.EXPECTED_ACTOR_ID, "actor_email": compat.EXPECTED_ACTOR_EMAIL,
            "jwt_role": "authenticated", "server_application_role": "importer",
            "gateway_instance_id": compat.EXPECTED_GATEWAY, "release_name": compat.EXPECTED_RELEASE_NAME,
            "source_sha": manifest["source_sha"], "manifest_sha256": "m" * 64,
            "semantic_planner_sha256": planner["planner_sha256"],
            "semantic_planner_trust_receipt_sha256": planner["trust_receipt_sha256"],
            "planner_commissioned": True, "writer_active": True, "operational": True,
            "activation_ready": True, "production_writes": False, "task_enabled": False,
            "mailbox_contacted": False, "uid514_processed": False, "migration_head": 503,
            "compatibility_successor_head": 672,
        }
        receipt = {"ok": True, "code": "uid514_receipt_terminal", "terminal": True,
                   "recovery_event_id": 25751401, "mailbox": "pmbcontroller@gmail.com",
                   "folder": "Inbox", "uidvalidity": 1, "uid": 514}
        with patch.object(compat.base, "jwt_payload", return_value=claims), patch.object(compat.base, "rpc", side_effect=[attestation, receipt]) as call:
            result = compat.validate_live(env, manifest, planner, True)
        self.assertEqual(result["uid514_receipt_status"]["code"], "uid514_receipt_terminal")
        self.assertEqual([item.args[1] for item in call.call_args_list], [compat.AUTHENTICATED_VERIFY_RPC, compat.AUTHENTICATED_UID514_RPC])


if __name__ == "__main__":
    unittest.main(verbosity=2)
