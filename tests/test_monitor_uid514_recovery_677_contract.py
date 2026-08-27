from __future__ import annotations

import hashlib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827111000_677_uid514_exact_recovery_successor.sql"


class Uid514ExactRecovery677ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_migration_is_append_only_and_anchors_exact_predecessors(self):
        self.assertEqual(self.sql.count("BEGIN;"), 1)
        self.assertEqual(self.sql.count("COMMIT;"), 1)
        for marker in (
            "20260827110000",
            "676_authenticated_monitor_rollback_control_repair",
            "9fe5f8bb31e15b9047a6c6d9304af2cfab19f9d33ec6161dcf31fbcf92367b43",
            "4c920ef25e257cc6de7b5009bbccc81e630974a2ca60f22cf5a33cddfdf6e629",
            "de073b856238150c88079b88c264d86a41d920155c760bedf7f0e06bb8c02351",
            "d6c57dd8f0215cff71e479b4b50e40de10dea2113216534ccc2edd9048db3bcb",
            "e850c319989d98b45b95a28aa815d78e2c2e3a4b",
            "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d",
            "7e08a00bc099610aa919bb7c3089ef84b91a74bafd69f95fab06bfccfdf67348",
            "e3e30ace04e676e34f271b161283b9e4764d462f76428d63826fa3cb153d7227",
            "52affc8ea7374f6067be51f56cb633deb520b0628801b427e5215c873ec26ebd",
            "a14a2d2b4ad3514a3367246ae9b8705762eda41987f9491980594e9c62e7d036",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("delete from", self.lower)
        self.assertNotIn("drop function", self.lower)

    def test_exact_recovery_evidence_is_server_bound(self):
        for marker in (
            "pmbcontroller@gmail.com",
            "inbox",
            "uidvalidity=1",
            "uid=514",
            "25751401",
            "440d174b6e1994fbb1afb9c285f068cb62b130f541ebaa834d590f44bdbec280",
            "7bc4e2dec9b1c405098f1ca7b4c646bf3262158e328f9f548abb855b8ef2f21a",
            "ffaa2bfbca036f9dbcbe10de9a43f8a141fd2a84f9fea75c0e114b96b87b4cf3",
            "c60dae99a28cdccdee51f5bdffa43382d9b7eb31af690c31caedcc8d4f66cf40",
            "9a8f412ec5c9e108817da26b20993fa0a5e61a54f7ac983673c1ef9e2d8af8f4",
            "66b790ba3a72760e00a034bf7f5cf5a7e1defe5d6947373216f8c8dc4ed8acff",
            "b297f4f9070f6c78c88aae099630b78bb5157c3094c45a30b5cfef0f263ac3b1",
            "ea248634b8610f757907c519ea2f7ba243fb1602c8114cbde947707aff8407ae",
            "observed_mime_part_count=7",
            "retained_authenticated_attachment_count=4",
            "all_mime_parts_retained",
            "stock_number='13016925'",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("authorize_pdc_uid514_retained_intake_257", self.lower)
        self.assertIn("enqueue_pdc_email_intake(jsonb,jsonb)", self.lower)
        self.assertIn("reviewed_typed", self.lower)
        self.assertIn("current_setting('pdc.uid514.recovery_token'", self.lower)

    def test_scope_is_not_a_generic_sub_515_bypass(self):
        self.assertIn("provider_uid='imap_uid:514'", self.lower)
        self.assertIn("p_recovery_event_id<>25751401", self.lower)
        self.assertIn("pdc_677_uid514_recovery_scope_invalid", self.lower)
        self.assertIn("pdc_677_uid514_recovery_capability_missing", self.lower)
        self.assertIn("pdc_monitor_authenticated_active_scope_674", self.lower)
        self.assertIn("pdc_pmb_email", self.lower)
        self.assertNotIn("substring(new.provider_uid from '^imap_uid:([0-9]+)$')::bigint<515", self.lower)
        self.assertNotIn("minimum_uid", self.lower)
        self.assertNotIn("grant insert", self.lower)
        self.assertNotIn("grant update", self.lower)
        self.assertNotIn("grant delete", self.lower)

    def test_idempotence_rollback_and_denials_are_explicit(self):
        for marker in (
            "uid514_recovery_replayed",
            "uid514_recovery_enqueued",
            "admin_rollback_pdc_uid514_recovery_677",
            "uid514_recovery_history_immutable",
            "force row level security",
            "wrong actor",
            "wrong gateway",
            "anon",
            "service_role",
            "not task_enabled",
            "not mailbox_contacted",
            "not uid514_processed",
            "not production_writes",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertRegex(hashlib.sha256(MIGRATION.read_bytes()).hexdigest(), r"^[a-f0-9]{64}$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
