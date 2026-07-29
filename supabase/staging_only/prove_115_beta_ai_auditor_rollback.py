#!/usr/bin/env python3
"""Stage A migration 115 proof: static + live apply inside one rollback-only transaction."""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import sys
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

import psycopg

ROOT = Path(__file__).resolve().parents[2]
MIGRATION = ROOT / "supabase" / "staging_only" / "115_beta_ai_auditor_foundation.sql"
OUT_JSON = ROOT / "review-evidence" / "stage-a-ai-auditor" / "rollback-proof-115.json"
OUT_MD = ROOT / "review-evidence" / "stage-a-ai-auditor" / "rollback-proof-115.md"
PROJECT_REF = "cdsmnqxtyyoeoznmbidd"
AUDITOR_TABLES = [
    "pdc_auditor_user_dealer_scopes", "pdc_auditor_worker_identities",
    "pdc_auditor_booking_work_relations", "pdc_auditor_runs", "pdc_auditor_findings",
    "pdc_auditor_finding_occurrences", "pdc_auditor_finding_history",
    "pdc_auditor_finding_evidence", "pdc_auditor_risk_scores", "pdc_auditor_rule_config",
    "pdc_auditor_report_runs", "pdc_auditor_revision",
]
RPCS = [
    "pdc_auditor_actor_scope()", "pdc_auditor_worker_scope(text)",
    "pdc_auditor_json_has_sensitive_key(jsonb)", "pdc_auditor_operational_revision(text)",
    "get_pdc_auditor_snapshot(uuid,integer)", "submit_pdc_auditor_findings(jsonb,jsonb)",
    "append_pdc_auditor_rule_config(text,jsonb,boolean)",
]
OPERATIONAL = [
    "vehicles", "vehicle_work_items", "workshop_bookings", "workshop_booking_assignments",
    "workshop_booking_history", "vehicle_parts_updates", "vehicle_movements", "audit_events",
    "pdc_ai_intake_proposals", "pdc_ai_intake_history", "vehicle_notifications",
    "navision_backend_records", "vehicle_master_history", "vehicle_master_source_records",
    "vehicle_aliases", "pdc_authenticated_email_operation_lines",
    "vehicle_workshop_line_adjustments", "vehicle_sublet_providers", "pdc_sublet_bookings",
    # Additional operational/authority/configuration relations read by migration 115 and the
    # authenticated browser campaign. Hashing read dependencies prevents a narrow immutability claim.
    "navision_backend_revision", "pdc_ai_intake_revision", "pdc_email_vehicle_revision",
    "pdc_staging_environment_sentinel", "pdc_user_roles", "vehicle_lifecycle_resolver_revision",
    "vehicle_master_revision", "workshop_bays", "workshop_revision", "workshop_settings",
    "workshop_stages", "workshop_station_revision", "workshop_technicians",
]


def migration_source() -> str:
    return MIGRATION.read_text(encoding="utf-8").replace("\r\n", "\n")


def migration_body(source: str) -> str:
    body = re.sub(r"(?im)^\s*begin;\s*$", "", source, count=1)
    body = re.sub(r"(?im)^\s*commit;\s*$", "", body, count=1)
    if body == source or re.search(r"(?im)^\s*(begin|commit);\s*$", body):
        raise RuntimeError("failed to isolate migration body")
    return body


def static_contract(source: str) -> dict:
    lowered = source.lower()
    missing = [name for name in AUDITOR_TABLES if f"public.{name}" not in lowered]
    missing += [sig for sig in RPCS if sig.split("(")[0] not in lowered]
    forbidden_dml = []
    submit = source.split("as $submit$", 1)[1].split("$submit$;", 1)[0]
    for verb, table in re.findall(r"(?is)\b(insert\s+into|update|delete\s+from)\s+public\.([a-z0-9_]+)", submit):
        if table not in AUDITOR_TABLES:
            forbidden_dml.append(f"{verb}:{table}")
    checks = {
        "outer_transaction": source.lstrip().startswith("--") and "begin;" in lowered and lowered.rstrip().endswith("commit;"),
        "staging_sentinel": PROJECT_REF in source and "PDC_AUDITOR_115_STAGING_SENTINEL_MISMATCH" in source,
        "migration_identity": "version = '114'" in source and "contain_multi_attachment_email_import" in source and "version = '115'" in source,
        "all_expected_objects_present": not missing,
        "submission_dml_auditor_only": not forbidden_dml,
        "recursive_sensitive_key_guard": "with recursive walk" in lowered and "pdc_auditor_json_has_sensitive_key(p_findings)" in lowered,
        "worker_excludes_viewer": "r.role::text in ('operator','administrator')" in source,
        "server_payload_hash": "v_computed_payload_hash := encode(extensions.digest" in lowered,
        "realtime_revision_only": "alter publication supabase_realtime add table public.pdc_auditor_revision" in lowered,
        "no_service_role_grant": "to service_role" not in lowered,
    }
    if missing or forbidden_dml or not all(checks.values()):
        raise AssertionError({"static_checks": checks, "missing": missing, "forbidden_dml": forbidden_dml})
    return {"checks": checks, "migration_sha256": hashlib.sha256(source.encode()).hexdigest()}


