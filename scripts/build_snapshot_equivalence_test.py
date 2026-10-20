#!/usr/bin/env python3
"""Build one rolled-back snapshot equivalence test (r410, stage 0 of SNAPSHOT_PLAN.md).

Output: a single SQL script for the staging SQL editor / execute_sql. It waits for the release-test window
(scripts/rolled_back_test_window.sql), sets the login's JWT claims from auth.users by id (no email in files),
loads scripts/snapshot_equivalence_harness.sql, runs the steps in one transaction, prints overall, per-department
and per-vehicle md5s plus every comparison, and ROLLS BACK. Run one test per minute window, never two at once
(the second would wait on the first's function locks and stop at lock_timeout 2 s).

Steps: snap:<label>:location|board, apply (candidate migration), undo (its .down.sql), fixture
(scripts/snapshot_edge_fixture.sql). Compare pairs with --compare A:B.

Example (old/new/old for the location snapshot):
  scripts/build_snapshot_equivalence_test.py --login <auth user id> \
    --candidate supabase/migrations/<id>.sql --undo supabase/rollbacks/<id>.down.sql \
    --steps snap:O1:location apply snap:N1:location undo snap:O2:location --compare O1:N1 O1:O2 > test.sql
"""
import argparse, re, sys

def rd(p):
    with open(p, newline='') as f:
        return f.read()

STATE = """INSERT INTO t_res(k,v) VALUES ('{k}', jsonb_build_object('role', public.current_pdc_user_role()::text,
  'pins_md5', (SELECT md5(string_agg(signature||prosrc_md5||release, ',' ORDER BY signature)) FROM pdc_ops.expected_function_md5),
  'checks_md5', (SELECT md5(string_agg(check_name||md5(check_sql)||enabled::text, ',' ORDER BY check_name)) FROM pdc_ops.regression_checks),
  'snapshot_fns_md5', (SELECT md5(string_agg(p.oid::regprocedure::text||md5(p.prosrc)||coalesce(p.proacl::text,''), ',' ORDER BY p.oid::regprocedure::text))
                       FROM pg_proc p WHERE p.proname LIKE 'get_pdc_email_vehicle_%snapshot%'),
  'clock_tick', (SELECT md5(prosrc) FROM pg_proc WHERE oid='public.workshop_clock_tick(boolean,timestamptz)'::regprocedure)));
"""

def main():
    a = argparse.ArgumentParser()
    a.add_argument('--login', required=True, help='auth.users id of the login (administrator or operator)')
    a.add_argument('--tag', default='SNAPEQ')
    a.add_argument('--candidate'); a.add_argument('--undo')
    a.add_argument('--fixture', default='scripts/snapshot_edge_fixture.sql')
    a.add_argument('--steps', nargs='+', required=True)
    a.add_argument('--compare', nargs='*', default=[])
    o = a.parse_args()
    if not re.fullmatch(r'[0-9a-f-]{36}', o.login):
        sys.exit('--login must be an auth.users id')
    out = [rd('scripts/rolled_back_test_window.sql').replace('@TAG@', o.tag), 'SELECT pg_temp.deadline();',
           f"SELECT set_config('request.jwt.claims', (SELECT jsonb_build_object('sub',u.id,'role','authenticated','email',u.email)::text FROM auth.users u WHERE u.id='{o.login}'), true);",
           f"SELECT set_config('request.jwt.claim.sub','{o.login}',true);",
           rd('scripts/snapshot_equivalence_harness.sql'), STATE.format(k='state start')]
    for s in o.steps:
        if s.startswith('snap:'):
            _, label, which = s.split(':')
            assert which in ('location', 'board') and re.fullmatch(r'\w+', label), s
            out.append(f"SELECT pg_temp.snap('{label}','{which}');")
        elif s in ('apply', 'undo'):
            path = o.candidate if s == 'apply' else o.undo
            if not path: sys.exit(f'{s} needs --candidate / --undo')
            out += ['SELECT pg_temp.deadline();', f'-- ===== {path} =====', rd(path), STATE.format(k=f'state after {s}')]
        elif s == 'fixture':
            out += ['SELECT pg_temp.deadline();', rd(o.fixture)]
        else:
            sys.exit(f'unknown step {s}')
    cmp = ','.join("pg_temp.compare('{}','{}')".format(*c.split(':')) for c in o.compare)
    out += ['SELECT pg_temp.deadline();', "INSERT INTO t_res(k,v) VALUES ('T test window', pg_temp.window_report());",
            "SELECT jsonb_build_object('results',(SELECT jsonb_agg(jsonb_build_object('k',k)||v ORDER BY step) FROM t_res),"
            f"'compare',jsonb_build_array({cmp})) AS r;", 'ROLLBACK;']
    sys.stdout.write('\n'.join(out))

if __name__ == '__main__':
    main()
