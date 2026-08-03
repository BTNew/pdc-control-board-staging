#!/usr/bin/env python3
"""Static contract for staging-only authenticated Back End batch fan-out."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SQL = (ROOT / "supabase" / "staging_only" / "130_authenticated_email_backend_batch_fanout.sql").read_text(encoding="utf-8")
LOWER = SQL.lower()

for required in (
    "PDC_EMAIL_130_STAGING_SENTINEL_MISMATCH",
    "project_ref='cdsmnqxtyyoeoznmbidd'",
    "PDC_EMAIL_130_PREDECESSOR_129_REQUIRED",
    "pdc_production_environment_sentinel",
    "import_pdc_authenticated_backend_batches",
    "pdc_authenticated_email_batch_receipts",
    "pdc_monitor_stage_activation_writers",
    "pdc_email_source_claims",
    "pdc_ai_intake_063",
    "jsonb_array_length(p_stock_numbers) not between 1 and 20",
    "unique(actor_id,idempotency_key)",
    "source_hash text not null unique",
    "backend_stock_not_found",
    "backend_stock_ambiguous",
    "operational_identity_conflict",
    "protected_existing_lifecycle",
    "activation_identity_conflict",
    "approved_email_build",
    "pdc_authenticated_email_backend_batch_130",
    "stock_only_authority',true",
    "'vin_required',false",
    "'booking_created',false",
    "identity_authority','unique_current_backend_stock",
    "where v.deleted_at is null and v.lifecycle_state='active' and v.stock_number_normalized=v_stock",
    "grant execute on function public.import_pdc_authenticated_backend_batches",
    "values('130','authenticated_email_backend_batch_fanout'",
):
    assert required in SQL, required

assert SQL.index("-- Validate every requested stock before the first mutation") < SQL.index("insert into public.navision_board_activations")
assert "split_part(v_sender,'@',2) not in ('broometoyota.com.au','pmgwa.com.au')" in SQL
assert "v_auth->'gmail_authentication_results' is distinct from 'true'::jsonb" in SQL

for forbidden in (
    "insert into public.workshop_bookings",
    "insert into public.vehicle_work_items",
    "insert into public.vehicle_parts_updates",
    "insert into public.notifications",
    "http_post",
    "net.http",
    "service_role key",
):
    assert forbidden not in LOWER, forbidden

print("PDC authenticated Back End batch fan-out contract passed.")
