from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import psycopg2

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path.home() / "pdc-control-board" / "_staging_test_tools"))
from staging_env import assert_staging_target, load_local_env

STOCK = "13045140"


def main() -> None:
    load_local_env()
    dsn = os.environ.get("PDC_STAGING_DIRECT_DATABASE_URL") or os.environ.get("PDC_STAGING_DATABASE_URL")
    assert_staging_target(database_url=dsn)
    conn = psycopg2.connect(dsn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                select p.proposal_id::text,p.source_hash,lower(p.evidence_hash),p.source_uid,
                       lower(p.sender_address),p.authentication,p.source_received_at,p.subject,
                       p.observations->'required_work',p.submitted_at
                from public.pdc_ai_intake_proposals p
                where public.normalize_vehicle_stock_number(p.stock_number)=%s
                order by p.submitted_at,p.proposal_id
                """,
                (STOCK,),
            )
            proposals = cur.fetchall()
            source_hashes = sorted({row[1] for row in proposals})
            claims = []
            if source_hashes:
                cur.execute(
                    """
                    select c.source_hash,c.proposal_ref,c.contract_name
                    from public.pdc_email_source_claims c
                    where c.source_hash=any(%s)
                    order by c.source_hash,c.proposal_ref
                    """,
                    (source_hashes,),
                )
                claims = cur.fetchall()
            proposal_by_id = {row[0]: row for row in proposals}
            exact_links = sum(
                1
                for source_hash, proposal_ref, contract_name in claims
                if contract_name == "pdc_ai_intake_063"
                and proposal_ref in proposal_by_id
                and proposal_by_id[proposal_ref][1] == source_hash
            )
            source_claims = {
                source_hash
                for source_hash, _proposal_ref, contract_name in claims
                if contract_name == "pdc_ai_intake_063"
            }
            source_bound_proposals = sum(1 for row in proposals if row[1] in source_claims)
            generations = []
            for index, row in enumerate(proposals, start=1):
                proposal_id, source_hash, evidence_hash, source_uid, sender, authentication, received_at, subject, required_work, created_at = row
                linked = any(c[0] == source_hash and c[1] == proposal_id and c[2] == "pdc_ai_intake_063" for c in claims)
                generations.append(
                    {
                        "generation": index,
                        "claim_points_to_this_generation": linked,
                        "source_claim_exists": source_hash in source_claims,
                        "required_work_count": len(required_work) if isinstance(required_work, list) else None,
                        "immutable_fields_present": all(
                            value not in (None, "")
                            for value in (source_hash, evidence_hash, source_uid, sender, authentication, received_at, subject)
                        ),
                        "created_at": created_at.isoformat() if created_at else None,
                    }
                )
            print(
                json.dumps(
                    {
                        "stock": STOCK,
                        "proposal_generations": len(proposals),
                        "claims": len(claims),
                        "exact_claim_generation_links": exact_links,
                        "source_bound_proposals": source_bound_proposals,
                        "generations": generations,
                    },
                    sort_keys=True,
                )
            )
    finally:
        conn.close()


if __name__ == "__main__":
    main()
