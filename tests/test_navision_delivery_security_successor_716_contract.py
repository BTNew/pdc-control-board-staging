from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260828040000_716_close_all_raw_navision_acl_grantees.sql"


class NavisionDelivery716ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_exact_candidate_source_hash_and_715_head_guards_are_append_only(self):
        for marker in (
            "5d60baa07f32d696e3d494fad8be00dcb579fff4",
            "45932e116e25d06f64f7df8c265bf43f223b671d",
            "1df478da87e0c5ddb3735ce5489246251f91fc877ebc7700403630e62fca461d",
            "20260828030000",
            "715_remove_leaked_navision_714_test_probes",
            "pdc_716_exact_live_head_required",
            "pdc_716_preserved_700_715_chain_required",
            "pdc_716_canonical_function_hash_mismatch",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("truncate", self.lower)
        self.assertIn("lock table supabase_migrations.schema_migrations in exclusive mode", self.lower)

    def test_all_non_system_case_insensitive_family_routines_and_raw_acl_entries_are_inventoried(self):
        for marker in (
            "pg_proc",
            "pg_namespace",
            "pdc_716_targets",
            "pdc_navision_raw_acl_inventory_716",
            "n.nspname !~ '^pg_'",
            "information_schema",
            "lower(p.proname)",
            "pg_get_function_identity_arguments",
            "proargdefaults",
            "proconfig",
            "aclexplode",
            "raw_acl",
            "acl_grantor",
            "acl_grantee",
            "privilege_type",
            "is_grantable",
        ):
            self.assertIn(marker.lower(), self.lower)
        for family in (
            "reconcile_navision_delivery_700%",
            "reconcile_navision_operational_record%",
            "process_pdc_monitor_body_location_20260821033000%",
        ):
            self.assertIn(family, self.lower)

    def test_dynamic_revoke_removes_every_explicit_grantee_and_grant_option(self):
        for marker in (
            "revoke all on routine %s from public",
            "revoke all on routine %s from %i",
            "x.grantee<>p.proowner",
            "pg_get_userbyid(x.grantee)",
            "alter routine %s owner to postgres",
            "grant execute on routine",
            "with grant option",
            "pdc_716_unknown_raw_acl_grantee",
            "pdc_716_unknown_or_grantable_raw_acl_entry",
            "pdc_716_arbitrary_role_execute_survived",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_canonical_acl_and_metadata_are_exact_and_historical_members_closed(self):
        for marker in (
            "grant execute on function public.reconcile_navision_delivery_700(uuid) to authenticated",
            "grant execute on function public.reconcile_navision_operational_record(uuid,uuid,text) to authenticated",
            "grant execute on function public.process_pdc_monitor_body_location_20260821033000(uuid,uuid,text,uuid,integer,integer,text,text,date,timestamptz,text) to authenticated",
            "acl_grantee_name not in ('postgres','authenticated')",
            "acl_grantee_name<>'postgres'",
            "pdc_716_raw_acl_normalization_failed",
            "pdc_716_raw_acl_cardinality_failed",
            "pdc_716_canonical_schema_default_config_owner_drift",
            "pdc_716_alternate_mixed_case_overload_default_closed_failed",
            "search_path=pg_catalog, public, auth, extensions",
            "search_path=pg_catalog, public, extensions, auth",
            "statement_timeout=120s",
            "has_defaults",
            "owner_name<>'postgres'",
            "not security_definer",
            "volatility<>'v'",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_quoted_hostile_role_is_transaction_contained_and_cleaned(self):
        for marker in (
            'create role "hermes-test-716-acl"',
            '"hermes-test-716-acl" with grant option',
            "pdc_716_hostile_raw_grant_not_captured",
            "pdc_716_hostile_noncanonical_target_missing",
            'drop role "hermes-test-716-acl"',
            "pdc_716_hostile_role_residue",
            "pre",
            "post",
            "no vehicle or user-data mutation",
        ):
            self.assertIn(marker.lower(), self.lower)

    def test_migration_ledger_and_schema_reload_are_present(self):
        self.assertIn("20260828040000", self.lower)
        self.assertIn("716_close_all_raw_navision_acl_grantees", self.lower)
        self.assertIn("notify pgrst", self.lower)


if __name__ == "__main__":
    unittest.main(verbosity=2)
