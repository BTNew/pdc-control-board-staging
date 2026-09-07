from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
RUNNER = SCRIPTS / "apply_pilbara_service_open_jobcards_authenticated_staging.py"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("pilbara_authenticated_runner", RUNNER)
assert SPEC is not None and SPEC.loader is not None
runner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(runner)


class PilbaraAuthenticatedRunnerSecurityTests(unittest.TestCase):
    def test_authentication_target_requires_exact_parsed_https_hostname(self) -> None:
        expected = "https://cdsmnqxtyyoeoznmbidd.supabase.co"
        self.assertEqual(runner._validated_staging_base(expected + "/"), expected)
        for unsafe in (
            "http://cdsmnqxtyyoeoznmbidd.supabase.co",
            "https://cdsmnqxtyyoeoznmbidd.supabase.co.evil.example",
            "https://evil.example/cdsmnqxtyyoeoznmbidd.supabase.co",
            "https://user@cdsmnqxtyyoeoznmbidd.supabase.co",
            "https://cdsmnqxtyyoeoznmbidd.supabase.co:444",
            "https://cdsmnqxtyyoeoznmbidd.supabase.co/extra",
        ):
            with self.subTest(url=unsafe), self.assertRaises(RuntimeError):
                runner._validated_staging_base(unsafe)

    def test_authenticated_posts_reject_cross_origin_redirects(self) -> None:
        request = runner.urllib.request.Request(
            "https://cdsmnqxtyyoeoznmbidd.supabase.co/auth/v1/token",
            data=b"{}",
            method="POST",
        )
        handler = runner._StagingRedirectHandler()
        for target in (
            "https://evil.example/auth/v1/token",
            "https://cdsmnqxtyyoeoznmbidd.supabase.co.evil.example/auth/v1/token",
            "http://cdsmnqxtyyoeoznmbidd.supabase.co/auth/v1/token",
        ):
            with self.subTest(target=target), self.assertRaises(RuntimeError):
                handler.redirect_request(request, None, 307, "redirect", {}, target)

        management_handler = runner._ManagementRedirectHandler()
        with self.assertRaises(RuntimeError):
            management_handler.redirect_request(
                request, None, 307, "redirect", {},
                "https://evil.example/v1/projects/test/database/query",
            )

    def test_snapshot_uses_origin_validated_management_query(self) -> None:
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("def _management_query", source)
        self.assertIn("_ManagementRedirectHandler", source)
        self.assertNotIn("from inspect_pdc14_staging import STAGING_REF, management_query", source)

    def test_apply_requires_exact_expected_migration_head(self) -> None:
        valid = {
            "project_ref": "cdsmnqxtyyoeoznmbidd",
            "production_sentinel_present": False,
            "head": ["20260907107000", "pilbara_service_null_safe_head_guard"],
        }
        runner._validate_apply_snapshot(valid)
        for head in (
            ["20260907103000", "pilbara_service_delivery_intercept_gate"],
            ["20260907104000", "wrong_name"],
            ["20260907105000", "wrong_name"],
            ["20260907106000", "later_migration"],
        ):
            with self.subTest(head=head), self.assertRaises(RuntimeError):
                runner._validate_apply_snapshot({**valid, "head": head})
        source = RUNNER.read_text(encoding="utf-8")
        self.assertIn("_validate_apply_snapshot(after_apply)\n        replay_status", source)
        self.assertIn("after_replay = _snapshot()\n        _validate_apply_snapshot(after_replay)", source)

    def test_containment_reports_verified_controls_not_unsupported_contact_claims(self) -> None:
        source = RUNNER.read_text(encoding="utf-8")
        self.assertNotIn('"production_contacted": False', source)
        self.assertNotIn('"staging_only": True', source)
        self.assertNotIn('"outbound_email_sent": False', source)
        self.assertIn('"staging_sentinel_verified": True', source)
        self.assertIn('["migration_head_verified"] = True', source)
        self.assertIn('"authenticated_rest_origin": base', source)
        self.assertIn('"cross_origin_redirects_rejected": True', source)
        self.assertIn('result["containment"]["notification_queue_unchanged"] = checks["notification_queue_unchanged"]', source)
        self.assertIn('"notification_hash"', source)
        self.assertIn('"quarantined_lines"', source)
        self.assertIn('["accepted_operations"] + after_replay["reconciliation"]["quarantined_lines"] == 162', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
