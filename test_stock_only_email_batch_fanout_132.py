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
require("from public.vehicle_aliases a")
require("a.active")
require("a.alias_type_normalized='vin'")
require("a.normalized_alias_value=v_vin")
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
require("pg_advisory_xact_lock(hashtextextended('pdc-email-source:'||v_source_hash,0))")
require("pdc_email_single_receipt_source_guard")
require("pdc_email_batch_receipt_source_guard")
require("PDC_EMAIL_SOURCE_ALREADY_BATCH_CONSUMED")
require("PDC_EMAIL_SOURCE_ALREADY_SINGLE_CONSUMED")
require("revoke all on function public.import_pdc_authenticated_vehicle_email")
require("grant execute on function public.import_pdc_authenticated_backend_batches")
require("to authenticated")

# Migration 132 deliberately bypasses the old trigger/reconciler path. VIN is a
# conflict guard only; it cannot select a canonical vehicle.
forbid("reconcile_navision_operational_record(")
forbid("insert into public.navision_board_activations")
forbid("update public.navision_board_activations")
forbid("v.vin_normalized=v_vin\n      union")

# Alias-only Stock identity must satisfy the final postcondition without
# rewriting the vehicle's canonical Stock number.
assert LOWER.rindex("a.alias_type_normalized='stock_number'") < LOWER.index("pdc_email_132_postcondition_failed")
assert LOWER.rindex("a.normalized_alias_value=v_stock") < LOWER.index("pdc_email_132_postcondition_failed")

# Complete validation must precede all canonical writes, and the shared global
# Navision advisory lock must precede vehicle/alias table locks to match Admin Apply.
nav_lock = LOWER.index("pg_advisory_xact_lock(hashtextextended('navision-backend-store',0))")
table_lock = LOWER.index("lock table public.vehicles,public.vehicle_aliases")
assert nav_lock < table_lock
assert table_lock < LOWER.index("insert into public.vehicles")
assert LOWER.index("-- validate the complete fan-out before the first write") < LOWER.index("insert into public.vehicles")
assert LOWER.index("for v_index in 1..cardinality(v_stocks) loop") < LOWER.index("insert into public.pdc_authenticated_email_batch_receipts")
print("authenticated email stock-only batch fan-out Migration 132 contract: ok")
