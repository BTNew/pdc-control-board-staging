"""Hash every restored/public table for complete C6 unrelated-row and rollback proof."""
from __future__ import annotations
import argparse, hashlib, json, os, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import stage2b_c6_operational_rehearsal as c6

REVISION_TABLES = {"vehicle_lifecycle_resolver_revision", "vehicle_master_revision", "workshop_revision"}
ROLLBACK_TABLES = c6.ROLLBACK_TABLES

def row_hash(cur, schema, table, where="true", params=()):
    cur.execute(f'''select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text), '[]'::jsonb), count(*)
                    from "{schema}"."{table}" t where {where}''', params)
    rows, count = cur.fetchone()
    return {"count": count, "full_row_sha256": c6.canonical_sha(rows)}


def primary_key_columns(cur, schema, table):
    cur.execute("""select a.attname from pg_index i
                   join pg_class c on c.oid=i.indrelid
                   join pg_namespace n on n.oid=c.relnamespace
                   join unnest(i.indkey) with ordinality k(attnum,ord) on true
                   join pg_attribute a on a.attrelid=c.oid and a.attnum=k.attnum
                   where n.nspname=%s and c.relname=%s and i.indisprimary order by k.ord""", (schema, table))
    keys = [row[0] for row in cur.fetchall()]
    if not keys:
        raise c6.C6PilotRefusal(f"stable partition requires a primary key: {table}")
    return keys


def row_fingerprints(cur, schema, table, where="true", params=()):
    keys = primary_key_columns(cur, schema, table)
    key_sql = ",".join(f't."{key}"' for key in keys)
    cur.execute(f'''select jsonb_build_array({key_sql})::text,to_jsonb(t)
                    from "{schema}"."{table}" t where {where}''', params)
    return {key: c6.canonical_sha(row) for key, row in cur.fetchall()}


def keyset_sha256(keys):
    return hashlib.sha256(c6.canonical_json(sorted(keys)).encode("utf-8")).hexdigest()


def frozen_partition_baseline(all_rows, unrelated_rows, exclusion):
    if not set(unrelated_rows) <= set(all_rows):
        raise c6.C6PilotRefusal("unrelated partition is not a subset of the baseline population")
    dependent = set(all_rows) - set(unrelated_rows)
    return {
        "exclusion": exclusion,
        "baseline_all_count": len(all_rows),
        "baseline_dependent_count": len(dependent),
        "baseline_unrelated_count": len(unrelated_rows),
        "baseline_all_keyset_sha256": keyset_sha256(all_rows),
        "baseline_dependent_keyset_sha256": keyset_sha256(dependent),
        "baseline_unrelated_keyset_sha256": keyset_sha256(unrelated_rows),
        "baseline_unrelated_full_row_sha256": c6.canonical_sha(sorted(unrelated_rows.items())),
        "partition_reconciled": len(all_rows) == len(dependent) + len(unrelated_rows),
    }


def reconcile_frozen_partition(before_all, before_unrelated, after_all, after_unrelated=None):
    before_keys, unrelated_keys, after_keys = set(before_all), set(before_unrelated), set(after_all)
    after_unrelated_keys = set(after_all if after_unrelated is None else after_unrelated)
    missing = unrelated_keys - after_keys
    changed = {key for key in unrelated_keys & after_keys if before_unrelated[key] != after_all[key]}
    new = after_keys - before_keys
    new_unrelated = new & after_unrelated_keys
    unchanged = not missing and not changed and not new_unrelated
    return {
        "after_all_count": len(after_all),
        "after_all_keyset_sha256": keyset_sha256(after_all),
        "after_new_dependent_rows": len(new - new_unrelated),
        "frozen_unrelated_count": len(unrelated_keys),
        "frozen_unrelated_keyset_sha256": keyset_sha256(unrelated_keys),
        "frozen_unrelated_full_row_sha256": c6.canonical_sha(sorted((key, after_all[key]) for key in unrelated_keys if key in after_all)),
        "missing_frozen_unrelated_rows": len(missing),
        "changed_frozen_unrelated_rows": len(changed),
        "new_rows_outside_baseline_partition": len(new_unrelated),
        "stable_unrelated_rows_unchanged": unchanged,
    }


