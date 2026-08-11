#!/usr/bin/env python3
"""Focused contract for the PMB open-jobcards operations workbook adapter."""
from pathlib import Path
from tempfile import TemporaryDirectory
import sys

from openpyxl import Workbook

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import pdc_pmb_retained_workbook_adapter as retained


def append_summary(ws, jc, stock, rego, count, matched, schedule):
    ws.append([jc, stock, rego, None, None, count, matched, schedule])


with TemporaryDirectory() as directory:
    path = Path(directory) / "open-jobcards.xlsx"
    wb = Workbook()
    upload = wb.active
    upload.title = retained.OPERATIONS_SHEET_NAME
    upload.append(retained.OPERATIONS_HEADERS)
    upload.append(["J1", "13000001", None, 1, "PD001", "Complete Pre-Delivery Inspection", None, "Schedule Hrs", "MATCHED", None, None])
    upload.append(["J1", "13000001", None, 2, "PD002", "PIT AND WEIGH", 2.5, "Schedule Hrs", "MATCHED", None, None])
    upload.append(["J2", None, "1ABC234", 1, "PD003", "Fit bull bar", 3, "Schedule Hrs", "REGO ONLY", None, None])
    upload.append(["J3", "FABPARTS", None, 1, "PD004", "Custom fabrication", 4, "Schedule Hrs", "MATCHED", None, None])
    summary = wb.create_sheet(retained.SUMMARY_SHEET_NAME)
    summary.append(retained.SUMMARY_HEADERS)
    append_summary(summary, "J1", "13000001", None, 2, "MATCHED", "YES")
    append_summary(summary, "J2", None, "1ABC234", 1, "REGO ONLY", "YES")
    append_summary(summary, "J3", "FABPARTS", None, 1, "MATCHED", "YES")
    append_summary(summary, "J4", "13000002", None, 0, "MATCHED", "NO")
    wb.save(path)

    payload, canonical, evidence = retained.adapt_retained_workbook(path)
    assert len(payload) == 4, evidence
    assert payload[0]["job_card_number"] == "J1"
    operations = payload[0]["operations"]
    assert [op["work_key"] for op in operations] == ["fitting", "pitInspection"]
    assert [op["description"] for op in operations] == ["Complete Pre-Delivery Inspection", "PIT AND WEIGH"]
    assert [op["estimated_hours"] for op in operations] == [1, 2.5]
    assert [op["estimated_hours_source"] for op in operations] == ["ai_estimate", "job_card"]
    assert payload[1]["job_card_number"] == "J2" and payload[1]["stock_number"] is None
    assert payload[2]["stock_number"] == "FABPARTS"
    assert payload[3]["job_card_number"] == "J4" and payload[3]["operations"] == []
    assert evidence["stock_only_rows"] == 1
    assert evidence["registration_only_pair_count"] == 1
    assert evidence["operation_count"] == 4
    assert canonical == retained.canonical_bytes(payload)

print("PDC open-jobcards workbook adapter contract passed.")
