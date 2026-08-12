#!/usr/bin/env python
import json,os,psycopg2

def claims(q,row):q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':row[0],'role':'authenticated','email':row[1]}),))
def main():
 u=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ['PDC_STAGING_DATABASE_URL']
 with psycopg2.connect(u) as c:
  c.autocommit=False
  with c.cursor() as q:
   q.execute("select public.pdc_monitor_staging_guard(),(select max(version::int) from supabase_migrations.schema_migrations where version~'^[0-9]+$'),to_regclass('public.pdc_production_environment_sentinel')");assert q.fetchone()==(True,222,None)
   q.execute("select auth_user_id::text,lower(email) from public.pdc_user_roles where role='administrator' and lower(email)='craig.watson@broometoyota.com.au'");craig=q.fetchone();claims(q,craig)
   # Simulate a fresh bot process by persisting through the database command RPC,
   # then discarding all local state and reading the new row back.
   ev={'original_instruction':'Learn OP17 should be 6.5 hours.','telegram_sender_id':7828138290,'telegram_chat_id':7828138290,'telegram_message_id':999993}
   params={'scope':{'operation_code':'OP17','operation_description':'OP17 test recovery points','current_mapping':None},'target_mapping':'fitting','estimated_hours':6.5,'pricing':None,'reason':'restart persistence acceptance'}
   q.execute("select public.execute_pdc_supervised_learning_command('propose_lesson',%s::jsonb,%s::jsonb)",(json.dumps(params),json.dumps(ev)));created=q.fetchone()[0];assert created['ok'],created
   lesson=created['data']['version_id'];q.execute("select public.execute_pdc_supervised_learning_command('activate_future',%s::jsonb,%s::jsonb)",(json.dumps({'lesson_id':lesson}),json.dumps(ev|{'telegram_message_id':999994,'original_instruction':'Apply this lesson to future jobs'})));assert q.fetchone()[0]['ok']
   q.execute("select estimated_hours from public.pdc_supervised_rule_versions where version_id=%s",(lesson,));assert float(q.fetchone()[0])==6.5
   # Fresh monitor identity applies the later job-card operation and records receipt.
   q.execute("select r.auth_user_id::text,lower(r.email) from public.pdc_user_roles r join public.pdc_monitor_stage_activation_writers w on w.user_id=r.auth_user_id where lower(r.email)='pdc.email.monitor.staging@pmb.local' and w.active and w.revoked_at is null");monitor=q.fetchone();claims(q,monitor)
   scope={'operation_code':'OP17','operation_description':'OP17 test recovery points','current_mapping':'fitting'}
   q.execute("select public.read_pdc_supervised_learning_rule(%s::jsonb)",(json.dumps(scope),));read=q.fetchone()[0];assert read['data']['matched'] and read['data']['rule']['version']==1,read
   resolution={'target_mapping':'fitting','estimated_hours':str(read['data']['rule']['estimated_hours']),'pricing':None,'display_description':'OP17 test recovery points','jc_metadata':{'original_operation_description':'JC-123: OP17 test recovery points','jc_prefix_stripped':True}}
   q.execute("select public.apply_pdc_supervised_learning_rule(%s::jsonb,%s,1,%s::jsonb)",(json.dumps(scope),lesson,json.dumps(resolution)));applied=q.fetchone()[0];assert applied['ok'],applied
   wrong_scope={'operation_code':'UNRELATED-220','operation_description':'unrelated operation','current_mapping':'fitting'}
   q.execute("select public.apply_pdc_supervised_learning_rule(%s::jsonb,%s,1,%s::jsonb)",(json.dumps(wrong_scope),lesson,json.dumps(resolution)));assert q.fetchone()[0]['code']=='conflict'

   # Manual/protected batch behavior already left two protected lines and eight applied.
   q.execute("select batch_id from public.pdc_supervised_correction_batches where idempotency_key='migration-213-authorised-exact-active-lines'");batch=q.fetchone()[0]
   q.execute("select outcome,count(*) from public.pdc_supervised_apply_receipts where batch_id=%s and outcome in('applied','protected') group by outcome",(batch,));out=dict(q.fetchall());assert out.get('applied')==8 and out.get('protected')==2,out
   # Administrator undo and re-apply are both exact and reversible.
   claims(q,craig);q.execute("select public.undo_pdc_supervised_correction_batch_213(%s,'acceptance undo')",(batch,));undo=q.fetchone()[0];assert undo['data']['undone']==8,undo
   q.execute("select public.apply_pdc_supervised_correction_batch_213(%s)",(batch,));redo=q.fetchone()[0];assert redo['data']['applied']==8 and redo['data']['skipped']==2,redo
   q.execute('rollback')
 print(json.dumps({'restart_persisted':True,'later_email_applied':True,'protected':2,'undo':8,'reapply':8}))
if __name__=='__main__':main()
