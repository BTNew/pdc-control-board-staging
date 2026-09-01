#!/usr/bin/env python3
"""Apply/read back the v2 planner contract binding in STAGING only."""
from __future__ import annotations
import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260901050000_pdc_email_ai_typed_action_v2_contract_binding_20260901.sql'
BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
STAGING_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'
PREDECESSOR = ('20260901040000', 'pdc_email_ai_typed_action_validator_binding_20260901')
TARGET = ('20260901050000', 'pdc_email_ai_typed_action_v2_contract_binding_20260901')
APPROVAL_ENV = 'PDC_APPROVE_STAGING_MIGRATION_20260901050000'

def one(cur, query, params=()):
    cur.execute(query, params)
    return cur.fetchone()

def bundle():
    if not BOOTSTRAP.is_file() or not SECRETS.is_file():
        raise RuntimeError('PDC_V2_CONTRACT_PROTECTED_STAGING_CONNECTOR_UNAVAILABLE')
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('PDC_V2_CONTRACT_STAGING_CONNECTOR_INVALID')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    data = json.loads(module.unprotect(SECRETS.read_bytes()).decode('utf-8'))
    module.validate(data)
    url = data.get('PDC_STAGING_DATABASE_URL', '')
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError('PDC_V2_CONTRACT_NON_STAGING_TARGET')
    return data

def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f'apply migration 20260901050000 pdc email ai typed action v2 contract binding source {digest}'
    if os.environ.get(APPROVAL_ENV) != expected:
        raise RuntimeError('PDC_V2_CONTRACT_APPROVAL_MISSING_OR_HASH_MISMATCH')
    data = bundle()
    import psycopg2
    conn = psycopg2.connect(data['PDC_STAGING_DATABASE_URL'], sslmode='verify-full', sslrootcert=data['PDC_STAGING_SSLROOTCERT'], application_name='pdc-email-ai-v2-contract-binding-staging-controller')
    conn.autocommit = False
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != PREDECESSOR:
            raise RuntimeError(f'PDC_V2_CONTRACT_UNEXPECTED_LIVE_HEAD:{head}')
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError('PDC_V2_CONTRACT_PRODUCTION_SENTINEL_PRESENT')
        cur.execute(MIGRATION.read_text(encoding='utf-8'))
        conn.commit()
        cur = conn.cursor()
        ledger = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version='20260901050000'") or ())
        strict = bool(one(cur, "select to_regprocedure('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)') is not null")[0])
        validator = bool(one(cur, "select to_regprocedure('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)') is not null")[0])
        acl = tuple(one(cur, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('service_role','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('public','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute'), has_function_privilege('anon','public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)','execute')"))
        source = one(cur, "select pg_get_functiondef('public.apply_pdc_email_ai_typed_action_surface_20260901_strict(jsonb)'::regprocedure)")[0] or ''
        old_acl = bool(one(cur, "select has_function_privilege('authenticated','public.apply_pdc_email_ai_typed_action_surface_20260901(jsonb)','execute')")[0])
        prod = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        proof = {'ok': ledger == TARGET and strict and validator and acl == (True,False,False,False) and not old_acl and 'pdc_email_ai_successor_validate_v2_instruction_20260901' in source and 'source_thread_id' in source and not prod, 'environment':'staging','project_ref':STAGING_REF,'migration_sha256':digest,'ledger_head':ledger,'strict_rpc_present':strict,'v2_validator_present':validator,'authenticated_execute':acl[0],'service_role_execute':acl[1],'public_execute':acl[2],'anon_execute':acl[3],'legacy_direct_execute':old_acl,'production_sentinel_present':prod,'action_rpc_invoked':False,'mailbox_contacted':False,'outbound_email':False,'business_mutation':False}
        print(json.dumps(proof, sort_keys=True))
        if not proof['ok']:
            raise RuntimeError('PDC_V2_CONTRACT_POST_APPLY_READBACK_FAILED')
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()

if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'ok':False,'environment':'staging','error':str(exc),'production_contacted':False,'mailbox_contacted':False,'action_rpc_invoked':False}, sort_keys=True))
        raise SystemExit(1)
