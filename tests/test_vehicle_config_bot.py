import csv
import importlib.util
import tempfile
import unittest
from decimal import Decimal
from pathlib import Path

import vehicle_config_bot as bot


def evidence(field, reference="quote:42"):
    tax = {
        "Hidden": bot.TaxSemantics.NOT_APPLICABLE,
        "Cost": bot.TaxSemantics.EX_GST,
        "Sell": bot.TaxSemantics.INC_GST,
    }[field]
    return bot.ProposalEvidence("approved-catalogue", reference, "operator:123", tax)


def change(row, field, value, reference="quote:42"):
    return bot.CellChange(row, field, value, evidence(field, reference))


def amount(value, tax, reference="quote:42"):
    return bot.ApprovedAmount(value, "approved-catalogue", reference, "operator:123", tax)


class VehicleConfigCsvTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "vehicle-config.csv"
        self.source.write_text(
            "Code,Description,Hidden,Cost,Sell,Notes\r\n"
            'A1,"Tow bar, black",no,100,150,"Keep wording"\r\n'
            "A2,Solis panel,no,200,300,Formula-like =A1\r\n",
            encoding="utf-8", newline="",
        )

    def tearDown(self):
        self.tempdir.cleanup()

    def read_rows(self, path):
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.reader(handle))

    def test_only_allowed_cells_change_and_rows_ids_wording_survive(self):
        destination = self.root / "reviewed.csv"
        before = self.read_rows(self.source)
        bot.apply_file(self.source, destination, [
            change(1, "Hidden", " YES "), change(1, "Cost", Decimal("121")),
            change(2, "Sell", 450),
        ])
        after = self.read_rows(destination)
        self.assertEqual(after[1][2], "yes")
        self.assertEqual(after[1][3], "121.00")
        self.assertEqual(after[2][4], "450.00")
        self.assertEqual(before[0], after[0])
        self.assertEqual([r[:2] for r in before[1:]], [r[:2] for r in after[1:]])
        self.assertEqual([r[5] for r in before[1:]], [r[5] for r in after[1:]])
        changed = {(r, c) for r in range(len(before)) for c in range(len(before[r]))
                   if before[r][c] != after[r][c]}
        self.assertEqual(changed, {(1, 2), (1, 3), (2, 4)})

    def test_second_apply_is_idempotent(self):
        first, second = self.root / "first.csv", self.root / "second.csv"
        changes = [change(1, "Cost", Decimal("121"))]
        bot.apply_file(self.source, first, changes)
        bot.apply_file(first, second, changes)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_typed_evidence_contract_rejects_prior_value_exploits(self):
        with self.assertRaises(TypeError):
            bot.CellChange(1, "Cost", 12)  # no provenance
        for bad in ("121", "=1+1", "$121.00", "1,000", True, float("nan"), float("inf"), -1):
            with self.subTest(bad=bad), self.assertRaises(bot.ValidationError):
                change(1, "Cost", bad)
        for bad in (True, 1, "true", "maybe", "=YES()", "yes "):
            if bad == "yes ":
                continue  # surrounding whitespace is deliberately normalized
            with self.subTest(hidden=bad), self.assertRaises(bot.ValidationError):
                change(1, "Hidden", bad)
        self.assertEqual(change(1, "Hidden", " No ").value, "no")
        with self.assertRaisesRegex(bot.ValidationError, "tax semantics"):
            bot.CellChange(1, "Cost", 12, evidence("Sell"))
        with self.assertRaisesRegex(bot.ValidationError, "non-empty"):
            bot.ProposalEvidence("", "ref", "operator", bot.TaxSemantics.EX_GST)

    def test_rejects_unauthorized_field_and_structural_tampering(self):
        with self.assertRaisesRegex(bot.ValidationError, "not editable"):
            bot.CellChange(1, "Description", "invented", evidence("Hidden"))
        tampered = self.root / "tampered.csv"
        tampered.write_text(self.source.read_text(encoding="utf-8").replace(
            "Keep wording", "Changed wording"), encoding="utf-8", newline="")
        with self.assertRaisesRegex(bot.ValidationError, "unauthorized CSV change"):
            bot._validate_csv(self.source, tampered, [change(1, "Cost", 121)])

    def test_review_validates_without_leaving_output(self):
        changes = [change(1, "Sell", 175)]
        self.assertEqual(bot.review_file(self.source, changes), tuple(changes))
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ["vehicle-config.csv"])


