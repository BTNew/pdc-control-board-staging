import copy
import json
import unittest
from unittest.mock import patch

from backend.pdc_jobcard_runtime_client import (
    ATTEST_RPC, NON_NAVISION_PROCESS_RPC, PROCESS_RPC, RpcClient, RuntimeContractError,
    STAGING_URL, clients_from_environment, execute_jobcard_request, validate_request,
)

HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
ATTACHMENT_ID = "11111111-1111-4111-8111-111111111111"
INTAKE_ID = "22222222-2222-4222-8222-222222222222"
AUTH = {"dkim_aligned": True, "dmarc_aligned": True, "gmail_authentication_results": True, "sender_domain": "example.com", "spf_aligned": True}
VEHICLE_ID = "33333333-3333-4333-8333-333333333333"
RECEIPT_ID = "44444444-4444-4444-8444-444444444444"
OBSERVATION_ID = "55555555-5555-4555-8555-555555555555"
LINE_ID = "66666666-6666-4666-8666-666666666666"


def request_fixture():
    auth = copy.deepcopy(AUTH)
    return {
        "intake_id": INTAKE_ID, "expected_source_hash": HASH_A, "extraction_hash": HASH_C,
        "provider": {"attachment_id": ATTACHMENT_ID, "provider_message_id": "<message@example.com>", "provider_authserv_id": "mx.google.com", "authentication": auth},
        "extraction": {
            "authentication": auth, "canonical_attachment_id": ATTACHMENT_ID,
            "canonical_document_hash": HASH_B, "contract_version": "pmb-email-work-v2",
            "email_vehicle": {
                "cancelled": False, "conflicts": [], "customer_name": "Synthetic customer",
                "eta_to_kewdale": None, "job_card_number": "JC-SYNTHETIC-1", "registration": None,
                "stock_numbers": ["12657478"], "toyota_order_number": None,
                "vehicle_description": "Toyota synthetic", "vins": [],
            },
            "operation_lines": [{"source_row_no": 1, "operation_no": "OP1", "work_key": "fitting", "description": "Synthetic fitting operation", "estimated_hours": 1.5}],
            "required_work": ["fitting"],
        },
    }


def canonical_data():
    return {"receipt_id": RECEIPT_ID, "vehicle_id": VEHICLE_ID, "operation_count": 1,
            "estimated_hours_sum": 1.5, "operation_lines": [{}], "canonical_operation_line_ids": [LINE_ID],
            "booking_created": False, "completion_created": False, "location_scheduled": False}


def non_navision_data():
    return {"receipt_id": RECEIPT_ID, "vehicle_id": VEHICLE_ID, "operation_count": 1,
            "vehicle_created": True, "operation_lines": [{}], "booking_created": False, "completion_created": False}


def attestation():
    return {"ok": True, "code": "provider_observation_attested", "data": {"observation_id": OBSERVATION_ID, "request_sha256": HASH_A}}


class FakeClient:
    def __init__(self, authority, apikey, bearer, replies, calls, url=STAGING_URL):
        self.authority, self.apikey, self.bearer = authority, apikey, bearer
        self.replies, self.calls, self.url = list(replies), calls, url

    def rpc(self, name, payload):
        self.calls.append((self.authority, name, payload))
        return self.replies.pop(0)


def clients(service_replies, actor_replies):
    calls = []
    return (
        FakeClient("service_role", "service-secret", "service-secret", service_replies, calls),
        FakeClient("authenticated_monitor", "anon-public", "actor-token", actor_replies, calls), calls,
    )


