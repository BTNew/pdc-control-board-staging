'use strict';
// r773 (F375, Craig 31 Oct 08:38): "shouldnt it only show me the changes?" The dry run asks the server which stocks are unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r773: dry run calls the delta RPCs, regroups the lists, page shows Changed / awaiting approval / Unchanged', () => {
  const ts = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');
  const js2 = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(ts, /async function previewDelta773\(/);
  assert.match(ts, /if \(parsed\.kind === 'service_whole'\) await previewDelta773\(/);
  assert.match(ts, /'revolution_upload_delta_773'/);
  assert.match(ts, /'revolution_upload_delta_compare_773'/);
  assert.match(ts, /changes\.awaiting_approval = awaiting;/);
  assert.match(ts, /changes\.held_before = retrying;/);
  assert.match(js2, /\['held_before', 'Held last time, retrying'/);
  assert.match(ts, /result\.counts\.unchanged = changes\.unchanged\.length;/);
  const js = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(js, /\['updated', 'Changed'/);
  assert.match(js, /\['awaiting_approval', 'Imported, waiting on New Vehicles'/);
  assert.match(js, /Could not compare with the last import/);
  const up = fs.readFileSync('supabase/migrations/20261031090000_r773_preview_delta.sql', 'utf8');
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.revolution_upload_delta_773\(p_rows jsonb\)/);
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.revolution_upload_delta_compare_773\(p_hashes jsonb\)/);
  assert.match(up, /row_content_hash_771/);
  assert.match(up, /'preview_delta_773', 'F375'/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-revolution-upload\.js\?[^"]*&amp;r773=2026\.10\.31\.r773/);
});

test('r777: leaving list split by Navision; a refusal after begin abandons the loading job; snapshot reuse', () => {
  const ts = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');
  assert.match(ts, /'revolution_upload_navision_777'/);
  assert.match(ts, /changes\.leaving_tagged = leaving\.filter/);
  assert.match(ts, /'revolution_upload_abandon_777'/);
  assert.ok((ts.match(/return await abandon\(/g) || []).length >= 5, 'every refusal after begin abandons the job');
  const js = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(js, /\['leaving_tagged', 'Staying, tagged/);
  assert.match(js, /Navision \$\{entry\.dealer\}/);
  const up = fs.readFileSync('supabase/migrations/20261031103500_r777_preview_leaving_reasons.sql', 'utf8');
  assert.match(up, /FUNCTION public\.revolution_upload_navision_777\(p_stocks jsonb\)/);
  assert.match(up, /FUNCTION public\.revolution_upload_abandon_777\(p_upload uuid, p_reason text\)/);
  assert.match(fs.readFileSync('supabase/migrations/20261031061500_r763_website_snapshot_and_last_part_archive.sql', 'utf8'), /'reused', true/);
});
