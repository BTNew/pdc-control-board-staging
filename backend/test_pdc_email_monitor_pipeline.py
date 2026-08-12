import copy
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from backend.pdc_communication_runtime_client import PROCESS_COMMUNICATION_RPC
from backend import pdc_email_monitor_pipeline as pipeline
from backend.pdc_email_monitor_pipeline import execute_retained_intake
from backend.pdc_jobcard_runtime_client import ATTEST_RPC, PROCESS_RPC, RuntimeContractError, STAGING_URL

H = "a" * 64
D = "b" * 64
A = "11111111-1111-4111-8111-111111111111"
I = "22222222-2222-4222-8222-222222222222"
R = "33333333-3333-4333-8333-333333333333"
V = "44444444-4444-4444-8444-444444444444"
O = "55555555-5555-4555-8555-555555555555"
L = "66666666-6666-4666-8666-666666666666"
AUTH = {"dkim_aligned": True, "dmarc_aligned": True, "gmail_authentication_results": True, "sender_domain": "example.com", "spf_aligned": True}


def base(kind):
    return {
        "intake_id": I, "expected_source_hash": H, "kind": kind,
        "provider": {"attachment_id": A, "attachment_source_hash": D, "provider_message_id": "<m@example.com>", "provider_authserv_id": "mx.google.com", "authentication": copy.deepcopy(AUTH)},
    }


def jobcard_extraction():
    auth = copy.deepcopy(AUTH)
    return {
        "authentication": auth, "canonical_attachment_id": A, "canonical_document_hash": D,
        "contract_version": "pmb-email-work-v2",
        "email_vehicle": {
            "cancelled": False, "conflicts": [], "customer_name": None, "eta_to_kewdale": None,
            "job_card_number": "J1", "registration": None, "stock_numbers": ["12657478"],
            "toyota_order_number": None, "vehicle_description": None, "vins": [],
        },
        "operation_lines": [{"source_row_no": 1, "operation_no": "OP1", "work_key": "fitting", "description": "Fit accessory", "estimated_hours": 1.0}],
        "required_work": ["fitting"],
    }


class Client:
    def __init__(self, authority, apikey, bearer, calls):
        self.authority, self.apikey, self.bearer, self.calls = authority, apikey, bearer, calls
        self.url = STAGING_URL

    def rpc(self, name, payload):
        self.calls.append((self.authority, name, payload))
        if name == ATTEST_RPC:
            return {"ok": True, "code": "provider_observation_attested", "data": {"observation_id": O, "request_sha256": H}}
        if name == PROCESS_RPC:
            return {"ok": True, "code": "jobcard_attachment_receipt", "data": {
                "receipt_id": R, "intake_id": I, "attachment_id": A,
                "parent_source_hash": H, "attachment_source_hash": D,
                "attachment_size_bytes": 123, "attachment_content_type": "application/pdf",
                "source_uid": "source-1", "proposal_id": "77777777-7777-4777-8777-777777777777",
                "canonical_import_receipt_id": "88888888-8888-4888-8888-888888888888",
                "vehicle_id": V, "vehicle_version": 1,
                "backend_record_id": "99999999-9999-4999-8999-999999999999", "backend_record_version": 1,
                "job_card_number": "J1", "requested_payload_sha256": H, "operation_sha256": D,
                "operation_count": 1, "estimated_hours_sum": 1.0,
                "operation_lines": [{"source_row_no": 1, "operation_no": "OP1", "operation_line_id": L,
                    "work_key": "fitting", "description": "Fit accessory", "estimated_hours": 1.0,
                    "estimated_hours_source": "job_card"}],
                "canonical_operation_line_ids": [L], "canonical_import_response": {
                    "observation": {}, "vehicle_import": {}, "operation_import": {},
                    "booking_created": False, "completion_created": False, "location_scheduled": False},
                "booking_created": False, "completion_created": False, "location_scheduled": False}}
        if name == PROCESS_COMMUNICATION_RPC:
            action = payload["p_extraction"]["actions"][0]
            retained_clause = " ".join(action["evidence"].split()).strip(" .,;:-").lower()
            return {"ok": True, "code": "communication_receipt", "data": {
                "receipt_id": R, "intake_id": I, "attachment_id": A, "vehicle_id": V,
                "action_count": 1, "actions": [{"source_action_no": 1, "action_type": action["action_type"], "evidence": action["evidence"],
                    "retained_clause": retained_clause, "retained_clause_sha256": hashlib.sha256(retained_clause.encode("utf-8")).hexdigest(),
                    "requested_action": action, "before_data": None, "after_data": {}}],
                "booking_created": False, "location_changed": False,
            }}
        raise AssertionError(f"unexpected RPC {name}")


