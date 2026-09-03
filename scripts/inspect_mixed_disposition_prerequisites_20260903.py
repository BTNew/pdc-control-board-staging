from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.diagnose_pdc_email_ai_actual_jwt_replay_staging_20260903 import management_query

rows = management_query("""
SELECT
  (SELECT version FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1) AS head,
  encode(extensions.digest(convert_to(pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS strict_sha,
  encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_execute_v2_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS executor_sha,
  encode(extensions.digest(convert_to(pg_get_functiondef('public.get_pdc_email_ai_v2_acceptance_fixture_generation_20260903(uuid)'::regprocedure),'UTF8'),'sha256'),'hex') AS fixture_rpc_sha,
  encode(extensions.digest(convert_to(pg_get_functiondef('public.validate_pdc_email_ai_v2_acceptance_generation_plan_20260903(uuid,jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS validate_rpc_sha
""")
print(json.dumps(rows, sort_keys=True))
print(json.dumps(management_query("""
SELECT operation_no,description,estimated_hours,estimated_hours_source
FROM public.pdc_authenticated_email_operation_lines
WHERE source_hash='5e3a53566c5596ee78f6bcc91e1d75a831c1572e4e1eb6a4eddb252e687488b6'
ORDER BY operation_no
"""), sort_keys=True))
