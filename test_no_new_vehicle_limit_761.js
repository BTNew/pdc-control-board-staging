'use strict';
// r761 (F367, Craig 31 Oct 05:07): "we should let more than 15 be created in one upload, there shouldnt be a limit".
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r761: queue hold on new vehicles removed; dry run gates only cars leaving the board; check 481; rollback', () => {
  const up = fs.readFileSync('supabase/migrations/20261031051500_r761_no_new_vehicle_limit.sql', 'utf8');
  assert.match(up, /IF md5\(v_old\) <> '1b2efb3460607fd58d3eb491f05387bf' THEN RAISE EXCEPTION 'r761: submit_finish/);
  assert.match(up, /'no_new_vehicle_limit_761', 'F367',/);
  assert.match(up, /'pdc620_archive_gate'\) > 0/, 'the leaving-the-board gate must stay');
  const parse = fs.readFileSync('supabase/functions/revolution-upload/parse.js', 'utf8');
  assert.match(parse, /const sanity = archived > 15;/);
  assert.doesNotMatch(parse, /fresh > 15/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-revolution-upload\.js\?[^"]*&amp;r761=2026\.10\.31\.r761/);
  assert.match(fs.readFileSync('supabase/rollbacks/20261031051500_r761_no_new_vehicle_limit.down.sql', 'utf8'), /would not return to the pre-r761 md5/);
});
