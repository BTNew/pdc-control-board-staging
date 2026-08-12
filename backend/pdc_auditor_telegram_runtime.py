#!/usr/bin/env python
"""Bounded Telegram natural-language adapter for staging AI Auditor operation changes.

The parser recognizes a deliberately small command grammar. Database RPCs own matching,
immutable planning, authorization, atomic apply, rule versioning, replay and rollback.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, sys
from typing import Any, Mapping
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

STAGING_PROJECT = "cdsmnqxtyyoeoznmbidd"
STAGING_URL = f"https://{STAGING_PROJECT}.supabase.co"
CRAIG_TELEGRAM_ID = 7828138290
PLAN_RPC = "plan_pdc_auditor_telegram_instruction_225"
APPLY_RPC = "apply_pdc_auditor_telegram_plan_226"
RULE_RPC = "rule_pdc_auditor_telegram_227"
UNDO_RPC = "undo_last_pdc_auditor_telegram_run_226"
QUERY_RPC = "query_pdc_auditor_telegram_225"

class AuditorContractError(ValueError): pass

def _exact_url(value: str) -> str:
    p=urlsplit(value)
    if p.scheme!="https" or p.hostname!=f"{STAGING_PROJECT}.supabase.co" or p.port is not None or p.username or p.password or p.path not in ("", "/") or p.query or p.fragment:
        raise AuditorContractError("Supabase URL is not the exact staging origin")
    return STAGING_URL

def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip()).lower()

def _hours(text: str) -> float | None:
    m=re.search(r"\b(\d+(?:\.\d{1,2})?)\s*(?:hours?|hrs?)\b", text, re.I)
    if not m:return None
    value=float(m.group(1))
    if value<0.25 or value>999.75 or round(value*4)!=value*4:raise AuditorContractError("hours must use quarter-hour precision")
    return value

def parse_instruction(instruction: str, context: Mapping[str, Any] | None=None) -> dict[str, Any]:
    if not isinstance(instruction,str) or instruction!=instruction.strip() or not 3<=len(instruction)<=4000:raise AuditorContractError("instruction is invalid")
    c=dict(context or {}); t=_norm(instruction)
    review=bool(re.match(r"^(review|audit|check|find|show)\b",t))
    if t in {"show auditor rules","show learned rules","show rules"}:return {"action":"show_rules","mode":"rule","scope":{}}
    if t.startswith("why did you change") or t.startswith("why was this changed"):
        if not c.get("operation_line_id"):return {"action":"clarification","question":"Which operation line should I explain?"}
        return {"action":"explain_line","mode":"query","scope":{"operation_line_id":c["operation_line_id"]}}
    if t in {"undo the last auditor run","undo last auditor run"}:return {"action":"undo_last_run","mode":"undo","scope":{}}
    if t in {"undo my last rule","undo the last rule","undo last rule"}:return {"action":"undo_last_rule","mode":"rule","scope":{}}
    if t.startswith("disable the ") and t.endswith(" rule"):
        return {"action":"disable_rule","mode":"rule","scope":{"rule_selector":t[12:-5].strip()}}
    if t.startswith("correct the ") and " rule " in t:
        h=_hours(t)
        if h is None:return {"action":"clarification","question":"What exact hours should the corrected rule use?"}
        return {"action":"correct_rule","mode":"rule","scope":{"rule_selector":t[12:t.index(" rule ")].strip(),"estimated_hours":h}}
    remember=t.startswith("remember:") or t.startswith("remember ") or "apply this rule to future audits" in t or t.startswith("learn:")
    if remember:
        h=_hours(t)
        if "gvm" in t and h is not None:return {"action":"remember_rule","mode":"rule","scope":{"category":"gvm_upgrade","estimated_hours":h,"include":["gvm upgrade","gross vehicle mass upgrade"],"exclude":["long range fuel tank","fuel tank"]}}
        if "long-range" in t or "long range" in t:return {"action":"remember_rule","mode":"rule","scope":{"category":"long_range_fuel_tank","work_key":"hoist","include":["long range fuel tank","long-range fuel tank"],"exclude":["gvm upgrade"]}}
        return {"action":"clarification","question":"Which exact operation code, description or category should this rule match?"}
    if "duplicate" in t and ("bullbar" in t or "bull bar" in t):
        return {"action":"duplicate_bullbars","mode":"review" if review else "apply","scope":{"category":"bullbar","confirmed_only":not review}}
    if "gvm" in t and any(v in t for v in ("adjust","change","fix","update","correct","review","audit","check","find","show")):
        h=_hours(t)
        if not review and h is None:return {"action":"clarification","question":"What exact hours should genuine GVM upgrades use?"}
        return {"action":"gvm_hours","mode":"review" if review else "apply","scope":{"category":"gvm_upgrade",**({"estimated_hours":h} if h is not None else {})}}
    if ("long-range fuel tank" in t or "long range fuel tank" in t) and any(v in t for v in ("move","change","review","audit","check","find","show")):
        return {"action":"long_range_tank_department","mode":"review" if review else "apply","scope":{"category":"long_range_fuel_tank","work_key":"hoist"}}
    if "tint" in t and review:return {"action":"review_category","mode":"review","scope":{"category":"tint"}}
    stock=re.search(r"\bstock\s+(\d{4,20})\b",t)
    if stock and any(v in t for v in ("hours","correct","adjust","change","fix","update")):
        h=_hours(t)
        if h is None:return {"action":"clarification","question":f"What exact hours should be applied to Stock {stock.group(1)}?"}
        return {"action":"stock_hours","mode":"apply","scope":{"stock_number":stock.group(1),"estimated_hours":h}}
    dep=re.search(r"\b(?:move|change) this operation to (fitting|tint|hoist(?:/gvm)?|electrical|fabrication|tyre|pit(?: inspection)?)\b",t)
    if dep:
        if not c.get("operation_line_id"):return {"action":"clarification","question":"Which operation line should I change?"}
        work={"hoist/gvm":"hoist","pit inspection":"pitInspection","pit":"pitInspection"}.get(dep.group(1),dep.group(1))
        return {"action":"line_department","mode":"apply","scope":{"operation_line_id":c["operation_line_id"],"work_key":work}}
    if "apply this correction to all matching vehicles" in t:
        if not c.get("rule_version_id") and not c.get("source_plan_id"):return {"action":"clarification","question":"Which reviewed correction should I apply to all matching vehicles?"}
        return {"action":"apply_matching","mode":"apply","scope":{k:c[k] for k in ("rule_version_id","source_plan_id") if c.get(k)}}
    return {"action":"clarification","question":"Please specify the operation, scope and intended change."}

def bind_telegram(update: Any, *, expected_chat_id: int, bot_identity: str) -> dict[str,Any]:
    if not isinstance(update,Mapping) or set(update)!={"update_id","message"}:raise AuditorContractError("Telegram update keys are invalid")
    m=update["message"]
    if not isinstance(m,Mapping) or set(m)!={"message_id","from","chat","date","text"}:raise AuditorContractError("Telegram message keys are invalid")
    sender=m["from"]
    if not isinstance(sender,Mapping) or set(sender)!={"id","is_bot"} or sender["is_bot"] is not False or isinstance(sender["id"],bool) or not isinstance(sender["id"],int) or sender["id"]<1:
        raise AuditorContractError("Telegram sender shape is invalid")
    if m["chat"]!={"id":expected_chat_id,"type":"private"}:raise AuditorContractError("Telegram chat is not the configured private chat")
    text=m["text"]
    if not isinstance(text,str) or text!=text.strip() or not 3<=len(text)<=4000:raise AuditorContractError("Telegram text is invalid")
    if not isinstance(m["message_id"],int) or isinstance(m["message_id"],bool) or m["message_id"]<1:raise AuditorContractError("Telegram message ID is invalid")
    return {"original_instruction":text,"telegram_sender_id":sender["id"],"telegram_chat_id":expected_chat_id,"telegram_message_id":m["message_id"],"telegram_update_id":update["update_id"],"bot_identity":bot_identity,"instruction_sha256":hashlib.sha256(text.encode()).hexdigest()}

class RpcClient:
    def __init__(self,url:str,apikey:str,bearer:str):self.url=_exact_url(url);self.apikey=apikey;self.bearer=bearer
    def rpc(self,name:str,payload:dict[str,Any])->dict[str,Any]:
        if name not in {PLAN_RPC,APPLY_RPC,RULE_RPC,UNDO_RPC,QUERY_RPC}:raise AuditorContractError("RPC is not allowlisted")
        req=Request(f"{self.url}/rest/v1/rpc/{name}",data=json.dumps(payload,separators=(",",":"),sort_keys=True).encode(),headers={"apikey":self.apikey,"Authorization":f"Bearer {self.bearer}","Content-Type":"application/json"},method="POST")
        with urlopen(req,timeout=30) as r: value=json.loads(r.read())
        if not isinstance(value,dict) or set(value)-{"ok","code","data"}:raise AuditorContractError("RPC response envelope is invalid")
        return value

def execute_bound(client:RpcClient,update:Any,*,expected_chat_id:int,bot_identity:str,context:Mapping[str,Any]|None=None)->dict[str,Any]:
    evidence=bind_telegram(update,expected_chat_id=expected_chat_id,bot_identity=bot_identity); command=parse_instruction(evidence["original_instruction"],context)
    if command["action"]=="clarification":return {"ok":True,"code":"clarification_required","data":{"question":command["question"]}}
    if command["mode"]=="query":return client.rpc(QUERY_RPC,{"p_action":command["action"],"p_scope":command["scope"],"p_telegram_evidence":evidence})
    if command["mode"]=="rule":
        action={"remember_rule":"remember","correct_rule":"correct","disable_rule":"disable","undo_last_rule":"undo","show_rules":"show"}[command["action"]]
        return client.rpc(RULE_RPC,{"p_action":action,"p_scope":command["scope"],"p_evidence":evidence})
    if command["mode"]=="undo":return client.rpc(UNDO_RPC,{"p_telegram_evidence":evidence})
    plan=client.rpc(PLAN_RPC,{"p_action":command["action"],"p_mode":command["mode"],"p_scope":command["scope"],"p_telegram_evidence":evidence})
    if command["mode"]=="review" or not plan.get("ok"):return plan
    plan_id=(plan.get("data") or {}).get("plan_id")
    if not plan_id:raise AuditorContractError("plan response omitted plan_id")
    return client.rpc(APPLY_RPC,{"p_plan":plan_id,"p_plan_hash":plan["data"]["plan_hash"],"p_telegram_evidence":evidence})

def client_from_environment()->RpcClient:
    return RpcClient(os.environ.get("SUPABASE_URL",""),os.environ.get("SUPABASE_ANON_KEY",""),os.environ.get("PDC_AUDITOR_ACCESS_TOKEN",""))

def main(argv=None)->int:
    p=argparse.ArgumentParser();p.add_argument("--telegram-update-json",required=True);p.add_argument("--context-json",default="{}");a=p.parse_args(argv)
    try:
        result=execute_bound(client_from_environment(),json.loads(a.telegram_update_json),expected_chat_id=int(os.environ["PDC_AUDITOR_TELEGRAM_CHAT_ID"]),bot_identity=os.environ["PDC_AUDITOR_BOT_IDENTITY"],context=json.loads(a.context_json));print(json.dumps(result,separators=(",",":"),sort_keys=True));return 0 if result.get("ok") else 1
    except Exception as exc:print(json.dumps({"ok":False,"code":"auditor_ingress_error","error":str(exc)},separators=(",",":")),file=sys.stderr);return 2
if __name__=="__main__":raise SystemExit(main())
