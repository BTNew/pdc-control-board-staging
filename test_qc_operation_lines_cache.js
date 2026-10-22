/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const forwardPath = 'supabase/migrations/20261019232000_qc_operation_lines_cache.sql';
const downPath = 'supabase/rollbacks/20261019232000_qc_operation_lines_cache.down.sql';
const inputs = JSON.parse(fs.readFileSync('scripts/qc_operation_lines_cache_inputs.json', 'utf8'));
const reviewed = 'b677d7bfdf67c046fd05922da249325c';

function between(sql, tag) {
  const marker = '$' + tag + '$';
  const start = sql.indexOf(marker);
  const end = sql.lastIndexOf(marker);
  assert.ok(start > 0 && end > start, tag);
  return sql.slice(start + marker.length, end);
}

test('the QC line cache covers the generated input tables and restores the reviewed body', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  if (inputs.time_or_user_dependent) {
    throw new Error('QC operation lines depend on the clock or the signed-in user and cannot be cached');
  }
  assert.equal(inputs.relations.length, 25);
  assert.equal(inputs.reviewed_body_md5, reviewed);
  for (const rel of inputs.relations) {
    const qualified = `${rel.schema}.${rel.name}`;
    assert.match(forward, new RegExp(`AFTER INSERT OR UPDATE OR DELETE ON ${qualified}\\n`));
    assert.match(forward, new RegExp(`AFTER TRUNCATE ON ${qualified}\\n`));
    assert.match(down, new RegExp(`DROP TRIGGER IF EXISTS qc_operation_lines_cache_row ON ${qualified};`));
    assert.match(down, new RegExp(`DROP TRIGGER IF EXISTS qc_operation_lines_cache_truncate ON ${qualified};`));
  }
  const uncached = between(forward, 'function');
  const restored = between(down, 'function');
  assert.equal(uncached, restored);
  assert.equal(crypto.createHash('md5').update(uncached.replace(/\r/g, '')).digest('hex'), reviewed);
  const wrapper = between(forward, 'wrapper');
  assert.match(wrapper, /qc_operation_lines_cache/);
  assert.match(wrapper, /pdc_qc_operation_lines_379_uncached/);
  assert.equal(wrapper.toLowerCase().includes('insert'), false);
  assert.equal(wrapper.toLowerCase().includes('now('), false);
  assert.match(forward, /LANGUAGE sql\n STABLE SECURITY DEFINER/);
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.doesNotMatch(forward, /cron|CREATE POLICY|administrator_schedule_workshop_vehicle/);
  assert.equal(fs.existsSync(path.join('supabase/migrations', path.basename(downPath))), false);
  assert.equal(down.includes('DROP TABLE IF EXISTS pdc_work_categories_private.qc_operation_lines_cache'), true);
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

test('a rolled-back edit of every input table refreshes the cached lines', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_qc_operation_lines_cache_local.js'], { stdio: 'inherit' });
});
