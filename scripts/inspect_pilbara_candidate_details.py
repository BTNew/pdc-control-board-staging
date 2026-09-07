from __future__ import annotations

import json

from inspect_pdc14_staging import STAGING_REF, management_query
from pilbara_service_open_jobcards import EXPECTED_SOURCE_HASH, parse_source
from apply_pilbara_service_open_jobcards_staging import SOURCE, _literal

if STAGING_REF != "cdsmnqxtyyoeoznmbidd":
    raise RuntimeError("refusing non-STAGING target")
parsed = parse_source(SOURCE, EXPECTED_SOURCE_HASH)
stocks = _literal(sorted({row["stock_number"] for row in parsed.accepted}))
rows = management_query(f"""
with requested as (select value stock_number from jsonb_array_elements_text('{stocks}'::jsonb))
select r.stock_number,b.dealer_code,b.id::text backend_record_id,b.canonical_vehicle_id::text,
       btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock','')) backend_stock
from requested r left join public.navision_backend_records b
  on b.source_system='microsoft_navision' and b.is_current and b.record_status='current'
 and btrim(coalesce(b.normalized_data->>'batch',b.normalized_data->>'stock',''))=btrim(r.stock_number)
order by r.stock_number,b.id
""")
print(json.dumps({"project_ref": STAGING_REF, "production_contacted": False, "rows": rows}, indent=2))
