"""Exercise guarded QC, RFT and Completed ordering/separation on 012-014."""
from __future__ import annotations
import datetime as dt, hashlib, json, pathlib, uuid
from hermes_overnight_scenarios_002_003_lifecycle import env_values, prove_environment, request_json

ROOT=pathlib.Path(__file__).resolve().parents[1]
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"
OUT=ROOT/"_staging_deployment_receipts"/"20260824_overnight_qc_rft_completed_012_014.json"
NS=uuid.UUID("36500000-0000-5000-8000-000000000365")
WORK_KEYS=("bus4x4","tint","hoist","fitting","fabrication","electrical","tyre","pitInspection","sublet","parts")

def digest(value):
 return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),default=str).encode()).hexdigest()

def main():
 e=env_values(); base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/"); key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base: raise RuntimeError("target guard")
 initial=prove_environment()
 def auth(email_key,password_key):
  s,x=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e[email_key],"password":e[password_key]})
  if s!=200: raise RuntimeError(f"staging authentication failed for {email_key}")
  return x
 admin=auth("PDC_STAGING_ADMIN2_EMAIL","PDC_STAGING_ADMIN2_PASSWORD")
 operator=auth("PDC_STAGING_CONTROLLER_A_EMAIL","PDC_STAGING_CONTROLLER_A_PASSWORD")
 unapproved=auth("PDC_STAGING_UNAPPROVED_EMAIL","PDC_STAGING_UNAPPROVED_PASSWORD")
 def headers(session): return {"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(session,name,payload): return request_json(base+"/rest/v1/rpc/"+name,"POST",headers(session),payload)
 def read(session=admin,vid=None):
  s,x=rpc(session,"read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":vid})
  return s,x
 s,fleet=read()
 if s!=200 or fleet.get("ok") is not True or fleet.get("notification_count")!=0: raise RuntimeError("initial readback")
 protected=fleet["protected_state"]
 rows={r["scenario_no"]:r for r in fleet["vehicles"] if r["scenario_no"] in (12,13,14)}
 if set(rows)!={12,13,14}: raise RuntimeError("scenario inventory")
 expected_interrupted={
  str(uuid.uuid5(NS,f"{RUN}:012-qc-to-rft-before-qc")):(12,"lifecycle_qc_to_rft"),
  str(uuid.uuid5(NS,f"{RUN}:012-collect-before-rft")):(12,"lifecycle_collect"),
  str(uuid.uuid5(NS,f"{RUN}:012-ready-qc-incomplete")):(12,"lifecycle_ready_qc"),
 }
 observed_interrupted={}
 for no,row in rows.items():
  v=row["vehicle"]
  if v["stock_number"]!=f"HERMES-TEST-{no:03d}" or v["version"]!=1 or v["current_location"]!="PMB" or v["lifecycle_state"]!="active": raise RuntimeError(f"scenario {no} initial state drift")
  for receipt in row["receipts"]:
   idem=receipt.get("idempotency_key"); expected=expected_interrupted.get(idem)
   stored=receipt.get("response") or {}
   if not expected or expected[0]!=no or receipt.get("vehicle_id")!=v["id"] or receipt.get("actor_id")!=admin["user"]["id"] or receipt.get("action")!=expected[1] or stored.get("ok") is not False or stored.get("action")!=expected[1] or stored.get("vehicle_id")!=v["id"] or stored.get("vehicle_version_before")!=1 or stored.get("vehicle_version_after")!=1 or stored.get("receipt_id")!=receipt.get("receipt_id") or stored.get("request_sha256")!=receipt.get("request_sha256") or receipt.get("request_payload")!={}: raise RuntimeError(f"scenario {no} unrelated or unbound preexisting receipt")
   observed_interrupted[idem]=expected
 if observed_interrupted!=expected_interrupted: raise RuntimeError("exact interrupted rejection receipt inventory mismatch")
 # Role contract: operator can inspect exact registry scope; viewer and unapproved identities cannot.
 os,ox=read(operator)
 if os!=200 or ox.get("ok") is not True: raise RuntimeError("operator read role denied")
 role_checks=[{"role":"operator","read_allowed":True,"http_status":os}]
 # The configured viewer credential is deliberately unusable (Auth 400), which is
 # itself a fail-closed role boundary; the authenticated unapproved identity must
 # additionally be rejected by the registry wrapper.
 vs,vx=request_json(base+"/auth/v1/token?grant_type=password","POST",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_VIEWER_EMAIL"],"password":e["PDC_STAGING_VIEWER_PASSWORD"]})
 if vs<400 or vx.get("user"): raise RuntimeError("viewer credential unexpectedly authenticated")
 role_checks.append({"role":"viewer","auth_allowed":False,"http_status":vs,"error":vx.get("error_code") or vx.get("msg")})
 for label,session in (("unapproved",unapproved),):
  rs,rx=read(session)
  if rs<400 or "PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID" not in json.dumps(rx): raise RuntimeError(f"{label} role fail-closed mismatch {rs} {json.dumps(rx)[:500]}")
  role_checks.append({"role":label,"read_allowed":False,"http_status":rs,"error":"PDC_365_READ_UNAUTHORIZED_OR_RUN_INVALID"})
 actions=[]
 def current(no):
  s,x=read(admin,rows[no]["vehicle"]["id"])
  if s!=200 or x.get("ok") is not True or x.get("notification_count")!=0: raise RuntimeError(f"read {no}")
  if x["protected_state"]!=protected: raise RuntimeError(f"protected digest {no}")
  return x["vehicles"][0]
 def state_digest(row):
  return digest({k:row[k] for k in ("vehicle","work_items","bookings","booking_assignments","booking_history","parts_overrides","parts","sublets","movements","audit_events","sublet_history")})
 def lifecycle(label,no,action,expect_ok,*,changed_probe=False,stale_version=None):
  before=current(no); v=before["vehicle"]; version=int(v["version"] if stale_version is None else stale_version)
  idem=str(uuid.uuid5(NS,f"{RUN}:{label}")); p={"p_run_id":RUN,"p_vehicle_id":v["id"],"p_expected_version":version,"p_idempotency_key":idem,"p_action":action}
  existing=next((r for r in before["receipts"] if r.get("actor_id")==admin["user"]["id"] and r.get("idempotency_key")==idem),None)
  pre=prove_environment(); status,response=rpc(admin,"pdc_hermes_test_lifecycle_365",p); after=current(no)
  if status!=200 or response.get("ok") is not expect_ok or response.get("notification_delta")!=0 or response.get("replay") is not bool(existing): raise RuntimeError(f"{label} result {status} {json.dumps(response)[:1000]}")
  if len(after["receipts"])!=len(before["receipts"])+(0 if existing else 1): raise RuntimeError(f"{label} receipt")
  if not expect_ok and state_digest(after)!=state_digest(before): raise RuntimeError(f"{label} rejection changed authoritative target state")
  if existing and (existing.get("vehicle_id")!=v["id"] or existing.get("action")!="lifecycle_"+action or existing.get("request_sha256")!=response.get("request_sha256") or existing.get("receipt_id")!=response.get("receipt_id") or state_digest(after)!=state_digest(before)): raise RuntimeError(f"{label} recovered receipt binding")
  prove_environment(); rstatus,replay=rpc(admin,"pdc_hermes_test_lifecycle_365",p); replay_row=current(no)
  if rstatus!=200 or replay.get("replay") is not True or replay.get("replay_containment_verified") is not True or len(replay_row["receipts"])!=len(after["receipts"]) or state_digest(replay_row)!=state_digest(after): raise RuntimeError(f"{label} replay")
  changed_rejected=False
  if changed_probe:
   cp=dict(p); cp["p_action"]="collect" if action!="collect" else "ready_qc"; prove_environment(); cs,cx=rpc(admin,"pdc_hermes_test_lifecycle_365",cp)
   if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cx): raise RuntimeError(f"{label} changed payload")
   if state_digest(current(no))!=state_digest(after): raise RuntimeError(f"{label} changed payload changed state")
   changed_rejected=True
  actions.append({"label":label,"scenario_no":no,"kind":"lifecycle","action":action,"expected_ok":expect_ok,"http_status":status,"receipt_id":response.get("receipt_id"),"error":(response.get("result") or {}).get("error"),"version_before":before["vehicle"]["version"],"version_after":after["vehicle"]["version"],"location_before":before["vehicle"]["current_location"],"location_after":after["vehicle"]["current_location"],"replay_verified":True,"recovered_from_prior_receipt":bool(existing),"changed_payload_rejected":changed_rejected,"pre_action_migration_head":pre["database"]["migration_head"]})
  return after
 def complete_work(label,no,key,*,changed_probe=False,stale_probe=False):
  before=current(no); v=before["vehicle"]; states={k:("complete" if k==key else "none") for k in WORK_KEYS}; idem=str(uuid.uuid5(NS,f"{RUN}:{label}"))
  p={"p_run_id":RUN,"p_vehicle_id":v["id"],"p_expected_version":int(v["version"]),"p_idempotency_key":idem,"p_work_key":key}
  pre=prove_environment(); status,response=rpc(admin,"pdc_hermes_test_complete_qc_fixture_373",p); after=current(no)
  if status!=200 or response.get("ok") is not True or response.get("notification_delta")!=0 or int(after["vehicle"]["version"])!=int(v["version"])+1: raise RuntimeError(f"{label} completion {status} {json.dumps(response)[:1000]}")
  item=next((w for w in after["work_items"] if w["work_key"].lower()==key.lower()),None)
  completion_result=response.get("result") or {}
  completion_audit=next((a for a in reversed(after["audit_events"]) if (a.get("metadata") or {}).get("action")=="pdc_hermes_test_complete_qc_fixture_373"),None)
  if not item or not item["required"] or not item["completed"] or not item.get("completed_at") or item.get("completed_by")!=admin["user"]["id"]: raise RuntimeError(f"{label} explicit synthetic completion evidence")
  if completion_result.get("physical_work_claimed") is not False or not completion_audit or (completion_audit.get("metadata") or {}).get("physical_work_claimed") is not False or (completion_audit.get("metadata") or {}).get("evidence")!="HERMES-TEST explicit synthetic completion": raise RuntimeError(f"{label} no-physical-work truthfulness evidence")
  prove_environment(); rs,rr=rpc(admin,"pdc_hermes_test_complete_qc_fixture_373",p)
  if rs!=200 or rr.get("replay") is not True or len(current(no)["receipts"])!=len(after["receipts"]): raise RuntimeError(f"{label} replay")
  changed_rejected=False
  if changed_probe:
   cp=dict(p); cp["p_work_key"]="electrical" if key!="electrical" else "fitting"; prove_environment(); cs,cx=rpc(admin,"pdc_hermes_test_complete_qc_fixture_373",cp)
   if cs<400 or "PDC_365_IDEMPOTENCY_PAYLOAD_OR_ACTOR_MISMATCH" not in json.dumps(cx): raise RuntimeError(f"{label} changed payload")
   changed_rejected=True
  stale_rejected=False
  if stale_probe:
   sp=dict(p); sp["p_idempotency_key"]=str(uuid.uuid5(NS,f"{RUN}:{label}:stale")); prove_environment(); ss,sx=rpc(admin,"pdc_hermes_test_complete_qc_fixture_373",sp); stale_after=current(no)
   if ss!=200 or sx.get("ok") is not False or "vehicle_version_conflict" not in json.dumps(sx) or len(stale_after["receipts"])!=len(after["receipts"])+1 or digest(stale_after["vehicle"])!=digest(after["vehicle"]): raise RuntimeError(f"{label} stale version")
   stale_rejected=True
  actions.append({"label":label,"scenario_no":no,"kind":"work_states","action":"explicit_synthetic_completion","work_key":key,"expected_ok":True,"http_status":status,"receipt_id":response.get("receipt_id"),"version_before":v["version"],"version_after":after["vehicle"]["version"],"replay_verified":True,"changed_payload_rejected":changed_rejected,"stale_version_rejected":stale_rejected,"physical_work_claimed":completion_result.get("physical_work_claimed"),"completion_audit_id":completion_audit.get("id"),"completion_audit_metadata":completion_audit.get("metadata"),"pre_action_migration_head":pre["database"]["migration_head"]})
  return after
 # 012 ends in QC: prove premature QC/RFT/collection rejection, then only explicit synthetic work completion and Ready-QC.
 lifecycle("012-qc-to-rft-before-qc",12,"qc_to_rft",False)
 lifecycle("012-collect-before-rft",12,"collect",False)
 lifecycle("012-ready-qc-incomplete",12,"ready_qc",False)
 complete_work("012-complete-fittings-synthetic",12,"fitting",changed_probe=True,stale_probe=True)
 lifecycle("012-qc-to-rft-still-pmb",12,"qc_to_rft",False)
 lifecycle("012-ready-qc",12,"ready_qc",True,changed_probe=True)
 lifecycle("012-ready-qc-again",12,"ready_qc",False)
 # 013 ends in RFT and remains distinct from both QC and Completed.
 lifecycle("013-collect-before-rft",13,"collect",False)
 lifecycle("013-qc-to-rft-before-qc",13,"qc_to_rft",False)
 complete_work("013-complete-electrical-synthetic",13,"electrical",stale_probe=True)
 lifecycle("013-ready-qc",13,"ready_qc",True)
 lifecycle("013-collect-from-qc",13,"collect",False)
 lifecycle("013-qc-to-rft",13,"qc_to_rft",True,changed_probe=True)
 lifecycle("013-ready-qc-from-rft",13,"ready_qc",False)
 # 014 alone advances to Completed/collected after the same ordered gates.
 lifecycle("014-qc-to-rft-before-qc",14,"qc_to_rft",False)
 complete_work("014-complete-fittings-synthetic",14,"fitting",changed_probe=True,stale_probe=True)
 lifecycle("014-ready-qc",14,"ready_qc",True)
 lifecycle("014-qc-to-rft",14,"qc_to_rft",True)
 lifecycle("014-qc-to-rft-again",14,"qc_to_rft",False)
 lifecycle("014-collect",14,"collect",True,changed_probe=True)
 lifecycle("014-collect-again",14,"collect",False)
 final_state={no:current(no) for no in (12,13,14)}; v12=final_state[12]["vehicle"]; v13=final_state[13]["vehicle"]; v14=final_state[14]["vehicle"]
 if not (v12["current_location"]=="QC" and v12["lifecycle_state"]=="active" and v12.get("qc_completed_at") is None and v12.get("rft_transferred_at") is None): raise RuntimeError("012 QC separation")
 if not (v13["current_location"]=="RFT" and v13["lifecycle_state"]=="rft" and v13.get("qc_completed_at") and v13.get("rft_transferred_at") and v13.get("rft_collected_at") is None): raise RuntimeError("013 RFT separation")
 if not (v14["current_location"]=="Completed" and v14["lifecycle_state"]=="completed" and v14.get("qc_completed_at") and v14.get("rft_transferred_at") and v14.get("rft_collected_at") and v14.get("rft_collected_by")==admin["user"]["id"] and v14.get("visible_on_board") is False): raise RuntimeError(f"014 Completed separation {json.dumps(v14)[:1000]}")
 fs,all_final=read(); final_proof=prove_environment()
 if fs!=200 or all_final["protected_state"]!=protected or all_final["notification_count"]!=0: raise RuntimeError("final containment")
 evidence={"schema":"pdc-overnight-qc-rft-completed-012-014-v1","project_ref":REF,"run_id":RUN,"actor_id":admin["user"]["id"],"initial_environment":initial,"final_environment":final_proof,"protected_state":protected,"role_checks":role_checks,"actions":actions,"final_separation":{str(no):{k:final_state[no]["vehicle"].get(k) for k in ("stock_number","version","current_location","lifecycle_state","qc_completed_at","qc_completed_by","rft_transferred_at","rft_collected_at","rft_collected_by","visible_on_board")} for no in (12,13,14)},"out_of_order_rejections":sum(1 for a in actions if a.get("expected_ok") is False),"exact_replays":sum(1 for a in actions if a.get("replay_verified")),"changed_payload_rejections":sum(1 for a in actions if a.get("changed_payload_rejected")),"stale_version_rejections":sum(1 for a in actions if a.get("stale_version_rejected")),"notifications":0,"physical_work_claimed":any(a.get("physical_work_claimed") is True for a in actions),"recorded_at_utc":dt.datetime.now(dt.timezone.utc).isoformat()}
 OUT.write_text(json.dumps(evidence,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"QC_RFT_COMPLETED_012_014_VERIFIED","out_of_order_rejections":evidence["out_of_order_rejections"],"successful_actions":sum(1 for a in actions if a.get("expected_ok") is True),"exact_replays":evidence["exact_replays"],"changed_payload_rejections":evidence["changed_payload_rejections"],"stale_version_rejections":evidence["stale_version_rejections"],"role_checks":len(role_checks),"notifications":0,"final_locations":{str(n):final_state[n]["vehicle"]["current_location"] for n in (12,13,14)},"evidence":str(OUT.resolve())},sort_keys=True))
if __name__=="__main__": main()
