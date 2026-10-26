/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r553 (F167): accept the renamed CW Revolution parts workbook.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261027040000_r553_parts_import_cw_rename';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const notes = fs.readFileSync('release_log/r553/NOTES', 'utf8');

const OLD_PROSRC = 'ccf492618ca11625470b691fbe029ac7';
const NEW_PROSRC = 'e56cd1f5d12205a0d72826d64cb8d1de';
const OLD_DEF = '2868827fe333373debf7b40194f5d46c';
const NEW_DEF = '76b0570ee2c788d5cacf9d01a5843ed6';

function checkSql(sql) {
  const start = sql.indexOf('$chk553$');
  const end = sql.indexOf('$chk553$', start + 8);
  assert.ok(start >= 0 && end > start);
  return sql.slice(start + 8, end);
}

test('migration files are LF only', () => {
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
  assert.doesNotMatch(notes, /\r/);
});

test('staging only, release window, never names production', () => {
  for (const sql of [up, down]) {
    assert.match(sql, /pdc_monitor_staging_guard\(\)/);
    assert.match(sql, /cdsmnqxtyyoeoznmbidd/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/);
    assert.match(sql, /^SET LOCAL lock_timeout = '2s';$/m);
    assert.match(sql, /pdc_production_environment_sentinel/);
    assert.equal(sql.includes('vjdtsswhroyguxyfjdkt'), false);
  }
});

test('prosrc and functiondef md5s, pin in place, outlook check length', () => {
  for (const hash of [OLD_PROSRC, NEW_PROSRC, OLD_DEF, NEW_DEF]) {
    assert.ok(up.includes(hash), hash);
    assert.ok(down.includes(hash), `down ${hash}`);
  }
  assert.match(up, /SET prosrc_md5='e56cd1f5d12205a0d72826d64cb8d1de'/);
  assert.match(up, /release='r553'/);
  assert.match(up, /AND release='r505'/);
  assert.match(down, /SET prosrc_md5='ccf492618ca11625470b691fbe029ac7'/);
  assert.match(down, /release='r505'/);
  assert.match(up, /pin count stays 241|pin count is not 241|pin count changed/);
  assert.match(up, /length\(check_sql\)=7303/);
  assert.match(down, /length\(check_sql\)=7303/);
  assert.equal(up.includes('karratha135'), false);
  assert.equal(down.includes('karratha135'), false);
});

test('only the CW arm is added; Pilbara and V1 literals stay', () => {
  assert.match(up, /CW PMG PD Parts Status Complete/);
  assert.match(up, /\^\(CW \)\?PMG PD Parts Status Complete\( - Job 1\)\?\[\.\]xlsx\?\$/);
  assert.match(up, /PMG PD Parts Status Complete - Pilbara/);
  assert.match(up, /\^PMG PD Parts Status Complete\[\.\]xlsx\?\$/);
  assert.match(up, /PMG PD Parts Status V1 - Job 1/);
  assert.match(up, /Workshop hours/);
  assert.match(up, /notes\.txt/);
});

test('parts_import_cw_rename uses schema-qualified types and no regprocedure cast', () => {
  const check = checkSql(up);
  assert.match(up, /\('parts_import_cw_rename', 'F167'/);
  assert.match(up, /true, 328, 'r553'\)/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.doesNotMatch(check, /expected_function_md5\s*\)\s*(=|<>|!=|is\s+distinct\s+from|is\s+not\s+distinct\s+from)\s*[0-9]+/i);
  assert.doesNotMatch(check, /[0-9]+\s*(=|<>|!=)\s*\(\s*select\s+count\(\s*\*\s*\)\s+from\s+pdc_ops\.expected_function_md5\s*\)/i);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.pdc_import_job_parts_csv_20260912\(pg_catalog\.jsonb,pg_catalog\.jsonb\)'\)/);
  assert.equal(check.includes('::regprocedure'), false);
  assert.equal(check.includes('::regproc'), false);
  assert.match(up, /set_config\('search_path', 'pg_catalog', true\)/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks\s+WHERE check_name='parts_import_cw_rename'/);
  assert.match(log, /\| F167 \|/);
  assert.match(log, /parts_import_cw_rename/);
  assert.match(notes, /r553 \/ F167 \/ sort 328/);
  assert.match(notes, /Craig approved go-live/);
});
