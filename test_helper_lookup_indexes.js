/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const forwardPath = 'supabase/migrations/20261019230000_helper_lookup_indexes.sql';
const downPath = 'supabase/rollbacks/20261019230000_helper_lookup_indexes.down.sql';

test('helper lookup indexes cover only the proven sequential scans and roll back', () => {
  const forward = fs.readFileSync(forwardPath, 'utf8');
  const down = fs.readFileSync(downPath, 'utf8');
  assert.match(forward, /pdc_monitor_staging_guard\(\)/);
  assert.match(forward, /pdc_production_environment_sentinel/);
  assert.match(forward, /reviewed_helper_lookup_columns_changed/);
  assert.match(forward, /CREATE INDEX IF NOT EXISTS pdc_tune_op_change_reviews_vehicle_idx\s+ON public\.pdc_tune_operation_change_reviews \(vehicle_id, status, change_kind\);/);
  assert.match(forward, /CREATE INDEX IF NOT EXISTS pdc_authenticated_email_operation_lines_vehicle_idx\s+ON public\.pdc_authenticated_email_operation_lines \(vehicle_id\);/);
  assert.equal((forward.match(/CREATE INDEX/g) || []).length, 2);
  assert.doesNotMatch(forward, /CREATE OR REPLACE FUNCTION|ALTER TABLE|CREATE POLICY|vjdtsswhroyguxyfjdkt/);
  assert.doesNotMatch(forward, /schedule_vehicle_work|administrator_schedule_workshop_vehicle|pdc_email_ai_successor_action_receipts/);

  assert.match(down, /pdc_monitor_staging_guard\(\)/);
  assert.match(down, /pdc_production_environment_sentinel/);
  assert.match(down, /DROP INDEX IF EXISTS public\.pdc_tune_op_change_reviews_vehicle_idx;/);
  assert.match(down, /DROP INDEX IF EXISTS public\.pdc_authenticated_email_operation_lines_vehicle_idx;/);
  assert.equal((down.match(/DROP INDEX/g) || []).length, 2);
  assert.doesNotMatch(down, /vjdtsswhroyguxyfjdkt|CREATE INDEX|CREATE OR REPLACE FUNCTION/);
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

test('a local database uses both indexes and the rollback removes them', { skip: !postgresProofAvailable() }, () => {
  execFileSync(process.execPath, ['scripts/run_helper_lookup_indexes_local.js'], { stdio: 'inherit' });
});
