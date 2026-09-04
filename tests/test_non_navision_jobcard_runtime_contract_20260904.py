from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


runtime = load("pdc_jobcard_runtime_client", ROOT / "backend/pdc_jobcard_runtime_client_successor_20260904.py")
processor = load("email_intake_processor_successor_20260904", ROOT / "backend/email_intake_processor_successor_20260904.py")

AUTH = {
    "dkim_aligned": True,
    "dmarc_aligned": False,
    "gmail_authentication_results": True,
    "sender_domain": "pmgwa.com.au",
    "spf_aligned": True,
}


class NonNavisionCurrentRuntimeContractTests(unittest.TestCase):
    def test_stock_lookup_accepts_optional_authenticated_source_vin_and_normalizes_it(self):
        vehicle = {
            "cancelled": False,
            "conflicts": [],
            "customer_name": "Customer",
            "eta_to_kewdale": None,
            "job_card_number": "J138000812",
            "registration": "1HJX697",
            "stock_numbers": ["U158318"],
            "toyota_order_number": None,
            "vehicle_description": "Toyota Hiace",
            "vins": ["jtfhb8cp806024409"],
        }

        self.assertIs(runtime._email_vehicle(vehicle), vehicle)
        self.assertEqual(vehicle["vins"], ["JTFHB8CP806024409"])

    def test_runtime_accepts_explicit_zero_and_excludes_unknown_from_required_work(self):
        lines = [
            {"source_row_no": 1, "operation_no": "OP1", "work_key": "sublet", "description": "SUB Reflective Striping", "estimated_hours": 0.0},
            {"source_row_no": 2, "operation_no": "OP2", "work_key": "owner_supplied_document", "description": "Bespoke retained instruction", "estimated_hours": 1.0},
        ]
        self.assertIs(runtime._operation_lines(lines, ["sublet"]), lines)

    def test_runtime_rejects_missing_hours_instead_of_coercing_to_zero(self):
        lines = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "sublet", "description": "SUB Reflective Striping", "estimated_hours": None}]
        with self.assertRaisesRegex(runtime.RuntimeContractError, "finite number"):
            runtime._operation_lines(lines, ["sublet"])

    def test_runtime_accepts_unknown_only_job_card_with_no_required_work(self):
        lines = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "owner_supplied_document", "description": "OP 018 Bespoke retained instruction", "estimated_hours": 1.0}]
        self.assertIs(runtime._operation_lines(lines, []), lines)

    def test_processor_current_taxonomy_and_explicit_sub_evidence(self):
        self.assertEqual(processor.classify_job_line("SUB Reflective Striping")[0], "SUBLET")
        self.assertEqual(processor.classify_job_line("Wheel Nut Indicator Set")[0], "TYRE")
        self.assertEqual(processor.classify_job_line("Supply Fire Extinguisher")[0], "FABRICATION")
        self.assertEqual(processor.classify_job_line("PIT AND WEIGH")[0], "PIT_INSPECTION")
        self.assertEqual(processor.classify_job_line("External provider paint protection")[0], "SUBLET")
        self.assertEqual(processor.classify_job_line("Suspension weight upgrade")[0], "HOIST")
        self.assertEqual(processor.classify_job_line("!ELEC dual battery")[0], "ELECTRICAL")
        for description in (
            "OP 018: SUB Reflective Striping",
            "OP018 - SUB Reflective Striping",
            "OP#018 SUB Reflective Striping",
            "OP/018 SUB Reflective Striping",
        ):
            self.assertEqual(processor.classify_job_line(description)[0], "SUBLET")
        self.assertIsNone(processor.classify_job_line("OP 018 Bespoke retained instruction")[0])

    def test_u158318_exact_source_descriptions_match_approved_work_keys(self):
        operations = (
            ("BUS 4X4 CONVERSION SLWB & COMMUTER 05C2B", "bus4x4"),
            ("Bus 4x4 Conversion 5x BFG 265/65R17 Tyres and Rims", "tyre"),
            ("BUS 4X4 Tanami Snorkel", "bus4x4"),
            ("Hiace Rock Sliders", "fitting"),
            ("MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON -ACOT500", "electrical"),
            ("BATTERY ISOLATOR WITH RED LOCKOUT", "electrical"),
            ("175 AMP JUMP START UNDER BONNET", "electrical"),
            ("Headlamps Auto On & Hand Brake OFF Alarm -DYNAMCO", "electrical"),
            ("MMT COMMUTER SEAT COVERS -CANVAS", "fitting"),
            ("MOUNTED WHEEL CHOCKS AND HOLDER", "fitting"),
            ("SAFETY TRIANGLE IN PMB HOLDER", "fitting"),
            ("WHEEL NUT INDICATORS -COMMUTER", "tyre"),
            ("UHF GME XRS370C WITH AE4704B AERIAL", "electrical"),
            ("SUB REFLECTIVE STRIPING YELLOW", "sublet"),
            ("Darkest Legal Tint Commuter van", "tint"),
            ('NARVA (72843) 20" EX2-R LIGHT BAR RGB DOUBLE RGB ENABLED', "electrical"),
            ("POST REGO CONVERSION", "bus4x4"),
            ("2.5KG FIRE EXTINGUISHER", "fabrication"),
        )
        self.assertEqual(
            [processor.canonical_jobcard_work_key(description) for description, _ in operations],
            [work_key for _, work_key in operations],
        )
        self.assertEqual(
            [processor.JOB_CARD_WORK_KEYS[processor.classify_job_line(description)[0]] for description, _ in operations],
            [work_key for _, work_key in operations],
        )
        self.assertEqual(processor.canonical_jobcard_work_key("MINE BAR"), "fabrication")
        self.assertEqual(processor.canonical_jobcard_work_key("!FAB MINE BAR WITH SIDE FACING INDICATORS, SWITCHED WITH BEACON"), "fabrication")
        self.assertEqual(processor.canonical_jobcard_work_key("Bedrock Sliders"), "owner_supplied_document")
        self.assertIsNone(processor.classify_job_line("Bedrock Sliders")[0])
        self.assertEqual(processor.canonical_jobcard_work_key("Unmapped bespoke instruction"), "owner_supplied_document")

    def test_processor_builds_runtime_valid_zero_and_unknown_lines(self):
        minute_line = processor.extract_job_lines("OP 018 Bespoke retained instruction 30 min", "attachment:job.pdf")
        self.assertEqual(minute_line[0].estimated_duration_minutes, 30)
        proposal = processor.ExtractionProposal(
            extraction_version="pdc-email-intake-v1",
            source_hash="a" * 64,
            subject="Job Card",
            body_text="",
            attachment_text="",
            fields={
                "stock_numbers": ["U000001"], "toyota_order_numbers": [], "vins": [],
                "jc_number": "J000001", "customer": "Customer", "vehicle": "Vehicle", "eta": "",
            },
            job_lines=[
                {"source_label": "attachment:job.pdf", "work_type": "SUBLET", "estimated_duration_minutes": 0, "original_description": "SUB Reflective Striping 0.00 hours", "operation_code": "OP1"},
                {"source_label": "attachment:job.pdf", "work_type": None, "estimated_duration_minutes": 30, "original_description": "OP 018 Bespoke retained instruction 30 min", "operation_code": "OP018"},
            ],
            warnings=[],
            warning_labels=[],
            evidence=[{"attachment_id": "11111111-1111-4111-8111-111111111111", "filename": "job.pdf", "source_hash": "b" * 64, "extraction_status": "extracted", "extracted_text": "SUB Reflective Striping 0.00 hours\nOP 018 Bespoke retained instruction 30 min"}],
        )
        request = processor.canonical_jobcard_request(
            {"id": "22222222-2222-4222-8222-222222222222", "internet_message_id": "message-1", "provider_authserv_id": "mx.google.com", "provider_authentication": AUTH},
            proposal,
        )
        checked = runtime.validate_request(request)
        self.assertEqual(checked["extraction"]["required_work"], ["sublet"])
        self.assertEqual([line["work_key"] for line in checked["extraction"]["operation_lines"]], ["sublet", "owner_supplied_document"])
        self.assertEqual([line["operation_no"] for line in checked["extraction"]["operation_lines"]], ["OP1", "OP2"])
        self.assertEqual(checked["extraction"]["operation_lines"][0]["description"], "SUB Reflective Striping")
        self.assertEqual(checked["extraction"]["operation_lines"][1]["description"], "Bespoke retained instruction")
        self.assertEqual(checked["extraction"]["operation_lines"][0]["estimated_hours"], 0)

    def test_processor_preserves_stock_lookup_with_authenticated_source_vin(self):
        proposal = processor.ExtractionProposal(
            extraction_version="pdc-email-intake-v1",
            source_hash="a" * 64,
            subject="Job Card",
            body_text="",
            attachment_text="",
            fields={
                "stock_numbers": ["U158318"], "toyota_order_numbers": [], "vins": ["JTFHB8CP806024409"],
                "jc_number": "J138000812", "customer": "CATALYST METALS PTY LTD", "vehicle": "Toyota HiAce", "eta": "",
            },
            job_lines=[
                {"source_label": "attachment:job.pdf", "work_type": "SUBLET", "estimated_duration_minutes": 0, "original_description": "SUB Reflective Striping 0.00 hours", "operation_code": "OP1"},
            ],
            warnings=[],
            warning_labels=[],
            evidence=[{"attachment_id": "11111111-1111-4111-8111-111111111111", "filename": "job.pdf", "source_hash": "b" * 64, "extraction_status": "extracted", "extracted_text": "U158318 JTFHB8CP806024409 J138000812 SUB Reflective Striping 0.00 hours"}],
        )

        request = processor.canonical_jobcard_request(
            {"id": "22222222-2222-4222-8222-222222222222", "internet_message_id": "message-1", "provider_authserv_id": "mx.google.com", "provider_authentication": AUTH},
            proposal,
        )

        self.assertEqual(request["extraction"]["email_vehicle"]["stock_numbers"], ["U158318"])
        self.assertEqual(request["extraction"]["email_vehicle"]["vins"], ["JTFHB8CP806024409"])
        runtime.validate_request(request)

    def test_non_navision_readback_accepts_yh_review_count_and_zero(self):
        expected = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "sublet", "description": "SUB Reflective Striping", "estimated_hours": 0.0}]
        retained = "SUB Reflective Striping 0.00 hours"
        data = {
            "receipt_id": "33333333-3333-4333-8333-333333333333",
            "vehicle_id": "44444444-4444-4444-8444-444444444444",
            "vehicle_created": True,
            "operation_count": 1,
            "operation_lines": [{**expected[0], "parser_contract": "pmb-email-work-v2/operation-line-v1", "source_start": 0, "source_end": len(retained), "retained_source_text": retained}],
            "initial_location": "YH",
            "stock_number": "U158318",
            "source_vin": "JTFHB8CP806024409",
            "canonical_vin": "JTFHB8CP806024409",
            "source_provenance": {"authenticated_source_vin": "JTFHB8CP806024409", "source_receipt_id": "33333333-3333-4333-8333-333333333333"},
            "effective_provenance": {"vin": {"value": "JTFHB8CP806024409", "authority": "authenticated_non_navision_job_card", "source_receipt_id": "33333333-3333-4333-8333-333333333333"}},
            "mapping_review_count": 0,
            "booking_created": False,
            "completion_created": False,
        }
        result = runtime._jobcard_readback(data, {"extraction": {"operation_lines": expected, "email_vehicle": {"stock_numbers": ["U158318"], "vins": ["JTFHB8CP806024409"]}}}, "non_navision_jobcard_receipt")
        self.assertEqual(result["operation_count"], 1)
        self.assertEqual(result["canonical_vin"], "JTFHB8CP806024409")

    def test_non_navision_readback_requires_exact_unknown_review_count(self):
        expected = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "owner_supplied_document", "description": "OP1 Bespoke retained instruction", "estimated_hours": 0.5}]
        retained = "OP1 Bespoke retained instruction 30 min"
        data = {
            "receipt_id": "33333333-3333-4333-8333-333333333333", "vehicle_id": "44444444-4444-4444-8444-444444444444",
            "vehicle_created": True, "operation_count": 1,
            "operation_lines": [{**expected[0], "parser_contract": "pmb-email-work-v2/operation-line-v1", "source_start": 0, "source_end": len(retained), "retained_source_text": retained}],
            "initial_location": "YH", "stock_number": "U158318", "source_vin": None, "canonical_vin": None,
            "source_provenance": {}, "effective_provenance": {},
            "mapping_review_count": 0, "booking_created": False, "completion_created": False,
        }
        with self.assertRaisesRegex(runtime.RuntimeContractError, "mapping_review_count"):
            runtime._jobcard_readback(data, {"extraction": {"operation_lines": expected, "email_vehicle": {"stock_numbers": ["U158318"], "vins": []}}}, "non_navision_jobcard_receipt")

    def test_original_absent_vin_replay_accepts_later_audited_effective_projection(self):
        expected = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "sublet", "description": "SUB Reflective Striping", "estimated_hours": 0.0}]
        retained = "SUB Reflective Striping 0.00 hours"
        data = {
            "receipt_id": "33333333-3333-4333-8333-333333333333", "vehicle_id": "44444444-4444-4444-8444-444444444444",
            "vehicle_created": True, "operation_count": 1,
            "operation_lines": [{**expected[0], "parser_contract": "pmb-email-work-v2/operation-line-v1", "source_start": 0, "source_end": len(retained), "retained_source_text": retained}],
            "initial_location": "YH", "stock_number": "U158318", "source_vin": None, "canonical_vin": "JTFHB8CP806024409",
            "source_provenance": {"source_receipt_id": "55555555-5555-4555-8555-555555555555"},
            "effective_provenance": {"vin": {"value": "JTFHB8CP806024409", "authority": "authenticated_non_navision_job_card", "source_receipt_id": "55555555-5555-4555-8555-555555555555"}},
            "mapping_review_count": 0, "booking_created": False, "completion_created": False,
        }

        with self.assertRaisesRegex(runtime.RuntimeContractError, "PDC_JOB_CARD_READBACK_PROVENANCE_MISMATCH"):
            runtime._jobcard_readback(data, {"extraction": {"operation_lines": expected, "email_vehicle": {"stock_numbers": ["U158318"], "vins": []}}}, "non_navision_jobcard_receipt")

        data["source_provenance"]["source_receipt_id"] = data["receipt_id"]
        data["effective_provenance"]["vin"]["source_receipt_id"] = data["receipt_id"]
        result = runtime._jobcard_readback(data, {"extraction": {"operation_lines": expected, "email_vehicle": {"stock_numbers": ["U158318"], "vins": []}}}, "non_navision_jobcard_receipt")

        self.assertEqual(result["canonical_vin"], "JTFHB8CP806024409")

    def test_stock_only_existing_vehicle_does_not_claim_preexisting_vin_provenance(self):
        expected = [{"source_row_no": 1, "operation_no": "OP1", "work_key": "sublet", "description": "SUB Reflective Striping", "estimated_hours": 0.0}]
        retained = "SUB Reflective Striping 0.00 hours"
        data = {
            "receipt_id": "33333333-3333-4333-8333-333333333333", "vehicle_id": "44444444-4444-4444-8444-444444444444",
            "vehicle_created": False, "operation_count": 1,
            "operation_lines": [{**expected[0], "parser_contract": "pmb-email-work-v2/operation-line-v1", "source_start": 0, "source_end": len(retained), "retained_source_text": retained}],
            "initial_location": None, "stock_number": "U158318", "source_vin": None, "canonical_vin": "JTFHB8CP806024409",
            "source_provenance": {}, "effective_provenance": {},
            "mapping_review_count": 0, "booking_created": False, "completion_created": False,
        }

        result = runtime._jobcard_readback(data, {"extraction": {"operation_lines": expected, "email_vehicle": {"stock_numbers": ["U158318"], "vins": []}}}, "non_navision_jobcard_receipt")

        self.assertEqual(result["canonical_vin"], "JTFHB8CP806024409")


if __name__ == "__main__":
    unittest.main()
