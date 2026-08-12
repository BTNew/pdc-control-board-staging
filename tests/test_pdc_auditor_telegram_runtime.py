"""Deterministic unit tests for the bounded AI Auditor Telegram runtime.

These tests deliberately use no network, database, environment secrets, or deployment.
The fake RPC client records the runtime's database boundary exactly.
"""
from __future__ import annotations

import hashlib
import unittest

from backend import pdc_auditor_telegram_runtime as runtime


CHAT_ID = 99887766
BOT_IDENTITY = "pdc-auditor-staging-test"


def telegram_update(text: str = "Review duplicate bullbars") -> dict:
    return {
        "update_id": 101,
        "message": {
            "message_id": 202,
            "from": {"id": runtime.CRAIG_TELEGRAM_ID, "is_bot": False},
            "chat": {"id": CHAT_ID, "type": "private"},
            "date": 1_700_000_000,
            "text": text,
        },
    }


class FakeClient:
    def __init__(self, responses=None, error=None):
        self.responses = list(responses or [])
        self.error = error
        self.calls = []

    def rpc(self, name, payload):
        self.calls.append((name, payload))
        if self.error is not None:
            raise self.error
        if not self.responses:
            raise AssertionError(f"unexpected RPC call: {name}")
        return self.responses.pop(0)


def execute(client, text, context=None):
    return runtime.execute_bound(
        client,
        telegram_update(text),
        expected_chat_id=CHAT_ID,
        bot_identity=BOT_IDENTITY,
        context=context,
    )


class ParseInstructionTests(unittest.TestCase):
    def test_duplicate_bullbars_review_and_apply_are_distinct(self):
        self.assertEqual(
            runtime.parse_instruction("Review duplicate bullbars"),
            {
                "action": "duplicate_bullbars",
                "mode": "review",
                "scope": {"category": "bullbar", "confirmed_only": False},
            },
        )
        self.assertEqual(
            runtime.parse_instruction("Remove duplicate bull bars"),
            {
                "action": "duplicate_bullbars",
                "mode": "apply",
                "scope": {"category": "bullbar", "confirmed_only": True},
            },
        )

    def test_gvm_five_hours_is_encoded_and_tank_is_not_gvm(self):
        self.assertEqual(
            runtime.parse_instruction("Change genuine GVM upgrades to 5 hours"),
            {
                "action": "gvm_hours",
                "mode": "apply",
                "scope": {"category": "gvm_upgrade", "estimated_hours": 5.0},
            },
        )
        self.assertEqual(
            runtime.parse_instruction("Remember: GVM upgrades take 5 hours"),
            {
                "action": "remember_rule",
                "mode": "rule",
                "scope": {
                    "category": "gvm_upgrade",
                    "estimated_hours": 5.0,
                    "include": ["gvm upgrade", "gross vehicle mass upgrade"],
                    "exclude": ["long range fuel tank", "fuel tank"],
                },
            },
        )

    def test_gvm_apply_requires_hours_and_quarter_hour_precision(self):
        self.assertEqual(
            runtime.parse_instruction("Fix GVM upgrades"),
            {
                "action": "clarification",
                "question": "What exact hours should genuine GVM upgrades use?",
            },
        )
        with self.assertRaisesRegex(runtime.AuditorContractError, "quarter-hour precision"):
            runtime.parse_instruction("Fix GVM upgrades to 5.1 hours")

    def test_long_range_tank_routes_to_hoist(self):
        self.assertEqual(
            runtime.parse_instruction("Move long range fuel tank operations"),
            {
                "action": "long_range_tank_department",
                "mode": "apply",
                "scope": {"category": "long_range_fuel_tank", "work_key": "hoist"},
            },
        )
        remembered = runtime.parse_instruction("Remember: long-range fuel tanks use hoist")
        self.assertEqual(remembered["scope"]["exclude"], ["gvm upgrade"])
        self.assertEqual(remembered["scope"]["work_key"], "hoist")

    def test_line_context_is_required_and_bound(self):
        self.assertEqual(
            runtime.parse_instruction("Move this operation to electrical"),
            {"action": "clarification", "question": "Which operation line should I change?"},
        )
        self.assertEqual(
            runtime.parse_instruction(
                "Move this operation to pit inspection", {"operation_line_id": "line-7"}
            ),
            {
                "action": "line_department",
                "mode": "apply",
                "scope": {"operation_line_id": "line-7", "work_key": "pitInspection"},
            },
        )
        self.assertEqual(
            runtime.parse_instruction("Why did you change this?", {"operation_line_id": "line-7"}),
            {
                "action": "explain_line",
                "mode": "query",
                "scope": {"operation_line_id": "line-7"},
            },
        )

    def test_stock_command_avoids_ambiguous_or_missing_stock_and_hours(self):
        self.assertEqual(
            runtime.parse_instruction("Correct stock hours to 4 hours"),
            {
                "action": "clarification",
                "question": "Please specify the operation, scope and intended change.",
            },
        )
        self.assertEqual(
            runtime.parse_instruction("Correct Stock 123456 estimated hours"),
            {
                "action": "clarification",
                "question": "What exact hours should be applied to Stock 123456?",
            },
        )
        self.assertEqual(
            runtime.parse_instruction("Correct Stock 123456 to 4.25 hours"),
            {
                "action": "stock_hours",
                "mode": "apply",
                "scope": {"stock_number": "123456", "estimated_hours": 4.25},
            },
        )

    def test_rule_show_disable_correct_and_undo_commands(self):
        cases = [
            ("Show auditor rules", "show_rules", "rule", {}),
            ("Disable the gvm rule", "disable_rule", "rule", {"rule_selector": "gvm"}),
            (
                "Correct the gvm rule to 5 hours",
                "correct_rule",
                "rule",
                {"rule_selector": "gvm", "estimated_hours": 5.0},
            ),
            ("Undo my last rule", "undo_last_rule", "rule", {}),
            ("Undo the last auditor run", "undo_last_run", "undo", {}),
        ]
        for text, action, mode, scope in cases:
            with self.subTest(text=text):
                self.assertEqual(
                    runtime.parse_instruction(text),
                    {"action": action, "mode": mode, "scope": scope},
                )

    def test_apply_matching_requires_and_preserves_review_context(self):
        text = "Apply this correction to all matching vehicles"
        self.assertEqual(
            runtime.parse_instruction(text),
            {
                "action": "clarification",
                "question": "Which reviewed correction should I apply to all matching vehicles?",
            },
        )
        self.assertEqual(
            runtime.parse_instruction(
                text, {"rule_version_id": "rule-v3", "source_plan_id": "plan-2", "ignored": 1}
            ),
            {
                "action": "apply_matching",
                "mode": "apply",
                "scope": {"rule_version_id": "rule-v3", "source_plan_id": "plan-2"},
            },
        )

    def test_unknown_instruction_returns_bounded_clarification(self):
        self.assertEqual(
            runtime.parse_instruction("Please improve everything"),
            {
                "action": "clarification",
                "question": "Please specify the operation, scope and intended change.",
            },
        )

    def test_instruction_whitespace_and_length_are_rejected(self):
        for bad in (" hi", "hi ", "hi", "x" * 4001):
            with self.subTest(value=repr(bad[:10])):
                with self.assertRaises(runtime.AuditorContractError):
                    runtime.parse_instruction(bad)


