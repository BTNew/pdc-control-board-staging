#!/usr/bin/env python3
"""Apply the one-shot successor owner provisioning contract in STAGING only."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase/staging_only/20260831350000_pdc_email_ai_successor_owner_provisioning.sql'
BOOTSTRAP = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
SECRETS = Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
STAGING_REF = 'cdsmnqxtyyoeoznmbidd'
PRODUCTION_REF = 'vjdtsswhroyguxyfjdkt'


def one(cursor, sql):
    cursor.execute(sql)
    return cursor.fetchone()


def main():
    digest = hashlib.sha256(MIGRATION.read_bytes()).hexdigest()
    expected = f'apply migration 865 pdc email ai successor owner provisioning source {digest}'
    if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_865') != expected:
        raise RuntimeError('PDC_SUCCESSOR_3500_STAGING_APPROVAL_MISSING_OR_HASH_MISMATCH')
    spec = importlib.util.spec_from_file_location('pdc_staging_bootstrap', BOOTSTRAP)
    if spec is None or spec.loader is None:
        raise RuntimeError('PDC_SUCCESSOR_STAGING_CONNECTOR_INVALID')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    bundle = json.loads(module.unprotect(SECRETS.read_bytes()).decode()); module.validate(bundle)
    url = bundle['PDC_STAGING_DATABASE_URL']
    if STAGING_REF not in url or PRODUCTION_REF in url:
        raise RuntimeError('PDC_SUCCESSOR_NON_STAGING_TARGET')
    import psycopg2
    conn = psycopg2.connect(url, sslmode='verify-full', sslrootcert=bundle['PDC_STAGING_SSLROOTCERT'], application_name='pdc-email-ai-successor-owner-provisioning-migration')
    try:
        cur = conn.cursor()
        head = tuple(one(cur, "select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != ('20260831340000','pdc_email_ai_successor_command_read_hardening'):
            raise RuntimeError(f'PDC_SUCCESSOR_3500_UNEXPECTED_LIVE_HEAD:{head}')
        if one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]:
            raise RuntimeError('PDC_SUCCESSOR_3500_PRODUCTION_SENTINEL_PRESENT')
        cur.execute(MIGRATION.read_text(encoding='utf-8')); conn.commit(); cur=conn.cursor()
        ledger=tuple(one(cur,"select version,name from supabase_migrations.schema_migrations where version='20260831350000'") or ())
        provision=bool(one(cur,"select to_regprocedure('public.commission_pdc_email_ai_successor_runtime(uuid,text,text,text,text,text,text,text,text,text,text,uuid)') is not null")[0])
        rollback=bool(one(cur,"select to_regprocedure('public.rollback_pdc_email_ai_successor_runtime(uuid)') is not null")[0])
        service_provision=bool(one(cur,"select has_function_privilege('service_role','public.commission_pdc_email_ai_successor_runtime(uuid,text,text,text,text,text,text,text,text,text,text,uuid)','execute')")[0])
        authenticated_provision=bool(one(cur,"select has_function_privilege('authenticated','public.commission_pdc_email_ai_successor_runtime(uuid,text,text,text,text,text,text,text,text,text,text,uuid)','execute')")[0])
        production_present = bool(one(cur, "select to_regclass('public.pdc_production_environment_sentinel') is not null")[0])
        print(json.dumps({'ok':ledger==('20260831350000','pdc_email_ai_successor_owner_provisioning') and provision and rollback and service_provision and not authenticated_provision and not production_present,'environment':'staging','project_ref':STAGING_REF,'migration_sha256':digest,'ledger':ledger,'commission_rpc_present':provision,'rollback_rpc_present':rollback,'service_role_execute':service_provision,'authenticated_execute':authenticated_provision,'production_contacted':False},sort_keys=True))
    except Exception:
        conn.rollback(); raise
    finally: conn.close()


if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print(json.dumps({'ok':False,'environment':'staging','error':str(exc),'production_contacted':False},sort_keys=True)); raise SystemExit(1)
