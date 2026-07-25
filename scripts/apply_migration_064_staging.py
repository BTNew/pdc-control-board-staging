#!/usr/bin/env python3
"""Apply or transactionally rehearse staging-only containment migration 064."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / '_staging_test_tools')]
from _staging_test_tools.staging_conn import get_conn  # noqa:E402
from _staging_test_tools.staging_env import (  # noqa:E402
    EXPECTED_STAGING_REF, assert_staging_target, load_local_env, required,
)

SQL_PATH = ROOT / 'supabase/staging_only/064_disable_pdc_ai_intake_decisions.sql'
APPROVAL = 'CONTAIN PDC AI INTAKE DECISIONS ON STAGING'


def body(text: str) -> str:
    begin = re.search(r'(?im)^\s*begin;\s*$', text)
    commits = list(re.finditer(r'(?im)^\s*commit;\s*$', text))
    if not begin or not commits:
        raise RuntimeError('migration must be transaction wrapped')
    return text[begin.end():commits[-1].start()]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--confirm-project', required=True)
    parser.add_argument('--approve', required=True)
    parser.add_argument('--rehearse', action='store_true')
    args = parser.parse_args()
    if args.confirm_project != EXPECTED_STAGING_REF or args.approve != APPROVAL:
        raise SystemExit('exact staging project/containment phrase mismatch')
    load_local_env()
    db_url = required('PDC_STAGING_DATABASE_URL')
    project_url = required('PDC_STAGING_SUPABASE_URL')
    assert_staging_target(project_url=project_url, database_url=db_url)
    if required('PDC_STAGING_WRITES_ENABLED').lower() != 'true':
        raise RuntimeError('PDC_STAGING_WRITES_ENABLED must be true')
    if required('PDC_PRODUCTION_WRITES_ENABLED').lower() != 'false':
        raise RuntimeError('production write tripwire must be false')
    sql = SQL_PATH.read_text(encoding='utf-8')
    migration = body(sql)
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('begin')
            cur.execute("select version from supabase_migrations.schema_migrations where version in ('063','064') order by version")
            versions = [row[0] for row in cur.fetchall()]
            if versions not in (['063'], ['063','064']):
                raise RuntimeError(f'expected migration 063 with optional 064, got {versions}')
            cur.execute("select project_ref from public.pdc_staging_environment_sentinel where singleton for share")
            sentinel = cur.fetchone()
            if not sentinel or sentinel[0] != EXPECTED_STAGING_REF:
                raise RuntimeError('pre-existing staging sentinel mismatch')
            cur.execute("select count(*) from public.pdc_ai_intake_proposals where status<>'pending' or decided_at is not null")
            if cur.fetchone()[0] != 0:
                raise RuntimeError('AI Intake decisions require inventory before containment')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            revision_before = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            activations_before = cur.fetchone()[0]
            if versions == ['063']:
                cur.execute(migration)
                cur.execute(
                    'insert into supabase_migrations.schema_migrations(version,name,statements) values(%s,%s,%s)',
                    ('064','disable_pdc_ai_intake_decisions',[sql]),
                )
            else:
                cur.execute("select name,statements from supabase_migrations.schema_migrations where version='064'")
                installed = cur.fetchone()
                if not installed or installed[0] != 'disable_pdc_ai_intake_decisions' or installed[1] != [sql]:
                    raise RuntimeError('installed migration 064 source differs')
            cur.execute("select to_regprocedure('public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text)'), to_regprocedure('public.get_pdc_ai_intake_snapshot(text,integer)')")
            decision_rpc, snapshot_rpc = cur.fetchone()
            if decision_rpc is not None or snapshot_rpc is None:
                raise RuntimeError('containment RPC verification failed')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            revision_after = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            activations_after = cur.fetchone()[0]
            if (revision_before,activations_before) != (revision_after,activations_after):
                raise RuntimeError('containment changed board state')
            cur.execute("select count(*) from public.pdc_ai_intake_proposals where status='pending'")
            pending = cur.fetchone()[0]
            result = {'status':'rehearsed' if args.rehearse else 'applied','migration':'064','pending_observations':pending,'decision_rpc':None,'navision_revision':revision_after,'board_activations':activations_after,'production_contacted':False}
            if args.rehearse:
                conn.rollback()
            else:
                conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    print(json.dumps(result,sort_keys=True))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
