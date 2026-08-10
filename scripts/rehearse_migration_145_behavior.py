#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,os,sys,uuid
from pathlib import Path
import psycopg
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(Path.home()/'pdc-control-board'/'_staging_test_tools'))
from staging_env import load_local_env,assert_staging_target
M=ROOT/'supabase'/'staging_only'/'145_explicit_receipt_only_monitor_importer_and_parts_normalization.sql'
M146=ROOT/'supabase'/'staging_only'/'146_bind_monitor_import_to_retained_proposal.sql'
def one(c,q,p=()): c.execute(q,p); return c.fetchone()[0]
def main():
 parser=argparse.ArgumentParser(); parser.add_argument('--installed',action='store_true'); parser.add_argument('--candidate-146',action='store_true'); args=parser.parse_args()
 load_local_env(); d=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ.get('PDC_STAGING_DATABASE_URL'); assert_staging_target(database_url=d)
 s=M.read_text(); body=s.replace('begin;','',1).rsplit('commit;',1)[0]; conn=psycopg.connect(d); report={}
 try:
  with conn.cursor() as c:
   c.execute("select count(*) from public.vehicles"); vehicle_count_before=c.fetchone()[0]
   c.execute("select r.source_hash,r.evidence_hash,r.source_uid,r.sender_address,r.authentication,r.source_received_at,r.subject,r.observations,r.result,p.proposal_id from public.pdc_ai_intake_proposals r cross join lateral (select r.proposal_id) p where public.normalize_vehicle_stock_number(r.stock_number)='13045140' order by r.submitted_at desc limit 1")
   evidence=c.fetchone()
   if not evidence: raise RuntimeError('retained proposal missing')
   source,evidence_hash,source_uid,sender,auth,received,subject,observations,proposal_result,proposal_id=evidence
   c.execute("select w.user_id,u.email from public.pdc_monitor_stage_activation_writers w join auth.users u on u.id=w.user_id join public.pdc_user_roles r on r.auth_user_id=w.user_id and lower(r.email)=lower(u.email) where w.active and w.revoked_at is null and r.role='viewer' and r.active and r.account_status='approved' limit 1")
   actor=c.fetchone();
   if not actor: raise RuntimeError('exact-bound enrolled Viewer missing')
   c.execute("select v.id,to_jsonb(v),to_jsonb(a),to_jsonb(r) from public.navision_backend_records r join public.navision_board_activations a on a.backend_record_id=r.id join public.vehicles v on v.id=a.canonical_vehicle_id where r.is_current and public.normalize_vehicle_stock_number(r.normalized_data->>'batch')='13045140'")
   vehicle_id,vehicle_before,activation_before,backend_before=c.fetchone()
   baseline=(one(c,'select count(*) from public.workshop_bookings'),one(c,'select count(*) from public.vehicle_parts_updates'),one(c,'select count(*) from public.navision_board_activations'),one(c,'select count(*) from public.pdc_ai_intake_history'),one(c,'select revision from public.pdc_email_vehicle_revision where singleton'))
   mutation_baseline=(one(c,'select count(*) from public.pdc_authenticated_email_import_receipts'),one(c,'select count(*) from public.vehicle_work_items'),one(c,'select revision from public.pdc_email_vehicle_revision where singleton'))
   if args.candidate_146:
    s146=M146.read_text(); c.execute(s146.replace('begin;','',1).rsplit('commit;',1)[0])
   elif not args.installed: c.execute(body)
   claims=json.dumps({'sub':str(actor[0]),'email':actor[1],'role':'authenticated'}); c.execute('set local role authenticated'); c.execute("select set_config('request.jwt.claims',%s,true)",(claims,))
   key='pdc-email-import-qa145'+uuid.uuid4().hex
   vehicle={'cancelled':False,'conflicts':[],'customer_name':'FULTON HOGAN INDUSTRIES PTY LTD','eta_to_kewdale':None,'job_card_number':'J139125431','registration':None,'stock_numbers':['13045140'],'toyota_order_number':None,'vehicle_description':'Retained authenticated evidence','vins':['MR0REBHV100548367']}
   required=['Tint','Fitting','Electrical']
   call="select public.import_pdc_authenticated_vehicle_email(%s,%s,%s,%s,%s,%s::jsonb,%s::timestamptz,%s,%s::jsonb,%s::jsonb)"
   params=(key,source,evidence_hash,source_uid,sender,json.dumps(auth),received,subject,json.dumps(vehicle),json.dumps(required))
   tampered=(key+'tamper',source,evidence_hash,source_uid,sender,json.dumps(auth),received,subject+' altered',json.dumps(vehicle),json.dumps(required))
   tampered_result=one(c,call,tampered)
   c.execute('reset role')
   mutation_after=(one(c,'select count(*) from public.pdc_authenticated_email_import_receipts'),one(c,'select count(*) from public.vehicle_work_items'),one(c,'select revision from public.pdc_email_vehicle_revision where singleton'))
   if tampered_result.get('code')!='source_proposal_binding_mismatch' or mutation_after!=mutation_baseline: raise RuntimeError(f'tampered proposal binding was not fail-closed: {tampered_result}')
   c.execute('set local role authenticated')
   revision_before=one(c,'select revision from public.pdc_email_vehicle_revision where singleton'); result=one(c,call,params); replay=one(c,call,params)
   if not result.get('ok') or result.get('code')!='canonical_receipt_and_work_imported' or replay!=result: raise RuntimeError(f'v4 import/replay failed: {result} / {replay}')
   ops=[]; keys=['fitting','electrical','tint','parts']
   for i in range(1,17): ops.append({'operation_no':f'OP{i}','work_key':keys[(i-1)%4],'description':f'QA 145 retained operation {i:02d}','estimated_hours':1,'estimated_hours_source':'job_card'})
   op="select public.import_pdc_authenticated_email_operations_with_hours(%s,%s,%s::jsonb)"; op_result=one(c,op,(source,source_uid,json.dumps(ops))); rev_after=one(c,'select revision from public.pdc_email_vehicle_revision where singleton'); op_replay=one(c,op,(source,source_uid,json.dumps(ops))); rev_replay=one(c,'select revision from public.pdc_email_vehicle_revision where singleton')
   c.execute('reset role')
   if not op_result.get('ok') or op_result['data']['operation_lines_added']!=16 or op_replay.get('code')!='operation_lines_and_hours_already_imported' or rev_replay!=rev_after: raise RuntimeError(f'Parts/operation import failed: {op_result} / {op_replay}')
   c.execute("select to_jsonb(v),to_jsonb(a),to_jsonb(r),v.job_card_number from public.navision_backend_records r join public.navision_board_activations a on a.backend_record_id=r.id join public.vehicles v on v.id=a.canonical_vehicle_id where v.id=%s",(vehicle_id,)); vehicle_after,activation_after,backend_after,jc=c.fetchone()
   immutable_keys=['job_card_number','version','updated_at','updated_by']
   for k in immutable_keys: vehicle_before.pop(k,None); vehicle_after.pop(k,None)
   if vehicle_before!=vehicle_after or activation_before!=activation_after or backend_before!=backend_after or jc!='J139125431': raise RuntimeError('v4 changed forbidden vehicle/activation/backend fields')
   work=one(c,"select jsonb_agg(work_key order by work_key) from public.vehicle_work_items where vehicle_id=%s and required",(vehicle_id,))
   if work!=['electrical','fitting','PARTS','tint']: raise RuntimeError(f'work mismatch: {work}')
   if one(c,'select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s',(source,))!=1 or one(c,'select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s',(source,))!=16: raise RuntimeError('receipt/line count mismatch')
   final=(one(c,'select count(*) from public.workshop_bookings'),one(c,'select count(*) from public.vehicle_parts_updates'),one(c,'select count(*) from public.navision_board_activations'),one(c,'select count(*) from public.pdc_ai_intake_history'))
   if final!=baseline[:4] or one(c,'select count(*) from public.vehicles')!=vehicle_count_before: raise RuntimeError(f'forbidden side mutation: {baseline[:4]} -> {final}')
   report={'ok':True,'transaction':'rolled_back','stock':'13045140','jc':'J139125431','receipt':1,'operation_lines':16,'work_items':4,'fitting':True,'electrical':True,'tint':True,'parts_normalized_to_PARTS':True,'source_proposal_binding':True,'tampered_evidence_rejected':True,'existing_vehicle_only':True,'activation_unchanged':True,'backend_unchanged':True,'no_booking':True,'no_parts_side_write':True,'no_ai_mutation':True,'replay_idempotent':True,'realtime_revision_advanced':rev_after>revision_before}
   conn.rollback()
  with conn.cursor() as c:
   if one(c,"select exists(select 1 from supabase_migrations.schema_migrations where version='145')") is not (args.installed or args.candidate_146): raise RuntimeError('Migration 145 ledger state mismatch after rollback')
   if one(c,"select exists(select 1 from supabase_migrations.schema_migrations where version='146')"): raise RuntimeError('Migration 146 rollback leaked ledger')
   if one(c,"select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(source,))!=0: raise RuntimeError('rollback leaked receipt')
  conn.rollback(); report['rollback_verified']=True
 finally: conn.close()
 print(json.dumps(report,sort_keys=True))
if __name__=='__main__': main()
