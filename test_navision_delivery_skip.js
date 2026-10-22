/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { execFileSync } = require('node:child_process');

const migration = fs.readFileSync('supabase/migrations/20261020123000_navision_delivery_skip_deleted_vehicle.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261020123000_navision_delivery_skip_deleted_vehicle.down.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');

test('the delivery skip keeps other failures hard and names the stock', () => {
  assert.match(migration, /delivery_vehicle_not_found/);
  assert.match(migration, /linked vehicle is soft-deleted/);
  assert.match(migration, /linked vehicle is missing/);
  assert.match(migration, /navision_dealer_delivery_failed: % \(stock %\)/);
  assert.match(migration, /pdc_monitor_staging_guard/);
  assert.match(migration, /pdc_production_environment_sentinel/);
  assert.equal(migration.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(migration.includes('deleted_at = NULL'), false);
  assert.equal(migration.includes('SET deleted_at'), false);
  assert.match(down, /59dc9d0ecaa8e1729e23a4d802cc0abe/);
  assert.match(down, /DROP TABLE IF EXISTS pdc_navision_delivery_private\.import_reviews/);
  assert.match(app, /data\.delivery_reviews/);
  assert.match(app, /navision_dealer_delivery_failed/);
  assert.match(app, /soft-deleted vehicles were not restored/);
  assert.match(migration, /'authenticated, service_role'/);
  assert.match(migration, /'service_role'/);
  assert.match(migration, /string_agg\(split_part\(trim\(arg\), ' ', 1\), ', ' ORDER BY ord\)/);
  assert.equal(migration.includes("GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated'"), false);
});

function postgresAvailable() {
  if (process.env.PGHOST) return true;
  try {
    execFileSync('sudo', ['-u', 'postgres', 'psql', '-d', 'postgres', '-c', 'SELECT 1'], { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

test('stock 13045140 is flagged and the rest of the upload commits', { skip: postgresAvailable() ? false : 'no local Postgres' }, () => {
  execFileSync(process.execPath, ['scripts/run_navision_delivery_skip_local.js'], { stdio: 'inherit' });
});
