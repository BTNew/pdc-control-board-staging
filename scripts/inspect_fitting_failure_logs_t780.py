#!/usr/bin/env python3
"""Inspect the STAGING logs for Craig's Fitting rejection."""
from __future__ import annotations

import json
import sys
import urllib.parse
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from inspect_pdc14_staging import STAGING_REF, supabase_access_token  # noqa: E402

START = "2026-09-08T22:30:00Z"
END = "2026-09-08T23:30:00Z"
SQL = """
select
  timestamp,
  source,
  event_message
from logs
where source = 'postgres_logs'
  and event_message ilike '%operation_estimate_duration_mismatch%'
  or (source = 'edge_logs'
      and event_message ilike '%administrator_schedule_workshop_vehicle%')
order by timestamp desc
limit 100
"""

params = urllib.parse.urlencode({
    "iso_timestamp_start": START,
    "iso_timestamp_end": END,
    "sql": SQL,
})
request = Request(
    f"https://api.supabase.com/v1/projects/{STAGING_REF}/analytics/endpoints/logs?{params}",
    headers={
        "Authorization": f"Bearer {supabase_access_token()}",
        "Accept": "application/json",
        "User-Agent": "pdc-staging-t780-log-inspection/1",
    },
)
with urlopen(request, timeout=60) as response:
    result = json.load(response)

output = {
    "project_ref": STAGING_REF,
    "range": {"start": START, "end": END},
    "result": result,
    "production_contacted": False,
}
out = ROOT / "review-evidence" / "t_780b25d4" / "craig-90-minute-failure-logs.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
print(json.dumps(output, indent=2))
