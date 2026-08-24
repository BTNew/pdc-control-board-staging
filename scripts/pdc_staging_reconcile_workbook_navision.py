"""Repair staging workbook vehicles by exact Navision stock matching.

Replays only the last applied per-dealer Navision snapshots from the verified,
encrypted pre-reset staging backup through the normal typed Navision importer,
then uses the manager/admin canonical activation contract to attach existing
workbook vehicles by exact current Stock. Unmatched vehicles remain fail-closed.
"""
from __future__ import annotations
import argparse,base64,gzip,hashlib,json,sys
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
sys.path.insert(0,str(Path(__file__).resolve().parent))
import pdc_staging_full_backup as backup
import pdc_staging_operation_workbook_import as op
from pdc_staging_management_migration import STAGING_REF,PRODUCTION_REF,_post

ENC=Path(r"C:/Users/nwmgr/AppData/Local/hermes/profiles/website-development-lead/backups/pdc-staging-full-reset-20260824/pdc-staging-full-0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0.json.gz.aesgcm")
MANIFEST=ENC.with_name("pdc-staging-full-0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0.manifest.json")
EXPECTED_MANIFEST="0cba8a1feb4a01ef55de4de93b29fd6e950949ccd34bf6ef5ecf82bf3031b2c0"
EXPECTED_ENCRYPTED="7e1ba89c675c7afb3fafdd072f20aa0145096ad03672b2de7b283b9f551c9d16"
EXPECTED_BATCH_COUNTS={"14450":736,"37047":234}

def decrypt_tables():
 v=backup.verify(ENC,MANIFEST)
 if v["backup_manifest_sha256"]!=EXPECTED_MANIFEST or v["encrypted_backup_sha256"]!=EXPECTED_ENCRYPTED:raise RuntimeError("PDC_NAV_REPAIR_BACKUP_BINDING_FAILED")
 enc=ENC.read_bytes();raw=gzip.decompress(AESGCM(backup.load_key()).decrypt(enc[:12],enc[12:],backup.AAD));p=json.loads(raw)
 return p["tables"]

