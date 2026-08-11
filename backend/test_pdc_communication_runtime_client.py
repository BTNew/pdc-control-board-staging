import copy
import hashlib
import unittest

from backend.pdc_communication_runtime_client import (
    PROCESS_COMMUNICATION_RPC, execute_communication_request, validate_communication_request,
)
from backend.pdc_jobcard_runtime_client import ATTEST_RPC, RuntimeContractError, STAGING_URL

HASH_A = "a" * 64
HASH_B = "b" * 64
HASH_C = "c" * 64
ATTACHMENT_ID = "11111111-1111-4111-8111-111111111111"
INTAKE_ID = "22222222-2222-4222-8222-222222222222"
OBSERVATION_ID = "55555555-5555-4555-8555-555555555555"
AUTH = {"dkim_aligned": True, "dmarc_aligned": True, "gmail_authentication_results": True, "sender_domain": "example.com", "spf_aligned": True}


def fixture(action=None):
    action = action or {"source_action_no": 1, "action_type": "parts_complete", "evidence": "Parts complete"}
    auth = copy.deepcopy(AUTH)
    return {
        "intake_id": INTAKE_ID, "expected_source_hash": HASH_A, "extraction_hash": HASH_C,
        "provider": {"attachment_id": ATTACHMENT_ID, "provider_message_id": "<m@example.com>", "provider_authserv_id": "mx.google.com", "authentication": auth},
        "extraction": {
            "actions": [action], "authentication": auth, "auto_applicable": True,
            "canonical_attachment_id": ATTACHMENT_ID, "canonical_document_hash": HASH_B,
            "contract_version": "pmb-email-communications-v1",
            "identity": {"job_card_numbers": [], "stock_numbers": ["12657478"], "vins": []}, "review_reasons": [],
        },
    }


def communication_data(request=None):
    request = request or fixture()
    action = request["extraction"]["actions"][0]
    retained_clause = " ".join(action["evidence"].split()).strip(" .,;:-").lower()
    return {
        "receipt_id": "33333333-3333-4333-8333-333333333333", "intake_id": INTAKE_ID,
        "attachment_id": ATTACHMENT_ID, "vehicle_id": "44444444-4444-4444-8444-444444444444",
        "action_count": 1, "actions": [{
            "source_action_no": 1, "action_type": action["action_type"], "evidence": action["evidence"],
            "retained_clause": retained_clause,
            "retained_clause_sha256": hashlib.sha256(retained_clause.encode("utf-8")).hexdigest(),
            "requested_action": action, "before_data": None, "after_data": {},
        }], "booking_created": False, "location_changed": False,
    }


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


