import csv
import importlib.util
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

import vehicle_config_bot as bot


class VehicleConfigCsvTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "vehicle-config.csv"
        self.source.write_text(
            "Code,Description,Hidden,Cost,Sell,Notes\r\n"
            'A1,"Tow bar, black",No,100,150,"Keep wording"\r\n'
            "A2,Solis panel,No,200,300,Formula-like =A1\r\n",
            encoding="utf-8",
            newline="",
        )

    def tearDown(self):
        self.tempdir.cleanup()

    def read_rows(self, path):
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.reader(handle))

    def test_only_allowed_cells_change_and_order_and_wording_survive(self):
        destination = self.root / "reviewed.csv"
        before = self.read_rows(self.source)
        bot.apply_file(
            self.source,
            destination,
            [
                bot.CellChange(1, "Hidden", "Yes"),
                bot.CellChange(1, "Cost", "121.00"),
                bot.CellChange(2, "Sell", "450.00"),
            ],
        )
        after = self.read_rows(destination)
        self.assertEqual(before[0], after[0])
        self.assertEqual(len(before), len(after))
        changed = {
            (r, c)
            for r in range(len(before))
            for c in range(len(before[r]))
            if before[r][c] != after[r][c]
        }
        self.assertEqual(changed, {(1, 2), (1, 3), (2, 4)})
        self.assertEqual(after[1][1], "Tow bar, black")
        self.assertEqual(after[1][5], "Keep wording")
        self.assertEqual(after[2][5], "Formula-like =A1")

    def test_second_apply_is_idempotent(self):
        first = self.root / "first.csv"
        second = self.root / "second.csv"
        changes = [bot.CellChange(1, "Cost", "121.00")]
        bot.apply_file(self.source, first, changes)
        bot.apply_file(first, second, changes)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_rejects_unauthorized_field_and_structural_tampering(self):
        with self.assertRaisesRegex(bot.ValidationError, "not editable"):
            bot.apply_file(
                self.source,
                self.root / "bad.csv",
                [bot.CellChange(1, "Description", "invented")],
            )

        tampered = self.root / "tampered.csv"
        tampered.write_text(
            self.source.read_text(encoding="utf-8").replace("Keep wording", "Changed wording"),
            encoding="utf-8",
            newline="",
        )
        with self.assertRaisesRegex(bot.ValidationError, "unauthorized CSV change"):
            bot._validate_csv(self.source, tampered, [bot.CellChange(1, "Cost", "121")])

    def test_review_validates_without_leaving_output(self):
        changes = [bot.CellChange(1, "Sell", "175")]
        self.assertEqual(bot.review_file(self.source, changes), tuple(changes))
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["vehicle-config.csv"])


class CommandAndPricingTests(unittest.TestCase):
    def test_command_parsing(self):
        self.assertEqual(bot.parse_command("Review quote-1"), bot.ParsedCommand("review", "quote-1", False))
        self.assertEqual(
            bot.parse_command("  SHOW   unresolved  "),
            bot.ParsedCommand("show unresolved", "", False),
        )
        with self.assertRaises(bot.AuthorizationError):
            bot.parse_command("Remember always use approved price")
        privileged = bot.parse_command(
            "Correct row 4", authorized_identity="operator:approved-user"
        )
        self.assertTrue(privileged.requires_authorized_identity)
        with self.assertRaisesRegex(bot.VehicleConfigError, "not configured"):
            bot.execute_privileged_stub(privileged)
        with self.assertRaises(bot.ValidationError):
            bot.parse_command("Delete everything")

    def test_pricing_rules_are_explicit(self):
        result = bot.calculate_pricing(
            cost_ex_gst="100",
            sell_inc_gst="200",
            solis=True,
            hilux_gvm_inc_gst="50",
            hilux_gvm_approved=True,
        )
        self.assertEqual(result.cost_ex_gst, Decimal("100.00"))
        self.assertEqual(result.sell_inc_gst, Decimal("400.00"))
        self.assertEqual(bot.calculate_pmb_sell("100"), Decimal("121.00"))
        self.assertEqual(bot.approved_pd_pricing(), (Decimal("300.00"), Decimal("1995.00")))
        self.assertEqual(bot.calculate_freight("Kununurra"), (Decimal("830.00"), Decimal("1095.60")))
        self.assertEqual(bot.calculate_freight("Halls Creek"), (Decimal("830.00"), Decimal("1095.60")))
        self.assertEqual(bot.calculate_freight("Fitzroy Crossing"), (Decimal("830.00"), Decimal("1095.60")))
        self.assertEqual(bot.calculate_freight("Derby"), (Decimal("600.00"), Decimal("792.00")))
        with self.assertRaisesRegex(bot.ValidationError, "no approved price evidence"):
            bot.calculate_freight("Perth")
        with self.assertRaisesRegex(bot.ValidationError, "explicit approval"):
            bot.calculate_pricing(
                cost_ex_gst=100,
                sell_inc_gst=200,
                hilux_gvm_inc_gst=50,
            )


