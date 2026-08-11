#!/usr/bin/env python3
"""Focused deterministic workshop-stage mapping contract."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / "scripts"))
import pdc_bulk_workbook_adapter as adapter

CASES = {
    "Complete Pre-Delivery Inspection": "fitting",
    "PDI": "fitting",
    "PD": "fitting",
    "Fill with Fuel": "pitInspection",
    "PIT AND WEIGH": "pitInspection",
    "Window Tint": "tint",
    "OME 3550Kg Nitro+ GVM Premium Includes Wheel Alignment": "hoist",
    "6x TYRES TO Bridgestone": "tyre",
    "Additional Spare Steel Rim": "tyre",
    "Battery Isolator mounted under bonnet": "electrical",
    "Supply and Fit GME XRS 370c UHF & Antenna": "electrical",
    "LED Lightbar - For Bull Bar": "electrical",
    "4x4 Bus conversion": "bus4x4",
    "Custom bracket fabrication and welding": "fabrication",
    "PTE Tray at Cost Refer PTE Quote": "sublet",
    "First Aid Kit left loose in vehicle": "fitting",
    "Safety Triangle kit left loose in vehicle": "fitting",
    "1.0 KG FIRE EXTINGUISHER left loose": "fitting",
    "Bonnet Protector - Dark Tint": "fitting",
    "Bonnet Protector - Matte Tint": "fitting",
    "Headlamp Covers": "fitting",
    "ARB Frontier Long Range Tank": "hoist",
    "Long Range Replacement Fuel Tank": "hoist",
    "Front Canvas Seat Covers": "fitting",
    "All Seat Covers": "fitting",
    "Recovery Points Rear Pair - Broome to supply": "fitting",
    "BROOME TO SUPPLY CARGO BARRIER": "fitting",
    "OME Suspension Upgrade": "hoist",
    "EXTRA SPARE GENUINE RIM - BROOME TO SUPPLY": "tyre",
    "Steel Bull Bar - Commercial": "fitting",
    "Tow Bar with Smart Wiring": "fitting",
    "Tool kit left loose in vehicle": "PARTS",
}

for description, expected in CASES.items():
    actual = adapter.infer_work_key(description)
    assert actual == expected, (description, actual, expected)

assert adapter.is_placeholder_operation("No operation available")
assert adapter.is_placeholder_operation("  NO OPERATION AVAILABLE  ")
assert not adapter.is_placeholder_operation("Fit tow bar")
assert adapter.STAGE_MAPPING_POLICY == "pmb-workshop-stages-v2"
print("PDC bulk workbook workshop-stage mapping contract passed.")