def pin_url(dsn: str) -> str:
    parsed = urlparse(dsn)
    identity = f"{parsed.hostname or ''}{parsed.path or ''}{parsed.username or ''}"
    if PROJECT_REF not in identity:
        raise RuntimeError("refusing database URL not pinned to the staging project ref")
    return parsed.hostname or "pinned-staging-host"


def object_state(conn) -> dict:
    with conn.cursor() as cur:
        out = {}
        for table in AUDITOR_TABLES:
            cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
            out[table] = cur.fetchone()[0]
        return out


def table_hashes(cur) -> dict:
    result = {}
    for table in OPERATIONAL:
        cur.execute("select to_regclass(%s) is not null", (f"public.{table}",))
        if not cur.fetchone()[0]:
            raise AssertionError(f"required operational table missing: {table}")
        cur.execute(f"select count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
        count, digest = cur.fetchone()
        result[table] = {"rows": count, "md5": digest}
    return result


def migration_ledger_signature(cur) -> dict:
    cur.execute("""select count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'' order by version,name),'')),
      count(*) filter(where version='115' and name='beta_ai_auditor_foundation'),
      count(*) filter(where version='115' and name<>'beta_ai_auditor_foundation'),
      count(*) filter(where version='114' and name='contain_multi_attachment_email_import')
      from supabase_migrations.schema_migrations t""")
    rows, digest, beta_rows, conflicting_115_rows, predecessor_114_rows = cur.fetchone()
    return {"rows": rows, "md5": digest, "beta_ai_auditor_rows": beta_rows,
            "conflicting_115_rows": conflicting_115_rows,
            "predecessor_114_rows": predecessor_114_rows}


def reject(cur, sql: str, params, token: str) -> str:
    name = "expected_rejection"
    cur.execute(f"savepoint {name}")
    try:
        cur.execute(sql, params)
    except psycopg.Error as exc:
        message = str(exc)
        cur.execute(f"rollback to savepoint {name}")
        if token not in message:
            raise AssertionError(f"expected {token}, received {message.splitlines()[0]}")
        return message.splitlines()[0]
    cur.execute(f"rollback to savepoint {name}")
    raise AssertionError(f"expected rejection containing {token}")


def set_claims(cur, uid, email, dealer_claim="forged-browser-claim") -> None:
    claims = {"sub": str(uid), "email": email, "role": "authenticated", "dealer_code": dealer_claim}
    cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps(claims),))


def capture_snapshot(cur, page_size=100) -> tuple[dict, list[dict]]:
    after = None
    pages, items = [], []
    expected_revision = None
    for number in range(1, 6):
        cur.execute("select public.get_pdc_auditor_snapshot(%s,%s)", (after, page_size))
        page = cur.fetchone()[0]
        if expected_revision is None:
            expected_revision = page["response_revision"]
        if page["response_revision"] != expected_revision or page["operational_revision"] != page["page_manifest"]["operational_revision"]:
            raise AssertionError("pagination revision changed")
        rows = page["items"]
        if not rows:
            raise AssertionError("complete snapshot contained an empty page")
        manifest = {
            "after_vehicle_id": after,
            "first_vehicle_id": str(rows[0]["vehicle_id"]),
            "has_more": bool(page["has_more"]),
            "item_count": len(rows),
            "last_vehicle_id": str(rows[-1]["vehicle_id"]),
            "operational_revision": page["operational_revision"],
            "page_number": number,
            "page_size": page_size,
            "response_revision": page["response_revision"],
        }
        pages.append(manifest)
        items.extend(rows)
        if not page["has_more"]:
            merged = dict(page)
            merged["items"] = items
            merged["has_more"] = False
            merged["next_vehicle_id"] = None
            merged["page_size"] = page_size
            merged["page_manifest"] = {**page["page_manifest"], "returned_count": len(items), "has_more": False, "next_vehicle_id": None}
            return merged, pages
        after = str(page["next_vehicle_id"])
    raise AssertionError("snapshot exceeded five-page submission bound")


