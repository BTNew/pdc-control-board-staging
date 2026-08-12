import copy
import io
import json
import unittest
import urllib.error
from unittest.mock import patch

from backend.pdc_supervised_learning_client import (
    ACTIONS, COMMAND_RPC, MONITOR_APPLY_RPC, MONITOR_READ_RPC, RpcClient,
    STAGING_URL, SupervisedLearningContractError, execute_command,
    resolve_active_rule, strip_jc_prefix, validate_command,
)

LESSON_ID = "11111111-1111-4111-8111-111111111111"
EVIDENCE = {
    "original_instruction": "Craig says use fitting for JC fit bull bar from now on",
    "telegram_sender_id": 81234567,
    "telegram_chat_id": -1001234567890,
    "telegram_message_id": 987,
}
PRICING = {"cost_ex_gst": "100.00", "sell_ex_gst": "175.00", "gst_percent": "10.00", "currency": "AUD"}
SCOPE = {"operation_code": "OP-14", "operation_description": "JC Fit bull bar", "current_mapping": "uncertain"}
PROPOSAL = {"scope": SCOPE, "target_mapping": "fitting", "estimated_hours": None, "pricing": PRICING, "reason": "Exact operation OP-14 evidence"}


class FakeClient:
    def __init__(self, authority, replies, url=STAGING_URL):
        self.authority, self.replies, self.url = authority, list(replies), url
        self.calls = []

    def rpc(self, name, payload):
        self.calls.append((name, copy.deepcopy(payload)))
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return copy.deepcopy(reply)


def envelope(code="lesson_proposed", data=None, ok=True):
    return {"ok": ok, "code": code, "data": {} if data is None else data}


def command(action, parameters):
    return {"action": action, "parameters": parameters, "telegram_evidence": copy.deepcopy(EVIDENCE)}