class CommunicationRuntimeClientTests(unittest.TestCase):
    def test_attests_then_accepts_strict_receipt_readback(self):
        request = fixture()
        service, actor, calls = clients(
            [attestation()],
            [{"ok": True, "code": "communication_receipt", "data": communication_data(request)}],
        )
        result = execute_communication_request(service, actor, request)
        self.assertTrue(result["ok"])
        self.assertEqual([(a, n) for a, n, _ in calls], [("service_role", ATTEST_RPC), ("authenticated_monitor", PROCESS_COMMUNICATION_RPC)])

    def test_invalid_requests_make_zero_rpc_calls(self):
        mutations = []
        request = fixture(); request["intake_id"] = "not-a-uuid"; mutations.append(request)
        request = fixture(); request["extraction"]["authentication"]["spf_aligned"] = "true"; mutations.append(request)
        request = fixture(); request["extraction"]["identity"]["vins"] = ["JH4TB2H26CC000000"]; mutations.append(request)
        request = fixture(); request["extraction"]["actions"][0]["evidence"] = "x" * 241; mutations.append(request)
        request = fixture({"source_action_no": 1, "action_type": "set_sublet_booking_date", "booking_date": "2026-02-30", "evidence": "Sublet booked 30 February"}); mutations.append(request)
        request = fixture({"source_action_no": 1, "action_type": "add_accessory_work", "description": "Premium bull bar", "work_key": "fitting", "evidence": "Add premium bull bar"}); mutations.append(request)
        for invalid in mutations:
            with self.subTest(invalid=invalid):
                service, actor, calls = clients([], [])
                with self.assertRaises(RuntimeContractError):
                    execute_communication_request(service, actor, invalid)
                self.assertEqual(calls, [])

    def test_review_only_request_is_rejected(self):
        request = fixture(); request["extraction"]["auto_applicable"] = False; request["extraction"]["review_reasons"] = ["uncertain"]
        with self.assertRaisesRegex(RuntimeContractError, "review-only"):
            validate_communication_request(request)

    def test_attestation_failure_stops_processing(self):
        service, actor, calls = clients([{"ok": False, "code": "binding_mismatch", "data": {}}], [])
        result = execute_communication_request(service, actor, fixture())
        self.assertFalse(result["ok"]); self.assertEqual(len(calls), 1)

    def test_failure_codes_are_fixed_not_remote_controlled(self):
        remote = "arbitrary_remote_body_code"
        service, actor, _ = clients([{"ok": False, "code": remote, "data": {}}], [])
        self.assertEqual(execute_communication_request(service, actor, fixture())["code"], "attestation_failed")
        service, actor, _ = clients([attestation()], [{"ok": False, "code": remote, "data": {}}])
        self.assertEqual(execute_communication_request(service, actor, fixture())["code"], "processing_failed")

    def test_receipt_intake_and_attachment_are_request_bound_and_count_is_strict(self):
        for key, value in (("intake_id", ATTACHMENT_ID), ("attachment_id", INTAKE_ID), ("action_count", True)):
            with self.subTest(key=key):
                data = communication_data(); data[key] = value
                service, actor, _ = clients([attestation()], [{"ok": True, "code": "communication_receipt", "data": data}])
                with self.assertRaises(RuntimeContractError):
                    execute_communication_request(service, actor, fixture())

    def test_credentials_are_pairwise_separated_before_rpc(self):
        calls = []
        service = FakeClient("service_role", "service-secret", "service-secret", [], calls)
        actor = FakeClient("authenticated_monitor", "service-secret", "actor-token", [], calls)
        with self.assertRaisesRegex(RuntimeContractError, "pairwise distinct"):
            execute_communication_request(service, actor, fixture())
        self.assertEqual(calls, [])

    def test_non_https_or_wrong_project_is_rejected_before_rpc(self):
        for url in ("http://cdsmnqxtyyoeoznmbidd.supabase.co", "https://other.supabase.co", STAGING_URL + "?x=1"):
            calls = []
            service = FakeClient("service_role", "service-secret", "service-secret", [], calls, url=url)
            actor = FakeClient("authenticated_monitor", "anon-public", "actor-token", [], calls, url=url)
            with self.assertRaises(RuntimeContractError):
                execute_communication_request(service, actor, fixture())
            self.assertEqual(calls, [])

    def test_wrong_success_code_or_readback_shape_fails_closed(self):
        for reply in (
            {"ok": True, "code": "communication_applied", "data": communication_data()},
            {"ok": True, "code": "communication_receipt", "data": {**communication_data(), "action_count": 2}},
            {"ok": True, "code": "communication_receipt", "data": {**communication_data(), "location_changed": True}},
        ):
            service, actor, _ = clients(
                [attestation()], [reply]
            )
            with self.assertRaises(RuntimeContractError):
                execute_communication_request(service, actor, fixture())

    def test_producer_receipt_clause_and_hash_are_exact(self):
        for field, value in (("retained_clause", "different"), ("retained_clause_sha256", "0" * 64)):
            data = communication_data()
            data["actions"][0][field] = value
            service, actor, _ = clients(
                [attestation()], [{"ok": True, "code": "communication_receipt", "data": data}]
            )
            with self.subTest(field=field), self.assertRaises(RuntimeContractError):
                execute_communication_request(service, actor, fixture())


if __name__ == "__main__":
    unittest.main()
