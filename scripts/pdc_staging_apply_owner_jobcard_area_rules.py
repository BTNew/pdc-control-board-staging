"""Apply Craig's staging-only Job Card area rules to exact current operation lines."""
import argparse,hashlib,json,re,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pdc_staging_management_migration import _post,STAGING_REF,PRODUCTION_REF

def opmod():
 import pdc_staging_operation_workbook_import
 return pdc_staging_operation_workbook_import

EXPECTED_WRONG=200
TARGET_COUNTS={"electrical":25,"fitting":146,"hoist":29}
FAMILY={"towbar":"towbars_fitting","long_range":"long_range_tanks_hoist","fire":"fire_extinguishers_fitting","socket":"accessory_12v_socket_plug_electrical","battery":"battery_box_bcdc_electrical","xrs":"xrs370c_electrical","navman":"navman_cardex_electrical"}
STAGE={"electrical":"ELECTRICAL","fitting":"FITTING","hoist":"HOIST","fabrication":"FABRICATION","PARTS":"PARTS","tyre":"TYRE","tint":"TINT","pitInspection":"PIT_INSPECTION","sublet":"SUBLET"}

def classify(s):
 d=s.lower()
 if re.search(r"\btow\s*bars?\b",d):return "fitting","towbar"
 if re.search(r"\b(long\s+range(?:r)?\s+(?:fuel\s+)?tanks?|arb\s+frontier\b.{0,80}\b(?:fuel\s+)?tanks?|sub\s+tank\s+replacem\w*)\b",d):return "hoist","long_range"
 if re.search(r"\bfire\s+ext(?:inguisher|inuisher|inguishers?|inuishers?)?\b",d):return "fitting","fire"
 if re.search(r"\banderson\s+plugs?\b",d):return "electrical","socket"
 if re.search(r"\b12v\b.{0,60}\b(?:acc(?:essory)?\s+socket|plugs?)\b|\b(?:acc(?:essory)?\s+socket|plugs?)\b.{0,60}\b12v\b",d):return "electrical","socket"
 if re.search(r"\b(?:arb\s+)?battery\s+box\b|\bbcdc\d*\b",d):return "electrical","battery"
 if re.search(r"\bxrs\s*370c\b",d):return "electrical","xrs"
 if re.search(r"\bnavman\b|\bcardex\b",d):return "electrical","navman"
 return None,None

def read(sql):return _post(f"https://api.supabase.com/v1/projects/{STAGING_REF}/database/query/read-only","SET TRANSACTION READ ONLY;"+sql)
def rpc(base,actor,name,body):
 r=opmod().request_json(base+"/rest/v1/rpc/"+name,"POST",actor["headers"],body)
 if r.get("ok") is not True:raise RuntimeError(f"PDC_RULE_RPC_FAILED:{name}:{r.get('code')}")
 return r

def frozen_scope():
 rows=read("""select l.operation_line_id::text,v.id::text vehicle_id,v.stock_number,l.description,l.work_key from public.pdc_authenticated_email_operation_lines l join public.vehicles v on v.id=l.vehicle_id order by l.operation_line_id""")
 rules=read("""select f.family_key,v.version_id::text from public.pdc_supervised_rule_families f join public.pdc_supervised_rule_versions v using(family_id) where f.family_key in('towbars_fitting','long_range_tanks_hoist','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical') and exists(select 1 from public.pdc_supervised_rule_events e where e.version_id=v.version_id and e.event_kind='activated') and not exists(select 1 from public.pdc_supervised_rule_events e where e.version_id=v.version_id and e.event_kind in('superseded','disabled','undo'))""")
 versions={x["family_key"]:x["version_id"] for x in rules}
 if set(versions)!=set(FAMILY.values()):raise RuntimeError("PDC_RULE_ACTIVE_FAMILIES_MISSING")
 items=[];all_targets=[]
 for x in rows:
  target,kind=classify(x["description"])
  if not target:continue
  all_targets.append((x,target))
  if x["work_key"]==target:continue
  if x["work_key"] not in STAGE:raise RuntimeError("PDC_RULE_UNKNOWN_SOURCE_STAGE:"+x["work_key"])
  items.append({"operation_line_id":x["operation_line_id"],"expected_stock":x["stock_number"],"expected_normalized_description":x["description"],"target_work_key":target,"target_stage_code":STAGE[target],"source_stage_code":STAGE[x["work_key"]],"rule_version_id":versions[FAMILY[kind]]})
 counts={k:sum(1 for i in items if i["target_work_key"]==k) for k in TARGET_COUNTS}
 if len(items)!=EXPECTED_WRONG or counts!=TARGET_COUNTS or len(all_targets)!=234:raise RuntimeError("PDC_RULE_SCOPE_DRIFT:"+json.dumps({"items":len(items),"counts":counts,"all":len(all_targets)},sort_keys=True))
 return items,counts

