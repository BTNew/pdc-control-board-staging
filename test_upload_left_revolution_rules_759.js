'use strict';
// r759 (F365, Craig 30 Oct 20:01 "go with the new rules and make sure we have a backup"): the Service as a Whole apply
// completes a missing car when it is off Navision and keeps it on the board, tagged, when it is still on Navision.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r759: backup guard, anchored r569 body, two branches, tag clears when back in the sheet, check 479, rollback from backup', () => {
  const up = fs.readFileSync('supabase/migrations/20261030201500_r759_upload_left_revolution_rules.sql', 'utf8');
  assert.match(up, /IF to_regclass\('pdc_backup_r759_20261030\.vehicles'\) IS NULL THEN RAISE EXCEPTION 'r759: backup schema missing'/);
  assert.match(up, /IF md5\(v_old\) <> '6bd4a75d2b96a187b3e0d5ff99f4d217' THEN RAISE EXCEPTION 'r759: service_whole_archive_569/);
  assert.match(up, /IF v_on_sales THEN\\n'/, 'rule 2 branch keyed on the Navision check the function already makes');
  assert.match(up, /''revolution_missing_since'', to_char\(clock_timestamp\(\) AT TIME ZONE ''Australia\/Perth'',''YYYY-MM-DD''\)/);
  assert.match(up, /CONTINUE;\\n'/, 'rule 2 never reaches the completion update');
  assert.match(up, /lifecycle_state=''completed'', current_location=''Completed'', workshop_status=''completed''/, 'rule 1 completes');
  assert.match(up, /board_purge_reason=''r759: left the Revolution service list and is not on Navision; completed''/);
  assert.match(up, /- ''revolution_missing_since''\) - ''revolution_missing_rule''/, 'tag clears for cars back in the sheet');
  assert.match(up, /''kept_on_navision'',v_kept,''missing_tag_cleared'',v_cleared/);
  assert.match(up, /'upload_left_revolution_rules_759', 'F365',/);
  assert.doesNotMatch(up, /UPDATE public\.navision_backend_records/, 'no Sales or Navision write');
  const down = fs.readFileSync('supabase/rollbacks/20261030201500_r759_upload_left_revolution_rules.down.sql', 'utf8');
  assert.match(down, /FROM pdc_backup_r759_20261030\.function_sources WHERE nspname = 'pdc_codex_intake_private' AND proname = 'service_whole_archive_569'/);
  assert.match(down, /<> '6bd4a75d2b96a187b3e0d5ff99f4d217' THEN RAISE EXCEPTION 'r759 down/);
});
