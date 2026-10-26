/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261026150000_r541_parts_complete_wording.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026150000_r541_parts_complete_wording.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk541$'), up.lastIndexOf('$chk541$'));

test('r541 accepts All parts complete and refuses All parts removed', () => {
  assert.match(up, /PREVIEW/);
  assert.match(up, /SQL is not applied/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /true, 319, 'r541'/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /00f93577e68479a0063d3955bb3c4be7/);
  assert.match(up, /8ddb1477beeb94c7879c4021cccf1d40/);
  assert.match(up, /parts\.malaga@pmgwa\.com\.au/);
  assert.match(up, /new vehicle order for/);
  assert.match(up, /All parts removed is not/);
  assert.match(up, /13102818/);
  assert.match(up, /1IRU519/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.record_pdc_person_parts_complete_20260913\(text,text,timestamptz,text,text,text,jsonb\)'\)/);
  assert.doesNotMatch(check, /::(?:pg_catalog\.)?regprocedure/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.doesNotMatch(check, /expected_function_md5/i);
  assert.match(up, /karratha135_pdc\.pdc_parts_completion_email_confirmations/);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /8ddb1477beeb94c7879c4021cccf1d40/);
  assert.match(down, /a rego-stock confirmation is stored/);
  assert.equal(scanSql(down).length, 0);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /parts_complete_wording_541/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F155 \|/);
});
