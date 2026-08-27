from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "apply_migration_716_staging.py"
PARENT = "b96c8fae340a8e0471196a5cf3e9b8bc8a6b9c1a"
CANDIDATE = "a" * 40
CANDIDATE_TREE = "c" * 40
PARENT_TREE = "4884de6c46f2294df81427f9a5e4904373790f6f"
IDENTITY = "Hermes Agent\x00hermes-agent@local\x00Hermes Agent\x00hermes-agent@local"


def load_controller():
    spec = importlib.util.spec_from_file_location("apply_migration_716_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class ApplyMigration716HardeningTests(unittest.TestCase):
    def test_hostile_psycopg2_and_bootstrap_do_not_execute_before_attestation_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            shadow = Path(directory)
            (shadow / "psycopg2.py").write_text(
                "print('HOSTILE_PSYCOPG2_EXECUTED', flush=True)\nraise SystemExit('hostile psycopg2')\n",
                encoding="utf-8",
            )
            hostile_bootstrap = shadow / "pdc_staging_bootstrap.py"
            hostile_bootstrap.write_text(
                "print('HOSTILE_BOOTSTRAP_EXECUTED', flush=True)\nraise SystemExit('hostile bootstrap')\n",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["PYTHONPATH"] = str(shadow) + os.pathsep + env.get("PYTHONPATH", "")
            code = (
                "import importlib.util, pathlib, sys\n"
                f"spec=importlib.util.spec_from_file_location('controller', {str(SCRIPT)!r})\n"
                "m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
                f"m.BOOTSTRAP_PATH=pathlib.Path({str(hostile_bootstrap)!r})\n"
                f"m.SECRET_PATH=pathlib.Path({str(shadow / 'secret.dpapi')!r})\n"
                f"m.git=lambda *args: {{('rev-parse','--show-toplevel'): str(m.ROOT), ('rev-parse','HEAD'): {CANDIDATE!r}, ('rev-parse','HEAD^'): 'wrong-parent', ('rev-parse','HEAD^{{tree}}'): 'wrong-tree', ('status','--porcelain=v1','--untracked-files=all'): '', ('show','-s','--format=%an%x00%ae%x00%cn%x00%ce','HEAD'): {IDENTITY!r}}}[args]\n"
                f"m.main(['--apply','--expected-commit', {CANDIDATE!r}])\n"
            )
            completed = subprocess.run(
                [sys.executable, "-c", code],
                cwd=ROOT,
                env=env,
                capture_output=True,
                text=True,
            )
            output = completed.stdout + completed.stderr
            self.assertNotEqual(completed.returncode, 0)
            self.assertNotIn("HOSTILE_PSYCOPG2_EXECUTED", output)
            self.assertNotIn("HOSTILE_BOOTSTRAP_EXECUTED", output)
            self.assertIn("PARENT_COMMIT_MISMATCH", output)

    def test_reviewed_read_only_path_reaches_database_verify_without_apply(self):
        controller = load_controller()
        calls = []

        class Cursor:
            def execute(self, sql, params=()):
                calls.append((sql, params))

            def fetchone(self):
                sql = calls[-1][0].lower()
                if "select project_ref" in sql:
                    return (controller.EXPECTED_REF,)
                if "production_environment_sentinel" in sql:
                    return (False,)
                if "max(version)" in sql:
                    return ("20260828040000",)
                return None

            def fetchall(self):
                return [("20260828040000", "716_close_all_raw_navision_acl_grantees")]

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        class Connection:
            def __init__(self):
                self.autocommit = False

            def cursor(self):
                return Cursor()

            def rollback(self):
                calls.append(("ROLLBACK", ()))

            def close(self):
                calls.append(("CLOSE", ()))

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

        fake_psycopg2 = types.ModuleType("psycopg2")
        fake_psycopg2.connect = lambda *args, **kwargs: calls.append(("CONNECT", kwargs)) or Connection()
        values = {
            "PDC_STAGING_DATABASE_URL": "postgresql://staging.invalid/db",
            "PDC_STAGING_SSLROOTCERT": "C:/trusted/staging-ca.pem",
        }
        git_values = {
            ("rev-parse", "--show-toplevel"): str(controller.ROOT),
            ("rev-parse", "HEAD"): CANDIDATE,
            ("rev-parse", "HEAD^"): PARENT,
            ("rev-parse", "HEAD^{tree}"): CANDIDATE_TREE,
            ("status", "--porcelain=v1", "--untracked-files=all"): "",
            ("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", "HEAD"): IDENTITY,
        }
        with (
            mock.patch.object(controller, "git", side_effect=lambda *args: git_values[args]),
            mock.patch.object(controller, "load_staging_values", return_value=values),
            mock.patch.dict(sys.modules, {"psycopg2": fake_psycopg2}),
        ):
            result = controller.main(["--expected-commit", CANDIDATE])

        self.assertTrue(result["ok"])
        self.assertFalse(result["applied"])
        self.assertTrue(any(item[0] == "CONNECT" for item in calls))
        self.assertTrue(any("select project_ref" in item[0].lower() for item in calls if isinstance(item[0], str)))
        self.assertFalse(any("alter " in item[0].lower() or "insert " in item[0].lower() for item in calls if isinstance(item[0], str)))

    def test_apply_requires_exact_confirmation_before_loading_credentials(self):
        controller = load_controller()
        git_values = {
            ("rev-parse", "--show-toplevel"): str(controller.ROOT),
            ("rev-parse", "HEAD"): CANDIDATE,
            ("rev-parse", "HEAD^"): PARENT,
            ("rev-parse", "HEAD^{tree}"): CANDIDATE_TREE,
            ("status", "--porcelain=v1", "--untracked-files=all"): "",
            ("show", "-s", "--format=%an%x00%ae%x00%cn%x00%ce", "HEAD"): IDENTITY,
        }
        with (
            mock.patch.object(controller, "git", side_effect=lambda *args: git_values[args]),
            mock.patch.object(controller, "load_staging_values", side_effect=AssertionError("credentials loaded")),
        ):
            with self.assertRaisesRegex(controller.Stop, "APPLY_CONFIRMATION_MISSING"):
                controller.main(["--apply", "--expected-commit", CANDIDATE])


if __name__ == "__main__":
    unittest.main(verbosity=2)
