#!/usr/bin/env python3
"""Post-install two-session TOCTOU regression for migration 065.

Creates short-lived, namespaced staging fixtures with triggers disabled, proves Apply
blocks behind a canonical identity writer, then fails closed after that writer commits.
All fixtures are deleted in a finally block; business revisions are unchanged.
"""
from __future__ import annotations
import hashlib
import json
import sys
import threading
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from staging_env import load_local_env
from staging_conn import get_conn


def claims(cur, user):
    cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (str(user[0]),))
    cur.execute("select set_config('request.jwt.claim.email',%s,true)", (user[1],))
    cur.execute("select set_config('request.jwt.claim.role','authenticated',true)")


def main():
    load_local_env()
    setup = get_conn()
    writer = get_conn()
    applier = get_conn()
    marker = uuid.uuid4().hex
    proposal_id = str(uuid.uuid4())
    permanent_id = 'QA-AI-065-RACE-' + marker
    result = {}
    try:
        setup.autocommit = True
        q = setup.cursor()
        q.execute("select auth_user_id,email from public.pdc_user_roles where role='administrator' and account_status='approved' and active order by email limit 1")
        admin = q.fetchone()
        if not admin:
            raise RuntimeError('No active Administrator fixture')
        q.execute("""select r.id::text,public.normalize_vehicle_stock_number(r.normalized_data->>'batch'),r.version,n.revision
          from public.navision_backend_records r cross join public.navision_backend_revision n
          where n.singleton and r.is_current and r.record_status='current' and not r.is_quoted
            and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
            and not exists(select 1 from public.navision_board_activations a where a.backend_record_id=r.id)
            and not exists(select 1 from public.vehicles v where v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch') and v.deleted_at is null)
          order by r.id limit 1""")
        record = q.fetchone()
        if not record:
            raise RuntimeError('No eligible race-test identity')
        rid, stock, record_version, nav_revision = record
        q.execute("select revision from public.pdc_ai_intake_revision where singleton")
        inbox_revision = q.fetchone()[0]
        source_hash = hashlib.sha256(('source-' + marker).encode()).hexdigest()
        evidence_hash = hashlib.sha256(('evidence-' + marker).encode()).hexdigest()
        fingerprint = hashlib.sha256(('fingerprint-' + marker).encode()).hexdigest()[:16].upper()
        q.execute("""insert into public.pdc_ai_intake_proposals(
          proposal_id,source_uid,source_hash,evidence_hash,source_account,sender_address,source_received_at,
          authentication,subject,action_type,stock_number,backend_record_id,backend_record_version,
          observed_navision_revision,summary,observations,fingerprint,status,version,submitted_by)
          values(%s::uuid,%s,%s,%s,'qa-race','qa@perthmotorbodies.com.au',clock_timestamp(),
          '{"gmail_authentication_results":true,"spf":"pass"}'::jsonb,'QA migration 065 identity race',
          'board_activate_only',%s,%s::uuid,%s,%s,'Two-session rollback fixture','{}'::jsonb,%s,'pending',1,%s::uuid)""",
          (proposal_id, 'qa-' + marker, source_hash, evidence_hash, stock, rid, record_version, nav_revision, fingerprint, str(admin[0])))

        writer.autocommit = False
        w = writer.cursor()
        w.execute("set local session_replication_role=replica")
        w.execute("insert into public.vehicles(permanent_vehicle_id,stock_number) values(%s,%s)", (permanent_id, stock))

        def apply():
            try:
                applier.autocommit = False
                a = applier.cursor()
                claims(a, admin)
                a.execute("select public.decide_pdc_ai_intake_proposal(%s,%s::uuid,1,%s,'board_activate_only','apply',%s,%s,%s)", (
                    'pdc-ai-intake-' + uuid.uuid4().hex, proposal_id, inbox_revision, fingerprint, nav_revision,
                    'Administrator two-session identity race regression'))
                result['body'] = a.fetchone()[0]
                applier.rollback()
            except Exception as error:
                result['error'] = repr(error)
                applier.rollback()

        thread = threading.Thread(target=apply, daemon=True)
        thread.start()
        time.sleep(0.75)
        if not thread.is_alive():
            raise AssertionError('Apply did not block behind canonical identity writer')
        writer.commit()
        thread.join(10)
        if thread.is_alive():
            raise AssertionError('Apply remained blocked after writer commit')
        if result.get('error'):
            raise AssertionError(result['error'])
        body = result.get('body') or {}
        if body.get('ok') is not False or body.get('code') != 'operational_identity_present':
            raise AssertionError(f'Apply did not fail closed: {body!r}')
        print(json.dumps({'apply_blocked': True, 'revalidation': 'operational_identity_present', 'activation_created': False, 'production_contacted': False}, sort_keys=True))
    finally:
        try:
            writer.rollback()
        except Exception:
            pass
        try:
            applier.rollback()
        except Exception:
            pass
        try:
            setup.autocommit = True
            q = setup.cursor()
            q.execute("set session_replication_role=replica")
            q.execute("delete from public.pdc_ai_intake_decision_receipts where proposal_id=%s::uuid", (proposal_id,))
            q.execute("delete from public.pdc_ai_intake_history where proposal_id=%s::uuid", (proposal_id,))
            q.execute("delete from public.pdc_ai_intake_proposals where proposal_id=%s::uuid", (proposal_id,))
            q.execute("delete from public.vehicles where permanent_vehicle_id=%s", (permanent_id,))
            q.execute("set session_replication_role=origin")
        finally:
            setup.close(); writer.close(); applier.close()


if __name__ == '__main__':
    main()
