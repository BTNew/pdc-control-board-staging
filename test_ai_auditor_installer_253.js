'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const source = fs.readFileSync('scripts/apply_migration_253_staging.py','utf8').replace(/\r\n/g,'\n');
for (const required of [
  'ALLOWED_IGNORED_PATHS = {"_staging_test_tools/.env"}',
  'def ignored_residue() -> list[str]:',
  '"ls-files", "--others", "--ignored", "--exclude-standard"',
  'ignored_dirty = ignored_residue()',
  'PRIVATE_FUNCTIONS = (',
  'public.pdc_auditor_valid_new_value_253(jsonb,boolean,boolean,boolean)',
  'row[0] != owner',
  'or row[1]',
  'or row[2] != "i"',
  'search_path=pg_catalog',
  'private-function owner/invoker/immutable/search-path mismatch',
  '"authenticated": False',
  '"service_role": False',
  'private-function ACL mismatch',
  '"private_functions": len(PRIVATE_FUNCTIONS)',
  'rollback-only rehearsal leaked migration or operational state',
  '"production_changed": False',
  'load_exact_repo_helper(',
  'repository helper bytes do not match exact reviewed commit',
  'exec(compile(expected, str(target), "exec"), module.__dict__)',
  'exact reviewed commit/pristine worktree required',
  '"--untracked-files=all"',
  'if not sys.flags.isolated:',
  'isolated Python is required',
  'staging_tls_kwargs = runtime.staging_tls_kwargs',
  'tls_kwargs = staging_tls_kwargs()',
  'psycopg2 import failed after exact-SHA/endpoint/TLS preflight',
  'psycopg2.connect(dsn, **tls_kwargs)',
]) assert.ok(source.includes(required),`installer contract missing: ${required}`);
const runtimeSource = fs.readFileSync('scripts/pdc_staging_runtime.py','utf8').replace(/\r\n/g,'\n');
for (const required of [
  'PDC_STAGING_SSLROOTCERT',
  'PDC_STAGING_SSLROOTCERT_SHA256',
  'sslmode": "verify-full"',
  'sslrootcert": trusted_sslrootcert()',
  'Staging TLS CA bundle SHA-256 mismatch',
  'Staging TLS CA bundle is not a parseable certificate bundle',
]) assert.ok(runtimeSource.includes(required),`runtime TLS contract missing: ${required}`);
assert.ok(source.includes("version='253'"),'rollback readback must check the exact migration ledger');
assert.ok(source.includes("to_regclass('public.pdc_auditor_gateway_keys_253') is not null"),'rollback readback must check private object residue');

const disableSource = fs.readFileSync('supabase/staging_only/254_disable_ai_auditor_typed_operation_control.sql','utf8').replace(/\r\n/g,'\n');
for (const required of [
  'do $reharden_private_253$',
  "drop policy %I on public.%I",
  "alter table public.%I enable row level security",
  "alter table public.%I force row level security",
  "revoke all on table public.%I from public,anon,authenticated,service_role",
  'revoke all on public.pdc_auditor_normalized_operation_lines_253 from public,anon,authenticated,service_role',
  'PDC_254_PRIVATE_TABLE_RLS_OR_POLICY_REMAINS',
  'PDC_254_PRIVATE_TABLE_AUTHORITY_REMAINS',
  'PDC_254_PRIVATE_VIEW_AUTHORITY_REMAINS',
  'create temp table pdc_auditor_retained_counts_254',
  'PDC_254_RETAINED_ROW_COUNT_CHANGED',
]) assert.ok(disableSource.includes(required),`migration 254 containment contract missing: ${required}`);
assert.strictEqual((disableSource.match(/'pdc_auditor_gateway_keys_253'/g) || []).length >= 3, true, 'migration 254 must guard, reharden and postcheck all private tables');

