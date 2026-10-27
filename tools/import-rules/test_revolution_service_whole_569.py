"""r570 (F184): a new as-a-Whole R/O is sent as new_board_vehicle unless Sub Status 99. Apply places both a
division vehicle and a non-division vehicle in the New vehicle section. A complete file archives a 138/139 board
vehicle that is absent from the sheet. Broome Sales and Karratha Sales rows are not written. Synthetic fixtures only."""
import unittest

import revolution_service_whole as wh
import test_revolution_service_whole_479 as t479


def lines(spec):
    return t479.lines(spec)


class Archive569(unittest.TestCase):
    def test_unknown_stock_is_a_board_create_and_the_snapshot_status_stays_blank(self):
        x = wh.resolve_ro('J139900077', 'SYN0099', None, t479.IDX)
        self.assertEqual(x['status'], 'no_board_vehicle')
        self.assertEqual(x['reason'], 'stock_not_on_board')
        self.assertIsNone(x['stock'])
        self.assertEqual((x['board_action'], x['send'], x['board_basis'], x['board_stock'], x['rego_fallback']),
                         ('create_board', True, wh.BOARD_BASIS, 'SYN0099', False))
        linked = wh.identity_r479(wh.resolve_ro('J139900001', 'SYN0001', None, t479.IDX))
        self.assertEqual(linked, {'rule': wh.IDENTITY_RULE, 'basis': 'stock_column'})

    def test_rego_fallback_only_when_stock_is_blank(self):
        x = wh.resolve_ro('J139900077', None, 'SYNREGO', t479.IDX)
        self.assertEqual((x['status'], x['reason'], x['rego_fallback'], x['board_stock']),
                         ('no_board_vehicle', 'rego_not_a_board_stock_and_no_job_card', True, 'SYNREGO'))
        self.assertEqual(wh.identity_r479(x)['rego_fallback'], True)
        kept = wh.resolve_ro('J139900077', 'SYN0099', 'SYNREGO', t479.IDX)
        self.assertEqual(kept['board_stock'], 'SYN0099')
        self.assertFalse(kept['rego_fallback'])

    def test_status_99_does_not_create_and_80_does(self):
        spec = [('139', 'J139900077', 1, 'SYN0099', None, '99'),
                ('139', 'J139900078', 1, 'SYN0098', None, '99'),
                ('139', 'J139900078', 2, 'SYN0098', None, '22'),
                ('139', 'J139900079', 1, 'SYN0097', None, '80')]
        ident = wh.resolve_lines(lines(spec), t479.IDX)
        self.assertEqual(ident[('139', 'J139900077')]['board_action'], 'skip_status_99')
        self.assertFalse(ident[('139', 'J139900077')]['send'])
        self.assertIn('status_99', ident[('139', 'J139900077')]['skip_reasons'])
        mixed = ident[('139', 'J139900078')]
        self.assertEqual(mixed['board_action'], 'create_board')
        self.assertTrue(mixed['send'])
        sent = [L['raw']['Line #'] for L in lines(spec) if wh.preview_line_allowed(L['raw'], ident[('139', L['raw']['R/O #'])])]
        self.assertEqual(sent, [2, 1])
        self.assertEqual(ident[('139', 'J139900079')]['board_action'], 'create_board')
        self.assertNotIn('status_99', ident[('139', 'J139900079')]['skip_reasons'])

    def test_hold_and_restore_are_skips_beyond_status_99(self):
        board = {'vehicles': list(t479.BOARD['vehicles']), 'jobs': list(t479.BOARD['jobs']),
                 'holds': ['SYN0099'], 'restores': ['SYN0098']}
        idx = wh.board_index(board)
        hold = wh.resolve_ro('J139900077', 'SYN0099', None, idx)
        self.assertEqual(hold['board_action'], 'skip_owner_hold')
        self.assertFalse(hold['send'])
        restore = wh.resolve_ro('J139900078', None, 'SYN0098', idx)
        self.assertEqual((restore['board_action'], restore['rego_fallback']), ('skip_pending_restore', True))
        both = wh.resolve_lines(lines([('139', 'J139900078', 1, None, 'SYN0098', '99')]), idx)[('139', 'J139900078')]
        self.assertEqual(both['board_action'], 'skip_status_99')
        self.assertEqual(sorted(both['skip_reasons']), ['pending_restore', 'status_99'])
        self.assertIsNone(wh.identity_r479(both))

    def test_existing_linked_row_is_unchanged_including_a_99_line(self):
        spec = [('139', 'J139900001', 1, 'SYN0001', None, '99')]
        ident = wh.resolve_lines(lines(spec), t479.IDX)[('139', 'J139900001')]
        self.assertEqual((ident['status'], ident['basis'], ident['board_action'], ident['send']),
                         ('linked', 'stock_column', 'existing_row', True))
        self.assertTrue(wh.preview_line_allowed(lines(spec)[0]['raw'], ident))
        self.assertEqual(wh.preview_stock_number(ident, lines(spec)[0]['raw']), 'SYN0001')

    def test_not_live_and_no_identity_are_not_sent(self):
        gone = wh.resolve_ro('J139900004', 'SYN0004', None, t479.IDX)
        self.assertEqual(gone['status'], 'vehicle_not_live')
        self.assertFalse(gone['send'])
        blank = wh.resolve_ro('J139900078', '', '', t479.IDX)
        self.assertFalse(blank['send'])
        self.assertIsNone(blank['board_action'])

    def test_snapshot_line_for_a_create_stays_no_board_vehicle_with_empty_stock(self):
        spec = [('138', 'J138900050', 1, 'SYN0050', 'R50', '20')]
        payload = wh.snapshot_payload('a' * 64, '2026-10-22T04:02:00+00:00', lines(spec), wh.resolve_lines(lines(spec), t479.IDX))
        self.assertEqual(payload['lines'][0][7], 'no_board_vehicle')
        self.assertIsNone(payload['lines'][0][3])
        self.assertEqual(payload['lines'][0][4], 'SYN0050')

    def test_stamp_requires_the_snapshot_sha(self):
        header = {'snapshot_sha256': 'ab' * 32, 'snapshot_scope': wh.SNAPSHOT_SCOPE}
        raw = {'Dept': '139', 'Sub Status': '22'}
        stamped = wh.stamp_preview_row(raw, header, 'PMG PD Service as a Whole w/Sublet.xlsx')
        self.assertEqual(stamped['snapshot_sha256'], 'ab' * 32)
        self.assertEqual(raw.get('snapshot_sha256'), None)
        self.assertNotIn('CreateAdvisor', stamped['source_filename'])
        with self.assertRaises(wh.ContractError):
            wh.stamp_preview_row(raw, {'snapshot_sha256': 'abc'}, 'x.xlsx')

    def test_both_creates_stay_in_the_new_vehicle_section(self):
        division = wh.board_decision('new_board_vehicle', False, 'SYN0001', 1, '14450', False, False)
        self.assertEqual(division['action'], 'create_division')
        self.assertEqual(division['location'], 'Yard Hold')
        self.assertFalse(division['visible'])
        self.assertFalse(division['new_to_pmb'])
        self.assertFalse(division['broome_sales'])
        self.assertEqual(division['link'], 'navision')
        self.assertEqual(division['dealer_code'], '14450')
        broome = wh.board_decision('new_board_vehicle', False, 'SYN0001', 1, '37047', False, False)
        self.assertEqual(broome['dealer_code'], '37047')
        self.assertFalse(broome['broome_sales'])
        plain = wh.board_decision('new_board_vehicle', False, 'SYN0000', 0, None, False, False)
        self.assertEqual((plain['action'], plain['location'], plain['visible'], plain['new_to_pmb'], plain['link']),
                         ('create_new_vehicle', 'Yard Hold', False, False, 'tune'))
        self.assertEqual(wh.board_decision('new_board_vehicle', True, 'SYN0099', 0, None, False, False)['action'], 'skip_status_99')
        self.assertEqual(wh.board_decision('stock_column', False, 'SYN0001', 1, '14450', False, False)['action'], 'existing_row')

    def test_file_guard_allows_a_complete_createadvisor_file(self):
        ok = wh.file_qc_guard(6751, 465, True, 6731, 'PMG PD Service as a Whole w/Sublet.xlsx', wh.SNAPSHOT_SCOPE)
        self.assertEqual(ok, {'ok': True, 'reason': 'complete_file'})
        self.assertEqual(wh.file_qc_guard(0, 0, True, 6731, 'a.xlsx', wh.SNAPSHOT_SCOPE)['reason'], 'empty_file')
        self.assertEqual(wh.file_qc_guard(6751, 465, False, 6731, 'a.xlsx', wh.SNAPSHOT_SCOPE)['reason'], 'partial_file')
        self.assertEqual(wh.file_qc_guard(500, 50, True, 6731, 'a.xlsx', wh.SNAPSHOT_SCOPE)['reason'], 'below_minimum_size')
        self.assertEqual(wh.file_qc_guard(2000, 200, True, 6731, 'a.xlsx', wh.SNAPSHOT_SCOPE)['reason'], 'partial_vs_previous')
        self.assertEqual(wh.file_qc_guard(6751, 465, True, None, 'a.xlsx', wh.SNAPSHOT_SCOPE)['reason'], 'no_previous_complete_snapshot')
        named = wh.file_qc_guard(6700, 460, True, 6731, 'CreateAdvisor-Service-as-a-Whole.xlsx', wh.SNAPSHOT_SCOPE)
        self.assertEqual(named, {'ok': True, 'reason': 'complete_file'})
        self.assertEqual(wh.file_qc_guard(6751, 465, True, 6731, 'a.xlsx', 'other')['reason'], 'not_full_snapshot')

    def test_sales_rows_stay_untouched_including_a_vehicle_on_both_boards(self):
        # A vehicle on the PMB board and also on Broome Sales (37047) or Karratha Sales (14450)
        # is archived on the PMB side only. The Sales record is not written.
        self.assertEqual(wh.SALES_DEALERS['broome'], ('37047', '037047'))
        self.assertEqual(wh.SALES_DEALERS['karratha'], ('14450', '014450'))
        dual = wh.archive_decision(True, False, False, True, True)
        self.assertTrue(dual['archive'])
        self.assertTrue(dual['on_sales_board'])
        self.assertFalse(dual['sales_write'])
        self.assertFalse(dual['hide_sales'])
        self.assertFalse(dual['delete'])
        self.assertFalse(dual['tombstone'])
        self.assertTrue(dual['booking_released'])
        self.assertTrue(dual['live_booking_reported'])
        pmb_only = wh.archive_decision(True, False, False, True, False)
        self.assertTrue(pmb_only['archive'])
        self.assertFalse(pmb_only['sales_write'])
        self.assertEqual(wh.archive_decision(False, False, False, True, True)['reason'], 'not_pmb_board')
        self.assertFalse(wh.archive_decision(False, False, False, True, True)['sales_write'])
        self.assertEqual(wh.archive_decision(True, True, False, True, True)['reason'], 'on_sheet')
        self.assertEqual(wh.archive_decision(True, False, True, True, False)['reason'], 'dept_135')
        self.assertEqual(wh.archive_decision(True, False, False, False, True)['reason'], 'file_not_ok')
        restored = wh.unarchive_plan(
            {'visible_on_board': True, 'pmb_stage': 'fit', 'pmb_bay_stage': None, 'pmb_bay_number': '4'},
            [{'booking_id': 'booking-1', 'bay_id': 'bay-1', 'status': 'queued'}])
        self.assertTrue(restored['visible_on_board'])
        self.assertIsNone(restored['board_purged_at'])
        self.assertIsNone(restored['deleted_at'])
        self.assertFalse(restored['sales_write'])
        self.assertEqual(restored['bookings'], [{'id': 'booking-1', 'bay_id': 'bay-1', 'status': 'queued'}])
        hidden = wh.unarchive_plan({'visible_on_board': False, 'pmb_stage': None, 'pmb_bay_stage': None, 'pmb_bay_number': None}, [])
        self.assertFalse(hidden['visible_on_board'])
        self.assertEqual(hidden['bookings'], [])


if __name__ == '__main__':
    unittest.main()
