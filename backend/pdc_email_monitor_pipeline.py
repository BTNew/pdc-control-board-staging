#!/usr/bin/env python
"""Fail-closed dispatcher for one profile-owned retained PMB intake item.

The owning pdc-monitor supplies retained provider/attachment evidence.  This
module never polls mail, sends messages, or stores credentials.
"""
from __future__ import annotations
import hashlib,json
from typing import Any,Mapping
try:
    from backend.pdc_email_communication_parser import parse_communication_actions
    from backend.pdc_communication_runtime_client import execute_communication_request
    from backend.pdc_jobcard_runtime_client import RpcClient,RuntimeContractError,execute_jobcard_request
except ModuleNotFoundError:
    from pdc_email_communication_parser import parse_communication_actions
    from pdc_communication_runtime_client import execute_communication_request
    from pdc_jobcard_runtime_client import RpcClient,RuntimeContractError,execute_jobcard_request


def _mapping(value:Any,label:str)->dict[str,Any]:
    if not isinstance(value,Mapping):raise RuntimeContractError(f"{label} must be an object")
    return dict(value)
def _hash(value:Any)->str:
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False).encode()).hexdigest()

def execute_retained_intake(service_client:RpcClient,actor_client:RpcClient,item:Mapping[str,Any])->dict[str,Any]:
    request=_mapping(item,"intake item")
    keys=set(request)
    common={"intake_id","expected_source_hash","provider","kind"}
    if request.get("kind")=="jobcard":
        if keys!=common|{"extraction"}:raise RuntimeContractError("jobcard intake keys are invalid")
        extraction=_mapping(request["extraction"],"jobcard extraction")
        provider=_mapping(request["provider"],"provider")
        return execute_jobcard_request(service_client,actor_client,{"intake_id":request["intake_id"],"expected_source_hash":request["expected_source_hash"],"extraction_hash":_hash(extraction),"provider":{k:v for k,v in provider.items() if k!="attachment_source_hash"},"extraction":extraction})
    if request.get("kind")!="communication" or keys!=common|{"retained_text"}:
        raise RuntimeContractError("intake kind or keys are invalid")
    provider=_mapping(request["provider"],"provider")
    parsed=parse_communication_actions(str(request.get("retained_text") or ""))
    if parsed.get("auto_applicable") is not True:
        return {"ok":False,"phase":"review_required","code":"communication_review_required","review_reasons":parsed.get("review_reasons",[]),"mutation_attempted":False,"message_sent":False}
    extraction={**parsed,"authentication":provider.get("authentication"),"canonical_attachment_id":provider.get("attachment_id"),"canonical_document_hash":provider.get("attachment_source_hash"),"contract_version":"pmb-email-communications-v1"}
    return execute_communication_request(service_client,actor_client,{"intake_id":request["intake_id"],"expected_source_hash":request["expected_source_hash"],"extraction_hash":_hash(extraction),"provider":{k:v for k,v in provider.items() if k!="attachment_source_hash"},"extraction":extraction})

__all__=["execute_retained_intake"]
