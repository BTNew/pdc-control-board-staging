from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "fixtures" / "ai_auditor_signing_boundaries_253.json"
data = json.loads(FIXTURE.read_text(encoding="utf-8"))
assert data["contract"] == "pdc-auditor-signing-boundaries-253-v1"
print("\\set ON_ERROR_STOP on")
print("do $vectors$ begin")
for vector in data["canonical_json"]:
    value = json.dumps(vector["value"], ensure_ascii=False, separators=(",", ":"))
    expected = vector["canonical_utf8"].replace("'", "''")
    payload = value.replace("'", "''")
    name = vector["name"].replace("'", "''")
    print(f" if public.pdc_auditor_canonical_json_253('{payload}'::jsonb) <> '{expected}' then raise exception 'shared canonical vector failed: {name}'; end if;")
for vector in data["negative_envelopes"]:
    name = vector["name"].replace("'", "''")
    issued = vector.get("mutation", {}).get("issued_at")
    if issued is not None:
        issued_sql = issued.replace("'", "''")
        expected = "true" if vector["valid_shape"] else "false"
        print(f" if ('{issued_sql}' ~ '^\\d{{4}}-\\d{{2}}-\\d{{2}}T\\d{{2}}:\\d{{2}}:\\d{{2}}(\\.\\d{{1,6}})?Z$') is distinct from {expected} then raise exception 'shared timestamp vector failed: {name}'; end if;")
print("end $vectors$;")
print("select 'AI_AUDITOR_253_SHARED_SIGNING_BOUNDARIES_PASS' result;")
