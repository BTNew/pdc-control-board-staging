"""Exercise guarded Parts lifecycle, stoppage and recovery on scenarios 008-009."""
from __future__ import annotations
import datetime as dt, json, pathlib, uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT=pathlib.Path(__file__).resolve().parents[1]
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_parts_008_009.json"
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
  if s!=200 or x.get("ok") is not True or x.get("notification_count")!=0:raise RuntimeError(f"readback failed {s} {json.dumps(x)[:1000]}")
  return x
 fleet=read(); protected=fleet["protected_state"]
 rows={r["scenario_no"]:r for r in fleet["vehicles"] if r["scenario_no"] in (8,9)}
 if set(rows)!={8,9}:raise RuntimeError("scenario inventory mismatch")
 for no,row in rows.items():
  if row["vehicle"]["stock_number"]!=f"HERMES-TEST-{no:03d}":raise RuntimeError(f"scenario {no} identity mismatch")
 # A prior interrupted execution may already have committed the exact deterministic
 # 008 lifecycle and 009 direct-receipt transition.  Resume only from that known state.
 if len(rows[8]["parts"])!=3 or len(rows[8]["receipts"])!=4 or not rows[8]["parts"][-1].get("parts_received"):
  raise RuntimeError("scenario 008 exact interrupted-run state mismatch")
 if len(rows[9]["parts"])!=1 or len(rows[9]["receipts"])!=1 or not rows[9]["parts"][-1].get("parts_received"):
  raise RuntimeError("scenario 009 exact interrupted-run state mismatch")

 actions=[]
 def invoke(label,no,kind,action,*,eta=None,reason=None,expect_ok=True,expected_error=None,replay=True,changed_probe=False,stale_probe=False):
  before=read(rows[no]["vehicle"]["id"]); row=before["vehicles"][0]; vehicle=row["vehicle"]
  version=int(vehicle["version"]); before_parts=list(row["parts"]); before_receipts=list(row["receipts"])
  idem=str(uuid.uuid5(NAMESPACE,f"{RUN}:{label}"))
  if kind=="parts":
   name="pdc_hermes_test_parts_365";payload={"p_run_id":RUN,"p_vehicle_id":vehicle["id"],"p_expected_version":version,"p_idempotency_key":idem,"p_action":action,"p_worst_eta":eta}
  else:
   name="pdc_hermes_test_parts_stoppage_365";payload={"p_run_id":RUN,"p_vehicle_id":vehicle["id"],"p_expected_version":version,"p_idempotency_key":idem,"p_action":action,"p_reason":reason}
  pre=prove_environment();status,response=rpc(name,payload)
  if status!=200:raise RuntimeError(f"{label} transport failure {status} {json.dumps(response)[:1200]}")
  if response.get("ok") is not expect_ok:raise RuntimeError(f"{label} expected ok={expect_ok} {json.dumps(response)[:1200]}")
  if expected_error and expected_error not in json.dumps(response):raise RuntimeError(f"{label} missing expected error {expected_error}: {json.dumps(response)[:1200]}")
  if response.get("notification_delta")!=0:raise RuntimeError(f"{label} notification delta")
  after=read(vehicle["id"]); after_row=after["vehicles"][0]
  if after["protected_state"]!=protected:raise RuntimeError(f"{label} protected digest changed")
  if expect_ok:
   if len(after_row["parts"])!=len(before_parts)+1 or int(after_row["vehicle"]["version"])!=version+1:raise RuntimeError(f"{label} success postcondition")
  else:
   if len(after_row["parts"])!=len(before_parts) or int(after_row["vehicle"]["version"])!=version:raise RuntimeError(f"{label} rejection changed target")
  if len(after_row["receipts"])!=len(before_receipts)+1:raise RuntimeError(f"{label} receipt postcondition")
  if replay:
   prove_environment();rs,rr=rpc(name,payload);replay_state=read(vehicle["id"])["vehicles"][0]
   if rs!=200 or rr.get("replay") is not True or rr.get("replay_containment_verified") is not True or len(replay_state["parts"])!=len(after_row["parts"]) or len(replay_state["receipts"])!=len(after_row["receipts"]):raise RuntimeError(f"{label} replay failed {rs} {json.dumps(rr)[:1200]}")
  if changed_probe:
   changed=dict(payload)
   if kind=="parts" and action=="eta":changed["p_worst_eta"]="2026-08-30"
   elif kind=="stoppage":changed["p_reason"]="HERMES-TEST CHANGED STOPPAGE"
   else:raise RuntimeError("changed probe unsupported")
   prove_environment();cs,cr=rpc(name,changed)
   if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cr):raise RuntimeError(f"{label} changed replay not rejected {cs} {json.dumps(cr)[:1200]}")
  if stale_probe:
   stale=dict(payload);stale["p_idempotency_key"]=str(uuid.uuid5(NAMESPACE,f"{RUN}:{label}:stale"));stale["p_expected_version"]=version
   prove_environment();ss,sr=rpc(name,stale)
   if ss!=200 or sr.get("ok") is not False or "vehicle_version_conflict" not in json.dumps(sr):raise RuntimeError(f"{label} stale version not rejected {ss} {json.dumps(sr)[:1200]}")
   stale_after=read(vehicle["id"])["vehicles"][0]
   if len(stale_after["parts"])!=len(after_row["parts"]) or len(stale_after["receipts"])!=len(after_row["receipts"])+1:raise RuntimeError(f"{label} stale rejection postcondition")
  actions.append({"label":label,"scenario_no":no,"stock":vehicle["stock_number"],"kind":kind,"action":action,"expected_ok":expect_ok,"http_status":status,"receipt_id":response.get("receipt_id"),"vehicle_version_before":version,"vehicle_version_after":after_row["vehicle"]["version"],"parts_rows_before":len(before_parts),"parts_rows_after":len(after_row["parts"]),"replay_verified":replay,"changed_payload_rejected":changed_probe,"stale_version_rejected":stale_probe,"result":response.get("result"),"pre_action_migration_head":pre["database"]["migration_head"]})

 # Canonical Parts completion is deliberately receipt-driven and may validly occur
 # without a prior ordered state.  The interrupted run proved both normal 008
 # ETA->ordered->received and direct 009 receipt paths.  Continue with invalid
 # post-receipt ordering plus synthetic stoppage/recovery containment.
 invoke("scenario-009-ordered-after-received",9,"parts","ordered",expect_ok=False,expected_error="parts_already_received")
 invoke("scenario-009-stoppage-after-receipt",9,"stoppage","stoppage",reason="HERMES-TEST PARTS HOLD 009",changed_probe=True)
 invoke("scenario-009-complete-while-stopped-and-received",9,"parts","complete",expect_ok=False,expected_error="parts_already_received")
 invoke("scenario-009-recover",9,"stoppage","recover",stale_probe=True)
 final=read();final_proof=prove_environment()
 if final["protected_state"]!=protected or final["notification_count"]!=0:raise RuntimeError("final containment mismatch")
 evidence={"schema":"pdc-overnight-parts-008-009-v1","project_ref":REF,"run_id":RUN,"actor_id":session["user"]["id"],"initial_environment":initial_proof,"final_environment":final_proof,"protected_state":protected,"actions":actions,"successful_actions":sum(1 for a in actions if a["expected_ok"]),"authoritative_rejections":sum(1 for a in actions if not a["expected_ok"]),"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"PARTS_008_009_VERIFIED","successful_actions":evidence["successful_actions"],"authoritative_rejections":evidence["authoritative_rejections"],"replays":len(actions),"changed_payload_rejections":sum(1 for a in actions if a["changed_payload_rejected"]),"stale_version_rejections":sum(1 for a in actions if a["stale_version_rejected"]),"receipts":[a["receipt_id"] for a in actions],"notifications":final["notification_count"],"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__":main()
