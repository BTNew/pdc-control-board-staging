'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const forwardPath = 'supabase/migrations/20261020075300_fix_375_safeupdate.sql';
const downPath = 'supabase/rollbacks/20261020075300_fix_375_safeupdate.down.sql';
const original = '446f28dc70b7a0e5e3ff13462ea29226';
const fixed = '2ca1e202c59e8238d75f5ebac52dced8';

function between(sql) {
  const marker = '$invalidate$';
  const start = sql.indexOf(marker);
  const end = sql.lastIndexOf(marker);
  assert.ok(start > 0 && end > start);
  return sql.slice(start + marker.length, end);
}

test('the cache wipes that broke Navision import end in WHERE true', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  const body = between(forward);
  const restored = between(down);
  assert.equal(crypto.createHash('md5').update(body.replace(/\r/g, '')).digest('hex'), fixed);
  assert.equal(crypto.createHash('md5').update(restored.replace(/\r/g, '')).digest('hex'), original);
  assert.equal((body.match(/DELETE FROM pdc_work_categories_private\.qc_operation_lines_cache WHERE true;/g) || []).length, 3);
  assert.equal(body.includes('DELETE FROM pdc_work_categories_private.qc_operation_lines_cache;'), false);
  assert.equal((restored.match(/DELETE FROM pdc_work_categories_private\.qc_operation_lines_cache;/g) || []).length, 3);
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
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

test('a shared input write and truncate clear the cache under safeupdate', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_qc_operation_lines_cache_safeupdate_local.js'], { stdio: 'inherit' });
});
