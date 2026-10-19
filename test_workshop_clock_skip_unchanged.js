'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const forward = fs.readFileSync('supabase/migrations/20261019143000_workshop_clock_skip_unchanged.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261019143000_workshop_clock_skip_unchanged.down.sql', 'utf8');
const reviewed = 'a7cd97007e7fdd96b01c90929d42fe2d';
const rewritten = '84af7607bfd0ce9907c89bae8644d5b6';

function between(sql, tag) {
  const parts = sql.split('$' + tag + '$');
  assert.equal(parts.length, 3, tag);
  return parts[1];
}

test('the clock skip migration keeps the reviewed body and a matching undo', () => {
  const inserted = between(forward, 'insert');
  const removed = between(down, 'insert');
  assert.equal(inserted, removed);
  assert.equal(between(forward, 'needle'), between(down, 'needle'));
  assert.ok(inserted.indexOf('An enabled overdue arrival') < inserted.indexOf('ORDER BY id FOR UPDATE'));
  assert.equal(inserted.split('NOT EXISTS(').length - 1, 2);
  assert.match(inserted, /b\.status='planned' AND b\.actual_start_at IS NULL AND b\.scheduled_start_at<p_now/);
  assert.match(inserted, /b\.status IN\('started','stoppage'\) AND greatest/);
  assert.match(inserted, /workshop_booking_effective_end_at\(b\.id\)/);
  assert.match(inserted, /pdc_bus_private\.clock_next_minute/);
  assert.match(inserted, /s\.code='BUS_4X4'/);
  assert.match(inserted, /b\.status='queued' AND b\.bay_id IS NULL AND b\.actual_start_at IS NULL/);
  assert.match(inserted, /\(y\.is_active AND s\.active AND s\.planner_enabled\) IS TRUE/);
  assert.match(forward, new RegExp(reviewed));
  assert.match(forward, new RegExp(rewritten));
  assert.match(down, new RegExp(reviewed));
  assert.match(down, new RegExp(rewritten));
  assert.match(forward, /pdc_monitor_staging_guard/);
  assert.match(down, /pdc_monitor_staging_guard/);
  assert.equal(forward.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(down.includes('vjdtsswhroyguxyfjdkt'), false);
  assert.equal(fs.existsSync('supabase/migrations/20261019143000_workshop_clock_skip_unchanged.down.sql'), false);
  assert.equal(down.includes('supabase/migrations'), false);
});
