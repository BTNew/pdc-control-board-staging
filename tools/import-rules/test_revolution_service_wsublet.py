import unittest
from revolution_service_wsublet import (BASE_HEADERS, ContractError, FILENAME_RE, check_headers, classify, collapse, read_values)

H = BASE_HEADERS + ['Description of sublet', 'PO #']


def row(ro='J139000001', line=1, hours=2.5, po=None, desc='Fit canopy', dept=139):
    v = dict(zip(BASE_HEADERS, [dept, 'S1', 'R1', 'Owner', 'A1', '7', ro, '20', line, desc, hours, '21/10/2026', 'HILUX']))
    v['Description of sublet'] = 'Sublet' if po else None
    v['PO #'] = po
    return v


class T(unittest.TestCase):
    def test_headers(self):
        self.assertEqual(check_headers(H + [None]), H)
        for bad in (['Type'] + H, BASE_HEADERS, BASE_HEADERS + ['PO #', 'PO #'], BASE_HEADERS + ['PO #', 'Other'], H[1:]):
            with self.assertRaises(ContractError):
                check_headers(bad)

    def test_filename(self):
        for ok in ('PMG PD Service Complete w/Sublet.xlsx', 'PMG PD Service Complete w_Sublet.xls', 'PMG PD Service Complete wSublet - Job 1.xlsx'):
            self.assertTrue(FILENAME_RE.match(ok), ok)
        for bad in ('PMG PD Service Complete.xlsx', 'PMG PD Service Complete w/Sublet - Job 2.xlsx', 'PMG PD Service Complete w/Sublet.csv'):
            self.assertFalse(FILENAME_RE.match(bad), bad)

    def test_classify_without_type(self):
        self.assertEqual(classify(row()), 'data')
        self.assertEqual(classify({'R/O #': None, 'Line #': None, 'Estimated labour hours': 99}), 'footer')
        self.assertEqual(classify(row(ro='J135000001', dept=135)), 'excluded_department')
        for bad in (row(ro='B139000001'), row(line=0), row(line=1.5), row(hours=-1), row(hours='x')):
            with self.assertRaises(ContractError):
                classify(bad)

    def test_collapse_keeps_every_po_and_never_sums(self):
        rows = [(5, row(po='GP13800001', hours=30)), (6, row(po='GP13800002', hours=30)), (7, row(po='gp13800001 ', hours=30)),
                (8, row(line=2, hours=1)), (9, row(line=3, hours=4, po='All'))]
        lines, s = collapse(rows)
        self.assertEqual(len(lines), 3)
        self.assertEqual(lines[0]['sublet_pos'], ['GP13800001', 'GP13800002'])
        self.assertEqual(lines[0]['raw']['Estimated labour hours'], 30)
        self.assertEqual(lines[0]['source_row_numbers'], [5, 6, 7])
        self.assertFalse(lines[0]['collapse']['conflict'])
        self.assertEqual(lines[1]['sublet_pos'], [])
        self.assertEqual(lines[2]['sublet_pos'], ['ALL'])
        self.assertEqual(s['hours_first_row_per_line'], 35.0)
        self.assertEqual(s['hours_naive_all_rows'], 95.0)
        self.assertEqual(s['rows_collapsed'], 2)

    def test_po_descriptions_r444(self):
        r1 = row(po='GP13800001'); r1['Description of sublet'] = '  Seat covers^Key 1 '
        r2 = row(po='GP13800002'); r2['Description of sublet'] = 'Transport'
        r3 = row(po='gp13800001'); r3['Description of sublet'] = 'Second text'
        r4 = row(po='GP13800001'); r4['Description of sublet'] = 'Seat covers^Key 1'
        r5 = row(line=2, po='GP13800003'); r5['Description of sublet'] = '   '
        lines, _ = collapse([(5, r1), (6, r2), (7, r3), (8, r4), (9, r5), (10, row(line=3))])
        self.assertEqual(lines[0]['sublet_po_descriptions'], {'GP13800001': 'Seat covers^Key 1^Second text', 'GP13800002': 'Transport'})
        self.assertEqual(lines[1]['sublet_po_descriptions'], {})
        self.assertEqual(lines[2]['sublet_po_descriptions'], {})
        for l in lines:
            self.assertTrue(set(l['sublet_po_descriptions']) <= set(l['sublet_pos']))

    def test_conflict_first_row_and_flagged(self):
        lines, s = collapse([(5, row(po='GP1', hours=3)), (6, row(po='GP2', hours=5))])
        self.assertEqual(lines[0]['raw']['Estimated labour hours'], 3)
        self.assertTrue(lines[0]['collapse']['conflict'])
        self.assertEqual(lines[0]['collapse']['differing_values']['Estimated labour hours'], [3, 5])
        self.assertEqual(s['conflicts'][0]['fields'], ['Estimated labour hours'])

    def test_read_values(self):
        vals = [('PMG PD Service Complete w/Sublet',), ('Extracted on X   Parameters: Company = "01" Division = "1"',), (None,), tuple(H)]
        vals += [tuple(row(po='GP1').get(h) for h in H), tuple([None] * 10 + [32.5] + [None] * 4)]
        h, data, footer, excl, _ = read_values(vals)
        self.assertEqual((len(data), len(footer), len(excl)), (1, 1, 0))
        with self.assertRaises(ContractError):
            read_values([('PMG PD Service Complete',)] + vals[1:])


if __name__ == '__main__':
    unittest.main()
