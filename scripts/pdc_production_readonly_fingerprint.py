"""Read-only Production fingerprint; this program has no mutation endpoint."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from pdc_staging_management_migration import _post, PRODUCTION_REF, STAGING_REF
SQL=r"""SET TRANSACTION READ ONLY;
select jsonb_build_object(
 'project_ref','vjdtsswhroyguxyfjdkt',
 'staging_sentinel_absent',to_regclass('public.pdc_staging_environment_sentinel') is null,
 'migration_head',(select jsonb_build_object('version',version,'name',name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version desc limit 1),
 'catalog',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]'::jsonb) from (
   select n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner) owner,c.relrowsecurity,c.relforcerowsecurity,
          c.reltuples::bigint estimated_rows
   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in('r','p','v','m')
 ) x)
) as fingerprint;"""
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 endpoint=f'https://api.supabase.com/v1/projects/{PRODUCTION_REF}/database/query/read-only'
 rows=_post(endpoint,SQL)
 if not isinstance(rows,list) or len(rows)!=1 or rows[0]['fingerprint'].get('project_ref')!=PRODUCTION_REF: raise RuntimeError('PDC_PRODUCTION_READONLY_FINGERPRINT_INVALID')
 doc=rows[0]['fingerprint']; raw=json.dumps(doc,sort_keys=True,separators=(',',':')).encode(); doc['fingerprint_sha256']=hashlib.sha256(raw).hexdigest()
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(doc,indent=2,sort_keys=True),encoding='utf-8')
 print(json.dumps({'status':'PRODUCTION_READ_ONLY_FINGERPRINT','project_ref':PRODUCTION_REF,'fingerprint_sha256':doc['fingerprint_sha256'],'output':str(a.output.resolve())},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