class RuntimeClientTests(unittest.TestCase):
    def test_service_attests_then_actor_processes_strict_readback(self):
        service, actor, calls = clients(
            [attestation()],
            [{"ok": True, "code": "jobcard_attachment_receipt", "data": canonical_data()}],
        )
        result = execute_jobcard_request(service, actor, request_fixture())
        self.assertTrue(result["ok"])
        self.assertEqual([(a, n) for a, n, _ in calls], [("service_role", ATTEST_RPC), ("authenticated_monitor", PROCESS_RPC)])
        self.assertEqual(result["operation_count"], 1)

    def test_guarded_non_navision_fallback(self):
        service, actor, calls = clients(
            [attestation()],
            [{"ok": False, "code": "backend_stock_not_found", "data": {}}, {"ok": True, "code": "non_navision_jobcard_receipt", "data": non_navision_data()}],
        )
        self.assertTrue(execute_jobcard_request(service, actor, request_fixture())["ok"])
        self.assertEqual([name for _, name, _ in calls], [ATTEST_RPC, PROCESS_RPC, NON_NAVISION_PROCESS_RPC])

    def test_unrelated_failure_does_not_fallback(self):
        service, actor, calls = clients(
            [attestation()],
            [{"ok": False, "code": "provider_observation_required_or_mismatch", "data": {}}],
        )
        result = execute_jobcard_request(service, actor, request_fixture())
        self.assertFalse(result["ok"]); self.assertEqual(len(calls), 2)

    def test_invalid_jobcard_shapes_make_zero_rpc_calls(self):
        cases = []
        request = request_fixture(); request["intake_id"] = "bad"; cases.append(request)
        request = request_fixture(); request["extraction"]["email_vehicle"].pop("cancelled"); cases.append(request)
        request = request_fixture(); request["extraction"]["email_vehicle"]["vins"] = ["INVALID"]; cases.append(request)
        request = request_fixture(); request["extraction"]["email_vehicle"]["vins"] = ["JH4TB2H26CC000000"]; cases.append(request)
        request = request_fixture(); request["extraction"]["operation_lines"][0]["operation_no"] = "OP2"; cases.append(request)
        request = request_fixture(); request["extraction"]["operation_lines"][0]["estimated_hours"] = True; cases.append(request)
        request = request_fixture(); request["extraction"]["operation_lines"][0]["description"] = "x" * 181; cases.append(request)
        request = request_fixture(); request["extraction"]["required_work"] = ["electrical"]; cases.append(request)
        request = request_fixture(); request["provider"]["authentication"]["gmail_authentication_results"] = 1; cases.append(request)
        for invalid in cases:
            with self.subTest(invalid=invalid):
                service, actor, calls = clients([], [])
                with self.assertRaises(RuntimeContractError):
                    execute_jobcard_request(service, actor, invalid)
                self.assertEqual(calls, [])

    def test_pairwise_credentials_and_exact_url_checked_before_rpc(self):
        calls = []
        service = FakeClient("service_role", "service-secret", "service-secret", [], calls)
        actor = FakeClient("authenticated_monitor", "anon-public", "anon-public", [], calls)
        with self.assertRaisesRegex(RuntimeContractError, "pairwise distinct"):
            execute_jobcard_request(service, actor, request_fixture())
        self.assertEqual(calls, [])
        service = FakeClient("service_role", "service-secret", "service-secret", [], calls, url="http://" + STAGING_URL.removeprefix("https://"))
        actor = FakeClient("authenticated_monitor", "anon-public", "actor-token", [], calls)
        with self.assertRaisesRegex(RuntimeContractError, "non-HTTPS"):
            execute_jobcard_request(service, actor, request_fixture())
        self.assertEqual(calls, [])

    def test_strict_success_code_and_shape(self):
        replies = (
            {"ok": True, "code": "jobcard_imported", "data": canonical_data()},
            {"ok": True, "code": "jobcard_attachment_receipt", "data": {**canonical_data(), "operation_count": 2}},
            {"ok": True, "code": "jobcard_attachment_receipt", "data": {**canonical_data(), "receipt_id": "bad"}},
            {"ok": True, "code": "jobcard_attachment_receipt"},
        )
        for reply in replies:
            service, actor, _ = clients([attestation()], [reply])
            with self.subTest(reply=reply), self.assertRaises(RuntimeContractError):
                execute_jobcard_request(service, actor, request_fixture())

    def test_attestation_success_shape_is_strict(self):
        service, actor, calls = clients([{"ok": True, "code": "provider_observation_attested"}], [])
        with self.assertRaises(RuntimeContractError):
            execute_jobcard_request(service, actor, request_fixture())
        self.assertEqual(len(calls), 1)

    def test_environment_rejects_wrong_url_without_network(self):
        with patch.dict("os.environ", {"SUPABASE_URL": "http://cdsmnqxtyyoeoznmbidd.supabase.co", "SUPABASE_SERVICE_ROLE_KEY": "service-secret", "SUPABASE_ANON_KEY": "anon-public"}, clear=True), patch("urllib.request.urlopen") as network:
            with self.assertRaises(RuntimeContractError):
                clients_from_environment()
            network.assert_not_called()

    def test_rpc_client_uses_anon_apikey_and_actor_bearer(self):
        response = type("Response", (), {
            "status": 200, "__enter__": lambda self: self, "__exit__": lambda self, *args: None,
            "read": lambda self, size=-1: json.dumps({"ok": True, "code": "x", "data": {}}).encode(),
        })()
        captured = {}
        def fake_urlopen(request, timeout):
            captured["request"] = request; return response
        client = RpcClient(STAGING_URL, "anon-public", "actor-token", "authenticated_monitor")
        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.rpc("some_rpc", {"x": 1})
        headers = {key.lower(): value for key, value in captured["request"].header_items()}
        self.assertEqual(headers["apikey"], "anon-public")
        self.assertEqual(headers["authorization"], "Bearer actor-token")


if __name__ == "__main__":
    unittest.main()