def hashing_contract():
    return {
        "algorithm": "sha256",
        "row_projection": "to_jsonb(complete_row)",
        "stable_order": "to_jsonb(complete_row)::text ascending",
        "aggregation": "jsonb_agg with empty-table []",
        "canonical_serialization": "UTF-8 JSON; keys sorted; separators comma/colon; datetime/UUID/decimal normalized by stage2b_c6 canonical_json",
        "comparison": "frozen baseline primary-key partitions; exact keyset, row count, and full-row SHA-256 reconciliation per table",
        "partition_stability": "dependent and unrelated primary-key sets are frozen before apply; mutable relationship fields cannot move rows across the comparison boundary",
        "selected_boundary": "selected pilot vehicle UUIDs, their dependent booking rows, four rehearsal participant role rows, and global revision singletons are explicitly categorized and excluded only where stated",
    }


def _normalize_schema_sql(value, schema):
    if value is None:
        return None
    value = str(value)
    for name in (schema, "public"):
        value = value.replace(f'"{name}".', '<schema>.').replace(f"{name}.", "<schema>.")
    return " ".join(value.split())


def _normalize_constraint_sql(value, schema):
    value = _normalize_schema_sql(value, schema)
    return re.sub(r"REFERENCES (?!(?:<schema>)\.)(\"?[a-zA-Z_][a-zA-Z0-9_]*\"?)",
                  r"REFERENCES <schema>.\1", value)


def schema_object_inventory(cur, schema, tables, restore_contract=False):
    cur.execute("""select table_name,column_name,ordinal_position,data_type,udt_schema,udt_name,is_nullable,
                          column_default,is_identity,identity_generation,is_generated,generation_expression
                   from information_schema.columns where table_schema=%s and table_name=any(%s)
                   order by table_name,ordinal_position""", (schema, tables))
    column_rows = [list(row) for row in cur.fetchall()]
    for row in column_rows:
        row[4] = "<schema>" if row[4] in {schema, "public"} else row[4]
        row[7] = _normalize_schema_sql(row[7], schema)
        row[11] = _normalize_schema_sql(row[11], schema)
        if restore_contract and schema == "public" and row[0] == "vehicle_notifications" and row[1] == "status":
            row[3], row[4], row[5] = "text", "pg_catalog", "text"
    cur.execute("""select c.relname,con.conname,con.contype,con.convalidated,pg_get_constraintdef(con.oid,true),
                          rn.nspname,rc.relname
                   from pg_constraint con join pg_class c on c.oid=con.conrelid
                   join pg_namespace n on n.oid=c.relnamespace
                   left join pg_class rc on rc.oid=con.confrelid
                   left join pg_namespace rn on rn.oid=rc.relnamespace
                   where n.nspname=%s and c.relname=any(%s)
                   order by c.relname,con.conname""", (schema, tables))
    raw_constraints = cur.fetchall()
    constraint_rows = [[*row[:4], _normalize_constraint_sql(row[4], schema)] for row in raw_constraints
                       if not restore_contract or row[2] != "f" or (row[5] == schema and row[6] in tables)
                       or (schema == "public" and row[5] == "public" and row[6] in tables)]
    cur.execute("""select tablename,indexname,indexdef from pg_indexes
                   where schemaname=%s and tablename=any(%s) order by tablename,indexname""", (schema, tables))
    raw_indexes = cur.fetchall()
    index_rows = []
    for table_name, index_name, index_def in raw_indexes:
        if restore_contract and schema == "public" and index_name == "vehicle_notifications_status_idx":
            continue
        semantic_def = re.sub(r"^(CREATE (?:UNIQUE )?INDEX) \S+ ON ", r"\1 ON ",
                              _normalize_schema_sql(index_def, schema))
        index_rows.append([table_name, semantic_def])
    index_rows.sort()
    cur.execute("""select sequence_name,data_type,start_value,minimum_value,maximum_value,increment,cycle_option
                   from information_schema.sequences where sequence_schema=%s order by sequence_name""", (schema,))
    sequence_rows = [list(row) for row in cur.fetchall()]
    foreign_keys = [row for row in constraint_rows if row[2] == "f"]
    return {
        "columns": {"count": len(column_rows), "sha256": c6.canonical_sha(column_rows)},
        "constraints": {"count": len(constraint_rows), "sha256": c6.canonical_sha(constraint_rows)},
        "foreign_keys": {"discovered": len(foreign_keys), "validated": sum(row[3] is True for row in foreign_keys), "sha256": c6.canonical_sha(foreign_keys)},
        "indexes": {"count": len(index_rows), "sha256": c6.canonical_sha(index_rows)},
        "sequences": {"count": len(sequence_rows), "sha256": c6.canonical_sha(sequence_rows)},
    }


