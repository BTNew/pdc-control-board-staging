from __future__ import annotations

import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
CALLER = ROOT / "pdc_historical_778_caller.py"
IMPORTER = ROOT / "pdc_full_inbox_typed_import.py"
M789 = ROOT / "supabase/staging_only/20260830190000_789_historical_proposal_binding_successor.sql"
M796 = ROOT / "supabase/staging_only/20260830203000_796_historical_domain_readback_guard_successor.sql"
ROWS = Path("C:/Users/nwmgr/AppData/Local/hermes/profiles/pdc-emails/data/pdc-email-reviewer/historical-inbox/historical-778-rows.json")


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def explicit_manifest_rows() -> list[dict]:
    rows = json.loads(ROWS.read_text(encoding="utf-8"))["rows"]
    return [
        {
            **row,
            "manifest_uidvalidity": 1,
            "manifest_high_water_uid": 685,
            "manifest_uid_count": 669,
        }
        for row in rows
    ]


def success_response(request: dict) -> dict:
    import pdc_historical_778_caller as caller
    uid = int(request["provider_uid"].split(":", 1)[1])
    receipt_id = f"11111111-1111-4111-8111-{uid:012x}"
    intake_id = f"22222222-2222-4222-8222-{uid:012x}"
    proposal_id = f"33333333-3333-4333-8333-{uid:012x}"
    children = []
    for child in request["job_card_children"]:
        operation_count = len(child["extraction"].get("operation_lines", []))
        child_receipt_id = f"55555555-5555-4555-8555-{uid:012x}"
        child_attachment_id = f"66666666-6666-4666-8666-{uid:012x}"
        child_vehicle_id = f"44444444-4444-4444-8444-{uid:012x}"
        child_backend_id = f"88888888-8888-4888-8888-{uid:012x}"
        child_source_uid = f"pdc-jc-159:{caller._sha256((intake_id + ':' + child_attachment_id + ':' + request['parent_source_hash'] + ':' + child['attachment_hash']).encode('utf-8'))}"
        child_operation_lines = [{
            "source_row_no": line["source_row_no"], "operation_no": line["operation_no"],
            "operation_line_id": f"99999999-9999-4999-8999-{uid * 100 + line['source_row_no']:012x}",
            "work_key": line["work_key"], "description": line["description"],
            "estimated_hours": None, "estimated_hours_source": "owner_supplied_document_unknown",
        } for line in child["extraction"].get("operation_lines", [])]
        child_canonical_source_hash = caller._length_prefixed_sha256(["pdc-attachment-canonical-source", "233.1", intake_id, child_attachment_id, request["parent_source_hash"], child["attachment_hash"]])
        child_requested_payload = {
            "contract_version": "159.1", "actor_id": caller.ACTOR_ID, "intake_id": intake_id,
            "attachment_id": child_attachment_id, "parent_source_hash": request["parent_source_hash"],
            "attachment_source_hash": child["attachment_hash"], "source_uid": child_source_uid,
            "authentication": request["authentication"], "email_vehicle": child["extraction"].get("email_vehicle", {}),
            "required_work": child["extraction"].get("required_work", []), "operation_lines": child["extraction"].get("operation_lines", []),
        }
        children.append({
            "attachment_ordinal": child["attachment_ordinal"],
            "attachment_hash": child["attachment_hash"],
            "result": {"ok": True, "code": "jobcard_attachment_receipt", "data": {
                "receipt_id": child_receipt_id, "intake_id": intake_id,
                "attachment_id": child_attachment_id,
                "parent_source_hash": request["parent_source_hash"],
                "canonical_source_hash": child_canonical_source_hash, "attachment_source_hash": child["attachment_hash"],
                "attachment_size_bytes": next(item["size"] for item in request["attachment_manifest"] if item["ordinal"] == child["attachment_ordinal"]), "attachment_content_type": "application/pdf",
                "source_uid": child_source_uid, "proposal_id": proposal_id,
                "canonical_import_receipt_id": f"77777777-7777-4777-8777-{uid:012x}",
                "vehicle_id": child_vehicle_id, "vehicle_version": 1,
                "backend_record_id": child_backend_id, "backend_record_version": 1,
                "job_card_number": child["extraction"].get("email_vehicle", {}).get("job_card_number", "J1"),
                "requested_payload_sha256": caller._sha256(caller._postgres_jsonb_text(child_requested_payload).encode("utf-8")),
                "operation_sha256": caller._sha256(caller._postgres_jsonb_text(child_operation_lines).encode("utf-8")),
                "operation_count": operation_count, "estimated_hours_sum": 0,
                "canonical_operation_line_ids": [line["operation_line_id"] for line in child_operation_lines], "operation_lines": child_operation_lines,
                "rule_applications": [],
                "canonical_import_response": {
                    "observation": {"ok": True, "code": "already_noticed", "data": {
                        "proposal_id": proposal_id, "status": "pending", "version": 1, "fingerprint": "ABCDEF0123456789",
                        "auto_activation": {"ok": True, "code": "automatically_closed_existing", "data": {
                            "proposal_id": proposal_id, "stock_number": request["stock_number"], "vehicle_id": child_vehicle_id,
                            "vehicle_mutated": False, "board_activation_only": False, "authority_refreshed": False,
                            "proposal_backend_record_version": 1, "current_backend_record_version": 1,
                            "authorization_basis": "enrolled_monitor_and_live_server_identity", "board_purge_reactivation": False,
                        }},
                    }},
                    "vehicle_import": {"ok": True, "code": "canonical_receipt_and_work_imported", "data": {
                        "vehicle_id": child_vehicle_id, "backend_record_id": child_backend_id, "stock_number": request["stock_number"],
                        "job_card_number": child["extraction"].get("email_vehicle", {}).get("job_card_number"),
                        "required_work": child["extraction"].get("required_work", []), "identity_source": "navision_exact",
                        "booking_created": False, "completed_work_reopened": False,
                    }},
                    "operation_import": {"ok": True, "code": "operation_lines_and_hours_already_imported", "data": {
                        "vehicle_id": child_vehicle_id, "source_hash": child_canonical_source_hash,
                        "operation_lines_received": operation_count, "operation_lines_added": 0,
                        "estimated_hours_added": 0, "job_card_hours_corrected": 0, "required_work_added": 0,
                        "resulting_revision": 1, "booking_created": False, "completed_work_reopened": False,
                    }},
                    "booking_created": False, "completion_created": False, "location_scheduled": False,
                },
                "booking_created": False, "completion_created": False, "location_scheduled": False,
            }},
            "authoritative_vehicle_id": child_vehicle_id,
            "authoritative_operation_count": operation_count,
        })
    manifest = request["attachment_manifest"]
    return {"ok": True, "code": "historical_reconciliation_782_receipt", "data": {
        "receipt_id": receipt_id, "contract_version": "778.1",
        "manifest_sha256": request["manifest_sha256"], "provider_uid": request["provider_uid"],
        "parent_source_hash": request["parent_source_hash"], "sender_email": request["sender_email"],
        "stock_number": request["stock_number"], "intake_id": intake_id,
        "attachment_count": len(manifest), "proposal_id": proposal_id,
        "proposal_binding_kind": "pending_proposal_observation_match", "proposal_observation_match": True,
        "job_card_count": sum(item["attachment_kind"] == "job_card" for item in manifest),
        "sibling_count": sum(item["attachment_kind"] != "job_card" for item in manifest),
        "attachment_receipts": children,
        "parent_observation": {"ok": True, "code": "already_noticed", "data": {"proposal_id": proposal_id, "status": "pending", "version": 1, "fingerprint": "ABCDEF0123456789"}},
        "authoritative_state": {"vehicle_id": children[0]["authoritative_vehicle_id"] if children else None,
            "lifecycle_state": "active" if children else None, "current_location": None,
            "operation_count": sum(item["authoritative_operation_count"] for item in children),
            "booking_count": 0, "completion_count": 0, "parts_changed": False},
        "authoritative_domain_state": {
            "vehicle": ({
                "vehicle_id": children[0]["authoritative_vehicle_id"], "lifecycle_state": "active", "current_location": None,
                "version": 1, "deleted_at": None, "board_purged_at": None, "rft_transferred_at": None,
                "rft_collected_at": None, "rft_confirmed_at": None, "rft_transport_booked_at": None,
                "dealer_transit_started_at": None, "dealer_transit_closed_at": None, "dealer_transit_duration_seconds": None,
                "delivered_to_dealer_date": None, "qc_completed_at": None, "workshop_status": "queued",
            } if children else None),
            "parts": {"rows": [], "fingerprint": "00000000000000000000000000000000"},
            "sublet": {"bookings": [], "instances": [], "fingerprint": "00000000000000000000000000000000"},
            "qc": {"rows": [], "fingerprint": "00000000000000000000000000000000"},
            "rft_transport": {"rows": [], "fingerprint": "00000000000000000000000000000000"},
            "protected_fingerprints": {
                "vehicle": "00000000000000000000000000000000", "lifecycle_location": "00000000000000000000000000000000",
                "parts": "00000000000000000000000000000000", "sublet": "00000000000000000000000000000000",
                "qc": "00000000000000000000000000000000", "rft_transport": "00000000000000000000000000000000",
                "all": "00000000000000000000000000000000",
            },
        },
        "booking_created": False, "completion_created": False, "location_scheduled": False,
        "parts_changed": False, "status_changed": False, "no_booking": True, "no_completion": True,
        "no_location_mutation": True,
    }}


