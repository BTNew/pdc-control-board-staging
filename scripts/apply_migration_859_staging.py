from pathlib import Path
import hashlib, importlib.util, json, os
R=Path(__file__).resolve().parents[1]
M=R/'supabase/staging_only/20260831250000_859_runtime_766_compatibility_and_attachment_path_successor.sql'
B=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-bootstrap/pdc_staging_bootstrap.py')
S=Path(r'C:/Users/nwmgr/AppData/Local/hermes/staging-secrets/pdc-staging.dpapi')
REF='cdsmnqxtyyoeoznmbidd'; PROD='vjdtsswhroyguxyfjdkt'
T=('20260831250000','859_runtime_766_compatibility_and_attachment_path_successor')

def row(c,q): c.execute(q); return c.fetchone()

def main():
    sp=importlib.util.spec_from_file_location('b',B); m=importlib.util.module_from_spec(sp); assert sp and sp.loader; sp.loader.exec_module(m)
    d=json.loads(m.unprotect(S.read_bytes()).decode()); m.validate(d)
    if REF not in d['PDC_STAGING_DATABASE_URL'] or PROD in d['PDC_STAGING_DATABASE_URL']: raise RuntimeError('PDC_859_NON_STAGING_TARGET')
    h=hashlib.sha256(M.read_bytes()).hexdigest()
    expected=f'apply migration 859 runtime 766 compatibility and attachment path source {h}'
    if os.environ.get('PDC_APPROVE_STAGING_MIGRATION_859')!=expected: raise RuntimeError('staging migration approval missing or hash-mismatched')
    import psycopg2
    c=psycopg2.connect(d['PDC_STAGING_DATABASE_URL'],sslmode='verify-full',sslrootcert=d['PDC_STAGING_SSLROOTCERT'],application_name='pdc-859-runtime-766-staging-controller')
    c.autocommit=False
    try:
        cur=c.cursor(); head=tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        if head != ('20260831240000','858_runtime_authority_839_scope_compatibility_successor'): raise RuntimeError(f'PDC_859_UNEXPECTED_LIVE_HEAD:{head}')
        if row(cur,"select to_regclass('public.pdc_production_environment_sentinel') is not null")[0]: raise RuntimeError('PDC_859_PRODUCTION_SENTINEL_PRESENT')
        cur.execute(M.read_text(encoding='utf-8')); c.commit(); cur=c.cursor()
        newhead=tuple(row(cur,"select version,name from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1") or ())
        fn=(row(cur,"select pg_get_functiondef('public.verify_pdc_monitor_runtime_binding_authenticated_766(text,text,text,text,text,text,text)'::regprocedure)") or ('',))[0]
        storage=(row(cur,"select pg_get_functiondef('public.get_pdc_monitor_intake_attachments_735(uuid,uuid,text)'::regprocedure)") or ('',))[0]
        o={'ok':newhead==T,'environment':'staging','project_ref':REF,'migration_sha256':h,'ledger_head':newhead,'legacy_projection_766':"'migration_head',766" in fn and "'compatibility_successor_head',766" in fn,'scope_839':'pdc_monitor_authenticated_active_scope_839' in fn,'storage_path_quarantine':'path_quarantined' in storage,'board_mutated':False,'mailbox_flags_changed':False,'uid514_processed':False,'production_contacted':False,'outbound_email_enabled':False}
        if not all((o['ok'],o['legacy_projection_766'],o['scope_839'],o['storage_path_quarantine'])): raise RuntimeError('PDC_859_POST_APPLY_READBACK_FAILED:'+json.dumps(o,sort_keys=True))
        c.commit(); print(json.dumps(o,sort_keys=True))
    except Exception:
        c.rollback(); raise
    finally: c.close()

if __name__=='__main__':
    try: main()
    except Exception as e:
        print(json.dumps({'ok':False,'error':str(e),'environment':'staging','mailbox_contacted':False,'uid514_processed':False,'production_contacted':False})); raise SystemExit(1)
