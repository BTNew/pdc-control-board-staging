from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / "supabase/staging_only/20260831420000_pdc_email_canonical_import_capability.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


class PdcEmailCanonicalImportCapabilityTests(unittest.TestCase):
    def test_staging_only_exact_predecessor_and_identity(self):
        self.assertEqual(SQL.count("BEGIN;"), 1)
        self.assertEqual(SQL.count("COMMIT;"), 1)
        self.assertIn("20260831410000", SQL)
        self.assertIn("862_allow_append_only_monitor_replay_subsets", LOWER)
        self.assertIn("cdsmnqxtyyoeoznmbidd", LOWER)
        self.assertIn("pmbcontroller+pdc-viewer-staging-20260830@gmail.com", LOWER)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", LOWER)
        self.assertIn("pdc_production_environment_sentinel", LOWER)

    def test_only_canonical_function_gets_authenticated_execute(self):
        self.assertIn(
            "grant execute on function public.import_pdc_jobcard_attachment_canonical",
            LOWER,
        )
        self.assertIn(
            "revoke all on function public.import_pdc_jobcard_attachment_canonical",
            LOWER,
        )
        self.assertNotIn("grant execute on public.pdc_monitor_canonical_import_capabilities", LOWER)
        self.assertIn("revoke all on public.pdc_monitor_canonical_import_capabilities_20260831", LOWER)
        self.assertIn("alter table public.pdc_monitor_canonical_import_capabilities_20260831 force row level security", LOWER)
        self.assertRegex(
            LOWER,
            r"grant execute on function public\.import_pdc_jobcard_attachment_canonical[\s\S]+?to authenticated;",
        )
        self.assertNotRegex(
            LOWER,
            r"grant execute on function public\.import_pdc_jobcard_attachment_canonical[\s\S]+?to (?:public|anon|service_role|pdc_email_monitor);",
        )

    def test_capability_is_exact_and_does_not_grant_writer(self):
        self.assertIn("capability text not null check(capability='canonical_attachment_import_only')", LOWER)
        self.assertIn("environment text not null check(environment='staging')", LOWER)
        self.assertIn("auth_user_id uuid not null unique references auth.users(id)", LOWER)
        self.assertNotIn("insert into public.pdc_monitor_stage_activation_writers", LOWER)
        self.assertNotIn("update public.pdc_monitor_stage_activation_writers", LOWER)
        self.assertIn("if not found and not exists(", LOWER)
        self.assertIn("c.auth_user_id=v_actor and c.active", LOWER)

    def test_rollback_is_disable_only_and_admin_gated(self):
        self.assertIn("disable_pdc_monitor_canonical_import_capability_20260831", LOWER)
        self.assertIn("pdc_20260831420000_admin_rollback_required", LOWER)
        self.assertIn("active=false", LOWER)
        self.assertNotIn("delete from public.pdc_monitor_canonical_import_capabilities_20260831", LOWER)
        self.assertNotIn("active=true", LOWER)

    def test_business_guards_are_preserved_by_source_contract(self):
        for marker in (
            "canonical importer remains the authority",
            "stock identity",
            "recognised work keys",
            "ambiguity",
            "idempotency",
            "lifecycle rules",
            "no evidence deletion",
        ):
            self.assertIn(marker, LOWER)
        self.assertEqual(LOWER.count("insert into supabase_migrations.schema_migrations"), 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
