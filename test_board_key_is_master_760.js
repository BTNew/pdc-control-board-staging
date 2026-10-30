'use strict';
// r760 (F366, Craig 30 Oct 20:24): "the key on the board is the correct key now". The Service as a Whole file never writes a key.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r760: key import returns board_key_is_master for every as-a-Whole row; pin moves; dry run no longer errors on key clashes', () => {
  const up = fs.readFileSync('supabase/migrations/20261030203500_r760_board_key_is_master.sql', 'utf8');
  assert.match(up, /IF md5\(v_old\) <> '7db7b5482de592222cfc5828ff9e6a45' THEN RAISE EXCEPTION 'r760: key import body is not the r479 one'/);
  assert.match(up, /''kept'',''board_key_is_master_r760''/);
  assert.doesNotMatch(up.split('b1 text')[1], /nullif\(btrim\(coalesce\(v\.key_number/, 'the blank-key condition is gone from the new body');
  assert.match(up, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = md5\(v_new\), release = 'r760' WHERE prosrc_md5 = '7db7b5482de592222cfc5828ff9e6a45'/);
  assert.match(up, /'board_key_is_master_760', 'F366',/);
  const parse = fs.readFileSync('supabase/functions/revolution-upload/parse.js', 'utf8');
  assert.doesNotMatch(parse, /key_not_unique/);
  assert.match(parse, /file_key_clashes_ignored: keyClashesIgnored/);
  const down = fs.readFileSync('supabase/rollbacks/20261030203500_r760_board_key_is_master.down.sql', 'utf8');
  assert.match(down, /would not return to the r479 md5/);
});
