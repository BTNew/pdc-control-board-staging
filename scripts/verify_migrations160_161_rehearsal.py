#!/usr/bin/env python3
"""Rollback-only exact catalog/ACL/RLS rehearsal for Migrations 160 and 161."""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from scripts.pdc_staging_runtime import assert_staging_target
FILES = [
    ROOT / "supabase" / "staging_only" / "160_email_communication_board_actions.sql",
    ROOT / "supabase" / "staging_only" / "161_non_navision_jobcard_board_creation.sql",
]


def migration_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    text, begins = re.subn(r"(?im)^\s*begin;\s*$", "", text, count=1)
    text, commits = re.subn(r"(?im)^\s*commit;\s*$", "", text, count=1)
    if begins != 1 or commits != 1:
        raise AssertionError(f"{path.name}: outer transaction markers were not uniquely removed")
    return text


def derive_inventory(sql: str) -> dict[str, list[str]]:
    flags = re.I | re.S
    relations: set[str] = set()
    functions: set[str] = set()
    indexes: set[str] = set()
    triggers: set[str] = set()
    for pattern in (
        r"\bcreate\s+table\s+([a-z_][\w]*\.[a-z_][\w]*)",
        r"\balter\s+table\s+([a-z_][\w]*\.[a-z_][\w]*)",
        r"\b(?:grant|revoke)\b[^;]*?\bon\s+table\s+([a-z_][\w]*\.[a-z_][\w]*)",
        r"\bcreate\s+(?:unique\s+)?index\s+[a-z_][\w]*\s+on\s+([a-z_][\w]*\.[a-z_][\w]*)",
        r"\bcreate\s+trigger\s+[a-z_][\w]*[^;]*?\bon\s+([a-z_][\w]*\.[a-z_][\w]*)",
    ):
        relations.update(match.lower() for match in re.findall(pattern, sql, flags))
    functions.update(match.lower() for match in re.findall(r"\bcreate\s+(?:or\s+replace\s+)?function\s+([a-z_][\w]*\.[a-z_][\w]*)\s*\(", sql, flags))
    functions.update(match.lower() for match in re.findall(r"\b(?:grant|revoke)\b[^;]*?\bon\s+function\s+([a-z_][\w]*\.[a-z_][\w]*)\s*\(", sql, flags))
    functions.update(match.lower() for match in re.findall(r"\bcomment\s+on\s+function\s+([a-z_][\w]*\.[a-z_][\w]*)\s*\(", sql, flags))
    indexes.update(match.lower() for match in re.findall(r"\bcreate\s+(?:unique\s+)?index\s+([a-z_][\w]*)\s+on\s+", sql, flags))
    triggers.update(match.lower() for match in re.findall(r"\bcreate\s+trigger\s+([a-z_][\w]*)", sql, flags))
    versions = sorted(set(re.findall(r"schema_migrations\s*\([^)]*version[^)]*\)\s*values\s*\(\s*'([0-9]+)'", sql, flags)))
    return {
        "relations": sorted(relations),
        "functions": sorted(functions),
        "indexes": sorted(indexes),
        "triggers": sorted(triggers),
        "ledger_versions": versions,
    }


def merged_inventory() -> dict[str, list[str]]:
    merged = {key: set() for key in ("relations", "functions", "indexes", "triggers", "ledger_versions")}
    for path in FILES:
        current = derive_inventory(path.read_text(encoding="utf-8"))
        for key, values in current.items():
            merged[key].update(values)
    result = {key: sorted(values) for key, values in merged.items()}
    if result["ledger_versions"] != ["160", "161"]:
        raise AssertionError(f"migration ledger inventory drifted: {result['ledger_versions']}")
    return result


def json_section(cur: Any, sql: str, params: tuple[Any, ...]) -> Any:
    cur.execute(sql, params)
    value = cur.fetchone()[0]
    return json.loads(value) if value else []


