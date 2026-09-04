from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE.parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from inspect_pdc14_staging import STAGING_REF, management_query, supabase_access_token

PRODUCTION_REF = "vjdtsswhroyguxyfjdkt"
PREFIX = "QA-OVERNIGHT-20260904"
ACTOR = "[REDACTED_UUID_efc9f9ee19]"


def quoted(value: str) -> str:
    return '"' + value.replace('"', '""') + '"'


def scan_rows(table_rows: list[dict], predicate: str) -> list[dict]:
    clauses = []
    for row in table_rows:
        schema, table = row["table_schema"], row["table_name"]
        label = f"{schema}.{table}".replace("'", "''")
        relation = f"{quoted(schema)}.{quoted(table)}"
        clauses.append(f"select '{label}' relation,count(*)::bigint count from {relation} t where {predicate}")
    if not clauses:
        return []
    return management_query(" union all ".join(clauses))


def advisor(kind: str) -> dict:
    request = Request(
        f"https://api.supabase.com/v1/projects/{STAGING_REF}/advisors/{kind}?lint_type=sql",
        headers={"Authorization": f"Bearer {supabase_access_token()}", "Accept": "application/json", "User-Agent": "SupabaseCLI/2.116.0"},
    )
    with urlopen(request, timeout=90) as response:
        payload = json.loads(response.read().decode())
    lints = payload.get("lints", []) if isinstance(payload, dict) else []
    levels: dict[str, int] = {}
    for lint in lints:
        level = str(lint.get("level") or "UNKNOWN").upper()
        levels[level] = levels.get(level, 0) + 1
    return {"total": len(lints), "levels": levels, "lints": lints}


def main() -> int:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("refusing non-STAGING target")
    tables = management_query("""
select table_schema,table_name
from information_schema.tables
where table_type='BASE TABLE' and table_schema in ('public','auth','storage')
order by table_schema,table_name
""")
    tagged = scan_rows(tables, f"row_to_json(t)::text ilike '%{PREFIX}%'")
    tagged = [row for row in tagged if row["count"]]
    actor_rows = scan_rows(tables, f"row_to_json(t)::text ilike '%{ACTOR}%'")
    actor_rows = [row for row in actor_rows if row["count"]]
    vehicle_tables = management_query("""
select distinct c.table_schema,c.table_name
from information_schema.columns c
join information_schema.tables t using(table_schema,table_name)
where t.table_type='BASE TABLE' and c.table_schema='public' and c.column_name='vehicle_id'
order by c.table_schema,c.table_name
""")
    orphan_rows = scan_rows(
        vehicle_tables,
        f"t.vehicle_id is not null and not exists(select 1 from public.vehicles v where v.id=t.vehicle_id) and (row_to_json(t)::text ilike '%{PREFIX}%' or row_to_json(t)::text ilike '%{ACTOR}%')",
    )
    orphan_rows = [row for row in orphan_rows if row["count"]]
    state = management_query("""
select jsonb_build_object(
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'staging_sentinel_count',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'vehicle_count',(select count(*) from public.vehicles),
  'active_vehicle_count',(select count(*) from public.vehicles where deleted_at is null and lifecycle_state='active'),
  'controls',(select jsonb_object_agg(stock_number,jsonb_build_object(
      'id',id,'version',version,'updated_at',updated_at,'current_location',current_location,
      'lifecycle_state',lifecycle_state,'vin',vin,'registration',registration,'job_card_number',job_card_number,
      'customer_name',customer_name,
      'work_items',(select count(*) from public.vehicle_work_items w where w.vehicle_id=v.id),
      'bookings',(select count(*) from public.workshop_bookings b where b.vehicle_id=v.id),
      'history_rows',(select count(*) from public.pdc_vehicle_lifecycle_history_events_82000 h where h.vehicle_id=v.id)
    )) from public.vehicles v where stock_number in ('[REDACTED_STOCK_A]','[REDACTED_STOCK_B]')),
  'snapshot_function',(select jsonb_build_object('provolatile',provolatile,'authenticated_execute',has_function_privilege('authenticated',oid,'execute'),'anon_execute',has_function_privilege('anon',oid,'execute'),'service_role_execute',has_function_privilege('service_role',oid,'execute')) from pg_proc where oid=to_regprocedure('public.pdc_admin_archived_vehicle_snapshot(uuid,integer)'))
) state
""")[0]["state"]
    security = advisor("security")
    performance = advisor("performance")
    cleanup = {
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "project_ref": STAGING_REF,
        "prefix": PREFIX,
        "synthetic_actor_id": ACTOR,
        "tagged_rows": tagged,
        "tagged_row_total": sum(row["count"] for row in tagged),
        "actor_rows": actor_rows,
        "actor_row_total": sum(row["count"] for row in actor_rows),
        "orphan_vehicle_references": orphan_rows,
        "orphan_vehicle_reference_total": sum(row["count"] for row in orphan_rows),
        "database": state,
        "production_contacted": False,
        "production_mutated": False,
    }
    advisors = {
        "verified_at": cleanup["verified_at"],
        "project_ref": STAGING_REF,
        "security": security,
        "performance": performance,
        "production_contacted": False,
    }
    (HERE / "fresh-cleanup-and-controls.json").write_text(json.dumps(cleanup, indent=2, default=str) + "\n", encoding="utf-8")
    (HERE / "fresh-advisors.json").write_text(json.dumps(advisors, indent=2, default=str) + "\n", encoding="utf-8")
    expected_controls = {"[REDACTED_STOCK_A]", "[REDACTED_STOCK_B]"}
    controls = state.get("controls") or {}
    ok = (
        state["head"] == ["20260905010200", "archived_snapshot_volatility_repair"]
        and state["staging_sentinel_count"] == 1
        and state["production_sentinel_present"] is False
        and cleanup["tagged_row_total"] == 0
        and cleanup["actor_row_total"] == 0
        and cleanup["orphan_vehicle_reference_total"] == 0
        and set(controls) == expected_controls
        and state["snapshot_function"] == {"provolatile": "v", "authenticated_execute": True, "anon_execute": False, "service_role_execute": False}
    )
    print(json.dumps({"ok": ok, "state": state, "tagged_row_total": cleanup["tagged_row_total"], "actor_row_total": cleanup["actor_row_total"], "orphan_vehicle_reference_total": cleanup["orphan_vehicle_reference_total"], "advisor_totals": {"security": {"total": security["total"], "levels": security["levels"]}, "performance": {"total": performance["total"], "levels": performance["levels"]}}, "production_contacted": False}, indent=2, default=str))
    return 0 if ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
