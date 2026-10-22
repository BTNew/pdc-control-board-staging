"""r479 (F92): 'PMG PD Service as a Whole w/Sublet' (full open-R/O snapshot). Synthetic fixtures only (SYN..., J13x9...)."""
import unittest

import fixtures_service_wsublet_468 as F
import revolution_service_wsublet as ws
import revolution_service_whole as wh

FULL_PARAMS = ('Extracted on 22/10/2026 12:02   Parameters: Company = "01" Division = "1" (Dept = "138" or Dept = "139") '
               'and Status >= "20" and Status < "90"')


def whole(values, params=FULL_PARAMS, wrap=True):
    v = [list(r) for r in values]
    v[0][0] = wh.TITLE
    v[1][0] = params
    if wrap:
        v[3] = ['="%s"' % h for h in v[3]]
    return v


def veh(i, stock, jc=None, ls='active', deleted=False):
    return {'id': '00000000-0000-4000-8000-%012d' % i, 'stock': stock, 'jc': jc, 'ls': ls, 'deleted': deleted}


BOARD = {'vehicles': [veh(1, 'SYN0001'), veh(2, 'SYN0002', jc='J139900002'), veh(3, 'SYN-RG03'), veh(4, 'SYN0004', ls='completed'),
                      veh(5, 'SYN0005'), veh(6, 'SYN0005B'), veh(7, 'SYN0007', ls='rft'), veh(8, 'SYN0008', deleted=True),
                      veh(9, 'SYN0009'), veh(10, 'SYN0010')],
         'jobs': [{'vehicle_id': '00000000-0000-4000-8000-%012d' % 9, 'ro': 'J139900009', 'closed': False},
                  {'vehicle_id': '00000000-0000-4000-8000-%012d' % 1, 'ro': 'J139900001', 'closed': False},
                  {'vehicle_id': '00000000-0000-4000-8000-%012d' % 1, 'ro': 'J139900091', 'closed': False},
                  {'vehicle_id': '00000000-0000-4000-8000-%012d' % 10, 'ro': 'J139900010', 'closed': False},
                  {'vehicle_id': '00000000-0000-4000-8000-%012d' % 7, 'ro': 'J139900007', 'closed': True}]}
IDX = wh.board_index(BOARD)


class Reader479(unittest.TestCase):
    def test_unwrap_header(self):
        self.assertEqual(wh.unwrap_header('="Dept"'), 'Dept')
        self.assertEqual(wh.unwrap_header(' = "Stock #" '), 'Stock #')
        self.assertEqual(wh.unwrap_header('="Say ""hi"""'), 'Say "hi"')
        self.assertEqual(wh.unwrap_header('Rego #'), 'Rego #')

    def test_parameters_must_be_a_full_snapshot(self):
        wh.check_parameters(FULL_PARAMS)
        for p in [F.PARAMS, FULL_PARAMS.replace('Dept = "138" or ', ''), FULL_PARAMS.replace('< "90"', '< "80"'),
                  FULL_PARAMS.replace('Division = "1"', 'Division = "2"')]:
            with self.assertRaises(wh.ContractError):
                wh.check_parameters(p)

    def test_title_and_filename(self):
        with self.assertRaises(wh.ContractError):
            wh.read_values(F.build())                      # the w/Sublet title is not 'as a Whole'
        self.assertTrue(wh.FILENAME_RE.match('PMG PD Service as a Whole w/Sublet - Job 1.xlsx'))
        self.assertTrue(wh.FILENAME_RE.match('PMG PD Service as a Whole w_Sublet.xlsx'))
        self.assertFalse(wh.FILENAME_RE.match('PMG PD Service Complete w/Sublet.xlsx'))

    def test_same_rows_as_wsublet_with_and_without_wrapping_and_type(self):
        for typed in (False, True):
            base = F.build(typed)
            expect = ws.read_values(base)
            for wrap in (True, False):
                got = wh.read_values(whole(base, wrap=wrap))
                self.assertEqual(got[:4], expect[:4])
                self.assertEqual(ws.collapse(got[1]), ws.collapse(expect[1]))
        lines, summary = ws.collapse(wh.read_values(whole(F.build()))[1])
        self.assertEqual(summary['lines'], F.EXPECTED['lines'])
        self.assertEqual(summary['distinct_pos'], F.EXPECTED['distinct_pos'])
        self.assertEqual(wh.source_headers(whole(F.build())), ws.check_headers(F.build()[3]))