def public_function_inventory(cur):
    cur.execute("""select p.proname,pg_get_function_identity_arguments(p.oid),p.prokind,
                          pg_get_function_result(p.oid),pg_get_functiondef(p.oid)
                   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' order by p.proname,pg_get_function_identity_arguments(p.oid),p.prokind""")
    rows = [[row[0], row[1], row[2], row[3], _normalize_schema_sql(row[4], "public")] for row in cur.fetchall()]
    return {"scope": "required operational functions remain in public and are not duplicated into data-only restore schemas",
            "count": len(rows), "sha256": c6.canonical_sha(rows)}


def foreign_key_scope(cur, tables):
    cur.execute("""select rn.nspname,rc.relname
                   from pg_constraint con join pg_class c on c.oid=con.conrelid
                   join pg_namespace n on n.oid=c.relnamespace
                   join pg_class rc on rc.oid=con.confrelid
                   join pg_namespace rn on rn.oid=rc.relnamespace
                   where n.nspname='public' and c.relname=any(%s) and con.contype='f'""", (tables,))
    rows = cur.fetchall()
    internal = [row for row in rows if row[0] == "public" and row[1] in tables]
    external_auth = [row for row in rows if row[0] == "auth" and row[1] == "users"]
    return {"public_total": len(rows), "payload_internal_restorable": len(internal),
            "external_auth_not_in_backup": len(external_auth), "restored_and_validated": len(internal)}

def columns(cur, schema, table):
    cur.execute("select column_name from information_schema.columns where table_schema=%s and table_name=%s", (schema, table))
    return {r[0] for r in cur.fetchall()}

def predicate(table, cols, selected_ids, booking_ids, participant_ids):
    if table in REVISION_TABLES:
        return "false", (), "global_revision_row"
    if table == "vehicles":
        return "not (id=any(%s::uuid[]))", (selected_ids,), "selected_vehicle_id"
    if table == "pdc_user_roles":
        return "not (auth_user_id=any(%s::uuid[]))", (participant_ids,), "rehearsal_participant_role"
    if table == "audit_events" and {"vehicle_id", "row_id", "before_data", "after_data"}.issubset(cols):
        return (
            "(vehicle_id is null or not (vehicle_id=any(%s::uuid[]))) and "
            "(row_id is null or not (row_id=any(%s::uuid[]))) and "
            "(before_data->>'vehicle_id' is null or not (before_data->>'vehicle_id'=any(%s::text[]))) and "
            "(after_data->>'vehicle_id' is null or not (after_data->>'vehicle_id'=any(%s::text[])))",
            (selected_ids, selected_ids, selected_ids, selected_ids), "selected_vehicle_audit_dependency")
    if table == "vehicle_master_history" and {"vehicle_id", "entity_id"}.issubset(cols):
        return ("(vehicle_id is null or not (vehicle_id=any(%s::uuid[]))) and "
                "(entity_id is null or not (entity_id=any(%s::uuid[])))",
                (selected_ids, selected_ids), "selected_vehicle_or_entity_id")
    if "vehicle_id" in cols:
        return "vehicle_id is null or not (vehicle_id=any(%s::uuid[]))", (selected_ids,), "selected_vehicle_id"
    if table in {"workshop_booking_history", "workshop_booking_assignments"} and "booking_id" in cols:
        return "not (booking_id=any(%s::uuid[]))", (booking_ids,), "selected_booking_id"
    return "true", (), "none"

def inventory(cur, schema):
    cur.execute("select table_name from information_schema.tables where table_schema=%s and table_type='BASE TABLE' order by table_name", (schema,))
    return [r[0] for r in cur.fetchall()]

def selected_context(cur, schema, participant_emails):
    cur.execute(f"select id::text from \"{schema}\".vehicles where source_system=%s and source_batch_id like 'C6-REAL-PILOT-%%' order by id", (c6.SOURCE_SYSTEM,))
    selected_ids = [r[0] for r in cur.fetchall()]
    if len(selected_ids) != 25:
        raise c6.C6PilotRefusal("full-schema verifier did not find exactly 25 selected vehicles")
    cur.execute(f"select id::text from \"{schema}\".workshop_bookings where vehicle_id=any(%s::uuid[]) order by id", (selected_ids,))
    booking_ids = [r[0] for r in cur.fetchall()]
    cur.execute("select id::text from auth.users where lower(email)=any(%s::text[])", ([e.lower() for e in participant_emails],))
    participant_ids = [r[0] for r in cur.fetchall()]
    if len(participant_ids) != 4:
        raise c6.C6PilotRefusal("full-schema verifier did not resolve four participant identities")
    return selected_ids, booking_ids, participant_ids

