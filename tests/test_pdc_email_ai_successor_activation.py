import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'activate_pdc_email_ai_successor_20260869.ps1'
VERIFY = ROOT / 'scripts' / 'verify_pdc_email_ai_successor_20260869.py'


class ActivationContractTests(unittest.TestCase):
    def test_minimal_activation_files_exist_and_are_guarded(self):
        self.assertTrue(SCRIPT.is_file())
        self.assertTrue(VERIFY.is_file())
        source = SCRIPT.read_text(encoding='utf-8')
        for marker in ('install-receipt.json', '2026.08.69', 'fa528d8d1ce405b430dc265ded7dca69cc7b49e8d190b90d9e55576b32a1a823', 'PDC-PMB-Email-Monitor-Staging', 'LOCAL SERVICE', 'PT5M', 'Enable-ScheduledTask'):
            self.assertIn(marker, source)
        self.assertNotIn('Start-ScheduledTask', source)
        self.assertNotIn('schtasks.exe /Run', source)
        py = VERIFY.read_text(encoding='utf-8')
        for marker in ('pdc_email_ai_successor', 'get_pdc_email_ai_successor_health', 'get_pdc_email_ai_transaction_successor_inbox_v2', 'get_pdc_email_vehicle_location_snapshot', 'service_role', 'production'):
            self.assertIn(marker, py)

    def test_activation_is_not_the_installer(self):
        source = SCRIPT.read_text(encoding='utf-8')
        self.assertNotIn('PDCMonitor-Install-20260869.ps1', source)
        self.assertNotIn('PDCMonitor-Install-20260869-Elevated.ps1', source)


if __name__ == '__main__':
    unittest.main()
