'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const forwardPath = 'supabase/migrations/20261019231000_inbox_page_vehicles.sql';
const downPath = 'supabase/rollbacks/20261019231000_inbox_page_vehicles.down.sql';
const behaviorPath = 'scripts/inbox_page_vehicles_behavior.sql';
const reviewed = '6f2c14b914643a93e53dfb9339de9dca';
const rewritten = '7db67f598be0a2ad38cffb63e1745e15';

function functionBody(sql) {
  const marker = '$function$';
  const start = sql.indexOf(marker);
  const end = sql.lastIndexOf(marker);
  assert.ok(start > 0 && end > start);
  return sql.slice(start + marker.length, end);
}

test('inbox v2 reads page vehicles and the rollback restores the reviewed body', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  const behavior = fs.readFileSync(behaviorPath, 'utf8');
  const next = functionBody(forward);
  const previous = functionBody(down);
  assert.equal(crypto.createHash('md5').update(previous.replace(/\r/g, '')).digest('hex'), reviewed);
  assert.equal(crypto.createHash('md5').update(next.replace(/\r/g, '')).digest('hex'), rewritten);
  assert.equal(next.includes('get_pdc_email_vehicle_location_snapshot'), false);
  assert.equal(next.includes('snapshot_vehicles'), false);
  assert.equal(next.includes('v_snapshot'), false);
  assert.match(next, /LEFT JOIN LATERAL public\.pdc_email_inbox_snapshot_vehicle\(groups\.vehicle_id\) sv ON true/);
  assert.match(previous, /v_snapshot:=public\.get_pdc_email_vehicle_location_snapshot\(\);/);
  assert.match(forward, /pdc_email_inbox_snapshot_vehicle\(p_vehicle_id uuid\)/);
  assert.match(forward, /pdc_tune_vehicle_details_v5\(v\.id\)/);
  assert.match(forward, /owner_board_hold_active_20261019\(v\.id, v\.stock_number, NULL\)/);
  assert.match(forward, /2b3b4f3b-c3a8-5a24-96cf-bcf3cf741b02/);
  assert.match(forward, new RegExp(reviewed));
  assert.match(forward, new RegExp(rewritten));
  assert.match(down, new RegExp(reviewed));
  assert.match(down, /DROP FUNCTION IF EXISTS public\.pdc_email_inbox_snapshot_vehicle\(uuid\)/);
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.match(down, /pdc_production_environment_sentinel/);
  assert.equal(forward.includes('get_pdc_email_ai_transaction_successor_inbox('), false);
  assert.equal(down.includes('get_pdc_email_ai_transaction_successor_inbox('), false);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.doesNotMatch(forward, /cron|CREATE POLICY|ALTER TABLE|GRANT /);
  assert.doesNotMatch(down, /cron|CREATE POLICY|ALTER TABLE|GRANT /);
  assert.equal(fs.existsSync(path.join('supabase/migrations', path.basename(downPath))), false);
  const referenceStart = behavior.indexOf('CREATE OR REPLACE FUNCTION public.inbox_page_reference_vehicle');
  const referenceEnd = behavior.indexOf('CREATE OR REPLACE FUNCTION public.get_pdc_email_vehicle_location_snapshot');
  assert.ok(referenceStart > 0 && referenceEnd > referenceStart);
  assert.equal(behavior.slice(referenceStart, referenceEnd).includes('pdc_email_inbox_snapshot_vehicle'), false);
  assert.match(behavior, /md5\(\(old_result->'items'\)::text\)/);
  assert.match(behavior, /ROLLBACK;/);
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

test('a rolled-back synthetic inbox matches the snapshot labels', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_inbox_page_vehicles_local.js'], { stdio: 'inherit' });
});
