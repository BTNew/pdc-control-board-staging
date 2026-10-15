"""Exercise real workshop/database functions in a disposable loopback-only restore.

Uses the already configured, encrypted local backup and restore tools. No remote
database connection is made. The original restore tool and backup files are never
edited. Test SQL cannot commit, and customer data is removed when the server stops.
"""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
import re
import secrets
import socket
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORKSPACE = REPO.parent.parent
BACKUPS = Path(r"C:\Users\craig\PDCBackups")
EXPECTED_PROJECT = "cdsmnqxtyyoeoznmbidd"
RESTORE_HELPER_SHA256 = "2ffeafaae46ed40ab083a0979282a4cb1f309cef85aeeb361c0a30ff2b2b2d5a"
SCENARIOS = [
    ("Moving bookings and conflict scope", "tests/workshop_move_conflict_scope_rollback.sql"),
    ("Start job priority and cascade", "tests/start_priority_cascade_rollback.sql"),
    ("Start job safety guards", "tests/start_priority_guards_rollback.sql"),
    ("Fitters line items and weighted progress", "tests/workshop_fitter_progress_rollback.sql"),
    ("Fitters follow destination bay assignments", "tests/fitter_bay_default_assignment_rollback.sql"),
    ("Return planned bookings to Unallocated", "tests/workshop_planned_unallocate_rollback.sql"),
    ("Close gaps with ready jobs", "tests/workshop_close_gaps_ready_jobs_rollback.sql"),
    ("Vehicle locations and bay ownership", "tests/workshop_location_override_booking_rollback_20260913.sql"),
    ("Calendar and working hours", "tests/workshop_hours_0600_1630_rollback.sql"),
    ("Best slot without pushing other vehicles", "tests/workshop_best_slot_no_cascade_rollback.sql"),
    ("Emergency priority", "tests/workshop_emergency_priority_rollback.sql"),
    ("Finance entry editing and permissions", "tests/broome_finance_pipeline_rollback.sql"),
    ("Sales Autocare dispatch", "tests/broome_sales_autocare_dispatch_rollback.sql"),
    ("Navision Broome and Pilbara access", "tests/navision_upload_staff_access_rollback.sql"),
    ("Delivered at dealer lifecycle cleanup", "tools/functional-monitor/dealer_delivery_rollback.sql"),
    ("Website activity and permissions", "scripts/test_staff_usage_all_pages_rollback.sql"),
]

def validate_sql(sql: str) -> None:
    # Remove line comments for this boundary check. Existing reviewed scenarios
    # use exactly one top-level transaction and finish with ROLLBACK.
    text = re.sub(r"--[^\n]*", "", sql)
    if not re.match(r"\s*begin\b", text, re.I) or not re.search(r"\brollback\s*;", text, re.I):
        raise ValueError("Workflow test must begin a transaction and roll back")
    if re.search(r"\bcommit\s*;|\b(?:dblink|http_post|http_get|http_request|net\.http|copy\s+.*program)\b", text, re.I):
        raise ValueError("Committing or outbound calls are forbidden in workflow tests")

def latest_backup() -> tuple[Path, dict]:
    for directory in sorted(BACKUPS.iterdir(), reverse=True):
        manifest_path = directory / "manifest.json"
        if not directory.is_dir() or not manifest_path.is_file():
            continue
        info = json.loads(manifest_path.read_text(encoding="utf-8"))
        if info.get("project") != EXPECTED_PROJECT or info.get("integrity_readback_verified") is not True:
            continue
        if not all((directory / name).is_file() for name in ("database.dump.pdc", "roles.sql.pdc")):
            continue
        age = datetime.now(timezone.utc) - datetime.fromisoformat(info["finished_at"])
        if age.total_seconds() < -300 or age.total_seconds() > 8 * 3600:
            raise ValueError("Latest verified backup is older than eight hours or has an invalid timestamp")
        return directory, info
    raise ValueError("No verified encrypted staging backup is available")

