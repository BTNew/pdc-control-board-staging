from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL = (ROOT / 'supabase/staging_only/20260830072000_navision_import_preflight_contract.sql').read_text(encoding='utf-8').lower()
APP = (ROOT / 'app.js').read_text(encoding='utf-8')
APP_LOWER = APP.lower()
SERVICE = (ROOT / 'navision-backend-service.js').read_text(encoding='utf-8')


def require(text: str, message: str) -> None:
    if text not in SQL:
        raise AssertionError(message)


def require_app(text: str, message: str) -> None:
    if text.lower() not in APP_LOWER:
        raise AssertionError(message)

for marker, message in [
    ('20260830071000', 'exact 767 predecessor must be bound'),
    ('769_monitor_compatibility_after_768', 'predecessor migration name must be bound'),
    ('navision_import_candidate_preflight_770', 'server preflight RPC/helper must exist'),
    ('duplicate_stock_number', 'duplicate Stock candidates must be classified'),
    ('duplicate_vin', 'duplicate VIN candidates must be classified'),
    ('duplicate_toyota_order', 'duplicate Toyota Order candidates must be classified'),
    ('wrong_dealer_scope', 'wrong-dealer candidates must be classified'),
    ('invalid_status_code', 'invalid status must be classified'),
    ('invalid_date', 'invalid date must be classified'),
    ('invalid_location_code', 'invalid location must be classified'),
    ('ambiguous_canonical_identity', 'ambiguous canonical identity must be classified'),
    ('canonical_identity_mismatch', 'canonical identity disagreement must be classified'),
    ("'atomic_apply',true", 'atomic apply contract must be explicit'),
    ('navision_preflight_blocked', 'apply must fail closed on server preflight'),
    ('navision_refresh_linked_vehicle_projection_770', 'linked Navision source projection must be refreshed'),
    ("'operational_mutations',0", 'projection must not mutate operations'),
    ('revoke all on function public.navision_import_candidate_preflight_770', 'preflight helper must not be browser-callable'),
    ("grant execute on function public.preview_navision_backend_import", 'preview grant must remain explicit'),
    ("grant execute on function public.apply_navision_backend_import", 'apply grant must remain explicit'),
    ('supabase_migrations.schema_migrations', 'migration ledger must be append-only'),
]:
    require(marker, message)

for marker, message in [
    ('function navisionclientpreflight', 'client preflight must exist'),
    ('duplicate_stock_number', 'client duplicate Stock reason missing'),
    ('invalid_status_code', 'client invalid status reason missing'),
    ('invalid_date', 'client invalid date reason missing'),
    ('invalid_location_code', 'client invalid location reason missing'),
    ('wrong_dealer_scope', 'client wrong-dealer reason missing'),
    ('sharednavisionapplyerrormessage', 'database errors must be translated for staff'),
    ('nothing was imported and no browser-local fallback was attempted', 'UI must retain actionable fail-closed message'),
]:
    require_app(marker, message)

if 'localstorage.setitem' in APP_LOWER[APP_LOWER.index('async function applysharednavisionimportpending'):APP_LOWER.index('function selectedpendingnavisionupdatekeys')]:
    raise AssertionError('shared apply must not write localStorage')
if 'p_source_system' not in SERVICE or 'p_dealer_code' not in SERVICE:
    raise AssertionError('service scope contract missing')
print('Navision 768 SQL/client contract: duplicate identity, invalid field, atomic/replay/security and no-localStorage checks passed')
