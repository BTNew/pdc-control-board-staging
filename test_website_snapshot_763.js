'use strict';
// r763 (F369, F371): the website Apply records the as-a-Whole snapshot; cars leave the board on the last part only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('r763: edge function records the snapshot before the rows and refuses when it cannot', () => {
  const ts = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');
  const snap = ts.indexOf("'revolution_upload_snapshot_763'");
  const rows = ts.indexOf("'revolution_upload_rows_728'");
  assert.ok(snap > 0 && rows > snap, 'snapshot RPC must run before the rows RPC');
  assert.match(ts, /The snapshot could not be recorded\./);
  assert.match(ts, /The snapshot is incomplete\./);
  assert.match(ts, /snapshot_lines: recorded/);
});

test('r763: migration pins the three bodies, defers the archive to the last part, un-duplicates a job that applied nothing', () => {
  const up = fs.readFileSync('supabase/migrations/20261031061500_r763_website_snapshot_and_last_part_archive.sql', 'utf8');
  for (const md5 of ['86b429f0e59cebccd82359d890c8b0f6', '8fdc72089413b558fd90c6b85ccd5a37', '2b75aa8ecef7eae73b0ca48941eb6475']) assert.match(up, new RegExp(md5));
  assert.match(up, /deferred_to_last_part/);
  assert.match(up, /CASE WHEN p_last THEN ''on'' ELSE ''off'' END/);
  assert.match(up, /p->''apply''->>''ok'' = ''true''/);
  assert.match(up, /record_snapshot_479\(p_header - 'gmail_message_id', p_lines\)/);
  assert.match(up, /source_snapshot_at, s\.expected_line_count INTO v_at, v_exp FROM pdc_service_snapshot_private\.snapshots_479/, 'retry reuses or completes the first snapshot');
  assert.match(up, /'website_snapshot_recorded_763', 'F369'/);
  assert.match(up, /'archive_only_on_last_part_763', 'F371'/);
  assert.match(up, /pdc_backup_r763_20261031\.function_sources/);
  const down = fs.readFileSync('supabase/rollbacks/20261031061500_r763_website_snapshot_and_last_part_archive.down.sql', 'utf8');
  assert.match(down, /DROP FUNCTION IF EXISTS public\.revolution_upload_snapshot_763/);
  assert.match(down, /would not return to the pre-r763 md5/);
});

test('r763: service_rows still builds the snapshot payload the recorder accepts', async () => {
  const { snapshotPayload } = await import('./supabase/functions/revolution-upload/service_rows.js');
  const sha = 'a'.repeat(64);
  const raw = { Dept: '138', 'R/O #': 'J138000001', 'Line #': 1, 'Sub Status': '10' };
  const identities = new Map([['138|J138000001', { stock: '13000001', file_stock: '13000001', file_rego: null, status: 'linked' }]]);
  const out = snapshotPayload(sha, '2026-10-31T00:00:00.000Z', [{ raw }], identities);
  assert.equal(out.header.snapshot_sha256, sha);
  assert.equal(out.header.report_title, 'PMG PD Service as a Whole w/Sublet');
  assert.equal(out.header.line_count, 1);
  assert.equal(out.lines[0].length, 8);
  assert.equal(out.lines[0][7], 'linked');
});
