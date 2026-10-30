'use strict';
// r743 (F348): run_jobs pauses three seconds between import parts while work remains, so board writes get through.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030085000_r743_import_breathes_between_parts.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030085000_r743_import_breathes_between_parts.down.sql', 'utf8');

test('r743: pause only after COMMIT, only while jobs remain, anchored on the r620 body, staging only', () => {
  assert.match(up, /COMMIT;\\n    -- r743:[^\n]*\\n    IF EXISTS \(SELECT 1 FROM pdc_import_620\.jobs WHERE status IN \(''queued'', ''running''\)\) THEN PERFORM pg_catalog\.pg_sleep\(3\); END IF;\\n  END LOOP;/);
  assert.match(up, /md5\(v_old\) <> 'f05db04600dc405e1d1c269ad26ee5d5'/, 'replaces only the body it was written against');
  assert.match(up, /<> 1 THEN RAISE EXCEPTION 'r743: anchor not found once'/);
  assert.match(up, /r743: an import job is running/);
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /readback differs/);
  assert.doesNotMatch(up, /expected_function_md5/, 'run_jobs is not a pinned function');
  assert.match(down, /pg_sleep\(3\)/, 'rollback removes the pause');
});
