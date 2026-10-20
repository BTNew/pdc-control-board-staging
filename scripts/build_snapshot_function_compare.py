#!/usr/bin/env python3
"""Compare candidate snapshot layer functions with the live ones in one statement (r411, stage 2 of SNAPSHOT_PLAN.md).

Reads every `CREATE OR REPLACE FUNCTION public.<name>()` (no arguments) from a candidate migration, creates each one as
pg_temp.cand_<name>() in a rolled-back transaction, and returns md5(live()::text) and md5(candidate()::text) for every
function from ONE statement, so both read the same snapshot. The candidates call the live layers below them, so each
segment is proven on its own. Nothing is replaced; the script ends with ROLLBACK.

Run it inside the release-test window (scripts/rolled_back_test_window.sql is prepended), one test per minute, never
two at once. The login's JWT claims are set from auth.users by id (no email in files). --fixture adds
scripts/snapshot_edge_fixture.sql (with the stage 0 harness tables) before the comparison.

  scripts/build_snapshot_function_compare.py --login <auth user id> \
    --candidate supabase/migrations/<id>.sql [--fixture] > compare.sql
"""
import argparse, re, sys

def rd(p):
    with open(p, newline='') as f:
        return f.read()

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--login', required=True)
    a.add_argument('--candidate', required=True)
    a.add_argument('--tag', default='SNAPFN')
    a.add_argument('--fixture', action='store_true')
    o = a.parse_args()
    if not re.fullmatch(r'[0-9a-f-]{36}', o.login):
        sys.exit('--login must be an auth.users id')
    src = rd(o.candidate)
    defs = []
    for m in re.finditer(r'CREATE OR REPLACE FUNCTION public\.(\w+)\(\)\n(.*?\n)AS \$function\$(.*?)\$function\$', src, re.S):
        name, head, body = m.groups()
        defs.append((name, f'CREATE FUNCTION pg_temp.cand_{name}()\n{head}AS $function${body}$function$;'))
    if not defs:
        sys.exit('no CREATE OR REPLACE FUNCTION public.<name>() in the candidate')
    out = [rd('scripts/rolled_back_test_window.sql').replace('@TAG@', o.tag), 'SELECT pg_temp.deadline();',
           f"SELECT set_config('request.jwt.claims', (SELECT jsonb_build_object('sub',u.id,'role','authenticated','email',u.email)::text FROM auth.users u WHERE u.id='{o.login}'), true);",
           f"SELECT set_config('request.jwt.claim.sub','{o.login}',true);"]
    out += [d for _, d in defs]
    if o.fixture:
        out += [rd('scripts/snapshot_equivalence_harness.sql'), 'SELECT pg_temp.deadline();', rd('scripts/snapshot_edge_fixture.sql')]
    cols = ',\n '.join(f"'{n}', jsonb_build_object('live', md5(public.{n}()::text), 'candidate', md5(pg_temp.cand_{n}()::text))" for n, _ in defs)
    out += ['SELECT pg_temp.deadline();',
            f'CREATE TEMP TABLE snapfn_cmp ON COMMIT DROP AS SELECT jsonb_build_object(\n {cols}) AS c;',
            'SELECT pg_temp.deadline();',
            "SELECT jsonb_build_object('functions', c, 'identical', (SELECT bool_and(v->>'live' = v->>'candidate') FROM jsonb_each(c) e(k, v)),"
            " 'window', pg_temp.window_report()) AS r FROM snapfn_cmp;",
            'ROLLBACK;']
    sys.stdout.write('\n'.join(out))

if __name__ == '__main__':
    main()
