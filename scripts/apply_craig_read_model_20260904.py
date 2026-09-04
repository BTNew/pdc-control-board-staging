#!/usr/bin/env python3
from __future__ import annotations
import json, os
from pathlib import Path
from inspect_pdc14_staging import STAGING_REF, management_query
from apply_pdc14_staging import management_write
MIGRATION=Path(__file__).resolve().parents[1]/'supabase/staging_only/20260904010100_craig_hours_provenance_read_model.sql'
PROOF=Path(__file__).resolve().parents[1]/'review-evidence/t_dbd0c6bf-read-model-post.json'
if os.getenv('PDC_APPROVE_STAGING_MIGRATION_20260904010100')!='YES': raise SystemExit('approval env missing')
management_write(MIGRATION.read_text(encoding='utf-8'))
q="""select jsonb_build_object(
'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version='20260904010100'),
'def_has_origin',position('''correction_origin'',a.correction_origin' in pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure))>0,
'def_has_lock',position('''manual_assignment_locked'',a.manual_assignment_locked' in pg_get_functiondef('public.get_vehicle_workshop_detail(uuid)'::regprocedure))>0,
'public_execute',has_function_privilege('public','public.get_vehicle_workshop_detail(uuid)','EXECUTE'),
'anon_execute',has_function_privilege('anon','public.get_vehicle_workshop_detail(uuid)','EXECUTE'),
'authenticated_execute',has_function_privilege('authenticated','public.get_vehicle_workshop_detail(uuid)','EXECUTE')) as proof"""
proof=management_query(q)[0]['proof']; PROOF.parent.mkdir(parents=True,exist_ok=True); PROOF.write_text(json.dumps(proof,indent=2),encoding='utf-8'); print(json.dumps(proof,sort_keys=True))
