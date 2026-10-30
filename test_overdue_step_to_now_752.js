'use strict';
// r752 (F357): an overdue planned job moves to now, not to the next 30 minute mark; the clock functions are untouched.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030105500_r752_overdue_job_moves_to_now.sql', 'utf8');
test('r752: setting to 1, pinned clock plan left alone, check 463 watches the clock history since the fix', () => {
  assert.match(up, /VALUES \('clock_overdue_step_minutes', to_jsonb\(1\), 'global'\)/);
  assert.match(up, /ON CONFLICT \(key\) DO UPDATE SET value = to_jsonb\(1\)/);
  assert.match(up, /md5\(prosrc\) FROM pg_proc WHERE oid = 'public\.workshop_clock_plan\(jsonb,jsonb,timestamptz\)'::regprocedure\) <> '58384098be842b62c87b0fa374a15bb6'/, 'reads the setting from the pinned body, never edits it');
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION|EXECUTE v_def/, 'no function change');
  assert.match(up, /'overdue_job_moves_to_now_752', 'F357', 'r752', true, 463,/);
  assert.match(up, /> h\.clock_at \+ interval '16 minutes'/);
  assert.match(up, /'2026-10-30 10:50\+08'::timestamptz/, 'history before the fix is not judged');
  assert.ok(fs.existsSync('supabase/rollbacks/20261030105500_r752_overdue_job_moves_to_now.down.sql'));
});
