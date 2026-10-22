/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r413 (F29): the QC cache refill (cron every 20 s) returns -1 (busy) when a writer holds the epoch row (or the cache
// unique check waits on an in-flight transaction) instead of failing the run with "canceling statement due to lock
// timeout" (6 failures on 20 Oct; 3 of them during Pilbara service imports, which keep the global epoch row locked).
// Only lock_not_available is caught, after the same 250 ms wait; nothing else in the function changes. The static checks
// need no database; the behaviour proof runs on a throwaway local Postgres when one is available (CI service).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const ID = '20261020182014_r413_qc_cache_refill_busy_skip';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const original = fs.readFileSync('supabase/migrations/20261020082000_qc_operation_lines_cache_refill.sql', 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const SIG = 'pdc_work_categories_private.refill_qc_operation_lines_cache(integer)';
const OLD = 'c9bad5fb2c6ce6f549539fc06647a215';
const NEW = '7b59047dbeab8613738c5c530eb25705';
const CHECK_MD5 = '2510b3c1e00f25c6df67b07448d55b7b';
const CLOCK_TICK = '84af7607bfd0ce9907c89bae8644d5b6';
const FRC = 'fa4651cce7bb0fdb8985857779b62d93';

function body(sql) {
  const start = sql.indexOf('AS $function$') + 'AS $function$'.length;
  const end = sql.indexOf('$function$', start);
  assert.ok(start > 20 && end > start, 'function body');
  return sql.slice(start, end);
}
function checkSql(sql) {
  const start = sql.indexOf('$c413$') + '$c413$'.length;
  const end = sql.indexOf('$c413$', start);
  assert.ok(start > 10 && end > start, 'check sql');
  return sql.slice(start, end);
}
// Undo the r413 edit textually: drop the r413 comment, unwrap BEGIN ... EXCEPTION ... END and de-indent the INSERT.
function withoutR413(b) {
  const block = /  -- r413 \(F29\)[^\n]*\n(?:  --[^\n]*\n)*  BEGIN\n((?:    [^\n]*\n)+?)  EXCEPTION WHEN lock_not_available THEN\n    RAISE LOG 'qc_cache_refill_busy: %', SQLERRM;\n    RETURN -1;\n  END;\n/;
  const m = b.match(block);
  assert.ok(m, 'r413 block shape');
  return b.replace(block, m[1].replace(/^  /gm, ''));
}

test('r413 changes only the refill INSERT: catches lock_not_available and returns -1, everything else byte-identical', () => {
  const nb = body(up);
  assert.equal(md5(nb), NEW);
  assert.equal(md5(body(original)), OLD, 'the pre-r413 body is the 20261020082000 body');
  assert.equal(withoutR413(nb), body(original));
  assert.equal((nb.match(/EXCEPTION WHEN/g) || []).length, 1);
  assert.doesNotMatch(nb, /WHEN\s+others/i);
  assert.doesNotMatch(nb, /query_canceled|deadlock_detected|SKIP LOCKED|NOWAIT/i);
  assert.equal((nb.match(/FOR SHARE OF e/g) || []).length, 2);
  assert.match(up, /SET statement_timeout TO '4s'\n SET lock_timeout TO '250ms'\n SET search_path TO 'pg_catalog'/);
  assert.match(up, /RETURNS integer\n LANGUAGE plpgsql\n SECURITY DEFINER\n/);
  assert.equal((up.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1);
  assert.match(up, /CREATE OR REPLACE FUNCTION pdc_work_categories_private\.refill_qc_operation_lines_cache\(p_batch integer DEFAULT 20\)/);
});

test('r413 undo restores the pre-r413 body byte-exact and the baseline pin, and removes the check', () => {
  assert.equal(md5(body(down)), OLD);
  assert.equal(body(down), body(original));
  assert.match(down, new RegExp(`UPDATE pdc_ops\\.expected_function_md5 SET prosrc_md5='${OLD}',release='baseline',note=NULL`));
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='qc_cache_refill_busy_not_error' AND added_in='r413';/);
  assert.match(down, new RegExp(`<>'${NEW}' THEN RAISE EXCEPTION 'r413 undo: refill is not the r413 version`));
});

test('r413 guards: staging only, test window, expected versions, not re-applied; touches nothing else', () => {
  for (const sql of [up, down]) {
    assert.match(sql, /SET LOCAL lock_timeout = '2s';/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/);
    assert.match(sql, /pdc_monitor_staging_guard\(\)/);
    assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/);
    assert.match(sql, /to_regclass\('public\.pdc_production_environment_sentinel'\) IS NOT NULL/);
    assert.equal(sql.includes('vjdtsswhroyguxyfjdkt'), false);
    assert.ok(sql.includes(CLOCK_TICK) && sql.includes(FRC));
    assert.doesNotMatch(sql, /CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.workshop_clock_tick/i);
    assert.doesNotMatch(sql, /cron\.(alter_job|schedule|unschedule)/);
    const code = sql.split('\n').filter(l => !l.trimStart().startsWith('--')).join('\n');
    assert.doesNotMatch(code, /karratha|k135|pdc_admin_complete_vehicle_delete|INSERT INTO public\.vehicles/i);
    assert.doesNotMatch(sql, /GRANT|REVOKE|ALTER FUNCTION|DROP FUNCTION/);
    assert.match(sql, /proacl::text\|\|p\.prosecdef::text\|\|p\.provolatile::text\|\|'\|'\|\|array_to_string\(p\.proconfig,'\|'\)='\{postgres=X\/postgres\}truev\|statement_timeout=4s\|lock_timeout=250ms\|search_path=pg_catalog'/);
  }
  assert.match(up, new RegExp(`<>'${OLD}' THEN RAISE EXCEPTION 'r413: refill is not the expected version'`));
  assert.match(up, /r413: already applied/);
  assert.match(up, new RegExp(`UPDATE pdc_ops\\.expected_function_md5 SET prosrc_md5='${NEW}',release='r413'`));
});

