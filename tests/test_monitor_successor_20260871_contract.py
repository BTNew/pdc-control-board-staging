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

    def test_builder_control_hash_matches_installer_and_verifier_tree_contract(self):
        source = (ROOT / 'scripts/build_pdc_monitor_successor_20260871.py').read_text(encoding='utf-8')
        self.assertIn('def tree_hash(', source)
        self.assertIn('control_sha = tree_hash(control_root)', source)
        self.assertNotIn('control_sha = inventory_hash(control_inventory)', source)
        self.assertIn('manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\\n", encoding="utf-8", newline="\\n")', source)

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

    def test_installer_creates_root_control_before_copy_and_wrapper_stays_disabled(self):
        installer = (ROOT / 'scripts/install_pdc_monitor_successor_20260871.ps1').read_text(encoding='utf-8')
        wrapper = (ROOT / 'scripts/PDCMonitor-Install-20260871-Elevated.ps1').read_text(encoding='utf-8')
        self.assertIn("New-Item -ItemType Directory -Path $stageRootControl -Force", installer)
        self.assertNotIn('-EnableAutomation', wrapper)
        self.assertIn('$ExpectedManifestSha256=', wrapper)
        self.assertIn('$InstallerSha256=', wrapper)
        self.assertIn('Hash $Installer', wrapper)
        self.assertNotIn('$ExpectedManifest=(Get-FileHash', wrapper)

    def test_protected_continuation_gates_verifyonly_and_onecycle_before_enable(self):
        path = ROOT / 'scripts/verify_onecycle_enable_pdc_monitor_20260871.ps1'
        source = path.read_text(encoding='utf-8')
        verify_at = source.index('current-head-preflight.py')
        onecycle_at = source.index("active-dispatch.ps1")
        enable_at = source.index('Enable-ScheduledTask')
        self.assertLess(verify_at, onecycle_at)
        self.assertLess(onecycle_at, enable_at)
        self.assertIn("$Task='PDC-PMB-Email-Monitor-Staging'", source)
        self.assertIn("$status.production_contacted -ne $false", source)
        self.assertIn("$status.uid514_processed -ne $false", source)
        self.assertNotIn('Start-ScheduledTask', source)

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

    def test_desktop_launcher_keeps_receipt_path_separate_from_record_object(self):
        source = (ROOT / 'scripts/launch_pdc_monitor_successor_20260871.ps1').read_text(encoding='utf-8')
        self.assertIn('$RecordPath=', source)
        self.assertNotIn('-LiteralPath $Record ', source)


if __name__ == '__main__':
    unittest.main(verbosity=2)
