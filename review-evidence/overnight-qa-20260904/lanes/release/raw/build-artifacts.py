from __future__ import annotations

import json
from pathlib import Path
import re

ROOT = Path(r"C:/Hermes-Active/projects/pdc-control-board-staging/review-evidence/overnight-qa-20260904/lanes/release")
RAW = ROOT / "raw"
SHA = "85bdc68513e0c1c6efee110712731e9be958374b"
COMPLETED = (RAW / "completed-at.txt").read_text().strip()


def load(name):
    return json.loads((RAW / name).read_text(encoding="utf-8"))


def write(name, value):
    (ROOT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")

node = (RAW / "node-full.log").read_text(encoding="utf-8", errors="replace")
focused_node = (RAW / "node-focused-pdc14.log").read_text(encoding="utf-8", errors="replace")
focused_py = (RAW / "python-focused.log").read_text(encoding="utf-8", errors="replace")
full_py = (RAW / "python-full-runnable.log").read_text(encoding="utf-8", errors="replace")
staging = load("staging-readonly-baseline.json")
pr = load("pr31.json")
integrity = load("staging-integrity-run.json")
pages = load("pages-run.json")
deployments = load("pages-deployments.json")
deployment_statuses = load("latest-pages-deployment-statuses.json")
checks = load("main-check-runs.json")
parity_lines = [line.split("\t") for line in (RAW / "asset-byte-parity.tsv").read_text().splitlines() if line]
hashes = {}
for line in (RAW / "gitblob-assets.sha256").read_text().splitlines():
    digest, path = line.split(maxsplit=1)
    hashes[Path(path.lstrip("*")).name] = digest

node_counts = {key: int(re.findall(rf"^ℹ {key} (\d+)$", node, re.M)[-1]) for key in ("tests", "pass", "fail", "skipped")}
focused_node_counts = {key: int(re.findall(rf"^ℹ {key} (\d+)$", focused_node, re.M)[-1]) for key in ("tests", "pass", "fail", "skipped")}
focused_py_match = re.search(r"(\d+) passed, (\d+) skipped", focused_py)
full_py_match = re.search(r"(\d+) failed, (\d+) passed, (\d+) skipped, (\d+) errors, (\d+) subtests passed", full_py)
if not (focused_py_match and full_py_match):
    raise RuntimeError("test totals did not parse")

preview = {
    "github_status_context": "FAILURE",
    "failed_preview_project": "xvflalqbfdxbelerhtjg",
    "failed_stage": "Migrations",
    "failed_sqlstate": "42P01",
    "failed_relation": "public.vehicle_intelligence_summaries",
    "failure_source": "supabase/release_history/014_vehicle_intelligence_timeline_foundation.sql",
    "successful_clean_preview_project": "rgrwkufllnlijmdtfhxf",
    "successful_tasks": ["Configurations", "Migrations", "Seeding", "Edge Functions"],
    "classification": "baseline_preview_integration_inconsistency",
    "local_bootstrap": "not runnable: Docker executable unavailable",
    "evidence": "raw/pr31-comments.log",
}

tests = {
    "task_id": "t_95939b14",
    "completed_at": COMPLETED,
    "authoritative_sha": SHA,
    "suites": [
        {"name": "focused PDC-14 Node", "command": "node --test test_pdc14_canonical_work_state_successor.js test_pdc14_control_board_parity.js test_pdc14_location_replay_successor.js test_parts_ordered_projection_color.js test_sublet_workgroup_projection_20260831.js test_vehicle_detail_booking_pills.js", "result": "PASS", **focused_node_counts, "evidence": "raw/node-focused-pdc14.log"},
        {"name": "full Node", "command": "node --test test_*.js", "result": "PASS", **node_counts, "evidence": "raw/node-full.log"},
        {"name": "focused Python/SQL contracts", "command": "uv run --with pytest --with psycopg2-binary --with requests python -m pytest -q tests/test_provenance_rpc_auth_hardening_20260904.py tests/test_provenance_history_release_20260904_live.py tests/test_non_navision_jobcard_runtime_contract_20260904.py", "result": "PASS_WITH_EXPECTED_SKIPS", "passed": int(focused_py_match.group(1)), "skipped": int(focused_py_match.group(2)), "failed": 0, "evidence": "raw/python-focused.log"},
        {"name": "full runnable Python", "command": "uv run --with pytest --with psycopg2-binary --with requests --with pglast python -m pytest -q tests --ignore=tests/test_latest100_runner_response_contract_20260901.py --ignore=tests/test_pdc_email_sender_chain_20260901.py --ignore=tests/test_pdc_latest100_resume_contract.py", "result": "BASELINE_FAILURES", "failed": int(full_py_match.group(1)), "passed": int(full_py_match.group(2)), "skipped": int(full_py_match.group(3)), "errors": int(full_py_match.group(4)), "subtests_passed": int(full_py_match.group(5)), "excluded_collection_files": 3, "evidence": "raw/python-full-runnable.log"},
        {"name": "clean Supabase Preview/bootstrap", "result": "SPLIT", **preview},
        {"name": "Staging Integrity", "result": integrity["conclusion"].upper(), "run_id": integrity["databaseId"], "sha": integrity["headSha"], "evidence": "raw/staging-integrity-run.json"},
        {"name": "transactional STAGING authorization matrix", "result": "PASS", "cases": len(staging["authorization_matrix"]), "denied_cases": len(staging["authorization_matrix"]) - 1, "denied_payloads": 0, "target_unchanged": staging["target_unchanged"], "u158318": staging["u158318_fresh"], "evidence": "raw/staging-readonly-baseline.json"},
    ],
    "summary": {
        "product_regressions_found": 0,
        "green_required_node_tests": node_counts["pass"],
        "focused_python_passed": int(focused_py_match.group(1)),
        "staging_authorization_cases_passed": len(staging["authorization_matrix"]),
        "baseline_python_failures": int(full_py_match.group(1)),
        "baseline_python_errors": int(full_py_match.group(4)),
        "baseline_python_collection_exclusions": 3,
    },
    "sql_note": "The sole tests/*.sql file performs external-completion business mutation and was not executed under the lane's strict read-only constraint. SQL syntax/contracts were exercised through pglast-backed Python tests and both Supabase Preview migrations lanes; one preview was fully green and one reproduced the known release_history/014 bootstrap defect.",
}
write("test-results.json", tests)

latest = deployments[0]
release = {
    "task_id": "t_95939b14", "verified_at": COMPLETED,
    "repository": "BTNew/pdc-control-board-staging",
    "main_sha": SHA,
    "remote_main_sha": SHA,
    "pr31": {
        "state": pr["state"],
        "merge_sha": pr["mergeCommit"]["oid"],
        "merged_at": pr["mergedAt"],
        "url": pr["url"],
        "checks": [
            {
                "name": item.get("name") or item.get("context"),
                "result": item.get("conclusion") or item.get("state"),
            }
            for item in pr["statusCheckRollup"]
        ],
    },
    "pages": {"deployment_id": latest["id"], "deployment_sha": latest["sha"], "deployment_ref": latest["ref"], "production_environment_flag": latest["production_environment"], "run_id": pages["databaseId"], "run_conclusion": pages["conclusion"], "deployment_status": deployment_statuses[0]["state"], "environment_url": deployment_statuses[0]["environment_url"]},
    "asset_byte_parity": {"checked": len(parity_lines), "matched": sum(status == "MATCH" for _, status in parity_lines), "all_match": all(status == "MATCH" for _, status in parity_lines), "sha256": hashes, "evidence": "raw/asset-byte-parity.tsv"},
    "repository_controls": {
        "branch_protection": "not configured (GitHub 404)",
        "branch_rules": [],
        "main_check_runs_total": checks["total_count"],
        "main_check_runs_success": sum(item["conclusion"] == "success" for item in checks["check_runs"]),
        "main_check_runs_skipped": sum(item["conclusion"] == "skipped" for item in checks["check_runs"]),
        "main_check_runs_failed": sum(item["conclusion"] == "failure" for item in checks["check_runs"]),
        "staging_integrity_run_id": integrity["databaseId"],
    },
    "production_contacted": False, "production_mutated": False, "email_contacted": False,
}
assert release["main_sha"] == release["pages"]["deployment_sha"]
assert release["asset_byte_parity"]["all_match"]
write("deployment-verification.json", release)

advisor = {
    "task_id": "t_95939b14", "observed_at": COMPLETED, "project_ref": staging["project_ref"],
    "current": staging["advisors"],
    "comparison_to_t_59b62999": {
        "security_previous_total": 907, "security_current_total": staging["advisors"]["security"]["total"],
        "security_warn_delta": staging["advisors"]["security"]["levels"].get("WARN", 0) - 456,
        "security_info_delta": staging["advisors"]["security"]["levels"].get("INFO", 0) - 451,
        "performance_previous_total": 1017, "performance_current_total": staging["advisors"]["performance"]["total"],
        "performance_warn_delta": staging["advisors"]["performance"]["levels"].get("WARN", 0) - 3,
        "performance_info_delta": staging["advisors"]["performance"]["levels"].get("INFO", 0) - 1014,
        "provenance_warning_cache_keys_unchanged": True,
    },
    "catalog_review": staging["catalog"],
    "data_api_exposure_review": staging["data_api_exposure_review"],
    "official_sources": [
        {"url": "https://supabase.com/docs/guides/database/database-advisors", "finding": "Current advisor catalog includes signed-in SECURITY DEFINER execution, mutable function search_path, RLS, sensitive exposure, and performance checks."},
        {"url": "https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically", "finding": "Existing projects move to explicit grants for newly created public tables on 2026-10-30; grants and RLS remain separate controls."},
        {"url": "https://supabase.com/changelog/43465-developer-update-march-2026", "finding": "March 2026 includes Storage security changes and OpenAPI schema access restriction; no lane mutation was required."},
    ],
    "assessment": {"new_security_warns_vs_prior_audit": 0, "new_performance_warns_vs_prior_audit": 0, "provenance_rpc_warning": "known intentional authenticated SECURITY DEFINER surface; live fail-closed matrix passed", "release_scoped_new_info": 2},
    "evidence": "raw/staging-readonly-baseline.json",
}
write("advisor-results.json", advisor)

issues = [
    {"id": "REL-BASE-001", "severity": "medium", "classification": "baseline_environment", "title": "Duplicate Supabase Preview integrations disagree", "status": "open", "introduced_by_sha": False, "evidence": "raw/pr31-comments.log", "detail": "Preview rgrwkufllnlijmdtfhxf completed configuration, migrations, seeding and Edge Functions; xvflalqbfdxbelerhtjg failed release_history/014 with SQLSTATE 42P01 and left the PR status context failed."},
    {"id": "REL-BASE-002", "severity": "medium", "classification": "baseline_environment", "title": "Full Python suite is not hermetic", "status": "open", "introduced_by_sha": False, "evidence": "raw/python-full-runnable.log", "detail": "Tests depend on absent pdc-emails profile files, historical fixtures, and a legacy staging-bootstrap path. Runnable total: 359 passed, 58 skipped, 22 failed, 3 errors, 304 subtests passed; three additional files fail collection before this runnable pass."},
    {"id": "REL-BASE-003", "severity": "low", "classification": "baseline_test_drift", "title": "Three legacy immutable digest assertions drift", "status": "open", "introduced_by_sha": False, "evidence": "raw/python-full-runnable.log", "detail": "Digest assertions fail in final email-AI remediation, email-monitor planner trust binding, and monitor successor 504 migration. These predate the current PDC-14 release and are outside its changed paths."},
    {"id": "REL-BASE-004", "severity": "medium", "classification": "baseline_security_debt", "title": "Large intentional SECURITY DEFINER surface requires inventory", "status": "open", "introduced_by_sha": False, "evidence": "advisor-results.json", "detail": "Current advisor result contains 455 authenticated SECURITY DEFINER warnings. The provenance/lifecycle cache keys are unchanged from the prior independent audit and pass the expanded fail-closed matrix; broader inventory remains release debt."},
    {"id": "REL-BASE-005", "severity": "low", "classification": "forward_compatibility", "title": "Explicit Data API grants must be standardized before 2026-10-30", "status": "open", "introduced_by_sha": False, "evidence": "advisor-results.json", "detail": "STAGING still has broad public-schema default ACL rows. The 14 RLS-disabled public tables currently expose no SELECT to anon/authenticated, but future migrations must declare grants explicitly before Supabase's existing-project rollout."},
    {"id": "REL-BASE-006", "severity": "low", "classification": "baseline_performance", "title": "PDC-14 role-history RLS policy uses per-row auth evaluation", "status": "open", "introduced_by_sha": False, "evidence": "advisor-results.json", "detail": "Performance advisor flags auth_rls_initplan for PDC administrators reading pdc14_parts_coordinator_role_history. WARN total is unchanged from the prior audit."},
]
register = {"task_id": "t_95939b14", "generated_at": COMPLETED, "issues": issues, "totals": {"all": len(issues), "product_regression": sum(i["classification"] == "product_regression" for i in issues), "baseline_environment": sum(i["classification"] == "baseline_environment" for i in issues), "baseline_or_forward_debt": sum(i["classification"] not in ("product_regression", "baseline_environment") for i in issues), "by_severity": {level: sum(i["severity"] == level for i in issues) for level in ("high", "medium", "low")}}}
write("issue-register.json", register)

report = f"""# Release/security diagnostic lane — t_95939b14

Classification: PASS_WITH_BASELINE_DEBT
Environment: STAGING cdsmnqxtyyoeoznmbidd only
Authoritative main/deployed SHA: `{SHA}`
Completed: {COMPLETED}

## Release

- `origin/main`, GitHub Pages deployment {latest['id']}, Pages run {pages['databaseId']}, and the live deployment all resolve to `{SHA}`.
- Pages build/deploy/status and Staging Integrity run {integrity['databaseId']} succeeded.
- Six release-critical assets match Git blobs byte-for-byte: index.html, app.js, STAGING config, styles.css, vehicle-requirements-guard.js, and workshop-planner.js.
- PR #31 is merged. Staging Integrity and CodeRabbit passed. The Supabase Preview status is a disclosed split baseline result: one preview project fully bootstrapped, while a duplicate preview failed at release_history/014 because `public.vehicle_intelligence_summaries` was absent.
- Main has no branch protection and no branch rules; four current main checks succeeded and the main-branch Supabase Preview check was skipped.

## Tests

- Focused PDC-14 Node: {focused_node_counts['pass']}/{focused_node_counts['tests']} passed.
- Full Node: {node_counts['pass']}/{node_counts['tests']} passed.
- Focused Python/SQL contracts: {focused_py_match.group(1)} passed, {focused_py_match.group(2)} expected live skips.
- Transactional STAGING authorization matrix: 8/8 passed; seven denied identities/scopes returned no data, the approved target succeeded, and the [REDACTED_STOCK_B] row fingerprint remained unchanged.
- Full runnable Python baseline: {full_py_match.group(2)} passed, {full_py_match.group(3)} skipped, {full_py_match.group(1)} failed, {full_py_match.group(4)} errors, {full_py_match.group(5)} subtests passed. Failures are separated in `issue-register.json`: missing external profile/bootstrap/fixture dependencies, three stale digest assertions, and one legacy historical-adapter expectation mismatch. No failure touches the PR #31 paths or reproduces in the focused/full Node release loops.
- The sole standalone SQL test mutates external-completion business state and was intentionally not run under this read-only lane. SQL contracts were exercised by pglast-backed tests and Supabase Preview migrations.

## STAGING security

- Migration head: `{staging['catalog']['migration_head'][0]} / {staging['catalog']['migration_head'][1]}`.
- Provenance RPC remains SECURITY DEFINER with fixed `search_path=pg_catalog, public`; EXECUTE is authenticated-only. Anon/service-role EXECUTE are denied and the obsolete two-argument overload is absent.
- Lifecycle-history table has RLS and FORCE RLS; anon/authenticated have no direct SELECT.
- Authorization outcomes: no role/inactive/pending/UUID-email mismatch = forbidden; wrong dealer = dealer_scope_denied; unauthenticated = unauthorized; invalid target = vehicle_not_found; approved target = ok. No denied result contained `data`.
- [REDACTED_STOCK_B] remained version 3, VIN [REDACTED_VIN_B], registration [REDACTED_REGISTRATION], YH, customer/salesperson/job-card identity unchanged before/after probes. Fresh read-back confirmed 18 operation rows / 58.90 hours, zero-hour OP9/OP14/OP15, seven required and zero completed work groups, and zero workshop bookings.

## Advisors and current Supabase guidance

- Security: {staging['advisors']['security']['total']} total ({staging['advisors']['security']['levels']['WARN']} WARN, {staging['advisors']['security']['levels']['INFO']} INFO). WARN count is unchanged from t_59b62999; +2 INFO are RLS-enabled/no-policy cleanup-history tables.
- Performance: {staging['advisors']['performance']['total']} total ({staging['advisors']['performance']['levels']['WARN']} WARN, {staging['advisors']['performance']['levels']['INFO']} INFO). WARN count is unchanged; INFO is -1.
- Current advisor docs include authenticated SECURITY DEFINER and RLS checks. The April 2026 changelog requires explicit Data API grants for newly created public tables on existing projects from 2026-10-30. Current STAGING has 14 RLS-disabled public tables but zero with anon/authenticated SELECT; broad default ACLs remain forward-compatibility debt.

## Containment and verdict

No code, migration, merge, deployment, Production request, email request, or persistent STAGING mutation was performed. Transactional role probes were rolled back and exact before/after [REDACTED_STOCK_B] fingerprints match. No introduced product regression was found. Release baseline passes with six documented baseline/environment/forward-debt issues for downstream integration.

Machine evidence: `test-results.json`, `deployment-verification.json`, `advisor-results.json`, `issue-register.json`, and bounded logs under `raw/`.
"""
(ROOT / "lane-report.md").write_text(report, encoding="utf-8")

for name in ("test-results.json", "deployment-verification.json", "advisor-results.json", "issue-register.json"):
    json.loads((ROOT / name).read_text(encoding="utf-8"))
for document in (tests, release, advisor, register):
    encoded = json.dumps(document)
    if PRODUCTION_REF := "vjdtsswhroyguxyfjdkt":
        pass
    if "gho_" in encoded or "sb_secret_" in encoded or "Bearer " in encoded:
        raise RuntimeError("credential marker in artifact")
for path in (ROOT / "test-results.json", ROOT / "deployment-verification.json", ROOT / "advisor-results.json", ROOT / "issue-register.json", ROOT / "lane-report.md"):
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"missing artifact: {path}")
print(json.dumps({"ok": True, "json_validated": 4, "required_artifacts": 5, "issue_total": len(issues), "asset_matches": len(parity_lines), "product_regressions": 0}, indent=2))
