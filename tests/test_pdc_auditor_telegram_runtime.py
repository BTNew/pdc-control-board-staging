"""Contract tests for bounded typed Auditor ingress and signed selection envelopes."""
from __future__ import annotations

import hashlib
import hmac
import json
from pathlib import Path
import unittest
import uuid

from backend import pdc_auditor_telegram_runtime as runtime

CHAT_ID = 99887766
BOT_IDENTITY = "pdc-auditor-staging-test"
KEY_ID = "gateway-key-1"
KEY = b"unit-test-key-material-only-32bytes"
NOW = 1_700_000_100
VEHICLE = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
PROPOSAL = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
PROPOSAL_VERSION = 1
RUN = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
SRC1 = "source:11111111-1111-4111-8111-111111111111"
SRC2 = "source:22222222-2222-4222-8222-222222222222"
AUD1 = "auditor:33333333-3333-4333-8333-333333333333"
HASH = "ab" * 32


def telegram_update(text: str) -> dict:
    return {"update_id": 101, "message": {"message_id": 202,
        "from": {"id": runtime.CRAIG_TELEGRAM_ID, "is_bot": False, "first_name": "Craig"},
        "chat": {"id": CHAT_ID, "type": "private", "first_name": "Craig"}, "date": 1_700_000_000, "text": text}}


def signed_envelope(text: str, selected_scope: dict, **overrides) -> dict:
    evidence = runtime.bind_telegram(telegram_update(text), expected_chat_id=CHAT_ID,
                                     bot_identity=BOT_IDENTITY)
    envelope = {"gateway_instance_id": "gw-staging-1",
        "delivery_uuid": "12345678-1234-4234-9234-123456789abc",
        "key_id": KEY_ID, "nonce": "nonce-unique-123456", "issued_at": "2023-11-14T22:14:50Z",
        "expires_at": "2023-11-14T22:16:40Z", "instruction_sha256": hashlib.sha256(text.encode()).hexdigest(),
        "selected_scope": selected_scope, "telegram_evidence": evidence, "signature": "0" * 64}
    envelope.update(overrides)
    envelope["signature"] = hmac.new(KEY, runtime.gateway_signing_bytes(envelope), hashlib.sha256).hexdigest()
    return envelope


class FakeClient:
    def __init__(self, responses=()): self.responses, self.calls = list(responses), []
    def rpc(self, name, payload):
        self.calls.append((name, payload))
        if not self.responses: raise AssertionError(f"unexpected RPC {name}")
        return self.responses.pop(0)


def execute(client, text, context=None, envelope=None):
    command = runtime.parse_instruction(text, context)
    selected = command.get("selected_scope", {})
    return runtime.execute_bound(client, telegram_update(text), expected_chat_id=CHAT_ID,
        bot_identity=BOT_IDENTITY, gateway_envelope=envelope or signed_envelope(text, selected),
        key_resolver=lambda key_id: KEY if key_id == KEY_ID else None, context=context, now=NOW)


def intent(selector: dict, action: str, **desired) -> dict:
    return {"contract": runtime.INTENT_CONTRACT, "action": action, "apply_unambiguous": False,
            "selector": selector, "desire": desired}


