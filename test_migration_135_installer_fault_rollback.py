import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

try:
    import psycopg2
except ImportError:  # The project staging venv supplies this dependency.
    psycopg2 = None

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "scripts" / "apply_migration_135_staging.py"
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))


@unittest.skipUnless(psycopg2 is not None and os.environ.get("PDC_RUN_LIVE_STAGING_FAULT_TESTS") == "1", "set PDC_RUN_LIVE_STAGING_FAULT_TESTS=1 for credentialed live-staging rollback probe")
class Migration135InstallerFaultRollbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from staging_env import assert_staging_target, load_local_env

        load_local_env()
        cls.dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
        if not cls.dsn:
            raise unittest.SkipTest("staging database URL is not configured")
        assert_staging_target(database_url=cls.dsn)

    def snapshot(self):
        with psycopg2.connect(self.dsn) as conn, conn.cursor() as cur:
            cur.execute(
                """select jsonb_build_object(
                  'ledger135',exists(select 1 from supabase_migrations.schema_migrations where version='135'),
                  'core',to_regprocedure('public.pdc_auto_apply_ai_intake_activation_internal(uuid,uuid,text,boolean)') is not null,
                  'pre135',to_regprocedure('public.submit_pdc_ai_intake_observation_pre135(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)') is not null,
                  'decision_receipts',to_regclass('public.pdc_ai_intake_auto_activation_receipts') is not null,
                  'batch_receipts',to_regclass('public.pdc_ai_intake_auto_backlog_receipts') is not null,
                  'pending_activation',(select count(*) from public.pdc_ai_intake_proposals where status='pending' and action_type='board_activate_only'),
                  'pending_review',(select count(*) from public.pdc_ai_intake_proposals where status='pending' and action_type='review_only'),
                  'inbox_revision',(select revision from public.pdc_ai_intake_revision where singleton),
                  'navision_revision',(select revision from public.navision_backend_revision where singleton),
                  'active_activations',(select count(*) from public.navision_board_activations where active),
                  'visible_vehicles',(select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active' and visible_on_board),
                  'work_items',(select count(*) from public.vehicle_work_items),
                  'parts_updates',(select count(*) from public.vehicle_parts_updates),
                  'bookings',(select count(*) from public.workshop_bookings),
                  'auto_history',(select count(*) from public.pdc_ai_intake_history where details->>'automatic'='true'),
                  'auto_audit',(select count(*) from public.navision_backend_audit where evidence->>'contract'='pdc_ai_intake_auto_135')
                )"""
            )
            return cur.fetchone()[0]

    def test_intentional_postcheck_failure_rolls_back_every_surface(self):
        before = self.snapshot()
        completed = subprocess.run(
            [sys.executable, str(SCRIPT), "--fault-inject-postcheck-failure"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertNotEqual(completed.returncode, 0, completed.stdout)
        self.assertIn("intentional postcheck failure before commit", completed.stderr)
        after = self.snapshot()
        self.assertEqual(after, before, json.dumps({"before": before, "after": after}, sort_keys=True))
        self.assertFalse(after["ledger135"])
        self.assertFalse(after["core"])
        self.assertFalse(after["pre135"])
        self.assertFalse(after["decision_receipts"])
        self.assertFalse(after["batch_receipts"])


if __name__ == "__main__":
    unittest.main()
