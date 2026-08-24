"""Exercise exact-minute scheduling and authoritative conflicts on scenarios 005-007."""
from __future__ import annotations
import datetime as dt, json, pathlib, urllib.error, urllib.request, uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT=pathlib.Path(__file__).resolve().parents[1]
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_workshop_005_007.json"
NAMESPACE=uuid.UUID("36500000-0000-5000-8000-000000000365")

def main():
 e=env_values();base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/");key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base:raise RuntimeError("target guard failed")
 initial_proof=prove_environment()
 status,session=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if status!=200:raise RuntimeError("staging Administrator2 authentication failed")
 headers={"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(name,payload):return request_json(base+"/rest/v1/rpc/"+name,"POST",headers,payload)
 def read(vehicle_id=None):
  s,x=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vehicle_id})
  if s!=200 or x.get("ok") is not True or x.get("notification_count")!=0:raise RuntimeError(f"readback failed {s} {json.dumps(x)[:800]}")
  return x
 fleet=read();protected=fleet["protected_state"]
 rows={r["scenario_no"]:r for r in fleet["vehicles"] if r["scenario_no"] in (5,6,7)}
 if set(rows)!={5,6,7}:raise RuntimeError("scenario inventory mismatch")
 for no,row in rows.items():
  if row["vehicle"]["stock_number"]!=f"HERMES-TEST-{no:03d}" or row["vehicle"]["current_location"]!="PMB" or row["bookings"]:raise RuntimeError(f"scenario {no} precondition mismatch")
 results=[]
 def schedule(label,scenario_no,stage,bay,start,duration,expect_success,conflict_kind=None):
  state=read(rows[scenario_no]["vehicle"]["id"]);row=state["vehicles"][0];vehicle=row["vehicle"]
  version=int(vehicle["version"]);before_bookings=list(row.get("bookings") or []);before_receipts=list(row.get("receipts") or [])
  idem=str(uuid.uuid5(NAMESPACE,RUN+":"+label))
  payload={"p_run_id":RUN,"p_vehicle_id":vehicle["id"],"p_expected_version":version,"p_idempotency_key":idem,
   "p_stage_code":stage,"p_bay_number":bay,"p_scheduled_start_at":start,"p_duration_minutes":duration,"p_technician_id":None,"p_override_reason":None}
  pre=prove_environment();status,response=rpc("pdc_hermes_test_schedule_365",payload)
  if status!=200 or response.get("replay") is not False or response.get("notification_delta")!=0:raise RuntimeError(f"{label} wrapper failure {status} {json.dumps(response)[:1200]}")
  after=read(vehicle["id"]);after_row=after["vehicles"][0]
  if after.get("protected_state")!=protected:raise RuntimeError(f"{label} protected digest changed")
  if expect_success:
   if response.get("ok") is not True or len(after_row["bookings"])!=len(before_bookings)+1 or int(after_row["vehicle"]["version"])!=version+1:raise RuntimeError(f"{label} success postcondition {json.dumps(response)[:1200]}")
   matches=[b for b in after_row["bookings"] if str(b.get("stage_code")).upper()==stage and int(b.get("bay_number"))==bay and b.get("scheduled_start_at")==start]
   if len(matches)!=1:raise RuntimeError(f"{label} exact-minute booking missing: {json.dumps(after_row['bookings'])[:1200]}")
   booking=matches[0]
   start_dt=dt.datetime.fromisoformat(start.replace("Z","+00:00"));expected_end=(start_dt+dt.timedelta(minutes=duration)).isoformat().replace("+00:00","+00:00")
   actual_end=str(booking.get("scheduled_end_at") or "")
   if dt.datetime.fromisoformat(actual_end.replace("Z","+00:00"))!=start_dt+dt.timedelta(minutes=duration):raise RuntimeError(f"{label} exact duration mismatch")
  else:
   text=json.dumps(response).lower()
   if response.get("ok") is not False or "conflict" not in text or (conflict_kind and conflict_kind not in text):raise RuntimeError(f"{label} conflict not enforced {json.dumps(response)[:1200]}")
   if len(after_row["bookings"])!=len(before_bookings) or int(after_row["vehicle"]["version"])!=version:raise RuntimeError(f"{label} rejected action changed target")
   booking=None
  if len(after_row["receipts"])!=len(before_receipts)+1:raise RuntimeError(f"{label} receipt count mismatch")
  replay_status,replay=rpc("pdc_hermes_test_schedule_365",payload)
  replay_state=read(vehicle["id"]);replay_row=replay_state["vehicles"][0]
  if replay_status!=200 or replay.get("replay") is not True or replay.get("replay_containment_verified") is not True or len(replay_row["bookings"])!=len(after_row["bookings"]) or len(replay_row["receipts"])!=len(after_row["receipts"]):raise RuntimeError(f"{label} replay mismatch")
  results.append({"label":label,"scenario_no":scenario_no,"stock":vehicle["stock_number"],"stage_code":stage,"bay_number":bay,"scheduled_start_at":start,"duration_minutes":duration,"expected_success":expect_success,"conflict_kind":conflict_kind,"receipt_id":response.get("receipt_id"),"booking_id":booking.get("id") if booking else None,"vehicle_version_before":version,"vehicle_version_after":after_row["vehicle"]["version"],"result":response.get("result"),"revisions":response.get("revisions"),"protected_state":response.get("protected_state"),"sibling_state":response.get("sibling_state"),"pre_action_migration_head":pre["database"]["migration_head"],"replay_verified":True})
  return after_row
 # Arbitrary minute starts/durations prove minute precision rather than rounded slots.
 schedule("scenario-005-fitting-0907",5,"FITTING",5,"2026-08-26T01:07:00+00:00",73,True)
 schedule("scenario-006-electrical-0911",6,"ELECTRICAL",10,"2026-08-26T01:11:00+00:00",61,True)
 # Same physical bay overlap must reject even for another synthetic vehicle.
 schedule("scenario-007-fitting-bay-conflict",7,"FITTING",5,"2026-08-26T01:30:00+00:00",30,False,"bay")
 schedule("scenario-007-fitting-1023",7,"FITTING",4,"2026-08-26T02:23:00+00:00",47,True)
 # A different station cannot overlap another active booking for the same vehicle.
 schedule("scenario-007-vehicle-conflict",7,"ELECTRICAL",10,"2026-08-26T02:30:00+00:00",30,False,"vehicle")
 # Exact end/start adjacency is permitted and retains minute precision.
 schedule("scenario-007-electrical-adjacent-1110",7,"ELECTRICAL",10,"2026-08-26T03:10:00+00:00",59,True)
 final=read();final_proof=prove_environment()
 if final["protected_state"]!=protected or final["notification_count"]!=0:raise RuntimeError("final containment mismatch")
 evidence={"schema":"pdc-overnight-workshop-005-007-v1","project_ref":REF,"run_id":RUN,"actor_id":session["user"]["id"],"initial_environment":initial_proof,"final_environment":final_proof,"protected_state":protected,"actions":results,"successful_bookings":sum(1 for r in results if r["expected_success"]),"authoritative_conflicts":sum(1 for r in results if not r["expected_success"]),"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"WORKSHOP_005_007_VERIFIED","successful_bookings":evidence["successful_bookings"],"authoritative_conflicts":evidence["authoritative_conflicts"],"receipts":[r["receipt_id"] for r in results],"notifications":final["notification_count"],"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__":main()
