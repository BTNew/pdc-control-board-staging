from __future__ import annotations

import re
import unittest
from pathlib import Path

from pglast import parse_sql


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260902261000_pdc_email_ai_v2_karratha_toyota_sender_enrollment_20260902.sql"
CONTROLLER = ROOT / "scripts/apply_pdc_email_ai_v2_karratha_toyota_sender_enrollment_staging.py"
TARGET_HASH = "ba17511f3cd912553d2f31744dde2b1be8d916d7dd2c1b94b6d2ce861600f2ae"


class KarrathaToyotaSenderEnrollmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.sql = MIGRATION.read_text(encoding="utf-8")
        self.controller = CONTROLLER.read_text(encoding="utf-8")

    def test_migration_is_exact_hash_only_and_staging_guarded(self):
        self.assertGreaterEqual(len(parse_sql(self.sql)), 12)
        for marker in (
            "20260902260000",
            "20260902261000",
            "pdc_staging_environment_sentinel",
            "cdsmnqxtyyoeoznmbidd",
            "pdc_production_environment_sentinel",
            "current_user<>'postgres'",
            "session_user<>'postgres'",
            "pg_advisory_xact_lock",
            "LOCK TABLE supabase_migrations.schema_migrations",
            TARGET_HASH,
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)
        self.assertNotIn("@gmail.com", self.sql.lower())
        self.assertNotRegex(self.sql, r"(?i)\b(drop|truncate)\s+(table|function|policy)")
        self.assertNotRegex(self.sql, r"(?i)\b(grant|trust).{0,80}\b(domain|gmail|karrathatoyota\.com\.au)")

    def test_predecessor_hash_history_and_rollback_controls_are_present(self):
        for marker in (
            "predecessor_version",
            "successor_version",
            "predecessor_hash",
            "successor_hash",
            "pdc_email_ai_v2_sender_enrollment_history_20260902",
            "FORCE ROW LEVEL SECURITY",
            "REVOKE ALL ON public.pdc_email_ai_v2_sender_enrollment_history_20260902",
            "BEFORE UPDATE OR DELETE",
            "PDC_20260902261000_HISTORY_IMMUTABLE",
            "PDC_20260902261000_POSTCONDITION_FAILED",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.sql)

    def test_exact_sender_insert_has_no_domain_widening_or_operational_dispatch(self):
        self.assertEqual(self.sql.count(TARGET_HASH), 5)
        self.assertIn("retained authenticated PD attachment source", self.sql)
        self.assertIn("NOTIFY pgrst", self.sql)
        pre_ledger_sql = self.sql.split("INSERT INTO supabase_migrations", 1)[0]
        self.assertNotIn("pdc_email_ai_successor_execute", pre_ledger_sql)
        self.assertNotIn("import_pdc_authenticated_email", pre_ledger_sql)

    def test_controller_is_hash_gated_and_proves_positive_negative_acl_and_rollback(self):
        for marker in (
            "PDC_APPROVE_STAGING_MIGRATION_20260902261000",
            "PDC_SENDER_NON_STAGING_TARGET",
            "exact_sender_active_count",
            "unapproved_negative_active_count",
            "history_select_acl",
            "enrollment_select_acl",
            "sender_enrollment_rollback_probe",
            "PDC_20260902261000_HISTORY_IMMUTABLE",
            "production_writes",
            "mailbox_contacted",
            "outbound_email",
            "action_rpc_invoked",
        ):
            with self.subTest(marker=marker):
                self.assertIn(marker, self.controller)
        self.assertRegex(self.controller, r'REF = "cdsmnqxtyyoeoznmbidd"')
        self.assertRegex(self.controller, r'TARGET = \("20260902261000",')
        self.assertEqual(len(re.findall(re.escape(TARGET_HASH), self.controller)), 1)


if __name__ == "__main__":
    unittest.main()
