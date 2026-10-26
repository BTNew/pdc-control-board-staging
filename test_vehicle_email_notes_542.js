/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261026160000_r542_vehicle_email_notes.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261026160000_r542_vehicle_email_notes.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk542$'), up.lastIndexOf('$chk542$'));
const writer = up.slice(up.indexOf('$note542$'), up.lastIndexOf('$note542$'));
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

test('r542 shows email notes on the vehicle card and appends once per message', () => {
  assert.match(up, /PREVIEW/);
  assert.match(up, /SQL is not applied/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /true, 320, 'r542'/);
  assert.match(up, /ef3bd3587978f25862546483913231e4/);
  assert.match(up, /stoppage/);
  assert.match(up, /po_received/);
  assert.match(up, /ON CONFLICT \(source_email_id\) WHERE source_email_id IS NOT NULL/);
  assert.doesNotMatch(writer, /INSERT INTO public\.vehicles/);
  assert.doesNotMatch(writer, /INSERT INTO public\.workshop_bookings/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.append_vehicle_email_note_542\(uuid,text,text,text,text,text,text,text,timestamp with time zone\)'\)/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.list_vehicle_email_notes_542\(uuid\)'\)/);
  assert.match(check, /LIKE '%is_pdc_role\(''operator''::public\.pdc_role\)%'/);
  assert.match(check, /LIKE '%is_pdc_role\(''administrator''::public\.pdc_role\)%'/);
  assert.doesNotMatch(check, /::(?:pg_catalog\.)?regprocedure/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.doesNotMatch(check, /expected_function_md5\s*\)\s*(=|<>|!=)\s*[0-9]+/i);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /structured_data->>'source' = 'email_note_542'/);
  assert.equal(scanSql(down).length, 0);
  assert.match(app, /list_vehicle_email_notes_542/);
  assert.match(app, /function vehicleEmailNotesVisible/);
  assert.match(app, /Email notes/);
  assert.doesNotMatch(app, /append_vehicle_email_note_542/);
  assert.match(html, /r542=2026\.10\.26\.r542/);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('list_vehicle_email_notes_542'), false);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('r542=2026.10.26.r542'), false);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F156 \|/);
});
