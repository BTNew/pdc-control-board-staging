from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MonitorSuccessor20260871ContractTests(unittest.TestCase):
    def test_builder_binds_both_repairs_and_current_head(self):
        builder = ROOT / 'scripts/build_pdc_monitor_successor_20260871.py'
        self.assertTrue(builder.is_file())
        source = builder.read_text(encoding='utf-8')
        for marker in (
            '2026.08.71', '2026.08.69', '20260831380000',
            '--storage-bridge-source', '--processor-source',
            '--active-bootstrap-source', '--active-dispatch-source',
            '--current-head-preflight-source', 'VENV_SEED_SHA256',
            'CONTROL_SHA256', 'TRUST-VALUES.json', 'outbound_email_enabled',
        ):
            self.assertIn(marker, source)

    def test_installer_is_atomic_and_preserves_rollback(self):
        installer = ROOT / 'scripts/install_pdc_monitor_successor_20260871.ps1'
        self.assertTrue(installer.is_file())
        source = installer.read_text(encoding='utf-8')
        for marker in (
            "2026.08.71", "2026.08.69", '.staging', 'Move-Item',
            'releases', 'venvs', 'control', 'trust', 'VENV_SHA256.tsv',
            'CURRENT', 'task_started=$false', 'mailbox_contacted=$false',
        ):
            self.assertIn(marker, source)
        self.assertNotRegex(source, r'Start-ScheduledTask|schtasks(?:\.exe)?\s+/Run|OneCycle|PDCMonitor-Install-20260869')

    def test_active_controls_bind_live_head(self):
        for name in (
            'pdc_monitor_active_bootstrap_20260871.ps1',
            'pdc_monitor_active_dispatch_20260871.ps1',
            'pdc_monitor_current_head_preflight_20260871.py',
        ):
            source = (ROOT / 'scripts' / name).read_text(encoding='utf-8')
            self.assertIn('2026.08.71', source)
            self.assertIn('20260831380000', source)
            if 'dispatch' in name or 'preflight' in name:
                self.assertIn('cdsmnqxtyyoeoznmbidd', source)

    def test_release_manifest_schema_requires_all_hash_domains(self):
        receipt = ROOT / 'scripts/pdc_monitor_successor_20260871_receipt.schema.json'
        self.assertTrue(receipt.is_file())
        data = json.loads(receipt.read_text(encoding='utf-8'))
        self.assertEqual(data['required'], [
            'ok', 'release_version', 'parent_release_version', 'manifest_sha256',
            'parent_manifest_sha256', 'storage_bridge_sha256', 'processor_sha256',
            'venv_sha256', 'control_sha256', 'trust_sha256', 'current_staging_migration_head',
            'task_enabled', 'task_started', 'mailbox_contacted', 'production_contacted',
        ])


if __name__ == '__main__':
    unittest.main(verbosity=2)