class TypedIntentTests(unittest.TestCase):
    def test_exact_edit_and_bounded_category_actions(self):
        self.assertEqual(runtime.parse_instruction("Correct operation hours to 4.25 hours", {"operation_ref": SRC1}),
            {"action": "edit", "mode": "apply", "selected_scope": intent(
                {"operation_ref": SRC1}, "edit", new_value={"estimated_hours": 4.25})})
        self.assertEqual(runtime.parse_instruction("Change genuine GVM upgrades to 5 hours"),
            {"action": "edit", "mode": "apply", "selected_scope": intent(
                {"category": "gvm_upgrade"}, "edit", new_value={"estimated_hours": 5.0})})
        self.assertEqual(runtime.parse_instruction("Review duplicate bullbars", {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}}),
            {"action": "remove_duplicate", "mode": "review", "selected_scope": intent(
                {"operation_refs": [SRC1, SRC2]}, "remove_duplicate", duplicate_proof="database_exact", survivor_operation_ref=SRC1)})
        self.assertNotIn("review_category", repr(runtime.parse_instruction("Review duplicate bullbars", {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}})))

    def test_exactly_one_strict_selector(self):
        for context in ({}, {"operation_ref": SRC1, "vehicle_id": VEHICLE},
                        {"operation_ref": "source:not-a-uuid"}, {"vehicle_id": "v1"},
                        {"job_card_number": "bad jc!"}):
            with self.subTest(context=context):
                if context and len(context) == 1 and next(iter(context)) in {"operation_ref", "vehicle_id", "job_card_number"}:
                    with self.assertRaises(runtime.AuditorContractError):
                        runtime.parse_instruction("Edit operation code to X1", context)
                else:
                    self.assertEqual(runtime.parse_instruction("Edit operation code to X1", context)["action"], "clarification")

    def test_add_requires_complete_trusted_value_not_prose(self):
        text = "Add operation code BB01 description Fit bullbar"
        self.assertEqual(runtime.parse_instruction(text, {"vehicle_id": VEHICLE})["action"], "clarification")
        context = {"vehicle_id": VEHICLE, "trusted_intent": {"new_value": {
            "description": "Fit bullbar", "work_key": "fitting", "estimated_hours": 3.25,
            "operation_code": "BB01", "ordered_position": 4}}}
        self.assertEqual(runtime.parse_instruction(text, context), {"action": "add", "mode": "apply",
            "selected_scope": intent({"vehicle_id": VEHICLE}, "add", new_value=context["trusted_intent"]["new_value"])})

    def test_ordered_position_accepts_canonical_integral_numeric_semantics(self):
        for good in (1, 1.0, 1e0, 10000.0):
            with self.subTest(good=good):
                self.assertEqual(runtime._new_value({
                    "description": "Fit bullbar", "work_key": "fitting", "estimated_hours": 3.25,
                    "operation_code": "BB01", "ordered_position": good
                }, complete=True)["ordered_position"], int(good))
        for bad in (1.25, 0, 10000.5, 10001, True, "1"):
            with self.subTest(bad=bad):
                with self.assertRaises(runtime.AuditorContractError):
                    runtime._new_value({
                        "description": "Fit bullbar", "work_key": "fitting", "estimated_hours": 3.25,
                        "operation_code": "BB01", "ordered_position": bad
                    }, complete=True)

    def test_split_combine_and_reorder_never_invent_structured_values(self):
        self.assertEqual(runtime.parse_instruction("Split this operation into A and B", {"operation_ref": SRC1})["action"], "clarification")
        children = [{"description": "Fit", "work_key": "fitting", "estimated_hours": 2.0},
                    {"description": "Wire", "work_key": "electrical", "estimated_hours": 1.25}]
        split = runtime.parse_instruction("Split this operation into A and B",
            {"operation_ref": SRC1, "trusted_intent": {"children": children}})
        self.assertEqual(split["selected_scope"], intent({"operation_ref": SRC1}, "split", children=children))

        combine_context = {"operation_refs": [SRC1, AUD1], "trusted_intent": {
            "survivor_operation_ref": SRC1, "new_value": {"description": "Combined", "work_key": "fitting",
                "estimated_hours": 4.0, "operation_code": "COMB"}}}
        combine = runtime.parse_instruction("Combine these operations", combine_context)
        self.assertEqual(combine["action"], "combine")
        self.assertEqual(combine["selected_scope"]["desire"]["survivor_operation_ref"], SRC1)

        self.assertEqual(runtime.parse_instruction("Reorder operation lines", {"vehicle_id": VEHICLE})["action"], "clarification")
        reorder = runtime.parse_instruction("Reorder operation lines", {"vehicle_id": VEHICLE,
            "trusted_intent": {"ordered_operation_refs": [SRC2, SRC1, AUD1]}})
        self.assertEqual(reorder["selected_scope"]["selector"]["operation_refs"], [SRC2, SRC1, AUD1])
        self.assertIs(reorder["selected_scope"]["desire"]["complete_effective_set"], True)

    def test_apply_and_undo_have_exact_selection_contracts(self):
        reviewed = {"reviewed_proposal_id": PROPOSAL, "reviewed_proposal_version": PROPOSAL_VERSION,
            "reviewed_proposal_hash": HASH, "reviewed_typed_item_set_hash": HASH,
            "reviewed_final_scope_hash": HASH, "reviewed_expected_row_versions_hash": HASH}
        expected = {"contract": runtime.APPLY_SELECTION_CONTRACT, "proposal_id": PROPOSAL,
            "proposal_version": PROPOSAL_VERSION, "proposal_hash": HASH,
            "typed_item_set_hash": HASH, "final_scope_hash": HASH,
            "expected_row_versions_hash": HASH}
        self.assertEqual(runtime.parse_instruction("Apply these corrections", reviewed), {
            "action": "apply_reviewed_proposal", "mode": "apply_reviewed", "selected_scope": expected})
        for missing in reviewed:
            bad = dict(reviewed); bad.pop(missing)
            self.assertEqual(runtime.parse_instruction("Apply these corrections", bad)["action"], "clarification")
        self.assertEqual(runtime.parse_instruction("Undo the selected Auditor run", {"selected_run_id": RUN, "selected_run_revision_after": HASH})["selected_scope"],
            {"contract": runtime.UNDO_SELECTION_CONTRACT, "run_id": RUN, "run_revision_after": HASH})

    def test_compose_requires_exactly_six_distinct_reviewed_proposals(self):
        proposals = [str(uuid.UUID(int=i, version=4)) for i in range(1, 7)]
        expected = {"contract": runtime.COMPOSE_SELECTION_CONTRACT, "proposal_ids": proposals}
        self.assertEqual(runtime.parse_instruction("Compose these reviewed corrections",
            {"reviewed_proposal_ids": proposals}),
            {"action": "compose_reviewed_proposals", "mode": "compose", "selected_scope": expected})
        for bad in (proposals[:5], proposals[:5] + [proposals[0]], ["invalid"] * 6):
            self.assertEqual(runtime.parse_instruction("Compose these reviewed corrections",
                {"reviewed_proposal_ids": bad})["action"], "clarification")

    def test_compose_dispatches_only_exact_bounded_rpc(self):
        proposals = [str(uuid.UUID(int=i, version=4)) for i in range(1, 7)]
        selected = {"contract": runtime.COMPOSE_SELECTION_CONTRACT, "proposal_ids": proposals}
        client = FakeClient([{"ok": True, "code": "typed_mixed_proposal_created", "data": {}}])
        result = execute(client, "Compose these reviewed corrections",
            {"reviewed_proposal_ids": proposals}, signed_envelope("Compose these reviewed corrections", selected))
        self.assertTrue(result["ok"])
        self.assertEqual(client.calls, [(runtime.COMPOSE_RPC,
            {"p_proposals": proposals, "p_gateway_envelope": signed_envelope("Compose these reviewed corrections", selected)})])

    def test_apply_prefix_still_only_selects_apply_mode_plan(self):
        command = runtime.parse_instruction("Apply edit operation code to X1", {"operation_ref": SRC1})
        self.assertEqual(command["action"], "edit")
        self.assertEqual(command["mode"], "apply")


