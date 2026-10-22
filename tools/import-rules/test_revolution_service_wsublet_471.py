"""r471 (F84): a trailing bay / parts-location code on an operation description is the same line, not a new version.
Synthetic fixtures only (no real stock numbers, job cards, customers or IDs)."""
import unittest

from revolution_service_wsublet import (BAY_CODE_PROVENANCE_KEY, BAY_CODE_RULE, canonicalise_bay_code_descriptions,
                                        existing_lines_from_operations, match_existing_description,
                                        same_line_ignoring_bay_code, split_bay_code)


def row(dept, ro, line, desc, hours=0):
    return {'department': dept, 'repair_order_number': ro, 'original_line_number': line, 'operation_description': desc,
            'source_estimated_hours': hours, 'raw_row': {'Dept': dept, 'R/O #': ro, 'Line #': line, 'Operation Desc': desc}}


# Shapes taken from the 21-22 Oct reports, with synthetic job cards.
DE_MINE = ('139', 'J139900001', 1)          # the held stock: 'DE MINE SPEC' then 'DE MINE SPEC 05K4F'
FUEL_A = ('139', 'J139900002', 1)           # fuel line, this morning: '... -- 04K2B'
FUEL_B = ('139', 'J139900003', 1)           # fuel line, this morning: '... -- 04K2A'
PDI = ('139', 'J139900004', 1)              # 20 Oct shape: case change + code
TRAY = ('139', 'J139900005', 17)            # 20 Oct shape: a real wording fix (HAEVY -> HEAVY) must still version
SUSP = ('139', 'J139900006', 1)             # 20 Oct shape: code plus another annotation (not a bare trailing code)
FUEL_TXT = 'COMPLIMENTARY FULL TANK OF FUEL AND/OR BATTERY CHARGE'

OPERATIONS = [
    {'id': 'op-keep', 'dept': '139', 'ro': DE_MINE[1], 'line': 1, 'description': 'DE MINE SPEC'},
    {'id': 'op-retired', 'dept': '139', 'ro': DE_MINE[1], 'line': 1, 'description': 'DE MINE SPEC 05K4F'},
    {'id': 'op-fuel-a', 'dept': '139', 'ro': FUEL_A[1], 'line': 1, 'description': FUEL_TXT},
    {'id': 'op-fuel-b', 'dept': '139', 'ro': FUEL_B[1], 'line': 1, 'description': FUEL_TXT},
    {'id': 'op-pdi', 'dept': '139', 'ro': PDI[1], 'line': 1, 'description': 'Pre-Delivery (Commercial)'},
    {'id': 'op-tray', 'dept': '139', 'ro': TRAY[1], 'line': 17, 'description': 'FITTED TRAY BODY - 1800MM HAEVY DUTY STEEL'},
    {'id': 'op-susp', 'dept': '139', 'ro': SUSP[1], 'line': 1, 'description': 'Complementary Full Tank of Fuel'},
]


class SplitBayCode471(unittest.TestCase):
    def test_trailing_codes(self):
        self.assertEqual(split_bay_code('DE MINE SPEC 05K4F'), ('DE MINE SPEC', '05K4F'))
        self.assertEqual(split_bay_code(FUEL_TXT + ' -- 04K2B'), (FUEL_TXT, '04K2B'))
        self.assertEqual(split_bay_code('X - 05E2A'), ('X', '05E2A'))
        self.assertEqual(split_bay_code('  X   05J2A  '), ('X', '05J2A'))

    def test_not_a_trailing_code(self):
        for d in ['DE MINE SPEC', 'X05K4F', 'X 5K4F', 'X 05K4', 'X 05k4f', 'X 005K4F', 'X 05K4FF', '05K4F',
                  'FUEL -- 05I4B **SUSP 17C6B**', 'UHF RADIO - GME TX3500', '9KG FIRE EXTINGUISHER 05L4E **MINEBAR 04X4B**']:
            self.assertIsNone(split_bay_code(d)[1], d)


class SameLine471(unittest.TestCase):
    def test_same_line(self):
        self.assertTrue(same_line_ignoring_bay_code('DE MINE SPEC', 'DE MINE SPEC 05K4F'))
        self.assertTrue(same_line_ignoring_bay_code(FUEL_TXT, FUEL_TXT + ' -- 04K2B'))
        self.assertTrue(same_line_ignoring_bay_code('Pre-Delivery (Commercial)', 'PRE-DELIVERY (COMMERCIAL) 05J2B'))
        self.assertTrue(same_line_ignoring_bay_code('PLUG -- 05J3A', 'PLUG -- 04W3B'), 'bay code changed')
        self.assertTrue(same_line_ignoring_bay_code('PLUG 05J3A', 'PLUG'), 'bay code dropped')

    def test_real_changes_still_version(self):
        self.assertFalse(same_line_ignoring_bay_code('DE MINE SPEC', 'DE MINE SPEC'))
        self.assertFalse(same_line_ignoring_bay_code('FITTED TRAY BODY - 1800MM HAEVY DUTY STEEL',
                                                     'FITTED TRAY BODY - 1800MM HEAVY DUTY STEEL'))
        self.assertFalse(same_line_ignoring_bay_code('UHF RADIO - KENWOODNX-3720HG', 'UHF RADIO - GME TX3500'))
        self.assertFalse(same_line_ignoring_bay_code('Complementary Full Tank of Fuel',
                                                     'COMPLEMENTARY FULL TANK OF FUEL -- 05I4B **SUSP 17C6B**'))
        self.assertFalse(same_line_ignoring_bay_code('DE MINE SPEC', 'DE MINE SPEC REMOVED 05K4F'))
        self.assertFalse(same_line_ignoring_bay_code('Pre-Delivery', 'PRE-DELIVERY'), 'case alone is not this rule')
        self.assertFalse(same_line_ignoring_bay_code('', '05K4F'))


