#!/usr/bin/env python3
"""Apply or transactionally rehearse staging-only migration 065."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / '_staging_test_tools')]
from _staging_test_tools.staging_conn import get_conn  # noqa:E402
from _staging_test_tools.staging_env import EXPECTED_STAGING_REF, assert_staging_target, load_local_env, required  # noqa:E402

SQL_PATH = ROOT / 'supabase/staging_only/065_pdc_ai_intake_admin_decisions.sql'
APPROVAL = 'ENABLE EXACT AI INTAKE ADMIN DECISIONS ON STAGING'


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
        raise SystemExit('exact staging project/approval phrase mismatch')
    load_local_env()
    db_url, project_url = required('PDC_STAGING_DATABASE_URL'), required('PDC_STAGING_SUPABASE_URL')
    assert_staging_target(project_url=project_url, database_url=db_url)
    if required('PDC_STAGING_WRITES_ENABLED').lower() != 'true' or required('PDC_PRODUCTION_WRITES_ENABLED').lower() != 'false':
        raise RuntimeError('staging/production write tripwire mismatch')
    sql, migration = SQL_PATH.read_text(encoding='utf-8'), body(SQL_PATH.read_text(encoding='utf-8'))
    conn = get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute('begin')
            cur.execute("select version from supabase_migrations.schema_migrations where version in ('063','064','065') order by version")
            versions = [row[0] for row in cur.fetchall()]
            if versions not in (['063','064'], ['063','064','065']):
                raise RuntimeError(f'expected 063/064 with optional 065, got {versions}')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            nav_before = cur.fetchone()[0]
            cur.execute('select revision from public.pdc_ai_intake_revision where singleton')
            inbox_before = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            activations_before = cur.fetchone()[0]
            if versions == ['063','064']:
                cur.execute(migration)
                cur.execute('insert into supabase_migrations.schema_migrations(version,name,statements) values(%s,%s,%s)',('065','pdc_ai_intake_admin_decisions',[sql]))
            else:
                cur.execute("select name,statements from supabase_migrations.schema_migrations where version='065'")
                installed = cur.fetchone()
                if not installed or installed[0] != 'pdc_ai_intake_admin_decisions' or installed[1] != [sql]:
                    raise RuntimeError('installed migration 065 source differs')
            cur.execute("select to_regprocedure('public.decide_pdc_ai_intake_proposal(text,uuid,bigint,bigint,text,text,text,bigint,text)')")
            if cur.fetchone()[0] is None:
                raise RuntimeError('exact migration 065 decision RPC missing')
            cur.execute("select has_function_privilege('anon','public.decide_pdc_ai_intake_proposal(text,uuid,bigint,bigint,text,text,text,bigint,text)','execute'),has_function_privilege('authenticated','public.decide_pdc_ai_intake_proposal(text,uuid,bigint,bigint,text,text,text,bigint,text)','execute')")
            if cur.fetchone() != (False, True):
                raise RuntimeError('decision RPC grant mismatch')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            nav_after = cur.fetchone()[0]
            cur.execute('select revision from public.pdc_ai_intake_revision where singleton')
            inbox_after = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            activations_after = cur.fetchone()[0]
            if (nav_before,inbox_before,activations_before)!=(nav_after,inbox_after,activations_after):
                raise RuntimeError('migration changed operational state')
            result={'status':'rehearsed' if args.rehearse else 'applied','migration':'065','navision_revision':nav_after,'inbox_revision':inbox_after,'board_activations':activations_after,'decision_rpc':'exact_admin_only','production_contacted':False}
            conn.rollback() if args.rehearse else conn.commit()
    except Exception:
        conn.rollback(); raise
    finally:
        conn.close()
    print(json.dumps(result,sort_keys=True)); return 0


if __name__ == '__main__':
    raise SystemExit(main())
