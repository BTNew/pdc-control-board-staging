import tempfile
import unittest
import zipfile
from pathlib import Path

try:
    from backend.email_intake_processor import (
        AttachmentEvidence,
        analyze_record,
        canonical_jobcard_request,
        classify_job_line,
        extract_attachment,
        extract_job_lines,
        operation_display_description,
    )
except ModuleNotFoundError:
    from email_intake_processor import (
        AttachmentEvidence,
        analyze_record,
        canonical_jobcard_request,
        classify_job_line,
        extract_attachment,
        extract_job_lines,
        operation_display_description,
    )


class EmailIntakeProcessorTests(unittest.TestCase):
    def test_three_distinct_job_lines_produce_three_independent_lines(self):
        body = """
        Stock Number: 47123
        Toyota Order Number: TOY-99821
        VIN: JTEBR3FJ10K123456
        JC Number: JC-7719
        Customer: Synthetic Fleet Account
        JITA Order: JITA-55
        Jobs:
        Tint all windows
        Replace four tyres
        Weld custom mounting brackets
        """
        proposal = analyze_record(
            {"subject": "Job card JC-7719", "raw_body": body, "source_hash": "a" * 64}, []
        )
        self.assertEqual([line["work_type"] for line in proposal.job_lines], ["TINT", "TYRE", "FABRICATION"])
        self.assertEqual(len({line["line_id"] for line in proposal.job_lines}), 3)
        self.assertTrue(all(line["original_description"] for line in proposal.job_lines))
        self.assertTrue(all(line["assignment_reason"] for line in proposal.job_lines))
        self.assertTrue(all(line["estimated_duration_minutes"] is None for line in proposal.job_lines))

    def test_unknown_or_conflicting_line_is_never_guessed(self):
        unknown_type, unknown_reason, unknown_confidence = classify_job_line("Perform special customer request")
        conflict_type, conflict_reason, _ = classify_job_line("Tint and fabricate custom panel")
        self.assertIsNone(unknown_type)
        self.assertIsNone(conflict_type)
        self.assertEqual(unknown_confidence, 0.0)
        self.assertIn("no deterministic work-type rule", unknown_reason)
        self.assertIn("conflicting deterministic rules", conflict_reason)

    def test_quantity_and_duration_remain_null_without_explicit_values(self):
        line = extract_job_lines("Fit bull bar", "body")[0]
        self.assertIsNone(line.quantity)
        self.assertIsNone(line.estimated_duration_minutes)
        explicit = extract_job_lines("Qty 2 fit bull bar 180 minutes", "body")[0]
        self.assertEqual(explicit.quantity, 2)
        self.assertEqual(explicit.estimated_duration_minutes, 180)

    def test_xlsx_openxml_attachment_is_read_locally(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "purchase-order.xlsx"
            shared = """<?xml version="1.0"?><sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>JC Number</t></si><si><t>JC-123</t></si><si><t>Tint windows</t></si></sst>"""
            sheet = """<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>2</v></c></row></sheetData></worksheet>"""
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("xl/sharedStrings.xml", shared)
                archive.writestr("xl/worksheets/sheet1.xml", sheet)
            extracted = extract_attachment(path)
            self.assertIn("JC-123", extracted)
            self.assertIn("Tint windows", extracted)

    def test_missing_attachment_is_visible_warning(self):
        evidence = AttachmentEvidence("att-2", "missing.pdf", "c" * 64, "X:/missing.pdf")
        proposal = analyze_record(
            {"subject": "JC Number: JC-1", "raw_body": "Stock Number: 1\nTint windows", "source_hash": "d" * 64},
            [evidence],
        )
        self.assertIn("Missing attachment", proposal.warning_labels)

    def test_duplicate_lines_across_body_and_attachment_are_deduplicated_by_line_hash(self):
        lines = extract_job_lines("Jobs:\nTint all windows\nTint all windows", "body")
        self.assertEqual(len(lines), 1)

    def test_canonical_jobcard_request_uses_exact_v2_shape(self):
        proposal = analyze_record({
            "id": "00000000-0000-4000-8000-000000000101",
            "subject": "Job card JC-7719",
            "raw_body": "",
            "source_hash": "a" * 64,
        }, [])
        proposal.fields.update({"stock_numbers": ["13018015"], "vins": [], "jc_number": "JC-7719", "toyota_order_numbers": []})
        proposal.job_lines = [{"source_label": "attachment:job.txt", "work_type": "FITTING", "estimated_duration_minutes": 120, "original_description": "Fit bull bar 2 hours"}]
        proposal.evidence = [{"attachment_id": "00000000-0000-4000-8000-000000000102", "filename": "job.txt", "source_hash": "b" * 64, "extraction_status": "extracted", "extracted_text": "JC-7719 Stock 13018015 Fit bull bar 2 hours"}]
        request = canonical_jobcard_request({
            "id": "00000000-0000-4000-8000-000000000101", "internet_message_id": "<job@example>",
            "provider_authserv_id": "mx.google.com", "provider_authentication": {"dkim_aligned": True, "dmarc_aligned": False, "gmail_authentication_results": True, "sender_domain": "example.com", "spf_aligned": False},
        }, proposal)
        self.assertEqual(request["extraction"]["contract_version"], "pmb-email-work-v2")
        self.assertEqual(request["extraction"]["operation_lines"][0]["work_key"], "fitting")
        self.assertEqual(request["extraction"]["operation_lines"][0]["estimated_hours"], 2.0)
        self.assertEqual(request["extraction"]["required_work"], ["fitting"])

    def test_canonical_jobcard_request_rejects_missing_explicit_duration(self):
        proposal = analyze_record({"subject": "", "raw_body": "", "source_hash": "a" * 64}, [])
        proposal.fields.update({"stock_numbers": ["13018015"], "vins": [], "jc_number": "JC-7719"})
        proposal.job_lines = [{"source_label": "attachment:job.txt", "work_type": "FITTING", "estimated_duration_minutes": None, "original_description": "Fit bull bar"}]
        proposal.evidence = [{"attachment_id": "00000000-0000-4000-8000-000000000102", "filename": "job.txt", "source_hash": "b" * 64, "extraction_status": "extracted", "extracted_text": "Fit bull bar"}]
        with self.assertRaisesRegex(RuntimeError, "explicit positive duration"):
            canonical_jobcard_request({"id": "00000000-0000-4000-8000-000000000101", "provider_authentication": {}}, proposal)

    def test_jc_number_remains_metadata_not_operation_display_prefix(self):
        self.assertEqual(operation_display_description("JC J139124174 · OP5 · Fit recovery points", "J139124174"), "OP5 · Fit recovery points")
        self.assertEqual(operation_display_description("Job Card J139124174 - Fit recovery points", "J139124174"), "Fit recovery points")
        line = extract_job_lines("OP17 Fit rear recovery points 2 hours", "attachment:job.txt")[0]
        self.assertEqual(line.operation_code, "OP17")

    def test_raw_tint_heuristic_is_overridden_only_by_persistent_resolver(self):
        work_type, reason, confidence = classify_job_line("Bonnet Protector - Dark Tint")
        self.assertEqual(work_type, "TINT")
        self.assertIn("tint wording", reason)
        self.assertGreater(confidence, 0)


if __name__ == "__main__":
    unittest.main()