def compare_public(conn, restored_schema, output):
    if not re.fullmatch(r"c6_full_audit_[0-9a-f]{8}", restored_schema):
        raise c6.C6PilotRefusal("invalid full-schema audit schema")
    cur = conn.cursor()
    participant_emails = [os.environ[k] for k in ("PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_CONTROLLER_A_EMAIL", "PDC_STAGING_CONTROLLER_B_EMAIL", "PDC_STAGING_VIEWER_EMAIL")]
    selected_ids, _public_booking_seed, participant_ids = selected_context(cur, "public", participant_emails)
    cur.execute(f"select id::text from \"{restored_schema}\".workshop_bookings where vehicle_id=any(%s::uuid[]) order by id", (selected_ids,))
    restored_booking_ids = [r[0] for r in cur.fetchall()]
    cur.execute("select id::text from public.workshop_bookings where vehicle_id=any(%s::uuid[]) order by id", (selected_ids,))
    public_booking_ids = [r[0] for r in cur.fetchall()]
    tables = inventory(cur, restored_schema)
    if not set(tables) <= set(inventory(cur, "public")):
        raise c6.C6PilotRefusal("restored table inventory is not a subset of public")
    results = {}
    restored_objects = schema_object_inventory(cur, restored_schema, tables, restore_contract=True)
    public_objects = schema_object_inventory(cur, "public", tables, restore_contract=True)
    required_public_functions = public_function_inventory(cur)
    fk_scope = foreign_key_scope(cur, tables)
    schema_objects_equal = restored_objects == public_objects
    try:
        for table in tables:
            cols = columns(cur, restored_schema, table)
            before_where, before_params, category = predicate(table, cols, selected_ids, restored_booking_ids, participant_ids)
            baseline_all = row_fingerprints(cur, restored_schema, table)
            baseline_unrelated = row_fingerprints(cur, restored_schema, table, before_where, before_params)
            public_all = row_fingerprints(cur, "public", table)
            after_where, after_params, _ = predicate(table, columns(cur, "public", table), selected_ids, public_booking_ids, participant_ids)
            public_unrelated = row_fingerprints(cur, "public", table, after_where, after_params)
            baseline = frozen_partition_baseline(baseline_all, baseline_unrelated, category)
            reconciliation = reconcile_frozen_partition(baseline_all, baseline_unrelated, public_all, public_unrelated)
            results[table] = {**baseline, **reconciliation, "unchanged": reconciliation["stable_unrelated_rows_unchanged"]}
        passed = len(tables) == 46 and all(v["unchanged"] and v["partition_reconciled"] for v in results.values()) and schema_objects_equal
        report = {"schema": "pdc.stage2b.c6-full-schema-unrelated/v1", "exact_staging_project_ref": c6.STAGING_REF,
                  "table_count": len(tables), "table_inventory": tables, "selected_vehicle_count": 25,
                  "hashing_method": hashing_contract(), "all_unrelated_full_row_hashes_unchanged": all(v["unchanged"] for v in results.values()),
                  "schema_objects_equal": schema_objects_equal, "restored_schema_objects": restored_objects,
                  "public_schema_objects": public_objects, "required_public_functions": required_public_functions,
                  "foreign_key_scope": fk_scope,
                  "intentional_restore_safety_transform": {"table": "vehicle_notifications", "status_column": "enum widened to text and forced to restored_disabled", "omitted_index": "vehicle_notifications_status_idx", "reason": "prevent notification replay"},
                  "all_checks_passed": passed, "tables": results, "restored_schema_removed": True}
        if not passed:
            mismatched = {table: {
                "missing": row["missing_frozen_unrelated_rows"],
                "changed": row["changed_frozen_unrelated_rows"],
                "new_unrelated": row["new_rows_outside_baseline_partition"],
                "new_dependent": row["after_new_dependent_rows"],
            } for table, row in results.items() if not row["unchanged"] or not row["partition_reconciled"]}
            raise c6.C6PilotRefusal(f"complete full-schema unrelated-row hashes differ: {c6.canonical_json(mismatched)}")
        Path(output).write_text(c6.canonical_json(report) + "\n", encoding="utf-8")
        return report
    finally:
        cur.execute(f'drop schema if exists "{restored_schema}" cascade')
        conn.commit()

