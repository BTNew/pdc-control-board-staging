"""Capture a secret-free live public catalog/count manifest from exact staging."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from pdc_staging_management_migration import STAGING_REF, PRODUCTION_REF, _post

CATALOG_SQL = r"""
select jsonb_build_object(
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'production_sentinel_absent',to_regclass('public.pdc_production_environment_sentinel') is null,
 'staging_sentinel_rows',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
 'migration_head',(select jsonb_build_object('version',version,'name',name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version desc limit 1),
 'tables',(select coalesce(jsonb_agg(jsonb_build_object('name',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity) order by c.relname),'[]'::jsonb)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p')),
 'columns',(select coalesce(jsonb_agg(jsonb_build_object('table',c.relname,'ordinal',a.attnum,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull) order by c.relname,a.attnum),'[]'::jsonb)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped where n.nspname='public' and c.relkind in('r','p')),
 'foreign_keys',(select coalesce(jsonb_agg(jsonb_build_object('name',con.conname,'child',ch.relname,'parent_schema',pn.nspname,'parent',pa.relname,'definition',pg_get_constraintdef(con.oid,true)) order by ch.relname,con.conname),'[]'::jsonb)
   from pg_constraint con join pg_class ch on ch.oid=con.conrelid join pg_namespace cn on cn.oid=ch.relnamespace join pg_class pa on pa.oid=con.confrelid join pg_namespace pn on pn.oid=pa.relnamespace where con.contype='f' and cn.nspname='public'),
 'monitor',(select jsonb_build_object(
   'pilot_enabled',coalesce((select enabled from public.pdc_email_monitor_pilot where singleton),false),
   'outbound_email_enabled',coalesce((select outbound_email_enabled from public.pdc_email_monitor_pilot where singleton),false),
   'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
   'active_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
   'running_status',(select running_status from public.pdc_email_monitor_status where singleton),
   'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton)))
) as catalog;
"""

def ro(query: str):
    return _post(f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only", "SET TRANSACTION READ ONLY;\n"+query)

def main() -> int:
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True); a=p.parse_args()
    rows=ro(CATALOG_SQL)
    if not isinstance(rows,list) or len(rows)!=1 or not isinstance(rows[0].get('catalog'),dict): raise RuntimeError('PDC_CATALOG_INVALID')
    doc=rows[0]['catalog']
    if doc['project_ref']!=STAGING_REF or not doc['production_sentinel_absent'] or doc['staging_sentinel_rows']!=1: raise RuntimeError('PDC_TARGET_GUARD_FAILED')
    counts={}
    for entry in doc['tables']:
        name=entry['name']
        q='select count(*)::bigint as n from public."'+name.replace('"','""')+'";'
        result=ro(q)
        if not isinstance(result,list) or len(result)!=1: raise RuntimeError('PDC_COUNT_INVALID:'+name)
        counts[name]=int(result[0]['n'])
    doc['row_counts']=counts
    raw=json.dumps(doc,sort_keys=True,separators=(',',':')).encode()
    doc['catalog_sha256']=hashlib.sha256(raw).hexdigest()
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(doc,indent=2,sort_keys=True),encoding='utf-8')
    print(json.dumps({'status':'CAPTURED','project_ref':STAGING_REF,'tables':len(doc['tables']),'foreign_keys':len(doc['foreign_keys']),'catalog_sha256':doc['catalog_sha256'],'output':str(a.output.resolve())},sort_keys=True))
    return 0
if __name__=='__main__': raise SystemExit(main())