def catalog_snapshot(cur: Any, inventory: dict[str, list[str]]) -> dict[str, Any]:
    relations = inventory["relations"]
    functions = inventory["functions"]
    index_names = inventory["indexes"]
    versions = inventory["ledger_versions"]
    result: dict[str, Any] = {}
    result["relations"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by identity),'[]'::jsonb)::text from (
       select n.nspname||'.'||c.relname identity,c.relkind,c.relpersistence,
        pg_get_userbyid(c.relowner) owner,coalesce(c.relacl::text,''::text) acl,
        c.relrowsecurity,c.relforcerowsecurity,obj_description(c.oid,'pg_class') comment
       from pg_class c join pg_namespace n on n.oid=c.relnamespace
       where n.nspname||'.'||c.relname=any(%s)
      ) x
    """, (relations,))
    result["columns"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by relation,attnum),'[]'::jsonb)::text from (
       select n.nspname||'.'||c.relname relation,a.attnum,a.attname,
        pg_catalog.format_type(a.atttypid,a.atttypmod) data_type,a.attnotnull,a.attidentity,a.attgenerated,
        coalesce(pg_get_expr(d.adbin,d.adrelid),''::text) default_expression,
        coalesce(a.attacl::text,''::text) acl,col_description(c.oid,a.attnum) comment
       from pg_class c join pg_namespace n on n.oid=c.relnamespace
       join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
       left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
       where n.nspname||'.'||c.relname=any(%s)
      ) x
    """, (relations,))
    result["constraints"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by relation,name),'[]'::jsonb)::text from (
       select n.nspname||'.'||r.relname relation,c.conname name,c.contype,c.condeferrable,c.condeferred,c.convalidated,
        pg_get_constraintdef(c.oid,true) definition,obj_description(c.oid,'pg_constraint') comment
       from pg_constraint c join pg_class r on r.oid=c.conrelid join pg_namespace n on n.oid=r.relnamespace
       where n.nspname||'.'||r.relname=any(%s)
      ) x
    """, (relations,))
    result["indexes"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by relation,name),'[]'::jsonb)::text from (
       select nt.nspname||'.'||t.relname relation,i.relname name,pg_get_indexdef(i.oid) definition,
        pg_get_userbyid(i.relowner) owner,coalesce(i.relacl::text,''::text) acl,obj_description(i.oid,'pg_class') comment
       from pg_index ix join pg_class i on i.oid=ix.indexrelid join pg_class t on t.oid=ix.indrelid
       join pg_namespace nt on nt.oid=t.relnamespace
       where nt.nspname||'.'||t.relname=any(%s) or i.relname=any(%s)
      ) x
    """, (relations, index_names))
    result["triggers"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by relation,name),'[]'::jsonb)::text from (
       select n.nspname||'.'||r.relname relation,t.tgname name,t.tgenabled,pg_get_triggerdef(t.oid,true) definition,
        obj_description(t.oid,'pg_trigger') comment
       from pg_trigger t join pg_class r on r.oid=t.tgrelid join pg_namespace n on n.oid=r.relnamespace
       where not t.tgisinternal and n.nspname||'.'||r.relname=any(%s)
      ) x
    """, (relations,))
    result["policies"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by relation,name),'[]'::jsonb)::text from (
       select n.nspname||'.'||r.relname relation,p.polname name,p.polpermissive,
        pg_get_expr(p.polqual,p.polrelid) using_expression,pg_get_expr(p.polwithcheck,p.polrelid) check_expression,
        array(select rolname from pg_roles where oid=any(p.polroles) order by rolname) roles
       from pg_policy p join pg_class r on r.oid=p.polrelid join pg_namespace n on n.oid=r.relnamespace
       where n.nspname||'.'||r.relname=any(%s)
      ) x
    """, (relations,))
    result["functions"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by identity),'[]'::jsonb)::text from (
       select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
        pg_get_functiondef(p.oid) definition,pg_get_userbyid(p.proowner) owner,coalesce(p.proacl::text,''::text) acl,
        coalesce(p.proconfig::text,''::text) configuration,p.prosecdef,p.proleakproof,p.provolatile,p.proparallel,
        obj_description(p.oid,'pg_proc') comment
       from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname||'.'||p.proname=any(%s)
      ) x
    """, (functions,))
    result["ledger"] = json_section(cur, """
      select coalesce(jsonb_agg(to_jsonb(x) order by version),'[]'::jsonb)::text from (
       select version,name,statements from supabase_migrations.schema_migrations where version=any(%s)
      ) x
    """, (versions,))
    return result


def fingerprint(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def main() -> int:
    dsn = os.getenv("PDC_STAGING_DIRECT_DATABASE_URL") or os.getenv("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=dsn)
    inventory = merged_inventory()
    digests = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in FILES}
    conn = psycopg2.connect(dsn)
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            if json_section(cur, "select to_jsonb(x)::text from (select project_ref from public.pdc_staging_environment_sentinel where singleton) x", ()) != {"project_ref": "cdsmnqxtyyoeoznmbidd"}:
                raise AssertionError("staging sentinel mismatch")
            cur.execute("select to_regclass('public.pdc_production_environment_sentinel') is not null")
            if cur.fetchone()[0]:
                raise AssertionError("production sentinel present")
            before = catalog_snapshot(cur, inventory)
            for path in FILES:
                cur.execute(migration_body(path))
            applied = catalog_snapshot(cur, inventory)
            if applied == before:
                raise AssertionError("migration produced no catalog delta")
        conn.rollback()
    finally:
        conn.close()

    fresh = psycopg2.connect(dsn)
    fresh.autocommit = False
    try:
        with fresh.cursor() as cur:
            after = catalog_snapshot(cur, inventory)
        fresh.rollback()
    finally:
        fresh.close()
    if after != before:
        changed = [key for key in sorted(before) if before[key] != after[key]]
        raise AssertionError(f"fresh-connection rollback catalog mismatch: {changed}")
    print(json.dumps({
        "ok": True,
        "mode": "rollback_rehearsal",
        "migrations": ["160", "161"],
        "sha256": digests,
        "mechanical_inventory": inventory,
        "inventory_coverage_complete": True,
        "catalog_sections": sorted(before),
        "before_sha256": fingerprint(before),
        "fresh_after_sha256": fingerprint(after),
        "fresh_connection_equality": True,
        "rollback_verified": True,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
