from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828020000_714_fail_closed_navision_family_catalog_hardening.sql"


class NavisionDelivery714ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_current_head_and_source_tree_guards_are_append_only(self):
        for marker in (
            "7e6bc3c94d173620c9070ff5f63a93f1dcdf9408",
            "a44984a27118dd2fb719ca57c715953786b2f850",
            "20260828010000",
            "683_uid514_capability_mint_replay_repair",
            "pdc_714_exact_live_head_required",
            "pdc_714_preserved_successor_chain_required",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("truncate", self.lower)
        self.assertIn("drop schema pdc_hermes_security_probe_714 cascade", self.lower)

    def test_inventory_classifies_postgrest_and_all_non_system_schemas(self):
        for marker in (
            "pg_proc",
            "pg_namespace",
            "pdc_navision_function_security_inventory_714",
            "pdc_navision_postgrest_schema_inventory_714",
            "postgrest_exposed",
            "live_postgrest_config",
            "public, graphql_public",
            "n.nspname !~ '^pg_'",
            "information_schema",
            "lower(p.proname)",
            "pg_get_function_identity_arguments",
            "pg_get_function_arguments",
            "proargdefaults",
            "proconfig",
            "aclexplode",
            "grant_option",
        ):
            self.assertIn(marker.lower(), self.lower)
        for family in (
            "reconcile_navision_delivery_700%",
            "reconcile_navision_operational_record%",
            "process_pdc_monitor_body_location_20260821033000%",
        ):
            self.assertIn(family, self.lower)

    def test_hardening_revokes_every_noncanonical_routine_and_normalizes_owner(self):
        self.assertIn("revoke all on routine %s from public,anon,authenticated,service_role,pdc_email_monitor", self.lower)
        self.assertIn("alter routine %s owner to postgres", self.lower)
        self.assertIn("has_function_privilege('public'", self.lower)
        self.assertIn("has_function_privilege('anon'", self.lower)
        self.assertIn("has_function_privilege('authenticated'", self.lower)
        self.assertIn("has_function_privilege('service_role'", self.lower)
        self.assertIn("has_function_privilege('pdc_email_monitor'", self.lower)
        self.assertIn("pdc_714_unexpected_callable_family_member", self.lower)
        self.assertIn("pdc_714_acl_or_owner_drift", self.lower)
        self.assertIn("pdc_714_postgrest_schema_classification_failed", self.lower)

    def test_exact_canonical_signatures_have_strict_metadata_and_acl(self):
        for signature in (
            "reconcile_navision_delivery_700(uuid)",
            "reconcile_navision_operational_record(uuid,uuid,text)",
            "process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text)",
        ):
            self.assertIn(signature, self.lower)
        for marker in (
            "owner_name",
            "owner_name<>'postgres'",
            "prokind in ('f','p')",
            "security_definer",
            "i.volatility<>'v'",
            "search_path=pg_catalog, public, auth, extensions",
            "search_path=pg_catalog, public, extensions, auth",
            "statement_timeout=120s",
            "has_defaults",
            "identity_arguments",
            "grantor",
            "grantee",
            "grant_option",
            "execute_authenticated",
            "execute_public",
            "pdc_714_canonical_metadata_failed",
            "pdc_714_canonical_metadata_failed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("is_canonical", self.lower)
        self.assertIn("boolean not null", self.lower)

    def test_hostile_probes_cover_mixed_case_alternate_default_and_grant_option(self):
        for marker in (
            '"Reconcile_Navision_Delivery_700"',
            "pdc_hermes_security_probe_714",
            "default 'hermes-test-714'",
            "with grant option",
            "reconcile_navision_delivery_700%",
            "reconcile_navision_operational_record%",
            "process_pdc_monitor_body_location_20260821033000%",
            "rollback-contained",
            "pdc_714_hostile_probe_failed",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("hermes-test", self.lower)

    def test_exact_grants_are_restored_without_public_implicit_execute(self):
        self.assertGreaterEqual(self.lower.count("grant execute on function public."), 3)
        self.assertIn("to authenticated", self.lower)
        self.assertIn("has_function_privilege('public'", self.lower)
        self.assertIn("has_function_privilege('anon'", self.lower)
        self.assertIn("has_function_privilege('service_role'", self.lower)
        self.assertIn("has_function_privilege('pdc_email_monitor'", self.lower)
        self.assertIn("notify pgrst", self.lower)

    def test_all_hermes_test_probe_routines_are_removed_before_commit(self):
        self.assertIn('drop function public."reconcile_navision_delivery_700"(uuid)', self.lower)
        self.assertIn("drop function public.reconcile_navision_delivery_700(uuid,text)", self.lower)
        self.assertIn("drop schema pdc_hermes_security_probe_714 cascade", self.lower)


if __name__ == "__main__":
    unittest.main()
