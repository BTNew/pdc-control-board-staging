import json,sys,urllib.request,subprocess,time,re
from pathlib import Path
sys.path.insert(0,'scripts')
from pdc_staging_management_migration import _post,STAGING_REF
sql="""SET TRANSACTION READ ONLY;
select jsonb_build_object(
 'project_ref','cdsmnqxtyyoeoznmbidd',
 'staging_sentinel_rows',(select count(*) from public.pdc_staging_environment_sentinel where singleton and project_ref='cdsmnqxtyyoeoznmbidd'),
 'production_sentinel_absent',to_regclass('public.pdc_production_environment_sentinel') is null,
 'migration_head',(select jsonb_build_object('version',version,'name',name)from supabase_migrations.schema_migrations where version~'^[0-9]{14}$'order by version desc limit 1),
 'monitor_status',(select running_status from public.pdc_email_monitor_status where singleton),
 'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
 'active_activation_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),
 'vehicle_total',(select count(*) from public.vehicles),
 'synthetic_vehicle_total',(select count(*) from public.vehicles where stock_number like 'HERMES-TEST%'),
 'outbound_notification_rows',(select count(*) from public.vehicle_notifications),
 'pending_outbound_notifications',(select count(*) from public.vehicle_notifications where status::text in('pending','retry','queued'))
) evidence;"""
evidence=_post(f'https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only',sql)[0]['evidence']
assert evidence['project_ref']==STAGING_REF and evidence['staging_sentinel_rows']==1 and evidence['production_sentinel_absent'] and evidence['monitor_status']=='stopped' and evidence['active_mailboxes']==0 and evidence['active_activation_writers']==0
base='https://btnew.github.io/pdc-control-board-staging/'
response=urllib.request.urlopen(base+'?identity='+str(time.time_ns()),timeout=30);html=response.read().decode('utf-8','replace')
live_commit=subprocess.check_output(['gh','api','repos/BTNew/pdc-control-board-staging/pages/builds/latest','--jq','.commit+" "+.status'],text=True).strip()
config=Path('pdc-supabase-config.staging.js').read_text(encoding='utf-8')
doc={'schema':'pdc-overnight-environment-proof-v1','website_hostname':'btnew.github.io','website_path':'/pdc-control-board-staging/','website_title':re.search(r'<title>(.*?)</title>',html,re.I|re.S).group(1),'pages_build':live_commit,'source_start_commit':'ac06394736b55220e7425322fc53e9b9dadc3fdd','branch':subprocess.check_output(['git','branch','--show-current'],text=True).strip(),'database':evidence,'banner_markers':{'staging_title':'PDC Control Board — STAGING' in html,'staging_ref_in_config':STAGING_REF in config,'production_url_absent_from_config':'https://vjdtsswhroyguxyfjdkt.supabase.co' not in config,'service_role_absent_from_config':'service_role' not in '\n'.join(line for line in config.splitlines() if not line.lstrip().startswith('//')).lower()},'credential_files_in_worktree':[str(p)for p in Path('.').glob('.env*')],'production_access_guard':Path('.hermes-overnight-staging-only').exists(),'outbound_policy':'mailboxes and activation writers disabled; no external sends permitted'}
Path('_overnight_evidence').mkdir(exist_ok=True);Path('_overnight_evidence/environment-proof.json').write_text(json.dumps(doc,indent=2,sort_keys=True),encoding='utf-8');print(json.dumps(doc,sort_keys=True))
