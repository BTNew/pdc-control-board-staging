from __future__ import annotations

import os
import json
import urllib.error
import urllib.request
import unittest

RUN_LIVE = os.environ.get("PDC_RUN_505_COMPATIBILITY_LIVE_TESTS") == "1"


PROJECT_URL = os.environ.get("PDC_STAGING_SUPABASE_URL", "").rstrip("/")
ANON_KEY = os.environ.get("PDC_STAGING_ANON_KEY", "")
if RUN_LIVE and ("cdsmnqxtyyoeoznmbidd" not in PROJECT_URL or "vjdtsswhroyguxyfjdkt" in PROJECT_URL):
    raise RuntimeError("Refusing non-staging Supabase endpoint")


def request_json(method, path, *, token=None, body=None):
    request = urllib.request.Request(
        PROJECT_URL + path,
        data=None if body is None else json.dumps(body).encode(),
        method=method,
        headers={
            "Content-Type": "application/json",
            "apikey": ANON_KEY,
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raw = exc.read()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = raw.decode(errors="replace")
        return exc.code, parsed


def sign_in(email, password):
    return request_json("POST", "/auth/v1/token?grant_type=password", body={"email": email, "password": password})


def rpc(token, name, body):
    return request_json("POST", f"/rest/v1/rpc/{name}", token=token, body=body)


def rest_select(token, table):
    return request_json("GET", f"/rest/v1/{table}", token=token)


REC = "0c53cb93-bda2-4d02-90db-4c1b96cc7896"
ACTOR = "df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b"
GATEWAY = "pdc-monitor-staging-sales-uid509-v1"
RELEASE = "pdc-monitor-staging-m502-2026.08.44"
SOURCE = "e850c319989d98b45b95a28aa815d78e2c2e3a4b"
TREE = "8981540501bc629e189c39c9ea8a9adf3165d397"
MANIFEST = "d48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d"
ARCHIVE = "4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90"


@unittest.skipUnless(RUN_LIVE, "set PDC_RUN_505_COMPATIBILITY_LIVE_TESTS=1 for authorised staging integration")
class MonitorCompatibility505LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        status, body = sign_in(
            os.environ["PDC_STAGING_ADMIN_EMAIL"],
            os.environ["PDC_STAGING_ADMIN_PASSWORD"],
        )
        if status != 200:
            raise unittest.SkipTest(f"staging administrator sign-in unavailable: HTTP {status}")
        cls.token = body["access_token"]

    def test_exact_projection_replay_and_compatibility_readback(self):
        status, replay = rpc(self.token, "admin_forward_project_pdc_monitor_contained_binding_505", {"p_reconciliation_id": REC})
        self.assertEqual(status, 200, replay)
        self.assertTrue(replay["ok"])
        self.assertTrue(replay["idempotent"])
        self.assertEqual(replay["reconciliation_id"], REC)
        self.assertEqual(replay["actor_id"], ACTOR)
        self.assertEqual(replay["gateway_instance_id"], GATEWAY)
        self.assertEqual(replay["release_name"], RELEASE)
        self.assertEqual(replay["source_sha"], SOURCE)
        self.assertEqual(replay["source_tree_sha"], TREE)
        self.assertEqual(replay["manifest_sha256"], MANIFEST)
        self.assertEqual(replay["archive_sha256"], ARCHIVE)
        for field in ("operational", "activation_ready", "writer_active", "planner_commissioned", "production_writes"):
            self.assertFalse(replay[field])

        status, readback = rpc(self.token, "verify_pdc_monitor_m503_compatibility_505", {"p_reconciliation_id": REC})
        self.assertEqual(status, 200, readback)
        self.assertTrue(readback["ok"])
        self.assertEqual(readback["history_id"], replay["history_id"])
        self.assertEqual(readback["source_sha"], SOURCE)
        self.assertEqual(readback["manifest_sha256"], MANIFEST)

    def test_wrong_reconciliation_and_private_history_fail_closed(self):
        status, body = rpc(
            self.token,
            "admin_forward_project_pdc_monitor_contained_binding_505",
            {"p_reconciliation_id": "00000000-0000-0000-0000-000000000000"},
        )
        self.assertEqual(status, 500, body)
        self.assertEqual(body.get("message"), "PDC_505_RECONCILIATION_PROOF_REQUIRED")

        status, body = rest_select(self.token, "pdc_monitor_runtime_binding_compatibility_history_505")
        self.assertIn(status, (401, 403))
        self.assertIsNotNone(body)

    def test_unapproved_identity_cannot_project(self):
        status, body = sign_in(
            os.environ["PDC_STAGING_UNAPPROVED_EMAIL"],
            os.environ["PDC_STAGING_UNAPPROVED_PASSWORD"],
        )
        if status != 200:
            raise unittest.SkipTest(f"staging unapproved sign-in unavailable: HTTP {status}")
        status, body = rpc(
            body["access_token"],
            "admin_forward_project_pdc_monitor_contained_binding_505",
            {"p_reconciliation_id": REC},
        )
        self.assertEqual(status, 403, body)
        self.assertEqual(body.get("message"), "PDC_505_ADMIN_AUTHORITY_REQUIRED")


if __name__ == "__main__":
    unittest.main(verbosity=2)
