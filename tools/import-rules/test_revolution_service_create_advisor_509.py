"""r509 (F122): optional trailing Create Advisor on the service workbook.

Synthetic rows only (SYN..., J139900..., GP139900...). A file with no Create Advisor column must still parse as r468
left it. Dropping the column (filled in) must not change the collapsed lines. A blank advisor on a data row is left
out of the import and does not close anything.
"""
import unittest

import fixtures_service_wsublet_468 as F
import revolution_service_whole as wh
import revolution_service_wsublet as ws
from test_revolution_service_wsublet_468 import NO_TYPE_DIGEST_BEFORE_R468, digest, parse
from test_revolution_service_whole_479 import FULL_PARAMS, whole

H = ws.BASE_HEADERS + ['Description of sublet', 'PO #']


def line(ro='J139900001', line_no=1, hours=2.5, po='GP13990001', dept=139, advisor='OB', stock='SYN0001'):
    raw = dict(zip(ws.BASE_HEADERS, [dept, stock, 'SYN-R0001', 'Synthetic Owner', 'A1', '7', ro, '20', line_no,
                                     'Synthetic operation', hours, '23/10/2026', 'HILUX']))
    raw['Description of sublet'] = 'Sublet' if po else None
    raw['PO #'] = po
    raw['Create Advisor'] = advisor
    return raw


def sheet(rows, typed=False, advisor_header='Create Advisor', footer_advisor=''):
    headers = (['Type'] if typed else []) + H + [advisor_header]
    out = [(ws.TITLE,), ('Extracted on 23/10/2026   Parameters: Company = "01" Division = "1"',), (None,), tuple(headers)]
    for raw in rows:
        cells = [raw.get(h) for h in H] + [raw.get('Create Advisor')]
        out.append(tuple((['D'] + cells) if typed else cells))
    footer = [None] * len(H)
    footer[H.index('Estimated labour hours')] = 1
    footer.append(footer_advisor)
    out.append(tuple((['T1'] + footer) if typed else footer))
    return out


def add_advisor(values, fill='OB'):
    """Append a filled Create Advisor cell on every data row and a blank one on the totals footer."""
    rows = [list(r) for r in values]
    rows[3] = list(rows[3]) + ['Create Advisor']
    last = len(rows) - 1
    for i in range(4, len(rows)):
        rows[i] = list(rows[i]) + ['' if i == last else fill]
    return rows


class Headers509(unittest.TestCase):
    def test_trailing_column_is_dropped(self):
        self.assertEqual(ws.check_headers(H + ['Create Advisor']), H)
        self.assertEqual(ws.check_headers(H + ['Create Advisor', None, '']), H)
        self.assertEqual(ws.check_headers(['Type'] + H + [' Create Advisor ']), H)
        self.assertEqual(ws.check_headers(['="%s"' % h for h in H] + ['="Create Advisor"', None]), H)
        self.assertTrue(ws.has_create_advisor_column(H + ['Create Advisor', None]))
        self.assertFalse(ws.has_create_advisor_column(H))
        self.assertEqual(ws.source_create_advisor_column(H + ['Create Advisor']), ws.CREATE_ADVISOR_DROPPED)
        self.assertEqual(ws.source_create_advisor_column(H), ws.CREATE_ADVISOR_ABSENT)

    def test_advisor_anywhere_but_last_is_refused(self):
        bad = (
            H + ['Create Advisor', 'PO #'],
            H[:5] + ['Create Advisor'] + H[5:],
            ['Create Advisor'] + H,
            H + ['create advisor'],
            H + ['Create advisor'],
            H + ['Create Advisor', 'Create Advisor'],
            ws.BASE_HEADERS + ['Create Advisor'],
        )
        for headers in bad:
            with self.assertRaises(ws.ContractError):
                ws.check_headers(headers)
        with self.assertRaisesRegex(ws.ContractError, 'only accepted as the last column'):
            ws.check_headers(H[:5] + ['Create Advisor'] + H[5:])
        with self.assertRaisesRegex(ws.ContractError, 'exactly .Create Advisor.'):
            ws.check_headers(H + ['create advisor'])


