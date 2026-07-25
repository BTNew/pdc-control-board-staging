#!/usr/bin/env python3
"""Transactional migration 065 authority, receipt, replay and activation gate."""
from __future__ import annotations
import hashlib, json, re, sys, uuid
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT),str(ROOT/'_staging_test_tools')]
from staging_env import load_local_env  # noqa:E402
from staging_conn import get_conn  # noqa:E402


def migration_body(text: str) -> str:
    a=re.search(r'(?im)^\s*begin;\s*$',text); b=list(re.finditer(r'(?im)^\s*commit;\s*$',text))
    if not a or not b: raise RuntimeError('wrapped migration required')
    return text[a.end():b[-1].start()]


def jwt(cur, user_id: str, email: str):
    cur.execute("select set_config('request.jwt.claim.sub',%s,true)",(user_id,))
    cur.execute("select set_config('request.jwt.claims',%s,true)",(json.dumps({'sub':user_id,'email':email}),))


def call(cur,key,pid,ver,inbox,action,decision,fingerprint,nav,reason):
    cur.execute("select public.decide_pdc_ai_intake_proposal(%s,%s,%s,%s,%s,%s,%s,%s,%s)",(key,pid,ver,inbox,action,decision,fingerprint,nav,reason))
    return cur.fetchone()[0]


def insert_proposal(cur, viewer_id, record, action, fingerprint, subject='QA migration 065 fixture'):
    pid=str(uuid.uuid4()); marker=uuid.uuid4().hex
    stock=record[1] if record else None; rid=record[0] if record else None; version=record[2] if record else None; nav=record[3] if record else None
    cur.execute("""insert into public.pdc_ai_intake_proposals(
      dedupe_key,source_hash,evidence_hash,source_uid,sender_address,authentication,source_received_at,
      subject,action_type,stock_number,backend_record_id,backend_record_version,observed_navision_revision,
      summary,observations,fingerprint,status,version,submitted_by)
      values(%s,%s,%s,%s,'qa@perthmotorbodies.com.au',%s,clock_timestamp(),%s,%s,%s,%s,%s,%s,%s,%s,%s,'pending',1,%s)
      returning proposal_id::text""",(
      'qa-'+marker,hashlib.sha256(('s'+marker).encode()).hexdigest(),hashlib.sha256(('e'+marker).encode()).hexdigest(),
      'qa-'+marker,json.dumps({'gmail_authentication_results':True,'spf':'pass'}),subject,action,stock,rid,version,nav,
      'Rollback-only migration 065 fixture',json.dumps({'qa_fixture':True}),fingerprint,viewer_id))
    return cur.fetchone()[0]


