from __future__ import annotations
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]; sys.path.insert(0,str(ROOT/'scripts'))
from apply_pdc14_staging import management_write
from inspect_pdc14_staging import management_query
EMAIL='[REDACTED_EMAIL]'
BAY='[REDACTED_UUID_93fa548a7b]'
EXPECTED_CURRENT='[REDACTED_UUID_e3f5fb15fa]'
PREVIOUS='[REDACTED_UUID_2e6fdba01b]'
pre=management_query(f"select code,version,default_technician_id::text,updated_at,updated_by::text from public.workshop_bays where id='{BAY}'::uuid")
rollback=management_write(f"""
begin;
alter table public.workshop_bays disable trigger user;
update public.workshop_bays target
set default_technician_id='{PREVIOUS}'::uuid,
    version=2,
    updated_at=source.updated_at,
    updated_by=source.updated_by
from public.workshop_bays source
where target.id='{BAY}'::uuid and target.version=3
  and target.default_technician_id='{EXPECTED_CURRENT}'::uuid
  and source.code='BUS_4X4-BAY-02'
returning target.code,target.version,target.default_technician_id::text,target.updated_at,target.updated_by::text;
alter table public.workshop_bays enable trigger user;
commit;
""")
uid=management_query(f"select id::text from auth.users where lower(email)='{EMAIL}'")[0]['id']
refs_cleanup=management_write(f"""
delete from public.workshop_bay_default_technician_history where actor_id='{uid}'::uuid;
delete from public.audit_events where actor_id='{uid}'::uuid;
delete from public.workshop_schedule_recovery_receipts where actor_user_id='{uid}'::uuid;
""")
management_write(f"delete from auth.users where id='{uid}'::uuid")
management_write(f"delete from public.pdc_user_roles where lower(email)='{EMAIL}'")
post=management_query(f"""
select jsonb_build_object(
 'bay',(select to_jsonb(x) from (select code,version,default_technician_id::text,updated_at,updated_by::text from public.workshop_bays where id='{BAY}'::uuid) x),
 'auth_count',(select count(*) from auth.users where lower(email)='{EMAIL}'),
 'role_count',(select count(*) from public.pdc_user_roles where lower(email)='{EMAIL}'),
 'qa_history_count',(select count(*) from public.workshop_bay_default_technician_history where actor_id='{uid}'::uuid),
 'qa_audit_count',(select count(*) from public.audit_events where actor_id='{uid}'::uuid),
 'qa_recovery_count',(select count(*) from public.workshop_schedule_recovery_receipts where actor_user_id='{uid}'::uuid),
 'production_sentinel_present',(select to_regclass('public.pdc_production_environment_sentinel') is not null)
) as state
""")[0]['state']
out={'pre':pre,'rollback':rollback,'post':post,'basis':'Restored Bay 01 to history-recorded previous technician and the matching version-2 metadata of Bay 02 from the same original default-technician configuration batch.'}
path=Path(__file__).with_name('cleanup-readback.json'); path.write_text(json.dumps(out,indent=2,default=str)+'\n',encoding='utf-8')
print(json.dumps(out,indent=2,default=str))
ok=post['auth_count']==0 and post['role_count']==0 and post['qa_history_count']==0 and post['qa_audit_count']==0 and post['qa_recovery_count']==0 and post['bay']['version']==2 and post['bay']['default_technician_id']==PREVIOUS and not post['production_sentinel_present']
raise SystemExit(0 if ok else 2)
