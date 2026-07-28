#!/usr/bin/env python3
"""Guarded, ledger-only reconciliation for historical staging migrations 073-092.

The default and safest mode is a rollback rehearsal.  ``--apply`` remains
fail-closed unless the exact QA run confirmation plus a fresh encrypted staging
backup and removed isolated-restore proof are supplied.  Migration SQL is never
executed: this utility may only append reviewed source text to the Supabase
migration ledger after all staging, branch, source, evidence, ledger and public-
table fingerprint guards pass.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

from psycopg2 import sql

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.pdc_staging_runtime import (  # noqa: E402
    assert_staging_target,
    get_conn,
    load_local_env,
    required,
)

EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
EXPECTED_BRANCH = "qa/workshop-bulletproof-20260728"
EXPECTED_RUN_ID = "QA-WCB-20260728T130102Z"
EXPECTED_LEDGER_HEAD = "102"
EXPECTED_RECONCILIATION_SHA256 = "34eaf7d23dfe9c8c6d4646c33402573640ef6c631c801a00e50dd9640bd83b57"
EXPECTED_LIVE_LEDGER_ARRAY_SHA256 = "bc8ac3e33b3cdb91836fdbdc9c64c084244e5c70fe123aed32f122425672e772"
APPLY_CONFIRMATION_ENV = "PDC_LEDGER_REPAIR_APPLY_CONFIRMATION"
APPLY_CONFIRMATION = f"{EXPECTED_RUN_ID}:073-092"

MIGRATIONS = {
    "073": {"name": "qc_gate_parts_eta_control_board", "sha256": "e5f07f95798991ba2862df3082753718e5fe7b1dd223272794969aef71f8a7bd"},
    "074": {"name": "navision_initial_scope_exact_review", "sha256": "1cd965b347a8b8c959a068bf99a73aba25baaab2fa5a1acfa5066892a882d3a7"},
    "075": {"name": "navision_declared_dealer_cross_scope", "sha256": "bc24231eda60911ac7f2118b1cd2b28a466d2bb797595691184316c300b23247"},
    "076": {"name": "navision_mixed_report_selected_scope", "sha256": "346e90eab0ee2883ca2c31c8768c24328286b51a16df75e1025b2cf267dd6371"},
    "077": {"name": "workshop_future_parts_planning_and_start_gate", "sha256": "5be989637971f3fdb80b0dae06dfd20740a2bfe978033f2a8d17ce5f1127c7d1"},
    "078": {"name": "workshop_viewer_read_snapshots", "sha256": "1e474fa525fdbcda8032019f02b1be92eb0122ca82b2b01ec9257adfb7074ccb"},
    "079": {"name": "navision_exact_dealer_scope_without_fleet_floor", "sha256": "98ae4a0be355161528f6eae0f1d927e17f39a825aac75e0676ad3fe02d46499e"},
    "080": {"name": "navision_generic_header_dealer_evidence", "sha256": "0987e78618e2c7ea1354f668a8b3fc32a0fd8a22a2b4508c4bb200fccf023cd1"},
    "081": {"name": "navision_restore_bounded_wrapper_timeout", "sha256": "cb5026303225b7244ac127e880387469bddbb35ea1cb06089797a3fc7a9044f3"},
    "082": {"name": "navision_authenticated_api_timeout", "sha256": "f3098faaa3a7d192fc144a461fe85b399322b02efba54eef3a202ea23c264c43"},
    "083": {"name": "navision_operational_location_and_completion", "sha256": "40f61322ca2f883994bde8bc1db42abe3b79ce04d4f7837ad73f16b5225a672a"},
    "084": {"name": "control_board_station_pipeline", "sha256": "7eb4e27bf178ee9efc7cf9dbf915a13c459ec27a0304093d26b186d61d0761f1"},
    "085": {"name": "salesperson_email_defaults", "sha256": "41ce61db3dfcd0b9ab1a9dc1caec5d32d1b74eee1e78c74ce9e38afcbaf93600"},
    "086": {"name": "sublet_provider_normalisation_and_workshop_settings", "sha256": "db05a6df1117aefe61da082f63ba6988e2ad0f98883617f66ba8ce888bee7da4"},
    "087": {"name": "workshop_authoritative_candidate_gate", "sha256": "391f63c4508357f4320496ba84d6fe478c2f3ae24a2111b5d997a73c937c8fae"},
    "088": {"name": "vehicle_workshop_detail_page", "sha256": "5b803bade72f253da154fc4261a17b67b8490654ef7bd36f8d125bc0ec5f9335"},
    "089": {"name": "toyota_navision_it_requires_kewdale_eta", "sha256": "01221fd268ac801eca8fc291aba0b8ba4ab881b910d6e91b64b0902d8e6877f8"},
    "090": {"name": "toyota_navision_it_status_parity", "sha256": "e9a10c98e88ba3d83be13845af968085bc19f98217d7d25d828802cd8bc1774c"},
    "091": {"name": "parts_ordered_and_workshop_candidate_scope", "sha256": "20595148a054490ab9b7f39e190414c9f74cb6451471fd180aacb3dab6fdbe5e"},
    "092": {"name": "vehicle_provenance_and_detailed_history", "sha256": "3393d2f45275580374c2d1e3060ec28c179880c867d4fc9ea9753af09b5f9150"},
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def normalized_source(path: Path) -> str:
    return path.read_text(encoding="utf-8").replace("\r\n", "\n")


def migration_sources() -> dict[str, str]:
    sources: dict[str, str] = {}
    expected_versions = [f"{number:03d}" for number in range(73, 93)]
    if list(MIGRATIONS) != expected_versions:
        raise RuntimeError("Migration repair inventory must cover exactly 073-092 in order")
    for version, contract in MIGRATIONS.items():
        matches = list((ROOT / "supabase" / "staging_only").glob(f"{version}_*.sql"))
        if len(matches) != 1:
            raise RuntimeError(f"Expected exactly one staging migration source for {version}")
        path = matches[0]
        if path.stem != f"{version}_{contract['name']}":
            raise RuntimeError(f"Migration {version} filename/name contract changed")
        source = normalized_source(path)
        actual = sha256_bytes(source.encode("utf-8"))
        if actual != contract["sha256"]:
            raise RuntimeError(f"Migration {version} source SHA-256 mismatch")
        lowered = source.lower()
        # Historical sources are recorded as immutable evidence only and are
        # never executed by this utility.  Several early staging-only files
        # predate embedded project-ref sentinels, so their reviewed SHA-256 is
        # the guard; any production-ref occurrence still fails closed.
        if PRODUCTION_REF in lowered:
            raise RuntimeError(f"Migration {version} source references production")
        sources[version] = source
    return sources


def verify_branch() -> str:
    result = subprocess.run(
        ["git", "branch", "--show-current"], cwd=ROOT, check=True,
        capture_output=True, text=True,
    )
    branch = result.stdout.strip()
    if branch != EXPECTED_BRANCH:
        raise RuntimeError(f"Refusing ledger repair from branch {branch!r}")
    return branch


def load_reconciliation_evidence(path: Path) -> dict:
    raw = path.read_bytes()
    if sha256_bytes(raw) != EXPECTED_RECONCILIATION_SHA256:
        raise RuntimeError("Reconciliation evidence SHA-256 mismatch")
    evidence = json.loads(raw)
    if evidence.get("runId") != EXPECTED_RUN_ID:
        raise RuntimeError("Reconciliation evidence run identity mismatch")
    if evidence.get("projectRef") != EXPECTED_STAGING_REF:
        raise RuntimeError("Reconciliation evidence staging project mismatch")
    if evidence.get("productionContacted") is not False:
        raise RuntimeError("Reconciliation evidence does not prove zero production contact")
    summary = evidence.get("summary", {})
    ledger = evidence.get("ledger", {})
    if (
        ledger.get("head") != EXPECTED_LEDGER_HEAD
        or summary.get("historicalUnledgered") != list(MIGRATIONS)
        or summary.get("intentionalNonApplied") != ["041", "043"]
        or summary.get("missingCurrentObjects") != []
        or summary.get("latestFunctionBodyMismatches") != []
        or summary.get("readOnly") is not True
    ):
        raise RuntimeError("Reconciliation evidence summary is not release-safe")
    classifications = {row.get("version"): row.get("classification") for row in evidence.get("gaps", [])}
    for version in MIGRATIONS:
        if classifications.get(version) != "historical_unledgered_source":
            raise RuntimeError(f"Migration {version} lacks reviewed unledgered classification")
    if classifications.get("041") != "intentional_not_applied" or classifications.get("043") != "rejected_never_apply":
        raise RuntimeError("Intentional ledger gaps 041/043 are not preserved")
    return evidence


def ledger_entries(cur) -> list[dict[str, str]]:
    cur.execute("select version,name,statements from supabase_migrations.schema_migrations order by version")
    rows = []
    for version, name, statements in cur.fetchall():
        first_statement = (statements or [""])[0] or ""
        rows.append({
            "version": str(version),
            "name": str(name or ""),
            "statementSha256": sha256_bytes(str(first_statement).replace("\r\n", "\n").encode("utf-8")),
        })
    return rows


def live_ledger_array_sha256(cur) -> str:
    """Bind exact raw ledger arrays, including CLI-split historical entries."""
    cur.execute("select version,name,statements from supabase_migrations.schema_migrations order by version")
    rows = [
        [
            str(version),
            str(name or ""),
            [str(value).replace("\r\n", "\n") for value in (statements or [])],
        ]
        for version, name, statements in cur.fetchall()
    ]
    raw = json.dumps(rows, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return sha256_bytes(raw)


def assert_ledger_matches_evidence(cur, evidence: dict) -> list[dict[str, str]]:
    actual = ledger_entries(cur)
    expected = evidence.get("ledger", {}).get("entries")
    actual_identity = [(row["version"], row["name"]) for row in actual]
    expected_identity = [(row["version"], row["name"]) for row in (expected or [])]
    if actual_identity != expected_identity:
        raise RuntimeError("Live staging ledger changed since reviewed reconciliation evidence")
    if live_ledger_array_sha256(cur) != EXPECTED_LIVE_LEDGER_ARRAY_SHA256:
        raise RuntimeError("Live staging ledger statement arrays changed since guarded design")
    if not actual or actual[-1]["version"] != EXPECTED_LEDGER_HEAD:
        raise RuntimeError("Live staging ledger head mismatch")
    present = {row["version"] for row in actual}
    unexpected_present = sorted(set(MIGRATIONS).intersection(present))
    if unexpected_present:
        raise RuntimeError(f"Ledger repair versions are no longer absent: {unexpected_present}")
    return actual


def assert_staging_sentinel(cur) -> None:
    cur.execute("select current_database(), current_user")
    database_name, current_user = cur.fetchone()
    if database_name != "postgres" or current_user not in {"postgres", "service_role"}:
        raise RuntimeError("Unexpected database or migration role")
    cur.execute(
        "select count(*) from public.pdc_staging_environment_sentinel "
        "where singleton and project_ref=%s",
        (EXPECTED_STAGING_REF,),
    )
    if cur.fetchone()[0] != 1:
        raise RuntimeError("PDC_STAGING_SENTINEL_MISMATCH")


def protected_table_fingerprint(cur) -> dict[str, object]:
    """Hash every public ordinary/partitioned table without exposing row data."""
    cur.execute(
        """select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relkind in ('r','p') order by c.relname"""
    )
    tables = [row[0] for row in cur.fetchall()]
    records = []
    for table in tables:
        query = sql.SQL(
            "select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from {}.{} t"
        ).format(sql.Identifier("public"), sql.Identifier(table))
        cur.execute(query)
        count, digest = cur.fetchone()
        records.append([table, int(count), str(digest)])
    canonical = json.dumps(records, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    return {"tableCount": len(records), "sha256": sha256_bytes(canonical)}


def post_repair_ledger(expected_before: list[dict[str, str]], sources: dict[str, str]) -> list[dict[str, str]]:
    additions = [
        {
            "version": version,
            "name": MIGRATIONS[version]["name"],
            "statementSha256": sha256_bytes(source.encode("utf-8")),
        }
        for version, source in sources.items()
    ]
    return sorted(expected_before + additions, key=lambda row: row["version"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reconciliation-evidence", required=True, type=Path)
    parser.add_argument("--apply", action="store_true", help="Commit only after all additional backup/restore gates pass")
    parser.add_argument("--backup-file", type=Path)
    parser.add_argument("--backup-sha256")
    parser.add_argument("--restore-schema")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    branch = verify_branch()
    sources = migration_sources()
    evidence = load_reconciliation_evidence(args.reconciliation_evidence)
    load_local_env()
    database_url = required("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=database_url)
    if args.apply:
        if os.environ.get(APPLY_CONFIRMATION_ENV, "") != APPLY_CONFIRMATION:
            raise RuntimeError(f"--apply requires exact {APPLY_CONFIRMATION_ENV} confirmation")
        if not args.backup_file or not args.backup_sha256 or not args.restore_schema:
            raise RuntimeError("--apply requires backup file, SHA-256 and isolated restore schema proof")

    conn = get_conn()
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            assert_staging_sentinel(cur)
            cur.execute("select pg_advisory_xact_lock(hashtextextended(%s,0))", ("pdc-staging-ledger-repair-073-092",))
            cur.execute("lock table supabase_migrations.schema_migrations in exclusive mode")
            before_ledger = assert_ledger_matches_evidence(cur, evidence)
            backup_proof = None
            if args.apply:
                # Keep cryptography/backup dependencies outside rollback-only
                # rehearsal while making the commit path prove the complete
                # encrypted-backup and removed isolated-restore contract.
                from scripts.release_backup_gate import validate_release_backup

                backup_proof = validate_release_backup(
                    conn,
                    args.backup_file,
                    args.backup_sha256,
                    args.restore_schema,
                    expected_migration=EXPECTED_LEDGER_HEAD,
                    max_age_seconds=7200,
                )
            before_protected = protected_table_fingerprint(cur)
            for version, source in sources.items():
                cur.execute(
                    "insert into supabase_migrations.schema_migrations(version,statements,name) values(%s,%s,%s)",
                    (version, [source], MIGRATIONS[version]["name"]),
                )
            after_ledger = ledger_entries(cur)
            if after_ledger != post_repair_ledger(before_ledger, sources):
                raise RuntimeError("Post-repair ledger inventory/hash mismatch")
            after_protected = protected_table_fingerprint(cur)
            if before_protected != after_protected:
                raise RuntimeError("Ledger-only repair changed protected public table fingerprints")

        report = {
            "runId": EXPECTED_RUN_ID,
            "branch": branch,
            "projectRef": EXPECTED_STAGING_REF,
            "versions": list(MIGRATIONS),
            "insertCount": len(MIGRATIONS),
            "sourceSha256Verified": True,
            "reconciliationEvidenceSha256": EXPECTED_RECONCILIATION_SHA256,
            "priorLedgerHead": EXPECTED_LEDGER_HEAD,
            "resultingLedgerHead": EXPECTED_LEDGER_HEAD,
            "protectedFingerprint": before_protected,
            "protectedFingerprintsUnchanged": True,
            "backupRestoreGate": backup_proof,
            "productionContacted": False,
            "productionChanged": False,
        }
        if args.apply:
            conn.commit()
            report["status"] = "applied"
        else:
            conn.rollback()
            report["status"] = "rollback_rehearsal"
        print(json.dumps(report, sort_keys=True))
        return 0
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
