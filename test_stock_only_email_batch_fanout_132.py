from pathlib import Path

SQL = (Path(__file__).parent / "supabase" / "staging_only" / "132_stock_only_authenticated_email_batch_fanout.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()


def require(text: str) -> None:
    assert text.lower() in LOWER, text


def forbid(text: str) -> None:
    assert text.lower() not in LOWER, text


require("PDC_EMAIL_132_STAGING_SENTINEL_MISMATCH")
require("PDC_EMAIL_132_PREDECESSOR_131_REQUIRED")
require("pdc_monitor_stage_activation_writers")
require("for share")
require("contract_version',2")
require("backend_stock_not_found")
require("backend_stock_ambiguous")
require("operational_identity_conflict")
require("vin_conflict_non_authoritative")
require("protected_existing_lifecycle")
require("protected_or_conflicting_activation")
require("backend_canonical_identity_conflict")
require("backend_source_identity_conflict")
require("PDC_EMAIL_132_POSTCONDITION_FAILED")
require("identity_authority','unique_current_backend_stock")
require("vin_required',false")
require("booking_created',false")
require("pdc_authenticated_email_batch_receipts")
require("get_pdc_email_vehicle_location_snapshot")
require("v.id=any(r.vehicle_ids)")
require("update public.pdc_email_vehicle_revision")
require("grant execute on function public.import_pdc_authenticated_backend_batches")
require("to authenticated")

# Migration 132 deliberately bypasses the old trigger/reconciler path. VIN is a
# conflict guard only; it cannot select a canonical vehicle.
forbid("reconcile_navision_operational_record(")
forbid("insert into public.navision_board_activations")
forbid("update public.navision_board_activations")
forbid("v.vin_normalized=v_vin\n      union")

# Complete validation must precede all canonical writes.
assert LOWER.index("-- validate the complete fan-out before the first write") < LOWER.index("insert into public.vehicles")
assert LOWER.index("for v_index in 1..cardinality(v_stocks) loop") < LOWER.index("insert into public.pdc_authenticated_email_batch_receipts")
print("authenticated email stock-only batch fan-out Migration 132 contract: ok")
