from __future__ import annotations

import json
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from inspect_pdc14_staging import STAGING_REF, management_query
from apply_pdc14_staging import management_write

RUN_LIVE = os.environ.get("PDC_RUN_PROVENANCE_RELEASE_LIVE") == "1"
EXPECTED_REF = "cdsmnqxtyyoeoznmbidd"
ACTOR_ID = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
ACTOR_EMAIL = "sales@broometoyota.com.au"
TARGET = "e49685ca-c9b7-448d-9b45-1aba97d6d3b4"
MISSING = "00000000-0000-4000-8000-000000000001"


def claims_sql(sub: str | None, email: str = "", role: str = "authenticated") -> str:
    claims = {} if sub is None else {"sub": sub, "email": email, "role": role}
    encoded = json.dumps(claims, separators=(",", ":")).replace("'", "''")
    return f"select set_config('request.jwt.claims','{encoded}',true);"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_PROVENANCE_RELEASE_LIVE=1 for authorised STAGING read-only regression")
class ProvenanceHistoryReleaseLiveTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assertEqual(STAGING_REF, EXPECTED_REF)

    @staticmethod
    def role_fixture(where: str) -> tuple[str, str]:
        row = management_query(
            "select coalesce(auth_user_id::text,'00000000-0000-4000-8000-000000000003') sub, "
            "lower(email) email from public.pdc_user_roles "
            f"where {where} order by id limit 1"
        )[0]
        return row["sub"], row["email"]

    def call(self, vehicle_id: str, *, sub: str | None = ACTOR_ID, email: str = ACTOR_EMAIL):
        rows = management_write(
            "begin;"
            + claims_sql(sub, email)
            + f"select public.get_pdc_vehicle_provenance_history('{vehicle_id}'::uuid) result;"
            + "rollback;"
        )
        return next(row["result"] for row in rows if "result" in row)

    def test_approved_importer_reads_canonical_target_history(self):
        result = self.call(TARGET)
        self.assertTrue(result.get("ok"), result)
        self.assertEqual(result.get("data", {}).get("vehicle", {}).get("vehicle_id"), TARGET)
        self.assertIsInstance(result.get("data", {}).get("email_imports"), list)
        self.assertIsInstance(result.get("data", {}).get("navision_imports"), list)
        self.assertIsInstance(result.get("data", {}).get("movements"), list)
        self.assertIsInstance(result.get("data", {}).get("audit_events"), list)
        self.assertIn("lifecycle_history", result.get("data", {}))

    def test_unauthenticated_and_invalid_target_fail_closed(self):
        unauthorized = self.call(TARGET, sub=None)
        self.assertEqual((unauthorized.get("ok"), unauthorized.get("code")), (False, "unauthorized"))
        self.assertNotIn("data", unauthorized)
        missing = self.call(MISSING)
        self.assertEqual((missing.get("ok"), missing.get("code")), (False, "vehicle_not_found"))
        self.assertNotIn("data", missing)

    def test_unapproved_and_mismatched_identities_return_no_history(self):
        no_role = self.call(TARGET, sub="00000000-0000-4000-8000-000000000002", email="no-role@example.invalid")
        inactive_sub, inactive_email = self.role_fixture("not active and account_status = 'disabled'")
        inactive = self.call(TARGET, sub=inactive_sub, email=inactive_email)
        pending_sub, pending_email = self.role_fixture("account_status = 'pending'")
        pending = self.call(TARGET, sub=pending_sub, email=pending_email)
        mismatch = self.call(TARGET, email="uuid-email-mismatch@example.invalid")
        for result in (no_role, inactive, pending, mismatch):
            self.assertEqual((result.get("ok"), result.get("code")), (False, "forbidden"), result)
            self.assertNotIn("data", result, result)

    def test_denied_dealer_scope_returns_no_history(self):
        scoped_sub, scoped_email = self.role_fixture(
            "active and account_status = 'approved' and exists ("
            "select 1 from public.pdc_auditor_user_dealer_scopes s "
            "where s.auth_user_id=pdc_user_roles.auth_user_id "
            "and s.normalized_email=lower(pdc_user_roles.email) "
            "and s.environment='staging' and s.active and s.dealer_code='14450')"
        )
        denied = self.call(TARGET, sub=scoped_sub, email=scoped_email)
        self.assertEqual((denied.get("ok"), denied.get("code")), (False, "dealer_scope_denied"), denied)
        self.assertNotIn("data", denied, denied)

    def test_catalog_exposes_only_canonical_one_argument_rpc(self):
        row = management_query(
            "select jsonb_build_object("
            "'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),"
            "'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null,"
            "'one_arg',to_regprocedure('public.get_pdc_vehicle_provenance_history(uuid)') is not null,"
            "'two_arg',to_regprocedure('public.get_pdc_vehicle_provenance_history(uuid,text)') is not null,"
            "'authenticated_execute',has_function_privilege('authenticated','public.get_pdc_vehicle_provenance_history(uuid)','execute'),"
            "'anon_execute',has_function_privilege('anon','public.get_pdc_vehicle_provenance_history(uuid)','execute'),"
            "'service_execute',has_function_privilege('service_role','public.get_pdc_vehicle_provenance_history(uuid)','execute')) result"
        )[0]["result"]
        self.assertEqual(
            row,
            {
                "project_ref": EXPECTED_REF,
                "production_sentinel": False,
                "one_arg": True,
                "two_arg": False,
                "authenticated_execute": True,
                "anon_execute": False,
                "service_execute": False,
            },
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
