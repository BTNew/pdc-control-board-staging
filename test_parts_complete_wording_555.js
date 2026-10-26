/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261027060000_r555_parts_complete_wording.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027060000_r555_parts_complete_wording.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk541$'), up.lastIndexOf('$chk541$'));

test('r555 accepts All parts complete and refuses All parts removed', () => {
  assert.match(up, /Approved go-live retry/);
  assert.doesNotMatch(up, /PREVIEW/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /true, 330, 'r555'/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /c5314b7bed8a1401b6698319125c2d74/);
  assert.match(up, /8ddb1477beeb94c7879c4021cccf1d40/);
  assert.match(up, /parts\.malaga@pmgwa\.com\.au/);
  assert.match(up, /new vehicle order for/);
  assert.match(up, /ai_classification/);
  assert.match(up, /13102818/);
  assert.match(up, /1IRU519/);
  for (const [phrase, result] of [
    ['parts complete', 'complete'],
    ['all parts complete', 'complete'],
    ['all parts are here', 'complete'],
    ['parts are here', 'complete'],
    ['parts arrived', 'complete'],
    ['all parts in', 'complete'],
    ['not complete', 'not_complete'],
    ['waiting on', 'not_complete'],
    ['except', 'not_complete'],
    ['is it complete?', 'not_complete'],
    ['all parts removed', 'not_complete'],
  ]) {
    const quoted = phrase.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(check, new RegExp(`pdc_parts_reply_wording_541\\('${quoted}'\\) = '${result}'`));
  }
  assert.match(check, /ai_classification":"ambiguous"/);
  assert.match(check, /ai_classification":"not_complete"/);
  assert.match(check, /ai_confidence":"high"/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.record_pdc_person_parts_complete_20260913\(text,text,timestamptz,text,text,text,jsonb\)'\)/);
  assert.match(check, /LIKE '%internal_ok AND domain=''pmgwa.com.au'' AND plain%'/);
  assert.match(check, /pdc_parts_mailbox_recipient_541/);
  assert.match(check, /pdc_parts_vehicle_match_541/);
  assert.match(check, /cc_addresses/);
  assert.match(check, /J138000880/);
  assert.match(check, /d9192a72-0987-496b-b395-b9c836dff8e8/);
  assert.match(check, /b85d26fb-8f52-40fe-b06b-bb1bf87b0659/);
  assert.match(check, /->>'code' = 'ambiguous'/);
  assert.match(check, /RE: New vehicle order for 13102818 - PMG Build'\) IS FALSE/);
  assert.match(check, /FW: 1IRU519 J138000880 EPT/);
  assert.doesNotMatch(check, /::(?:pg_catalog\.)?regprocedure/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.doesNotMatch(check, /expected_function_md5/i);
  assert.match(up, /karratha135_pdc\.pdc_parts_completion_email_confirmations/);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /8ddb1477beeb94c7879c4021cccf1d40/);
  assert.match(down, /c5314b7bed8a1401b6698319125c2d74/);
  assert.match(down, /pdc_parts_mailbox_recipient_541/);
  assert.match(down, /pdc_parts_vehicle_match_541/);
  assert.match(down, /a rego-stock confirmation is stored/);
  assert.equal(scanSql(down).length, 0);
  assert.doesNotMatch(fs.readFileSync('karratha/app.js', 'utf8'), /parts_complete_wording_555/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F169 \|/);
  assert.doesNotMatch(up, /pdc_import_job_parts_csv_20260912/);
});