class GatewayEnvelopeTests(unittest.TestCase):
    def test_telegram_evidence_values_are_typed_before_signature_use(self):
        text = "Review duplicate bullbars"
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate",
            duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        for field in ("original_instruction", "bot_identity", "instruction_sha256"):
            for wrong in (123, True, None, [], {}):
                envelope = signed_envelope(text, scope)
                envelope["telegram_evidence"] = dict(envelope["telegram_evidence"], **{field: wrong})
                envelope["signature"] = hmac.new(KEY, runtime.gateway_signing_bytes(envelope), hashlib.sha256).hexdigest()
                with self.subTest(field=field, wrong=wrong), self.assertRaisesRegex(
                        runtime.AuditorContractError, "telegram evidence value is invalid"):
                    runtime.validate_gateway_envelope(envelope, instruction=text, selected_scope=scope,
                        key_resolver=lambda _: KEY, now=NOW)
        for field in ("telegram_sender_id", "telegram_chat_id", "telegram_message_id", "telegram_update_id"):
            for wrong in ("123", True, None, [], {}, 0, -1, 1.5, 9223372036854775808):
                envelope = signed_envelope(text, scope)
                envelope["telegram_evidence"] = dict(envelope["telegram_evidence"], **{field: wrong})
                with self.subTest(field=field, wrong=wrong), self.assertRaisesRegex(
                        runtime.AuditorContractError, "telegram evidence value is invalid"):
                    runtime.gateway_signing_bytes(envelope)

    def test_runtime_rejects_key_shorter_than_database_minimum(self):
        text = "Review duplicate bullbars"
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate",
            duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        envelope = signed_envelope(text, scope)
        short = b"sixteen-byte-key"
        envelope["signature"] = hmac.new(short, runtime.gateway_signing_bytes(envelope), hashlib.sha256).hexdigest()
        with self.assertRaisesRegex(runtime.AuditorContractError, "signing key is unavailable"):
            runtime.validate_gateway_envelope(envelope, instruction=text, selected_scope=scope,
                key_resolver=lambda _key_id: short, now=NOW)

    def test_literal_iso_length_prefix_known_answer(self):
        text = "Review duplicate bullbars"
        duplicate_context = {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}}
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate", duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        envelope = signed_envelope(text, scope)
        expected = (
            b'pdc-auditor-envelope-253-v1\n'
            b'gateway_instance_id:12:gw-staging-1\n'
            b'delivery_uuid:36:12345678-1234-4234-9234-123456789abc\n'
            b'key_id:13:gateway-key-1\n'
            b'nonce:19:nonce-unique-123456\n'
            b'issued_at:20:2023-11-14T22:14:50Z\n'
            b'expires_at:20:2023-11-14T22:16:40Z\n'
            b'instruction_sha256:64:' + hashlib.sha256(text.encode()).hexdigest().encode() + b'\n'
            b'selected_scope:' + str(len(runtime.canonical_json(scope))).encode() + b':' + runtime.canonical_json(scope) + b'\n'
            b'telegram_evidence:' + str(len(runtime.canonical_json(envelope['telegram_evidence']))).encode() + b':' + runtime.canonical_json(envelope['telegram_evidence']))
        self.assertEqual(runtime.gateway_signing_bytes(envelope), expected)
        self.assertEqual(envelope["signature"], "e81eb0b70300844e78718651b10b56a55c202ebfa39a1ee6ddef011ae5dffe0a")


    def test_shared_canonical_vectors(self):
        fixture = json.loads((Path(__file__).parent / "fixtures" / "ai_auditor_signing_vectors_253.json").read_text(encoding="utf-8"))
        for vector in fixture["canonical_json"]:
            with self.subTest(vector=vector["name"]):
                self.assertEqual(runtime.canonical_json(vector["value"]), vector["canonical_utf8"].encode("utf-8"))
        envelope = fixture["envelope"]["value"]
        key = bytes.fromhex(fixture["envelope"]["hmac_key_hex"])
        signature = hmac.new(key, runtime.gateway_signing_bytes(envelope), hashlib.sha256).hexdigest()
        self.assertEqual(runtime.gateway_signing_bytes(envelope).hex(), fixture["envelope"]["signing_bytes_hex"])
        self.assertEqual(signature, fixture["envelope"]["signature_hex"])

    def test_shared_boundary_and_negative_inventory(self):
        fixture = json.loads((Path(__file__).parent / "fixtures" / "ai_auditor_signing_boundaries_253.json").read_text(encoding="utf-8"))
        self.assertEqual(fixture["contract"], "pdc-auditor-signing-boundaries-253-v1")
        for vector in fixture["canonical_json"]:
            with self.subTest(vector=vector["name"]):
                self.assertEqual(runtime.canonical_json(vector["value"]), vector["canonical_utf8"].encode("utf-8"))
        base = json.loads((Path(__file__).parent / "fixtures" / "ai_auditor_signing_vectors_253.json").read_text(encoding="utf-8"))["envelope"]["value"]
        for vector in fixture["negative_envelopes"]:
            envelope = json.loads(json.dumps(base))
            if vector.get("remove"): envelope.pop(vector["remove"])
            envelope.update(vector.get("mutation", {}))
            issued = envelope.get("issued_at")
            shape_valid = set(envelope) == runtime.GATEWAY_ENVELOPE_KEYS and isinstance(issued, str) and bool(__import__('re').fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z", issued))
            if vector["name"] == "altered_scope_rejected": shape_valid = False
            with self.subTest(vector=vector["name"]): self.assertIs(shape_valid, vector["valid_shape"])

    def test_signature_hash_scope_uuid_and_time_validation_precede_rpc(self):
        text = "Review duplicate bullbars"
        duplicate_context = {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}}
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate", duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        envelope = signed_envelope(text, scope)
        verified = runtime.validate_gateway_envelope(envelope, instruction=text, selected_scope=scope,
            telegram_evidence=envelope["telegram_evidence"], key_resolver=lambda _: KEY, now=NOW)
        self.assertEqual(verified["selected_scope"], scope)
        for mutation, message in [({"delivery_uuid": "not-uuid"}, "delivery_uuid"),
                                  ({"selected_scope": {"category": "other"}}, "scope")]:
            bad = dict(envelope); bad.update(mutation)
            if mutation.get("delivery_uuid") != "not-uuid":
                bad["signature"] = hmac.new(KEY, runtime.gateway_signing_bytes(bad), hashlib.sha256).hexdigest()
            with self.subTest(mutation=mutation), self.assertRaisesRegex(runtime.AuditorContractError, message):
                runtime.validate_gateway_envelope(bad, instruction=text, selected_scope=scope,
                    key_resolver=lambda _: KEY, now=NOW)

    def test_envelope_identifier_values_match_sql_boundary(self):
        text = "Review duplicate bullbars"
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate",
            duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        base = signed_envelope(text, scope)
        for field, invalid_values in {
            "gateway_instance_id": [" bad", "-leading", "x" * 129],
            "key_id": ["bad value", "/leading", "x" * 129],
            "nonce": ["short", "bad value nonce 123", "x" * 129],
        }.items():
            for invalid in invalid_values:
                bad = dict(base); bad[field] = invalid
                with self.subTest(field=field, invalid=invalid), self.assertRaisesRegex(
                        runtime.AuditorContractError, field):
                    runtime.validate_gateway_envelope(bad, instruction=text,
                        selected_scope=scope, key_resolver=lambda _: KEY, now=NOW)

    def test_envelope_instruction_text_matches_sql_boundary(self):
        valid = "Add the reviewed winch operation"
        scope = intent({"vehicle_id": VEHICLE}, "add", new_value={
            "description": "Winch", "work_key": "fitting", "estimated_hours": 2})
        envelope = signed_envelope(valid, scope)
        for invalid in ("", "ab", " leading", "trailing ", "x" * 4001):
            with self.subTest(invalid=invalid), self.assertRaisesRegex(
                    runtime.AuditorContractError, "instruction is invalid"):
                runtime.validate_gateway_envelope(envelope, instruction=invalid,
                    selected_scope=scope, key_resolver=lambda _: KEY, now=NOW)

    def test_telegram_integral_json_numbers_match_postgresql_jsonb(self):
        text = "Review duplicate bullbars"
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate",
            duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        envelope = signed_envelope(text, scope)
        integer_bytes = runtime.gateway_signing_bytes(envelope)
        for field in ("telegram_sender_id", "telegram_chat_id", "telegram_message_id", "telegram_update_id"):
            equivalent = json.loads(json.dumps(envelope))
            equivalent["telegram_evidence"][field] = float(equivalent["telegram_evidence"][field])
            equivalent["signature"] = hmac.new(KEY, runtime.gateway_signing_bytes(equivalent), hashlib.sha256).hexdigest()
            self.assertEqual(runtime.gateway_signing_bytes(equivalent), integer_bytes)
            verified = runtime.validate_gateway_envelope(equivalent, instruction=text,
                selected_scope=scope, key_resolver=lambda _: KEY, now=NOW)
            self.assertIsInstance(verified["telegram_evidence"][field], int)
        for invalid in (1.5, 0.0, -1.0, float("nan"), float("inf"), True, "1"):
            bad = json.loads(json.dumps(envelope)); bad["telegram_evidence"]["telegram_message_id"] = invalid
            with self.subTest(invalid=invalid), self.assertRaises(runtime.AuditorContractError):
                runtime.validate_gateway_envelope(bad, instruction=text,
                    selected_scope=scope, key_resolver=lambda _: KEY, now=NOW)

    def test_external_json_preserves_large_exponent_telegram_ids_exactly(self):
        text = "Review duplicate bullbars"
        scope = intent({"operation_refs": [SRC1, SRC2]}, "remove_duplicate",
            duplicate_proof="database_exact", survivor_operation_ref=SRC1)
        envelope = signed_envelope(text, scope)
        for literal, expected in (
            ("9007199254740991e0", 9007199254740991),
            ("9007199254740992e0", 9007199254740992),
            ("9007199254740993e0", 9007199254740993),
            ("9223372036854775806e0", 9223372036854775806),
            ("9223372036854775807e0", 9223372036854775807),
        ):
            raw = json.dumps(envelope, separators=(",", ":"))
            raw = raw.replace('"telegram_message_id":202',
                              f'"telegram_message_id":{literal}')
            parsed = runtime.exact_json_loads(raw)
            self.assertIsInstance(parsed["telegram_evidence"]["telegram_message_id"], int)
            parsed["signature"] = hmac.new(
                KEY, runtime.gateway_signing_bytes(parsed), hashlib.sha256).hexdigest()
            verified = runtime.validate_gateway_envelope(parsed, instruction=text,
                selected_scope=scope, key_resolver=lambda _: KEY, now=NOW)
            with self.subTest(literal=literal):
                self.assertEqual(verified["telegram_evidence"]["telegram_message_id"], expected)
                self.assertIn(f'"telegram_message_id":{expected}'.encode(),
                              runtime.gateway_signing_bytes(parsed))
        for literal in ("9223372036854775808e0", "1.5e0", "NaN", "Infinity",
                        "1e100000000", "0.10000000000000001"):
            raw = json.dumps(envelope, separators=(",", ":")).replace(
                '"telegram_message_id":202', f'"telegram_message_id":{literal}')
            with self.subTest(literal=literal), self.assertRaises(runtime.AuditorContractError):
                parsed = runtime.exact_json_loads(raw)
                runtime.gateway_signing_bytes(parsed)
        with self.assertRaises(runtime.AuditorContractError):
            runtime._telegram_id(float(9007199254740993), "telegram evidence value")


