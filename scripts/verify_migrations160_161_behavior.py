#!/usr/bin/env python3
"""Rollback-only behavioral proof for PMB email Migrations 160/161."""
from __future__ import annotations
import hashlib,json,os,re,uuid
from pathlib import Path
import psycopg2
from psycopg2.extras import Json
from scripts.pdc_staging_runtime import assert_staging_target
ROOT=Path(__file__).resolve().parents[1]
FILES=[ROOT/'supabase'/'staging_only'/'160_email_communication_board_actions.sql',ROOT/'supabase'/'staging_only'/'161_non_navision_jobcard_board_creation.sql']
SENDER='craig.watson@broometoyota.com.au'
AUTH={'dkim_aligned':True,'dmarc_aligned':True,'gmail_authentication_results':True,'sender_domain':'broometoyota.com.au','spf_aligned':True}
def sha(x):return hashlib.sha256(x.encode()).hexdigest()
def body(p):
 s=p.read_text();s=re.sub(r'^\s*begin;\s*','',s,count=1,flags=re.I);return re.sub(r'\s*commit;\s*$','',s,count=1,flags=re.I)
def claims(c,role,actor=None,email=None):
 p={'role':role};
 if actor:p['sub']=actor
 if email:p['email']=email
 c.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps(p),))
def ok(v,code=None):
 assert isinstance(v,dict) and v.get('ok') is True,v
 if code:assert v.get('code')==code,v
 return v