class HistoricalProposalBinding789Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.caller = load(CALLER, "historical_proposal_binding_caller")
        sys.modules["pdc_historical_778_caller"] = cls.caller
        cls.importer = load(IMPORTER, "historical_proposal_binding_importer")

    def test_migration_is_append_only_after_788_and_has_immutable_binding_contract(self):
        sql = M789.read_text(encoding="utf-8").lower()
        self.assertEqual(len(parse_sql(M789.read_text(encoding="utf-8"))), 24)
        for marker in (
            "20260830185000",
            "pdc_historical_proposal_bindings_789",
            "historical_proposal_tuple_conflict",
            "historical_proposal_terminal_conflict",
            "pending_proposal_observation_mismatch",
            "pdc_789_proposal_binding_immutable",
            "request_sha256",
            "observation_match",
            "proposal_observations",
            "revoke all on table public.pdc_historical_proposal_bindings_789",
            "relforcerowsecurity",
            "pdc_789_current_head_guard_failed",
            "where proposal_id=v_proposal_id for update",
            "historical_proposal_payload_conflict",
            "where source_hash=lower(p_request->>'parent_source_hash')",
            "limit 1 for update",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn("update public.pdc_ai_intake_proposals", sql)
        self.assertNotIn("delete from public.pdc_ai_intake_proposals", sql)
        self.assertNotIn("update public.pdc_historical_proposal_bindings_789", sql)
        self.assertNotIn("delete from public.pdc_historical_proposal_bindings_789", sql)

    def test_796_is_append_only_server_guard_and_complete_domain_readback_contract(self):
        sql = M796.read_text(encoding="utf-8").lower()
        self.assertEqual(len(parse_sql(M796.read_text(encoding="utf-8"))), 27)
        for marker in (
            "20260830203000",
            "pdc_historical_domain_readbacks_796",
            "pdc_historical_796_domain_snapshot",
            "historical_terminal_or_protected_location",
            "pdc_796_protected_domain_drift",
            "parts_required",
            "parts_ordered",
            "parts_received",
            "parts_stoppage",
            "pdc_sublet_booking_instances",
            "pdc_qc_operation_completions_379",
            "pdc_rft_transport_email_outbox_734",
            "before_protected_fingerprints",
            "after_protected_fingerprints",
            "force row level security",
            "revoke all on table public.pdc_historical_domain_readbacks_796",
            "submit_pdc_historical_reconciliation_778_pre796",
            "historical_terminal_or_protected_location",
            "pdc_796_terminal_readback_failed",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn("update public.pdc_historical_reconciliation_778_receipts", sql)
        self.assertNotIn("delete from public.pdc_historical_reconciliation_778_receipts", sql)

    def test_frozen_uid_1_21_is_the_regression_input(self):
        row = next(item for item in explicit_manifest_rows() if item["provider_uid"] == "1:21")
        request = self.caller.build_historical_request(row)
        self.assertEqual(request["provider_uid"], "1:21")
        self.assertEqual(request["stock_number"], "13042997")
        self.assertEqual(self.caller.canonical_request_digest(request), "fd784959b016976994087545866e346f01b6f05e1e0faf8627bda25ed9e84550")

    def test_bounded_caller_rejects_missing_or_extra_frozen_uid(self):
        rows = explicit_manifest_rows()
        with self.assertRaises(self.importer.Historical777Error):
            self.importer.select_authorized_rows(rows[:-1])
        with self.assertRaises(self.importer.Historical777Error):
            self.importer.select_authorized_rows(rows + [dict(rows[0])])
        extra = dict(rows[0])
        extra["provider_uid"] = "1:999"
        with self.assertRaises(self.importer.Historical777Error):
            self.importer.select_authorized_rows(rows[:-1] + [extra])

    def test_shared_caller_rejects_missing_or_extra_frozen_uid(self):
        rows = explicit_manifest_rows()
        with self.assertRaises(self.caller.Historical777Error):
            self.caller.select_authorized_rows(rows[:-1])
        with self.assertRaises(self.caller.Historical777Error):
            self.caller.select_authorized_rows(rows + [dict(rows[0])])

    def test_shared_runner_persists_false_and_returns_nonzero_summary(self):
        rows = explicit_manifest_rows()
        with tempfile.TemporaryDirectory() as directory:
            connection = self.caller.prepare_fresh_outbox(Path(directory) / "shared-caller-outbox.sqlite3")
            try:
                results = self.caller.run_bounded_historical(
                    rows,
                    connection,
                    lambda request: {"ok": False, "code": "historical_proposal_tuple_conflict", "data": {"review_required": True}}
                    if request["provider_uid"] == "1:21" else success_response(request),
                )
                connection.row_factory = sqlite3.Row
                stored = connection.execute("select state,attempt_count,last_error_code,review_required from historical_778_outbox where provider_uid='1:21'").fetchone()
            finally:
                connection.close()
        self.assertEqual(next(item for item in results if item["provider_uid"] == "1:21")["state"], "review")
        self.assertEqual(dict(stored), {"state": "review", "attempt_count": 1, "last_error_code": "historical_proposal_tuple_conflict", "review_required": 1})
        self.assertEqual(self.caller.summarize_historical_results(results)["exit_code"], 1)

    def test_shared_cli_returns_nonzero_for_false_rpc_row(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
            self.caller,
            "invoke_historical_rpc",
            side_effect=lambda request, **kwargs: {"ok": False, "code": "historical_proposal_payload_conflict"}
            if request["provider_uid"] == "1:21" else success_response(request),
        ), patch.dict(os.environ, {
            "PDC_STAGING_SUPABASE_URL": "https://cdsmnqxtyyoeoznmbidd.supabase.co",
            "PDC_STAGING_SUPABASE_ANON_KEY": "test-anon-key",
            "PDC_MONITOR_ACCESS_TOKEN": "test-token",
        }, clear=False):
            rows_path = Path(directory) / "explicit-rows.json"
            rows_path.write_text(json.dumps({"rows": explicit_manifest_rows()}), encoding="utf-8")
            exit_code = self.caller.main([
                "--rows-json", str(rows_path),
                "--outbox", str(Path(directory) / "shared-cli-outbox.sqlite3"),
                "--bounded-caller",
            ])
        self.assertEqual(exit_code, 1)

    def test_review_required_overrides_contradictory_ok_true(self):
        rows = explicit_manifest_rows()
        for module in (self.caller, self.importer):
            with tempfile.TemporaryDirectory() as directory:
                connection = module.prepare_fresh_outbox(Path(directory) / "contradictory-review-outbox.sqlite3")
                try:
                    results = module.run_bounded_historical(
                        rows,
                        connection,
                        lambda request: {"ok": True, "code": "historical_proposal_observation_review_required", "data": {"review_required": True}}
                        if request["provider_uid"] == "1:21" else success_response(request),
                    )
                finally:
                    connection.close()
            uid21 = next(item for item in results if item["provider_uid"] == "1:21")
            self.assertFalse(uid21["ok"])
            self.assertEqual(uid21["state"], "review")
            self.assertEqual(module.summarize_historical_results(results)["exit_code"], 1)

    def test_success_requires_exact_receipt_identity_and_authoritative_readback(self):
        rows = explicit_manifest_rows()
        request = self.caller.build_historical_request(next(item for item in rows if item["provider_uid"] == "1:22"))
        good = success_response(request)
        malformed = [
            {"ok": True},
            {"ok": True, "code": "arbitrary_success", "data": {}},
            {"ok": True, "code": "historical_reconciliation_782_receipt", "data": {}},
        ]
        missing_receipt = json.loads(json.dumps(good))
        missing_receipt["data"].pop("receipt_id")
        malformed.append(missing_receipt)
        bad_receipt = json.loads(json.dumps(good))
        bad_receipt["data"]["receipt_id"] = "not-a-uuid"
        malformed.append(bad_receipt)
        bad_identity = json.loads(json.dumps(good))
        bad_identity["data"]["provider_uid"] = "1:23"
        malformed.append(bad_identity)
        bad_proposal = json.loads(json.dumps(good))
        bad_proposal["data"]["parent_observation"]["data"]["proposal_id"] = "99999999-9999-4999-8999-999999999999"
        malformed.append(bad_proposal)
        bad_binding = json.loads(json.dumps(good))
        bad_binding["data"]["proposal_binding_kind"] = "pending_proposal_observation_mismatch"
        malformed.append(bad_binding)
        bad_occurrence = json.loads(json.dumps(good))
        bad_occurrence["data"]["attachment_receipts"][0]["attachment_ordinal"] = 3
        malformed.append(bad_occurrence)
        bad_unhashable_occurrence = json.loads(json.dumps(good))
        bad_unhashable_occurrence["data"]["attachment_receipts"][0]["attachment_ordinal"] = []
        bad_unhashable_occurrence["data"]["attachment_receipts"][0]["attachment_hash"] = {}
        malformed.append(bad_unhashable_occurrence)
        bad_child_code = json.loads(json.dumps(good))
        bad_child_code["data"]["attachment_receipts"][0]["result"]["code"] = "arbitrary_child_success"
        malformed.append(bad_child_code)
        bad_child_nested = json.loads(json.dumps(good))
        bad_child_nested["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"] = {}
        malformed.append(bad_child_nested)
        bad_nested_false = json.loads(json.dumps(good))
        bad_nested_false["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["operation_import"]["ok"] = False
        malformed.append(bad_nested_false)
        bad_nested_extra = json.loads(json.dumps(good))
        bad_nested_extra["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["vehicle_import"]["data"]["unexpected"] = True
        malformed.append(bad_nested_extra)
        bad_auto_backend = json.loads(json.dumps(good))
        bad_auto_backend["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["observation"]["data"]["auto_activation"]["data"]["backend_record_id"] = "99999999-9999-4999-8999-999999999999"
        bad_auto_backend["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["observation"]["data"]["auto_activation"]["code"] = "automatically_applied"
        bad_auto_backend["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["observation"]["data"]["auto_activation"]["data"] = {
            "proposal_id": good["data"]["proposal_id"], "stock_number": request["stock_number"], "backend_record_id": "99999999-9999-4999-8999-999999999999",
            "vehicle_id": good["data"]["attachment_receipts"][0]["result"]["data"]["vehicle_id"], "navision_revision": 1,
            "vehicle_mutated": True, "authority_refreshed": False, "proposal_backend_record_version": 1,
            "current_backend_record_version": 1, "board_activation_only": True, "booking_created": False,
            "work_mutated": False, "parts_mutated": False, "authorization_basis": "enrolled_monitor_and_live_server_identity",
            "board_purge_reactivation": False,
        }
        malformed.append(bad_auto_backend)
        bad_auto_mutated = json.loads(json.dumps(good))
        bad_auto_mutated["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["observation"]["data"]["auto_activation"]["data"]["vehicle_mutated"] = True
        malformed.append(bad_auto_mutated)
        bad_child_duplicate = json.loads(json.dumps(good))
        child_data = bad_child_duplicate["data"]["attachment_receipts"][0]["result"]["data"]
        child_data["canonical_import_receipt_id"] = child_data["receipt_id"]
        malformed.append(bad_child_duplicate)
        bad_hours = json.loads(json.dumps(good))
        bad_hours["data"]["attachment_receipts"][0]["result"]["data"]["operation_lines"][0]["estimated_hours"] = 1
        bad_hours["data"]["attachment_receipts"][0]["result"]["data"]["operation_lines"][0]["estimated_hours_source"] = "job_card"
        malformed.append(bad_hours)
        bad_auto = json.loads(json.dumps(good))
        bad_auto["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_response"]["observation"]["data"]["auto_activation"]["ok"] = False
        malformed.append(bad_auto)
        bad_aggregate = json.loads(json.dumps(good))
        bad_aggregate["data"]["authoritative_state"]["operation_count"] += 1
        malformed.append(bad_aggregate)
        missing_readback = json.loads(json.dumps(good))
        missing_readback["data"].pop("authoritative_state")
        malformed.append(missing_readback)
        for module in (self.caller, self.importer):
            for response in malformed:
                with self.assertRaises(module.Historical777Error):
                    module.validate_success_response(request, response, module.canonical_request_digest(request))
            with self.assertRaises(module.Historical777Error):
                module.validate_success_response(request, good, "0" * 64)
            module.validate_success_response(request, good, module.canonical_request_digest(request))
            ambiguous = json.loads(json.dumps(good))
            ambiguous["data"]["attachment_receipts"] = [{
                "attachment_ordinal": request["job_card_children"][0]["attachment_ordinal"],
                "attachment_hash": request["job_card_children"][0]["attachment_hash"],
                "result": {"ok": False, "code": "historical_child_ambiguous"},
            }]
            ambiguous["data"]["authoritative_state"].update({"vehicle_id": None, "lifecycle_state": None, "current_location": None, "operation_count": 0})
            ambiguous["data"]["authoritative_domain_state"]["vehicle"] = None
            ambiguous_request = json.loads(json.dumps(request))
            ambiguous_request["job_card_children"][0]["attachment_kind"] = "ambiguous_job_card"
            module.validate_success_response(ambiguous_request, ambiguous, module.canonical_request_digest(ambiguous_request))
            with tempfile.TemporaryDirectory() as directory:
                connection = module.prepare_fresh_outbox(Path(directory) / "malformed-receipt.sqlite3")
                try:
                    def malformed_rpc(row_request):
                        response = success_response(row_request)
                        if row_request["provider_uid"] == "1:22":
                            response["data"]["attachment_receipts"][0]["attachment_ordinal"] = []
                        return response
                    malformed_results = module.run_bounded_historical(rows, connection, malformed_rpc)
                finally:
                    connection.close()
            malformed_row = next(item for item in malformed_results if item["provider_uid"] == "1:22")
            self.assertEqual(malformed_row["state"], "retry")
            self.assertFalse(malformed_row["ok"])
            with tempfile.TemporaryDirectory() as directory:
                connection = module.prepare_fresh_outbox(Path(directory) / "serialization-outbox.sqlite3")
                try:
                    def unserializable_rpc(row_request):
                        response = success_response(row_request)
                        if row_request["provider_uid"] == "1:22":
                            response["data"]["authoritative_state"]["current_location"] = {"unserializable"}
                        return response
                    serialization_results = module.run_bounded_historical(rows, connection, unserializable_rpc)
                    connection.row_factory = sqlite3.Row
                    stored_serialization = connection.execute("select state,attempt_count,last_error_code,review_required,response_json from historical_778_outbox where provider_uid='1:22'").fetchone()
                finally:
                    connection.close()
            serialization_row = next(item for item in serialization_results if item["provider_uid"] == "1:22")
            self.assertEqual(serialization_row["state"], "retry")
            self.assertFalse(serialization_row["ok"])
            self.assertEqual(dict(stored_serialization)["last_error_code"], "historical_response_not_json_serializable")
            self.assertIn("historical_response_not_json_serializable", dict(stored_serialization)["response_json"])
            with tempfile.TemporaryDirectory() as directory:
                connection = module.prepare_fresh_outbox(Path(directory) / "case-insensitive-receipt.sqlite3")
                try:
                    def duplicate_case_rpc(row_request, _calls=[0]):
                        _calls[0] += 1
                        response = success_response(row_request)
                        response["data"]["receipt_id"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA" if _calls[0] % 2 else "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
                        return response
                    duplicate_results = module.run_bounded_historical(rows, connection, duplicate_case_rpc)
                finally:
                    connection.close()
            self.assertEqual(sum(item["state"] == "retry" for item in duplicate_results), 14)

    def test_both_published_callers_contain_exact_receipt_safety_contract(self):
        caller_source = CALLER.read_text(encoding="utf-8")
        for marker in (
            "EXPECTED_SUCCESS_CODE = \"historical_reconciliation_782_receipt\"",
            "SUCCESS_RESPONSE_KEYS = frozenset({\"ok\", \"code\", \"data\"})",
            "historical success receipt envelope mismatch",
            "historical success receipt identity mismatch",
            "historical attachment occurrence readback mismatch",
            "historical authoritative state readback mismatch",
            "validate_success_response(request, response, request_hash, seen_identity_ids)",
        ):
            self.assertIn(marker, caller_source)
        importer_source = IMPORTER.read_text(encoding="utf-8")
        self.assertIn("validate_shared_success_response", importer_source)
        self.assertIn("def validate_success_response", importer_source)
        self.assertIn("validate_success_response(request, response, request_hash, seen_identity_ids)", importer_source)

    def test_global_identity_and_protected_lifecycle_location_guards(self):
        rows = explicit_manifest_rows()
        for module in (self.caller, self.importer):
            with tempfile.TemporaryDirectory() as directory:
                connection = module.prepare_fresh_outbox(Path(directory) / "global-identity-outbox.sqlite3")
                try:
                    def repeated_nested_identity_rpc(row_request):
                        response = success_response(row_request)
                        if row_request["job_card_children"]:
                            child_data = response["data"]["attachment_receipts"][0]["result"]["data"]
                            child_data["receipt_id"] = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
                            child_data["canonical_import_receipt_id"] = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
                        return response
                    repeated_results = module.run_bounded_historical(rows, connection, repeated_nested_identity_rpc)
                finally:
                    connection.close()
            nested_rows = sum(bool(item["job_card_children"]) for item in rows)
            self.assertEqual(sum(item["state"] == "imported" for item in repeated_results), len(rows) - nested_rows + 1)
            self.assertEqual(sum(item["state"] == "retry" for item in repeated_results), nested_rows - 1)

            request = module.build_historical_request(next(item for item in rows if item["provider_uid"] == "1:22"))
            good = success_response(request)
            cross_level = json.loads(json.dumps(good))
            cross_level["data"]["attachment_receipts"][0]["result"]["data"]["canonical_import_receipt_id"] = cross_level["data"]["receipt_id"]
            with self.assertRaises(module.Historical777Error):
                module.validate_success_response(request, cross_level, module.canonical_request_digest(request))
            for lifecycle_state, current_location in (("completed", None), ("deleted", None), ("active", "Completed"), ("active", "RFT"), ("active", "Delivered - At Dealer"), ("active", "DRIFTED")):
                mutated = json.loads(json.dumps(good))
                mutated["data"]["authoritative_state"]["lifecycle_state"] = lifecycle_state
                mutated["data"]["authoritative_state"]["current_location"] = current_location
                with self.assertRaises(module.Historical777Error):
                    module.validate_success_response(request, mutated, module.canonical_request_digest(request))
            for mutate in (
                lambda value: value["data"]["authoritative_domain_state"].pop("parts"),
                lambda value: value["data"]["authoritative_domain_state"]["parts"].update({"fingerprint": "not-a-fingerprint"}),
                lambda value: value["data"]["authoritative_domain_state"]["sublet"].update({"bookings": [{"unexpected": True}]}),
            ):
                mutated = json.loads(json.dumps(good))
                mutate(mutated)
                with self.assertRaises(module.Historical777Error):
                    module.validate_success_response(request, mutated, module.canonical_request_digest(request))

    def test_bounded_limit_validates_full_cohort_and_records_build_failure(self):
        rows = explicit_manifest_rows()
        for module in (self.caller, self.importer):
            bad_rows = [dict(row) for row in rows]
            bad_rows[0] = dict(bad_rows[0])
            bad_rows[0].pop("attachments")
            with tempfile.TemporaryDirectory() as directory:
                outbox_path = Path(directory) / "bounded-limit-outbox.sqlite3"
                connection = module.prepare_fresh_outbox(outbox_path)
                try:
                    results = module.run_bounded_historical(
                        bad_rows,
                        connection,
                        lambda request: {"ok": True, "code": "unexpected-rpc-call"},
                        limit=1,
                    )
                    connection.row_factory = sqlite3.Row
                    stored = connection.execute("select state,attempt_count,last_error_code,review_required from historical_778_outbox where provider_uid='1:21'").fetchone()
                finally:
                    connection.close()
            self.assertEqual(len(results), 1)
            self.assertEqual(results[0], {"provider_uid": "1:21", "state": "retry", "code": "historical row missing attachments", "ok": False})
            self.assertEqual(dict(stored), {"state": "retry", "attempt_count": 1, "last_error_code": "historical row missing attachments", "review_required": 0})
            self.assertEqual(module.summarize_historical_results(results)["exit_code"], 1)

    def test_live_probe_uses_validated_cohort_then_one_row(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(
            self.caller,
            "invoke_historical_rpc",
            side_effect=lambda request, **kwargs: success_response(request),
        ), patch.dict(os.environ, {
            "PDC_STAGING_SUPABASE_URL": "https://cdsmnqxtyyoeoznmbidd.supabase.co",
            "PDC_STAGING_SUPABASE_ANON_KEY": "test-anon-key",
            "PDC_MONITOR_ACCESS_TOKEN": "test-token",
        }, clear=False):
            rows_path = Path(directory) / "explicit-rows.json"
            rows_path.write_text(json.dumps({"rows": explicit_manifest_rows()}), encoding="utf-8")
            exit_code = self.caller.main([
                "--rows-json", str(rows_path),
                "--outbox", str(Path(directory) / "live-probe-outbox.sqlite3"),
                "--live-probe",
            ])
        self.assertEqual(exit_code, 0)

    def test_manifest_and_source_uid_fields_are_required_and_typed(self):
        valid = explicit_manifest_rows()
        manifest_variants = (
            ("manifest_uidvalidity", "missing"),
            ("manifest_uidvalidity", None),
            ("manifest_uidvalidity", "1"),
            ("manifest_uidvalidity", 2),
            ("manifest_high_water_uid", "missing"),
            ("manifest_high_water_uid", None),
            ("manifest_high_water_uid", "685"),
            ("manifest_high_water_uid", 684),
            ("manifest_uid_count", "missing"),
            ("manifest_uid_count", None),
            ("manifest_uid_count", "669"),
            ("manifest_uid_count", 668),
        )
        source_variants = (("missing", None), ("null", None), ("string", "1"), ("wrong", 2))
        for module in (self.caller, self.importer):
            for field, value in manifest_variants:
                candidate = [dict(row) for row in valid]
                if value == "missing":
                    candidate[0].pop(field)
                else:
                    candidate[0][field] = value
                with self.assertRaises(module.Historical777Error):
                    module.select_authorized_rows(candidate)
            for _, value in source_variants:
                candidate = [dict(row) for row in valid]
                candidate[0]["source_metadata"] = dict(candidate[0]["source_metadata"])
                if value == "missing":
                    candidate[0]["source_metadata"].pop("uidvalidity")
                else:
                    candidate[0]["source_metadata"]["uidvalidity"] = value
                with self.assertRaises(module.Historical777Error):
                    module.select_authorized_rows(candidate)
            candidate = [dict(row) for row in valid]
            candidate[0]["source_metadata"] = dict(candidate[0]["source_metadata"])
            candidate[0]["source_metadata"]["uid"] = "21"
            with self.assertRaises(module.Historical777Error):
                module.select_authorized_rows(candidate)

    def test_false_result_is_durable_review_and_nonzero_summary(self):
        rows = explicit_manifest_rows()
        with tempfile.TemporaryDirectory() as directory:
            outbox = Path(directory) / "new-789-outbox.sqlite3"
            connection = self.importer.prepare_fresh_outbox(outbox)
            try:
                results = self.importer.run_bounded_historical(
                    rows, connection,
                    lambda request: {"ok": False, "code": "historical_proposal_tuple_conflict", "data": {"review_required": True}}
                    if request["provider_uid"] == "1:21" else success_response(request),
                )
                connection.row_factory = sqlite3.Row
                stored = connection.execute("select state,attempt_count,last_error_code,review_required from historical_778_outbox where provider_uid='1:21'").fetchone()
            finally:
                connection.close()
        uid21 = next(item for item in results if item["provider_uid"] == "1:21")
        self.assertEqual(uid21["state"], "review")
        self.assertEqual(stored["state"], "review")
        self.assertEqual(stored["attempt_count"], 1)
        self.assertEqual(stored["last_error_code"], "historical_proposal_tuple_conflict")
        self.assertEqual(stored["review_required"], 1)
        self.assertEqual(self.importer.summarize_historical_results(results)["exit_code"], 1)

    def test_exact_replay_digest_and_request_are_unchanged(self):
        row = next(item for item in explicit_manifest_rows() if item["provider_uid"] == "1:21")
        first = self.caller.build_historical_request(row)
        second = self.caller.build_historical_request(row)
        self.assertEqual(first["canonical_request_utf8"], second["canonical_request_utf8"])
        self.assertEqual(self.caller.canonical_request_digest(first), self.caller.canonical_request_digest(second))


if __name__ == "__main__":
    unittest.main(verbosity=2)