def run(output: Path, scenario_names: list[str] | None = None, fingerprints: Path | None = None) -> dict:
    output = output.resolve()
    private_root = (WORKSPACE / "work" / "functional-monitor-private").resolve()
    if not output.is_relative_to(private_root) or output == private_root or output.exists():
        raise ValueError("A fresh run directory inside functional-monitor-private is required")
    backup, manifest = latest_backup()
    helper_path = WORKSPACE / "work" / "run_restore_test.py"
    if hashlib.sha256(helper_path.read_bytes()).hexdigest() != RESTORE_HELPER_SHA256:
        raise ValueError("Local restore tool changed; review it before unattended execution")
    spec = importlib.util.spec_from_file_location("functional_restore", helper_path)
    if spec is None or spec.loader is None:
        raise ValueError("Verified local restore tool is unavailable")
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    helper.BACKUP_DIR, helper.REPORT_ROOT = backup, output
    helper.REPORT_FILE = output / "restore-report.private.json"
    helper.STATUS_FILE = output / "restore-status.private.json"
    # The audited restore helper binds this name in several function defaults.
    # It is a fresh cluster, so retaining the name cannot overwrite another DB.
    helper.DATABASE_NAME = "pdc_restore_check"
    output.mkdir(parents=True)
    summary = {"started_at": datetime.now(timezone.utc).isoformat(), "project": EXPECTED_PROJECT,
        "test_vehicle_label": "TEST VEHICLE", "backup_finished_at": manifest["finished_at"],
        "live_database_modified": False, "outbound_emails": False, "scenarios": [],
        "browser_drag_checks": "NOT RUN: authenticated computer-use connection unavailable"}
    expected = None
    if fingerprints:
        expected = json.loads(fingerprints.read_text(encoding="utf-8"))
        if expected.get("project") != EXPECTED_PROJECT or not expected.get("functions"):
            raise ValueError("Wrong or empty backend fingerprint evidence")
    password = secrets.token_urlsafe(32)
    pwfile = output / "local-password.private"
    pwfile.write_text(password, encoding="utf-8")
    previous_password = os.environ.get("PGPASSWORD")
    os.environ["PGPASSWORD"] = password
    original_run, original_psql, original_scrub = helper.run, helper.psql, helper.scrub_plaintext

    def safe_scrub(paths):
        safe = []
        for candidate in paths:
            resolved = Path(candidate).resolve()
            if not resolved.is_relative_to(output) or resolved == output:
                raise ValueError("Refusing cleanup outside this private run")
            if resolved.name == "pgdata" and (resolved / "postmaster.pid").exists():
                # Never remove data files from a still-running test server.
                continue
            safe.append(resolved)
        return original_scrub(safe)
    helper.scrub_plaintext = safe_scrub

    def safe_run(cmd, **kwargs):
        args = [str(x) for x in cmd]
        if Path(args[0]).name == "initdb.exe":
            args[args.index("-A") + 1] = "scram-sha-256"
            args.extend(["--pwfile", str(pwfile)])
        if Path(args[0]).name == "pg_restore.exe":
            # Functional permission tests require the original ACLs. All roles
            # were restored in this disposable cluster; owner mapping stays local.
            args = [x for x in args if x != "--no-acl"]
        return original_run(args, **kwargs)
    helper.run = safe_run

    def test_after_jobs_disabled(env, sql, database="postgres", **kwargs):
        result = original_psql(env, sql, database=database, **kwargs)
        if "if to_regclass('cron.job')" not in sql:
            return result
        if env.get("PGHOST") != "127.0.0.1" or database != "pdc_restore_check":
            raise ValueError("Refusing any non-local workflow database")
        port = int(env.get("PGPORT", "0"))
        if not 55432 <= port < 55520:
            raise ValueError("Unexpected local test database port")
        if result["returncode"] != 0:
            raise ValueError("Scheduled jobs could not be disabled in the test copy")
        safe = original_psql(env, "select count(*) from pg_extension where extname not in ('plpgsql','pgcrypto','uuid-ossp','citext','pg_trgm','btree_gist');", database=database, timeout=15)
        if safe["stdout_tail"].strip() != "0":
            raise ValueError("Unexpected extension in the disposable test database")
        if expected:
            names = sorted({x["proname"] for x in expected["functions"]})
            if any(not re.fullmatch(r"[a-z_0-9]+", name) for name in names):
                raise ValueError("Invalid function fingerprint name")
            clause = ",".join("'" + name + "'" for name in names)
            found = original_psql(env, "select coalesce(jsonb_agg(jsonb_build_object('proname',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),'definition_hash',md5(pg_get_functiondef(p.oid)))),'[]') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in (" + clause + ");", database=database, timeout=20)
            local = {(x["proname"],x["arguments"]):x["definition_hash"] for x in json.loads(found["stdout_tail"])}
            mismatch = [x["proname"] for x in expected["functions"] if local.get((x["proname"],x["arguments"])) != x["definition_hash"]]
            summary["backend_version_check"] = {"status":"BLOCKED" if mismatch else "PASS", "different_functions":mismatch,
                "live_checked_at":expected["checked_at"]}
        else:
            summary["backend_version_check"] = {"status":"NOT RUN","reason":"No current read-only live fingerprint evidence supplied"}
        # Read and booking-boundary test fixture. This row exists only in the copy.
        fixture = """begin;
          insert into public.vehicles(permanent_vehicle_id,stock_number,customer_name,
            vehicle_description,current_location,visible_on_board,source_system,source_record_id,source_payload)
          values('functional-monitor-test-vehicle','TEST-VEHICLE','TEST VEHICLE',
            'TEST VEHICLE - isolated functional checks only','PMB',true,
            'functional_monitor_isolated','TEST-VEHICLE','{"test_vehicle":true,"isolated_copy":true}');
          select 'TEST VEHICLE created and read back' from public.vehicles
            where permanent_vehicle_id='functional-monitor-test-vehicle' and customer_name='TEST VEHICLE';
          rollback;"""
        probe = original_psql(env, fixture, database=database, timeout=20)
        summary["test_vehicle"] = "PASS" if "TEST VEHICLE created and read back" in probe["stdout_tail"] else "FAIL"
        selected = [row for row in SCENARIOS if not scenario_names or row[0] in scenario_names]
        if not selected:
            raise ValueError("No workflow scenarios were selected")
        for name, relative in selected:
            text = (REPO / relative).read_text(encoding="utf-8")
            validate_sql(text)
            # Make the synthetic label unambiguous without changing identifiers.
            text = text.replace("ROLLBACK FIXTURE ", "TEST VEHICLE ")
            if relative.startswith("tests/start_priority_"):
                # These historical start-now scenarios assume now is an open
                # minute. Give only their transaction an explicit test calendar;
                # the separate working-hours scenario tests the real calendar.
                clock_setup = """
INSERT INTO public.workshop_settings(key,value,scope) VALUES
 ('day_start_time','"00:00"','global'),('day_end_time','"23:59"','global'),
 ('working_week','["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]','global'),
 ('closures','[]','global'),('break_windows','[]','global'),('overtime_windows','[]','global')
ON CONFLICT(key) DO UPDATE SET value=excluded.value;
"""
                text = text.replace("SET LOCAL TIME ZONE 'Australia/Perth';", "SET LOCAL TIME ZONE 'Australia/Perth';\n" + clock_setup, 1)
            if relative == "tests/workshop_location_override_booking_rollback_20260913.sql":
                # The owner changed the vehicle handover from five hours to one
                # after this historical scenario was written. Keep its other checks.
                text = text.replace("interval '5 hours'", "interval '1 hour'").replace("five-hour vehicle handover", "one-hour vehicle handover")
            test_file = output / "scenario.private.sql"
            test_file.write_text(text, encoding="utf-8")
            try:
                executed = helper.psql_file(env, test_file, database=database, timeout=300, on_error_stop=True)
                status = "PASS" if executed["returncode"] == 0 else "FAIL"
                # Detailed SQL diagnostics stay in the private run directory.
                (output / (re.sub(r"[^a-z0-9]+", "-", name.lower()) + ".private.log")).write_text(
                    executed["stdout_tail"] + "\n" + executed["stderr_tail"], encoding="utf-8")
                summary["scenarios"].append({"name": name, "status": status})
            except Exception as exc:
                summary["scenarios"].append({"name": name, "status": "BLOCKED", "reason": type(exc).__name__})
        return result
    helper.psql = test_after_jobs_disabled
    try:
        helper.main()
        report = json.loads(helper.REPORT_FILE.read_text(encoding="utf-8"))
        summary["restore_passed"] = report.get("restore_passed", False)
        summary["local_server_stopped"] = report.get("steps", {}).get("local_postgres_stopped", {}).get("returncode") == 0
        summary["plaintext_removed"] = not (output / "scratch").exists() and not (output / "pgdata").exists()
    except Exception as exc:
        summary["setup_status"] = "BLOCKED"
        summary["setup_reason"] = type(exc).__name__
        (output / "setup-error.private.log").write_text(str(exc), encoding="utf-8")
    finally:
        # Also clean up if restore/init/verification fails before the helper's own
        # cleanup block. These absolute paths were checked inside the fresh run root.
        pgdata = output / "pgdata"
        if pgdata.exists():
            stopped = helper.run_quiet([helper.PG_SERVER_BIN / "pg_ctl.exe", "-D", pgdata, "-m", "fast", "-w", "stop"], timeout=120, check=False)
            summary["local_server_stopped"] = stopped["returncode"] == 0 or not (pgdata / "postmaster.pid").exists()
            helper.scrub_plaintext([output / "scratch", pgdata])
        summary["plaintext_removed"] = not (output / "scratch").exists() and not pgdata.exists()
        pwfile.unlink(missing_ok=True)
        if previous_password is None:
            os.environ.pop("PGPASSWORD", None)
        else:
            os.environ["PGPASSWORD"] = previous_password
    summary["finished_at"] = datetime.now(timezone.utc).isoformat()
    passed = bool(summary.get("restore_passed") and summary.get("test_vehicle") == "PASS" and summary.get("local_server_stopped") and summary.get("plaintext_removed") and summary["scenarios"] and all(x["status"] == "PASS" for x in summary["scenarios"]))
    summary["database_workflow_status"] = "PASS" if passed else "FAIL"
    summary["coverage_gaps"] = ["Authenticated browser interaction and dragging", "Storage file contents and external provider integrations"]
    if summary.get("backend_version_check", {}).get("status") != "PASS":
        summary["coverage_gaps"].append("Current live backend version not fully verified against restored copy")
    summary["overall"] = "CHECKS_PASSED_WITH_COVERAGE_GAPS" if passed else "FAIL"
    # Never convert partial coverage or a version mismatch into an all-clear.
    (output / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scenario", action="append", choices=[name for name, _ in SCENARIOS])
    parser.add_argument("--fingerprints", type=Path)
    args = parser.parse_args()
    result = run(args.output, args.scenario, args.fingerprints)
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["database_workflow_status"] == "PASS" else 1)
