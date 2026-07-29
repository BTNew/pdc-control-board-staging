#!/usr/bin/env python3
"""Rollback-only Stage A 160-vehicle database/engine benchmark for migration 115.

The campaign preserves all operational triggers and canonical Navision authority. It
never writes the migration ledger and never commits. Browser/PostgREST/Realtime are
explicitly outside this transaction-only evidence boundary.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import statistics
import subprocess
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import psycopg

ROOT = Path(__file__).resolve().parents[1]
SQL = ROOT / "supabase/staging_only/115_beta_ai_auditor_foundation.sql"
OUT = ROOT / "review-evidence/stage-a-ai-auditor/performance-160-transaction.json"
SNAP = ROOT / "review-evidence/stage-a-ai-auditor/performance-160-database-snapshot.json"
N = 160
DEALERS = ("14450", "37047")
NS = uuid.UUID("f9e2724a-dc60-4a34-a940-ea9bb4a57dce")
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
OPERATIONAL_TABLES = (
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "workshop_booking_history", "vehicle_parts_updates", "vehicle_movements", "vehicle_master_history",
    "vehicle_master_source_records", "vehicle_aliases", "pdc_authenticated_email_operation_lines",
    "vehicle_workshop_line_adjustments", "vehicle_sublet_providers", "pdc_sublet_bookings",
    "navision_backend_records", "navision_import_batches", "pdc_ai_intake_proposals",
    "pdc_ai_intake_history", "vehicle_notifications", "audit_events", "workshop_stages",
    "workshop_bays", "workshop_technicians", "workshop_settings", "workshop_revision",
    "workshop_station_revision", "vehicle_master_revision", "vehicle_lifecycle_resolver_revision",
    "navision_backend_revision", "pdc_ai_intake_revision", "pdc_email_vehicle_revision",
)
FIXTURE_TABLES = (
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "workshop_booking_history", "vehicle_parts_updates", "vehicle_movements", "vehicle_master_history",
    "vehicle_master_source_records", "vehicle_aliases", "pdc_authenticated_email_operation_lines",
    "vehicle_workshop_line_adjustments", "vehicle_sublet_providers", "pdc_sublet_bookings",
    "navision_backend_records", "navision_import_batches", "pdc_ai_intake_proposals",
    "pdc_ai_intake_history", "vehicle_notifications", "audit_events",
)
AUDITOR_TABLES = (
    "pdc_auditor_user_dealer_scopes", "pdc_auditor_worker_identities",
    "pdc_auditor_booking_work_relations", "pdc_auditor_runs", "pdc_auditor_findings",
    "pdc_auditor_finding_occurrences", "pdc_auditor_finding_history",
    "pdc_auditor_finding_evidence", "pdc_auditor_risk_scores", "pdc_auditor_rule_config",
    "pdc_auditor_report_runs", "pdc_auditor_revision",
)


def uid(label: str) -> uuid.UUID:
    return uuid.uuid5(NS, f"stage-a-160-v1:{label}")


def migration_body() -> str:
    source = SQL.read_text(encoding="utf-8")
    source = re.sub(r"^\s*begin\s*;", "", source, count=1, flags=re.I)
    return re.sub(r"commit\s*;\s*$", "", source, count=1, flags=re.I)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def metric(values: list[float]) -> dict:
    return {
        "samples": len(values),
        "p50_ms": round(percentile(values, 0.50), 2),
        "p95_ms": round(percentile(values, 0.95), 2),
        "max_ms": round(max(values), 2),
    }


def json_default(value):
    if isinstance(value, datetime):
        return value.isoformat().replace("+00:00", "Z")
    if isinstance(value, uuid.UUID):
        return str(value)
    raise TypeError(type(value).__name__)


def json_safe(value):
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    if isinstance(value, datetime):
        return value.isoformat().replace("+00:00", "Z")
    if isinstance(value, uuid.UUID):
        return str(value)
    return value


def set_actor(q, actor: uuid.UUID, email: str) -> None:
    q.execute(
        "select set_config('request.jwt.claims',%s,true)",
        (json.dumps({"sub": str(actor), "email": email, "role": "authenticated"}),),
    )


def relation_exists(q, table: str) -> bool:
    q.execute("select to_regclass(%s) is not null", (f"public.{table}",))
    return q.fetchone()[0]


def state_inventory(q) -> dict:
    tables = {}
    for table in OPERATIONAL_TABLES:
        if not relation_exists(q, table):
            tables[table] = {"present": False}
            continue
        q.execute(
            f"""select count(*)::bigint,
                encode(extensions.digest(convert_to(coalesce(string_agg(row_hash,'' order by row_hash),''),'UTF8'),'sha256'),'hex')
                from (select md5(to_jsonb(t)::text) row_hash from public.{table} t) rows"""
        )
        count, digest = q.fetchone()
        tables[table] = {"present": True, "rows": count, "sha256": digest}
    q.execute(
        """select count(*)::bigint,
           encode(extensions.digest(convert_to(coalesce(string_agg(md5(to_jsonb(m)::text),'' order by md5(to_jsonb(m)::text)),''),'UTF8'),'sha256'),'hex')
           from supabase_migrations.schema_migrations m"""
    )
    ledger_count, ledger_hash = q.fetchone()
    q.execute(
        """select count(*)::integer from pg_trigger t join pg_class c on c.oid=t.tgrelid
           join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and not t.tgisinternal and t.tgenabled <> 'D'"""
    )
    enabled_triggers = q.fetchone()[0]
    canonical = json.dumps(tables, sort_keys=True, separators=(",", ":"))
    return {
        "tables": tables,
        "combined_sha256": hashlib.sha256(canonical.encode()).hexdigest(),
        "migration_ledger": {"rows": ledger_count, "sha256": ledger_hash},
        "enabled_operational_trigger_count": enabled_triggers,
    }


def fixture_counts(q, ids: dict[str, list[uuid.UUID]]) -> dict:
    specs = {
        "vehicles": ("id", ids["vehicles"]),
        "vehicle_work_items": ("id", ids["work_items"]),
        "workshop_bookings": ("id", ids["bookings"]),
        "vehicle_parts_updates": ("id", ids["parts"]),
        "navision_backend_records": ("id", ids["navision"]),
        "navision_import_batches": ("id", ids["batches"]),
    }
    result = {}
    for table, (column, values) in specs.items():
        q.execute(f"select count(*)::integer from public.{table} where {column}=any(%s)", (values,))
        result[table] = q.fetchone()[0]
    q.execute("select count(*)::integer from public.audit_events where vehicle_id=any(%s)", (ids["vehicles"],))
    result["trigger_created_audit_events"] = q.fetchone()[0]
    q.execute("select count(*)::integer from public.workshop_booking_history where booking_id=any(%s)", (ids["bookings"],))
    result["trigger_created_booking_history"] = q.fetchone()[0]
    return result


def read_snapshot(q, samples: int = 1) -> tuple[dict, list[float], list[dict]]:
    timings = []
    retained = None
    retained_manifest = None
    for _ in range(samples):
        pages, manifest, after = [], [], None
        first = None
        started = time.perf_counter()
        for page_number in range(1, 6):
            q.execute("select public.get_pdc_auditor_snapshot(%s,100)", (after,))
            page = q.fetchone()[0]
            if first is None:
                first = page
            else:
                assert page["response_revision"] == first["response_revision"]
                assert page["operational_revision"] == first["operational_revision"]
            items = page["items"]
            assert items
            manifest.append({
                "page_number": page_number,
                "after_vehicle_id": str(after) if after else None,
                "first_vehicle_id": str(items[0]["vehicle_id"]),
                "last_vehicle_id": str(items[-1]["vehicle_id"]),
                "item_count": len(items),
                "has_more": page["has_more"],
                "response_revision": page["response_revision"],
                "operational_revision": page["operational_revision"],
            })
            pages.extend(items)
            if not page["has_more"]:
                break
            after = page["next_vehicle_id"]
        timings.append((time.perf_counter() - started) * 1000)
        retained = {**first, "items": pages, "has_more": False, "next_vehicle_id": None}
        retained_manifest = manifest
    return json_safe(retained), timings, retained_manifest


def engine_benchmark(snapshot_path: Path) -> dict:
    source = r"""
