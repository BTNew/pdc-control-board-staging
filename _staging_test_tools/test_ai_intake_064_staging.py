#!/usr/bin/env python3
"""Transactional runtime gate for migration 064 containment; always rolls back."""
from __future__ import annotations
import json, sys, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / '_staging_test_tools')]
from staging_env import load_local_env  # noqa:E402
from staging_conn import get_conn  # noqa:E402


def main() -> int:
    load_local_env()
    conn = get_conn()
    conn.autocommit = False
    cur = conn.cursor()
    try:
        cur.execute("select user_id::text from public.pdc_monitor_stage_activation_writers where active order by granted_at limit 1")
        viewer = cur.fetchone()[0]
        cur.execute("select auth_user_id::text from public.pdc_user_roles where role='administrator' and active and account_status='approved' order by updated_at desc limit 1")
        admin = cur.fetchone()[0]
        cur.execute("select id::text,email from auth.users where id in (%s::uuid,%s::uuid)", (viewer, admin))
        auth_emails = {row[0]: row[1] for row in cur.fetchall()}
        cur.execute("select count(*) from public.pdc_ai_intake_proposals")
        proposals_before = cur.fetchone()[0]
        cur.execute("select count(*) from public.navision_board_activations")
        activations_before = cur.fetchone()[0]
        cur.execute("select revision from public.navision_backend_revision where singleton")
        navision_revision_before = cur.fetchone()[0]
        cur.execute("select to_regprocedure('public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text)')")
        assert cur.fetchone()[0] is None

        cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({'sub':viewer,'email':auth_emails[viewer]}),))
        cur.execute("select public.get_pdc_ai_intake_snapshot('pending',100)")
        viewer_snapshot = cur.fetchone()[0]
        assert viewer_snapshot['code'] == 'unauthorized', viewer_snapshot

        source_hash = uuid.uuid4().hex + uuid.uuid4().hex
        evidence_hash = uuid.uuid4().hex + uuid.uuid4().hex
        cur.execute("select public.submit_pdc_ai_intake_observation(%s,%s,%s,%s,%s::jsonb,now(),%s,%s,%s,%s,%s::jsonb)", (
            source_hash, evidence_hash, f'containment-064-{uuid.uuid4().hex}',
            'noreply@broometoyota.com.au',
            json.dumps({'sender_domain':'broometoyota.com.au','gmail_authentication_results':True,'spf_aligned':True,'dkim_aligned':False,'dmarc_aligned':True}),
            '[TRANSACTIONAL TEST] Observation only', 'review_only', '',
            'Migration 064 proposal-only runtime gate.', json.dumps({'test_namespace':'AI-INTAKE-064-ROLLBACK'}),
        ))
        submitted = cur.fetchone()[0]
        assert submitted['ok'] is True and submitted['data']['status'] == 'pending', submitted

        cur.execute("select set_config('request.jwt.claims',%s,true)", (json.dumps({'sub':admin,'email':auth_emails[admin]}),))
        cur.execute("select public.get_pdc_ai_intake_snapshot('pending',100)")
        admin_snapshot = cur.fetchone()[0]
        assert admin_snapshot['ok'] is True and admin_snapshot['code'] == 'snapshot', admin_snapshot

        conn.rollback()
        cur.execute("select count(*) from public.pdc_ai_intake_proposals")
        proposals_after = cur.fetchone()[0]
        cur.execute("select count(*) from public.navision_board_activations")
        activations_after = cur.fetchone()[0]
        cur.execute("select revision from public.navision_backend_revision where singleton")
        navision_revision_after = cur.fetchone()[0]
        assert proposals_after == proposals_before
        assert activations_after == activations_before
        assert navision_revision_after == navision_revision_before
        print(json.dumps({'ok':True,'decision_rpc_absent':True,'viewer_snapshot_denied':True,'viewer_observation_rolled_back':True,'admin_snapshot_allowed':True,'proposals':proposals_after,'activations':activations_after,'navision_revision':navision_revision_after}))
        return 0
    finally:
        conn.rollback()
        conn.close()

if __name__ == '__main__':
    raise SystemExit(main())
