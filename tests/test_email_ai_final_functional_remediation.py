from __future__ import annotations

import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class EmailAiFinalFunctionalRemediationTests(unittest.TestCase):
    def test_final_successor_sources_are_staging_only_and_append_only(self):
        paths = sorted((ROOT / "supabase/staging_only").glob("20260828*_*acceptance*.sql"))
        paths += sorted((ROOT / "supabase/staging_only").glob("20260828*_*email_ai_final*.sql"))
        self.assertTrue(paths)
        for path in paths:
            sql = path.read_text(encoding="utf-8").lower()
            self.assertNotIn("vjdtsswhroyguxyfjdkt", sql)
            self.assertNotRegex(sql, r"\b(drop|truncate)\s+(table|function|schema)")
        final = (ROOT / "supabase/staging_only/20260828140000_693_authenticated_email_ai_final_functional_remediation.sql").read_text(encoding="utf-8").lower()
        for marker in (
            "pdc_email_ai_acceptance_plans_693", "pdc_email_ai_acceptance_action_receipts_693",
            "pdc_email_ai_acceptance_final_receipts_693", "pdc_email_ai_resolve_date_693",
            "pdc_email_ai_scope_693", "record_pdc_email_ai_acceptance_plan_693",
            "execute_pdc_email_ai_acceptance_action_693", "finalize_pdc_email_ai_acceptance_693",
            "pdc_email_vehicle_location_snapshot_pre_693", "13000765", "2027-06-12",
            "2026-09-15", "2026-09-10", "pdc-monitor-staging-m502-2026.08.44",
            "provider_created',false", "uid514_processed',false", "production_writes',false",
        ):
            self.assertIn(marker, final)

    def test_final_source_hash_is_stable(self):
        path = ROOT / "supabase/staging_only/20260828140000_693_authenticated_email_ai_final_functional_remediation.sql"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), "21b81a4a95a3095024d176681365c147cfeadcf1142860cfd75d05c3191f7ff1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
