'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const forwardPath = 'supabase/migrations/20261019233000_qc_operation_lines_cache_refill.sql';
const downPath = 'supabase/rollbacks/20261019233000_qc_operation_lines_cache_refill.down.sql';
const clockCommand = 'SELECT public.workshop_clock_tick(true,clock_timestamp());';
const refillCommand = 'SELECT pdc_work_categories_private.refill_qc_operation_lines_cache(20);';

function between(sql, tag) {
  const marker = '$' + tag + '$';
  const start = sql.indexOf(marker);
  const end = sql.lastIndexOf(marker);
  assert.ok(start > 0 && end > start, tag);
  return sql.slice(start + marker.length, end);
}

test('the QC line cache refill is a bounded minute job and does not take the clock locks', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  const body = between(forward, 'function');
  assert.match(forward, /staging-qc-operation-lines-cache-refill/);
  assert.match(forward, /\* \* \* \* \*/);
  assert.match(forward, /statement_timeout/);
  assert.match(forward, /lock_timeout/);
  assert.match(body, /pdc_qc_operation_lines_379_uncached/);
  assert.equal(body.includes('pdc_qc_operation_lines_379('), false);
  assert.match(body, /p_batch > 40/);
  assert.equal(forward.includes(refillCommand), true);
  assert.equal(forward.split(clockCommand).length - 1, 2);
  assert.equal(down.split(clockCommand).length - 1, 2);
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.match(down, /pdc_production_environment_sentinel/);
  assert.match(down, /cron\.unschedule\('staging-qc-operation-lines-cache-refill'\)/);
  assert.match(down, /DROP FUNCTION IF EXISTS pdc_work_categories_private\.refill_qc_operation_lines_cache\(integer\)/);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(forward.toLowerCase().includes('pg_advisory'), false);
  assert.equal(down.toLowerCase().includes('pg_advisory'), false);
  assert.equal(body.toLowerCase().includes('workshop_clock'), false);
  assert.equal(body.toLowerCase().includes('workshop_bookings'), false);
  assert.doesNotMatch(forward, /for\s+update/i);
  assert.doesNotMatch(forward, /for\s+share/i);
  assert.doesNotMatch(forward, /lock\s+table/i);
  assert.doesNotMatch(down, /for\s+update/i);
  assert.doesNotMatch(down, /for\s+share/i);
  assert.doesNotMatch(down, /lock\s+table/i);
  assert.doesNotMatch(forward, /CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+public\.workshop_clock_tick/i);
  assert.equal(down.includes('DROP TABLE'), false);
  assert.equal(fs.existsSync(path.join('supabase/migrations', path.basename(downPath))), false);
});

function postgresProofAvailable() {
  if (process.env.PGHOST) return true;
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-c', 'SELECT 1'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('a bounded refill restores deleted cache rows and the rollback leaves the clock job', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_qc_operation_lines_cache_refill_local.js'], { stdio: 'inherit' });
});
