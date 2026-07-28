#!/usr/bin/env python3
"""Guarded synthetic Workshop Control Board fixture planning and seeding.

Vehicle creation is exercised through the protected vehicle-master RPC under a
real approved staging identity. Direct fixture-only setup that has no canonical
creator is namespace-bound and audited. Retained continuation batches require
the exact run confirmation and an external UUID manifest; cleanup remains a
separate, manifest-bound campaign phase.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

RUN_ID = "QA-WCB-20260728T130102Z"
EXPECTED_STAGING_REF = "cdsmnqxtyyoeoznmbidd"
PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
EXPECTED_BRANCH = "qa/workshop-bulletproof-20260728"
EXPECTED_LEDGER_HEAD = "103"
EXPECTED_LEDGER_COUNT = 101
EXPECTED_LEDGER_GAPS = ["041", "043"]
SOURCE_SYSTEM = "qa_wcb_synthetic"
ROOT = Path(__file__).resolve().parents[1]
STAGES = (
    ("BUS_4X4", "bus4x4"),
    ("TINT", "tint"),
    ("HOIST", "hoist"),
    ("FITTING", "fitting"),
    ("FABRICATION", "fabrication"),
    ("ELECTRICAL", "electrical"),
    ("TYRE", "tyre"),
    ("PIT_INSPECTION", "pitInspection"),
)
UUID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_URL, f"pdc-control-board:{RUN_ID}")
MUTABLE_EVIDENCE_TABLES = {
    "audit_events", "vehicle_master_history", "vehicle_master_operation_receipts",
    "vehicle_master_source_records", "vehicle_master_revision",
    "vehicle_lifecycle_resolver_revision", "pdc_email_vehicle_revision",
    "pdc_online_state_revision", "workshop_revision", "workshop_station_revision",
}


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def assert_branch() -> str:
    branch = git("branch", "--show-current")
    if branch != EXPECTED_BRANCH:
        raise RuntimeError(f"Refusing Workshop QA fixture work from branch {branch!r}")
    return branch


def fixture_plan(batch_size: int) -> dict[str, Any]:
    if batch_size < 1 or batch_size > 25:
        raise ValueError("batch size per stage must be between 1 and 25")
    rows = []
    for stage_code, work_key in STAGES:
        for index in range(1, batch_size + 1):
            identity = f"{RUN_ID}:{stage_code}:{index:04d}"
            rows.append({
                "stageCode": stage_code,
                "workKey": work_key,
                "ordinal": index,
                "sourceRecordId": identity,
                "idempotencyKey": identity,
                "workItemId": str(uuid.uuid5(UUID_NAMESPACE, identity + ":work-item")),
            })
    return {
        "schema": "pdc.qa-wcb-fixture-plan/v1",
        "runId": RUN_ID,
        "mode": "plan",
        "sourceBranch": EXPECTED_BRANCH,
        "batchSizePerStage": batch_size,
        "rows": rows,
        "retainedWritesSupported": True,
        "cleanupMode": "manifest_bound_separate_phase",
    }


def assert_online_window() -> None:
    """The original deadline is superseded by explicit continuation authority."""
    return None


def load_runtime():
    if str(ROOT) not in sys.path:
        sys.path.insert(0, str(ROOT))
    from scripts.pdc_staging_runtime import (  # pylint: disable=import-outside-toplevel
        assert_staging_target,
        get_conn,
        load_local_env,
        required,
    )
    load_local_env()
    database_url = required("PDC_STAGING_DATABASE_URL")
    lowered = database_url.lower()
    if PRODUCTION_REF in lowered or EXPECTED_STAGING_REF not in lowered:
        raise RuntimeError("Refusing database endpoint outside guarded staging")
    assert_staging_target(database_url=database_url)
    return get_conn, required


def assert_staging_catalog(cur) -> dict[str, Any]:
    cur.execute("select current_database(),current_user")
    database_name, current_user = cur.fetchone()
    if database_name != "postgres" or current_user not in {"postgres", "service_role"}:
        raise RuntimeError("Unexpected staging database or connection role")
    cur.execute(
        "select count(*) from public.pdc_staging_environment_sentinel "
        "where singleton and project_ref=%s",
        (EXPECTED_STAGING_REF,),
    )
    if cur.fetchone()[0] != 1:
        raise RuntimeError("PDC_STAGING_SENTINEL_MISMATCH")
    cur.execute("select version from supabase_migrations.schema_migrations order by version::int")
    versions = [str(row[0]) for row in cur.fetchall()]
    numbers = [int(value) for value in versions]
    gaps = [f"{number:03d}" for number in range(min(numbers), max(numbers) + 1) if number not in numbers]
    if len(versions) != EXPECTED_LEDGER_COUNT or versions[-1] != EXPECTED_LEDGER_HEAD or gaps != EXPECTED_LEDGER_GAPS:
        raise RuntimeError("Unexpected staging migration ledger identity")
    cur.execute(
        "select code,work_key,active,planner_enabled,"
        "(select count(*) from public.workshop_bays b where b.stage_id=s.id and b.is_active) "
        "from public.workshop_stages s where code=any(%s) order by sort_order",
        ([stage for stage, _ in STAGES],),
    )
    stages = [
        {"code": code, "workKey": work_key, "active": active,
         "plannerEnabled": planner_enabled, "activeBays": active_bays}
        for code, work_key, active, planner_enabled, active_bays in cur.fetchall()
    ]
    if [row["code"] for row in stages] != [stage for stage, _ in STAGES]:
        raise RuntimeError("Effective staging station inventory is incomplete or reordered")
    expected_keys = dict(STAGES)
    if any(row["workKey"] != expected_keys[row["code"]] or not row["active"] for row in stages):
        raise RuntimeError("Effective staging station/work-key contract changed")
    cur.execute("select to_regprocedure('public.upsert_vehicle_master_import(text,text,text,jsonb,integer,text)')::text")
    if cur.fetchone()[0] is None:
        raise RuntimeError("Protected vehicle-master creator RPC is absent")
    cur.execute("select to_regprocedure('public.workshop_station_eligibility(text)')::text")
    if cur.fetchone()[0] is None:
        raise RuntimeError("Canonical station eligibility function is absent")
    return {
        "ledgerHead": versions[-1],
        "ledgerCount": len(versions),
        "ledgerGaps": gaps,
        "stages": stages,
        "plannerEnabledStages": [row["code"] for row in stages if row["plannerEnabled"]],
        "plannerDisabledStages": [row["code"] for row in stages if not row["plannerEnabled"]],
    }


def table_names(cur) -> list[str]:
    cur.execute(
        "select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace "
        "where n.nspname='public' and c.relkind in('r','p') "
        "and c.relname not in('backup_runs','restore_test_runs') order by c.relname"
    )
    return [row[0] for row in cur.fetchall()]


def namespace_hits(cur, tables: list[str]) -> dict[str, int]:
    from psycopg2 import sql  # pylint: disable=import-outside-toplevel
    result: dict[str, int] = {}
    for table in tables:
        query = sql.SQL("select count(*) from {}.{} t where to_jsonb(t)::text like %s").format(
            sql.Identifier("public"), sql.Identifier(table)
        )
        cur.execute(query, (f"%{RUN_ID}%",))
        count = int(cur.fetchone()[0])
        if count:
            result[table] = count
    return result


def protected_fingerprint(cur, tables: list[str]) -> dict[str, Any]:
    from psycopg2 import sql  # pylint: disable=import-outside-toplevel
    rows = []
    for table in tables:
        query = sql.SQL(
            "select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' "
            "order by md5(to_jsonb(t)::text)),'')) from {}.{} t"
        ).format(sql.Identifier("public"), sql.Identifier(table))
        cur.execute(query)
        count, digest = cur.fetchone()
        rows.append([table, int(count), str(digest)])
    return {"tableCount": len(rows), "sha256": sha256_json(rows)}


def non_namespace_fingerprint(cur, tables: list[str]) -> dict[str, Any]:
    """Hash ordinary rows while excluding campaign rows and expected revisions."""
    from psycopg2 import sql  # pylint: disable=import-outside-toplevel
    rows = []
    for table in tables:
        if table in MUTABLE_EVIDENCE_TABLES:
            continue
        query = sql.SQL(
            "select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' "
            "order by md5(to_jsonb(t)::text)),'')) from {}.{} t "
            "where to_jsonb(t)::text not like %s"
        ).format(sql.Identifier("public"), sql.Identifier(table))
        cur.execute(query, (f"%{RUN_ID}%",))
        count, digest = cur.fetchone()
        rows.append([table, int(count), str(digest)])
    return {"tableCount": len(rows), "sha256": sha256_json(rows), "tables": rows}


def durable_replace(path: Path, value: dict[str, Any]) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + f".{os.getpid()}.tmp")
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    with temporary.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(payload)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def reconcile_retained_batch(cur, stage_code: str, entries: list[dict[str, Any]]) -> dict[str, Any]:
    vehicle_ids = [entry["vehicleId"] for entry in entries]
    work_item_ids = [entry["workItemId"] for entry in entries]
    cur.execute(
        "select count(*) from public.vehicles where id=any(%s::uuid[]) "
        "and source_payload->>'qa_run_id'=%s and source_payload->>'qa_stage_code'=%s",
        (vehicle_ids, RUN_ID, stage_code),
    )
    vehicle_count = int(cur.fetchone()[0])
    cur.execute(
        "select count(*) from public.vehicle_work_items where id=any(%s::uuid[]) "
        "and vehicle_id=any(%s::uuid[]) and notes=%s and required and not completed",
        (work_item_ids, vehicle_ids, RUN_ID),
    )
    work_item_count = int(cur.fetchone()[0])
    cur.execute(
        "select count(*) from public.workshop_station_eligibility(%s) e "
        "where e.vehicle_id=any(%s::uuid[])",
        (stage_code, vehicle_ids),
    )
    eligible_count = int(cur.fetchone()[0])
    expected = len(entries)
    if (vehicle_count, work_item_count, eligible_count) != (expected, expected, expected):
        raise RuntimeError(
            f"Retained {stage_code} reconciliation failed: "
            f"vehicles={vehicle_count}, workItems={work_item_count}, eligible={eligible_count}, expected={expected}"
        )
    return {
        "stageCode": stage_code,
        "vehicleCount": vehicle_count,
        "workItemCount": work_item_count,
        "eligibleCount": eligible_count,
    }


def cleanup_graph(cur) -> dict[str, Any]:
    cur.execute(
        "select src.relname,dst.relname,c.conname,c.confdeltype "
        "from pg_constraint c "
        "join pg_class src on src.oid=c.conrelid join pg_namespace sn on sn.oid=src.relnamespace "
        "join pg_class dst on dst.oid=c.confrelid join pg_namespace dn on dn.oid=dst.relnamespace "
        "where c.contype='f' and sn.nspname='public' and dn.nspname='public' "
        "order by dst.relname,src.relname,c.conname"
    )
    action = {"a": "no_action", "r": "restrict", "c": "cascade", "n": "set_null", "d": "set_default"}
    edges = [
        {"child": child, "parent": parent, "constraint": name, "onDelete": action.get(delete_type, delete_type)}
        for child, parent, name, delete_type in cur.fetchall()
    ]
    reachable = {"vehicles"}
    changed = True
    while changed:
        changed = False
        for edge in edges:
            if edge["parent"] in reachable and edge["child"] not in reachable:
                reachable.add(edge["child"])
                changed = True
    related = [edge for edge in edges if edge["parent"] in reachable and edge["child"] in reachable]
    return {
        "root": "vehicles",
        "reachableTables": sorted(reachable),
        "foreignKeys": related,
        "nonCascadeEdges": [edge for edge in related if edge["onDelete"] != "cascade"],
        "strategy": "derive live FK graph; preview namespace/UUID cardinality; require explicit review before any retained cleanup",
    }


def approved_admin(cur, required) -> tuple[str, str]:
    email = required("PDC_STAGING_ADMIN_EMAIL").strip().lower()
    cur.execute(
        "select u.id::text,lower(u.email) from auth.users u "
        "join public.pdc_user_roles r on r.auth_user_id=u.id "
        "where lower(u.email)=%s and r.active and r.account_status='approved' and r.role='administrator'",
        (email,),
    )
    row = cur.fetchone()
    if not row:
        raise RuntimeError("Configured approved staging administrator is unavailable")
    return row[0], row[1]


def impersonate(cur, actor_id: str, email: str) -> None:
    claims = canonical_json({"sub": actor_id, "email": email, "role": "authenticated"})
    cur.execute("set local role authenticated")
    cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))


def reset_role(cur) -> None:
    cur.execute("reset role")


def create_rehearsal_fixture(cur, row: dict[str, Any], actor_id: str, email: str) -> str:
    impersonate(cur, actor_id, email)
    payload = {
        "permanent_vehicle_id": "SYNTHETIC:" + row["sourceRecordId"],
        "customer_name": "SYNTHETIC QA LOAD",
        "vehicle_description": f"Synthetic {row['stageCode']} reliability fixture",
        "make": "SYNTHETIC",
        "model": "QA LOAD FIXTURE",
    }
    cur.execute(
        "select public.upsert_vehicle_master_import(%s,%s,%s,%s::jsonb,null,%s)",
        (SOURCE_SYSTEM, RUN_ID, row["sourceRecordId"], canonical_json(payload), row["idempotencyKey"]),
    )
    response = cur.fetchone()[0]
    if not isinstance(response, dict) or response.get("ok") is not True or response.get("code") != "applied":
        raise RuntimeError(f"Protected fixture vehicle creation failed with code {response.get('code') if isinstance(response, dict) else 'invalid_response'}")
    vehicle_id = str(response["data"]["vehicle_id"])
    reset_role(cur)
    cur.execute("select to_jsonb(v) from public.vehicles v where id=%s for update", (vehicle_id,))
    before = cur.fetchone()[0]
    cur.execute(
        "update public.vehicles set current_location='PMB',visible_on_board=true,"
        "source_payload=coalesce(source_payload,'{}'::jsonb)||jsonb_build_object("
        "'qa_run_id',%s,'qa_stage_code',%s,'synthetic',true),"
        "version=version+1,updated_by=%s::uuid where id=%s returning to_jsonb(vehicles)",
        (RUN_ID, row["stageCode"], actor_id, vehicle_id),
    )
    after = cur.fetchone()[0]
    cur.execute(
        "insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,before_data,after_data,metadata) "
        "values('update','vehicles',%s,%s,%s,%s,%s::jsonb,%s::jsonb,jsonb_build_object("
        "'qa_run_id',%s,'fixture_setup',true,'stage_code',%s))",
        (vehicle_id, vehicle_id, actor_id, email, canonical_json(before), canonical_json(after), RUN_ID, row["stageCode"]),
    )
    cur.execute(
        "insert into public.vehicle_work_items(id,vehicle_id,work_key,required,completed,notes) "
        "values(%s,%s,%s,true,false,%s) returning to_jsonb(vehicle_work_items)",
        (row["workItemId"], vehicle_id, row["workKey"], RUN_ID),
    )
    work_item = cur.fetchone()[0]
    cur.execute(
        "insert into public.audit_events(action,table_name,row_id,vehicle_id,actor_id,actor_email,after_data,metadata) "
        "values('insert','vehicle_work_items',%s,%s,%s,%s,%s::jsonb,jsonb_build_object("
        "'qa_run_id',%s,'fixture_setup',true,'stage_code',%s))",
        (row["workItemId"], vehicle_id, actor_id, email, canonical_json(work_item), RUN_ID, row["stageCode"]),
    )
    return vehicle_id


def seed_retained(batch_size: int, manifest_path: Path, confirmation: str, backup_run_id: str) -> dict[str, Any]:
    if confirmation != RUN_ID:
        raise RuntimeError("Retained seed requires the exact run ID confirmation")
    branch = assert_branch()
    manifest_path = manifest_path.resolve()
    try:
        manifest_path.relative_to(ROOT.resolve())
    except ValueError:
        pass
    else:
        raise RuntimeError("Fixture UUID manifest must be stored outside the source worktree")
    plan = fixture_plan(batch_size)
    plan_digest = sha256_json(plan["rows"])
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if (manifest.get("runId"), manifest.get("planSha256"), manifest.get("batchSizePerStage")) != (
            RUN_ID, plan_digest, batch_size
        ):
            raise RuntimeError("Existing fixture manifest does not match this exact run plan")
    else:
        manifest = {
            "schema": "pdc.qa-wcb-retained-fixture-manifest/v1",
            "runId": RUN_ID,
            "projectRef": EXPECTED_STAGING_REF,
            "sourceBranch": branch,
            "sourceCommit": git("rev-parse", "HEAD"),
            "backupRunId": backup_run_id,
            "batchSizePerStage": batch_size,
            "planSha256": plan_digest,
            "createdAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "entries": [],
            "batchReceipts": [],
            "complete": False,
        }

    get_conn, required = load_runtime()
    preflight = get_conn()
    preflight.set_session(readonly=True, autocommit=False)
    try:
        with preflight.cursor() as cur:
            catalog = assert_staging_catalog(cur)
            if set(catalog["plannerEnabledStages"]) != set(dict(STAGES)):
                raise RuntimeError("All eight canonical stations must be planner enabled before retained seeding")
            cur.execute(
                "select status,environment,finished_at from public.backup_runs where id=%s::uuid",
                (backup_run_id,),
            )
            backup = cur.fetchone()
            if not backup or backup[0] != "success" or backup[1] != "staging" or backup[2] is None:
                raise RuntimeError("Fresh successful staging backup evidence is required")
            tables = table_names(cur)
            baseline = non_namespace_fingerprint(cur, tables)
            existing_entries = manifest["entries"]
            if existing_entries:
                expected_sources = {row["sourceRecordId"] for row in plan["rows"]}
                actual_sources = {entry["sourceRecordId"] for entry in existing_entries}
                if not actual_sources.issubset(expected_sources) or len(actual_sources) != len(existing_entries):
                    raise RuntimeError("Manifest contains duplicate or out-of-plan fixture identities")
                for stage_code, _ in STAGES:
                    stage_entries = [entry for entry in existing_entries if entry["stageCode"] == stage_code]
                    if stage_entries and len(stage_entries) != batch_size:
                        raise RuntimeError("Refusing a partially manifested retained batch")
                    if stage_entries:
                        reconcile_retained_batch(cur, stage_code, stage_entries)
            elif namespace_hits(cur, tables):
                raise RuntimeError("Run namespace exists without a retained UUID manifest")
            preflight.rollback()
    finally:
        preflight.close()

    completed_stages = {entry["stageCode"] for entry in manifest["entries"]}
    for stage_code, _work_key in STAGES:
        if stage_code in completed_stages:
            continue
        rows = [row for row in plan["rows"] if row["stageCode"] == stage_code]
        conn = get_conn()
        conn.autocommit = False
        stage_entries: list[dict[str, Any]] = []
        try:
            with conn.cursor() as cur:
                cur.execute("set local statement_timeout='120s'")
                assert_staging_catalog(cur)
                cur.execute("select pg_advisory_xact_lock(hashtextextended(%s,0))", (f"qa-workshop-fixtures:{RUN_ID}",))
                actor_id, email = approved_admin(cur, required)
                for row in rows:
                    vehicle_id = create_rehearsal_fixture(cur, row, actor_id, email)
                    stage_entries.append({
                        "stageCode": stage_code,
                        "ordinal": row["ordinal"],
                        "sourceRecordId": row["sourceRecordId"],
                        "vehicleId": vehicle_id,
                        "workItemId": row["workItemId"],
                    })
                reconcile_retained_batch(cur, stage_code, stage_entries)
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

        verify = get_conn()
        verify.set_session(readonly=True, autocommit=False)
        try:
            with verify.cursor() as cur:
                reconciliation = reconcile_retained_batch(cur, stage_code, stage_entries)
                after = non_namespace_fingerprint(cur, table_names(cur))
                verify.rollback()
        finally:
            verify.close()
        if after != baseline:
            raise RuntimeError(f"Unrelated staging rows changed while committing {stage_code}")
        manifest["entries"].extend(stage_entries)
        manifest["batchReceipts"].append({
            **reconciliation,
            "committedAtUtc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "unrelatedRowsSha256": after["sha256"],
        })
        durable_replace(manifest_path, manifest)

    manifest["complete"] = len(manifest["entries"]) == len(plan["rows"])
    manifest["completedAtUtc"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    manifest["manifestEntriesSha256"] = sha256_json(manifest["entries"])
    durable_replace(manifest_path, manifest)
    if not manifest["complete"]:
        raise RuntimeError("Retained fixture manifest did not reach the complete plan cardinality")
    return {
        "schema": "pdc.qa-wcb-retained-seed-result/v1",
        "runId": RUN_ID,
        "projectRef": EXPECTED_STAGING_REF,
        "sourceBranch": branch,
        "sourceCommit": git("rev-parse", "HEAD"),
        "backupRunId": backup_run_id,
        "manifestPath": str(manifest_path),
        "manifestSha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        "retainedVehicleCount": len(manifest["entries"]),
        "retainedWorkItemCount": len(manifest["entries"]),
        "byStage": {stage: sum(1 for entry in manifest["entries"] if entry["stageCode"] == stage) for stage, _ in STAGES},
        "unrelatedRowsUnchanged": True,
        "productionContacted": False,
        "productionWrites": 0,
    }


def rollback_rehearsal(batch_size: int) -> dict[str, Any]:
    assert_online_window()
    branch = assert_branch()
    get_conn, required = load_runtime()
    plan = fixture_plan(batch_size)
    conn = get_conn()
    conn.autocommit = False
    before_fingerprint = None
    catalog = None
    cleanup = None
    in_transaction_hits = None
    vehicle_ids: list[str] = []
    eligibility: dict[str, int] = {}
    aggregate_candidate_count = 0
    try:
        with conn.cursor() as cur:
            cur.execute("set local statement_timeout='120s'")
            catalog = assert_staging_catalog(cur)
            cur.execute("select pg_advisory_xact_lock(hashtextextended(%s,0))", (f"qa-workshop-fixtures:{RUN_ID}",))
            tables = table_names(cur)
            before_hits = namespace_hits(cur, tables)
            if before_hits:
                raise RuntimeError(f"Run namespace already exists in staging tables: {sorted(before_hits)}")
            before_fingerprint = protected_fingerprint(cur, tables)
            cleanup = cleanup_graph(cur)
            actor_id, email = approved_admin(cur, required)
            for row in plan["rows"]:
                vehicle_ids.append(create_rehearsal_fixture(cur, row, actor_id, email))
            for stage_code, _ in STAGES:
                cur.execute(
                    "select count(*) from public.workshop_station_eligibility(%s) e where e.vehicle_id=any(%s::uuid[])",
                    (stage_code, vehicle_ids),
                )
                eligibility[stage_code] = int(cur.fetchone()[0])
            impersonate(cur, actor_id, email)
            cur.execute("select public.get_workshop_eligibility_snapshot()")
            snapshot = cur.fetchone()[0]
            aggregate_candidate_count = sum(
                1 for item in snapshot.get("candidates", [])
                if str(item.get("vehicle", {}).get("id")) in set(vehicle_ids)
            )
            reset_role(cur)
            in_transaction_hits = namespace_hits(cur, tables)
            if not in_transaction_hits:
                raise RuntimeError("Rollback fixture namespace was not observable inside its transaction")
            enabled = set(catalog["plannerEnabledStages"])
            expected = batch_size
            for stage_code, count in eligibility.items():
                if stage_code in enabled and count != expected:
                    raise RuntimeError(f"Expected {expected} eligible fixtures for {stage_code}, got {count}")
                if stage_code not in enabled and count != 0:
                    raise RuntimeError(f"Planner-disabled stage {stage_code} unexpectedly accepted fixtures")
            if aggregate_candidate_count != batch_size * len(enabled.intersection(dict(STAGES))):
                raise RuntimeError("Aggregate Control Board candidate count did not match effective planner-enabled scope")
        conn.rollback()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

    verify = get_conn()
    verify.set_session(readonly=True, autocommit=False)
    try:
        with verify.cursor() as cur:
            assert_staging_catalog(cur)
            tables = table_names(cur)
            after_hits = namespace_hits(cur, tables)
            after_fingerprint = protected_fingerprint(cur, tables)
            cur.execute("select count(*) from public.vehicles where id=any(%s::uuid[])", (vehicle_ids,))
            remaining_vehicles = int(cur.fetchone()[0])
            verify.rollback()
    finally:
        verify.close()
    if after_hits or remaining_vehicles:
        raise RuntimeError("Rollback rehearsal left synthetic staging residue")
    if after_fingerprint != before_fingerprint:
        raise RuntimeError("Protected non-synthetic staging fingerprint changed across rollback rehearsal")
    return {
        "schema": "pdc.qa-wcb-fixture-rollback-rehearsal/v1",
        "runId": RUN_ID,
        "mode": "rollback_rehearsal",
        "projectRef": EXPECTED_STAGING_REF,
        "sourceBranch": branch,
        "sourceCommit": git("rev-parse", "HEAD"),
        "batchSizePerStage": batch_size,
        "plannedRows": len(plan["rows"]),
        "protectedCreatorCalls": len(plan["rows"]),
        "fixtureVehicleCountInsideTransaction": len(vehicle_ids),
        "eligibilityByStage": eligibility,
        "aggregateCandidateCount": aggregate_candidate_count,
        "plannerEnabledStages": catalog["plannerEnabledStages"],
        "plannerDisabledStages": catalog["plannerDisabledStages"],
        "activeBaysByStage": {row["code"]: row["activeBays"] for row in catalog["stages"]},
        "namespaceTablesInsideTransaction": in_transaction_hits,
        "cleanupPreview": cleanup,
        "rollbackComplete": True,
        "remainingNamespaceHits": {},
        "remainingVehicleCount": remaining_vehicles,
        "protectedFingerprintBefore": before_fingerprint,
        "protectedFingerprintAfter": after_fingerprint,
        "protectedFingerprintsUnchanged": True,
        "retainedWrites": 0,
        "productionContacted": False,
        "productionWrites": 0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan", action="store_true", help="Print an offline deterministic fixture plan")
    mode.add_argument("--rollback-rehearsal", action="store_true", help="Exercise one guarded staging batch and roll it back")
    mode.add_argument("--seed-retained", action="store_true", help="Commit guarded namespaced fixture batches")
    parser.add_argument("--batch-size", type=int, default=1, help="Synthetic rows per stage (1-25)")
    parser.add_argument("--confirm-run-id", help="Exact destructive campaign run confirmation")
    parser.add_argument("--manifest", type=Path, help="External retained fixture UUID manifest path")
    parser.add_argument("--backup-run-id", help="Fresh successful staging backup run UUID")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    assert_branch()
    if args.plan:
        result = fixture_plan(args.batch_size)
    elif args.rollback_rehearsal:
        result = rollback_rehearsal(args.batch_size)
    else:
        if not args.manifest or not args.backup_run_id:
            raise RuntimeError("Retained seed requires --manifest and --backup-run-id")
        result = seed_retained(
            args.batch_size, args.manifest, args.confirm_run_id or "", args.backup_run_id
        )
    print(canonical_json(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