class TelegramBindingTests(unittest.TestCase):
    def test_exact_craig_sender_and_configured_private_chat_are_bound(self):
        evidence = runtime.bind_telegram(
            telegram_update("Show rules"), expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY
        )
        self.assertEqual(evidence["telegram_sender_id"], runtime.CRAIG_TELEGRAM_ID)
        self.assertEqual(evidence["telegram_chat_id"], CHAT_ID)
        self.assertEqual(evidence["telegram_message_id"], 202)
        self.assertEqual(evidence["telegram_update_id"], 101)
        self.assertEqual(evidence["bot_identity"], BOT_IDENTITY)
        self.assertEqual(
            evidence["instruction_sha256"], hashlib.sha256(b"Show rules").hexdigest()
        )

    def test_other_human_sender_is_bound_for_database_authorization(self):
        update = telegram_update()
        update["message"]["from"] = {"id": runtime.CRAIG_TELEGRAM_ID + 1, "is_bot": False}
        evidence = runtime.bind_telegram(update, expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY)
        self.assertEqual(evidence["telegram_sender_id"], runtime.CRAIG_TELEGRAM_ID + 1)

    def test_invalid_or_bot_sender_is_rejected(self):
        for sender in (
            {"id": runtime.CRAIG_TELEGRAM_ID, "is_bot": True},
            {"id": runtime.CRAIG_TELEGRAM_ID, "is_bot": False, "username": "craig"},
            {"id": True, "is_bot": False},
        ):
            update = telegram_update()
            update["message"]["from"] = sender
            with self.subTest(sender=sender):
                with self.assertRaisesRegex(runtime.AuditorContractError, "sender shape"):
                    runtime.bind_telegram(update, expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY)

    def test_wrong_chat_or_non_private_chat_is_rejected(self):
        for chat in (
            {"id": CHAT_ID + 1, "type": "private"},
            {"id": CHAT_ID, "type": "group"},
            {"id": CHAT_ID, "type": "private", "title": "extra"},
        ):
            update = telegram_update()
            update["message"]["chat"] = chat
            with self.subTest(chat=chat):
                with self.assertRaisesRegex(runtime.AuditorContractError, "configured private chat"):
                    runtime.bind_telegram(update, expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY)

    def test_update_and_message_shapes_are_exact(self):
        update = telegram_update()
        update["extra"] = True
        with self.assertRaisesRegex(runtime.AuditorContractError, "update keys"):
            runtime.bind_telegram(update, expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY)
        update = telegram_update()
        update["message"]["username"] = "injected"
        with self.assertRaisesRegex(runtime.AuditorContractError, "message keys"):
            runtime.bind_telegram(update, expected_chat_id=CHAT_ID, bot_identity=BOT_IDENTITY)