test('r413 health check: refill busy handler, cron job running and a 24 h refill failure count', () => {
  const c = checkSql(up);
  assert.equal(md5(c), CHECK_MD5);
  assert.match(up, /\('qc_cache_refill_busy_not_error','F29',/);
  assert.match(up, /,true,210,'r413'\);/);
  assert.match(c, /cron\.job_run_details/);
  assert.match(c, /interval '24 hours'/);
  assert.match(c, /status <> 'succeeded'/);
  assert.match(c, /s\.failed_24h - s\.pre_r413_lock_timeouts = 0/);
  assert.match(c, /timestamptz '2026-10-20 15:18:10\+08'/);
  assert.match(c, /EXCEPTION WHEN lock_not_available THEN/);
  assert.match(up, new RegExp(`<>'${CHECK_MD5}' THEN RAISE EXCEPTION 'r413: check md5'`));
  assert.match(up, /EXECUTE \(SELECT check_sql FROM pdc_ops\.regression_checks WHERE check_name='qc_cache_refill_busy_not_error'\) INTO r;/);
});

test('FAULT_LOG records F29 with the migration, undo and guarding check', () => {
  const row = log.split('\n').find(l => l.startsWith('| F29 |'));
  assert.ok(row, 'F29 row');
  assert.ok(row.includes('20261020182014'));
  assert.ok(row.includes(`supabase/rollbacks/${ID}.down.sql`));
  assert.ok(row.includes('`qc_cache_refill_busy_not_error`'));
  assert.ok(row.includes('test_qc_cache_refill_busy_413.js'));
  const f28 = log.indexOf('| F28 |');
  assert.ok(f28 > 0 && f28 < log.indexOf('| F29 |'));
});

function postgresProofAvailable() {
  if (process.env.PGHOST) return true;
  try {
    execFileSync('sudo', ['-n', '-u', 'postgres', 'psql', '-d', 'postgres', '-c', 'SELECT 1'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('r413 refill returns -1 under a held lock where the old one failed (local Postgres)', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_qc_cache_refill_busy_413_local.js'], { stdio: 'inherit' });
});
