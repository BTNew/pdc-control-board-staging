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
 s=p.read_text();s,n1=re.subn(r'(?im)^\s*begin;\s*$','',s,count=1);s,n2=re.subn(r'(?im)^\s*commit;\s*$','',s,count=1)
 assert n1==1 and n2==1,(p,n1,n2);return s
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
   c.execute("""select w.user_id::text,lower(r.email) from public.pdc_monitor_stage_activation_writers w join public.pdc_user_roles r on r.auth_user_id=w.user_id where w.active and w.revoked_at is null and r.active and r.account_status='approved' and r.role='importer' order by w.user_id limit 1""");actor,email=c.fetchone()
   c.execute("select id::text,mailbox_address from public.monitored_mailboxes where mailbox_key='pdc_pmb_email' and active");mailbox,recipient=c.fetchone()
   seq=uuid.uuid4().hex[:6];comm_stock='91'+str(int(seq,16)%1000000).zfill(6);non_stock='92'+str(int(seq,16)%1000000).zfill(6)
   c.execute("""insert into public.vehicles(permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,pmb_stage,source_payload,created_by,updated_by) values(%s,%s,%s,'active',true,'PMB','UNALLOCATED','{}',%s,%s) returning id::text,version,current_location""",(f'FIX-COMM-{seq}',comm_stock,f'JC-COMM-{seq}',actor,actor));vehicle,initial_version,initial_location=c.fetchone()
   c.execute("insert into public.vehicle_work_items(vehicle_id,work_key,required,completed) values(%s,'sublet',true,false)",(vehicle,))
   def evidence(label,text,received='clock_timestamp()'):
    intake=str(uuid.uuid4());attachment=str(uuid.uuid4());parent=sha('p-'+label+seq);doc=sha('d-'+label+seq);msg=f'<{label}-{seq}@broometoyota.com.au>'
    c.execute(f"""insert into public.ai_email_intake(id,status,subject,sender_email,received_at,graph_message_id,internet_message_id,attachment_names,raw_body,extracted_data,warnings,processing_result,source_hash,monitored_mailbox_id,recipient_mailbox) values(%s,'received','Controlled PMB fixture',%s,{received},%s,%s,array['evidence.pdf'],'','{{}}','{{}}','{{}}',%s,%s,%s)""",(intake,SENDER,msg,msg,parent,mailbox,recipient))
    c.execute("""insert into public.ai_email_attachments(id,intake_id,graph_attachment_id,file_name,content_type,size_bytes,storage_path,text_extraction_status,extracted_text,source_hash) values(%s,%s,%s,'evidence.pdf','application/pdf',1024,%s,'extracted',%s,%s)""",(attachment,intake,'a-'+label,'fixture/'+attachment,text,doc))
    claims(c,'service_role');c.execute("select public.attest_pdc_provider_email_observation(%s,%s,%s,%s,%s,'mx.google.com',%s)",(intake,attachment,parent,doc,msg,Json(AUTH)));ok(c.fetchone()[0])
    return intake,attachment,parent,doc
   def mutation_counts():
    c.execute("""select
      (select count(*) from public.vehicles),(select count(*) from public.vehicle_work_items),
      (select count(*) from public.vehicle_parts_updates),(select count(*) from public.pdc_sublet_bookings),
      (select count(*) from public.pdc_authenticated_email_import_receipts),(select count(*) from public.pdc_authenticated_email_operation_lines),
      (select count(*) from public.pdc_email_communication_receipts),(select count(*) from public.pdc_email_communication_action_receipts),
      (select count(*) from public.pdc_non_navision_jobcard_receipts),(select count(*) from public.pdc_non_navision_jobcard_source_row_receipts),
      (select count(*) from public.pdc_email_evidence_consumptions),(select count(*) from public.audit_events)""")
    return c.fetchone()
   def rejected_without_delta(sql,params,code):
    before=mutation_counts();c.execute(sql,params);result=c.fetchone()[0]
    assert result.get('ok') is False and result.get('code')==code,result
    assert mutation_counts()==before,(code,before,mutation_counts())
    return result
   communication_text=f'Stock {comm_stock}. Job Card JC-COMM-{seq}. Parts Complete. Sublet booked 21/08/2026. Please add long range tank to this job. Fit long range tank 1.0 hours.'
   intake,attachment,parent,doc=evidence('communication',communication_text)
   extraction={'actions':[{'source_action_no':1,'action_type':'parts_complete','evidence':'Parts Complete'},{'source_action_no':2,'action_type':'set_sublet_booking_date','booking_date':'2026-08-21','evidence':'Sublet booked 21/08/2026'},{'source_action_no':3,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Please add long range tank to this job'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':attachment,'canonical_document_hash':doc,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   xhash=sha(json.dumps(extraction,sort_keys=True));claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,xhash,Json(extraction)));first=ok(c.fetchone()[0],'communication_receipt');data=first['data'];assert data['action_count']==3 and data['booking_created'] is False and data['location_changed'] is False,first
   c.execute("select completed from public.vehicle_work_items where vehicle_id=%s and work_key='PARTS'",(vehicle,));assert c.fetchone()==(True,)
   c.execute("select parts_received,parts_stoppage from public.vehicle_parts_updates where vehicle_id=%s order by updated_at desc limit 1",(vehicle,));assert c.fetchone()==(True,False)
   c.execute("select booking_date::text from public.pdc_sublet_bookings where vehicle_id=%s",(vehicle,));assert c.fetchone()==('2026-08-21',)
   c.execute("select description,estimated_hours::text,source_contract from public.pdc_authenticated_email_operation_lines where vehicle_id=%s and source_hash=%s",(vehicle,parent));assert c.fetchone()==('Long range tank','1.00','pmb-email-communications-v1')
   c.execute("select count(*) from public.pdc_authenticated_email_import_receipts where actor_id=%s and source_hash=%s",(actor,parent));assert c.fetchone()[0]==1
   c.execute("select current_location,count(*) over() from public.vehicles where id=%s",(vehicle,));assert c.fetchone()==(initial_location,1)
   c.execute("select count(*) from public.workshop_bookings where vehicle_id=%s",(vehicle,));assert c.fetchone()[0]==0
   c.execute("select version from public.vehicles where id=%s",(vehicle,));after_version=c.fetchone()[0]
   c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,xhash,Json(extraction)));replay=ok(c.fetchone()[0],'communication_receipt');assert replay['data']['receipt_id']==data['receipt_id']
   c.execute("select version from public.vehicles where id=%s",(vehicle,));assert c.fetchone()[0]==after_version
   combined_lines=[{'description':'Fit long range tank','estimated_hours':1.0,'operation_no':'OP1','source_row_no':1,'work_key':'fitting'}]
   combined={'authentication':AUTH,'canonical_attachment_id':attachment,'canonical_document_hash':doc,'contract_version':'pmb-email-work-v2','email_vehicle':{'cancelled':False,'conflicts':[],'customer_name':'','eta_to_kewdale':None,'job_card_number':f'JC-COMM-{seq}','registration':'','stock_numbers':[comm_stock],'toyota_order_number':'','vehicle_description':'Used vehicle','vins':[]},'operation_lines':combined_lines,'required_work':['fitting']}
   c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,sha(json.dumps(combined,sort_keys=True)),Json(combined)));consumed=c.fetchone()[0];assert consumed.get('ok') is False and consumed.get('code')=='non_navision_evidence_already_consumed',consumed
   c.execute("update public.ai_email_intake set received_at=clock_timestamp()-interval '31 days' where id=%s",(intake,))
   c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(intake,parent,xhash,Json(extraction)));stale_replay=ok(c.fetchone()[0],'communication_receipt');assert stale_replay['data']['receipt_id']==data['receipt_id']

   # SQL independently rejects Viewers, contradictory actions, mismatched IDs, forged evidence and completed-work reopening.
   viewer_text=f'Stock {comm_stock}. Parts Complete.';vi,va,vp,vd=evidence('viewer-denial',viewer_text)
   vx={'actions':[{'source_action_no':1,'action_type':'parts_complete','evidence':'Parts Complete'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':va,'canonical_document_hash':vd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   c.execute("update public.pdc_user_roles set role='viewer' where auth_user_id=%s",(actor,));claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(vi,vp,sha(json.dumps(vx,sort_keys=True)),Json(vx)));assert c.fetchone()[0].get('code')=='unauthorized';c.execute("update public.pdc_user_roles set role='importer' where auth_user_id=%s",(actor,))
   dup_text=f'Stock {comm_stock}. Sublet booked 21/08/2026. Sublet booked 22/08/2026.';di,da,dp,dd=evidence('duplicate-actions',dup_text)
   dx={'actions':[{'source_action_no':1,'action_type':'set_sublet_booking_date','booking_date':'2026-08-21','evidence':'Sublet booked 21/08/2026'},{'source_action_no':2,'action_type':'set_sublet_booking_date','booking_date':'2026-08-22','evidence':'Sublet booked 22/08/2026'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':da,'canonical_document_hash':dd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(di,dp,sha(json.dumps(dx,sort_keys=True)),Json(dx)));assert c.fetchone()[0].get('code')=='communication_actions_invalid'
   forged_text=f'Stock {comm_stock}. Please inspect this vehicle.';gi,ga,gp,gd=evidence('forged-action',forged_text);gx=dict(vx);gx['canonical_attachment_id']=ga;gx['canonical_document_hash']=gd
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(gi,gp,sha(json.dumps(gx,sort_keys=True)),Json(gx)));assert c.fetchone()[0].get('code')=='communication_retained_text_mismatch'
   mismatch_vin='JH4KA8260MC000001';mi,ma,mp,md=evidence('identity-mismatch',f'Stock {comm_stock}. VIN {mismatch_vin}. Parts Complete.');mx=dict(vx);mx['canonical_attachment_id']=ma;mx['canonical_document_hash']=md;mx['identity']={'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[mismatch_vin]}
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(mi,mp,sha(json.dumps(mx,sort_keys=True)),Json(mx)));mismatch_result=c.fetchone()[0];assert mismatch_result.get('code')=='communication_vehicle_not_found',mismatch_result
   c.execute("update public.vehicle_work_items set completed=true,completed_by=%s,completed_at=clock_timestamp() where vehicle_id=%s and work_key='fitting'",(actor,vehicle));pi,pa,pp,pd=evidence('completed-work',f'Stock {comm_stock}. Please add long range tank to this job.');px={'actions':[{'source_action_no':1,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Please add long range tank to this job'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':pa,'canonical_document_hash':pd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(pi,pp,sha(json.dumps(px,sort_keys=True)),Json(px)));assert c.fetchone()[0].get('code')=='communication_completed_work_protected'

   # Complete-clause, whole-accessory and scalar-shape rejections are stable and mutation-free.
   ti,ta,tp,td=evidence('truncated-clause',f'Stock {comm_stock}. Parts Complete if the delivery arrives.')
   tx=dict(vx);tx['canonical_attachment_id']=ta;tx['canonical_document_hash']=td
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(ti,tp,sha(json.dumps(tx,sort_keys=True)),Json(tx)),'communication_retained_text_mismatch')
   qi,qa,qp,qd=evidence('compound-accessory',f'Stock {comm_stock}. Please add long range tank and snorkel to this job.')
   qx={'actions':[{'source_action_no':1,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Please add long range tank and snorkel to this job'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':qa,'canonical_document_hash':qd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[comm_stock],'vins':[]},'review_reasons':[]}
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(qi,qp,sha(json.dumps(qx,sort_keys=True)),Json(qx)),'communication_retained_text_mismatch')
   ui,ua,up,ud=evidence('malformed-shapes',f'Stock {comm_stock}. Parts Complete.')
   ux=dict(vx);ux['canonical_attachment_id']='not-a-uuid';ux['canonical_document_hash']=ud
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(ui,up,sha(json.dumps(ux,sort_keys=True)),Json(ux)),'invalid_communication_extraction')
   ux=dict(vx);ux['canonical_attachment_id']=ua;ux['canonical_document_hash']=ud;ux['actions']=[{'source_action_no':'1','action_type':'parts_complete','evidence':'Parts Complete'}]
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(ui,up,sha(json.dumps(ux,sort_keys=True)),Json(ux)),'communication_actions_invalid')

   # A late Sublet failure must roll back earlier Parts/accessory mutations and receipts.
   fail_stock='94'+non_stock[2:]
   c.execute("""insert into public.vehicles(permanent_vehicle_id,stock_number,job_card_number,lifecycle_state,visible_on_board,current_location,pmb_stage,source_payload,created_by,updated_by) values(%s,%s,%s,'active',true,'PMB','UNALLOCATED','{}',%s,%s) returning id::text,version""",(f'FIX-FAIL-{seq}',fail_stock,f'JC-FAIL-{seq}',actor,actor));fail_vehicle,fail_version=c.fetchone()
   fail_text=f'Stock {fail_stock}. Parts Complete. Add long range tank to this job. Sublet booked 22/08/2026.'
   fi,fa,fp,fd=evidence('atomic-fail',fail_text)
   fx={'actions':[{'source_action_no':1,'action_type':'parts_complete','evidence':'Parts Complete'},{'source_action_no':2,'action_type':'add_accessory_work','description':'Long range tank','work_key':'fitting','evidence':'Add long range tank to this job'},{'source_action_no':3,'action_type':'set_sublet_booking_date','booking_date':'2026-08-22','evidence':'Sublet booked 22/08/2026'}],'authentication':AUTH,'auto_applicable':True,'canonical_attachment_id':fa,'canonical_document_hash':fd,'contract_version':'pmb-email-communications-v1','identity':{'job_card_numbers':[],'stock_numbers':[fail_stock],'vins':[]},'review_reasons':[]}
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_email_communication(%s,%s,%s,%s,'pdc-monitor')",(fi,fp,sha(json.dumps(fx,sort_keys=True)),Json(fx)));fr=c.fetchone()[0];assert fr.get('ok') is False and fr.get('code')=='sublet_not_required',fr
   c.execute("select version from public.vehicles where id=%s",(fail_vehicle,));assert c.fetchone()[0]==fail_version
   c.execute("select count(*) from public.vehicle_work_items where vehicle_id=%s",(fail_vehicle,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_authenticated_email_operation_lines where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   c.execute("select count(*) from public.pdc_email_communication_receipts where source_hash=%s",(fp,));assert c.fetchone()[0]==0
   
   lines=[{'description':'Fit long range tank','estimated_hours':3.25,'operation_no':'OP1','source_row_no':1,'work_key':'fitting'},{'description':'Install UHF','estimated_hours':1.50,'operation_no':'OP2','source_row_no':2,'work_key':'electrical'}]
   non_job=f'JC-NV-{seq}'
   non_text=f'Stock {non_stock}. Job Card {non_job}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.'
   ni,na,np,nd=evidence('nonnav',non_text)
   nx={'authentication':AUTH,'canonical_attachment_id':na,'canonical_document_hash':nd,'contract_version':'pmb-email-work-v2','email_vehicle':{'cancelled':False,'conflicts':[],'customer_name':'Used Vehicle Customer','eta_to_kewdale':None,'job_card_number':non_job,'registration':'1ABC234','stock_numbers':[non_stock],'toyota_order_number':'','vehicle_description':'Nissan Patrol Used','vins':[]},'operation_lines':lines,'required_work':['electrical','fitting']}
   nxh=sha(json.dumps(nx,sort_keys=True));claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ni,np,nxh,Json(nx)));nr=ok(c.fetchone()[0],'non_navision_jobcard_receipt');ndat=nr['data'];assert ndat['vehicle_created'] is True and ndat['initial_location']=='PMB' and ndat['operation_count']==2,nr
   nv=ndat['vehicle_id'];c.execute("select current_location,visible_on_board,lifecycle_state,make,job_card_number from public.vehicles where id=%s",(nv,));nvrow=c.fetchone();assert nvrow==('PMB',True,'active','Nissan',f'JC-NV-{seq}'.upper()),nvrow
   c.execute("select array_agg(estimated_hours::text order by source_row_no),array_agg(estimated_hours_source order by source_row_no) from public.pdc_authenticated_email_operation_lines where vehicle_id=%s",(nv,));assert c.fetchone()==(['3.25','1.50'],['job_card','job_card'])
   c.execute('savepoint line_drift_probe')
   try:
    c.execute("update public.pdc_authenticated_email_operation_lines set description='tampered' where vehicle_id=%s and source_contract='pmb-non-navision-jobcard-161'",(nv,))
   except Exception:
    c.execute('rollback to savepoint line_drift_probe')
   else:
    raise AssertionError('immutable non-Navision source operation line accepted a drift update')
   c.execute('release savepoint line_drift_probe')
   c.execute("select count(*) from public.workshop_bookings where vehicle_id=%s",(nv,));assert c.fetchone()[0]==0
   c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ni,np,nxh,Json(nx)));nr2=ok(c.fetchone()[0],'non_navision_jobcard_receipt');assert nr2['data']['receipt_id']==ndat['receipt_id']
   c.execute("select count(*) from public.vehicles where stock_number_normalized=%s",(non_stock,));assert c.fetchone()[0]==1
   c.execute("select count(*) from public.pdc_authenticated_email_operation_lines where vehicle_id=%s",(nv,));assert c.fetchone()[0]==2
   c.execute("""select count(*),bool_and(parser_contract='pmb-email-work-v2/operation-line-v1'),
     bool_and(source_start>=0 and source_end>source_start and length(retained_source_text)>0)
     from public.pdc_non_navision_jobcard_source_row_receipts where receipt_id=%s""",(ndat['receipt_id'],));assert c.fetchone()==(2,True,True)

   # Swapped tuple members and malformed scalars are rejected before every operational delta.
   si,sa,sp,sd=evidence('swapped-hours',f'Stock 95{non_stock[2:]}. Job Card JC-SWAP-{seq}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.')
   sx=dict(nx);sx['canonical_attachment_id']=sa;sx['canonical_document_hash']=sd;sx['email_vehicle']=dict(nx['email_vehicle']);sx['email_vehicle']['stock_numbers']=['95'+non_stock[2:]];sx['email_vehicle']['job_card_number']=f'JC-SWAP-{seq}'
   sx['operation_lines']=[dict(lines[0],estimated_hours=1.50),dict(lines[1],estimated_hours=3.25)]
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(si,sp,sha(json.dumps(sx,sort_keys=True)),Json(sx)),'non_navision_retained_text_mismatch')
   wi,wa,wp,wd=evidence('swapped-work',f'Stock 96{non_stock[2:]}. Job Card JC-WORK-{seq}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.')
   wx=dict(nx);wx['canonical_attachment_id']=wa;wx['canonical_document_hash']=wd;wx['email_vehicle']=dict(nx['email_vehicle']);wx['email_vehicle']['stock_numbers']=['96'+non_stock[2:]];wx['email_vehicle']['job_card_number']=f'JC-WORK-{seq}'
   wx['operation_lines']=[dict(lines[0],work_key='electrical'),dict(lines[1],work_key='fitting')]
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(wi,wp,sha(json.dumps(wx,sort_keys=True)),Json(wx)),'non_navision_operation_lines_invalid')
   zi,za,zp,zd=evidence('malformed-nonnav',f'Stock 97{non_stock[2:]}. Job Card JC-SHAPE-{seq}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.')
   zx=dict(nx);zx['canonical_attachment_id']='bad-uuid';zx['canonical_document_hash']=zd;zx['email_vehicle']=dict(nx['email_vehicle']);zx['email_vehicle']['stock_numbers']=['97'+non_stock[2:]];zx['email_vehicle']['job_card_number']=f'JC-SHAPE-{seq}'
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(zi,zp,sha(json.dumps(zx,sort_keys=True)),Json(zx)),'invalid_non_navision_extraction')
   zx['canonical_attachment_id']=za;zx['operation_lines']=[dict(lines[0],source_row_no='1'),lines[1]]
   claims(c,'authenticated',actor,email);rejected_without_delta("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(zi,zp,sha(json.dumps(zx,sort_keys=True)),Json(zx)),'non_navision_operation_lines_invalid')

   # A current Navision stock is never allowed through the non-Navision fallback.
   c.execute("""select public.normalize_vehicle_stock_number(normalized_data->>'batch') from public.navision_backend_records where source_system='microsoft_navision' and dealer_code in('14450','37047') and is_current and record_status='current' and public.is_real_vehicle_stock_number(public.normalize_vehicle_stock_number(normalized_data->>'batch')) order by id limit 1""");canonical_stock=c.fetchone()[0]
   canonical_job=f'JC-CAN-{seq}'
   canonical_text=f'Stock {canonical_stock}. Job Card {canonical_job}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.'
   ci,ca,cp,cd=evidence('canonical-guard',canonical_text);cx=dict(nx);cx['canonical_attachment_id']=ca;cx['canonical_document_hash']=cd;cx['email_vehicle']=dict(nx['email_vehicle']);cx['email_vehicle']['job_card_number']=canonical_job;cx['email_vehicle']['stock_numbers']=[canonical_stock]
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(ci,cp,sha(json.dumps(cx,sort_keys=True)),Json(cx)));cr=c.fetchone()[0];assert cr.get('ok') is False and cr.get('code')=='navision_record_requires_canonical_path',cr
   c.execute("select count(*) from public.pdc_authenticated_email_import_receipts where source_hash=%s",(cp,));assert c.fetchone()[0]==0
   
   old_job=f'JC-OLD-{seq}';old_stock='93'+non_stock[2:]
   old_text=f'Stock {old_stock}. Job Card {old_job}. Fit long range tank 3.25 hours. Install UHF 1.5 hours.'
   old_i,old_a,old_p,old_d=evidence('stale',old_text,"clock_timestamp()-interval '31 days'")
   oldx=dict(nx);oldx['canonical_attachment_id']=old_a;oldx['canonical_document_hash']=old_d;oldx['email_vehicle']=dict(nx['email_vehicle']);oldx['email_vehicle']['job_card_number']=old_job;oldx['email_vehicle']['stock_numbers']=[old_stock]
   claims(c,'authenticated',actor,email);c.execute("select public.process_pdc_non_navision_jobcard(%s,%s,%s,%s,'pdc-monitor')",(old_i,old_p,sha('oldx'),Json(oldx)));oldr=c.fetchone()[0];assert oldr.get('ok') is False and oldr.get('code')=='non_navision_evidence_binding_failed',oldr
   c.execute("select count(*) from public.vehicles where stock_number_normalized=%s",(oldx['email_vehicle']['stock_numbers'][0],));assert c.fetchone()[0]==0
   print(json.dumps({'ok':True,'mode':'rollback_behavior','communication_actions':3,'parts_complete':True,'sublet_date':'2026-08-21','accessory_hours':'1.00','atomic_failure_rollback':True,'canonical_navision_guard':True,'non_navision_created_at':'PMB','non_navision_operations':2,'replay_safe':True,'stale_replay_safe':True,'stale_rejected':True,'retained_text_binding':True,'complete_clause_binding':True,'compound_accessory_rejected':True,'importer_only_mutation':True,'duplicate_actions_rejected':True,'completed_work_protected':True,'identity_agreement':True,'cross_family_single_use':True,'operation_lines_immutable':True,'atomic_source_coordinates':True,'swapped_hours_rejected':True,'swapped_work_keys_rejected':True,'malformed_scalars_stable':True,'rejection_zero_deltas':True,'bookings_created':0},sort_keys=True))
  con.rollback();return 0
 finally:
  con.rollback();con.close()
if __name__=='__main__':raise SystemExit(main())