def main():
 dsn=os.getenv('PDC_STAGING_DIRECT_DATABASE_URL') or os.getenv('PDC_STAGING_DATABASE_URL');assert_staging_target(database_url=dsn)
 con=psycopg2.connect(dsn);con.autocommit=False
 try:
  with con.cursor() as c:
   for p in FILES:c.execute(body(p))
   c.execute("""select w.user_id::text,lower(r.email) from public.pdc_monitor_stage_activation_writers w join public.pdc_user_roles r on r.auth_user_id=w.user_id where w.active and w.revoked_at is null and r.active and r.account_status='approved' and r.role in('viewer','importer') order by w.user_id limit 1""");actor,email=c.fetchone()
   c.execute("select id::text,mailbox_address from public.monitored_mailboxes where mailbox_key='pdc_pmb_email' and active");mailbox,recipient=c.fetchone()
   seq=uuid.uuid4().hex[:6];comm_stock='91'+str(int(seq,16)%1000000).zfill(6);non_stock='92'+str(int(seq,16)%1000000).zfill(6)
   c.execute("""insert into public.vehicles(permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,pmb_stage,source_payload,created_by,updated_by) values(%s,%s,%s,'active',true,'PMB','UNALLOCATED','{}',%s,%s) returning id::text,version,current_location""",(f'FIX-COMM-{seq}',comm_stock,f'JC-COMM-{seq}',actor,actor));vehicle,initial_version,initial_location=c.fetchone()
   c.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'sublet',true,false)",(vehicle,))
   def evidence(label,received='clock_timestamp()'):
    intake=str(uuid.uuid4());attachment=str(uuid.uuid4());parent=sha('p-'+label+seq);doc=sha('d-'+label+seq);msg=f'<{label}-{seq}@broometoyota.com.au>'
    c.execute(f"""insert into public.ai_email_intake(id,status,subject,sender_email,received_at,graph_message_id,internet_message_id,attachment_names,raw_body,extracted_data,warnings,processing_result,source_hash,monitored_mailbox_id,recipient_mailbox) values(%s,'received','Controlled PMB fixture',%s,{received},%s,%s,array['evidence.pdf'],'','{{}}','{{}}','{{}}',%s,%s,%s)""",(intake,SENDER,msg,msg,parent,mailbox,recipient))
    c.execute("""insert into public.ai_email_attachments(id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,storage_path,text_extraction_status,extracted_text,source_hash) values(%s,%s,%s,'evidence.pdf','application/pdf',1024,%s,'extracted','controlled',%s)""",(attachment,intake,'a-'+label,'fixture/'+attachment,doc))
    claims(c,'service_role');c.execute("select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)",(intake,attachment,parent,doc,msg,Json(AUTH)));ok(c.fetchone()[0])
    return intake,attachment,parent,doc
   intake,attachment,parent,doc=evidence('communication')
   # A retained email may already have a canonical job-card receipt; communication work must reuse it for the same vehicle.
   pre_receipt=str(uuid.uuid4())
   c.execute("insert into public.pdc_authenticated_email_import_receipts(receipt_id,actor_id,idempotency_key,request_hash,source_hash,evidence_hash,source_uid,sender_address,source_received_at,stock_number,vin,backend_record_id,vehicle_id,identity_source,required_work,response) values(%s,%s,%s,%s,%s,%s,%s,%s,clock_timestamp(),%s,null,null,%s,'operational_exact','[\"fitting\"]'::jsonb,public.navision_backend_response(true,'fixture'))",(pre_receipt,actor,'pdc-test-'+seq,sha('pre-request'),parent,doc,'pre-'+seq,email,comm_stock,vehicle))
   extraction={'actions':[{'source_action_no':1,'action_type':'parts_complete','evidence':'Parts Complete'},{'source_action_no':2,'action_type':'set_sublet_booking_date','booking_date':'2026-08-21','evidence':'Sublet booked 21/08/2026'},{'source_action_no':3,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Please add long range tank to this job'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':attachment,'canonical_document_hash':doc,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   xhash=sha(json.dumps(extraction,sort_keys=True));claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,xhash,Json(extraction)));first=ok(c.fetchone()[0],'communication_receipt');data=first['data'];assert data['action_count']==3 and data['booking_created'] is False and data['location_changed'] is False,first
   c.execute("select completed from public.vehicle_work_items where vehicle_id=%s and work_key='PARTS'",(vehicle,));assert c.fetchone()==(True,)
   c.execute("select parts_received,parts_stoppage from public.vehicle_parts_updates where vehicle_id=%s order by updated_at desc limit 1",(vehicle,));assert c.fetchone()==(True,False)
   c.execute("select booking_date::text from public.pdc_sublet_bookings where vehicle_id=%s",(vehicle,));assert c.fetchone()==('2026-08-21',)
   c.execute("select description,estimated_hours::text,source_contract from public.pdc_authenticated_email_operation_lines where vehicle_id=%s and source_hash=%s",(vehicle,parent));assert c.fetchone()==('Long range tank','1.00','pmb-email-communications-v1')
   c.execute("select array_agg(receipt_id::text),count(*) from public.pdc_authenticated_email_import_receipts where actor_id=%s and source_hash=%s",(actor,parent));bound_ids,bound_count=c.fetchone();assert bound_count==1 and bound_ids==[pre_receipt]
   c.execute("select current_location,count(*) over() from public.vehicles where id=%s",(vehicle,));assert c.fetchone()==(initial_location,1)
   c.execute("select count(*) from public.workshop_bookings where vehicle_id=%s",(vehicle,));assert c.fetchone()[0]==0
   c.execute("select version from public.vehicles where id=%s",(vehicle,));after_version=c.fetchone()[0]
   c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,xhash,Json(extraction)));replay=ok(c.fetchone()[0],'communication_receipt');assert replay['data']['receipt_id']==data['receipt_id']
   c.execute("select version from public.vehicles where id=%s",(vehicle,));assert c.fetchone()[0]==after_version

   # A late Sublet failure must roll back earlier Parts/accessory mutations and receipts.
   fail_stock='94'+non_stock[2:]
   c.execute("""insert into public.vehicles(permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,pmb_stage,source_payload,created_by,updated_by) values(%s,%s,%s,'active',true,'PMB','UNALLOCATED','{}',%s,%s) returning id::text,version""",(f'FIX-FAIL-{seq}',fail_stock,f'JC-FAIL-{seq}',actor,actor));fail_vehicle,fail_version=c.fetchone()
   fi,fa,fp,fd=evidence('atomic-fail')
   fx={'actions':[{'source_action_no':1,'action_type':'parts_complete','evidence':'Parts Complete'},{'source_action_no':2,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Add long range tank'},{'source_action_no':3,'action_type':'set_sublet_booking_date','booking_date':'2026-08-22','evidence':'Sublet booked 22/08/2026'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':fa,'canonical_document_hash':fd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[fail_stock],'vins':[]},'review_reasons':[]}
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(fi,fp,sha(json.dumps(fx,sort_keys=True)),Json(fx)));fr=c.fetchone()[0];assert fr.get('ok') is False and fr.get('code')=='sublet_not_required',fr
   c.execute("select version from public.vehicles where id=%s",(fail_vehicle,));assert c.fetchone()[0]==fail_version
   c.execute("select count(*) from public.vehicle_work_items where vehicle_id=%s",(fail_vehicle,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_email_communication_receipts where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   
   ni,na,np,nd=evidence('nonnav')
   lines=[{'description':'Fit long range tank','estimated_hours':3.25,'operation_no':'OP1','source_row_no':1,'work_key':'fitting'},{'description':'Install UHF','estimated_hours':1.50,'operation_no':'OP2','source_row_no':2,'work_key':'electrical'}]
   nx={'authentication':AUTH,'canonical_attachment_id':na,'canonical_document_hash':nd,'contract_version':'pmb-email-work-v2','email_vehicle':{'cancelled':False,'conflicts':[],'customer_name':'Used Vehicle Customer','eta_to_kewdale':None,'job_card_number':f'JC-NV-{seq}','registration':'1ABC234','stock_numbers':[non_stock],'toyota_order_number':'','vehicle_description':'Nissan Patrol Used','vins':[]},'operation_lines':lines,'required_work':['electrical','fitting']}
   nxh=sha(json.dumps(nx,sort_keys=True));claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ni,np,nxh,Json(nx)));nr=ok(c.fetchone()[0],'non_navision_jobcard_receipt');ndat=nr['data'];assert ndat['vehicle_created'] is True and ndat['initial_location']=='PMB' and ndat['operation_count']==2,nr
   nv=ndat['vehicle_id'];c.execute("select current_location,visible_on_board,lifecycle_state,make,job_card_number from public.vehicles where id=%s",(nv,));nvrow=c.fetchone();assert nvrow==('PMB',True,'active','Nissan',f'JC-NV-{seq}'.upper()),nvrow
   c.execute("select array_agg(estimated_hours::text order by source_row_no),array_agg(estimated_hours_source order by source_row_no) from public.pdc_authenticated_email_operation_lines where vehicle_id=%s",(nv,));assert c.fetchone()==(['3.25','1.50'],['job_card','job_card'])
   c.execute("select count(*) from public.workshop_bookings where vehicle_id=%s",(nv,));assert c.fetchone()[0]==0
   c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ni,np,nxh,Json(nx)));nr2=ok(c.fetchone()[0],'non_navision_jobcard_receipt');assert nr2['data']['receipt_id']==ndat['receipt_id']
   c.execute("select count(*) from public.vehicles where stock_number_normalized=%s",(non_stock,));assert c.fetchone()[0]==1
   c.execute("select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id=%s",(nv,));assert c.fetchone()[0]==2

   # A current Navision stock is never allowed through the non-Navision fallback.
   c.execute("""select public.normalize_vehicle_stock_number(normalized_data->>'batch') from public.navision_backend_records where source_system='microsoft_navision' and dealer_code in('14450','37047') and is_current and record_status='current' and public.is_real_vehicle_stock_number(public.normalize_vehicle_stock_number(normalized_data->>'batch')) order by id limit 1""");canonical_stock=c.fetchone()[0]
   ci,ca,cp,cd=evidence('canonical-guard');cx=dict(nx);cx['canonical_attachment_id']=ca;cx['canonical_document_hash']=cd;cx['email_vehicle']=dict(nx['email_vehicle']);cx['email_vehicle']['job_card_number']=f'JC-CAN-{seq}';cx['email_vehicle']['stock_numbers']=[canonical_stock]
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ci,cp,sha(json.dumps(cx,sort_keys=True)),Json(cx)));cr=c.fetchone()[0];assert cr.get('ok') is False and cr.get('code')=='navision_record_requires_canonical_path',cr
   c.execute("select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(cp,));assert c.fetchone()[0]==0
   
   old_i,old_a,old_p,old_d=evidence('stale',"clock_timestamp()-interval '31 days'")
   oldx=dict(nx);oldx['canonical_attachment_id']=old_a;oldx['canonical_document_hash']=old_d;oldx['email_vehicle']=dict(nx['email_vehicle']);oldx['email_vehicle']['job_card_number']=f'JC-OLD-{seq}';oldx['email_vehicle']['stock_numbers']=['93'+non_stock[2:]]
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(old_i,old_p,sha('oldx'),Json(oldx)));oldr=c.fetchone()[0];assert oldr.get('ok') is False and oldr.get('code')=='non_navision_evidence_binding_failed',oldr
   c.execute("select count(*) from public.vehicles where stock_number_normalized=%s",(oldx['email_vehicle']['stock_numbers'][0],));assert c.fetchone()[0]==0
   print(json.dumps({'ok':True,'mode':'rollback_behavior','communication_actions':3,'parts_complete':True,'sublet_date':'2026-08-21','accessory_hours':'1.00','atomic_failure_rollback':True,'canonical_navision_guard':True,'non_navision_created_at':'PMB','non_navision_operations':2,'replay_safe':True,'stale_rejected':True,'bookings_created':0},sort_keys=True))
  con.rollback();return 0
 finally:
  con.rollback();con.close()
if __name__=='__main__':raise SystemExit(main())
