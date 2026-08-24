"""Resume exact Parts stress after the deliberately interrupted negative probe."""
from __future__ import annotations
import datetime as dt,json,pathlib,uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values,prove_environment,request_json
ROOT=pathlib.Path(__file__).resolve().parents[1];REF="cdsmnqxtyyoeoznmbidd";RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_parts_008_009.json";NS=uuid.UUID("36500000-0000-5000-8000-000000000365")
def main():
 e=env_values();base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/");key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base:raise RuntimeError("target guard")
 initial=prove_environment();s,session=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if s!=200:raise RuntimeError("auth failed")
 headers={"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(n,p):return request_json(base+"/rest/v1/rpc/"+n,"POST",headers,p)
 def read(vid=None):
  s,x=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vid})
  if s!=200 or x.get("ok") is not True or x.get("notification_count")!=0:raise RuntimeError(f"read failed {s}")
  return x
 fleet=read();protected=fleet["protected_state"];rows={r["scenario_no"]:r for r in fleet["vehicles"] if r["scenario_no"] in(8,9)}
 if set(rows)!={8,9} or len(rows[8]["parts"])!=3 or len(rows[9]["parts"])!=1:raise RuntimeError("exact resume parts state mismatch")
 if not rows[8]["parts"][-1].get("parts_received") or not rows[9]["parts"][-1].get("parts_received"):raise RuntimeError("receipt state mismatch")
 # Confirm the already-committed invalid post-receipt ordering rejection by its deterministic receipt.
 order_key=str(uuid.uuid5(NS,f"{RUN}:scenario-009-ordered-after-received"));order_receipts=[r for r in rows[9]["receipts"] if r.get("idempotency_key")==order_key]
 if len(order_receipts)!=1 or "parts_already_ordered" not in json.dumps(order_receipts[0]):raise RuntimeError("ordering rejection receipt mismatch")
 actions=[]
 def act(label,action,reason=None,expect_ok=True,error=None,changed=False,stale=False):
  before=read(rows[9]["vehicle"]["id"]);r=before["vehicles"][0];v=r["vehicle"];version=int(v["version"]);bp=len(r["parts"]);br=len(r["receipts"])
  keyid=str(uuid.uuid5(NS,f"{RUN}:{label}"));name="pdc_hermes_test_parts_stoppage_365" if action in("stoppage","recover") else "pdc_hermes_test_parts_365"
  payload={"p_run_id":RUN,"p_vehicle_id":v["id"],"p_expected_version":version,"p_idempotency_key":keyid,"p_action":action}
  if name.endswith("stoppage_365"):payload["p_reason"]=reason
  else:payload["p_worst_eta"]=None
  proof=prove_environment();s,x=rpc(name,payload)
  if s!=200 or x.get("ok") is not expect_ok or (error and error not in json.dumps(x)) or x.get("notification_delta")!=0:raise RuntimeError(f"{label} failed {s} {json.dumps(x)[:1200]}")
  after=read(v["id"]);ar=after["vehicles"][0]
  if after["protected_state"]!=protected or len(ar["receipts"])!=br+1:raise RuntimeError(f"{label} receipt/containment")
  if expect_ok and (len(ar["parts"])!=bp+1 or int(ar["vehicle"]["version"])!=version+1):raise RuntimeError(f"{label} success state")
  if not expect_ok and (len(ar["parts"])!=bp or int(ar["vehicle"]["version"])!=version):raise RuntimeError(f"{label} rejection state")
  prove_environment();rs,rx=rpc(name,payload);rr=read(v["id"])["vehicles"][0]
  if rs!=200 or rx.get("replay") is not True or len(rr["receipts"])!=len(ar["receipts"]) or len(rr["parts"])!=len(ar["parts"]):raise RuntimeError(f"{label} replay")
  if changed:
   cp=dict(payload);cp["p_reason"]="HERMES-TEST CHANGED PARTS HOLD 009";prove_environment();cs,cx=rpc(name,cp)
   if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cx):raise RuntimeError(f"{label} changed payload")
  if stale:
   sp=dict(payload);sp["p_idempotency_key"]=str(uuid.uuid5(NS,f"{RUN}:{label}:stale"));sp["p_expected_version"]=version;prove_environment();ss,sx=rpc(name,sp)
   if ss!=200 or sx.get("ok") is not False or "vehicle_version_conflict" not in json.dumps(sx):raise RuntimeError(f"{label} stale")
   sr=read(v["id"])["vehicles"][0]
   if len(sr["parts"])!=len(ar["parts"]) or len(sr["receipts"])!=len(ar["receipts"])+1:raise RuntimeError(f"{label} stale state")
  actions.append({"label":label,"action":action,"expected_ok":expect_ok,"receipt_id":x.get("receipt_id"),"vehicle_version_before":version,"vehicle_version_after":ar["vehicle"]["version"],"parts_rows_before":bp,"parts_rows_after":len(ar["parts"]),"replay_verified":True,"changed_payload_rejected":changed,"stale_version_rejected":stale,"result":x.get("result"),"pre_action_migration_head":proof["database"]["migration_head"]})
 act("scenario-009-stoppage-after-receipt","stoppage","HERMES-TEST PARTS HOLD 009",changed=True)
 act("scenario-009-complete-while-stopped-and-received","complete",expect_ok=False,error="parts_already_received")
 act("scenario-009-recover","recover",stale=True)
 final=read();proof=prove_environment();r9=next(r for r in final["vehicles"] if r["scenario_no"]==9)
 latest=r9["parts"][-1]
 if final["protected_state"]!=protected or latest.get("parts_stoppage") or not latest.get("parts_received"):raise RuntimeError("final recovery mismatch")
 evidence={"schema":"pdc-overnight-parts-008-009-v2","project_ref":REF,"run_id":RUN,"actor_id":session["user"]["id"],"initial_environment":initial,"final_environment":proof,"protected_state":protected,"scenario_008":{"parts_rows":len(next(r for r in final["vehicles"] if r["scenario_no"]==8)["parts"]),"lifecycle":"eta_ordered_received"},"scenario_009":{"parts_rows":len(r9["parts"]),"lifecycle":"direct_receipt_stoppage_recovery","ordering_rejection":"parts_already_ordered"},"actions":actions,"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"PARTS_008_009_VERIFIED","normal_lifecycle":True,"direct_receipt_semantics":True,"ordering_rejection":True,"stoppage_recovery":True,"replays":3,"changed_payload_rejections":1,"stale_version_rejections":1,"notifications":0,"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__":main()
