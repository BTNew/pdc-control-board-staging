"""Read back and replay-verify the completed guarded Sublet 010-011 run."""
from __future__ import annotations
import datetime as dt, hashlib, json, pathlib, uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT=pathlib.Path(__file__).resolve().parents[1]
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
SOURCE=ROOT/"_staging_deployment_receipts"/"20260824_overnight_sublet_010_011.json"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_sublet_010_011_verification.json"
NS=uuid.UUID("36500000-0000-5000-8000-000000000365")
LABELS={10:["scenario-010-invalid-date-order","scenario-010-create","scenario-010-update","scenario-010-stale-update","scenario-010-return"],11:["scenario-011-create-provider-a","scenario-011-overlap-provider-b","scenario-011-create-provider-b","scenario-011-update-provider-a"]}
EXPECTED={
 "scenario-010-invalid-date-order":("sublet_create",False,"invalid_input",{"provider_id":"A","out_date":"2026-09-12","expected_return_date":"2026-09-10","notes":"HERMES-TEST SUBLET INVALID DATE 010"}),
 "scenario-010-create":("sublet_create",True,"created",{"provider_id":"A","out_date":"2026-09-10","expected_return_date":"2026-09-12","notes":"HERMES-TEST SUBLET BOOKED 010"}),
 "scenario-010-update":("sublet_update",True,"updated",{"out_date":"2026-09-10","expected_return_date":"2026-09-13","notes":"HERMES-TEST SUBLET UPDATED 010"}),
 "scenario-010-stale-update":("sublet_update",False,"version_conflict",{"out_date":"2026-09-10","expected_return_date":"2026-09-13","notes":"HERMES-TEST SUBLET STALE 010"}),
 "scenario-010-return":("sublet_return",True,"returned",{"returned_at":"2026-09-13T08:00:00+00:00"}),
 "scenario-011-create-provider-a":("sublet_create",True,"created",{"provider_id":"A","out_date":"2026-09-15","expected_return_date":"2026-09-16","notes":"HERMES-TEST SUBLET PROVIDER A 011"}),
 "scenario-011-overlap-provider-b":("sublet_create",False,"sublet_booking_overlap",{"provider_id":"B","out_date":"2026-09-16","expected_return_date":"2026-09-18","notes":"HERMES-TEST SUBLET OVERLAP B 011"}),
 "scenario-011-create-provider-b":("sublet_create",True,"created",{"provider_id":"B","out_date":"2026-09-18","expected_return_date":"2026-09-19","notes":"HERMES-TEST SUBLET PROVIDER B 011"}),
 "scenario-011-update-provider-a":("sublet_update",True,"updated",{"out_date":"2026-09-15","expected_return_date":"2026-09-17","notes":"HERMES-TEST SUBLET PROVIDER A UPDATED 011"})}

def digest(x): return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()

def pg_jsonb_text(x):
 """Render the scalar/object subset used here like PostgreSQL jsonb::text."""
 if isinstance(x,dict):
  keys=sorted(x,key=lambda k:(len(k.encode()),k.encode()))
  return "{"+", ".join(json.dumps(k,ensure_ascii=False)+": "+pg_jsonb_text(x[k]) for k in keys)+"}"
 if isinstance(x,list): return "["+", ".join(pg_jsonb_text(v) for v in x)+"]"
 return json.dumps(x,ensure_ascii=False,separators=(",",":"))

