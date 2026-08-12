import json, os, sys
from pathlib import Path
import psycopg2

ROOT=Path(__file__).resolve().parents[1]
MIG=ROOT/'supabase/staging_only/212_retained_uid_1477_recreation_import.sql'
UID='1:477'; SOURCE='971afa06b68bb54a94316a8d14fc3a6bf95d3eb8364d50a366add8cf7e6ee7cb'; ATTACHMENT='9ab13a8a43200ad32470b06406e1a1c7c53d85dc8f9e3b1d9ba3fe21170aabcd'
STOCK='13047224'; JC='J139125358'; VIN='MR0PEBHV600404885'
IMPORTER=('519126fa-0f97-43df-895b-3a950d51ac6f','viewer@staging.pdc-workshop.example.com')
DENIED=[
 ('7d3b3458-32c7-457b-9260-afa57d548f00','pdc.ai.auditor.staging@pmb.local'),
 ('b7e467b5-f3a1-44b9-a615-8ec618643b6d','pdc.email.monitor.staging@pmb.local'),
 ('4931987b-a7d8-46a2-81f6-1fdd51c2c2f3','unapproved@staging.pdc-workshop.example.com'),
 ('6c2c4e7d-c530-495d-8b6a-0850631d8086','controllerb@staging.pdc-workshop.example.com')]
OPS=[
{'source_row_no':1,'operation_no':'OP1','work_key':'electrical','description':'LIGHT BAR - LED DRIVING LIGHT BAR SPOT BEAM 9800 LUME','estimated_hours':1.00},
{'source_row_no':2,'operation_no':'OP2','work_key':'hoist','description':'LONG RANGE FUEL TANK','estimated_hours':1.50},
{'source_row_no':3,'operation_no':'OP3','work_key':'fitting','description':'FRONT CANVAS SEAT COVERS - BROOME TO SUPPLY','estimated_hours':0.50},
{'source_row_no':4,'operation_no':'OP4','work_key':'fitting','description':'REAR CANVAS SEAT COVER - BROOME TO SUPPLY','estimated_hours':0.50},
{'source_row_no':5,'operation_no':'OP5','work_key':'fitting','description':'SIDE STEPS - HEAVY DUTY - MATTE - BROOME TO SUPPLY','estimated_hours':0.72},
{'source_row_no':6,'operation_no':'OP6','work_key':'fitting','description':'STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY','estimated_hours':6.50},
{'source_row_no':7,'operation_no':'OP7','work_key':'tyre','description':'ADDITIONAL TYRE - PMG TO SUPPLY MATCHING EX SALES STOCK','estimated_hours':0.20},
{'source_row_no':8,'operation_no':'OP8','work_key':'pitInspection','description':'Fill with Fuel','estimated_hours':0.00},
{'source_row_no':9,'operation_no':'OP9','work_key':'fitting','description':'Complete Pre-Delivery Inspection','estimated_hours':0.10},
{'source_row_no':10,'operation_no':'OP10','work_key':'tyre','description':'TYRE UPGRADE - BFG KO3 A/T X 6','estimated_hours':1.20},
{'source_row_no':11,'operation_no':'OP11','work_key':'electrical','description':'MOBILE PHONE CRADLE WITH AERIAL TO SUIT IPHONE 13','estimated_hours':1.00},
{'source_row_no':12,'operation_no':'OP12','work_key':'fitting','description':'SJOG FIRST AID KIT - OFF ROAD 7027 WITH SNAKE BITE BANDAGE','estimated_hours':0.05},
{'source_row_no':13,'operation_no':'OP13','work_key':'fitting','description':'Safety Triangle Kit left Loose in Vehicle','estimated_hours':0.05}]

def claims(q,user):
    q.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':user[0],'role':'authenticated','email':user[1]}),))

def call(q):
    q.execute("select public.import_pdc_retained_reset_jobcard_212(%s,%s,%s,%s,%s,%s,%s::jsonb)",(UID,SOURCE,ATTACHMENT,STOCK,JC,VIN,json.dumps(OPS)))
    return q.fetchone()[0]

def main():
    url=os.environ.get('PDC_STAGING_DIRECT_DATABASE_URL') or os.environ['PDC_STAGING_DATABASE_URL']
    install='--installed' in sys.argv
    sql=MIG.read_text()
    if not install: sql=sql.rstrip()[:-7]
    with psycopg2.connect(url) as c:
      with c.cursor() as q:
        if not install: q.execute(sql)
        for denied in DENIED:
          claims(q,denied); result=call(q); assert result['code']=='importer_required',(denied,result)
          try:
            q.execute("select * from public.get_pdc_retained_reset_binding_212(%s)",(STOCK,))
            raise AssertionError(('reader_allowed',denied))
          except psycopg2.errors.InsufficientPrivilege:
            c.rollback();
            if not install:q.execute(sql)
        claims(q,IMPORTER)
        q.execute("select stock_number,tombstone_kind,grant_exists,grant_unused from public.get_pdc_retained_reset_binding_212(%s)",(STOCK,)); before=q.fetchone();assert before==(STOCK,'staging_reset',False,False),before
        first=call(q); assert first['ok'],first
        second=call(q); assert second==first,(first,second)
        vehicle=first['data']['vehicle_id']; receipt=first['data']['receipt_id']
        q.execute("select count(*),min(job_card_number),min(vin) from vehicles where stock_number=%s and visible_on_board and lifecycle_state='active'",(STOCK,)); assert q.fetchone()==(1,JC,VIN)
        q.execute("select count(*),count(distinct operation_no),sum(estimated_hours)::text from pdc_authenticated_email_operation_lines where vehicle_id=%s",(vehicle,)); actual=q.fetchone(); assert actual==(13,13,'13.32'),actual
        q.execute("select work_key,sum(estimated_hours)::text from pdc_authenticated_email_operation_lines where vehicle_id=%s group by work_key order by work_key",(vehicle,)); totals=dict(q.fetchall()); assert totals=={'electrical':'2.00','fitting':'8.42','hoist':'1.50','pitInspection':'0.00','tyre':'1.40'},totals
        q.execute("select count(*) from pdc_vehicle_recreation_permissions where normalized_stock=%s and consumed_at is not null",(STOCK,)); assert q.fetchone()[0]==1
        q.execute("select count(*) from pdc_vehicle_lifecycle_events where normalized_stock=%s and event_kind='recreation_consumed'",(STOCK,)); actual=q.fetchone()[0]; assert actual==1,actual
        q.execute("select count(*) from pdc_retained_reset_import_receipts_212 where receipt_id=%s",(receipt,)); assert q.fetchone()[0]==1
        q.execute("select (select count(*) from workshop_bookings where vehicle_id=%s)+(select count(*) from pdc_sublet_bookings where vehicle_id=%s)",(vehicle,vehicle)); assert q.fetchone()[0]==0
        if not install:q.execute('rollback')
        print(json.dumps({'first':first,'second':second,'totals':totals},default=str))
if __name__=='__main__':main()