def payload(cur, snapshot: dict, pages: list[dict], dealer: str, ordinal: int, findings: list[dict]) -> dict:
    run = {
        "dealer_code": dealer,
        "environment": "staging",
        "model_key": "stage-a-proof-v2",
        "operational_revision": snapshot["operational_revision"],
        "payload_hash": "0" * 64,
        "request_hash": "0" * 64,
        "rule_set_hash": snapshot["rule_set_hash"],
        "run_id": str(uuid.uuid4()),
        "snapshot_complete": True,
        "snapshot_generated_at": (datetime(2035, 1, 1, tzinfo=timezone.utc) + timedelta(minutes=ordinal)).isoformat().replace("+00:00", "Z"),
        "snapshot_page_manifest": pages,
        "snapshot_response_revision": snapshot["response_revision"],
        "snapshot_vehicle_count": len(snapshot["items"]),
    }
    cur.execute("select encode(extensions.digest(convert_to((%s::jsonb-array['payload_hash','request_hash']::text[])::text||'|'||%s::jsonb::text,'UTF8'),'sha256'),'hex')", (json.dumps(run), json.dumps(findings)))
    digest = cur.fetchone()[0]
    run["payload_hash"] = digest
    run["request_hash"] = digest
    return run


def submit(cur, run, findings) -> dict:
    cur.execute("select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)", (json.dumps(run), json.dumps(findings)))
    result = cur.fetchone()[0]
    if result.get("ok") is not True:
        raise AssertionError(result)
    return result


def generic_fk_proof(cur) -> dict:
    cur.execute("select count(*),count(*) filter(where convalidated) from pg_constraint where contype='f' and connamespace='public'::regnamespace")
    total, validated = cur.fetchone()
    if total != validated:
        raise AssertionError(f"unvalidated public FKs: {total-validated}")
    violations = []
    cur.execute("""select c.oid,c.conname,c.conrelid::regclass::text,c.confrelid::regclass::text,
      array_agg(quote_ident(ca.attname) order by u.n),array_agg(quote_ident(pa.attname) order by u.n)
      from pg_constraint c join lateral unnest(c.conkey,c.confkey) with ordinality u(ca_num,pa_num,n) on true
      join pg_attribute ca on ca.attrelid=c.conrelid and ca.attnum=u.ca_num
      join pg_attribute pa on pa.attrelid=c.confrelid and pa.attnum=u.pa_num
      where c.contype='f' and c.connamespace='public'::regnamespace
      group by c.oid,c.conname,c.conrelid,c.confrelid order by c.conname""")
    constraints = cur.fetchall()
    for _, name, child, parent, child_cols, parent_cols in constraints:
        join = " and ".join(f"c.{cc}=p.{pc}" for cc, pc in zip(child_cols, parent_cols))
        nonnull = " and ".join(f"c.{cc} is not null" for cc in child_cols)
        cur.execute(f"select count(*) from {child} c where {nonnull} and not exists(select 1 from {parent} p where {join})")
        n = cur.fetchone()[0]
        if n:
            violations.append({"constraint": name, "orphans": n})
    if violations:
        raise AssertionError({"fk_violations": violations})
    return {"constraints_checked": len(constraints), "validated": validated, "orphan_rows": 0}


