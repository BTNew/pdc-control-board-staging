#!/usr/bin/env python3
"""Apply/read back the STAGING-only v2 contract-alignment successor."""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from scripts.diagnose_pdc_email_ai_actual_jwt_replay_staging_20260903 import management_query
from scripts.apply_pdc_email_ai_current_hours_fixture_generation_staging_20260903 import (
    GENERATION_ID,
    PRODUCTION_REF,
    STAGING_REF,
    rpc,
    runtime_headers,
)

VERSION = "20260903121000"
# Explicit review markers: STAGING cdsmnqxtyyoeoznmbidd; reject Production vjdtsswhroyguxyfjdkt.
APPROVAL = "PDC_APPROVE_STAGING_MIGRATION_20260903121000"
MIGRATION = ROOT / "supabase/staging_only/20260903121000_pdc_email_ai_v2_contract_alignment_20260903.sql"
EVIDENCE = ROOT / "review-evidence/t_9cea2926/v2-contract-alignment-staging-verification.json"


def main() -> None:
    if os.environ.get(APPROVAL) != "YES":
        raise RuntimeError(f"Set {APPROVAL}=YES for this reversible STAGING-only migration")
    sql = MIGRATION.read_text(encoding="utf-8")
    if STAGING_REF not in sql or PRODUCTION_REF in sql:
        raise RuntimeError("PDC_CONTRACT_ALIGNMENT_NON_STAGING_REFUSED")
    try:
        management_query(sql)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"STAGING_MIGRATION_HTTP_{exc.code}: {exc.read().decode('utf-8', 'replace')[:2000]}") from exc
    rows = management_query("""
      SELECT
        (SELECT version FROM supabase_migrations.schema_migrations WHERE version~'^[0-9]{14}$' ORDER BY version DESC LIMIT 1) AS ledger_head,
        encode(extensions.digest(convert_to(pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure),'UTF8'),'sha256'),'hex') AS validator_sha256,
        position('''operation_update''' IN pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure))=0 AS operation_update_fail_closed,
        position('^(OP[1-9][0-9]{0,2}|PD[0-9]{3}-[A-F0-9]{8})$' IN pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure))>0 AS operation_number_fully_anchored,
        position('(''job_card'',''ai_estimate'',''business_rule_default'')' IN pg_get_functiondef('public.pdc_email_ai_successor_validate_v2_instruction_20260901(jsonb)'::regprocedure))>0 AS hours_provenance_aligned,
        NOT has_table_privilege('authenticated','public.pdc_email_ai_v2_contract_alignments_20260903','select') AS evidence_private,
        to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL AS production_sentinel_present
    """)[0]
    if str(rows["ledger_head"]) != VERSION or not all(bool(rows[key]) for key in (
        "operation_update_fail_closed", "operation_number_fully_anchored", "hours_provenance_aligned", "evidence_private"
    )) or rows["production_sentinel_present"]:
        raise RuntimeError(f"PDC_CONTRACT_ALIGNMENT_POSTCONDITION_FAILED: {rows}")

    base, headers, _ = runtime_headers()
    last: tuple[int, object] = (0, None)
    for _ in range(20):
        last = rpc(base, headers, "get_pdc_email_ai_v2_acceptance_fixture_generation_20260903", {"p_generation_id": GENERATION_ID})
        if last[0] == 200:
            break
        time.sleep(1)
    if last[0] != 200 or not isinstance(last[1], dict) or not last[1].get("ok") or last[1].get("fixture_count") != 14:
        raise RuntimeError(f"PDC_GENERATION_READBACK_FAILED: {last}")
    if any(bool(row.get("consumed")) for row in last[1].get("fixtures", [])):
        raise RuntimeError("PDC_GENERATION_NO_LONGER_FRESH")

    result = {
        "ok": True,
        "environment": "staging",
        "project_ref": STAGING_REF,
        "migration": VERSION,
        "generation_id": GENERATION_ID,
        "fresh_fixture_count": 14,
        "consumed_fixture_count": 0,
        "deployed_contract": rows,
        "production_contacted": False,
        "production_writes": False,
        "mailbox_contacted": False,
        "outbound_email_sent": False,
    }
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "migration": VERSION, "generation_id": GENERATION_ID, "fresh_fixture_count": 14, "proof": str(EVIDENCE)}, sort_keys=True))


if __name__ == "__main__":
    main()
