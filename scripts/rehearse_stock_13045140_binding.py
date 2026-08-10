from __future__ import annotations

import json
import os
import sys
import uuid
from pathlib import Path

import psycopg2
from psycopg2.extras import Json

sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env  # noqa: E402

STOCK = "13045140"
VIN = "MR0REBHV100548367"
JOB_CARD = "J139125431"

load_local_env()
dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
assert_staging_target(database_url=dsn)

conn = psycopg2.connect(dsn)
conn.autocommit = False
try:
    with conn.cursor() as cur:
        cur.execute(
            """
            select p.source_hash,p.evidence_hash,p.source_uid,p.sender_address,p.authentication,
                   p.source_received_at,p.subject,p.observations,p.submitted_by::text,r.email
            from public.pdc_ai_intake_proposals p
            join public.pdc_user_roles r on r.auth_user_id=p.submitted_by
            join public.pdc_monitor_stage_activation_writers w on w.user_id=p.submitted_by and w.active and w.revoked_at is null
            where public.normalize_vehicle_stock_number(p.stock_number)=%s
              and r.role='viewer' and r.active and r.account_status='approved'
            order by p.submitted_at desc limit 1
            """,
            (STOCK,),
        )
        row = cur.fetchone()
        if not row:
            raise RuntimeError("retained proposal or enrolled actor missing")
        source_hash,evidence_hash,source_uid,sender,authentication,received_at,subject,observations,actor_id,actor_email = row
        required_work = observations.get("required_work") if isinstance(observations, dict) else []
        email_vehicle = {
            "cancelled": False,
            "conflicts": [],
            "customer_name": None,
            "eta_to_kewdale": None,
            "job_card_number": JOB_CARD,
            "registration": None,
            "stock_numbers": [STOCK],
            "toyota_order_number": None,
            "vehicle_description": None,
            "vins": [VIN],
        }
        claims = json.dumps({"sub": actor_id, "email": actor_email, "role": "authenticated"})
        cur.execute("select set_config('request.jwt.claims',%s,true)", (claims,))
        cur.execute("set local role authenticated")

        def rehearse(label: str, candidate_evidence: str) -> str:
            cur.execute("savepoint rehearsal")
            key = "pdc-email-import-binding-rehearsal-" + uuid.uuid4().hex
            cur.execute(
                """
                select public.import_pdc_authenticated_vehicle_email(
                  %s,%s,%s,%s,%s,%s,%s,%s,%s,%s
                )
                """,
                (key,source_hash,candidate_evidence,source_uid,sender,Json(authentication),received_at,subject,Json(email_vehicle),Json(required_work)),
            )
            result = cur.fetchone()[0]
            cur.execute("rollback to savepoint rehearsal")
            return str(result.get("code") or result.get("message") or "unknown")

        exact_code = rehearse("proposal", evidence_hash)
        different = "0" * 64 if evidence_hash != "0" * 64 else "1" * 64
        changed_code = rehearse("different", different)
        print(json.dumps({
            "exact_proposal_evidence": exact_code,
            "different_valid_evidence": changed_code,
            "all_changes_rolled_back": True,
            "required_work_count": len(required_work or []),
            "stock": STOCK,
        }, sort_keys=True))
finally:
    conn.rollback()
    conn.close()