def encrypted_logical_payload_round_trip_proof(cur) -> dict:
    key = secrets.token_hex(32)
    schema = f"pdc_auditor_restore_{uuid.uuid4().hex[:12]}"
    backup = {}
    for table in AUDITOR_TABLES:
        cur.execute(f"select coalesce(jsonb_agg(to_jsonb(t) order by md5(to_jsonb(t)::text)),'[]'::jsonb)::text from public.{table} t")
        backup[table] = cur.fetchone()[0]
    plain = json.dumps(backup, sort_keys=True, separators=(",", ":"))
    cur.execute("select extensions.pgp_sym_encrypt(%s,%s,'cipher-algo=aes256,compress-algo=1')", (plain, key))
    encrypted = bytes(cur.fetchone()[0])
    if plain.encode() in encrypted:
        raise AssertionError("encrypted backup contains plaintext")
    cur.execute("select extensions.pgp_sym_decrypt(%s::bytea,%s)", (encrypted, key))
    decrypted = cur.fetchone()[0]
    cur.execute(f"create schema {schema}")
    try:
        for table in AUDITOR_TABLES:
            cur.execute(f"create table {schema}.{table}_restore(payload jsonb not null)")
            cur.execute(f"insert into {schema}.{table}_restore(payload) select value from jsonb_array_elements(((%s::jsonb)->>%s)::jsonb)", (decrypted, table))
            cur.execute(f"select count(*),md5(coalesce(string_agg(payload::text,'' order by md5(payload::text)),'')) from {schema}.{table}_restore")
            restored_sig = cur.fetchone()
            cur.execute(f"select count(*),md5(coalesce(string_agg(to_jsonb(t)::text,'' order by md5(to_jsonb(t)::text)),'')) from public.{table} t")
            if restored_sig != cur.fetchone():
                raise AssertionError(f"isolated restore mismatch: {table}")
    finally:
        cur.execute(f"drop schema {schema} cascade")
    cur.execute("select to_regnamespace(%s) is null", (schema,))
    if not cur.fetchone()[0]:
        raise AssertionError("restore schema residue")
    return {
        "scope": "encrypted logical row-payload round trip only; not a schema, ACL, RLS, publication or disaster-recovery restore",
        "algorithm": "OpenPGP AES-256 symmetric (in-memory)",
        "ciphertext_bytes": len(encrypted),
        "table_payloads_round_tripped": len(AUDITOR_TABLES),
        "temporary_schema_removed": True,
    }


