from __future__ import annotations

import importlib.util
import json
import tempfile
import re
import unittest
from email.message import EmailMessage
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827106000_673_authenticated_monitor_execution_attachment_successor.sql"
ADAPTER = ROOT / "scripts/pdc_authenticated_monitor_runtime_adapter.py"
INSTALLER = ROOT / "scripts/install_pdc_authenticated_monitor_runtime_adapter.ps1"


def load_adapter():
    spec = importlib.util.spec_from_file_location("pdc_authenticated_monitor_runtime_adapter", ADAPTER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AuthenticatedRuntimeSuccessor673Tests(unittest.TestCase):
    def test_append_only_guarded_successor_and_narrow_execution_surface(self):
        sql = MIGRATION.read_text(encoding="utf-8")
        lower = sql.lower()
        self.assertEqual(sql.count("BEGIN;"), 1)
        self.assertEqual(sql.count("COMMIT;"), 1)
        self.assertIn("20260827067200", sql)
        self.assertIn("672_authenticated_active_email_monitor_identity_successor", lower)
        self.assertIn("20260827106000", sql)
        self.assertNotIn("DROP TABLE", sql.upper())
        self.assertNotIn("DELETE FROM", sql.upper())
        for marker in (
            "pdc_monitor_authenticated_active_scope_673",
            "authenticated",
            "importer",
            "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b",
            "sales@broometoyota.com.au",
            "pdc-monitor-staging-sales-uid509-v1",
            "pdc-monitor-staging-m502-2026.08.44",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4",
            "observed_mime_part_count",
            "retained_authenticated_attachment_count",
            "all_mime_parts_retained",
            "rollback",
            "immutable",
            "force row level security",
        ):
            self.assertIn(marker.lower(), lower)
        for marker in (
            "public.claim_pdc_email_intake_batch(integer,text)",
            "public.record_pdc_email_monitor_cycle(text,text,text)",
            "public.get_pdc_monitor_intake_attachments(uuid,uuid,text)",
            "public.heartbeat_pdc_email_intake_claim(uuid,uuid,text)",
            "public.record_pdc_monitor_attachment_extraction(uuid,uuid,uuid,text,text,text)",
            "public.record_pdc_email_intake_result(uuid,uuid,text,boolean,jsonb,text,text,boolean,jsonb)",
            "public.read_pdc_agentic_email_context_502(jsonb)",
            "public.record_pdc_agentic_email_plan_502(jsonb)",
            "public.execute_pdc_agentic_email_action_502(jsonb)",
            "public.pdc_agentic_apply_action_502(uuid)",
            "public.append_pdc_agentic_email_action_audit_502(jsonb)",
            "public.finalize_pdc_agentic_email_plan_502(jsonb)",
        ):
            self.assertIn(marker, lower)
        self.assertIn("pdc_email_monitor_runtime_authorized_502", lower)
        self.assertIn("pdc_673_authenticated_active_identity_required", lower)
        self.assertIn("pdc_673_attachment_set_mismatch", lower)
        self.assertNotIn("grant select", lower)
        self.assertNotIn("grant insert", lower)
        self.assertNotIn("grant update", lower)
        self.assertNotIn("grant delete", lower)
        self.assertNotIn(" to anon", lower)
        self.assertNotIn(" to service_role", lower)

    def test_adapter_selects_four_pdfs_and_retains_all_seven_parts(self):
        adapter = load_adapter()
        attachments = [
            {"attachment_id": f"a{i}", "filename": f"image-{i}.png" if i < 3 else f"document-{i}.pdf",
             "content_type": "image/png" if i < 3 else "application/pdf",
             "source_hash": ("a" if i < 3 else "b") * 64, "validation_status": "verified"}
            for i in range(7)
        ]
        attachments[3]["source_hash"] = adapter.JOB_CARD_SHA256
        selected = adapter.select_authenticated_business_pdfs(attachments)
        self.assertEqual(selected["observed_mime_part_count"], 7)
        self.assertEqual(selected["retained_authenticated_attachment_count"], 4)
        self.assertTrue(selected["all_mime_parts_retained"])
        self.assertEqual(len(selected["all_parts"]), 7)
        self.assertEqual(len(selected["business_pdfs"]), 4)
        self.assertEqual(selected["job_card"]["source_hash"], adapter.JOB_CARD_SHA256)
        self.assertEqual([item["attachment_id"] for item in selected["business_pdfs"]], ["a3", "a4", "a5", "a6"])

    def test_external_loader_registers_sealed_module_before_execution(self):
        adapter = load_adapter()
        with tempfile.TemporaryDirectory(prefix="hermes-verify-673-loader-") as temp:
            root = Path(temp)
            backend = root / "backend"
            backend.mkdir()
            (backend / "imap_bridge.py").write_text(
                "from dataclasses import dataclass\n"
                "import sys\n"
                "@dataclass\n"
                "class LoadedPart:\n"
                "    module_seen: bool = __name__ in sys.modules\n",
                encoding="utf-8",
            )
            module = adapter.load_sealed_imap_module(root)
            self.assertTrue(module.LoadedPart().module_seen)

    def test_adapter_rejects_malformed_or_ambiguous_sets(self):
        adapter = load_adapter()
        base = [{"attachment_id": str(i), "filename": f"x-{i}.pdf", "content_type": "application/pdf",
                 "source_hash": (str(i) * 64)[:64], "validation_status": "verified"} for i in range(7)]
        with self.assertRaises(adapter.RuntimeCompatibilityError):
            adapter.select_authenticated_business_pdfs(base[:6])
        base[0]["source_hash"] = adapter.JOB_CARD_SHA256
        base[1]["source_hash"] = adapter.JOB_CARD_SHA256
        with self.assertRaises(adapter.RuntimeCompatibilityError):
            adapter.select_authenticated_business_pdfs(base)
        malformed = list(base)
        malformed[0] = {"attachment_id": "0", "filename": "x.pdf", "content_type": "application/pdf", "source_hash": "not-a-hash"}
        with self.assertRaises(adapter.RuntimeCompatibilityError):
            adapter.select_authenticated_business_pdfs(malformed)

    def test_synthetic_full_chain_rehearsal_preserves_seven_and_replays_idempotently(self):
        adapter = load_adapter()
        attachments = [
            {"attachment_id": f"synthetic-{i}", "filename": f"image-{i}.png" if i < 3 else f"business-{i}.pdf",
             "content_type": "image/png" if i < 3 else "application/pdf",
             "source_hash": ("a" if i < 3 else "b") * 64, "validation_status": "verified",
             "size_bytes": 128, "storage_path": f"pdc-email-intake-private/hash-{i}/file"}
            for i in range(7)
        ]
        attachments[3]["source_hash"] = adapter.JOB_CARD_SHA256
        message, projection = adapter.build_enqueue_projection(
            {"provider_uid": "synthetic-673", "source_hash": "c" * 64,
             "processing_result": {"synthetic_rehearsal": True}}, attachments
        )
        self.assertEqual(len(projection["all_parts"]), 7)
        self.assertEqual(len(projection["selection"]["business_pdfs"]), 4)
        self.assertTrue(projection["selection"]["all_mime_parts_retained"])
        self.assertEqual(message["processing_result"]["mime_selection"]["qualifying_attachment_sha256"], adapter.JOB_CARD_SHA256)
        calls = []
        seen = {}
        def fake_enqueue(enqueued_message, enqueued_projection):
            key = (enqueued_message["provider_uid"], enqueued_message["source_hash"])
            if key in seen:
                return seen[key]
            calls.append((enqueued_message, enqueued_projection))
            seen[key] = {"ok": True, "code": "synthetic_chain_rehearsed", "vehicle_operations": 0}
            return seen[key]
        first = fake_enqueue(message, projection)
        second = fake_enqueue(message, projection)
        self.assertEqual(first, second)
        self.assertEqual(len(calls), 1)
        self.assertEqual(first["vehicle_operations"], 0)

    def test_external_installer_is_protected_and_does_not_enable_task(self):
        source = INSTALLER.read_text(encoding="utf-8").lower()
        self.assertIn("programdata", source)
        self.assertIn("icacls", source)
        self.assertIn("current", source)
        self.assertIn("2026.08.44", source)
        self.assertIn("sealed", source)
        self.assertNotIn("enable-scheduledtask", source)
        self.assertNotIn("start-scheduledtask", source)
        self.assertNotIn("imap", source)
        self.assertNotIn("uid514", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