class Read509(unittest.TestCase):
    def test_without_the_column_parses_as_before(self):
        got = ws.read_values(F.build())
        self.assertEqual(digest(parse(F.build())), NO_TYPE_DIGEST_BEFORE_R468)
        self.assertEqual(got.create_advisor['column'], ws.CREATE_ADVISOR_ABSENT)
        self.assertEqual(got.create_advisor['blank_data_rows'], 0)
        self.assertFalse(got.create_advisor['closes_board_cards'])

    def test_a_filled_column_does_not_change_the_lines(self):
        for typed in (False, True):
            base = F.build(typed=typed)
            self.assertEqual(digest(parse(add_advisor(base))), NO_TYPE_DIGEST_BEFORE_R468, typed)

    def test_blank_advisor_data_rows_are_not_imported(self):
        rows = [
            line(hours=3, advisor='OB', po='GP13990001'),
            line(hours=9, advisor='', po='GP13990002'),          # same line, blank advisor, different hours
            line(ro='J139900002', advisor='   ', po=None),
            line(ro='J139900003', advisor='GR', po=None, stock='SYN0003'),
            line(ro='J135900001', dept=135, advisor='', po=None),
        ]
        got = ws.read_values(sheet(rows, footer_advisor=''))
        h, data, footer, excluded, _ = got
        self.assertEqual(h, H)
        self.assertEqual(got.create_advisor['blank_data_row_numbers'], [6, 7])
        self.assertEqual(got.create_advisor['kept_data_rows'], 2)
        self.assertEqual(got.create_advisor['rule'], ws.CREATE_ADVISOR_RULE)
        self.assertFalse(got.create_advisor['closes_board_cards'])
        ros = [ws.norm(raw['R/O #']) for _, raw in data]
        self.assertEqual(ros, ['J139900001', 'J139900003'])
        self.assertNotIn('J139900002', ros)
        for _, raw in data + footer + excluded:
            self.assertNotIn('Create Advisor', raw)
            self.assertNotIn('Type', raw)
        self.assertEqual((len(footer), len(excluded)), (1, 1))
        lines, summary = ws.collapse(data)
        self.assertEqual(lines[0]['raw']['Estimated labour hours'], 3)
        self.assertEqual(lines[0]['sublet_pos'], ['GP13990001'])
        self.assertFalse(lines[0]['collapse']['conflict'])
        self.assertEqual(summary['conflicts'], [])
        self.assertEqual([ln['raw']['R/O #'] for ln in lines], ['J139900001', 'J139900003'])

    def test_footer_advisor_is_not_a_data_row_and_a_bad_kept_row_still_stops_the_file(self):
        got = ws.read_values(sheet([line(advisor='BP')], typed=True, footer_advisor='99'))
        self.assertEqual(got.create_advisor['blank_data_rows'], 0)
        self.assertEqual(len(got[2]), 1)
        self.assertNotIn('Create Advisor', got[2][0][1])
        bad = line(advisor='OB')
        bad['Line #'] = 0
        with self.assertRaisesRegex(ws.ContractError, 'Line #'):
            ws.read_values(sheet([bad]))


class Whole509(unittest.TestCase):
    def test_filename_and_parameters(self):
        self.assertTrue(wh.FILENAME_RE.match('CreateAdvisor-Service-as-a-Whole.xlsx'))
        self.assertTrue(wh.FILENAME_RE.match('CreateAdvisor-Service-as-a-Whole.xls'))
        self.assertTrue(wh.FILENAME_RE.match('PMG PD Service as a Whole w/Sublet - Job 1.xlsx'))
        self.assertFalse(wh.FILENAME_RE.match('CreateAdvisor-Service-as-a-Whole.csv'))
        self.assertFalse(wh.FILENAME_RE.match('PMG PD Service Complete w/Sublet.xlsx'))
        wh.check_parameters(FULL_PARAMS + ' and Create Advisor <> ""')
        with self.assertRaises(wh.ContractError):
            wh.check_parameters('Parameters: Create Advisor <> ""')

    def test_formula_headers_and_source_headers_drop_the_column(self):
        base = add_advisor(F.build())
        wrapped = whole(base, params=FULL_PARAMS + ' and Create Advisor <> ""')
        self.assertIn('="Create Advisor"', wrapped[3])
        got = wh.read_values(wrapped)
        self.assertEqual(wh.source_headers(wrapped), ws.check_headers(F.build()[3]))
        self.assertNotIn('Create Advisor', wh.source_headers(wrapped))
        self.assertEqual(got.create_advisor['column'], ws.CREATE_ADVISOR_DROPPED)
        self.assertEqual(got.create_advisor['blank_data_rows'], 0)
        self.assertFalse(got.create_advisor['closes_board_cards'])
        self.assertEqual(ws.collapse(got[1]), ws.collapse(ws.read_values(F.build())[1]))
        self.assertIn('never closes', wh.reconcile.__doc__)


if __name__ == '__main__':
    unittest.main()