def run() -> dict:
    dsn = os.environ.get("PDC_STAGING_DATABASE_URL", "")
    if not dsn:
        raise RuntimeError("PDC_STAGING_DATABASE_URL is required")
    host = pin_url(dsn)
    source = migration_source()
    result = {"committed": False, "migration": 115, "migration_name": "beta_ai_auditor_foundation", "project_ref": PROJECT_REF, "database_host": host, "static": static_contract(source)}
    with psycopg.connect(dsn, autocommit=True) as probe:
        before_objects = object_state(probe)
        with probe.cursor() as cur:
            before_operational = table_hashes(cur)
            ledger_before = migration_ledger_signature(cur)
    if any(before_objects.values()):
        raise AssertionError(f"migration 115 objects already exist before rollback proof: {before_objects}")

    with psycopg.connect(dsn, autocommit=False) as conn:
        try:
            cur = conn.cursor()
            cur.execute("select current_database(),current_user,(select project_ref from public.pdc_staging_environment_sentinel where singleton),current_setting('app.project_ref',true)")
            database, actor, sentinel, app_ref = cur.fetchone()
            if sentinel != PROJECT_REF:
                raise AssertionError("database sentinel mismatch")
            result.update({"database": database, "database_actor": actor, "app_project_ref_setting": app_ref, "service_role_used": actor == "service_role"})
            if result["service_role_used"]:
                raise AssertionError("proof must not use service_role")

            cur.execute("savepoint wrong_environment")
            cur.execute("update public.pdc_staging_environment_sentinel set project_ref='wrong-project-proof' where singleton")
            wrong_env = reject(cur, migration_body(source), None, "PDC_AUDITOR_115_STAGING_SENTINEL_MISMATCH")
            cur.execute("rollback to savepoint wrong_environment")
            cur.execute(migration_body(source))

            during = object_state(conn)
            if not all(during.values()):
                raise AssertionError({"missing_objects": during})
            cur.execute("select count(*) from pg_proc where oid=any(%s::regprocedure[])", (RPCS,))
            rpc_count = cur.fetchone()[0]
            if rpc_count != len(RPCS):
                raise AssertionError(f"RPC inventory mismatch: {rpc_count}/{len(RPCS)}")
            cur.execute("select count(*) from pg_trigger where not tgisinternal and tgname like 'pdc_auditor_%_immutable'")
            immutable_triggers = cur.fetchone()[0]
            if immutable_triggers < 8:
                raise AssertionError(f"immutable trigger count too low: {immutable_triggers}")

            # Migration exact replay cannot mutate append-only seed rows.
            cur.execute("select count(*),md5(string_agg(to_jsonb(t)::text,'' order by to_jsonb(t)::text)) from public.pdc_auditor_rule_config t")
            seed_before = cur.fetchone()
            cur.execute(migration_body(source))
            cur.execute("select count(*),md5(string_agg(to_jsonb(t)::text,'' order by to_jsonb(t)::text)) from public.pdc_auditor_rule_config t")
            if cur.fetchone() != seed_before:
                raise AssertionError("migration replay changed seed configuration")

            cur.execute("""select r.auth_user_id,lower(r.email),r.role::text from public.pdc_user_roles r
                join auth.users u on u.id=r.auth_user_id and lower(u.email)=lower(r.email)
                where r.active and r.account_status='approved' and r.role::text in ('operator','administrator')
                group by r.auth_user_id,lower(r.email),r.role::text having count(*)=1
                order by (r.role::text='administrator') desc limit 1""")
            actor_row = cur.fetchone()
            if not actor_row:
                raise AssertionError("no approved operator/administrator available")
            uid, email, role = actor_row
            cur.execute("""select public.pdc_auditor_vehicle_dealer(v.id),count(*) from public.vehicles v
                where v.deleted_at is null and public.pdc_auditor_vehicle_dealer(v.id) in ('14450','37047')
                group by 1 having count(*) between 1 and 500 order by count(*) desc limit 1""")
            dealer_row = cur.fetchone()
            if not dealer_row:
                raise AssertionError("no dealer has 1..500 authoritative vehicles")
            dealer, dealer_vehicle_count = dealer_row
            other_dealer = "37047" if dealer == "14450" else "14450"
            cur.execute("insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')", (uid, email, dealer))
            cur.execute("insert into public.pdc_auditor_worker_identities(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')", (uid, email, dealer))
            set_claims(cur, uid, email, other_dealer)

            snapshot, pages = capture_snapshot(cur, 100)
            if snapshot["dealer_code"] != dealer or len(snapshot["items"]) != dealer_vehicle_count:
                raise AssertionError("server dealer scope or complete page count mismatch")
            # Independent small-page walk establishes cursor behavior, exact IDs, and bound.
            _, small_pages = capture_snapshot(cur, min(17, dealer_vehicle_count))
            small_ids = [m["last_vehicle_id"] for m in small_pages]
            if len(small_ids) != len(set(small_ids)):
                raise AssertionError("pagination cursor repeated")

            vehicle_id = str(snapshot["items"][0]["vehicle_id"])
            stable_input_id = str(uuid.uuid4())
            def finding(value, n, finding_id=None):
                return {"category":"data_quality","confidence":0.8,"detected_at":(datetime(2035,1,1,tzinfo=timezone.utc)+timedelta(minutes=n)).isoformat().replace("+00:00","Z"),"entity_id":vehicle_id,"entity_type":"vehicle","evidence":[{"boolean_value":None,"entity_id":vehicle_id,"entity_type":"vehicle","field_code":"version","numeric_value":value,"signal_code":"proof_signal","timestamp_value":None}],"finding_id":finding_id or str(uuid.uuid4()),"risk_score":25,"rule_key":"proof_rule","scoring_version":"proof-v2","severity":"medium","summary_code":"proof_recommendation"}

            # A complete worker submission is accepted only from canonical 100-row pages.
            # Caller-declared boundaries are reconstructed server-side before any write.
            probe_findings = [finding(1, 0)]
            fabricated_pages = [dict(page) for page in pages]
            fabricated_pages[0]["first_vehicle_id"] = fabricated_pages[0]["last_vehicle_id"]
            fabricated_run = payload(cur, snapshot, fabricated_pages, dealer, 0, probe_findings)
            fabricated_manifest_rejected = reject(
                cur, "select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)",
                (json.dumps(fabricated_run), json.dumps(probe_findings)), "pdc_auditor_incomplete_snapshot")
            wrong_page_size = [dict(page, page_size=17) for page in pages]
            wrong_page_size_run = payload(cur, snapshot, wrong_page_size, dealer, 0, probe_findings)
            noncanonical_submission_page_size_rejected = reject(
                cur, "select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)",
                (json.dumps(wrong_page_size_run), json.dumps(probe_findings)), "pdc_auditor_incomplete_snapshot")

            runs = []
            sequences = [[finding(1,1,stable_input_id)],[finding(1,2)],[],[finding(1,4)],[finding(2,5)]]
            for n, findings in enumerate(sequences, 1):
                # Each completed submission bumps auditor_revision, so bind every run to a fresh
                # complete snapshot while preserving the same operational fixture set.
                if n > 1:
                    snapshot, pages = capture_snapshot(cur, 100)
                run_data = payload(cur, snapshot, pages, dealer, n, findings)
                response = submit(cur, run_data, findings)
                runs.append((run_data, findings, response))
                if n == 1:
                    replay = submit(cur, run_data, findings)
                    if replay.get("code") != "exact_replay":
                        raise AssertionError("exact replay not recognized")
            cur.execute("""select count(*),count(distinct finding_id),min(finding_id::text),min(lifecycle_status),
                min(first_detected_at),max(last_evidence_change_at) from public.pdc_auditor_findings where dealer_code=%s and rule_key='proof_rule'""", (dealer,))
            finding_rows, stable_ids, persisted_id, status, first_at, evidence_changed_at = cur.fetchone()
            cur.execute("select count(*) from public.pdc_auditor_finding_occurrences o join public.pdc_auditor_findings f on f.finding_id=o.finding_id where f.rule_key='proof_rule'")
            occurrences = cur.fetchone()[0]
            cur.execute("select event_type,count(*) from public.pdc_auditor_finding_history h join public.pdc_auditor_findings f on f.finding_id=h.finding_id where f.rule_key='proof_rule' group by event_type order by event_type")
            history = dict(cur.fetchall())
            if (finding_rows, stable_ids, persisted_id, status, occurrences) != (1, 1, stable_input_id, "current", 4):
                raise AssertionError("stable lifecycle identity/occurrence proof failed")
            if history.get("resolved") != 1 or history.get("reopened") != 1 or evidence_changed_at <= first_at:
                raise AssertionError("resolution/reappearance/evidence-change proof failed")

            # Wrong environment and dealer are rejected before writes.
            bad_env = dict(runs[-1][0]); bad_env["run_id"] = str(uuid.uuid4()); bad_env["environment"] = "production"
            wrong_submission_env = reject(cur, "select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)", (json.dumps(bad_env), json.dumps(runs[-1][1])), "pdc_auditor_invalid_run")
            bad_dealer = dict(runs[-1][0]); bad_dealer["run_id"] = str(uuid.uuid4()); bad_dealer["dealer_code"] = other_dealer
            wrong_dealer = reject(cur, "select public.submit_pdc_auditor_findings(%s::jsonb,%s::jsonb)", (json.dumps(bad_dealer), json.dumps(runs[-1][1])), "pdc_auditor_worker_unauthorized")

            # Viewer can read its RLS dealer but cannot become a worker.
            cur.execute("""select r.auth_user_id,lower(r.email) from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id
                where r.active and r.account_status='approved' and r.role::text='viewer' and lower(u.email)=lower(r.email) limit 1""")
            viewer = cur.fetchone()
            viewer_rejected = None
            if viewer:
                vu, ve = viewer
                cur.execute("insert into public.pdc_auditor_user_dealer_scopes(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')", (vu, ve, dealer))
                cur.execute("insert into public.pdc_auditor_worker_identities(auth_user_id,normalized_email,dealer_code,environment) values(%s,%s,%s,'staging')", (vu, ve, dealer))
                set_claims(cur, vu, ve)
                viewer_rejected = reject(cur, "select public.pdc_auditor_worker_scope(%s)", (dealer,), "pdc_auditor_worker_unauthorized")
                set_claims(cur, uid, email)

            cur.execute("set local role authenticated")
            set_claims(cur, uid, email)
            cur.execute("select count(*) from public.pdc_auditor_findings")
            rls_own_count = cur.fetchone()[0]
            cur.execute("select has_table_privilege('authenticated','public.pdc_auditor_findings','insert,update,delete')")
            direct_write = cur.fetchone()[0]
            cur.execute("reset role")
            if rls_own_count < 1 or direct_write:
                raise AssertionError("RLS/direct-write contract failed")

            fk = generic_fk_proof(cur)
            logical_backup = encrypted_logical_payload_round_trip_proof(cur)
            during_operational = table_hashes(cur)
            if during_operational != before_operational:
                raise AssertionError("Stage A changed operational table hashes")

            result.update({
                "apply": {"all_auditor_tables_present": True, "rpc_count": rpc_count, "immutable_trigger_count": immutable_triggers, "migration_exact_replay": True},
                "wrong_environment_migration_rejected": wrong_env,
                "actor_role": role, "dealer_code": dealer, "dealer_vehicle_count": dealer_vehicle_count,
                "bounded_pagination": {"submission_pages": len(pages), "small_page_size": min(17,dealer_vehicle_count), "small_pages": len(small_pages), "unique_cursors": True},
                "lifecycle": {"stable_finding_rows": finding_rows, "stable_finding_ids": stable_ids, "persisted_first_finding_id": persisted_id, "occurrences": occurrences, "history": history, "status": status, "evidence_change_recorded": True, "resolved_then_reappeared": True, "exact_replay": True},
                "rejections": {"wrong_submission_environment": wrong_submission_env, "wrong_dealer": wrong_dealer, "viewer_worker": viewer_rejected or "SKIP:no approved viewer fixture", "fabricated_page_manifest": fabricated_manifest_rejected, "noncanonical_submission_page_size": noncanonical_submission_page_size_rejected},
                "security": {"claims_simulated_with_request_jwt_claims": True, "forged_jwt_dealer_ignored": True, "rls_own_rows": rls_own_count, "authenticated_direct_write": direct_write, "service_role_used": False},
                "payload_hash_computed_server_side": True,
                "operational_hashes_before": before_operational,
                "operational_hashes_during": during_operational,
                "operational_unchanged_during": True,
                "foreign_keys": fk,
                "encrypted_logical_payload_round_trip_not_disaster_restore": logical_backup,
            })
        finally:
            conn.rollback()

    with psycopg.connect(dsn, autocommit=True) as fresh:
        after_objects = object_state(fresh)
        with fresh.cursor() as cur:
            after_operational = table_hashes(cur)
            ledger_after = migration_ledger_signature(cur)
            cur.execute("select to_regnamespace('pdc_auditor_restore_leak')")
    if any(after_objects.values()) or after_operational != before_operational or ledger_after != ledger_before:
        raise AssertionError({"rollback_objects": after_objects, "operational_equal": after_operational == before_operational,
                              "migration_ledger_equal": ledger_after == ledger_before})
    if ledger_after["beta_ai_auditor_rows"] != 0:
        raise AssertionError("Stage A migration unexpectedly present in migration ledger")
    result.update({"rollback": {"fresh_connection": True, "migration_objects_absent": True, "object_state": after_objects,
                    "operational_hashes_unchanged": True, "migration_ledger_unchanged": True},
                   "migration_ledger_before": ledger_before, "migration_ledger_after": ledger_after,
                   "operational_hashes_after_rollback": after_operational, "passed": True})
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    evidence_result = dict(result)
    for sensitive_connection_key in ("project_ref", "database_host", "database", "database_actor", "app_project_ref_setting"):
        evidence_result[sensitive_connection_key] = "[REDACTED]"
    OUT_JSON.write_text(json.dumps(evidence_result, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
    OUT_MD.write_text("# Migration 115 rollback proof\n\n**PASS** — static contract, exact predecessor/version identity, rollback-only apply/replay, schema/RPC, authenticated RLS and worker rejection, lifecycle identity/evidence/resolution/reappearance/exact replay, server-reconstructed canonical submission pages, wrong-environment/dealer rejection, operational hashes, all public FKs, and fresh-connection rollback restoration/absence passed.\n\nThe encrypted exercise is explicitly limited to an in-memory logical row-payload encryption/decryption round trip. It is **not** claimed as a schema, ACL, RLS, publication, or disaster-recovery restore.\n\n- Migration SHA-256: `" + result["static"]["migration_sha256"] + "`\n- Operational tables hashed: **" + str(len(OPERATIONAL)) + "**\n- Public FKs checked: **" + str(result["foreign_keys"]["constraints_checked"]) + "**\n- Evidence JSON: `review-evidence/stage-a-ai-auditor/rollback-proof-115.json`\n- Commit performed: **no**\n", encoding="utf-8")
    return result


def main() -> int:
    result = run()
    print(json.dumps({"PASS": result["passed"], "migration": 115, "migration_name": "beta_ai_auditor_foundation", "operational_tables_hashed": len(OPERATIONAL), "public_fks_checked": result["foreign_keys"]["constraints_checked"], "snapshot_vehicles": result["dealer_vehicle_count"], "evidence_json": str(OUT_JSON), "evidence_md": str(OUT_MD), "committed": False}, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())
