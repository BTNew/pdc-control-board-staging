'use strict';
const assert = require('assert');
const fs = require('fs');

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
]) assert.ok(source.includes(required),`installer contract missing: ${required}`);
assert.ok(source.includes("version='253'"),'rollback readback must check the exact migration ledger');
assert.ok(source.includes("to_regclass('public.pdc_auditor_gateway_keys_253') is not null"),'rollback readback must check private object residue');
console.log('Migration 253 installer exact-SHA/private-function/rollback contract passed');