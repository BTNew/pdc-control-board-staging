"""Exercise guarded Sublet lifecycle and multi-provider isolation on 010-011."""
from __future__ import annotations
import datetime as dt, hashlib, json, pathlib, uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT=pathlib.Path(__file__).resolve().parents[1]
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_sublet_010_011.json"
NS=uuid.UUID("36500000-0000-5000-8000-000000000365")

def canonical(value):
 return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()

def main():
 e=env_values(); base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/"); key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base: raise RuntimeError("target guard")
 initial=prove_environment()
 s,session=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if s!=200: raise RuntimeError("staging Administrator2 authentication failed")
 headers={"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(name,payload): return request_json(base+"/rest/v1/rpc/"+name,"POST",headers,payload)
 def read(vid=None):
  rs,x=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vid})
  if rs!=200 or x.get("ok") is not True or x.get("notification_count")!=0: raise RuntimeError(f"read failed {rs} {json.dumps(x)[:800]}")
  return x
 ps,providers=rpc("list_sublet_providers",{})
 if ps!=200 or not isinstance(providers,list): raise RuntimeError("provider inventory unavailable")
 active=sorted((p for p in providers if p.get("active") and p.get("id") and p.get("name")),key=lambda p:(int(p.get("sort_order") or 999999),p["name"],p["id"]))
 if len(active)<2 or active[0]["id"]==active[1]["id"]: raise RuntimeError("two active providers required")
 provider_a,provider_b=active[:2]
 fleet=read(); protected=fleet["protected_state"]
 rows={r["scenario_no"]:r for r in fleet["vehicles"] if r["scenario_no"] in (10,11)}
 if set(rows)!={10,11}: raise RuntimeError("scenario inventory mismatch")
 for no,row in rows.items():
  if row["vehicle"]["stock_number"]!=f"HERMES-TEST-{no:03d}" or row["sublets"] or row["sublet_history"]: raise RuntimeError(f"scenario {no} not pristine")
  if not any(w.get("work_key")=="sublet" and w.get("required") and not w.get("completed") for w in row["work_items"]): raise RuntimeError(f"scenario {no} queued Sublet work evidence missing")
 actions=[]
 def payload(row,key,action,booking=None,booking_version=None,provider=None,out=None,expected=None,returned=None,notes=None,vehicle_version=None):
  return {"p_run_id":RUN,"p_vehicle_id":row["vehicle"]["id"],"p_expected_vehicle_version":int(row["vehicle"]["version"] if vehicle_version is None else vehicle_version),
   "p_booking_id":booking,"p_expected_booking_version":booking_version,"p_idempotency_key":key,"p_action":action,
   "p_provider_id":provider,"p_out_date":out,"p_expected_return_date":expected,"p_returned_at":returned,"p_notes":notes}
 def invoke(label,no,action,*,booking=None,booking_version=None,provider=None,out=None,expected=None,returned=None,notes=None,expect_ok=True,error=None,changed=None,vehicle_version=None):
  before=read(rows[no]["vehicle"]["id"]); br=before["vehicles"][0]; keyid=str(uuid.uuid5(NS,f"{RUN}:{label}"))
  p=payload(br,keyid,action,booking,booking_version,provider,out,expected,returned,notes,vehicle_version)
  proof=prove_environment(); status,response=rpc("pdc_hermes_test_sublet_365",p)
  if status!=200 or response.get("ok") is not expect_ok or (error and error not in json.dumps(response)) or response.get("notification_delta")!=0: raise RuntimeError(f"{label} result {status} {json.dumps(response)[:1000]}")
  after=read(br["vehicle"]["id"]); ar=after["vehicles"][0]
  if after["protected_state"]!=protected or len(ar["receipts"])!=len(br["receipts"])+1: raise RuntimeError(f"{label} containment/receipt")
  expected_delta=1 if expect_ok and action=="create" else 0
  if len(ar["sublets"])!=len(br["sublets"])+expected_delta: raise RuntimeError(f"{label} sublet count")
  if not expect_ok and canonical(ar["sublets"])!=canonical(br["sublets"]): raise RuntimeError(f"{label} rejection changed sublets")
  prove_environment(); rstatus,replay=rpc("pdc_hermes_test_sublet_365",p); replay_row=read(br["vehicle"]["id"])["vehicles"][0]
  if rstatus!=200 or replay.get("replay") is not True or len(replay_row["receipts"])!=len(ar["receipts"]) or canonical(replay_row["sublets"])!=canonical(ar["sublets"]): raise RuntimeError(f"{label} replay")
  changed_rejected=False
  if changed:
   cp=dict(p); cp.update(changed); prove_environment(); cs,cx=rpc("pdc_hermes_test_sublet_365",cp)
   if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cx): raise RuntimeError(f"{label} changed payload {cs} {json.dumps(cx)[:800]}")
   changed_rejected=True
  actions.append({"label":label,"scenario_no":no,"action":action,"expected_ok":expect_ok,"expected_error":error,"http_status":status,"receipt_id":response.get("receipt_id"),"booking_id":(response.get("result") or {}).get("data",{}).get("booking",{}).get("booking_id"),"sublets_before":len(br["sublets"]),"sublets_after":len(ar["sublets"]),"history_before":len(br["sublet_history"]),"history_after":len(ar["sublet_history"]),"replay_verified":True,"changed_payload_rejected":changed_rejected,"pre_action_migration_head":proof["database"]["migration_head"],"result":response.get("result")})
  return ar,response
 # 010: queued work item -> booked -> updated -> returned. These are explicit synthetic transitions only.
 r10,_=invoke("scenario-010-invalid-date-order",10,"create",provider=provider_a["id"],out="2026-09-12",expected="2026-09-10",notes="HERMES-TEST SUBLET INVALID DATE 010",expect_ok=False,error="invalid_input")
 r10,c10=invoke("scenario-010-create",10,"create",provider=provider_a["id"],out="2026-09-10",expected="2026-09-12",notes="HERMES-TEST SUBLET BOOKED 010",changed={"p_notes":"HERMES-TEST CHANGED SUBLET BOOKED 010"})
 b10=r10["sublets"][-1]
 r10,_=invoke("scenario-010-update",10,"update",booking=b10["booking_id"],booking_version=b10["version"],out="2026-09-10",expected="2026-09-13",notes="HERMES-TEST SUBLET UPDATED 010",changed={"p_expected_return_date":"2026-09-14"})
 b10=r10["sublets"][-1]
 r10,_=invoke("scenario-010-stale-update",10,"update",booking=b10["booking_id"],booking_version=b10["version"]-1,out="2026-09-10",expected="2026-09-13",notes="HERMES-TEST SUBLET STALE 010",expect_ok=False,error="version_conflict")
 r10,_=invoke("scenario-010-return",10,"return",booking=b10["booking_id"],booking_version=b10["version"],returned="2026-09-13T08:00:00Z")
 if r10["sublets"][-1].get("status")!="returned": raise RuntimeError("010 returned-state missing")
 # 011: two provider rows on non-overlapping dates, overlap rejection, and row isolation.
 r11,_=invoke("scenario-011-create-provider-a",11,"create",provider=provider_a["id"],out="2026-09-15",expected="2026-09-16",notes="HERMES-TEST SUBLET PROVIDER A 011")
 a11=r11["sublets"][-1]
 r11,_=invoke("scenario-011-overlap-provider-b",11,"create",provider=provider_b["id"],out="2026-09-16",expected="2026-09-18",notes="HERMES-TEST SUBLET OVERLAP B 011",expect_ok=False,error="sublet_booking_overlap")
 r11,_=invoke("scenario-011-create-provider-b",11,"create",provider=provider_b["id"],out="2026-09-18",expected="2026-09-19",notes="HERMES-TEST SUBLET PROVIDER B 011")
 if len(r11["sublets"])!=2 or {x["provider_id"] for x in r11["sublets"]}!={provider_a["id"],provider_b["id"]}: raise RuntimeError("011 provider isolation inventory")
 a11=next(x for x in r11["sublets"] if x["provider_id"]==provider_a["id"]); b11=next(x for x in r11["sublets"] if x["provider_id"]==provider_b["id"]); b_digest=canonical(b11)
 r11,_=invoke("scenario-011-update-provider-a",11,"update",booking=a11["booking_id"],booking_version=a11["version"],out="2026-09-15",expected="2026-09-17",notes="HERMES-TEST SUBLET PROVIDER A UPDATED 011")
 if canonical(next(x for x in r11["sublets"] if x["provider_id"]==provider_b["id"]))!=b_digest: raise RuntimeError("provider B changed during provider A update")
 # Cross-vehicle subject must fail before canonical mutation and before a receipt is written.
 before11=read(rows[11]["vehicle"]["id"])["vehicles"][0]; bad=payload(before11,str(uuid.uuid5(NS,f"{RUN}:scenario-011-cross-vehicle-subject")),"update",b10["booking_id"],b10["version"],None,"2026-09-10","2026-09-13",None,"HERMES-TEST CROSS VEHICLE REJECT 011")
 prove_environment(); xs,xx=rpc("pdc_hermes_test_sublet_365",bad)
 after11=read(rows[11]["vehicle"]["id"])["vehicles"][0]
 if xs<400 or "PDC_365_SUBJECT_OUTSIDE_REGISTRY_VEHICLE" not in json.dumps(xx) or canonical(after11["sublets"])!=canonical(before11["sublets"]) or len(after11["receipts"])!=len(before11["receipts"]): raise RuntimeError(f"cross-vehicle isolation {xs} {json.dumps(xx)[:800]}")
 actions.append({"label":"scenario-011-cross-vehicle-subject","scenario_no":11,"action":"update","expected_transport_rejection":True,"http_status":xs,"error":"PDC_365_SUBJECT_OUTSIDE_REGISTRY_VEHICLE","no_receipt_or_target_change":True})
 final=read(); final_proof=prove_environment(); f10=next(r for r in final["vehicles"] if r["scenario_no"]==10); f11=next(r for r in final["vehicles"] if r["scenario_no"]==11)
 if final["protected_state"]!=protected or final["notification_count"]!=0 or f10["sublets"][-1]["status"]!="returned" or len(f11["sublets"])!=2: raise RuntimeError("final containment/state")
 evidence={"schema":"pdc-overnight-sublet-010-011-v1","project_ref":REF,"run_id":RUN,"actor_id":session["user"]["id"],"initial_environment":initial,"final_environment":final_proof,"protected_state":protected,"provider_inventory":{"count":len(providers),"active_count":len(active),"selected":[provider_a,provider_b]},"queued_evidence":{"010":"required incomplete sublet work item","011":"required incomplete sublet work item"},"actions":actions,"scenario_010":{"booking_count":len(f10["sublets"]),"final_status":f10["sublets"][-1]["status"],"history_count":len(f10["sublet_history"])},"scenario_011":{"booking_count":len(f11["sublets"]),"provider_ids":[x["provider_id"] for x in f11["sublets"]],"provider_b_unchanged_during_a_update":True,"history_count":len(f11["sublet_history"])},"physical_work_claimed":False,"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"SUBLET_010_011_VERIFIED","receipted_actions":sum(1 for a in actions if a.get("receipt_id")),"successful_actions":sum(1 for a in actions if a.get("expected_ok") is True),"authoritative_rejections":sum(1 for a in actions if a.get("expected_ok") is False)+1,"replays":sum(1 for a in actions if a.get("replay_verified")),"changed_payload_rejections":sum(1 for a in actions if a.get("changed_payload_rejected")),"providers":2,"notifications":0,"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__": main()
