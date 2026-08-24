"""Read-only inventory for overnight Workshop scenarios 005-007."""
from __future__ import annotations
import json, pathlib, urllib.error, urllib.request

ROOT=pathlib.Path(__file__).resolve().parents[1]
ENV=pathlib.Path(r"C:\Users\nwmgr\AppData\Local\hermes\profiles\website-development-lead\.env")
REF="cdsmnqxtyyoeoznmbidd"; RUN="HERMES-TEST-RUN-20260824"

def values():
 out={}
 for raw in ENV.read_text(encoding="utf-8-sig").splitlines():
  s=raw.strip()
  if s and not s.startswith("#") and "=" in s:
   k,v=s.split("=",1);out[k.strip()]=v.strip().strip("'\"")
 return out

def request(url,headers,body):
 req=urllib.request.Request(url,data=json.dumps(body).encode(),method="POST",headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=120) as res:return res.status,json.load(res)
 except urllib.error.HTTPError as exc:return exc.code,json.loads(exc.read().decode("utf-8","replace"))

def main():
 e=values();base=e["PDC_STAGING_SUPABASE_URL"].rstrip("/");key=e["PDC_STAGING_ANON_KEY"]
 if e.get("PDC_STAGING_PROJECT_REF")!=REF or REF not in base:raise RuntimeError("target guard")
 status,session=request(base+"/auth/v1/token?grant_type=password",{"apikey":key,"Content-Type":"application/json"},{"email":e["PDC_STAGING_ADMIN2_EMAIL"],"password":e["PDC_STAGING_ADMIN2_PASSWORD"]})
 if status!=200:raise RuntimeError("auth failed")
 headers={"apikey":key,"Authorization":"Bearer "+session["access_token"],"Content-Type":"application/json"}
 def rpc(name,payload):return request(base+"/rest/v1/rpc/"+name,headers,payload)
 status,state=rpc("read_pdc_hermes_test_mutation_state_365",{"p_run_id":RUN,"p_vehicle_id":None})
 if status!=200 or state.get("ok") is not True:raise RuntimeError(json.dumps(state)[:800])
 chosen=[r for r in state.get("vehicles") or [] if r.get("scenario_no") in (5,6,7)]
 status,eligibility=rpc("get_workshop_eligibility_snapshot",{})
 if status!=200:raise RuntimeError(f"eligibility {status} {json.dumps(eligibility)[:800]}")
 snapshots=[]
 for stage_code in ("FITTING","ELECTRICAL"):
  status,snapshot=rpc("get_station_workshop_snapshot",{"p_stage_code":stage_code,"p_date_from":"2026-08-25","p_date_to":"2026-08-31"})
  if status!=200:raise RuntimeError(f"station snapshot {stage_code} {status} {json.dumps(snapshot)[:800]}")
  snapshots.append(snapshot)
 ids={r["vehicle"]["id"] for r in chosen}
 candidates=[c for c in eligibility.get("candidates") or [] if (c.get("vehicle") or {}).get("id") in ids]
 relevant_bookings=[b for snapshot in snapshots for b in snapshot.get("bookings") or []]
 bays=[b for snapshot in snapshots for b in snapshot.get("bays") or []]
 print(json.dumps({"vehicles":chosen,"stages":eligibility.get("stages"),"bays":bays,"relevant_bookings":relevant_bookings,"candidates":candidates,"semantics":eligibility.get("semantics")},indent=2,sort_keys=True))
if __name__=="__main__":main()
