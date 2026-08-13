'use strict';
const assert = require('assert');
const { spawnSync } = require('child_process');

const probe = String.raw`
import importlib.util
import json
import sys
import types

sys.modules['psycopg2'] = types.SimpleNamespace(connect=None)
spec = importlib.util.spec_from_file_location('pdc_staging_runtime_guard_test', 'scripts/pdc_staging_runtime.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ref = module.EXPECTED_STAGING_REF
accepted = [
    ('project', f'https://{ref}.supabase.co'),
    ('project', f'https://{ref}.supabase.co:443/rest/v1/'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?sslmode=require'),
    ('database', f'postgres://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres'),
]
rejected = [
    ('project', f'https://{ref}@attacker.example'),
    ('project', f'https://attacker.example/?project={ref}'),
    ('project', f'https://{ref}.attacker.example'),
    ('project', f'http://{ref}.supabase.co'),
    ('project', f'https://attacker.example/{ref}'),
    ('project', f'https://{ref}.supabase.co:444'),
    ('project', f'https://user@{ref}.supabase.co'),
    ('project', f'https://{ref}.supabase.co:notaport'),
    ('database', f'postgresql://{ref}:placeholder@attacker.example:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@attacker.example:5432/postgres?project={ref}'),
    ('database', f'postgresql://postgres:placeholder@{ref}.attacker.example:5432/postgres'),
    ('database', f'http://db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@attacker.example:5432/{ref}'),
    ('database', f'postgresql://postgres.wrongref:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:443/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com.attacker.example:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?host=attacker.example'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?hostaddr=203.0.113.10'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?service=attacker'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/other_database'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:notaport/postgres'),
]
for kind, value in accepted:
    module.assert_staging_target(**{f'{kind}_url': value})
for kind, value in rejected:
    try:
        module.assert_staging_target(**{f'{kind}_url': value})
    except Exception:
        continue
    raise AssertionError(f'guard accepted spoofed {kind} endpoint: {value}')
print(json.dumps({'accepted': len(accepted), 'rejected': len(rejected)}))
`;
const result = spawnSync('python3', ['-I', '-c', probe], { encoding: 'utf8' });
assert.strictEqual(result.status, 0, result.stderr || result.stdout);
const report = JSON.parse(result.stdout.trim());
assert.deepStrictEqual(report, { accepted: 5, rejected: 21 });
console.log('PDC staging parsed-host endpoint guard passed');
