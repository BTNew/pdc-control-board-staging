"""r572 (F186). Named stocks stay in this test. The rule module does not embed them."""
import unittest

from revolution_service_cards import attach, card_close, group, reconcile_flag, reconcile_item


class ServiceCardStack(unittest.TestCase):
    def test_12710970_groups_by_stock_and_keeps_both_cards(self):
        decision = group('12710970', '1ABC123', 1, '139')
        self.assertTrue(decision['group'])
        self.assertEqual(decision['key'], 'stock')
        self.assertFalse(decision['ambiguous'])
        primary = attach(True, True, False, '139')
        second = attach(True, False, False, '139')
        self.assertEqual(primary['reason'], 'existing_card_line')
        self.assertTrue(primary['quarantine'])
        self.assertFalse(second['quarantine'])
        self.assertTrue(second['attach'])
        self.assertEqual(second['reason'], 'new_card')

    def test_u158851_groups_138_and_139_on_the_same_stock(self):
        self.assertEqual(group('U158851', '1HLY556', 1, '138')['key'], 'stock')
        self.assertTrue(group('U158851', '1HLY556', 1, '139')['group'])
        self.assertTrue(attach(True, False, False, '139')['attach'])

    def test_13107437_uses_rego_when_stock_is_blank(self):
        decision = group('', '13107437', 1, '139')
        self.assertTrue(decision['group'])
        self.assertEqual(decision['key'], 'rego')
        self.assertFalse(decision['ambiguous'])

    def test_ambiguous_vehicle_is_not_merged(self):
        decision = group('12710970', '', 2, '139')
        self.assertTrue(decision['ambiguous'])
        self.assertFalse(decision['group'])

    def test_held_card_is_not_attached(self):
        held = attach(True, False, True, '139')
        self.assertFalse(held['attach'])
        self.assertFalse(held['quarantine'])
        self.assertEqual(held['reason'], 'owner_hold')

    def test_department_135_is_not_attached(self):
        self.assertEqual(attach(True, False, False, '135')['reason'], 'dept_135')
        self.assertEqual(group('135STOCK', '', 1, '135')['reason'], 'dept_out_of_scope')

    def test_80_or_99_closes_only_that_card(self):
        one = card_close('99', True)
        self.assertTrue(one['close_card'])
        self.assertFalse(one['close_vehicle'])
        self.assertFalse(one['auto_close'])
        self.assertFalse(one['delete'])
        self.assertFalse(one['hide'])
        last = card_close('80', False)
        self.assertTrue(last['close_vehicle'])
        self.assertFalse(last['auto_close'])
        self.assertFalse(card_close('22', False)['close_card'])

    def test_reconcile_flag_is_an_open_card_with_no_board_lines(self):
        item = reconcile_item('139', 'J139126027', 'U158851', 2, 0, '22')
        self.assertEqual(item['category'], 'open_card_lines_missing_on_board')
        self.assertFalse(reconcile_flag(16, 16, '22'))
        self.assertFalse(reconcile_flag(2, 0, '80'))
        self.assertIsNone(reconcile_item('139', 'J139125207', '12710970', 30, 16, '22'))


if __name__ == '__main__':
    unittest.main()
