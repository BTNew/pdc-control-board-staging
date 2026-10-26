"""Read-only evidence comparison; never starts a restore or contacts a database."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest

sys.dont_write_bytecode = True
module_path = Path(__file__).resolve().parents[1] / 'tools' / 'functional-monitor' / 'run_isolated_workflows.py'
spec = importlib.util.spec_from_file_location('isolated_monitor', module_path)
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def fingerprint(name, schema='public', value='a' * 32):
    return {'schema': schema, 'proname': name, 'arguments': 'p_id uuid', 'definition_hash': value}


class FingerprintEvidenceTests(unittest.TestCase):
    def test_missing_new_private_routine_is_blocked_even_when_old_rows_match(self):
        old = [fingerprint('workshop_extend_running_booking_538')]
        result = monitor.compare_fingerprints(old, old, monitor.RUNNING_GROWTH_FINGERPRINTS)
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertIn('pdc_operation_updates_private.reconcile_running_growth_20261026', result['missing_required_functions'])

    def test_same_named_public_function_cannot_substitute_private_definition(self):
        expected = [fingerprint('reconcile_running_growth_20261026', 'pdc_operation_updates_private')]
        restored = [fingerprint('reconcile_running_growth_20261026')]
        result = monitor.compare_fingerprints(expected, restored, set())
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(len(result['different_functions']), 1)

    def test_stale_restored_definition_is_blocked(self):
        expected = [fingerprint('workshop_extend_running_booking_538')]
        restored = [fingerprint('workshop_extend_running_booking_538', value='b' * 32)]
        self.assertEqual(monitor.compare_fingerprints(expected, restored, set())['status'], 'BLOCKED')

    def test_missing_restored_function_is_blocked_with_valid_hash(self):
        expected = [fingerprint('workshop_extend_running_booking_538')]
        result = monitor.compare_fingerprints(expected, [], set())
        self.assertEqual(result['status'], 'BLOCKED')
        self.assertEqual(result['different_functions'], ['public.workshop_extend_running_booking_538(p_id uuid)'])

    def test_null_hashes_cannot_pass_when_all_required_functions_are_absent(self):
        expected = [fingerprint(name, schema, None) for schema, name in monitor.RUNNING_GROWTH_FINGERPRINTS]
        with self.assertRaisesRegex(ValueError, 'Invalid function definition fingerprint hash'):
            monitor.compare_fingerprints(expected, [], monitor.RUNNING_GROWTH_FINGERPRINTS)

    def test_both_evidence_sides_require_a_complete_hex_digest(self):
        for value in [None, '', 'a' * 31, 'a' * 33, 'g' * 32, ' ' + 'a' * 32, 1234]:
            for side in ['expected', 'restored']:
                with self.subTest(value=value, side=side):
                    good = [fingerprint('safe_name')]
                    malformed = [fingerprint('safe_name', value=value)]
                    args = (malformed, good) if side == 'expected' else (good, malformed)
                    with self.assertRaisesRegex(ValueError, 'Invalid function definition fingerprint hash'):
                        monitor.compare_fingerprints(*args, set())
        missing_hash = fingerprint('safe_name')
        missing_hash.pop('definition_hash')
        with self.assertRaisesRegex(ValueError, 'Invalid function definition fingerprint hash'):
            monitor.compare_fingerprints([missing_hash], [], set())

    def test_hexadecimal_case_does_not_change_a_valid_digest(self):
        expected = [fingerprint('safe_name', value='ABCD' * 8)]
        restored = [fingerprint('safe_name', value='abcd' * 8)]
        self.assertEqual(monitor.compare_fingerprints(expected, restored, set())['status'], 'PASS')

    def test_complete_matching_namespaced_evidence_passes(self):
        rows = [fingerprint(name, schema) for schema, name in monitor.RUNNING_GROWTH_FINGERPRINTS]
        self.assertEqual(monitor.compare_fingerprints(rows, rows, monitor.RUNNING_GROWTH_FINGERPRINTS)['status'], 'PASS')

    def test_legacy_public_evidence_is_still_understood(self):
        expected = [fingerprint('schedule_vehicle_work')]
        expected[0].pop('schema')
        self.assertEqual(monitor.compare_fingerprints(expected, [fingerprint('schedule_vehicle_work')], set())['status'], 'PASS')

    def test_invalid_namespace_is_not_used_as_sql(self):
        with self.assertRaises(ValueError):
            monitor.compare_fingerprints([fingerprint('safe_name', "public'; select 1; --")], [], set())

    def test_long_combined_evidence_is_read_without_helper_tail_truncation(self):
        rows = [fingerprint('routine_' + str(i)) for i in range(60)]
        self.assertGreater(len(json.dumps(rows)), 6000)
        reads = []
        def query(sql):
            reads.append(sql)
            selected = [x for x in rows if "p.proname='" + x['proname'] + "'" in sql]
            return {'returncode': 0, 'stdout_tail': json.dumps(selected)[-6000:]}
        self.assertEqual(len(monitor.read_restored_fingerprints(query, rows)), 60)
        self.assertEqual(len(reads), 60)

    def test_individual_truncated_evidence_is_refused(self):
        with self.assertRaisesRegex(ValueError, 'Incomplete restored'):
            monitor.read_restored_fingerprints(lambda sql: {'returncode': 0, 'stdout_tail': 'x' * 6000}, [fingerprint('overloaded')])


if __name__ == '__main__':
    unittest.main()
