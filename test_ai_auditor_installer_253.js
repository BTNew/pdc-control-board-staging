'use strict';
const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const source = fs.readFileSync('scripts/apply_migration_253_staging.py','utf8').replace(/\r\n/g,'\n');
for (const required of [
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
  'exact reviewed commit/clean tracked worktree required',
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
]) assert.ok(runtimeSource.includes(required),`runtime TLS contract missing: ${required}`);
assert.ok(source.includes("version='253'"),'rollback readback must check the exact migration ledger');
assert.ok(source.includes("to_regclass('public.pdc_auditor_gateway_keys_253') is not null"),'rollback readback must check private object residue');

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
console.log('Migration 253 installer exact-SHA/private-function/rollback contract passed');