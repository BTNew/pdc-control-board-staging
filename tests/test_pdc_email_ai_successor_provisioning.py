import unittest
from pathlib import Path

from pglast import parse_sql

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase' / 'staging_only' / '20260831350000_pdc_email_ai_successor_owner_provisioning.sql'
SCRIPT = ROOT / 'scripts' / 'provision_pdc_email_ai_successor_staging.py'


class SuccessorProvisioningTests(unittest.TestCase):
    def test_owner_provisioning_is_one_shot_and_scoped(self):
        sql = MIGRATION.read_text(encoding='utf-8')
        for marker in (
            'pdc_email_ai_successor_provisioning_receipts',
            'commission_pdc_email_ai_successor_runtime',
            'rollback_pdc_email_ai_successor_runtime',
            '20260831340000',
            'pdc-email-ai-successor-069',
            'pdc-emails',
            'service_role',
            'FORCE ROW LEVEL SECURITY',
            'production_environment_sentinel',
            'get_pdc_email_ai_transaction_successor_inbox_v2',
            'apply_pdc_email_ai_transaction_successor',
            'get_pdc_email_vehicle_location_snapshot',
        ):
            self.assertIn(marker, sql)
        self.assertNotIn('PDC_STAGING_SERVICE_ROLE_KEY', sql)
        self.assertNotIn('password', sql.lower())
        self.assertGreaterEqual(len(parse_sql(sql)), 12)

    def test_controller_uses_in_process_protected_secret_flow(self):
        source = SCRIPT.read_text(encoding='utf-8')
        for marker in ('load_local_env', 'admin_create_user', 'admin_delete_user', 'CryptProtectData', 'icacls', 'generate_password', 'PDC_STAGING_SERVICE_ROLE_KEY'):
            self.assertIn(marker, source)
        self.assertNotIn('service_role_key =', source.lower())
        self.assertNotIn('password = "', source.lower())
        self.assertIn('pdc-email-ai-successor-staging@broometoyota.com.au', source)


if __name__ == '__main__':
    unittest.main()
