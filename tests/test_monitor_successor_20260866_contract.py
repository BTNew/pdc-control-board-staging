from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class MonitorSuccessor20260866ContractTests(unittest.TestCase):
    def test_refresh_and_control_artifacts_exist(self):
        for rel in (
            "scripts/pdc_monitor_refresh_20260866.py",
            "scripts/build_pdc_monitor_successor_20260866.py",
            "scripts/verify_pdc_monitor_successor_20260866.py",
            "scripts/install_pdc_monitor_successor_20260866.ps1",
            "scripts/pdc_monitor_active_dispatch_20260866.ps1",
            "scripts/pdc_monitor_active_bootstrap_20260866.ps1",
            "scripts/pdc_monitor_verifyonly_bootstrap_20260866.ps1",
        ):
            self.assertTrue((ROOT / rel).is_file(), rel)

    def test_machine_refresh_is_exact_scope_and_fail_closed(self):
        text = (ROOT / "scripts/pdc_monitor_refresh_20260866.py").read_text(encoding="utf-8")
        for marker in (
            "CRYPTPROTECT_LOCAL_MACHINE",
            "ACTOR_EMAIL",
            "sales@broometoyota.com.au",
            "pdc-monitor-staging-sales-uid509-v1",
            "PROJECT = \"cdsmnqxtyyoeoznmbidd\"",
            "URL = f\"https://{PROJECT}.supabase.co\"",
            "PDC_MONITOR_REFRESH_MACHINE_DENIED",
            "secrets_printed",
            "production_contacted",
        ):
            self.assertIn(marker, text)
        for forbidden in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_DB_URL", "PDC_ADMIN_JWT"):
            self.assertNotIn(forbidden, text)

    def test_dispatch_refreshes_before_preflight_and_uses_manifest_only_inventory(self):
        dispatch = (ROOT / "scripts/pdc_monitor_active_dispatch_20260866.ps1").read_text(encoding="utf-8")
        verifier = (ROOT / "scripts/verify_pdc_monitor_successor_20260866.py").read_text(encoding="utf-8")
        self.assertLess(dispatch.index("pdc_monitor_refresh_20260866.py"), dispatch.index("authenticated_parent_preflight"))
        self.assertIn("PDC_MONITOR_SUCCESSOR_ACTIVE_REFRESH_DENIED", dispatch)
        self.assertIn("p.name!='release-manifest.json'", verifier)
        self.assertIn("successor complete inventory mismatch", verifier)
        self.assertIn("2026.08.44", dispatch)
        self.assertIn("2026.08.66", dispatch)
        bootstrap = (ROOT / "scripts/pdc_monitor_verifyonly_bootstrap_20260866.ps1").read_text(encoding="utf-8")
        self.assertIn("VERIFYONLY_RUNNER_SHA256", bootstrap)
        self.assertIn("venvs\\2026.08.66", dispatch)
        runner = (ROOT / "scripts/pdc_monitor_verifyonly_runner_20260866.ps1").read_text(encoding="utf-8")
        self.assertIn("ValidateSet('OneCycle','Continuous')", runner)
        self.assertIn("[switch]$DryRun", runner)
        installer = (ROOT / "scripts/install_pdc_monitor_successor_20260866.ps1").read_text(encoding="utf-8")
        self.assertIn("CURRENT_NOT_065_OR_066", installer)
        self.assertIn("Scripts\\python.exe", installer)
        self.assertIn("python-runtime\\python.exe", installer)
        self.assertIn("$venvCfg=Join-Path $venv 'pyvenv.cfg'", installer)
        self.assertIn("home = $install", installer)
        self.assertIn("active-preflight-authenticated-mailbox-compatibility.py", dispatch)
        self.assertIn("control\\2026.08.44", dispatch)
        self.assertIn("Status 'running' 'PDC_MONITOR_SUCCESSOR_ACTIVE_REACHED_MONITOR' $true $false $false", dispatch)
        self.assertIn("PDC_AGENTIC_EMAIL_ENABLED=true", installer)
        self.assertIn("$targetManifest", installer)
        self.assertIn("Split-Path -Parent $targetMember", installer)
        self.assertIn("New-Item (Split-Path -Parent $targetMember)", installer)
        self.assertNotIn("Where-Object Name -eq '__pycache__'|Remove-Item", installer)
        self.assertIn("PDC_AGENTIC_EMAIL_ENABLED=true", installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
