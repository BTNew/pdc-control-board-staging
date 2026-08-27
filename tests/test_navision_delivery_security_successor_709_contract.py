from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260827113000_709_close_navision_delivery_overloads_and_body_location_bypass.sql"


class NavisionDelivery709ContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.lower = cls.sql.lower()

    def test_is_append_only_guarded_at_actual_live_head(self):
        self.assertIn("20260827112000", self.sql)
        self.assertIn("20260827112000", self.sql)
        self.assertIn("678_uid514_authorize_attachment_count_repair", self.sql)
        self.assertIn("f6219e5bbd833cce6889f44b9e4a04921b9bead9", self.sql)
        self.assertIn("e450854f0f60ad6c8207590bfbfac51759de37f5", self.sql)
        self.assertIn("PDC_709_EXACT_LIVE_HEAD_REQUIRED", self.sql)
        self.assertIn("PDC_709_PREDECESSOR_FUNCTION_HASH_MISMATCH", self.sql)
        self.assertNotIn("drop table", self.lower)
        self.assertNotIn("truncate", self.lower)

    def test_catalog_inventory_covers_pg_proc_namespace_and_postgrest_family(self):
        for marker in (
            "pg_proc",
            "pg_namespace",
            "pg_get_function_identity_arguments",
            "pg_get_function_arguments",
            "pdc_navision_delivery_security_inventory_709",
            "pdc_delivery_completion_path_inventory_709",
            "phase in('pre','post')",
            "reconcile_navision_delivery_700",
            "reconcile_navision_operational_record",
        ):
            self.assertIn(marker.lower(), self.lower)
        self.assertIn("p.proargdefaults is not null", self.lower)
        self.assertIn("p.prokind='f'", self.lower)

    def test_all_family_overloads_are_revoked_then_only_exact_shapes_granted(self):
        self.assertIn("revoke all on function %s from public,anon,authenticated,service_role,pdc_email_monitor", self.lower)
        self.assertIn("rename to reconcile_navision_operational_record_pre709", self.lower)
        self.assertRegex(self.sql, r"CREATE FUNCTION public\.reconcile_navision_operational_record\(\s*p_backend_record_id uuid,\s*p_actor_id uuid,\s*p_actor_email text\s*\)")
        self.assertIn("to_regprocedure('public.reconcile_navision_delivery_700(uuid,uuid,text)') is not null", self.lower)
        self.assertIn("to_regprocedure('public.reconcile_navision_operational_record(uuid)') is not null", self.lower)
        self.assertIn("r.has_defaults", self.lower)
        self.assertIn("PDC_709_UNEXPECTED_OVERLOAD_CALLABLE", self.sql)

    def test_body_location_exact_delivery_has_no_direct_completion_write(self):
        self.assertIn("process_pdc_monitor_body_location_20260821033000_pre709", self.sql)
        self.assertIn("pdc_monitor_authenticated_active_scope_674(btrim(p_gateway_instance_id))", self.sql)
        self.assertIn("reconcile_navision_delivery_700(v_delivery_record_id)", self.sql)
        self.assertIn("delivery_canonical_record_required", self.sql)
        self.assertIn("v_canonical_delivery", self.sql)
        self.assertIn("PDC_709_BODY_LOCATION_REWRITE_POSTCONDITION_FAILED", self.sql)
        self.assertIn("PDC_709_BODY_LOCATION_SECURITY_POSTCONDITION_FAILED", self.sql)
        self.assertIn("update public.vehicles set lifecycle_state='completed'", self.lower)
        self.assertIn("position('update public.vehicles set lifecycle_state=''completed''' in d)>0", self.lower)

    def test_private_legacy_predecessors_and_non_delivery_path_are_preserved(self):
        self.assertIn("revoke all on function public.process_pdc_monitor_body_location_20260821033000_pre709", self.lower)
        self.assertIn("reconcile_navision_operational_record_pre171", self.sql)
        self.assertIn("named_body_or_legacy_169_path", self.sql)
        self.assertIn("exact\n      -- delivery is eligible only", self.lower)
        self.assertIn("non-delivery body-location processing remains unchanged", self.lower)

    def test_no_broadened_roles_and_exact_scope_route(self):
        self.assertIn("grant execute on function public.process_pdc_monitor_body_location_20260821033000", self.lower)
        self.assertIn("to authenticated", self.lower)
        self.assertIn("has_function_privilege('service_role'", self.lower)
        self.assertIn("has_function_privilege('anon'", self.lower)
        self.assertIn("auth.uid()", self.lower)
        self.assertIn("auth.jwt()", self.lower)
        self.assertIn("not coalesce(public.pdc_monitor_authenticated_active_scope_674(null),false)", self.lower)

    def test_append_only_body_repair_successors_have_exact_predecessor_guards(self):
        successors = (
            ("20260827115000_710_body_location_intake_alias_repair.sql", "20260827114000", "679_uid514_recovery_event_key_repair"),
            ("20260827116000_711_body_location_canonical_delivery_eligibility.sql", "20260827115000", "710_body_location_intake_alias_repair"),
            ("20260827117000_712_body_location_collected_visibility_eligibility.sql", "20260827116000", "711_body_location_canonical_delivery_eligibility"),
        )
        for filename, predecessor_version, predecessor_name in successors:
            sql = (ROOT / "supabase/staging_only" / filename).read_text(encoding="utf-8")
            lowered = sql.lower()
            self.assertIn(predecessor_version, sql)
            self.assertIn(predecessor_name, sql)
            self.assertIn("exact_live_head_required", lowered)
            self.assertIn("body_predecessor_hash_mismatch", lowered)
            self.assertNotIn("drop table", lowered)
            self.assertNotIn("truncate", lowered)


if __name__ == "__main__":
    unittest.main()