@unittest.skipUnless(importlib.util.find_spec("openpyxl"), "openpyxl optional dependency unavailable")
class VehicleConfigXlsxTests(unittest.TestCase):
    def setUp(self):
        import openpyxl
        from openpyxl.styles import Font, PatternFill

        self.openpyxl = openpyxl
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "vehicle-config.xlsx"
        workbook = openpyxl.Workbook()
        sheet = workbook.active
        sheet.title = "Options"
        sheet.append(["Code", "Description", "Hidden", "Cost", "Sell", "Calc"])
        sheet.append(["A1", "Tow bar", False, 100, 150, "=D2*1.5"])
        sheet.append(["A2", "Solis", False, 200, 300, "=D3*1.5"])
        sheet["A1"].font = Font(bold=True)
        sheet["D2"].fill = PatternFill("solid", fgColor="FFFF00")
        sheet.column_dimensions["B"].width = 24
        sheet.freeze_panes = "A2"
        notes = workbook.create_sheet("Read Me")
        notes["A1"] = "Exact wording must survive"
        workbook.save(self.source)
        workbook.close()

    def tearDown(self):
        self.tempdir.cleanup()

    def test_xlsx_changes_only_allowed_values_preserving_formulas_styles_sheets(self):
        output = self.root / "reviewed.xlsx"
        bot.apply_file(
            self.source,
            output,
            [
                bot.CellChange(1, "Hidden", True, "Options"),
                bot.CellChange(1, "Cost", 121, "Options"),
                bot.CellChange(2, "Sell", 450, "Options"),
            ],
        )
        before = self.openpyxl.load_workbook(self.source, data_only=False)
        after = self.openpyxl.load_workbook(output, data_only=False)
        try:
            self.assertEqual(before.sheetnames, after.sheetnames)
            changed = set()
            for sheet_name in before.sheetnames:
                for row in before[sheet_name].iter_rows():
                    for cell in row:
                        if cell.value != after[sheet_name][cell.coordinate].value:
                            changed.add((sheet_name, cell.coordinate))
                        self.assertEqual(cell.style_id, after[sheet_name][cell.coordinate].style_id)
            self.assertEqual(
                changed,
                {("Options", "C2"), ("Options", "D2"), ("Options", "E3")},
            )
            self.assertEqual(after["Options"]["F2"].value, "=D2*1.5")
            self.assertEqual(after["Options"]["F3"].value, "=D3*1.5")
            self.assertEqual(after["Read Me"]["A1"].value, "Exact wording must survive")
            self.assertEqual(after["Options"].column_dimensions["B"].width, 24)
            self.assertEqual(after["Options"].freeze_panes, "A2")
        finally:
            before.close()
            after.close()

    def test_xlsx_is_logically_idempotent(self):
        first, second = self.root / "first.xlsx", self.root / "second.xlsx"
        changes = [bot.CellChange(1, "Cost", 121, "Options")]
        bot.apply_file(self.source, first, changes)
        bot.apply_file(first, second, changes)
        bot._validate_xlsx(first, second, changes)

    def test_xlsx_gate_rejects_formula_tampering(self):
        tampered = self.root / "tampered.xlsx"
        workbook = self.openpyxl.load_workbook(self.source, data_only=False)
        workbook["Options"]["F2"] = "=0"
        workbook.save(tampered)
        workbook.close()
        with self.assertRaisesRegex(bot.ValidationError, "unauthorized XLSX change"):
            bot._validate_xlsx(
                self.source,
                tampered,
                [bot.CellChange(1, "Cost", 121, "Options")],
            )


if __name__ == "__main__":
    unittest.main()