class Canonicalise471(unittest.TestCase):
    def setUp(self):
        self.existing = existing_lines_from_operations(OPERATIONS, superseded_ids={'op-retired'})

    def test_de_mine_spec_counts_as_unchanged_after_retirement(self):
        out, rep = canonicalise_bay_code_descriptions([row(*DE_MINE, 'DE MINE SPEC 05K4F')], self.existing)
        self.assertEqual(out[0]['operation_description'], 'DE MINE SPEC')
        self.assertEqual(out[0]['raw_row']['Operation Desc'], 'DE MINE SPEC 05K4F', 'source text kept')
        p = out[0]['raw_row'][BAY_CODE_PROVENANCE_KEY]
        self.assertEqual((p['rule'], p['incoming'], p['kept'], p['incoming_bay_code'], p['kept_bay_code']),
                         (BAY_CODE_RULE, 'DE MINE SPEC 05K4F', 'DE MINE SPEC', '05K4F', None))
        self.assertEqual(rep['matched'], 1)

    def test_before_retirement_two_live_versions_are_left_to_the_native_preview(self):
        both = existing_lines_from_operations(OPERATIONS)
        self.assertEqual(both[DE_MINE], ['DE MINE SPEC', 'DE MINE SPEC 05K4F'])
        out, rep = canonicalise_bay_code_descriptions([row(*DE_MINE, 'DE MINE SPEC 05K4F')], both)
        self.assertEqual(out[0]['operation_description'], 'DE MINE SPEC 05K4F', 'exact live text: untouched')
        self.assertEqual(rep['matched'], 0)

    def test_fuel_lines_from_this_morning(self):
        rows = [row(*FUEL_A, FUEL_TXT + ' -- 04K2B'), row(*FUEL_B, FUEL_TXT + ' -- 04K2A')]
        out, rep = canonicalise_bay_code_descriptions(rows, self.existing)
        self.assertEqual([r['operation_description'] for r in out], [FUEL_TXT, FUEL_TXT])
        self.assertEqual([m['incoming_bay_code'] for m in rep['matches']], ['04K2B', '04K2A'])

    def test_case_and_code_change_maps_to_the_board_text(self):
        out, _ = canonicalise_bay_code_descriptions([row(*PDI, 'PRE-DELIVERY (COMMERCIAL) 05J2B')], self.existing)
        self.assertEqual(out[0]['operation_description'], 'Pre-Delivery (Commercial)')

    def test_real_wording_change_and_extra_annotation_still_version(self):
        rows = [row(*TRAY, 'FITTED TRAY BODY - 1800MM HEAVY DUTY STEEL'),
                row(*SUSP, 'COMPLEMENTARY FULL TANK OF FUEL -- 05I4B **SUSP 17C6B**')]
        out, rep = canonicalise_bay_code_descriptions(rows, self.existing)
        self.assertEqual([r['operation_description'] for r in out], [r['operation_description'] for r in rows])
        self.assertEqual(rep['matched'], 0)
        self.assertNotIn(BAY_CODE_PROVENANCE_KEY, out[0]['raw_row'])

    def test_new_line_and_other_line_numbers_untouched(self):
        rows = [row('139', 'J139900001', 2, 'DE MINE SPEC 05K4F'), row('139', 'J139900099', 1, 'NEW WORK 05K4F'),
                row('138', 'J139900001', 1, 'DE MINE SPEC 05K4F')]
        out, rep = canonicalise_bay_code_descriptions(rows, self.existing)
        self.assertEqual(out, rows)
        self.assertEqual(rep['matched'], 0)

    def test_ambiguous_live_versions_are_not_guessed(self):
        live = {('139', 'J139900007', 1): ['PLUG -- 05J3A', 'PLUG -- 04W3B']}
        self.assertIsNone(match_existing_description('PLUG -- 05K1A', live[('139', 'J139900007', 1)]))
        out, rep = canonicalise_bay_code_descriptions([row('139', 'J139900007', 1, 'PLUG -- 05K1A')], live)
        self.assertEqual(out[0]['operation_description'], 'PLUG -- 05K1A')
        self.assertEqual(len(rep['ambiguous']), 1)

    def test_input_rows_are_not_mutated(self):
        rows = [row(*DE_MINE, 'DE MINE SPEC 05K4F')]
        before = repr(rows)
        canonicalise_bay_code_descriptions(rows, self.existing)
        self.assertEqual(repr(rows), before)


if __name__ == '__main__':
    unittest.main()
