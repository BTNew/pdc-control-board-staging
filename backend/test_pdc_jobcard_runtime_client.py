import json
import unittest
from unittest.mock import patch

try:
    from backend.pdc_jobcard_runtime_client import (
        ATTEST_RPC,
        PROCESS_RPC,
        RpcClient,
        RuntimeContractError,
        execute_jobcard_request,
        validate_request,
    )
except ModuleNotFoundError:
    from pdc_jobcard_runtime_client import (
        ATTEST_RPC,
        PROCESS_RPC,
        RpcClient,
        RuntimeContractError,
        execute_jobcard_request,
        validate_request,
    )


HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
ATTACHMENT_ID = "11111111-1111-4111-8111-111111111111"
INTAKE_ID = "22222222-2222-4222-8222-222222222222"


def request_fixture():
    authentication = {
        "dkim_aligned": True,
        "dmarc_aligned": True,
        "gmail_authentication_results": True,
        "sender_domain": "example.com",
        "spf_aligned": True,
    }
    return {
        "intake_id": INTAKE_ID,
        "expected_source_hash": HASH_A,
        "extraction_hash": HASH_C,
        "provider": {
            "attachment_id": ATTACHMENT_ID,
            "provider_message_id": "<message@example.com>",
            "provider_authserv_id": "mx.google.com",
            "authentication": authentication,
        },
        "extraction": {
            "authentication": authentication,
            "canonical_attachment_id": ATTACHMENT_ID,
            "canonical_document_hash": HASH_B,
            "contract_version": "pmb-email-work-v2",
            "email_vehicle": {"stock_number": "SYNTHETIC-1", "job_card_number": "JC-SYNTHETIC-1"},
            "operation_lines": [{
                "source_row_no": 1,
                "operation_no": "OP1",
                "work_key": "FITTING",
                "description": "Synthetic fitting operation",
                "estimated_hours": "1.50",
            }],
            "required_work": ["FITTING"],
        },
    }


class FakeClient:
    def __init__(self, authority, bearer, replies, calls):
        self.authority = authority
        self.bearer = bearer
        self.replies = list(replies)
        self.calls = calls

    def rpc(self, name, payload):
        self.calls.append((self.authority, name, payload))
        return self.replies.pop(0)


class RuntimeClientTests(unittest.TestCase):
    def test_service_role_attests_then_authenticated_monitor_processes(self):
        calls = []
        service = FakeClient("service_role", "service-secret", [
            {"ok": True, "code": "provider_observation_attested", "data": {"observation_id": "x"}}
        ], calls)
        actor = FakeClient("authenticated_monitor", "actor-jwt", [
            {"ok": True, "code": "jobcard_attachment_receipt", "data": {
                "receipt_id": "receipt-1", "vehicle_id": "vehicle-1",
                "operation_count": 1, "estimated_hours_sum": 1.5,
            }}
        ], calls)
        result = execute_jobcard_request(service, actor, request_fixture())
        self.assertTrue(result["ok"])
        self.assertEqual(
            [(authority, name) for authority, name, _ in calls],
            [("service_role", ATTEST_RPC), ("authenticated_monitor", PROCESS_RPC)],
        )
        self.assertEqual(calls[0][2]["p_authentication"], request_fixture()["provider"]["authentication"])
        self.assertEqual(calls[1][2]["p_actor"], "pdc-monitor")
        self.assertEqual(result["operation_count"], 1)

    def test_exact_attestation_replay_is_accepted(self):
        calls = []
        service = FakeClient("service_role", "service-secret", [
            {"ok": True, "code": "provider_observation_already_attested"}
        ], calls)
        actor = FakeClient("authenticated_monitor", "actor-jwt", [
            {"ok": True, "code": "jobcard_attachment_receipt", "data": {"operation_count": 1}}
        ], calls)
        self.assertTrue(execute_jobcard_request(service, actor, request_fixture())["ok"])
        self.assertEqual(len(calls), 2)

    def test_attestation_failure_stops_before_operational_processing(self):
        calls = []
        service = FakeClient("service_role", "service-secret", [
            {"ok": False, "code": "provider_observation_binding_mismatch"}
        ], calls)
        actor = FakeClient("authenticated_monitor", "actor-jwt", [], calls)
        result = execute_jobcard_request(service, actor, request_fixture())
        self.assertFalse(result["ok"])
        self.assertEqual(result["phase"], "provider_attestation")
        self.assertEqual(len(calls), 1)

    def test_shared_credential_is_rejected_before_any_rpc(self):
        calls = []
        service = FakeClient("service_role", "same", [], calls)
        actor = FakeClient("authenticated_monitor", "same", [], calls)
        with self.assertRaisesRegex(RuntimeContractError, "credentials must differ"):
            execute_jobcard_request(service, actor, request_fixture())
        self.assertEqual(calls, [])

    def test_importer_cannot_be_substituted_for_attestation_authority(self):
        calls = []
        wrong = FakeClient("authenticated_monitor", "actor-jwt", [], calls)
        actor = FakeClient("authenticated_monitor", "actor-jwt-2", [], calls)
        with self.assertRaisesRegex(RuntimeContractError, "authorities are not separated"):
            execute_jobcard_request(wrong, actor, request_fixture())
        self.assertEqual(calls, [])

    def test_authentication_or_attachment_drift_is_rejected_before_network(self):
        changed = request_fixture()
        changed["extraction"]["authentication"] = dict(changed["extraction"]["authentication"])
        changed["extraction"]["authentication"]["spf_aligned"] = False
        with self.assertRaisesRegex(RuntimeContractError, "authentication evidence differ"):
            validate_request(changed)
        changed = request_fixture()
        changed["extraction"]["canonical_attachment_id"] = "33333333-3333-4333-8333-333333333333"
        with self.assertRaisesRegex(RuntimeContractError, "attachment identities differ"):
            validate_request(changed)

    def test_rpc_client_uses_distinct_apikey_and_bearer_headers(self):
        response = type("Response", (), {
            "__enter__": lambda self: self,
            "__exit__": lambda self, *args: None,
            "read": lambda self: json.dumps({"ok": True, "code": "x"}).encode(),
        })()
        captured = {}

        def fake_urlopen(request, timeout):
            captured["request"] = request
            captured["timeout"] = timeout
            return response

        client = RpcClient("https://example.supabase.co", "anon-key", "actor-jwt", "authenticated_monitor")
        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.rpc("some_rpc", {"x": 1})
        headers = {key.lower(): value for key, value in captured["request"].header_items()}
        self.assertEqual(headers["apikey"], "anon-key")
        self.assertEqual(headers["authorization"], "Bearer actor-jwt")
        self.assertNotIn("actor-jwt", captured["request"].data.decode())


if __name__ == "__main__":
    unittest.main()