class Identity479(unittest.TestCase):
    def r(self, ro, st, rg):
        return wh.resolve_ro(ro, st, rg, IDX)

    def test_stock_column_exact(self):
        x = self.r('J139900001', 'SYN0001', 'X')
        self.assertEqual((x['status'], x['basis'], x['stock']), ('linked', 'stock_column', 'SYN0001'))
        self.assertEqual(self.r('J139900001', ' syn0001 ', None)['status'], 'linked')
        x = self.r('J139900001', 'SYN000', None)            # no prefix / fuzzy match
        self.assertEqual((x['status'], x['reason']), ('no_board_vehicle', 'stock_not_on_board'))

    def test_a_stock_number_never_falls_back_to_rego_or_job_card(self):
        x = self.r('J139900002', 'SYN9999', 'SYN0001')
        self.assertEqual(x['status'], 'no_board_vehicle')

    def test_blank_stock(self):
        self.assertEqual(self.r('J139900003', None, 'SYN-RG03')['basis'], 'rego_column_exact_board_stock')
        self.assertEqual(self.r('J139900002', '', 'NOTONBOARD')['basis'], 'job_card_exact')
        self.assertEqual(self.r('J139900009', '', None)['basis'], 'job_card_service_job')
        x = self.r('J139900077', '', 'NOTONBOARD')
        self.assertEqual((x['status'], x['reason']), ('no_board_vehicle', 'rego_not_a_board_stock_and_no_job_card'))
        self.assertEqual(self.r('J139900078', '', '')['reason'], 'no_stock_no_rego_no_job_card')

    def test_not_live_and_ambiguous(self):
        self.assertEqual(self.r('J139900004', 'SYN0004', None)['status'], 'vehicle_not_live')
        self.assertEqual(self.r('J139900008', 'SYN0008', None)['board_states'], ['deleted'])
        self.assertEqual(self.r('J139900007', 'SYN0007', None)['status'], 'linked')   # rft is live
        x = self.r('J139900002', '', 'SYN0005')            # rego -> one vehicle, job card -> another
        self.assertEqual(x['status'], 'ambiguous')

    def test_lines_of_one_ro_disagree(self):
        L = [{'raw': {'Dept': '139', 'R/O #': 'J139900001', 'Line #': 1, 'Stock #': 'SYN0001', 'Rego #': None}},
             {'raw': {'Dept': '139', 'R/O #': 'J139900001', 'Line #': 2, 'Stock #': 'SYN0002', 'Rego #': None}}]
        self.assertEqual(wh.resolve_lines(L, IDX)[('139', 'J139900001')]['status'], 'ambiguous')


def lines(spec):
    return [{'raw': {'Dept': d, 'R/O #': ro, 'Line #': n, 'Stock #': st, 'Rego #': rg, 'Sub Status': ss}} for d, ro, n, st, rg, ss in spec]


class Snapshot479(unittest.TestCase):
    SPEC = [('139', 'J139900001', 1, 'SYN0001', None, '20'), ('139', 'J139900001', 2, 'SYN0001', None, '80'),
            ('139', 'J139900010', 1, 'SYN0010', None, '80'), ('139', 'J139900010', 2, 'SYN0010', None, '99'),
            ('138', 'J138900050', 1, 'SYN0050', 'R50', '20')]

    def payload(self, sha, at, spec=None):
        L = lines(spec or self.SPEC)
        return wh.snapshot_payload(sha, at, L, wh.resolve_lines(L, IDX), lib_md5='x')

    def test_payload(self):
        p = self.payload('a' * 64, '2026-10-22T04:02:00+00:00')
        self.assertEqual(p['header']['line_count'], 5)
        self.assertEqual(p['header']['ro_count'], 3)
        self.assertEqual(p['header']['snapshot_scope'], wh.SNAPSHOT_SCOPE)
        self.assertEqual(p['lines'][0], ['139', 'J139900001', 1, 'SYN0001', 'SYN0001', None, '20', 'linked'])
        self.assertEqual(p['lines'][4][7], 'no_board_vehicle')
        self.assertEqual(len(p['lines'][0]), len(wh.LINE_FIELDS))
        with self.assertRaises(wh.ContractError):
            self.payload('A' * 64, 'x')

    def test_reconcile_one_then_two_snapshots(self):
        s1 = self.payload('a' * 64, '2026-10-22T04:02:00+00:00')
        r = wh.reconcile([s1], BOARD)
        self.assertEqual(r['counts'], {'ro_all_lines_80_99_still_open': 1, 'open_ro_no_board_vehicle': 1,
                                       'board_ro_missing_pending': 1, 'board_vehicle_missing_pending': 1})
        self.assertEqual([i['ro'] for i in r['items'] if i['category'] == 'ro_all_lines_80_99_still_open'], ['J139900010'])
        self.assertEqual([i['ro'] for i in r['items'] if i['category'] == 'board_ro_missing_pending'], ['J139900091'])
        self.assertEqual([i['stock'] for i in r['items'] if i['category'] == 'board_vehicle_missing_pending'], ['SYN0009'])
        s2 = self.payload('b' * 64, '2026-10-22T05:02:00+00:00')
        r = wh.reconcile([s1, s2], BOARD)
        self.assertEqual(r['counts'].get('board_ro_missing'), 1)
        self.assertEqual(r['counts'].get('board_vehicle_missing'), 1)
        self.assertNotIn('board_ro_missing_pending', r['counts'])

    def test_present_in_either_of_the_two_snapshots_is_not_missing(self):
        s1 = self.payload('a' * 64, '2026-10-22T04:02:00+00:00', self.SPEC + [('139', 'J139900009', 1, None, None, '20')])
        s2 = self.payload('b' * 64, '2026-10-22T05:02:00+00:00')
        r = wh.reconcile([s1, s2], BOARD)
        self.assertNotIn('board_vehicle_missing', r['counts'])
        self.assertEqual(r['counts'].get('board_ro_missing'), 1)

    def test_reconcile_never_touches_the_board(self):
        import copy, json
        before = json.dumps(BOARD, sort_keys=True)
        wh.reconcile([self.payload('a' * 64, '2026-10-22T04:02:00+00:00')], copy.deepcopy(BOARD))
        self.assertEqual(json.dumps(BOARD, sort_keys=True), before)
        self.assertEqual(wh.reconcile([], BOARD)['note'], 'no_complete_snapshot')


if __name__ == '__main__':
    unittest.main()