const fs=require('fs'),crypto=require('crypto'),{performance}=require('perf_hooks');
const engine=require('./pdc-ai-auditor-stage-a.js');
const fixtures=require('./pdc-ai-auditor-stage-a-fixtures.js');
const evidence=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));
const output={dealers:{},samples:100};const represented=new Set();
for(const [dealer,snapshot] of Object.entries(evidence.snapshots)){
  const times=[];let result;
  for(let i=0;i<100;i++){const started=performance.now();result=engine.analyze(snapshot);times.push(performance.now()-started);}
  times.sort((a,b)=>a-b);const p=f=>times[Math.floor((times.length-1)*f)];
  const canonical=JSON.stringify(result);
  const ruleIds=[...new Set(result.findings.map(f=>f.ruleId))].sort();ruleIds.forEach(id=>represented.add(id));
  output.dealers[dealer]={vehicles:snapshot.items.length,findings:result.findings.length,rule_ids:ruleIds,
    result_sha256:crypto.createHash('sha256').update(canonical).digest('hex'),
    metric:{samples:times.length,p50_ms:p(.5),p95_ms:p(.95),max_ms:times[times.length-1]}};
}
const catalogue=engine.RULE_CATALOGUE.map(r=>r.id).sort();
output.database_snapshot_observed_rule_coverage={catalogue_rules:catalogue.length,represented_rules:represented.size,represented_rule_ids:[...represented].sort(),missing_rule_ids:catalogue.filter(id=>!represented.has(id)),claim:'observed in the 160-row database-derived snapshot only; not the catalogue-completeness gate'};
const directMatrix={};
for(const rule of engine.RULE_CATALOGUE){
  const fixture=fixtures.buildRuleFixture(rule.id);
  const audited=engine.auditSnapshot(fixture,fixtures.NOW_ISO);
  const matches=audited.findings.filter(f=>f.ruleId===rule.id);
  if(!matches.length) throw new Error(`canonical direct fixture did not exercise ${rule.id}`);
  const finding=matches[0];
  directMatrix[rule.id]={finding_count:matches.length,finding_id:finding.id,severity:finding.severity,risk_score:finding.riskScore,evidence_count:Array.isArray(finding.evidence)?finding.evidence.length:0,source_ref:finding.sourceRef};
}
output.canonical_fixture_rule_coverage={catalogue_rules:catalogue.length,represented_rules:Object.keys(directMatrix).length,missing_rule_ids:catalogue.filter(id=>!directMatrix[id]),matrix:directMatrix,gate_passed:Object.keys(directMatrix).length===catalogue.length};
console.log(JSON.stringify(output));
"""
    raw = subprocess.check_output(["node", "-e", source, str(snapshot_path)], cwd=ROOT, text=True)
    return json.loads(raw)


def payload_hash(q, run: dict, findings: list[dict]) -> str:
    q.execute(
        """select encode(extensions.digest(convert_to(
             (%s::jsonb-array['payload_hash','request_hash']::text[])::text||'|'||%s::jsonb::text,
             'UTF8'),'sha256'),'hex')""",
        (json.dumps(run, separators=(",", ":")), json.dumps(findings, separators=(",", ":"))),
    )
    return q.fetchone()[0]


def main() -> None:
    dsn = os.environ["PDC_STAGING_DATABASE_URL"]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    result = {
        "campaign": "stage-a-160-rollback-only-v1",
        "migration": str(SQL.relative_to(ROOT)).replace("\\", "/"),
        "migration_sha256": hashlib.sha256(SQL.read_bytes()).hexdigest(),
        "committed": False,
        "fixture_namespace_uuid": str(NS),
        "synthetic_vehicles": N,
        "dealer_distribution": {"14450": 80, "37047": 80},
        "provenance": {
            "database_snapshot_rpc": "direct PostgreSQL call to the real migration-115 get_pdc_auditor_snapshot RPC inside the rollback-only transaction",
            "deterministic_engine": "real pdc-ai-auditor-stage-a.js over the captured real RPC wire payload",
            "findings": "real migration-115 submit_pdc_auditor_findings RPC and authenticated RLS refresh inside the same transaction",
            "browser_metrics": "not collected in this transaction-only run",
            "postgrest": "not exercised; no live PostgREST claim",
            "realtime": "not exercised; no live Realtime claim",
        },
    }
    ids = {key: [] for key in ("vehicles", "work_items", "bookings", "parts", "navision", "batches")}

    with psycopg.connect(dsn, autocommit=True) as baseline_connection:
        baseline_q = baseline_connection.cursor()
        baseline_q.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
        assert baseline_q.fetchone()[0] == PROJECT_REF
        before = state_inventory(baseline_q)
    result["operational_before"] = before

    setup_expected = {"vehicles": N, "vehicle_work_items": N * 2, "vehicle_parts_updates": N,
                      "navision_backend_records": N, "navision_import_batches": 2}
    snapshots = {}
    manifests = {}
    try:
        with psycopg.connect(dsn) as connection:
            connection.autocommit = False
            q = connection.cursor()
            q.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton")
            assert q.fetchone()[0] == PROJECT_REF
            q.execute(migration_body())

            q.execute(
                """select r.role::text,u.id,lower(u.email) from public.pdc_user_roles r
                   join auth.users u on u.id=r.auth_user_id and lower(u.email)=lower(r.email)
                   where r.active and r.account_status='approved' and r.role::text='administrator'
                   order by u.id limit 1"""
            )
            admin_role, admin_id, admin_email = q.fetchone()
            q.execute(
                """select r.role::text,u.id,lower(u.email) from public.pdc_user_roles r
                   join auth.users u on u.id=r.auth_user_id and lower(u.email)=lower(r.email)
                   where r.active and r.account_status='approved' and r.role::text='viewer'
                   order by u.id limit 1"""
            )
            viewer_role, viewer_id, viewer_email = q.fetchone()
            actors = {
                "14450": (admin_role, admin_id, admin_email),
                "37047": (viewer_role, viewer_id, viewer_email),
            }
            for dealer, (_, actor, email) in actors.items():
                q.execute(
                    "insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')",
                    (actor, email, dealer),
                )
            q.execute(
                "insert into public.pdc_auditor_worker_identities(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,'14450','staging')",
                (admin_id, admin_email),
            )
            result["role_boundaries"] = {
                "14450": {"role": admin_role, "auth_user_id": str(admin_id), "snapshot_allowed": True, "worker_enrolled": True},
                "37047": {"role": viewer_role, "auth_user_id": str(viewer_id), "snapshot_allowed": True, "worker_enrolled": False},
            }
            calendar = {"public_holidays": ["2026-01-01", "2026-01-26", "2026-04-03", "2026-04-06", "2026-06-01", "2026-09-28", "2026-12-25", "2026-12-28"]}
            for dealer in DEALERS:
                q.execute(
                    """insert into public.pdc_auditor_rule_config(dealer_code,environment,rule_key,config_version,config,provisional)
                       values(%s,'staging','working_calendar',1,%s::jsonb,false)""",
                    (dealer, json.dumps(calendar)),
                )
            q.execute(
                """select s.id,array_agg(b.id order by b.code) from public.workshop_stages s
                   join public.workshop_bays b on b.stage_id=s.id and b.is_active
                   where s.code='FITTING' and s.active and s.planner_enabled group by s.id"""
            )
            stage, bays = q.fetchone()
            q.execute("select transaction_timestamp()")
            recorded_at = q.fetchone()[0]
            base = datetime(2026, 8, 3, 0, 0, tzinfo=timezone.utc)
            isolation_counts = {}
            for dealer in DEALERS:
                q.execute(
                    """update public.navision_backend_records
                       set is_current=false,missing_since_batch_id=last_seen_batch_id,record_status='not_in_latest_batch'
                       where dealer_code=%s and is_current""",
                    (dealer,),
                )
                isolation_counts[dealer] = q.rowcount
                batch = uid(f"navision-batch:{dealer}")
                ids["batches"].append(batch)
                q.execute(
                    """insert into public.navision_import_batches(id,idempotency_key,request_hash,source_name,source_timestamp,
                       source_hash,preview_hash,base_revision,result_revision,status,total_rows,new_count,receipt,actor_id,
                       actor_email,source_system,dealer_code)
                       values(%s,%s,%s,'stage_a_160_transaction_fixture',%s,%s,%s,1,2,'applied',80,80,'{}',%s,%s,
                       'microsoft_navision',%s)""",
                    (batch, f"stage-a-160-transaction-{dealer}", hashlib.sha256(f"request:{dealer}".encode()).hexdigest(),
                     recorded_at, hashlib.sha256(f"source:{dealer}".encode()).hexdigest(),
                     hashlib.sha256(f"preview:{dealer}".encode()).hexdigest(), actors[dealer][1], actors[dealer][2], dealer),
                )
            result["canonical_navision_isolation"] = {
                "method": "valid transactional transition of existing current records to not_in_latest_batch; fully restored by rollback",
                "updated_existing_current_rows": isolation_counts,
            }

            booking_count = 0
            for index in range(N):
                dealer = DEALERS[index // 80]
                actor = actors[dealer][1]
                batch = ids["batches"][index // 80]
                local_index = index % 80
                vehicle = uid(f"vehicle:{dealer}:{local_index}")
                ids["vehicles"].append(vehicle)
                completed = index % 11 == 0
                location = ("YH", "IT", "PMB", "FITTING", "ELEC", "RFT")[index % 6]
                q.execute(
                    """insert into public.vehicles(id,permanent_vehicle_id,lifecycle_state,visible_on_board,source_payload,
                       version,created_at,updated_at,workshop_status,source_batch_id,key_number,stock_number,
                       vehicle_description,current_location,eta_to_kewdale,qc_completed_at,rft_transferred_at,rft_collected_at)
                       values(%s,%s,'active',true,'{}',1,%s,%s,%s,'stage_a_160_transaction_fixture',%s,%s,%s,%s,%s,%s,%s,%s)""",
                    (vehicle, f"STAGE-A-160-{dealer}-{local_index:04d}", base, base + timedelta(minutes=index),
                     "completed" if completed else "queued", f"PA-{dealer}-{local_index:04d}",
                     f"P{dealer[-2:]}{local_index:05d}", f"Stage A deterministic vehicle {dealer} {local_index}", location,
                     (base + timedelta(days=index % 15)).date() if location == "IT" else None,
                     base + timedelta(days=1) if completed else None,
                     base + timedelta(days=2) if completed else None,
                     base + timedelta(days=3) if completed else None),
                )
                navision = uid(f"navision:{dealer}:{local_index}")
                ids["navision"].append(navision)
                q.execute(
                    """insert into public.navision_backend_records(id,source_record_id,row_hash,normalized_data,raw_evidence,
                       canonical_vehicle_id,first_seen_batch_id,last_seen_batch_id,is_current,version,source_system,dealer_code,record_status)
                       values(%s,%s,%s,%s::jsonb,'{}',%s,%s,%s,true,1,'microsoft_navision',%s,'current')""",
                    (navision, f"STAGE-A-160-{dealer}-{local_index:04d}",
                     hashlib.sha256(f"row:{dealer}:{local_index}".encode()).hexdigest(),
                     json.dumps({"stock_number": f"P{dealer[-2:]}{local_index:05d}", "dealer_code": dealer}),
                     vehicle, batch, batch, dealer),
                )
                work_ids = []
                for kind in ("fitting", "electrical"):
                    work = uid(f"work:{dealer}:{local_index}:{kind}")
                    ids["work_items"].append(work)
                    work_ids.append(work)
                    done = completed or (index % 7 == 0 and kind == "fitting")
                    q.execute(
                        "insert into public.vehicle_work_items(id,vehicle_id,work_key,required,completed,completed_at,updated_at) values(%s,%s,%s,%s,%s,%s,%s)",
                        (work, vehicle, kind, index % 13 != 0, done,
                         base + timedelta(hours=3) if done else None, base + timedelta(minutes=index)),
                    )
                parts_state = index % 4
                parts = uid(f"parts:{dealer}:{local_index}")
                ids["parts"].append(parts)
                q.execute(
                    """insert into public.vehicle_parts_updates(id,vehicle_id,parts_required,parts_ordered,parts_received,
                       parts_stoppage,worst_eta,updated_at) values(%s,%s,true,%s,%s,%s,%s,%s)""",
                    (parts, vehicle, parts_state >= 1, parts_state >= 2, parts_state == 1,
                     base + timedelta(days=2 + index % 5) if parts_state < 2 else None, base + timedelta(minutes=index)),
                )
                booking_eligible = not completed and index % 7 != 0 and index % 13 != 0 and location in ("PMB", "IT")
                bookings = (2 if index % 10 == 0 else 1) if booking_eligible else 0
                for booking_index in range(bookings):
                    booking = uid(f"booking:{dealer}:{local_index}:{booking_index}")
                    ids["bookings"].append(booking)
                    start = base + timedelta(days=index)
                    while start.weekday() >= 5:
                        start += timedelta(days=1)
                    start += timedelta(hours=3 * booking_index)
                    end = start + timedelta(hours=2)
                    status = "stoppage" if index % 17 == 0 else "planned"
                    q.execute(
                        """insert into public.workshop_bookings(id,vehicle_id,stage_id,bay_id,status,scheduled_start_at,
                           scheduled_end_at,default_duration_minutes,stoppage_started_at,source,version,created_by,
                           updated_by,created_at,updated_at,metadata)
                           values(%s,%s,%s,%s,%s,%s,%s,120,%s,'planner',1,%s,%s,%s,%s,'{}')""",
                        (booking, vehicle, stage, bays[index % len(bays)], status, start, end,
                         start if status == "stoppage" else None, actor, actor, base, base),
                    )
                    booking_count += 1
                    if index % 5 != 0:
                        q.execute(
                            """insert into public.pdc_auditor_booking_work_relations(relation_id,dealer_code,environment,
                               booking_id,work_item_id,relation_kind,relation_action,source_revision,source_recorded_at)
                               values(%s,%s,'staging',%s,%s,'explicit_fk','asserted',%s,%s)""",
                            (uid(f"relation:{dealer}:{local_index}:{booking_index}"), dealer, booking,
                             work_ids[0], index + 1, recorded_at),
                        )
            setup_expected["workshop_bookings"] = booking_count
            setup_actual = fixture_counts(q, ids)
            for table, expected in setup_expected.items():
                assert setup_actual[table] == expected, (table, setup_actual[table], expected)
            result["fixture_setup_counts"] = {"expected": setup_expected, "actual": setup_actual, "exact": True}

            for dealer, (_, actor, email) in actors.items():
                set_actor(q, actor, email)
                snapshot, timings, manifest = read_snapshot(q, samples=25 if dealer == "14450" else 10)
                assert len(snapshot["items"]) == 80
                assert {item["dealer_code"] for item in snapshot["items"]} == {dealer}
                snapshots[dealer] = snapshot
                manifests[dealer] = manifest
                result.setdefault("database_snapshot_rpc", {})[dealer] = {
                    **metric(timings), "rows": len(snapshot["items"]),
                    "payload_bytes": len(json.dumps(snapshot, separators=(",", ":")).encode()),
                    "response_revision": snapshot["response_revision"],
                    "operational_revision": snapshot["operational_revision"],
                }
            assert sum(len(snapshot["items"]) for snapshot in snapshots.values()) == N

            # Viewer can read only its server-derived dealer and cannot submit worker findings.
            set_actor(q, viewer_id, viewer_email)
            viewer_run = {
                "run_id": str(uid("viewer-denied-run")), "dealer_code": "37047", "environment": "staging",
                "model_key": "stage-a-deterministic-auditor-v3", "operational_revision": snapshots["37047"]["operational_revision"],
                "payload_hash": "0" * 64, "request_hash": "0" * 64,
                "rule_set_hash": snapshots["37047"]["rule_set_hash"], "snapshot_complete": True,
                "snapshot_generated_at": snapshots["37047"]["generated_at"],
                "snapshot_page_manifest": manifests["37047"], "snapshot_response_revision": snapshots["37047"]["response_revision"],
                "snapshot_vehicle_count": 80,
            }
            denied_finding = [{
                "finding_id": str(uid("viewer-denied-finding")), "rule_key": "data_quality_missing_hours",
                "category": "data_quality", "severity": "medium", "summary_code": "missing_hours",
                "entity_type": "vehicle", "entity_id": str(snapshots["37047"]["items"][0]["vehicle_id"]),
                "detected_at": snapshots["37047"]["generated_at"], "risk_score": 8, "confidence": 1,
                "scoring_version": "stage-a-v3", "evidence": [{"entity_type": "vehicle",
                    "entity_id": str(snapshots["37047"]["items"][0]["vehicle_id"]), "signal_code": "missing_hours",
                    "field_code": "hours_present", "numeric_value": None, "boolean_value": False, "timestamp_value": None}],
            }]
            viewer_digest = payload_hash(q, viewer_run, denied_finding)
            viewer_run["payload_hash"] = viewer_run["request_hash"] = viewer_digest
            viewer_denied = False
            q.execute("savepoint viewer_denial")
            try:
                q.execute("select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)",
                          (json.dumps(viewer_run), json.dumps(denied_finding)))
            except psycopg.errors.InsufficientPrivilege:
                q.execute("rollback to savepoint viewer_denial")
                viewer_denied = True
            assert viewer_denied
            result["role_boundaries"]["37047"]["findings_submit_denied"] = True

            snapshot_evidence = {
                "campaign": result["campaign"],
                "provenance": result["provenance"],
                "fixture_namespace_uuid": str(NS),
                "snapshots": snapshots,
                "page_manifests": manifests,
            }
            SNAP.write_text(json.dumps(snapshot_evidence, default=json_default, separators=(",", ":")), encoding="utf-8")
            result["database_snapshot_evidence"] = {
                "path": str(SNAP.relative_to(ROOT)).replace("\\", "/"),
                "sha256": hashlib.sha256(SNAP.read_bytes()).hexdigest(),
                "bytes": SNAP.stat().st_size,
                "rows": N,
            }
            result["deterministic_engine"] = engine_benchmark(SNAP)

            # Submit one deterministic engine-derived recommendation shape through the real RPC.
            set_actor(q, admin_id, admin_email)
            entity = str(snapshots["14450"]["items"][0]["vehicle_id"])
            finding = [{
                "finding_id": str(uid("submitted-finding:14450")), "rule_key": "data_quality_missing_hours",
                "category": "data_quality", "severity": "medium", "summary_code": "missing_hours",
                "entity_type": "vehicle", "entity_id": entity,
                "detected_at": snapshots["14450"]["generated_at"], "risk_score": 8, "confidence": 1,
                "scoring_version": "stage-a-v3", "evidence": [{"entity_type": "vehicle", "entity_id": entity,
                    "signal_code": "missing_hours", "field_code": "hours_present", "numeric_value": None,
                    "boolean_value": False, "timestamp_value": None}],
            }]
            run = {
                "run_id": str(uid("submitted-run:14450")), "dealer_code": "14450", "environment": "staging",
                "model_key": "stage-a-deterministic-auditor-v3", "operational_revision": snapshots["14450"]["operational_revision"],
                "payload_hash": "0" * 64, "request_hash": "0" * 64,
                "rule_set_hash": snapshots["14450"]["rule_set_hash"], "snapshot_complete": True,
                "snapshot_generated_at": snapshots["14450"]["generated_at"],
                "snapshot_page_manifest": manifests["14450"], "snapshot_response_revision": snapshots["14450"]["response_revision"],
                "snapshot_vehicle_count": 80,
            }
            digest = payload_hash(q, run, finding)
            run["payload_hash"] = run["request_hash"] = digest
            started = time.perf_counter()
            q.execute("select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)",
                      (json.dumps(run), json.dumps(finding)))
            submitted = q.fetchone()[0]
            submit_ms = (time.perf_counter() - started) * 1000
            assert submitted["code"] == "findings_appended"
            q.execute("select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)",
                      (json.dumps(run), json.dumps(finding)))
            replay = q.fetchone()[0]
            assert replay["code"] == "exact_replay"
            started = time.perf_counter()
            refreshed_snapshot, refresh_timing, _ = read_snapshot(q, samples=1)
            q.execute(
                """select finding_id,rule_key,lifecycle_status,last_seen_run_id from public.pdc_auditor_findings
                   where dealer_code='14450' and environment='staging' and finding_id=%s""", (uid("submitted-finding:14450"),)
            )
            refreshed_finding = q.fetchone()
            refresh_ms = (time.perf_counter() - started) * 1000
            assert refreshed_finding and refreshed_finding[2] == "current"
            assert refreshed_snapshot["response_revision"] != snapshots["14450"]["response_revision"]
            assert refreshed_snapshot["operational_revision"] == snapshots["14450"]["operational_revision"]
            result["findings_submit_refresh"] = {
                "submit_ms": round(submit_ms, 2), "submit_result": submitted,
                "exact_replay_result": replay, "refresh_ms": round(refresh_ms, 2),
                "snapshot_rpc_refresh_ms": round(refresh_timing[0], 2),
                "finding": {"finding_id": str(refreshed_finding[0]), "rule_key": refreshed_finding[1],
                            "lifecycle_status": refreshed_finding[2], "last_seen_run_id": str(refreshed_finding[3])},
                "auditor_revision_changed": True, "operational_revision_unchanged": True,
            }
            result["role_boundaries"]["14450"]["findings_submit_allowed"] = True

            during = state_inventory(q)
            assert during["migration_ledger"] == before["migration_ledger"]
            assert during["enabled_operational_trigger_count"] >= before["enabled_operational_trigger_count"]
            result["during_transaction"] = {
                "migration_ledger_unchanged": True,
                "enabled_trigger_count_before": before["enabled_operational_trigger_count"],
                "enabled_trigger_count_during": during["enabled_operational_trigger_count"],
                "no_trigger_disabled": True,
            }
            connection.rollback()
    finally:
        with psycopg.connect(dsn, autocommit=True) as post_connection:
            post_q = post_connection.cursor()
            after = state_inventory(post_q)
            rollback_counts = fixture_counts(post_q, ids) if ids["vehicles"] else {}
            auditor_objects_remaining = {table: relation_exists(post_q, table) for table in AUDITOR_TABLES}
        result["operational_after"] = after
        result["rollback_fixture_counts"] = rollback_counts
        result["auditor_objects_remaining_after_rollback"] = auditor_objects_remaining
        result["rollback_verification"] = {
            "operational_combined_hash_equal": before["combined_sha256"] == after["combined_sha256"],
            "operational_table_hashes_equal": before["tables"] == after["tables"],
            "migration_ledger_equal": before["migration_ledger"] == after["migration_ledger"],
            "enabled_trigger_count_equal": before["enabled_operational_trigger_count"] == after["enabled_operational_trigger_count"],
            "fixture_counts_all_zero": bool(rollback_counts) and all(value == 0 for value in rollback_counts.values()),
            "migration_objects_absent": not any(auditor_objects_remaining.values()),
        }
        result["rollback_complete"] = all(result["rollback_verification"].values())
        OUT.write_text(json.dumps(result, default=json_default, indent=2, sort_keys=True), encoding="utf-8")
    assert result["rollback_complete"], result["rollback_verification"]
    print(json.dumps(result, default=json_default, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