def verify():
 q="""with x as(select l.operation_line_id,v.id vehicle_id,v.stock_number,l.description,l.work_key source_work_key,coalesce(a.stage_code,case l.work_key when 'electrical' then 'ELECTRICAL' when 'fitting' then 'FITTING' when 'hoist' then 'HOIST' when 'fabrication' then 'FABRICATION' when 'PARTS' then 'PARTS' when 'tyre' then 'TYRE' when 'tint' then 'TINT' when 'pitInspection' then 'PIT_INSPECTION' when 'sublet' then 'SUBLET' end) effective_stage from public.pdc_authenticated_email_operation_lines l join public.vehicles v on v.id=l.vehicle_id left join lateral(select stage_code from public.vehicle_workshop_line_adjustments z where (z.source_operation_line_id=l.operation_line_id or z.line_key='source:'||l.operation_line_id::text) and z.active order by z.updated_at desc limit 1)a on true), matched as(select * from x where lower(description)~'(tow ?bar|long range|long ranger|frontier.*fuel tank|sub tank replacem|fire ext|fire exting|fire extinuisher|12v.*(acc socket|plug)|(acc socket|plug).*12v|battery box|bcdc|xrs ?370|navman|cardex)') select jsonb_build_object('matched_lines',count(*),'wrong_effective',count(*)filter(where effective_stage<>case when lower(description)~'tow ?bar|fire ext|fire exting|fire extinuisher' then 'FITTING' when lower(description)~'long range|long ranger|frontier.*fuel tank|sub tank replacem' then 'HOIST' else 'ELECTRICAL' end),'by_stage',(select jsonb_object_agg(effective_stage,n)from(select effective_stage,count(*)n from matched group by effective_stage)q),'adjustments',(select count(*)from public.vehicle_workshop_line_adjustments where active and line_key like 'source:%'),'active_rules',(select count(*)from public.pdc_supervised_rule_families f join public.pdc_supervised_rule_versions v using(family_id) where f.family_key in('towbars_fitting','long_range_tanks_hoist','fire_extinguishers_fitting','accessory_12v_socket_plug_electrical','battery_box_bcdc_electrical','xrs370c_electrical','navman_cardex_electrical') and exists(select 1 from public.pdc_supervised_rule_events e where e.version_id=v.version_id and e.event_kind='activated') and not exists(select 1 from public.pdc_supervised_rule_events e where e.version_id=v.version_id and e.event_kind in('superseded','disabled','undo'))),'active_writers',(select count(*)from public.pdc_monitor_stage_activation_writers where active and revoked_at is null),'active_mailboxes',(select count(*)from public.monitored_mailboxes where active),'monitor_status',(select running_status from public.pdc_email_monitor_status where singleton)) evidence from matched"""
 e=read(q)[0]["evidence"]
 if e["matched_lines"]!=234 or e["wrong_effective"]!=0 or e["by_stage"]!={"ELECTRICAL":44,"FITTING":161,"HOIST":29} or e["adjustments"]!=200 or e["active_rules"]!=7 or e["active_writers"]!=0 or e["active_mailboxes"]!=0 or e["monitor_status"]!="stopped":raise RuntimeError("PDC_RULE_READBACK_FAILED:"+json.dumps(e,sort_keys=True))
 return e

def main():
 a=argparse.ArgumentParser();a.add_argument("--apply",action="store_true");a.add_argument("--confirmation");a.add_argument("--receipt",type=Path);args=a.parse_args();op=opmod()
 env=op.env(op.WEBSITE_ENV);base=env["PDC_STAGING_SUPABASE_URL"]
 if env.get("PDC_STAGING_PROJECT_REF")!=STAGING_REF or PRODUCTION_REF in base:raise RuntimeError("PDC_RULE_TARGET_GUARD")
 admin=op.auth(base,env["PDC_STAGING_ANON_KEY"],env["PDC_STAGING_ADMIN_EMAIL"],env["PDC_STAGING_ADMIN_PASSWORD"])
 if admin["role"]!="administrator":raise RuntimeError("PDC_RULE_ADMIN_REQUIRED")
 items,counts=frozen_scope()
 if not args.apply:
  print(json.dumps({"status":"PREPARED","wrong_lines":len(items),"target_counts":counts},sort_keys=True));return 0
 if args.confirmation!="CRAIG APPROVED DURABLE JOBCARD AREA RULES":raise RuntimeError("PDC_RULE_CONFIRMATION_REQUIRED")
 batches=[]
 for index,start in enumerate(range(0,len(items),100),1):
  chunk=items[start:start+100];raw=json.dumps(chunk,sort_keys=True,separators=(",",":"));key=f"craig-owner-jobcard-area-rules-20260824-{index}-{hashlib.sha256(raw.encode()).hexdigest()[:16]}"
  scoped=rpc(base,admin,"scope_pdc_supervised_corrections_213",{"p_idempotency_key":key,"p_reason":"Craig-directed durable Job Card area correction; exact immutable line, Stock and description scope","p_items":chunk})
  batch_id=scoped["data"]["batch_id"];applied=rpc(base,admin,"apply_pdc_supervised_correction_batch_213",{"p_batch_id":batch_id});replay=rpc(base,admin,"apply_pdc_supervised_correction_batch_213",{"p_batch_id":batch_id})
  batches.append({"batch_id":batch_id,"idempotency_key":key,"item_count":len(chunk),"apply":applied,"replay":replay})
 evidence=verify();result={"schema":"pdc-owner-jobcard-area-rules-v1","status":"APPLIED","project_ref":STAGING_REF,"scope_count":len(items),"target_counts":counts,"batches":batches,"readback":evidence,"production_touched":False}
 if args.receipt:args.receipt.parent.mkdir(parents=True,exist_ok=True);args.receipt.write_text(json.dumps(result,indent=2,sort_keys=True),encoding="utf-8")
 print(json.dumps({"status":"APPLIED","scope_count":len(items),"target_counts":counts,"readback":evidence,"receipt":str(args.receipt.resolve()) if args.receipt else None},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