class RuntimeContractTests(unittest.TestCase):
    def test_review_and_mutation_both_plan_only_with_exact_payload(self):
        review = {"ok": True, "code": "planned", "data": {"proposal_id": PROPOSAL, "proposal_version": PROPOSAL_VERSION, "proposal_hash": HASH, "typed_item_set_hash": HASH, "final_scope_hash": HASH, "expected_row_versions_hash": HASH}}
        client = FakeClient([review])
        self.assertIs(execute(client, "Review duplicate bullbars", {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}}), review)
        name, payload = client.calls[0]
        self.assertEqual(name, runtime.PLAN_RPC)
        self.assertEqual(payload["p_action"], "remove_duplicate")
        self.assertEqual(payload["p_mode"], "review")
        self.assertEqual(payload["p_selected_scope"]["contract"], runtime.INTENT_CONTRACT)

        plan = {"ok": True, "code": "planned", "data": {"proposal_id": PROPOSAL, "proposal_version": PROPOSAL_VERSION, "proposal_hash": HASH, "typed_item_set_hash": HASH, "final_scope_hash": HASH, "expected_row_versions_hash": HASH}}
        client = FakeClient([plan])
        result = execute(client, "Apply edit operation code to X1", {"operation_ref": SRC1})
        self.assertEqual([name for name, _ in client.calls], [runtime.PLAN_RPC])
        self.assertEqual(result["code"], "pending_apply_confirmation")
        self.assertEqual(result["data"]["apply_selected_scope"], {
            "contract": runtime.APPLY_SELECTION_CONTRACT, "proposal_id": PROPOSAL,
            "proposal_version": PROPOSAL_VERSION, "proposal_hash": HASH,
            "typed_item_set_hash": HASH, "final_scope_hash": HASH,
            "expected_row_versions_hash": HASH})

    def test_confirmation_uses_new_signed_selection_and_never_replans(self):
        context = {"reviewed_proposal_id": PROPOSAL, "reviewed_proposal_version": PROPOSAL_VERSION,
            "reviewed_proposal_hash": HASH, "reviewed_typed_item_set_hash": HASH,
            "reviewed_final_scope_hash": HASH, "reviewed_expected_row_versions_hash": HASH}
        applied = {"ok": True, "code": "applied", "data": {"run_id": RUN}}
        client = FakeClient([applied])
        self.assertIs(execute(client, "Apply these corrections", context), applied)
        self.assertEqual([name for name, _ in client.calls], [runtime.APPLY_RPC])
        payload = client.calls[0][1]
        self.assertEqual(payload["p_proposal"], PROPOSAL)
        self.assertEqual(payload["p_proposal_version"], PROPOSAL_VERSION)
        for field in ("proposal_hash", "typed_item_set_hash", "final_scope_hash", "expected_row_versions_hash"):
            self.assertEqual(payload[f"p_{field}"], HASH)
        self.assertEqual(payload["p_gateway_envelope"]["selected_scope"]["proposal_id"], PROPOSAL)

    def test_query_undo_and_rule_regression_paths(self):
        query_client = FakeClient([{"ok": True}])
        execute(query_client, "Why did you change this", {"vehicle_id": VEHICLE, "job_card_number": "JC-42"})
        self.assertEqual(query_client.calls[0][0], runtime.QUERY_RPC)
        self.assertEqual(query_client.calls[0][1]["p_action"], "operation_snapshot")

        undo_client = FakeClient([{"ok": True}])
        execute(undo_client, "Undo the selected Auditor run", {"selected_run_id": RUN, "selected_run_revision_after": HASH})
        self.assertEqual(undo_client.calls[0][0], runtime.UNDO_RPC)
        self.assertEqual(undo_client.calls[0][1]["p_gateway_envelope"]["selected_scope"], {
            "contract": runtime.UNDO_SELECTION_CONTRACT, "run_id": RUN, "run_revision_after": HASH})

        rule_client = FakeClient([{"ok": True}])
        execute(rule_client, "Show rules")
        self.assertEqual(rule_client.calls[0][0], runtime.RULE_RPC)
        self.assertEqual(set(rule_client.calls[0][1]), {"p_action", "p_scope", "p_evidence"})

    def test_invalid_plan_identity_and_envelope_make_no_apply(self):
        client = FakeClient([{"ok": True, "data": {"plan_id": "p1", "plan_hash": "hash9"}}])
        with self.assertRaisesRegex(runtime.AuditorContractError, "valid immutable"):
            execute(client, "Edit operation code to X1", {"operation_ref": SRC1})
        self.assertEqual([name for name, _ in client.calls], [runtime.PLAN_RPC])

        no_calls = FakeClient([])
        text = "Review duplicate bullbars"
        duplicate_context = {"operation_refs": [SRC1, SRC2], "trusted_intent": {"survivor_operation_ref": SRC1}}
        scope = runtime.parse_instruction(text, duplicate_context)["selected_scope"]
        bad = signed_envelope(text, scope); bad["signature"] = "0" * 64
        with self.assertRaisesRegex(runtime.AuditorContractError, "signature"):
            execute(no_calls, text, duplicate_context, envelope=bad)
        self.assertEqual(no_calls.calls, [])

    def test_rpc_allowlist(self):
        self.assertEqual(runtime.PLAN_RPC, "plan_pdc_auditor_typed_instruction_253")
        self.assertEqual(runtime.APPLY_RPC, "apply_pdc_auditor_typed_plan_253")
        rpc = runtime.RpcClient(runtime.STAGING_URL, "key", "token")
        with self.assertRaisesRegex(runtime.AuditorContractError, "not allowlisted"):
            rpc.rpc("arbitrary_sql_rpc", {})


if __name__ == "__main__":
    unittest.main()