const poison = fs.mkdtempSync(path.join(os.tmpdir(),'pdc-installer-pythonpath-poison-'));
try {
  fs.writeFileSync(path.join(poison,'psycopg2.py'),"raise SystemExit('POISONED_IMPORT_EXECUTED')\n",'utf8');
  const expected = spawnSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).stdout.trim();
  const env = { ...process.env, PYTHONPATH: poison };
  const normal = spawnSync('python3',['scripts/apply_migration_253_staging.py','--expected-commit',expected],{encoding:'utf8',env});
  const normalOutput = `${normal.stdout || ''}${normal.stderr || ''}`;
  assert.notStrictEqual(normal.status,0,'non-isolated installer invocation must fail');
  assert.ok(normalOutput.includes('isolated Python is required'),normalOutput);
  assert.ok(!normalOutput.includes('POISONED_IMPORT_EXECUTED'),normalOutput);

  const isolated = spawnSync('python3',['-I','scripts/apply_migration_253_staging.py','--expected-commit',expected],{encoding:'utf8',env});
  const isolatedOutput = `${isolated.stdout || ''}${isolated.stderr || ''}`;
  assert.notStrictEqual(isolated.status,0,'credential-free isolated probe must stop before installation');
  assert.ok(!isolatedOutput.includes('POISONED_IMPORT_EXECUTED'),isolatedOutput);
  assert.ok(!isolatedOutput.includes('isolated Python is required'),isolatedOutput);
} finally {
  fs.rmSync(poison,{recursive:true,force:true});
}

if (fs.existsSync(path.join(__dirname,'.git'))) {
  const pycPoison = String.raw`
import importlib.util
import os
import pathlib
import shutil
import sys

root = pathlib.Path('.').resolve()
scripts = root / 'scripts'
source = scripts / 'pdc_staging_runtime.py'
cache_dir = scripts / '__pycache__'
cache_dir.mkdir(exist_ok=True)
cache_path = cache_dir / f'pdc_staging_runtime.{sys.implementation.cache_tag}.pyc'
marker = root / 'ignored-pyc-marker.txt'
connect_marker = root / 'ignored-pyc-connect.txt'
marker.unlink(missing_ok=True)
connect_marker.unlink(missing_ok=True)
poison_code = """
from pathlib import Path
import sys, types
ROOT = Path(__file__).resolve().parents[1]
ENV_PATH = ROOT / '_staging_test_tools' / '.env'
SSLROOTCERT_ENV = 'PDC_STAGING_SSLROOTCERT'
SSLROOTCERT_SHA256_ENV = 'PDC_STAGING_SSLROOTCERT_SHA256'
EXPECTED_STAGING_REF = 'cdsmnqxtyyoeoznmbidd'
Path('ignored-pyc-marker.txt').write_text('IGNORED_PYC_EXECUTED', encoding='utf-8')
def _connect(*args, **kwargs):
    Path('ignored-pyc-connect.txt').write_text('PDC_CONNECT_EXECUTED', encoding='utf-8')
    raise RuntimeError('PDC_CONNECT_STOP')
sys.modules['psycopg2'] = types.SimpleNamespace(connect=_connect)
def load_local_env():
    return None
def assert_staging_target(*args, **kwargs):
    return None
def staging_tls_kwargs():
    return {}
"""
code = compile(poison_code, str(source), 'exec')
source_stat = source.stat()
payload = importlib._bootstrap_external._code_to_timestamp_pyc(code, int(source_stat.st_mtime), source_stat.st_size)
cache_path.write_bytes(payload)
try:
    env = dict(os.environ)
    env['PDC_STAGING_DATABASE_URL'] = 'postgresql://postgres:bad@attacker.example:5432/postgres'
    env['PDC_STAGING_SSLROOTCERT'] = str(root / 'tests' / 'fixtures' / 'pdc_test_root_ca.pem')
    env['PDC_STAGING_SSLROOTCERT_SHA256'] = '0' * 64
    expected = __import__('subprocess').check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    proc = __import__('subprocess').run([
        'python3', '-I', 'scripts/apply_migration_253_staging.py', '--expected-commit', expected
    ], cwd=root, env=env, text=True, capture_output=True)
    combined = (proc.stdout or '') + (proc.stderr or '')
    assert proc.returncode != 0, combined
    assert 'exact reviewed commit/pristine worktree required' in combined, combined
    assert not marker.exists(), 'ignored helper pyc executed before preflight'
    assert not connect_marker.exists(), 'ignored helper pyc reached connector call'
finally:
    cache_path.unlink(missing_ok=True)
    marker.unlink(missing_ok=True)
    connect_marker.unlink(missing_ok=True)
    shutil.rmtree(cache_dir, ignore_errors=True)
`;
  const pycProbe = spawnSync('python3', ['-I', '-c', pycPoison], { encoding: 'utf8' });
  assert.strictEqual(pycProbe.status, 0, pycProbe.stderr || pycProbe.stdout);
}
console.log('Migration 253 installer exact-SHA/private-function/rollback contract passed');