class SupervisedLearningClientTests(unittest.TestCase):
    def test_every_supported_command_uses_one_exact_rpc_and_retains_telegram_evidence(self):
        cases = {
            "propose_lesson": (PROPOSAL, "lesson_proposed"),
            "activate_future": ({"lesson_id": LESSON_ID}, "lesson_activated"),
            "review_apply_existing_scope": ({"lesson_id": LESSON_ID}, "existing_scope_reviewed"),
            "list_active": ({}, "active_lessons"),
            "explain_why": ({"lesson_id": LESSON_ID}, "lesson_explained"),
            "create_corrected_version": ({"lesson_id": LESSON_ID, "replacement": PROPOSAL}, "corrected_version_created"),
            "disable": ({"lesson_id": LESSON_ID}, "lesson_disabled"),
            "undo_last_lesson": ({}, "last_lesson_undone"),
            "review_uncertain": ({}, "uncertain_lessons"),
        }
        self.assertEqual(set(cases), set(ACTIONS))
        for action, (parameters, code) in cases.items():
            with self.subTest(action=action):
                client = FakeClient("actor", [envelope(code)])
                result = execute_command(client, command(action, parameters))
                self.assertTrue(result["ok"])
                self.assertEqual(client.calls, [(COMMAND_RPC, {
                    "p_action": action,
                    "p_parameters": parameters,
                    "p_telegram_evidence": EVIDENCE,
                })])

    def test_broad_category_proposal_returns_clarification_and_never_activates(self):
        broad = copy.deepcopy(PROPOSAL)
        broad["scope"] = {"operation_code": "ALL", "operation_description": "all accessories", "current_mapping": None}
        reply = envelope("clarification_required", {
            "question": "Which exact operation code should this cover?",
            "candidates": ["OP-14", "OP-15"],
        })
        client = FakeClient("actor", [reply, envelope("lesson_activated")])
        self.assertEqual(execute_command(client, command("propose_lesson", broad)), reply)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(client.calls[0][0], COMMAND_RPC)
        self.assertEqual(client.calls[0][1]["p_action"], "propose_lesson")

    def test_pricing_requires_supplied_cost_sell_gst_currency_shape(self):
        invalid = []
        for pricing in (
            {"sell_ex_gst": "175.00", "gst_percent": "10.00", "currency": "AUD"},
            {**PRICING, "cost_ex_gst": 100.0},
            {**PRICING, "sell_ex_gst": "175"},
            {**PRICING, "gst_percent": "10"},
            {**PRICING, "gst_percent": "15.00"},
            {**PRICING, "currency": "USD"},
            {**PRICING, "calculated_sell_inc_gst": "192.50"},
        ):
            proposal = copy.deepcopy(PROPOSAL); proposal["pricing"] = pricing; invalid.append(proposal)
        for proposal in invalid:
            with self.subTest(pricing=proposal["pricing"]):
                client = FakeClient("actor", [])
                with self.assertRaises(SupervisedLearningContractError):
                    execute_command(client, command("propose_lesson", proposal))
                self.assertEqual(client.calls, [])
        proposal = copy.deepcopy(PROPOSAL); proposal["pricing"] = None
        self.assertEqual(validate_command(command("propose_lesson", proposal))["parameters"]["pricing"], None)

    def test_exact_payload_rejects_extra_missing_or_invalid_telegram_identity_before_rpc(self):
        cases = []
        value = command("list_active", {}); value["extra"] = True; cases.append(value)
        value = command("list_active", {}); value["telegram_evidence"].pop("original_instruction"); cases.append(value)
        value = command("list_active", {}); value["telegram_evidence"]["telegram_sender_id"] = "81234567"; cases.append(value)
        value = command("list_active", {}); value["telegram_evidence"]["telegram_message_id"] = 0; cases.append(value)
        value = command("list_active", {"scope": "all"}); cases.append(value)
        for value in cases:
            client = FakeClient("actor", [])
            with self.subTest(value=value), self.assertRaises(SupervisedLearningContractError):
                execute_command(client, value)
            self.assertEqual(client.calls, [])

    def test_restart_has_no_local_state_and_new_client_reads_supabase(self):
        first = FakeClient("actor", [envelope("lesson_proposed", {"lesson_id": LESSON_ID})])
        execute_command(first, command("propose_lesson", PROPOSAL))
        # Simulate a process restart: no object or module state is carried over.
        restarted = FakeClient("actor", [envelope("active_lessons", {"lessons": [{"lesson_id": LESSON_ID}]})])
        result = execute_command(restarted, command("list_active", {}))
        self.assertEqual(result["data"]["lessons"][0]["lesson_id"], LESSON_ID)
        self.assertEqual(restarted.calls[0][0], COMMAND_RPC)
        self.assertEqual(restarted.calls[0][1]["p_action"], "list_active")

    def test_monitor_resolver_reads_then_applies_exact_rule_with_jc_metadata(self):
        rule = {"lesson_id": LESSON_ID, "version": 3, "target_mapping": "fitting", "pricing": PRICING}
        client = FakeClient("scoped_monitor", [
            envelope("active_lessons", {"matched": True, "rule": rule}),
            envelope("lesson_activated", {"applied": True}),
        ])
        result = resolve_active_rule(client, "OP-14", "JC-123: Fit bull bar", "uncertain")
        self.assertTrue(result["ok"])
        self.assertEqual([name for name, _ in client.calls], [MONITOR_READ_RPC, MONITOR_APPLY_RPC])
        apply = client.calls[1][1]
        self.assertEqual(apply["p_lesson_id"], LESSON_ID)
        self.assertEqual(apply["p_expected_version"], 3)
        self.assertEqual(apply["p_resolution"]["display_description"], "Fit bull bar")
        self.assertEqual(apply["p_resolution"]["jc_metadata"], {
            "original_operation_description": "JC-123: Fit bull bar", "jc_prefix_stripped": True,
        })

    def test_monitor_unmatched_rule_does_not_apply(self):
        client = FakeClient("scoped_monitor", [envelope("active_lessons", {"matched": False, "rule": None})])
        result = resolve_active_rule(client, "OP-14", "Fit bull bar", None)
        self.assertFalse(result["data"]["matched"])
        self.assertEqual([name for name, _ in client.calls], [MONITOR_READ_RPC])

    def test_jc_prefix_stripping_is_prefix_only(self):
        self.assertEqual(strip_jc_prefix("JC-123: Fit bull bar")[0], "Fit bull bar")
        self.assertEqual(strip_jc_prefix("JC Fit bull bar")[0], "JC Fit bull bar")
        self.assertEqual(strip_jc_prefix("Fit JC connector")[0], "Fit JC connector")

    def test_actor_monitor_authority_and_exact_staging_url_fail_closed(self):
        actor_command = command("list_active", {})
        for authority in ("scoped_monitor", None):
            client = FakeClient(authority, [])
            with self.assertRaisesRegex(SupervisedLearningContractError, "actor JWT"):
                execute_command(client, actor_command)
        for bad_url in ("http://cdsmnqxtyyoeoznmbidd.supabase.co", "https://other.supabase.co", STAGING_URL + "?prod=1"):
            client = FakeClient("actor", [], bad_url)
            with self.assertRaises(SupervisedLearningContractError):
                execute_command(client, actor_command)
            self.assertEqual(client.calls, [])
        client = FakeClient("actor", [])
        with self.assertRaisesRegex(SupervisedLearningContractError, "scoped monitor"):
            resolve_active_rule(client, "OP-14", "Fit bull bar", None)

    def test_remote_unauthorized_and_errors_propagate_without_secret_details(self):
        unauthorized = envelope("unauthorized", {}, ok=False)
        client = FakeClient("actor", [unauthorized])
        self.assertEqual(execute_command(client, command("list_active", {})), unauthorized)

        actor_jwt = "actor-super-secret-jwt"
        anon_key = "anon-super-secret-key"
        error_body = b'{"message":"actor-super-secret-jwt anon-super-secret-key database password"}'
        http_error = urllib.error.HTTPError(STAGING_URL, 401, "Denied", {}, io.BytesIO(error_body))
        rpc = RpcClient(STAGING_URL, anon_key, actor_jwt, "actor")
        with patch("urllib.request.urlopen", side_effect=http_error):
            with self.assertRaises(SupervisedLearningContractError) as caught:
                rpc.rpc(COMMAND_RPC, {})
        rendered = str(caught.exception)
        self.assertIn("unauthorized", rendered)
        for secret in (actor_jwt, anon_key, "database password"):
            self.assertNotIn(secret, rendered)

    def test_rpc_client_sends_anon_key_and_actor_jwt_only_in_headers(self):
        response = type("Response", (), {
            "status": 200, "getcode": lambda self: 200,
            "__enter__": lambda self: self, "__exit__": lambda self, *args: None,
            "read": lambda self, size=-1: json.dumps(envelope("active_lessons")).encode(),
        })()
        captured = {}
        def open_request(request, timeout):
            captured["request"] = request
            return response
        client = RpcClient(STAGING_URL, "anon-public", "actor-token", "actor")
        with patch("urllib.request.urlopen", side_effect=open_request):
            client.rpc(COMMAND_RPC, {"p_action": "list_active"})
        headers = {key.lower(): value for key, value in captured["request"].header_items()}
        self.assertEqual(headers["apikey"], "anon-public")
        self.assertEqual(headers["authorization"], "Bearer actor-token")
        self.assertNotIn(b"actor-token", captured["request"].data)


if __name__ == "__main__":
    unittest.main()
