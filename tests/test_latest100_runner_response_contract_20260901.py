from __future__ import annotations
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

REVIEWER = Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/scripts/pdc_email_reviewer.py")
spec = importlib.util.spec_from_file_location("pdc_email_reviewer_latest100_runner_contract", REVIEWER)
reviewer = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(reviewer)


class Latest100RunnerResponseContractTests(unittest.TestCase):
    def test_typed_source_reuse_conflict_bridges_to_attachment_work_successor(self):
        binding = {
            "intake_id": "11111111-1111-4111-8111-111111111111",
            "attachment_id": "22222222-2222-4222-8222-222222222222",
            "parent_source_hash": "a" * 64,
            "attachment_source_hash": "b" * 64,
            "extraction_hash": "c" * 64,
            "extraction": {"authentication": {}, "email_vehicle": {}, "required_work": [], "operation_lines": []},
        }
        payload = {"p_attachment_index": 3}
        fallback = {
            "ok": True,
            "code": "work_receipt_duplicate_zero_add",
            "data": {
                "receipt_id": "33333333-3333-4333-8333-333333333333",
                "intake_id": binding["intake_id"],
                "attachment_id": binding["attachment_id"],
                "parent_source_hash": binding["parent_source_hash"],
                "attachment_source_hash": binding["attachment_source_hash"],
                "extraction_hash": binding["extraction_hash"],
            },
        }
        with mock.patch.object(reviewer, "rpc", side_effect=[
            {"ok": False, "code": "source_reuse_conflict", "data": {}},
            fallback,
        ]) as call:
            result = reviewer._process_bound_attachment(None, {}, "1:680", ("url", "key", "token"), payload, binding)
        self.assertEqual(result, fallback)
        self.assertEqual(call.call_args_list[1].args[3], "process_email_intake_work")

    def test_direct_canonical_reader_envelope_is_validated_before_success(self):
        source = REVIEWER.read_text(encoding="utf-8")
        self.assertIn('response.get("code") == "jobcard_attachment_receipt"', source)
        self.assertIn("_validate_attachment_receipt_readback", source)
        self.assertIn("source_reuse_conflict", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
