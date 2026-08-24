"""Run the first registry-bound synthetic edit through live staging RPCs."""
from __future__ import annotations
import datetime as dt, json, pathlib, urllib.error, urllib.request, uuid

ROOT=pathlib.Path(__file__).resolve().parents[1]
ENV=pathlib.Path(r"C:\Users\nwmgr\AppData\Local\hermes\profiles\website-development-lead\.env")
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_scenario_001_edit.json"

def env_values():
 out={}
 for raw in ENV.read_text(encoding="utf-8-sig").splitlines():
  s=raw.strip()
  if s and not s.startswith("#") and "=" in s:
   k,v=s.split("=",1);out[k.strip()]=v.strip().strip("'\"")
 return out

def request_json(url,method,headers,body):
 req=urllib.request.Request(url,data=json.dumps(body).encode(),method=method,headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=120) as res:return res.status,json.load(res)
 except urllib.error.HTTPError as exc:
  return exc.code,json.loads(exc.read().decode("utf-8","replace"))

def main():
 e=env_values();base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/");key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base:raise RuntimeError("target guard failed")
 status,session=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if status!=200:raise RuntimeError("staging Administrator2 authentication failed")
 token=session["access_token"];user_id=session["user"]["id"]
 headers={"apikey":key,"Authorization":"Bearer "+token,"Content-Type":"application/json"}
 def rpc(name,payload):return request_json(base+"/rest/v1/rpc/"+name,"POST",headers,payload)
 status,before=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":None})
 if status!=200 or before.get("ok") is not True:raise RuntimeError(f"authenticated wrapper readback failed status={status} body={json.dumps(before)[:800]}")
 rows=before.get("vehicles") or [];row=next((x for x in rows if x.get("scenario_no")==1),None)
 if not row:raise RuntimeError("scenario 001 missing")
 vehicle=row["vehicle"];vehicle_id=vehicle["id"];version=int(vehicle["version"])
 if vehicle.get("stock_number")!="HERMES-TEST-001":raise RuntimeError("scenario 001 identity mismatch")
 idem=str(uuid.uuid5(uuid.UUID("36500000-0000-5000-8000-000000000365"),RUN+":scenario-001:key-tag-a"))
 payload={"p_run_id":RUN,"p_vehicle_id":vehicle_id,"p_expected_version":version,"p_idempotency_key":idem,"p_pmb_key_tag":"HERMES-TEST-KEY-001-A"}
 status,applied=rpc("pdc_hermes_test_vehicle_edit_365",payload)
 if status!=200 or applied.get("ok") is not True or applied.get("replay") is not False:raise RuntimeError(f"scenario 001 Apply failed status={status} body={json.dumps(applied)[:1200]}")
 if applied.get("notification_delta")!=0:raise RuntimeError("unexpected notification delta")
 status,replayed=rpc("pdc_hermes_test_vehicle_edit_365",payload)
 if status!=200 or replayed.get("ok") is not True or replayed.get("replay") is not True or replayed.get("replay_containment_verified") is not True:raise RuntimeError("scenario 001 replay failed")
 changed=dict(payload);changed["p_pmb_key_tag"]="HERMES-TEST-KEY-001-CHANGED"
 mismatch_status,mismatch=rpc("pdc_hermes_test_vehicle_edit_365",changed)
 if mismatch_status<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(mismatch):raise RuntimeError("changed replay was not rejected")
 status,after=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vehicle_id})
 if status!=200 or after.get("ok") is not True or after.get("notification_count")!=0:raise RuntimeError("post-edit readback failed")
 after_row=(after.get("vehicles") or [None])[0]
 if not after_row or after_row["vehicle"].get("pmb_key_tag")!="HERMES-TEST-KEY-001-A":raise RuntimeError("edited key tag not authoritative")
 if len(after_row.get("receipts") or [])!=1:raise RuntimeError("unexpected scenario receipt count")
 # Prove this run's exact actor cannot bypass the bounded façade through a legacy core.
 states={"bus4x4":"none","tint":"none","hoist":"required","fitting":"none","fabrication":"none","electrical":"none","tyre":"none","pitInspection":"none","sublet":"none","parts":"none"}
 direct_status,direct=rpc("set_pdc_vehicle_work_states",{"p_vehicle_id":vehicle_id,"p_expected_version":int(after_row["vehicle"]["version"]),"p_work_states":states})
 if direct_status<400 or "PDC_365_OVERNIGHT_ACTOR_MUST_USE_EXACT_SYNTHETIC_WRAPPER" not in json.dumps(direct):raise RuntimeError("legacy direct-core bypass was not blocked")
 status,final=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vehicle_id})
 if status!=200 or final.get("vehicles",[{}])[0].get("vehicle",{}).get("version")!=after_row["vehicle"]["version"]:raise RuntimeError("negative direct-core probe changed state")
 evidence={"schema":"pdc-overnight-scenario-001-edit-v1","project_ref":REF,"run_id":RUN,"scenario_no":1,"stock":"HERMES-TEST-001","vehicle_id":vehicle_id,"actor_id":user_id,"idempotency_key":idem,"receipt_id":applied.get("receipt_id"),"request_sha256":applied.get("request_sha256"),"vehicle_version_before":version,"vehicle_version_after":after_row["vehicle"]["version"],"pmb_key_tag":after_row["vehicle"]["pmb_key_tag"],"apply_ok":True,"replay_ok":True,"changed_replay_rejected":True,"legacy_direct_core_rejected":True,"notification_count":final.get("notification_count"),"protected_state":applied.get("protected_state"),"sibling_state":applied.get("sibling_state"),"revisions":applied.get("revisions"),"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"SCENARIO_001_EDIT_VERIFIED","project_ref":REF,"stock":"HERMES-TEST-001","receipt_id":evidence["receipt_id"],"vehicle_version_before":version,"vehicle_version_after":evidence["vehicle_version_after"],"replay":True,"changed_replay_rejected":True,"legacy_direct_core_rejected":True,"notifications":evidence["notification_count"],"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__":main()