def rollback(conn, restored_schema, output):
    if not re.fullmatch(r"c6_full_rollback_audit_[0-9a-f]{8}", restored_schema):
        raise c6.C6PilotRefusal("invalid full-schema rollback audit schema")
    cur = conn.cursor()
    participant_emails = [os.environ[k] for k in ("PDC_STAGING_ADMIN_EMAIL", "PDC_STAGING_CONTROLLER_A_EMAIL", "PDC_STAGING_CONTROLLER_B_EMAIL", "PDC_STAGING_VIEWER_EMAIL")]
    selected_ids, booking_ids, participant_ids = selected_context(cur, restored_schema, participant_emails)
    tables = inventory(cur, restored_schema)
    if len(tables) != 46:
        raise c6.C6PilotRefusal("isolated rollback inventory is not exactly 46 tables")
    full_before = {table: row_hash(cur, restored_schema, table) for table in tables}
    restored_objects_before = schema_object_inventory(cur, restored_schema, tables, restore_contract=True)
    public_objects = schema_object_inventory(cur, "public", tables, restore_contract=True)
    required_public_functions_before = public_function_inventory(cur)
    fk_scope = foreign_key_scope(cur, tables)
    if (restored_objects_before != public_objects
            or restored_objects_before["foreign_keys"]["discovered"] != 72
            or restored_objects_before["foreign_keys"]["validated"] != 72):
        raise c6.C6PilotRefusal("isolated rollback schema objects or 72/72 foreign keys are incomplete")
    before, after, frozen = {}, {}, {}
    try:
        for table in tables:
            where, params, category = predicate(table, columns(cur, restored_schema, table), selected_ids, booking_ids, participant_ids)
            baseline_all = row_fingerprints(cur, restored_schema, table)
            baseline_unrelated = row_fingerprints(cur, restored_schema, table, where, params)
            frozen[table] = (baseline_all, baseline_unrelated)
            before[table] = frozen_partition_baseline(baseline_all, baseline_unrelated, category)
        cur.execute(f'select revision from "{restored_schema}".vehicle_master_revision where singleton')
        row = cur.fetchone()
        if row is None: raise c6.C6PilotRefusal("restored vehicle-master revision is missing")
        revision = row[0]
        cur.execute(f'select revision from "{restored_schema}".vehicle_lifecycle_resolver_revision where singleton')
        row = cur.fetchone()
        if row is None: raise c6.C6PilotRefusal("restored resolver revision is missing")
        resolver_revision = row[0]
        resolver_advance = c6._prove_independent_revision_advance_refusal(
            cur, restored_schema, "lifecycle_resolver", resolver_revision)
        resolver_stale_refused = resolver_advance["saved_rollback_refused_after_advance"]
        c6._lock_restored_resolver_revision(cur, restored_schema, resolver_revision)
        vehicle_master_advance = c6._prove_independent_revision_advance_refusal(
            cur, restored_schema, "vehicle_master", revision)
        stale_refused = vehicle_master_advance["saved_rollback_refused_after_advance"]
        c6._lock_restored_vehicle_master_revision(cur, restored_schema, revision)
        predicates = {
            "vehicles": ("id=any(%s::uuid[])", (selected_ids,)),
            "vehicle_aliases": ("vehicle_id=any(%s::uuid[])", (selected_ids,)),
            "vehicle_master_source_records": ("vehicle_id=any(%s::uuid[])", (selected_ids,)),
            "vehicle_master_operation_receipts": ("vehicle_id=any(%s::uuid[])", (selected_ids,)),
            "vehicle_master_history": ("vehicle_id=any(%s::uuid[]) or entity_id=any(%s::uuid[])", (selected_ids, selected_ids)),
            "audit_events": ("vehicle_id=any(%s::uuid[]) and metadata->>'stage'='stage2b_029'", (selected_ids,)),
        }
        deleted = {}
        for table in ("audit_events", "vehicle_master_history", "vehicle_master_operation_receipts", "vehicle_master_source_records", "vehicle_aliases", "vehicles"):
            where, params = predicates[table]; cur.execute(f'delete from "{restored_schema}"."{table}" where {where}', params); deleted[table] = cur.rowcount
        cur.execute("set constraints all immediate")
        for table in tables:
            baseline_all, baseline_unrelated = frozen[table]
            current_all = row_fingerprints(cur, restored_schema, table)
            after[table] = reconcile_frozen_partition(baseline_all, baseline_unrelated, current_all)
        full_after = {table: row_hash(cur, restored_schema, table) for table in tables}
        restored_objects_after = schema_object_inventory(cur, restored_schema, tables, restore_contract=True)
        required_public_functions_after = public_function_inventory(cur)
        unchanged = all(before[t]["partition_reconciled"] and after[t]["stable_unrelated_rows_unchanged"] for t in tables)
        schema_objects_unchanged = restored_objects_before == restored_objects_after == public_objects
        functions_unchanged = required_public_functions_before == required_public_functions_after
        for table, (where, params) in predicates.items():
            cur.execute(f'select count(*) from "{restored_schema}"."{table}" where {where}', params)
            if cur.fetchone()[0] != 0: raise c6.C6PilotRefusal("selected rollback residue remains")
        final_resolver_revision = c6._lock_restored_resolver_revision(cur, restored_schema, resolver_revision)
        final_vehicle_master_revision = c6._lock_restored_vehicle_master_revision(cur, restored_schema, revision)
        report = {"schema": "pdc.stage2b.c6-full-schema-rollback/v1", "table_count": len(tables), "table_inventory": tables,
                  "selected_vehicle_count": 25, "hashing_method": hashing_contract(),
                  "full_tables_before": full_before, "full_tables_after": full_after,
                  "exact_revision_lock": revision, "stale_revision_attempted": revision + 1, "stale_revision_database_query_executed": True,
                  "stale_revision_refused": stale_refused, "deleted_selected_rows": deleted,
                  "resolver_revision_lock": resolver_revision, "resolver_stale_revision_attempted": resolver_revision + 1,
                  "resolver_stale_revision_database_query_executed": True, "resolver_stale_revision_refused": resolver_stale_refused,
                  "resolver_independent_advance_test": resolver_advance,
                  "vehicle_master_independent_advance_test": vehicle_master_advance,
                  "revisions_unchanged_through_apply": final_resolver_revision == resolver_revision and final_vehicle_master_revision == revision,
                  "all_unrelated_full_row_hashes_unchanged": unchanged, "before": before, "after": after,
                  "restored_schema_objects_before": restored_objects_before, "restored_schema_objects_after": restored_objects_after,
                  "public_schema_objects": public_objects, "schema_objects_equal_and_unchanged": schema_objects_unchanged,
                  "required_public_functions_before": required_public_functions_before,
                  "required_public_functions_after": required_public_functions_after,
                  "required_public_functions_unchanged": functions_unchanged,
                  "foreign_keys_discovered": restored_objects_before["foreign_keys"]["discovered"],
                  "foreign_keys_validated": restored_objects_before["foreign_keys"]["validated"],
                  "foreign_key_scope": fk_scope,
                  "intentional_restore_safety_transform": {"table": "vehicle_notifications", "status_column": "enum widened to text and forced to restored_disabled", "omitted_index": "vehicle_notifications_status_idx", "reason": "prevent notification replay"},
                  "temporary_schema_removed": True, "public_rows_changed": 0,
                  "all_checks_passed": unchanged and schema_objects_unchanged and functions_unchanged}
        if not report["all_checks_passed"]:
            mismatched_tables = [table for table in tables
                                 if not before[table]["partition_reconciled"] or not after[table]["stable_unrelated_rows_unchanged"]]
            raise c6.C6PilotRefusal(
                "full-schema rollback equivalence failed: "
                f"tables={mismatched_tables}, schema_objects={schema_objects_unchanged}, functions={functions_unchanged}, "
                f"audit_before={before.get('audit_events', {}).get('baseline_unrelated_count')}, "
                f"audit_after={after.get('audit_events', {}).get('frozen_unrelated_count')}")
        conn.commit(); Path(output).write_text(c6.canonical_json(report) + "\n", encoding="utf-8"); return report
    finally:
        conn.rollback(); cur = conn.cursor()
        cur.execute(f'drop schema if exists "{restored_schema}" cascade'); conn.commit()

def main():
    p=argparse.ArgumentParser(); p.add_argument('--mode',choices=('compare-public','rollback'),required=True); p.add_argument('--restored-schema',required=True); p.add_argument('--output',required=True); a=p.parse_args()
    url=os.environ.get('PDC_STAGING_DATABASE_URL',''); conn=c6._connect_guarded(url)
    try: report=compare_public(conn,a.restored_schema,a.output) if a.mode=='compare-public' else rollback(conn,a.restored_schema,a.output)
    finally: conn.close()
    print(c6.canonical_json({k:report[k] for k in report if k not in {'tables','before','after'}}))
if __name__=='__main__': main()
