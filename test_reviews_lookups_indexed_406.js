/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r406 (F16): the review-table lookups used per line by the QC and snapshot helpers
// stay indexed. The 91.9M sequential scans predate 20261019230000_helper_lookup_indexes.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const crypto = require('crypto');

const ID = '20261020142310_r406_reviews_lookups_indexed';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const indexes = fs.readFileSync('supabase/migrations/20261019230000_helper_lookup_indexes.sql', 'utf8');
const CHECK_MD5 = '725010dda682fc1ed9faa1b377fb1491';

function checkSql() {
  const m = up.match(/'reviews_lookups_indexed','F16','(?:[^']|'')*','((?:[^']|'')*)',true,195,'r406'\)/);
  assert.ok(m, 'check row');
  return m[1].replace(/''/g, "'");
}

test('migration is staging-only, adds only the F16 check, and asserts its md5', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.match(up, /pdc_production_environment_sentinel/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.match(up, /'fa4651cce7bb0fdb8985857779b62d93'/, 'fault_regression_check unchanged');
  assert.strictEqual(crypto.createHash('md5').update(checkSql()).digest('hex'), CHECK_MD5);
  assert.ok(up.includes(`'${CHECK_MD5}'`) && down.includes(`'${CHECK_MD5}'`));
  const body = up.replace(/\$[a-z]\$[\s\S]*?\$[a-z]\$/g, '');
  assert.doesNotMatch(body, /\b(CREATE|DROP|ALTER)\s+(INDEX|FUNCTION|TABLE)|\bUPDATE\s|\bDELETE\s/i, 'no DDL or data change');
  assert.match(body, /INSERT INTO pdc_ops\.regression_checks/);
});

test('the check covers the three lookup indexes and the sequential-scan counter', () => {
  const sql = checkSql();
  for (const name of ['pdc_tune_op_change_reviews_vehicle_idx', 'pdc_tune_approved_operation_source_idx', 'pdc_authenticated_email_operation_lines_vehicle_idx']) {
    assert.ok(sql.includes(`'public.${name}'`), name);
  }
  assert.ok(indexes.includes('pdc_tune_op_change_reviews_vehicle_idx') && indexes.includes('pdc_authenticated_email_operation_lines_vehicle_idx'));
  assert.match(sql, /indisvalid AND i\.indisready/);
  assert.match(sql, /seq_scan >= 91878195 THEN s\.seq_scan - 91878195 ELSE s\.seq_scan/, 'baseline survives a stats reset');
  assert.match(sql, /< 100000 AS ok/);
});

test('undo removes only the r406 check and asserts it first', () => {
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='reviews_lookups_indexed' AND added_in='r406';/);
  assert.match(down, /IS DISTINCT FROM '725010dda682fc1ed9faa1b377fb1491'/);
  assert.doesNotMatch(down, /DROP INDEX/);
});

test('FAULT_LOG has F16, F17 and F18 after F15', () => {
  const at = id => log.indexOf(`| ${id} |`);
  assert.ok(at('F15') > 0 && at('F15') < at('F16') && at('F16') < at('F17') && at('F17') < at('F18'));
  const f16 = log.split('\n').find(l => l.startsWith('| F16 |'));
  for (const s of ['reviews_lookups_indexed', `${ID}.down.sql`, '20261019230000_helper_lookup_indexes', 'test_reviews_lookups_indexed_406.js']) assert.ok(f16.includes(s), s);
  assert.ok(log.split('\n').find(l => l.startsWith('| F17 |')).includes('test_planner_perth_timezone_406.js'));
  assert.ok(log.split('\n').find(l => l.startsWith('| F18 |')).includes('pdc-workshop-departments.js'));
  assert.doesNotMatch(log.slice(at('F15'), at('F18')), /\n\n\| F1[678] \|/, 'table rows are contiguous');
});
