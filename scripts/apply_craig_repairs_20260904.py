#!/usr/bin/env python3
from __future__ import annotations
import json, os
from pathlib import Path
from inspect_pdc14_staging import STAGING_REF, management_query
from apply_pdc14_staging import management_write, security_advisor_summary
ROOT=Path(__file__).resolve().parents[1]
MIGRATION=ROOT/'supabase/staging_only/20260904010000_craig_workshop_and_jobcard_repairs.sql'
APPROVAL='PDC_APPROVE_STAGING_MIGRATION_20260904010000'

def main():
    if os.environ.get(APPROVAL)!='YES': raise RuntimeError(f'Set {APPROVAL}=YES')
    head=management_query("select version from supabase_migrations.schema_migrations where version='20260904010000'")
    if not head: management_write(MIGRATION.read_text(encoding='utf-8'))
    proof=management_write(r"""
select jsonb_build_object(
 'project_ref',(select project_ref from public.pdc_staging_environment_sentinel where singleton),
 'head',(select jsonb_build_array(version,name) from supabase_migrations.schema_migrations where version~'^[0-9]{14}$' order by version::bigint desc limit 1),
 'production_sentinel',to_regclass('public.pdc_production_environment_sentinel') is not null,
 'pit_enabled',(select planner_enabled from public.workshop_stages where code='PIT_INSPECTION'),
 'rename_acl',jsonb_build_object('authenticated',has_function_privilege('authenticated','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute'),'anon',has_function_privilege('anon','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute'),'service_role',has_function_privilege('service_role','public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)','execute')),
 'pd_cases',jsonb_build_array(public.pdc_apply_craig_pd_hours_rule_20260904('Pre-Delivery (Commercial)',0.0,'job_card'),public.pdc_apply_craig_pd_hours_rule_20260904('PD Inspection',null,null),public.pdc_apply_craig_pd_hours_rule_20260904('PIT AND WEIGH',0.0,'job_card')),
 'vehicle',(select jsonb_build_object('id',v.id,'stock',v.stock_number,'job_card',v.job_card_number,'customer',v.customer_name,'salesperson_reference',v.salesperson_reference,'salesperson_name',s.name,'stock_authority',v.source_payload->>'stock_authority','invoice_value',v.source_payload->>'job_card_invoice_value') from public.vehicles v left join public.salespeople s on s.id=v.salesperson_id where v.stock_number_normalized='13048501' and v.deleted_at is null),
 'hours',(select jsonb_build_object('immutable_source_total',(select sum(o.estimated_hours) from public.pdc_authenticated_email_operation_lines o where o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'),'effective_total',(select sum(coalesce(a.estimated_hours,o.estimated_hours)) from public.pdc_authenticated_email_operation_lines o left join public.vehicle_workshop_line_adjustments a on a.source_operation_line_id=o.operation_line_id and a.active where o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0'),'op1',(select jsonb_build_object('source_hours',o.estimated_hours,'source_provenance',o.estimated_hours_source,'effective_hours',a.estimated_hours,'effective_provenance',a.correction_origin) from public.pdc_authenticated_email_operation_lines o left join public.vehicle_workshop_line_adjustments a on a.source_operation_line_id=o.operation_line_id and a.active where o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0' and o.operation_no='OP1'),'op15',(select jsonb_build_object('source_hours',o.estimated_hours,'source_provenance',o.estimated_hours_source,'effective_hours',a.estimated_hours,'effective_provenance',a.correction_origin) from public.pdc_authenticated_email_operation_lines o left join public.vehicle_workshop_line_adjustments a on a.source_operation_line_id=o.operation_line_id and a.active where o.vehicle_id='f41c7e49-a5fe-527c-94a3-e1fd18be15b0' and o.operation_no='OP15'))),
 'correction_count',(select count(*) from public.pdc_jobcard_hours_corrections_20260904),
 'correction_rls',(select relrowsecurity and relforcerowsecurity from pg_class where oid='public.pdc_jobcard_hours_corrections_20260904'::regclass),
 'rename_definition_ok',(select position('FOR UPDATE' in upper(pg_get_functiondef('public.rename_workshop_admin_block_20260904(uuid,bigint,text,jsonb)'::regprocedure)))>0),
 'pit_delete_trigger',(select count(*)=1 from pg_trigger where tgname='pdc_admin_block_delete_cancel_pit_20260904' and tgenabled='O'),
 'prospective_pd_trigger',(select count(*)=1 from pg_trigger where tgname='pdc_project_craig_pd_hours_20260904' and tgenabled='O')
) proof
""")[0]['proof']
    cases=proof['pd_cases']; h=proof['hours']; v=proof['vehicle']; acl=proof['rename_acl']
    checks=[proof['project_ref']==STAGING_REF,proof['head']==['20260904010000','craig_workshop_and_jobcard_repairs'],not proof['production_sentinel'],proof['pit_enabled'],acl=={'authenticated':True,'anon':False,'service_role':False},cases[0]['estimated_hours']==1.5,cases[0]['estimated_hours_source']=='craig_standard_pd_1_5',cases[1]['estimated_hours']==1.5,cases[2]['applied'] is False,cases[2]['estimated_hours']==0,v['stock']=='13048501',v['job_card']=='J139125583',v['customer']=='SHIRE OF EAST PILBARA',v['salesperson_name']=='Stephen Peck',v['stock_authority']=='069',v['invoice_value']=='1324.5',h['immutable_source_total']==17,h['effective_total']==18.5,h['op1']['source_hours']==0,h['op1']['effective_hours']==1.5,h['op15']['source_provenance']=='ai_estimate',h['op15']['effective_provenance']=='job_card_source_correction',proof['correction_count']==2,proof['correction_rls'],proof['rename_definition_ok'],proof['pit_delete_trigger'],proof['prospective_pd_trigger']]
    if not all(checks): raise RuntimeError(f'PDC_20260904_VERIFY_FAILED:{proof}')
    out={'ok':True,'environment':'staging','project_ref':STAGING_REF,'proof':proof,'security_advisors':security_advisor_summary(),'production_contacted':False,'production_mutated':False}
    path=ROOT/'review-evidence/t_dbd0c6bf-staging-apply-proof.json';path.write_text(json.dumps(out,indent=2,default=str)+'\n',encoding='utf-8');print(json.dumps(out,indent=2,default=str))
if __name__=='__main__': main()
