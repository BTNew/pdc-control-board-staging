'use strict';
// r721 (F331): lines move into or out of a station whose job already finished; Move all to ____ on a station heading.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
test('Move all to on each station heading, one line at a time, no confirm pop-up', () => {
  assert.match(js, /<span>Move all to<\/span><select data-vso-move-all/);
  assert.match(js, /async function moveAllTo\(key, lineKeys, category, select\)/);
  assert.match(js, /for \(const lineKey of lineKeys\) \{/);
  assert.equal((js.match(/closest: \(\) => null \}, \{ release: true \}\)/g) || []).length, 2, 'line and move-all saves skip the confirm');
});
test('server: only a finished job that did the line blocks; a moved-in line reopens the station', () => {
  const sql = fs.readFileSync('supabase/migrations/20261029150000_r721_move_into_finished_station.sql', 'utf8');
  assert.match(sql, /AND b\.work_category_scope \? p_line_identity\) -- r721 \(F331\): only a finished job that did this line/);
  assert.match(sql, /SET required=true,completed=false,completed_by=NULL,completed_at=NULL/);
  assert.match(sql, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = v_new_md5 WHERE prosrc_md5 = v_md5;/);
});
