from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MERGE_SHA = "d488f1f18c1058df6d068a467b7347e088e43ef8"


def load(name: str):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))


class FinalEvidenceAcceptanceTests(unittest.TestCase):
    def test_required_deliverables_exist(self):
        required = {
            "detailed-report.md", "executive-summary.md", "sitemap.json",
            "interaction-matrix.csv", "interaction-matrix.json",
            "transaction-ledger.json", "issue-register.json", "fixture-manifest.json",
            "cleanup-verification.json", "console-network-log.json",
            "test-results.json", "deployment-verification.json",
        }
        self.assertEqual([], sorted(name for name in required if not (ROOT / name).is_file()))

    def test_coverage_and_transaction_totals_are_consistent(self):
        sitemap = load("sitemap.json")
        matrix = load("interaction-matrix.json")
        ledger = load("transaction-ledger.json")
        with (ROOT / "interaction-matrix.csv").open(encoding="utf-8", newline="") as stream:
            csv_count = sum(1 for _ in csv.DictReader(stream))
        self.assertEqual(35, len(sitemap["routes"]))
        self.assertEqual(3, len(sitemap["viewports"]))
        self.assertEqual(4358, len(matrix))
        self.assertEqual(4358, csv_count)
        self.assertEqual((26, 26, 0), (len(ledger["assertions"]), ledger["functional_summary"]["passed"], ledger["functional_summary"]["failed"]))

    def test_issue_register_is_deduplicated_and_fully_evidenced(self):
        issues = load("issue-register.json")["issues"]
        self.assertEqual(11, len(issues))
        self.assertEqual(11, len({issue["issue_id"] for issue in issues}))
        self.assertEqual(5, sum(issue["status"] == "resolved" for issue in issues))
        self.assertEqual(6, sum(issue["status"] == "open" for issue in issues))
        for issue in issues:
            self.assertTrue(issue["severity"])
            self.assertTrue(issue["category"])
            self.assertTrue(issue.get("actual") or issue.get("detail"))
            self.assertTrue(issue["evidence"])
            self.assertTrue(all((ROOT / path).exists() for path in issue["evidence"]))

    def test_cleanup_and_protected_controls_are_verified(self):
        cleanup = load("cleanup-verification.json")
        fresh = cleanup["fresh_readback"]
        self.assertEqual(0, fresh["tagged_row_total"])
        self.assertEqual(0, fresh["actor_row_total"])
        self.assertEqual(0, fresh["orphan_vehicle_reference_total"])
        self.assertEqual(2, fresh["database"]["vehicle_count"])
        self.assertTrue(cleanup["invariants"]["protected_controls_exact_identity_state_unchanged"])
        self.assertFalse(cleanup["production_contacted"])
        self.assertFalse(cleanup["email_or_external_commitments_created"])

    def test_final_sha_deployment_migration_and_retests_are_verified(self):
        deployment = load("deployment-verification.json")
        tests = load("test-results.json")
        self.assertEqual(MERGE_SHA, deployment["merge_sha"])
        self.assertEqual(MERGE_SHA, deployment["remote_main"])
        self.assertEqual(MERGE_SHA, deployment["pages"]["headSha"])
        self.assertEqual(MERGE_SHA, deployment["staging_integrity"]["headSha"])
        self.assertTrue(deployment["asset_byte_parity"])
        self.assertTrue(deployment["staging_database"]["ok"])
        self.assertTrue(deployment["staging_database"]["authenticated_probe"]["ok"])
        self.assertEqual(15, deployment["deployed_browser"]["checks"])
        self.assertEqual(189, tests["full_node"]["tests"])
        self.assertEqual(16, tests["focused_python"]["passed"])
        self.assertEqual(456, tests["advisors"]["security"]["levels"]["WARN"])
        self.assertEqual(3, tests["advisors"]["performance"]["levels"]["WARN"])
        self.assertFalse(deployment["production_contacted"])
        self.assertFalse(deployment["production_mutated"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
