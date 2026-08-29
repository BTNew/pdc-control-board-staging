from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/20260830050000_766_monitor_current_head_compatibility.sql"


def load_builder():
    path = ROOT / "scripts/build_pdc_monitor_successor_20260868.py"
    spec = importlib.util.spec_from_file_location("build_monitor_766", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MonitorSuccessor20260868ContractTests(unittest.TestCase):
    def test_control_artifacts_exist(self):
        for relative in (
            "scripts/build_pdc_monitor_successor_20260868.py",
            "scripts/verify_pdc_monitor_successor_20260868.py",
            "scripts/install_pdc_monitor_successor_20260868.ps1",
            "scripts/pdc_monitor_current_head_preflight_20260868.py",
            "scripts/pdc_monitor_active_dispatch_20260868.ps1",
            "scripts/pdc_monitor_verifyonly_runner_20260868.ps1",
            "scripts/pdc_monitor_verifyonly_bootstrap_20260868.ps1",
            "scripts/pdc_monitor_refresh_20260868.py",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_processor_patch_targets_current_authenticated_provider_wrapper(self):
        module = load_builder()
        with tempfile.TemporaryDirectory(prefix="hermes-verify-766-") as directory:
            path = Path(directory) / "processor.py"
            path.write_text(
                'attested = attestor.rpc("attest_pdc_provider_email_observation", {\n'
                '            "p_intake_id": request["intake_id"],\n',
                encoding="utf-8",
            )
            module.patch_processor(path)
            text = path.read_text(encoding="utf-8")
            self.assertIn("attest_pdc_monitor_provider_email_observation_current_766", text)
            self.assertIn('"p_gateway_instance_id": self.gateway_instance_id', text)
            self.assertIn('"p_claim_token": str(record.get("claim_token") or "")', text)

    def test_sql_is_current_head_guarded_and_append_only(self):
        sql = SQL.read_text(encoding="utf-8").lower()
        for marker in (
            "20260830040000",
            "20260830050000",
            "765_authenticated_exact_claim_floor_640_successor",
            "766_monitor_current_head_compatibility",
            "verify_pdc_monitor_runtime_binding_authenticated_766",
            "attest_pdc_monitor_provider_email_observation_current_766",
            "claim_pdc_email_intake_authenticated_exact_732",
            "process_claimed_pdc_email_intake_work",
            "minimum_uid=640",
            "force row level security",
            "mailbox_contacted",
            "uid514_processed",
            "production_writes",
            "pdc_production_environment_sentinel",
        ):
            self.assertIn(marker, sql)
        self.assertNotIn("update public.monitored_mailboxes", sql)
        self.assertNotIn("insert into public.ai_email_intake", sql)
        self.assertNotIn("insert into public.ai_email_attachments", sql)
        self.assertNotIn("enable scheduledtask", sql)
        self.assertRegex(sql, r"revoke all on function public\.verify_pdc_monitor_runtime_binding_authenticated_766")
        self.assertRegex(sql, r"grant execute on function public\.verify_pdc_monitor_runtime_binding_authenticated_766[^;]+ to authenticated")
        self.assertRegex(sql, r"grant execute on function public\.attest_pdc_monitor_provider_email_observation_current_766[^;]+ to authenticated")

    def test_runtime_dispatch_refreshes_and_preflights_before_monitor(self):
        dispatch = (ROOT / "scripts/pdc_monitor_active_dispatch_20260868.ps1").read_text(encoding="utf-8")
        self.assertLess(dispatch.index("pdc_monitor_refresh_20260868.py"), dispatch.index("current_head_preflight"))
        self.assertLess(dispatch.index("current_head_preflight"), dispatch.index("runtime_launcher.py") if "runtime_launcher.py" in dispatch else dispatch.index("monitor_entrypoint"))
        self.assertIn("current_staging_migration_head", dispatch)
        self.assertIn("uid514_processed", dispatch)
        self.assertIn("PDC_MONITOR_766_REFRESH_DENIED", dispatch)
        self.assertIn("-DryRun", (ROOT / "scripts/pdc_monitor_verifyonly_bootstrap_20260868.ps1").read_text(encoding="utf-8"))

    def test_install_is_elevated_and_never_enables_task(self):
        installer = (ROOT / "scripts/install_pdc_monitor_successor_20260868.ps1").read_text(encoding="utf-8")
        self.assertIn("IsInRole", installer)
        self.assertIn("ELEVATION_REQUIRED", installer)
        self.assertIn("$task.State -ne 'Disabled'", installer)
        self.assertIn("$currentValue -ne $Parent -and $currentValue -ne $Version", installer)
        self.assertNotIn("Enable-ScheduledTask", installer)
        self.assertNotIn("Start-ScheduledTask", installer)
        self.assertIn("MachineStoreSource", installer)
        self.assertIn("monitor-refresh.dpapi", installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
