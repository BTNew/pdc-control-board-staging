import unittest

from backend.pdc_communication_runtime_client import (
    PROCESS_COMMUNICATION_RPC,
    execute_communication_request,
    validate_communication_request,
)
from backend.pdc_jobcard_runtime_client import ATTEST_RPC, RuntimeContractError

HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
ATTACHMENT_ID = "11111111-1111-4111-8111-111111111111"


def fixture(action=None):
    auth = {"dkim_aligned": True, "dmarc_aligned": True, "gmail_authentication_results": True, "sender_domain": "example.com", "spf_aligned": True}
    action = action or {"source_action_no": 1, "action_type": "parts_complete", "evidence": "Parts complete"}
    return {
        "intake_id": "22222222-2222-4222-8222-222222222222",
        "expected_source_hash": HASH_A,
        "extraction_hash": HASH_C,
        "provider": {"attachment_id": ATTACHMENT_ID, "provider_message_id": "<m@example.com>", "provider_authserv_id": "mx.google.com", "authentication": auth},
        "extraction": {
            "actions": [action], "authentication": auth, "auto_applicable": True,
            "canonical_attachment_id": ATTACHMENT_ID, "canonical_document_hash": HASH_B,
            "contract_version": "pmb-email-communications-v1",
            "identity": {"job_card_numbers": [], "stock_numbers": ["12657478"], "vins": []},
            "review_reasons": [],
        },
    }


class FakeClient:
    def __init__(self, authority, bearer, replies, calls):
        self.authority, self.bearer, self.replies, self.calls = authority, bearer, list(replies), calls

    def rpc(self, name, payload):
        self.calls.append((self.authority, name, payload))
        return self.replies.pop(0)


class CommunicationRuntimeClientTests(unittest.TestCase):
    def test_attests_then_processes_with_separate_authorities(self):
        calls = []
        service = FakeClient("service_role", "service", [{"ok": True, "code": "provider_observation_attested"}], calls)
        actor = FakeClient("authenticated_monitor", "actor", [{"ok": True, "code": "communication_applied", "data": {"receipt_id": "r", "vehicle_id": "v", "action_count": 1}}], calls)
        result = execute_communication_request(service, actor, fixture())
        self.assertTrue(result["ok"])
        self.assertEqual([(a, n) for a, n, _ in calls], [("service_role", ATTEST_RPC), ("authenticated_monitor", PROCESS_COMMUNICATION_RPC)])
        self.assertEqual(result["action_count"], 1)

    def test_review_only_request_never_calls_network(self):
        request = fixture()
        request["extraction"]["auto_applicable"] = False
        request["extraction"]["review_reasons"] = ["vehicle_identity_ambiguous"]
        with self.assertRaisesRegex(RuntimeContractError, "review-only"):
            validate_communication_request(request)

    def test_accessory_requires_approved_work_key(self):
        action = {"source_action_no": 1, "action_type": "add_accessory_work", "description": "Mystery", "work_key": "mystery", "evidence": "Add mystery"}
        with self.assertRaisesRegex(RuntimeContractError, "not approved"):
            validate_communication_request(fixture(action))

    def test_sublet_requires_exact_shape(self):
        action = {"source_action_no": 1, "action_type": "set_sublet_booking_date", "evidence": "Sublet booked"}
        with self.assertRaisesRegex(RuntimeContractError, "keys"):
            validate_communication_request(fixture(action))

    def test_attestation_failure_stops_processing(self):
        calls = []
        service = FakeClient("service_role", "service", [{"ok": False, "code": "binding_mismatch"}], calls)
        actor = FakeClient("authenticated_monitor", "actor", [], calls)
        result = execute_communication_request(service, actor, fixture())
        self.assertFalse(result["ok"])
        self.assertEqual(len(calls), 1)

    def test_shared_credential_rejected(self):
        calls = []
        with self.assertRaisesRegex(RuntimeContractError, "credentials must differ"):
            execute_communication_request(FakeClient("service_role", "same", [], calls), FakeClient("authenticated_monitor", "same", [], calls), fixture())
        self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