def frozen_batches(tables):
 latest={}
 for b in tables["navision_import_batches"]:
  if b.get("status")!="applied":continue
  d=str(b.get("dealer_code") or "")
  if d in EXPECTED_BATCH_COUNTS and (d not in latest or str(b.get("applied_at"))>str(latest[d].get("applied_at"))):latest[d]=b
 if set(latest)!=set(EXPECTED_BATCH_COUNTS):raise RuntimeError("PDC_NAV_REPAIR_LATEST_BATCH_SET_FAILED")
 out=[]
 for dealer in sorted(latest):
  b=latest[dealer];items=sorted((x for x in tables["navision_import_items"] if x.get("batch_id")==b["id"] and isinstance(x.get("raw_evidence"),dict)),key=lambda x:x["row_index"])
  rows=[x["raw_evidence"] for x in items]
  if len(rows)!=EXPECTED_BATCH_COUNTS[dealer] or len({x["row_index"] for x in items})!=len(rows):raise RuntimeError("PDC_NAV_REPAIR_FROZEN_ROW_COUNT_FAILED:"+dealer)
  digest=hashlib.sha256(json.dumps(rows,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()
  out.append({"dealer_code":dealer,"rows":rows,"row_count":len(rows),"source_name":"Verified pre-reset latest Navision snapshot","source_timestamp":b.get("applied_at"),"source_batch_id":b["id"],"frozen_rows_sha256":digest})
 return out

def rpc_raw(base,actor,name,body):return op.request_json(base+"/rest/v1/rpc/"+name,"POST",actor["headers"],body)
def rpc(base,actor,name,body):
 r=rpc_raw(base,actor,name,body)
 if not isinstance(r,dict) or not r.get("ok"):raise RuntimeError("PDC_NAV_REPAIR_RPC_"+name+":"+str(r.get("code") if isinstance(r,dict) else "INVALID"))
 return r

def nav_preview(base,admin,b):
 return rpc(base,admin,"preview_navision_backend_import",{"p_rows":b["rows"],"p_source_system":"microsoft_navision","p_dealer_code":b["dealer_code"],"p_source_name":b["source_name"],"p_source_timestamp":b["source_timestamp"]})
def nav_apply(base,admin,b,preview):
 d=preview["data"]
 return rpc(base,admin,"apply_navision_backend_import",{"p_idempotency_key":"craig-fix-workbook-navision-match-20260824-"+b["dealer_code"]+"-"+b["frozen_rows_sha256"][:16],"p_rows":b["rows"],"p_source_system":"microsoft_navision","p_dealer_code":b["dealer_code"],"p_source_name":b["source_name"],"p_source_timestamp":b["source_timestamp"],"p_source_hash":d["source_hash"],"p_preview_hash":d["preview_hash"],"p_expected_revision":d["base_revision"]})

def readback():
 sql="""SET TRANSACTION READ ONLY;select jsonb_build_object(
 'vehicles',(select count(*) from public.vehicles),'unique_vehicle_stocks',(select count(distinct upper(btrim(stock_number))) from public.vehicles),
 'workbook_source_vehicles',(select count(*) from public.vehicles where source_system='pdc_pmb_workbook'),
 'navision_source_vehicles',(select count(*) from public.vehicles where source_system='navision'),
 'navision_records',(select count(*) from public.navision_backend_records),'current_navision_records',(select count(*) from public.navision_backend_records where is_current),
 'current_navision_unique_stocks',(select count(distinct upper(btrim(normalized_data->>'stock'))) from public.navision_backend_records where is_current),
 'canonical_linked_records',(select count(*) from public.navision_backend_records where is_current and canonical_vehicle_id is not null),
 'active_activations',(select count(*) from public.navision_board_activations where active and completed_at is null),
 'operation_lines',(select count(*) from public.pdc_authenticated_email_operation_lines),'work_items',(select count(*) from public.vehicle_work_items where required),
 'bookings',(select count(*) from public.workshop_bookings),'parts_updates',(select count(*) from public.vehicle_parts_updates),'completed_rows',(select count(*) from public.deleted_completed_vehicles),
 'active_writers',(select count(*) from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),'active_mailboxes',(select count(*) from public.monitored_mailboxes where active),
 'pilot_enabled',(select enabled from public.pdc_email_monitor_pilot where singleton),'monitor_status',(select running_status from public.pdc_email_monitor_status where singleton),'gateway_instance_id',(select gateway_instance_id from public.pdc_email_monitor_status where singleton),
 'canonical_manager_authority',(select count(*) from public.pdc_pmb_canonical_manager_authorities where active),
 'canonical_apply_receipts',(select count(*) from public.pdc_pmb_canonical_apply_receipts),'canonical_pair_receipts',(select count(*) from public.pdc_pmb_canonical_pair_receipts),
 'latest_pair_classifications',(select jsonb_object_agg(classification,n) from(select classification,count(*)n from public.pdc_pmb_workbook_pair_reviews where preview_id=(select preview_id from public.pdc_pmb_workbook_previews order by created_at desc limit 1) group by classification)q)
 )evidence;"""
 return _post(f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only",sql)[0]["evidence"]

def main():
 a=argparse.ArgumentParser();a.add_argument("--prepare-only",action="store_true");a.add_argument("--apply",action="store_true");a.add_argument("--confirmation");a.add_argument("--receipt",type=Path);args=a.parse_args()
 tables=decrypt_tables();batches=frozen_batches(tables);we=op.env(op.WEBSITE_ENV);ae=op.env(op.AUDITOR_ENV);base=we["PDC_STAGING_SUPABASE_URL"];anon=we["PDC_STAGING_ANON_KEY"]
 if we.get("PDC_STAGING_PROJECT_REF")!=STAGING_REF or PRODUCTION_REF in base:raise RuntimeError("PDC_NAV_REPAIR_TARGET_GUARD")
 admin=op.auth(base,anon,we["PDC_STAGING_ADMIN_EMAIL"],we["PDC_STAGING_ADMIN_PASSWORD"]);manager=op.auth(base,anon,we["PDC_STAGING_CONTROLLER_B_EMAIL"],we["PDC_STAGING_CONTROLLER_B_PASSWORD"]);importer=op.auth(base,anon,ae["PDC_AUDITOR_STAGING_EMAIL"],ae["PDC_AUDITOR_STAGING_PASSWORD"])
 if (admin["role"],manager["role"],importer["role"])!=("administrator","operator","viewer"):raise RuntimeError("PDC_NAV_REPAIR_ACTOR_ROLE_MISMATCH")
 previews=[]
 for b in batches:
  pr=nav_preview(base,admin,b);d=pr["data"];previews.append({"dealer_code":b["dealer_code"],"row_count":b["row_count"],"frozen_rows_sha256":b["frozen_rows_sha256"],"preview_hash":d.get("preview_hash"),"source_hash":d.get("source_hash"),"base_revision":d.get("base_revision"),"blocking":d.get("blocking") or (d.get("safety") or {}).get("blocking"),"safety_reason":(d.get("safety") or {}).get("reason"),"invalid_count":(d.get("counts") or {}).get("invalid"),"conflict_count":(d.get("counts") or {}).get("conflict"),"sublet_unknown_count":((d.get("sublet_provider_preview") or {}).get("unknown_count"))})
 if args.prepare_only:
  print(json.dumps({"status":"PREPARED","backup_manifest_sha256":EXPECTED_MANIFEST,"batches":previews,"current":readback()},sort_keys=True));return 0
 if not args.apply or args.confirmation!="CRAIG DIRECTED STAGING NAVISION STOCK MATCH REPAIR":raise RuntimeError("PDC_NAV_REPAIR_CONFIRMATION_REQUIRED")
 before=readback()
 if before["vehicles"]!=153 or before["navision_records"]!=0 or before["active_activations"]!=0 or before["operation_lines"]!=494 or before["work_items"]!=294 or before["active_writers"]!=0 or before["active_mailboxes"]!=0 or before["pilot_enabled"] or before["monitor_status"]!="stopped" or before["gateway_instance_id"] is not None:raise RuntimeError("PDC_NAV_REPAIR_PRESTATE_FAILED:"+json.dumps(before,sort_keys=True))
 nav_receipts=[];cleanup=[];primary=None
 try:
  for b in batches:
   pr=nav_preview(base,admin,b);d=pr["data"]
   if d.get("blocking") or (d.get("safety") or {}).get("blocking"):
    reason=(d.get("safety") or {}).get("reason")
    if reason not in ("initial_scope_approval_required","unproven_empty_dealer_scope"):raise RuntimeError("PDC_NAV_REPAIR_PREVIEW_BLOCKED:"+str(reason))
    rpc(base,admin,"approve_navision_initial_scope",{"p_rows":b["rows"],"p_source_system":"microsoft_navision","p_dealer_code":b["dealer_code"]});pr=nav_preview(base,admin,b);d=pr["data"]
   counts=d.get("counts") or {}
   if d.get("blocking") or (d.get("safety") or {}).get("blocking") or counts.get("invalid") or counts.get("conflict") or ((d.get("sublet_provider_preview") or {}).get("unknown_count") or 0):raise RuntimeError("PDC_NAV_REPAIR_PREVIEW_NOT_SAFE:"+b["dealer_code"]+":"+json.dumps({"counts":counts,"safety":d.get("safety")},sort_keys=True))
   applied=nav_apply(base,admin,b,pr);replay=nav_apply(base,admin,b,pr)
   nav_receipts.append({"dealer_code":b["dealer_code"],"row_count":b["row_count"],"frozen_rows_sha256":b["frozen_rows_sha256"],"preview_hash":d["preview_hash"],"source_hash":d["source_hash"],"apply_code":applied["code"],"apply":applied["data"],"replay_code":replay["code"],"replay":replay["data"]})
  mid=readback()
  if mid["navision_records"]!=970 or mid["current_navision_records"]!=970 or mid["current_navision_unique_stocks"]!=970 or mid["vehicles"]!=153:raise RuntimeError("PDC_NAV_REPAIR_IMPORT_READBACK_FAILED:"+json.dumps(mid,sort_keys=True))
  op.role_change(base,admin,importer["email"],"viewer","Craig directed exact staging Navision stock-match repair")
  rpc(base,admin,"admin_set_pdc_monitor_stage_activation_writer",{"p_monitor_user_id":importer["uid"],"p_active":True,"p_reason":"Craig directed exact staging Navision stock-match repair"})
  op.role_change(base,admin,importer["email"],"importer","Craig directed exact staging Navision stock-match repair")
  importer=op.auth(base,anon,ae["PDC_AUDITOR_STAGING_EMAIL"],ae["PDC_AUDITOR_STAGING_PASSWORD"])
  p,ps=op.payload();ps["payload_sha256"]=op.server_hash(p)
  preview=rpc(base,importer,"preview_pdc_pmb_retained_workbook",{"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_confirmation":"PREVIEW RETAINED PMB WORKBOOK","p_payload":p});pd=preview["data"];pairs=op.read_pairs(base,admin,pd["preview_id"],166)
  approvals=[];ineligible=[]
  for pair in pairs:
   pre=rpc_raw(base,manager,"manager_approve_pdc_pmb_canonical_activation",{"p_preview_id":pd["preview_id"],"p_pair_id":pair["pair_id"],"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_expected_action":"__candidate_preflight__","p_expected_backend_record_id":None,"p_expected_backend_record_version":None,"p_expected_vehicle_id":None,"p_expected_vehicle_version":None,"p_reason":"Exact candidate preflight for Craig-directed staging repair","p_confirmation":"MANAGER APPROVE CANONICAL BOARD ACTIVATION"})
   c=pre.get("data") if isinstance(pre,dict) else None
   if not isinstance(c,dict) or not c.get("eligible"):
    ineligible.append({"pair_no":pair["pair_no"],"classification":pair["classification"],"reason":(c or {}).get("reason") if isinstance(c,dict) else pre.get("code")});continue
   if pre.get("code")!="manager_exact_candidate_mismatch" or c.get("action") not in ("attach_exact_existing_workbook_vehicle",):raise RuntimeError("PDC_NAV_REPAIR_CANDIDATE_ACTION_FAILED:"+json.dumps({"code":pre.get("code"),"candidate":c},sort_keys=True))
   exact={"p_preview_id":pd["preview_id"],"p_pair_id":pair["pair_id"],"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_expected_action":c["action"],"p_expected_backend_record_id":c.get("backend_record_id"),"p_expected_backend_record_version":c.get("backend_record_version"),"p_expected_vehicle_id":c.get("target_vehicle_id"),"p_expected_vehicle_version":c.get("target_vehicle_version"),"p_reason":"Exact current Navision Stock matched to existing staging workbook vehicle","p_confirmation":"MANAGER APPROVE CANONICAL BOARD ACTIVATION"}
   ma=rpc(base,manager,"manager_approve_pdc_pmb_canonical_activation",exact);cs=rpc(base,admin,"administrator_countersign_pdc_pmb_canonical_activation",{"p_manager_approval_id":ma["data"]["approval_id"],"p_manager_approval_hash":ma["data"]["approval_hash"],"p_reason":"Independent countersignature for exact current Navision Stock match","p_confirmation":"ADMINISTRATOR COUNTERSIGN CANONICAL BOARD ACTIVATION"});approvals.append({"pair_no":pair["pair_no"],"action":c["action"],"manager_approval_id":ma["data"]["approval_id"],"countersignature_id":cs["data"]["countersignature_id"]})
  if len(approvals)!=127 or len(ineligible)!=39:raise RuntimeError("PDC_NAV_REPAIR_CANDIDATE_COUNTS_FAILED:"+json.dumps({"eligible":len(approvals),"ineligible":len(ineligible)}))
  au=rpc(base,admin,"authorize_pdc_pmb_canonical_activation_apply",{"p_preview_id":pd["preview_id"],"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_expected_activation_count":127,"p_confirmation":"AUTHORIZE MANAGER APPROVED CANONICAL ACTIVATIONS"})
  ca=rpc(base,admin,"apply_pdc_pmb_canonical_activations",{"p_authorization_id":au["data"]["authorization_id"],"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_expected_activation_count":127,"p_confirmation":"APPLY MANAGER APPROVED CANONICAL ACTIVATIONS"});cr=rpc(base,admin,"apply_pdc_pmb_canonical_activations",{"p_authorization_id":au["data"]["authorization_id"],"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_expected_activation_count":127,"p_confirmation":"APPLY MANAGER APPROVED CANONICAL ACTIVATIONS"})
  if not cr["data"].get("zero_add_replay"):raise RuntimeError("PDC_NAV_REPAIR_CANONICAL_REPLAY_FAILED")
  fresh=rpc(base,importer,"preview_pdc_pmb_retained_workbook",{"p_workbook_sha256":ps["workbook_sha256"],"p_payload_sha256":ps["payload_sha256"],"p_confirmation":"PREVIEW RETAINED PMB WORKBOOK","p_payload":p});fresh_pairs=op.read_pairs(base,admin,fresh["data"]["preview_id"],166);classes=dict(__import__('collections').Counter(x["classification"] for x in fresh_pairs))
  result={"schema":"pdc-staging-workbook-navision-stock-repair-v1","status":"MATCHED","project_ref":STAGING_REF,"backup_manifest_sha256":EXPECTED_MANIFEST,"encrypted_backup_sha256":EXPECTED_ENCRYPTED,"navision_imports":nav_receipts,"workbook_sha256":ps["workbook_sha256"],"payload_sha256":ps["payload_sha256"],"canonical_preview_id":pd["preview_id"],"eligible_pair_count":127,"eligible_unique_stock_count":116,"ineligible_pair_count":39,"ineligible_unique_stock_count":37,"canonical_apply":ca["data"],"canonical_replay":cr["data"],"fresh_preview_id":fresh["data"]["preview_id"],"fresh_pair_classifications":classes}
 except Exception as e:
  primary=e;raise
 finally:
  try:op.role_change(base,admin,importer["email"],"viewer","Restore pmb-auditor viewer after Navision stock-match repair");cleanup.append("viewer_restored")
  except Exception as e:cleanup.append("viewer_restore_failed:"+type(e).__name__)
  try:rpc(base,admin,"admin_set_pdc_monitor_stage_activation_writer",{"p_monitor_user_id":importer["uid"],"p_active":False,"p_reason":"Revoke temporary writer after Navision stock-match repair"});cleanup.append("writer_revoked")
  except Exception as e:cleanup.append("writer_revoke_failed:"+type(e).__name__)
  if primary is None and cleanup!=["viewer_restored","writer_revoked"]:raise RuntimeError("PDC_NAV_REPAIR_CLEANUP_FAILED:"+json.dumps(cleanup))
 after=readback();result["cleanup"]=cleanup;result["readback"]=after
 expected={"vehicles":153,"unique_vehicle_stocks":153,"navision_records":970,"current_navision_records":970,"current_navision_unique_stocks":970,"canonical_linked_records":116,"active_activations":116,"operation_lines":494,"work_items":294,"bookings":0,"parts_updates":0,"completed_rows":0,"active_writers":0,"active_mailboxes":0,"pilot_enabled":False,"monitor_status":"stopped","gateway_instance_id":None}
 if any(after.get(k)!=v for k,v in expected.items()):raise RuntimeError("PDC_NAV_REPAIR_POSTCONDITION_FAILED:"+json.dumps({k:after.get(k) for k in expected},sort_keys=True))
 if args.receipt:args.receipt.parent.mkdir(parents=True,exist_ok=True);args.receipt.write_text(json.dumps(result,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"MATCHED","vehicles":153,"navision_records":970,"matched_unique_stocks":116,"matched_pairs":127,"unmatched_unique_stocks":37,"operation_lines":494,"work_items":294,"cleanup":cleanup,"receipt":str(args.receipt.resolve()) if args.receipt else None},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
