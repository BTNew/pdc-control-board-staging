from __future__ import annotations

import json
import os
import sys
import unittest

RUN_LIVE = os.environ.get("PDC_RUN_504_LIVE_TESTS") == "1"
if RUN_LIVE:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "_staging_test_tools"))
    from staging_rest import rest_select, rpc, sign_in  # noqa: E402


ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE = "pdc-monitor-staging-m502-2026.08.44"
SOURCE = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
MANIFEST = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
ARCHIVE = "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_504_LIVE_TESTS=1 for the authorised staging integration test")
class MonitorSuccessor504LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        status, body = sign_in(
            os.environ["PDC_STAGING_ADMIN_EMAIL"],
            os.environ["PDC_STAGING_ADMIN_PASSWORD"],
        )
        if status != 200:
            raise unittest.SkipTest(f"staging administrator sign-in unavailable: HTTP {status}")
        cls.token = body["access_token"]

    @staticmethod
    def reconcile_params():
        return {
            "p_monitor_user_id": ACTOR,
            "p_gateway_instance_id": GATEWAY,
            "p_release_name": RELEASE,
            "p_source_sha": SOURCE,
            "p_manifest_sha256": MANIFEST,
            "p_archive_sha256": ARCHIVE,
        }

    def test_exact_transition_is_idempotent_and_fail_closed(self):
        status, first = rpc(self.token, "reconcile_pdc_monitor_contained_binding_504", self.reconcile_params())
        self.assertEqual(status, 200, first)
        self.assertTrue(first["ok"])
        self.assertFalse(first["idempotent"])
        for field in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertFalse(first[field])

        status, replay = rpc(self.token, "reconcile_pdc_monitor_contained_binding_504", self.reconcile_params())
        self.assertEqual(status, 200, replay)
        self.assertTrue(replay["ok"])
        self.assertTrue(replay["idempotent"])
        self.assertEqual(replay["reconciliation_id"], first["reconciliation_id"])

        status, bad = rpc(self.token, "verify_pdc_monitor_contained_binding_504", {
            "p_gateway_instance_id": GATEWAY,
            "p_release_name": RELEASE,
            "p_source_sha": SOURCE,
            "p_manifest_sha256": MANIFEST,
            "p_archive_sha256": "0" * 64,
        })
        self.assertEqual(status, 200, bad)
        self.assertEqual(bad["code"], "contained_reviewed_pair_mismatch")
        self.assertFalse(bad["ok"])

    def test_private_reconciliation_table_has_no_direct_api_read(self):
        status, body = rest_select(self.token, "pdc_monitor_contained_binding_reconciliations_504")
        self.assertIn(status, (401, 403))
        self.assertIsNotNone(body)

    def test_readback_contract_returns_exact_successor(self):
        status, body = rpc(self.token, "get_pdc_monitor_contained_binding_504", {})
        self.assertEqual(status, 200, body)
        self.assertEqual(body["actor_id"], ACTOR)
        self.assertEqual(body["gateway_instance_id"], GATEWAY)
        self.assertEqual(body["release_name"], RELEASE)
        self.assertEqual(body["source_sha"], SOURCE)
        self.assertEqual(body["manifest_sha256"], MANIFEST)
        self.assertEqual(body["archive_sha256"], ARCHIVE)
        self.assertEqual(body["migration_head"], 503)
        self.assertEqual(body["mode"], "contained")


if __name__ == "__main__":
    unittest.main(verbosity=2)