class PipelineTests(unittest.TestCase):
    def clients(self):
        calls = []
        return Client("service_role", "service-secret", "service-secret", calls), Client("authenticated_monitor", "anon-public", "actor-token", calls), calls

    def test_parts_communication_dispatches_two_authority_action(self):
        service, actor, calls = self.clients(); item = base("communication"); item["retained_text"] = "Stock 12657478. Parts Complete."
        result = execute_retained_intake(service, actor, item)
        self.assertTrue(result["ok"]); self.assertEqual([row[1] for row in calls], [ATTEST_RPC, PROCESS_COMMUNICATION_RPC])

    def test_uncertain_language_is_review_only_with_zero_rpc(self):
        for text in (
            "Please sort this out.", "Stock 12657478. Sublet booked tomorrow.",
            "Stock 12657478. Could you add UHF to this job?",
        ):
            service, actor, calls = self.clients(); item = base("communication"); item["retained_text"] = text
            result = execute_retained_intake(service, actor, item)
            self.assertEqual(result["phase"], "review_required"); self.assertFalse(result["mutation_attempted"]); self.assertEqual(calls, [])

    def test_conditional_and_future_phrases_require_review_before_any_rpc(self):
        for text in (
            "Stock 12657478. Parts complete subject to approval.",
            "Stock 12657478. Parts complete later today.",
            "Stock 12657478. Sublet booked 14/08/2026 upon manager sign-off.",
            "Stock 12657478. Add UHF to this vehicle this afternoon.",
        ):
            with self.subTest(text=text):
                service, actor, calls = self.clients(); item = base("communication"); item["retained_text"] = text
                result = execute_retained_intake(service, actor, item)
                self.assertEqual(result["phase"], "review_required")
                self.assertFalse(result["mutation_attempted"])
                self.assertFalse(result["message_sent"])
                self.assertEqual(calls, [])

    def test_non_string_retained_text_is_rejected_with_zero_rpc(self):
        for value in (None, 0, ["Stock 12657478. Parts complete."], {"text": "Parts complete"}):
            service, actor, calls = self.clients(); item = base("communication"); item["retained_text"] = value
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeContractError, "retained_text"):
                execute_retained_intake(service, actor, item)
            self.assertEqual(calls, [])

    def test_jobcard_uses_existing_canonical_path(self):
        service, actor, calls = self.clients(); item = base("jobcard"); item["extraction"] = jobcard_extraction()
        # Provider and extraction authentication must be byte-for-byte equal.
        item["extraction"]["authentication"] = item["provider"]["authentication"]
        result = execute_retained_intake(service, actor, item)
        self.assertTrue(result["ok"]); self.assertEqual([row[1] for row in calls], [ATTEST_RPC, PROCESS_RPC])

    def test_one_shot_cli_uses_profile_owned_file_and_sanitized_output(self):
        with tempfile.TemporaryDirectory() as directory:
            request_path = Path(directory) / "retained.json"
            request_path.write_text(json.dumps(base("communication") | {"retained_text": "Stock 12657478. Parts Complete."}), encoding="utf-8")
            output = io.StringIO()
            with patch.object(sys, "argv", ["pdc_email_monitor_pipeline", "--request", str(request_path)]), \
                 patch.object(pipeline, "clients_from_environment", return_value=(object(), object())), \
                 patch.object(pipeline, "execute_retained_intake", return_value={"ok": True, "phase": "complete", "code": "communication_receipt"}), \
                 patch("sys.stdout", output):
                self.assertEqual(pipeline.main(), 0)
            self.assertEqual(json.loads(output.getvalue()), {"ok": True, "phase": "complete", "code": "communication_receipt"})

    def test_one_shot_cli_invalid_json_is_fail_closed_and_sanitized(self):
        with tempfile.TemporaryDirectory() as directory:
            request_path = Path(directory) / "retained.json"
            request_path.write_text("{not-json", encoding="utf-8")
            output = io.StringIO()
            with patch.object(sys, "argv", ["pdc_email_monitor_pipeline", "--request", str(request_path)]), patch("sys.stdout", output):
                self.assertEqual(pipeline.main(), 1)
            self.assertEqual(json.loads(output.getvalue()), {"ok": False, "phase": "preflight", "code": "request_json_invalid", "mutation_attempted": False})


if __name__ == "__main__":
    unittest.main()
