from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from inspect_pdc14_staging import STAGING_REF, management_query  # noqa: E402

if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
    raise RuntimeError("refusing non-STAGING target")

SQL = r"""
select jsonb_build_object(
  'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
  'production_sentinel_present',to_regclass('public.pdc_production_environment_sentinel') is not null,
  'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
  'normalize_definition',pg_get_functiondef('public.normalize_vehicle_vin(text)'::regprocedure),
  'valid_definition',pg_get_functiondef('public.is_valid_vehicle_vin(text)'::regprocedure),
  'normalize_row_definition',pg_get_functiondef('public.navision_backend_normalize_row(jsonb)'::regprocedure),
  'preview_internal_definition',pg_get_functiondef('public.navision_backend_preview_internal(jsonb,text,text,text,timestamptz)'::regprocedure),
  'candidate_definition',pg_get_functiondef('public.navision_backend_candidate_vehicle_ids(jsonb)'::regprocedure),
  'preflight_definition',pg_get_functiondef('public.navision_import_candidate_preflight_770(jsonb,text,text)'::regprocedure),
  'preview_definition',pg_get_functiondef('public.preview_navision_backend_import(jsonb,text,text,text,timestamptz)'::regprocedure),
  'apply_definition',pg_get_functiondef('public.apply_navision_backend_import(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure),
  'predecessor_definition',pg_get_functiondef('public.apply_navision_backend_import_pre_20260902271000(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure),
  'pre768_definition',pg_get_functiondef('public.apply_navision_backend_import_pre768(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure),
  'preholding_definition',pg_get_functiondef('public.apply_navision_backend_import_preholding_055(text,jsonb,text,text,text,timestamptz,text,text,bigint)'::regprocedure),
  'effective_definition',pg_get_functiondef('public.pdc_navision_effective_vin_471(jsonb)'::regprocedure)
) result
"""

result = management_query(SQL)[0]["result"]
output_dir = Path(__file__).resolve().parent / "live-definitions"
output_dir.mkdir(parents=True, exist_ok=True)
for key, value in result.items():
    if key.endswith("_definition") and isinstance(value, str):
        (output_dir / f"{key}.sql").write_text(value, encoding="utf-8")
print(json.dumps({"ok": True, "environment": "staging", "production_contacted": False, "result": result}, indent=2))