def main():
    load_local_env(); conn=get_conn()
    try:
      with conn.cursor() as cur:
        cur.execute('begin')
        cur.execute(migration_body((ROOT/'supabase/staging_only/065_pdc_ai_intake_admin_decisions.sql').read_text(encoding='utf-8')))
        cur.execute("select count(*),(select revision from public.navision_backend_revision where singleton),(select revision from public.pdc_ai_intake_revision where singleton),(select count(*) from public.pdc_ai_intake_decision_receipts) from public.navision_board_activations")
        baseline=cur.fetchone()
        cur.execute("select w.user_id::text,u.email from public.pdc_monitor_stage_activation_writers w join auth.users u on u.id=w.user_id where w.active order by w.granted_at desc limit 1")
        viewer=cur.fetchone()
        cur.execute("select r.auth_user_id::text,u.email from public.pdc_user_roles r join auth.users u on u.id=r.auth_user_id where r.role='administrator' and r.active and r.account_status='approved' order by r.approved_at desc nulls last limit 1")
        admin=cur.fetchone()
        if not viewer or not admin: raise RuntimeError('viewer/admin fixture identity unavailable')

        # Viewer can never decide.
        jwt(cur,*viewer)
        cur.execute("select proposal_id::text,version,fingerprint,action_type from public.pdc_ai_intake_proposals where status='pending' order by submitted_at limit 1")
        pending=cur.fetchone()
        denied=call(cur,'pdc-ai-intake-'+uuid.uuid4().hex,pending[0],pending[1],baseline[2],pending[3],'reject',pending[2],None,'Viewer cannot decide this observation')
        assert denied['code']=='unauthorized'
        for denied_role in ('operator','importer'):
          cur.execute("update public.pdc_user_roles set role=%s,account_status='approved',active=true where auth_user_id=%s::uuid",(denied_role,viewer[0]))
          jwt(cur,*viewer)
          role_denied=call(cur,'pdc-ai-intake-'+uuid.uuid4().hex,pending[0],pending[1],baseline[2],pending[3],'reject',pending[2],None,f'{denied_role} cannot decide this observation')
          assert role_denied['code']=='unauthorized'

        # Exact Administrator rejection, replay, and idempotency conflict.
        reject_id=insert_proposal(cur,viewer[0],None,'review_only','A065A065A065A065')
        cur.execute("update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision")
        reject_rev=cur.fetchone()[0]; jwt(cur,*admin)
        reject_key='pdc-ai-intake-'+uuid.uuid4().hex
        rejected=call(cur,reject_key,reject_id,1,reject_rev,'review_only','reject','A065A065A065A065',None,'Administrator dismissed rollback-only observation')
        assert rejected['ok'] and rejected['code']=='rejected'
        replay=call(cur,reject_key,reject_id,1,reject_rev,'review_only','reject','A065A065A065A065',None,'Administrator dismissed rollback-only observation')
        assert replay==rejected
        conflict=call(cur,reject_key,reject_id,1,reject_rev,'review_only','reject','A065A065A065A065',None,'Administrator changed the exact decision reason')
        assert conflict['code']=='idempotency_conflict'

        # Select one disposable eligible current Navision identity.
        cur.execute("""select r.id::text,public.normalize_vehicle_stock_number(r.normalized_data->>'batch'),r.version,
          (select revision from public.navision_backend_revision where singleton),encode(digest(r.normalized_data::text,'sha256'),'hex')
          from public.navision_backend_records r
          where r.source_system='microsoft_navision' and r.dealer_code in ('14450','37047') and r.is_current and r.record_status='current'
            and public.is_real_vehicle_stock_number(r.normalized_data->>'batch')
            and not exists(select 1 from public.navision_board_activations a where a.backend_record_id=r.id)
            and not exists(select 1 from public.vehicles v where v.stock_number_normalized=public.normalize_vehicle_stock_number(r.normalized_data->>'batch') and v.deleted_at is null)
            and not exists(select 1 from public.vehicle_aliases a where a.active and a.alias_type_normalized='stock_number' and a.normalized_alias_value=public.normalize_vehicle_stock_number(r.normalized_data->>'batch'))
          order by r.id limit 1""")
        record=cur.fetchone()
        if not record: raise RuntimeError('no eligible rollback-only Navision identity')
        cancelled_id=insert_proposal(cur,viewer[0],record[:4],'board_activate_only','C065C065C065C065','Cancelled new vehicle build')
        cur.execute("update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision")
        cancelled_rev=cur.fetchone()[0]
        cancelled=call(cur,'pdc-ai-intake-'+uuid.uuid4().hex,cancelled_id,1,cancelled_rev,'board_activate_only','apply','C065C065C065C065',record[3],'Administrator tests cancellation fail closed')
        assert cancelled['code']=='proposal_conflicted_or_cancelled'
        apply_id=insert_proposal(cur,viewer[0],record[:4],'board_activate_only','B065B065B065B065')
        cur.execute("update public.pdc_ai_intake_revision set revision=revision+1,updated_at=clock_timestamp() where singleton returning revision")
        apply_rev=cur.fetchone()[0]
        stale=call(cur,'pdc-ai-intake-'+uuid.uuid4().hex,apply_id,1,apply_rev-1,'board_activate_only','apply','B065B065B065B065',record[3],'Administrator approves exact rollback-only activation')
        assert stale['code']=='stale_inbox_revision'
        applied=call(cur,'pdc-ai-intake-'+uuid.uuid4().hex,apply_id,1,apply_rev,'board_activate_only','apply','B065B065B065B065',record[3],'Administrator approves exact rollback-only activation')
        assert applied['ok'] and applied['code']=='applied'
        cur.execute("select count(*),max(activation_source) from public.navision_board_activations where backend_record_id=%s",(record[0],))
        assert cur.fetchone()==(1,'approved_email_build')
        cur.execute("select encode(digest(normalized_data::text,'sha256'),'hex') from public.navision_backend_records where id=%s",(record[0],))
        assert cur.fetchone()[0]==record[4]
        cur.execute("select count(*) from public.pdc_ai_intake_decision_receipts where proposal_id in (%s,%s)",(reject_id,apply_id))
        assert cur.fetchone()[0]==2
        result={'viewer_denied':True,'operator_denied':True,'importer_denied':True,'admin_reject':True,'idempotent_replay':True,'idempotency_conflict':True,'cancelled_denied':True,'stale_revision_denied':True,'admin_apply':True,'location_and_record_preserved':True,'transaction':'rolled_back'}
        conn.rollback()
    except Exception:
      conn.rollback(); raise
    finally: conn.close()
    print(json.dumps(result,sort_keys=True))


if __name__=='__main__': main()