class CommandAndPricingTests(unittest.TestCase):
    def test_command_parsing(self):
        self.assertEqual(bot.parse_command("Review quote-1"), bot.ParsedCommand("review", "quote-1", False))
        with self.assertRaises(bot.AuthorizationError):
            bot.parse_command("Remember rule")
        privileged = bot.parse_command("Correct row 4", authorized_identity="operator:approved")
        with self.assertRaisesRegex(bot.VehicleConfigError, "not configured"):
            bot.execute_privileged_stub(privileged)

    def test_solis_recomputes_from_immutable_approved_base_exactly_once(self):
        cost = amount(100, bot.TaxSemantics.EX_GST)
        base = amount(200, bot.TaxSemantics.INC_GST, "arb-retail:solis-v7")
        first = bot.calculate_pricing(cost=cost, base_sell=base, solis=True)
        second = bot.calculate_pricing(cost=cost, base_sell=base, solis=True)
        self.assertEqual(first.sell_inc_gst, Decimal("350.00"))
        self.assertEqual(second.sell_inc_gst, Decimal("350.00"))
        self.assertEqual(first.base_sell_reference, "arb-retail:solis-v7")
        with self.assertRaises(bot.ValidationError):
            amount("350.00", bot.TaxSemantics.INC_GST)  # output strings cannot masquerade as base evidence

    def test_hilux_gvm_requires_fully_scoped_evidence_not_boolean(self):
        cost = amount(100, bot.TaxSemantics.EX_GST)
        base = amount(200, bot.TaxSemantics.INC_GST)
        gvm = bot.HiluxGvmEvidence("Hilux SR5 48V", 50, "approved-uplift", "job:88", "operator:123")
        result = bot.calculate_pricing(cost=cost, base_sell=base, hilux_gvm=gvm)
        self.assertEqual(result.sell_inc_gst, Decimal("250.00"))
        with self.assertRaisesRegex(bot.ValidationError, "scoped evidence"):
            bot.calculate_pricing(cost=cost, base_sell=base, hilux_gvm=True)
        with self.assertRaisesRegex(bot.ValidationError, "Hilux model"):
            bot.HiluxGvmEvidence("Prado", 50, "src", "ref", "operator")
        with self.assertRaises(TypeError):
            bot.calculate_pricing(cost=cost, base_sell=base, hilux_gvm_approved=True)

    def test_other_pricing_rules(self):
        pmb = amount(100, bot.TaxSemantics.EX_GST)
        self.assertEqual(bot.calculate_pmb_sell(pmb), Decimal("121.00"))
        self.assertEqual(bot.approved_pd_pricing(), (Decimal("300.00"), Decimal("1995.00")))
        self.assertEqual(bot.calculate_freight("Kununurra"), (Decimal("830.00"), Decimal("1095.60")))
        self.assertEqual(bot.calculate_freight("Derby"), (Decimal("600.00"), Decimal("792.00")))
        with self.assertRaisesRegex(bot.ValidationError, "no approved price evidence"):
            bot.calculate_freight("Perth")
        with self.assertRaises(bot.ValidationError):
            bot.calculate_pmb_sell(amount(100, bot.TaxSemantics.INC_GST))


@unittest.skipUnless(importlib.util.find_spec("openpyxl"), "openpyxl unavailable")
class VehicleConfigXlsxFailClosedTests(unittest.TestCase):
    def setUp(self):
        import openpyxl
        from openpyxl.worksheet.datavalidation import DataValidation
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.source = self.root / "vehicle-config.xlsx"
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = "Options"
        ws.append(["Code", "Description", "Hidden", "Cost", "Sell"])
        ws.append(["A1", "Formula targets must survive", "no", "=100+21", 150])
        dv = DataValidation(type="list", formula1='"yes,no"')
        ws.add_data_validation(dv)
        dv.add(ws["C2"])
        wb.save(self.source)
        wb.close()

    def tearDown(self):
        self.tempdir.cleanup()

    def test_formula_target_is_never_overwritten(self):
        output = self.root / "reviewed.xlsx"
        before = self.source.read_bytes()
        with self.assertRaisesRegex(bot.UnsupportedFormatError, "OOXML preservation"):
            bot.apply_file(self.source, output, [change(1, "Cost", 121)])
        self.assertEqual(self.source.read_bytes(), before)
        self.assertFalse(output.exists())

    def test_data_validation_tamper_surface_fails_closed(self):
        output = self.root / "reviewed.xlsx"
        with self.assertRaises(bot.UnsupportedFormatError):
            bot.apply_file(self.source, output, [change(1, "Hidden", "yes")])
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
