"""Rollback-only staging proof for migration 043 on the applied migration-042 baseline."""
import json,os,pathlib,uuid
from datetime import date,timedelta,datetime,timezone
import psycopg2,psycopg2.extras
psycopg2.extras.register_uuid()
ROOT=pathlib.Path(__file__).resolve().parents[1]
SQL=(ROOT/'supabase/migrations/043_all_station_review_closure.sql').read_text(encoding='utf-8')
ALIASES={
 'BUS_4X4':['BUS4X4','4X4BUS','DEPARTMENT138','DEPT138'],'TINT':['TINT','TINTING','WINDOWTINT'],
 'HOIST':['HOIST','PITSHOIST','PITHOIST','EXPRESSHOIST'],'FITTING':['FITTING','FITMENT','FITOUT','EXPRESSFITOUT'],
 'FABRICATION':['FABRICATION','FAB','FABRICATING'],'ELECTRICAL':['ELECTRICAL','ELEC','AUTOELECTRICAL','AUTOELEC'],
 'TYRE':['TYRE','TYRES','TYREBAY','TIRE','TIREBAY'],'PIT_INSPECTION':['PITINSPECTION','PIT','INSPECTION'],
 'SUBLET':['SUBLET','OUTSOURCE','OUTSOURCED','EXTERNAL']}
conn=psycopg2.connect(os.environ['PDC_STAGING_DATABASE_URL']); conn.autocommit=False; q=conn.cursor()
try:
 q.execute(SQL)
 for stage,aliases in ALIASES.items():
  q.execute('select alias_normalized from public.workshop_stage_aliases where stage_code=%s',(stage,)); actual={r[0] for r in q.fetchall()}
  assert set(aliases)<=actual,(stage,set(aliases)-actual)
 admin_email=os.environ['PDC_STAGING_ADMIN_EMAIL'].lower(); q.execute('select id from auth.users where lower(email)=%s',(admin_email,)); admin=q.fetchone()[0]
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 vehicle=uuid.uuid4(); stock='FIX043-'+uuid.uuid4().hex[:10].upper()
 q.execute("insert into public.vehicles(id,permanent_vehicle_id,stock_number,current_location,pmb_stage,visible_on_board,version,lifecycle_state,updated_by) values(%s,%s,%s,'YH','UNALLOCATED',false,1,'active',%s)",(vehicle,uuid.uuid4(),stock,admin))
 start=datetime.combine(date.today()+timedelta(days=1),datetime.min.time(),tzinfo=timezone.utc)+timedelta(hours=1)
 q.execute("select public.schedule_vehicle_work(%s,1,'BUS_4X4',1,%s,60,null,null,'{}'::jsonb)",(vehicle,start)); result=q.fetchone()[0]; assert result['ok'] is True,result
 q.execute('select current_location,pmb_stage,visible_on_board from public.vehicles where id=%s',(vehicle,)); assert q.fetchone()==('YH','UNALLOCATED',False)
 importer='fixture-importer-'+uuid.uuid4().hex+'@example.invalid'; q.execute("insert into public.pdc_user_roles(email,display_name,role,active) values(%s,'Fixture Importer','importer',true)",(importer,))
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(uuid.uuid4()),'email':importer,'role':'authenticated'}),))
 q.execute('savepoint importer_denied')
 try:
  q.execute('select public.get_workshop_eligibility_snapshot()'); raise AssertionError('importer read unexpectedly allowed')
 except psycopg2.Error as e:
  assert e.pgcode=='42501',e; q.execute('rollback to savepoint importer_denied')
 q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':str(admin),'email':admin_email,'role':'authenticated'}),))
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); before=q.fetchone()[0]
 q.execute("insert into public.workshop_stage_aliases(alias_normalized,alias_value,stage_code) values(%s,%s,'HOIST')",('FIXTUREALIAS'+uuid.uuid4().hex.upper(),'Fixture Alias'))
 q.execute("select revision from public.workshop_station_revision where stage_code='HOIST'"); assert q.fetchone()[0]>before
 q.execute("select public.get_station_workshop_snapshot('Pits Hoist',current_date,current_date)"); assert q.fetchone()[0]['stage']=='HOIST'
 print(json.dumps({'migration_043_transactional':True,'yh_without_eta_scheduled':True,'location_stage_visibility_unchanged':True,'importer_denied':True,'alias_parity':sum(map(len,ALIASES.values())),'config_revision_bumped':True,'rolled_back':True}))
finally:
 conn.rollback(); conn.close()
