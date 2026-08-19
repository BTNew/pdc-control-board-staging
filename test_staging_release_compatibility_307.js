'use strict';
const assert = require('assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/staging_only/307_staging_hardening_phase1_release_head_contract.sql', 'utf8');
assert.ok(sql.includes("version='307'"), 'release-head repair must have its own immutable migration');
assert.ok(sql.includes("version ~ '^[0-9]{1,3}$'"), 'compatibility head must exclude timestamp-form maintenance entries');
assert.ok(sql.includes("'database_release_too_old'") && sql.includes('v_head,0)<307'), 'compatibility must fail closed below the installed numbered head');
console.log('Staging release compatibility head contract passed.');
