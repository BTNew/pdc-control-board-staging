"""Record the acceptance-closure staging baseline without mutation."""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import subprocess
import urllib.request

from pdc_staging_management_migration import STAGING_REF, _post
from hermes_overnight_scenarios_002_003_lifecycle import env_values, request_json

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "_acceptance_closure_evidence" / "baseline.json"
STAGING_BASE = "https://btnew.github.io/pdc-control-board-staging/"


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def main() -> None:
    if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
        raise RuntimeError("PDC_ACCEPTANCE_STAGING_REF_MISMATCH")
    sql = """SET TRANSACTION READ ONLY;
with protected as materialized(
 select v.id from public.vehicles v where not exists(
  select 1 from public.pdc_overnight_synthetic_fleet_registry_363 r where r.vehicle_id=v.id
 )
), material as (
 select 'vehicles' relation,to_jsonb(v) row_data from public.vehicles v join protected p on p.id=v.id
 union all select 'vehicle_work_items',to_jsonb(x) from public.vehicle_work_items x join protected p on p.id=x.vehicle_id
 union all select 'workshop_bookings',to_jsonb(x) from public.workshop_bookings x join protected p on p.id=x.vehicle_id
 union all select 'workshop_booking_assignments',to_jsonb(a) from public.workshop_booking_assignments a join public.workshop_bookings b on b.id=a.booking_id join protected p on p.id=b.vehicle_id
 union all select 'workshop_booking_history',to_jsonb(h) from public.workshop_booking_history h join public.workshop_bookings b on b.id=h.booking_id join protected p on p.id=b.vehicle_id
 union all select 'workshop_parts_overrides',to_jsonb(x) from public.workshop_parts_overrides x join protected p on p.id=x.vehicle_id
 union all select 'vehicle_parts_updates',to_jsonb(x) from public.vehicle_parts_updates x join protected p on p.id=x.vehicle_id
 union all select 'pdc_sublet_booking_instances',to_jsonb(x) from public.pdc_sublet_booking_instances x join protected p on p.id=x.vehicle_id
 union all select 'pdc_sublet_booking_instance_history',to_jsonb(x) from public.pdc_sublet_booking_instance_history x join protected p on p.id=x.vehicle_id
 union all select 'vehicle_movements',to_jsonb(x) from public.vehicle_movements x join protected p on p.id=x.vehicle_id
 union all select 'audit_events',to_jsonb(x) from public.audit_events x join protected p on p.id=x.vehicle_id
), protected_digest as (
 select jsonb_build_object('rows',count(*),'sha256',encode(extensions.digest(convert_to(
  coalesce(jsonb_agg(jsonb_build_object('relation',relation,'row',row_data) order by relation,row_data::text),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')) value
 from material
)
select jsonb_build_object(
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'staging_sentinel_rows',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
 'production_sentinel_absent',to_regclass('public.pdc_production_environment_sentinel') is null,
 'migration_head',(select jsonb_build_object('version',version,'name',name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version desc limit 1),
 'monitor_status',(select running_status from public.pdc_email_monitor_status where singleton),
 'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
 'active_activation_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
 'vehicle_total',(select count(*) from public.vehicles),
 'synthetic_vehicle_total',(select count(*) from public.vehicles where stock_number like 'HERMES-TEST%'),
 'outbound_notification_rows',(select count(*) from public.vehicle_notifications),
 'pending_outbound_notifications',(select count(*) from public.vehicle_notifications where status::text in('pending','retry','queued')),
 'management_visible_protected_state',(select value from protected_digest),
 'duplicate_stocks',(select count(*) from (select stock_number from public.vehicles where deleted_at is null group by stock_number having count(*)>1) d),
 'duplicate_receipt_ids',(select count(*) from (select receipt_id from public.pdc_overnight_synthetic_mutation_receipts_365 group by receipt_id having count(*)>1) d),
 'duplicate_actor_idempotency',(select count(*) from (select actor_id,idempotency_key from public.pdc_overnight_synthetic_mutation_receipts_365 group by actor_id,idempotency_key having count(*)>1) d)
) evidence;"""
    database = _post(f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only", sql)[0]["evidence"]
    environment = env_values()
    rest_base = environment["PDC_STAGING_SUPABASE_URL"].rstrip("/")
    anon_key = environment["PDC_STAGING_ANON_KEY"]
    if environment.get("PDC_STAGING_PROJECT_REF") != STAGING_REF or STAGING_REF not in rest_base:
        raise RuntimeError("PDC_ACCEPTANCE_AUTH_TARGET_MISMATCH")
    auth_status, auth = request_json(
        rest_base + "/auth/v1/token?grant_type=password",
        "POST",
        {"apikey": anon_key, "Content-Type": "application/json"},
        {"email": environment["PDC_STAGING_ADMIN2_EMAIL"], "password": environment["PDC_STAGING_ADMIN2_PASSWORD"]},
    )
    if auth_status != 200:
        raise RuntimeError("PDC_ACCEPTANCE_STAGING_AUTH_FAILED")
    headers = {"apikey": anon_key, "Authorization": "Bearer " + auth["access_token"], "Content-Type": "application/json"}
    state_status, state = request_json(
        rest_base + "/rest/v1/rpc/read_pdc_hermes_test_mutation_state_365",
        "POST",
        headers,
        {"p_run_id": "HERMES-TEST-RUN-20260824", "p_vehicle_id": None},
    )
    if state_status != 200 or state.get("ok") is not True:
        raise RuntimeError("PDC_ACCEPTANCE_AUTHORITATIVE_STATE_READ_FAILED")
    database["protected_state"] = state["protected_state"]
    database["authoritative_synthetic_vehicle_total"] = len(state["vehicles"])
    if not (
        database["project_ref"] == STAGING_REF
        and database["staging_sentinel_rows"] == 1
        and database["production_sentinel_absent"]
        and database["monitor_status"] == "stopped"
        and database["active_mailboxes"] == 0
        and database["active_activation_writers"] == 0
        and database["outbound_notification_rows"] == 0
        and database["pending_outbound_notifications"] == 0
        and database["vehicle_total"] == 173
        and database["synthetic_vehicle_total"] == 20
        and database["authoritative_synthetic_vehicle_total"] == 20
        and database["protected_state"] == {
            "rows": 1413,
            "sha256": "28476c8fac93aa03707b20a84b4b836b4268c96fa6710bf1238f0f6ebb265f11",
        }
    ):
        raise RuntimeError("PDC_ACCEPTANCE_BASELINE_CONTAINMENT_MISMATCH")
    with urllib.request.urlopen(STAGING_BASE + "?acceptance-baseline=1", timeout=30) as response:
        html = response.read().decode("utf-8", "replace")
    if "PDC Control Board — STAGING" not in html:
        raise RuntimeError("PDC_ACCEPTANCE_STAGING_PAGE_IDENTITY_MISMATCH")
    latest_build = subprocess.check_output(
        ["gh", "api", "repos/BTNew/pdc-control-board-staging/pages/builds/latest"], text=True
    )
    document = {
        "schema": "pdc-acceptance-closure-baseline-v1",
        "recorded_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "starting_commit": git("rev-parse", "HEAD"),
        "starting_tree": git("rev-parse", "HEAD^{tree}"),
        "branch": git("branch", "--show-current"),
        "staging_repository": "https://github.com/BTNew/pdc-control-board-staging.git",
        "staging_website": STAGING_BASE,
        "website_identity": "PDC Control Board — STAGING",
        "pages_build": json.loads(latest_build),
        "database": database,
        "production_contacted": False,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(document, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps({
        "recorded_at_utc": document["recorded_at_utc"],
        "starting_commit": document["starting_commit"],
        "starting_tree": document["starting_tree"],
        "branch": document["branch"],
        "pages_commit": document["pages_build"].get("commit"),
        "pages_status": document["pages_build"].get("status"),
        "migration_head": database["migration_head"],
        "protected_state": database["protected_state"],
        "vehicles": database["vehicle_total"],
        "synthetic": database["synthetic_vehicle_total"],
        "notifications": database["outbound_notification_rows"],
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