def main():
 e=env_values();base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/");key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base: raise RuntimeError("target guard")
 initial=prove_environment(); prior=json.loads(SOURCE.read_text(encoding="utf-8"))
 s,session=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if s!=200: raise RuntimeError("auth failed")
 actor=session["user"]["id"];headers={"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(name,payload): return request_json(base+"/rest/v1/rpc/"+name,"POST",headers,payload)
 def read(vid=None):
  prove_environment()
  rs,x=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vid})
  if rs!=200 or not x.get("ok") or x.get("notification_count")!=0: raise RuntimeError("state read")
  return x
 def providers():
  prove_environment()
  ps,p=rpc("list_sublet_providers",{})
  if ps!=200 or not isinstance(p,list): raise RuntimeError("provider inventory")
  return p
 p_before=providers(); fleet_before=read(); protected=fleet_before["protected_state"]
 selected=prior["provider_inventory"]["selected"]
 provider_ids={"A":selected[0]["id"],"B":selected[1]["id"]}
 rows={r["scenario_no"]:r for r in fleet_before["vehicles"] if r["scenario_no"] in (10,11)}
 if set(rows)!={10,11} or protected!=prior["protected_state"]: raise RuntimeError("scope/protected mismatch")
 all_receipts=[]
 for no in (10,11):
  row=rows[no]; expected_labels=LABELS[no]
  expected_keys={str(uuid.uuid5(NS,f"{RUN}:{label}")):label for label in expected_labels}
  receipts=[r for r in row["receipts"] if r.get("idempotency_key") in expected_keys]
  if len(receipts)!=len(expected_labels) or {r["idempotency_key"] for r in receipts}!=set(expected_keys): raise RuntimeError(f"receipt set {no}")
  for r in receipts:
   response=r["response"]; keyid=r["idempotency_key"]; label=expected_keys[keyid]
   expected_action,expected_ok,expected_code,expected_payload=EXPECTED[label]
   expected_payload={k:provider_ids.get(v,v) for k,v in expected_payload.items()}
   expected_receipt=str(uuid.uuid5(NS,f"{RUN}:{actor}:{keyid}"))
   if r["receipt_id"]!=expected_receipt or response.get("receipt_id")!=expected_receipt or r["vehicle_id"]!=row["vehicle"]["id"] or r["actor_id"]!=actor or response.get("vehicle_id")!=row["vehicle"]["id"]: raise RuntimeError(f"receipt identity {label}")
   result=response.get("result") or {}
   if r["action"]!=expected_action or response.get("action")!=expected_action or response.get("ok") is not expected_ok or result.get("code")!=expected_code or r["request_payload"]!=expected_payload: raise RuntimeError(f"expected action/payload/result binding {label}")
   sibling=response.get("sibling_state",{})
   if response.get("request_sha256")!=r["request_sha256"] or response.get("protected_state")!=protected or response.get("notification_delta")!=0 or not isinstance(sibling.get("rows"),int) or sibling["rows"]<0 or not isinstance(sibling.get("sha256"),str) or len(sibling["sha256"])!=64: raise RuntimeError(f"receipt content {label}")
   payload=r["request_payload"]; action=r["action"].removeprefix("sublet_")
   exact={"p_run_id":RUN,"p_vehicle_id":row["vehicle"]["id"],"p_expected_vehicle_version":response["vehicle_version_before"],"p_booking_id":response.get("subject_id"),"p_expected_booking_version":response.get("subject_version_before"),"p_idempotency_key":keyid,"p_action":action,"p_provider_id":payload.get("provider_id"),"p_out_date":payload.get("out_date"),"p_expected_return_date":payload.get("expected_return_date"),"p_returned_at":payload.get("returned_at"),"p_notes":payload.get("notes")}
   request_contract={"contract":"pdc-overnight-synthetic-mutation-365","run_id":RUN,"actor_id":actor,"vehicle_id":row["vehicle"]["id"],"expected_vehicle_version":response["vehicle_version_before"],"subject_id":response.get("subject_id"),"expected_subject_version":response.get("subject_version_before"),"idempotency_key":keyid,"action":expected_action,"payload":expected_payload}
   recomputed=hashlib.sha256(pg_jsonb_text(request_contract).encode()).hexdigest()
   if recomputed!=r["request_sha256"]: raise RuntimeError(f"request hash recompute {label}: {recomputed} != {r['request_sha256']}")
   replay_before=read(); prove_environment(); rs,rx=rpc("pdc_hermes_test_sublet_365",exact); replay_after=read()
   if rs!=200 or rx.get("replay") is not True or rx.get("receipt_id")!=expected_receipt or rx.get("replay_containment_verified") is not True or rx.get("notification_delta")!=0 or rx.get("current_notification_count")!=0 or rx.get("current_protected_digest")!=protected or digest(replay_after)!=digest(replay_before): raise RuntimeError(f"exact replay {label}: {rs} {json.dumps(rx)[:500]}")
   all_receipts.append({"label":label,"scenario_no":no,"idempotency_key":keyid,"receipt_id":expected_receipt,"request_sha256":r["request_sha256"],"action":r["action"],"ok":response["ok"],"sibling_state":response["sibling_state"],"exact_replay":True})
 # Re-run both changed-payload hostile probes, with full-fleet authoritative no-change comparison.
 by_label={x["label"]:x for x in all_receipts}
 for label,change in (("scenario-010-create",{"p_notes":"HERMES-TEST CHANGED SUBLET BOOKED 010"}),("scenario-010-update",{"p_expected_return_date":"2026-09-14"})):
  rr=next(r for r in rows[10]["receipts"] if r["receipt_id"]==by_label[label]["receipt_id"]); z=rr["response"]; q=rr["request_payload"]
  cp={"p_run_id":RUN,"p_vehicle_id":rows[10]["vehicle"]["id"],"p_expected_vehicle_version":z["vehicle_version_before"],"p_booking_id":z.get("subject_id"),"p_expected_booking_version":z.get("subject_version_before"),"p_idempotency_key":rr["idempotency_key"],"p_action":rr["action"].removeprefix("sublet_"),"p_provider_id":q.get("provider_id"),"p_out_date":q.get("out_date"),"p_expected_return_date":q.get("expected_return_date"),"p_returned_at":q.get("returned_at"),"p_notes":q.get("notes")};cp.update(change)
  snap=read();prove_environment();cs,cx=rpc("pdc_hermes_test_sublet_365",cp);snap2=read()
  if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cx) or digest(snap2)!=digest(snap): raise RuntimeError(f"changed payload no-change {label}")
 # Re-run cross-vehicle hostile subject and prove both source and presented vehicles plus full fleet unchanged.
 b10=rows[10]["sublets"][0]; cross_key=str(uuid.uuid5(NS,f"{RUN}:scenario-011-cross-vehicle-subject"))
 cross={"p_run_id":RUN,"p_vehicle_id":rows[11]["vehicle"]["id"],"p_expected_vehicle_version":rows[11]["vehicle"]["version"],"p_booking_id":b10["booking_id"],"p_expected_booking_version":2,"p_idempotency_key":cross_key,"p_action":"update","p_provider_id":None,"p_out_date":"2026-09-10","p_expected_return_date":"2026-09-13","p_returned_at":None,"p_notes":"HERMES-TEST CROSS VEHICLE REJECT 011"}
 snap=read();prove_environment();xs,xx=rpc("pdc_hermes_test_sublet_365",cross);snap2=read()
 if xs<400 or "PDC_365_SUBJECT_OUTSIDE_REGISTRY_VEHICLE" not in json.dumps(xx) or digest(snap2)!=digest(snap): raise RuntimeError("cross-vehicle full-fleet no-change")
 # Full state must remain byte-stable across all exact replays and hostile probes.
 fleet_after=read();p_after=providers();final=prove_environment()
 if digest(fleet_after)!=digest(fleet_before) or digest(p_after)!=digest(p_before) or fleet_after["protected_state"]!=protected: raise RuntimeError("final fleet/provider stability")
 f10=rows[10];f11=rows[11]
 if len(f10["sublets"])!=1 or f10["sublets"][0]["status"]!="returned" or len(f10["sublet_history"])!=3: raise RuntimeError("010 final state")
 if len(f11["sublets"])!=2 or len(f11["sublet_history"])!=3 or len({x["provider_id"] for x in f11["sublets"]})!=2: raise RuntimeError("011 final state")
 h10=f10["sublet_history"];h11=f11["sublet_history"]
 if [h.get("action") for h in h10] != ["created","updated","returned"] or [h.get("action") for h in h11] != ["created","created","updated"]: raise RuntimeError("history action sequence")
 booking_provider_10={f10["sublets"][0]["booking_id"]:f10["sublets"][0]["provider_id"]}
 for h in h10:
  after=h.get("after_data") or {}; before=h.get("before_data") or {}; provider=after.get("provider_id") or before.get("provider_id")
  if h.get("vehicle_id")!=f10["vehicle"]["id"] or h.get("booking_id") not in booking_provider_10 or provider!=booking_provider_10[h["booking_id"]] or h.get("actor_id")!=actor or not h.get("event_at"): raise RuntimeError("010 history binding")
 booking_provider_11={x["booking_id"]:x["provider_id"] for x in f11["sublets"]}
 for h in h11:
  after=h.get("after_data") or {}; before=h.get("before_data") or {}; provider=after.get("provider_id") or before.get("provider_id")
  if h.get("vehicle_id")!=f11["vehicle"]["id"] or h.get("booking_id") not in booking_provider_11 or provider!=booking_provider_11[h["booking_id"]] or h.get("actor_id")!=actor or not h.get("event_at"): raise RuntimeError("011 history binding")
 w10=[w for w in f10["work_items"] if w.get("work_key")=="sublet" and w.get("required")];w11=[w for w in f11["work_items"] if w.get("work_key")=="sublet" and w.get("required")]
 if len(w10)!=1 or not w10[0].get("completed") or not w10[0].get("completed_at") or w10[0].get("completed_by")!=actor: raise RuntimeError("010 explicit return completion projection missing")
 if len(w11)!=1 or w11[0].get("completed") or w11[0].get("completed_at") is not None or w11[0].get("completed_by") is not None: raise RuntimeError("011 physical completion invented")
 evidence={"schema":"pdc-overnight-sublet-010-011-verification-v1","project_ref":REF,"run_id":RUN,"actor_id":actor,"initial_environment":initial,"final_environment":final,"protected_state":protected,"provider_inventory":{"count":len(p_before),"sha256_before":digest(p_before),"sha256_after":digest(p_after),"unchanged":True},"full_fleet_state":{"sha256_before":digest(fleet_before),"sha256_after":digest(fleet_after),"unchanged_across_replays_and_hostile_probes":True},"receipts":all_receipts,"exact_replays":len(all_receipts),"changed_payload_full_state_rejections":2,"cross_vehicle_full_fleet_rejection":True,"scenario_010":{"booking_count":1,"history_count":3,"status":"returned","explicit_synthetic_return_projection":True},"scenario_011":{"booking_count":2,"history_count":3,"provider_isolation":True,"completion_not_claimed":True},"physical_work_claimed":False,"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"SUBLET_010_011_INDEPENDENT_READBACK_VERIFIED","receipts":len(all_receipts),"exact_replays":len(all_receipts),"changed_payload_no_change":2,"cross_vehicle_full_fleet_no_change":True,"provider_inventory_unchanged":True,"notifications":0,"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__": main()
