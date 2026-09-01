from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
REVIEWER_PATH = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/scripts/pdc_email_reviewer.py")
MANIFEST = Path(r"C:/Users/nwmgr/HermesWorkspaces/pdc-monitor/latest100-resume-manifest.json")
spec = importlib.util.spec_from_file_location("pdc_email_reviewer_resume_contract", REVIEWER_PATH)
reviewer = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(reviewer)


class PdcLatest100ResumeContractTests(unittest.TestCase):
    def test_manifest_preserves_exact_scoped_uid_and_source_hash_coverage(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        messages = data["messages"]
        self.assertEqual(data["uidvalidity"], 1)
        self.assertEqual(len(messages), 100)
        self.assertEqual(len({row["scoped_uid"] for row in messages}), 100)
        self.assertEqual(sum(row["new_build_candidate"] for row in messages), 42)
        for row in messages:
            self.assertRegex(row["scoped_uid"], r"^1:[1-9][0-9]*$")
            self.assertRegex(row["source_hash"], r"^[a-f0-9]{64}$")

    def test_exact_replay_requires_expected_hash_argument(self):
        args = reviewer.build_parser().parse_args([
            "poll", "--replay-scoped-uid", "1:597",
            "--expected-source-hash", "a" * 64,
        ])
        self.assertEqual(args.replay_scoped_uid, "1:597")
        self.assertEqual(args.expected_source_hash, "a" * 64)
        self.assertIn("exact retained replay requires its expected source hash", REVIEWER_PATH.read_text(encoding="utf-8"))
        self.assertIn("exact retained replay source hash mismatch", REVIEWER_PATH.read_text(encoding="utf-8"))

    def test_resume_contract_keeps_mutations_staging_only(self):
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
        self.assertTrue(data["resume_contract"]["exact_uid_required"])
        self.assertTrue(data["resume_contract"]["expected_source_hash_required"])
        self.assertFalse(data["resume_contract"]["mailbox_mutation_allowed"])
        self.assertFalse(data["resume_contract"]["production_writes"])
        self.assertFalse(data["resume_contract"]["outbound_email"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
