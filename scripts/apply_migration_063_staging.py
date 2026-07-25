#!/usr/bin/env python3
"""Apply or transactionally rehearse staging-only migration 063."""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT), str(ROOT / '_staging_test_tools')]
from _staging_test_tools.staging_conn import get_conn  # noqa:E402
from _staging_test_tools.staging_env import (  # noqa:E402
    EXPECTED_STAGING_REF, assert_staging_target, load_local_env, required,
)

SQL_PATH = ROOT / 'supabase/staging_only/063_pdc_ai_intake_inbox_history.sql'
APPROVAL = 'APPLY PDC AI INTAKE HISTORY TO STAGING'
BEFORE = [f'{n:03d}' for n in range(53, 63)]
AFTER = BEFORE + ['063']


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
    db_url = required('PDC_STAGING_DATABASE_URL')
    project_url = required('PDC_STAGING_SUPABASE_URL')
    assert_staging_target(project_url=project_url, database_url=db_url)
    if required('PDC_STAGING_WRITES_ENABLED').lower() != 'true':
        raise RuntimeError('PDC_STAGING_WRITES_ENABLED must be true')
    if required('PDC_PRODUCTION_WRITES_ENABLED').lower() != 'false':
        raise RuntimeError('production write tripwire must be false')
    sql = SQL_PATH.read_text(encoding='utf-8')
    migration = body(sql)
    for fragment in (
        'pdc_staging_environment_sentinel', 'pdc_email_source_claims',
        'submit_pdc_ai_intake_observation', 'get_pdc_ai_intake_snapshot',
        'decide_pdc_ai_intake_proposal', 'activation_identity_conflict',
        'pdc_claim_legacy_stage_activation_source',
    ):
        if fragment not in sql:
            raise RuntimeError(f'migration safety fragment missing: {fragment}')
    conn = get_conn()
    result = {}
    try:
        with conn.cursor() as cur:
            cur.execute('begin')
            cur.execute("select version from supabase_migrations.schema_migrations where version::int between 53 and 63 order by version::int")
            versions = [row[0] for row in cur.fetchall()]
            if versions not in (BEFORE, AFTER):
                raise RuntimeError(f'expected exact ledger 053-062 or 053-063, got {versions}')
            cur.execute('select project_ref from public.pdc_staging_environment_sentinel where singleton for share')
            sentinel = cur.fetchone()
            if not sentinel or sentinel[0] != EXPECTED_STAGING_REF:
                raise RuntimeError('pre-existing staging sentinel mismatch')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            before_revision = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            before_activations = cur.fetchone()[0]
            if versions == BEFORE:
                cur.execute(migration)
                cur.execute(
                    'insert into supabase_migrations.schema_migrations(version,name,statements) values(%s,%s,%s)',
                    ('063', 'pdc_ai_intake_inbox_history', [sql]),
                )
            else:
                cur.execute("select name,statements from supabase_migrations.schema_migrations where version='063'")
                installed = cur.fetchone()
                if not installed or installed[0] != 'pdc_ai_intake_inbox_history' or installed[1] != [sql]:
                    raise RuntimeError('installed migration 063 source differs')
            cur.execute("select to_regprocedure('public.submit_pdc_ai_intake_observation(text,text,text,text,jsonb,timestamp with time zone,text,text,text,text,jsonb)'), to_regprocedure('public.get_pdc_ai_intake_snapshot(text,integer)'), to_regprocedure('public.decide_pdc_ai_intake_proposal(uuid,bigint,text,text,text)')")
            procedures = cur.fetchone()
            if any(value is None for value in procedures):
                raise RuntimeError('AI Intake RPC verification failed')
            cur.execute('select revision from public.navision_backend_revision where singleton')
            after_revision = cur.fetchone()[0]
            cur.execute('select count(*) from public.navision_board_activations')
            after_activations = cur.fetchone()[0]
            if (before_revision, before_activations) != (after_revision, after_activations):
                raise RuntimeError('migration changed Navision revision or board activations')
            cur.execute('select count(*) from public.pdc_ai_intake_proposals')
            proposal_count = cur.fetchone()[0]
            cur.execute('select count(*) from public.pdc_email_source_claims')
            claim_count = cur.fetchone()[0]
            result = {
                'status': 'rehearsed' if args.rehearse else 'applied',
                'project_ref': EXPECTED_STAGING_REF,
                'migration': '063',
                'proposals': proposal_count,
                'source_claims': claim_count,
                'navision_revision': after_revision,
                'board_activations': after_activations,
                'production_contacted': False,
            }
            if args.rehearse:
                conn.rollback()
            else:
                conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