class RpcBoundaryTests(unittest.TestCase):
    def test_staging_url_is_pinned_to_exact_origin(self):
        client = runtime.RpcClient(runtime.STAGING_URL + "/", "key", "token")
        self.assertEqual(client.url, runtime.STAGING_URL)
        rejected = [
            "http://cdsmnqxtyyoeoznmbidd.supabase.co",
            "https://evil.example",
            runtime.STAGING_URL + ":443",
            runtime.STAGING_URL + "/rest/v1",
            runtime.STAGING_URL + "?x=1",
            runtime.STAGING_URL + "#fragment",
            "https://user:pass@cdsmnqxtyyoeoznmbidd.supabase.co",
        ]
        for url in rejected:
            with self.subTest(url=url):
                with self.assertRaisesRegex(runtime.AuditorContractError, "exact staging origin"):
                    runtime.RpcClient(url, "key", "token")

    def test_rpc_name_allowlist_rejects_before_any_network_access(self):
        client = runtime.RpcClient(runtime.STAGING_URL, "key", "token")
        with self.assertRaisesRegex(runtime.AuditorContractError, "not allowlisted"):
            client.rpc("arbitrary_or_production_rpc", {})

    def test_review_calls_planner_only_with_review_mode(self):
        plan = {"ok": True, "code": "planned", "data": {"plan_id": "p1", "plan_hash": "h1"}}
        client = FakeClient([plan])
        self.assertIs(execute(client, "Review duplicate bullbars"), plan)
        self.assertEqual(len(client.calls), 1)
        name, payload = client.calls[0]
        self.assertEqual(name, runtime.PLAN_RPC)
        self.assertEqual(payload["p_action"], "duplicate_bullbars")
        self.assertEqual(payload["p_mode"], "review")
        self.assertEqual(payload["p_scope"], {"category": "bullbar", "confirmed_only": False})
        self.assertEqual(payload["p_telegram_evidence"]["telegram_sender_id"], runtime.CRAIG_TELEGRAM_ID)

    def test_apply_calls_planner_then_apply_with_immutable_plan_identity(self):
        plan = {"ok": True, "code": "planned", "data": {"plan_id": "p9", "plan_hash": "hash9"}}
        applied = {"ok": True, "code": "applied", "data": {"run_id": "r2"}}
        client = FakeClient([plan, applied])
        self.assertIs(execute(client, "Remove duplicate bullbars"), applied)
        self.assertEqual([name for name, _ in client.calls], [runtime.PLAN_RPC, runtime.APPLY_RPC])
        apply_payload = client.calls[1][1]
        self.assertEqual(apply_payload["p_plan"], "p9")
        self.assertEqual(apply_payload["p_plan_hash"], "hash9")
        self.assertEqual(
            apply_payload["p_telegram_evidence"], client.calls[0][1]["p_telegram_evidence"]
        )

    def test_failed_plan_is_returned_and_never_applied_or_retried(self):
        denied = {"ok": False, "code": "conflict", "data": {}}
        client = FakeClient([denied])
        self.assertIs(execute(client, "Remove duplicate bullbars"), denied)
        self.assertEqual(len(client.calls), 1)
        self.assertEqual(client.calls[0][0], runtime.PLAN_RPC)

    def test_runtime_does_not_retry_rpc_errors_because_db_owns_retries(self):
        client = FakeClient(error=RuntimeError("database unavailable"))
        with self.assertRaisesRegex(RuntimeError, "database unavailable"):
            execute(client, "Remove duplicate bullbars")
        self.assertEqual(len(client.calls), 1)

    def test_clarification_makes_no_rpc_call(self):
        client = FakeClient([])
        result = execute(client, "Please improve everything")
        self.assertEqual(result["code"], "clarification_required")
        self.assertEqual(client.calls, [])

    def test_query_rule_and_undo_dispatch_to_only_their_allowlisted_rpc(self):
        cases = [
            ("Show rules", runtime.RULE_RPC, "show_rules"),
            ("Disable the gvm rule", runtime.RULE_RPC, "disable_rule"),
            ("Undo last auditor run", runtime.UNDO_RPC, None),
        ]
        for text, expected_rpc, expected_action in cases:
            with self.subTest(text=text):
                response = {"ok": True, "code": "ok", "data": {}}
                client = FakeClient([response])
                self.assertIs(execute(client, text), response)
                self.assertEqual(len(client.calls), 1)
                name, payload = client.calls[0]
                self.assertEqual(name, expected_rpc)
                if expected_action is None:
                    self.assertEqual(set(payload), {"p_telegram_evidence"})
                else:
                    if expected_rpc == runtime.RULE_RPC:
                        self.assertEqual(payload["p_action"], "show" if expected_action == "show_rules" else "disable")
                        self.assertIn("p_evidence", payload)
                    else:
                        self.assertEqual(payload["p_action"], expected_action)

    def test_apply_requires_plan_id(self):
        client = FakeClient([{"ok": True, "code": "planned", "data": {"plan_hash": "h"}}])
        with self.assertRaisesRegex(runtime.AuditorContractError, "omitted plan_id"):
            execute(client, "Remove duplicate bullbars")
        self.assertEqual(len(client.calls), 1)


if __name__ == "__main__":
    unittest.main()
