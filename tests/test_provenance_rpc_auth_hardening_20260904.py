from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/staging_only/20260904010900_provenance_rpc_auth_hardening.sql"


class ProvenanceRpcAuthorizationHardeningContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.sql = MIGRATION.read_text(encoding="utf-8")
        cls.normalized = " ".join(cls.sql.lower().split())

    def test_successor_is_staging_only_and_append_only(self):
        self.assertIn("cdsmnqxtyyoeoznmbidd", self.sql)
        self.assertNotIn("vjdtsswhroyguxyfjdkt", self.sql)
        self.assertIn("version='20260904010800'", self.normalized)
        self.assertIn("version>'20260904010800'", self.normalized)
        self.assertIn("'20260904010900'", self.sql)
        self.assertNotIn("alter function public.get_pdc_vehicle_provenance_history(uuid) rename", self.normalized)

    def test_lifecycle_role_check_is_null_safe(self):
        self.assertIn(
            "if actor_role is null or actor_role not in('viewer','operator','importer','administrator') then",
            self.normalized,
        )

    def test_wrapper_authenticates_before_fallback_and_preserves_failures(self):
        wrapper_start = self.normalized.index(
            "create or replace function public.get_pdc_vehicle_provenance_history(p_vehicle_id uuid)"
        )
        wrapper = self.normalized[wrapper_start:]
        identity_check = wrapper.index("uid is null or v_actor_email=''")
        approved_role = wrapper.index("r.active and r.account_status='approved'")
        lifecycle_call = wrapper.index("get_pdc_vehicle_lifecycle_history_82000(p_vehicle_id,null)")
        predecessor_call = wrapper.index("get_pdc_vehicle_provenance_history_pre_82000(p_vehicle_id)")
        fallback_guard = wrapper.index("base->>'code' is distinct from 'vehicle_not_found'")
        fallback = wrapper.index("return jsonb_build_object( 'ok',true, 'code','lifecycle_history'")
        self.assertLess(identity_check, approved_role)
        self.assertLess(approved_role, lifecycle_call)
        self.assertLess(lifecycle_call, predecessor_call)
        self.assertLess(predecessor_call, fallback_guard)
        self.assertLess(fallback_guard, fallback)
        self.assertIn("if not coalesce((lifecycle->>'ok')::boolean,false) then return lifecycle", wrapper)
        self.assertIn("then return base", wrapper)

    def test_execute_acl_remains_authenticated_only(self):
        self.assertIn(
            "revoke all on function public.get_pdc_vehicle_provenance_history(uuid) from public,anon,authenticated,service_role",
            self.normalized,
        )
        self.assertIn(
            "grant execute on function public.get_pdc_vehicle_provenance_history(uuid) to authenticated",
            self.normalized,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
