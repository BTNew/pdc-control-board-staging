"""Final read-only synthetic/protected inventory and duplicate proof."""
import hashlib, json, pathlib, time
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json
ROOT=pathlib.Path(__file__).resolve().parents[1]; OUT=ROOT/'_overnight_evidence'/'final-inventory.json'; REF='cdsmnqxtyyoeoznmbidd'; RUN='HERMES-TEST-RUN-20260824'
def digest(x): return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def main():
 e=env_values(); base=e['PDC_STAGING_SUPABASE_URL'].rstrip('/'); key=e['PDC_STAGING_ANON_KEY']
 if e.get('PDC_STAGING_PROJECT_REF')!=REF or REF not in base: raise RuntimeError('target guard')
 proof=prove_environment(); s,a=request_json(base+'/auth/v1/token?grant_type=password','POST',{'apikey':key,'Content-Type':'application/json'},{'email':e['PDC_STAGING_ADMIN2_EMAIL'],'password':e['PDC_STAGING_ADMIN2_PASSWORD']})
 if s!=200: raise RuntimeError('auth failed')
 h={'apikey':key,'Authorization':'Bearer '+a['access_token'],'Content-Type':'application/json'}; s,state=request_json(base+'/rest/v1/rpc/read_pdc_hermes_test_mutation_state_365','POST',h,{'p_run_id':RUN,'p_vehicle_id':None})
 if s!=200 or not state.get('ok') or state.get('notification_count')!=0: raise RuntimeError('read failed')
 rows=state['vehicles']; receipts=[x for r in rows for x in r['receipts']]; semantic={}; ids={}; stocks={}
 for r in rows:
  stocks[r['vehicle']['stock_number']]=stocks.get(r['vehicle']['stock_number'],0)+1
  for x in r['receipts']:
   k=(x.get('actor_id'),x.get('idempotency_key')); semantic[k]=semantic.get(k,0)+1; ids[x.get('receipt_id')]=ids.get(x.get('receipt_id'),0)+1
 duplicate_semantic=[list(k)+[n] for k,n in semantic.items() if n>1]; duplicate_ids=[[k,n] for k,n in ids.items() if n>1]; duplicate_stocks=[[k,n] for k,n in stocks.items() if n>1]
 if len(rows)!=20 or duplicate_semantic or duplicate_ids or duplicate_stocks: raise RuntimeError('duplicate/inventory acceptance failed')
 relation_counts={k:sum(len(r[k]) for r in rows) for k in ['work_items','bookings','booking_history','parts','sublets','sublet_history','movements','audit_events','receipts']}
 evidence={'schema':'pdc-overnight-final-inventory-v1','completed_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'environment':proof,'protected_state':state['protected_state'],'protected_state_digest':digest(state['protected_state']),'synthetic_state_digest':digest(rows),'synthetic_vehicle_count':len(rows),'stocks':sorted(stocks),'relation_counts':relation_counts,'duplicate_semantic_receipts':duplicate_semantic,'duplicate_receipt_ids':duplicate_ids,'duplicate_stocks':duplicate_stocks,'notifications':state['notification_count'],'scenario_inventory':[{'scenario':r['scenario_no'],'stock':r['vehicle']['stock_number'],'location':r['vehicle']['current_location'],'version':r['vehicle']['version'],'work_items':len(r['work_items']),'bookings':len(r['bookings']),'parts':len(r['parts']),'sublets':len(r['sublets']),'receipts':len(r['receipts'])} for r in rows]}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding='utf-8'); print(json.dumps({'protected_state':evidence['protected_state'],'synthetic_state_digest':evidence['synthetic_state_digest'],'relation_counts':relation_counts,'duplicate_semantic_receipts':0,'duplicate_receipt_ids':0,'duplicate_stocks':0,'notifications':0},indent=2))
if __name__=='__main__': main()
