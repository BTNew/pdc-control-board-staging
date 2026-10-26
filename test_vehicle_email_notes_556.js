/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261027070000_r556_vehicle_email_notes.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027070000_r556_vehicle_email_notes.down.sql', 'utf8');
const check = up.slice(up.indexOf('$chk556$'), up.lastIndexOf('$chk556$'));
const writer = up.slice(up.indexOf('$note556$'), up.lastIndexOf('$note556$'));
const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const cssStart = app.indexOf('const VEHICLE_EMAIL_PARTS_ETA_CSS');
const css = app.slice(cssStart, app.indexOf('function vehicleEmailNotesVisible'));
const signature = 'public.record_pdc_vehicle_email_556(text,uuid,text,text,text,timestamp with time zone,text,text,text,text,text)';

test('r556 attaches a board email and shows a blue Parts ETA warning', () => {
  assert.match(up, /Approved go-live/);
  assert.doesNotMatch(up, /PREVIEW/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /Pin count stays 241/);
  assert.match(up, /13057027/);
  assert.match(up, /true, 331, 'r556'/);
  assert.match(up, /ef3bd3587978f25862546483913231e4/);
  assert.match(up, /waiting_parts/);
  assert.match(up, /parts_eta/);
  assert.match(up, /job_card_problem/);
  assert.match(up, /ON CONFLICT \(source_email_id\) WHERE source_email_id IS NOT NULL/);
  assert.match(up, /parts_status_changed/);
  assert.match(writer, /service_role/);
  assert.match(writer, /management_connection\(\)/);
  assert.doesNotMatch(writer, /INSERT INTO public\.vehicles/);
  assert.doesNotMatch(writer, /INSERT INTO public\.workshop_bookings/);
  assert.doesNotMatch(writer, /vehicle_parts_updates/);
  assert.match(check, new RegExp(`pg_catalog\\.to_regprocedure\\('${signature.replace(/[().]/g, '\\$&')}'\\)`));
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.list_vehicle_email_notes_556\(uuid\)'\)/);
  assert.match(check, /LIKE '%is_pdc_role\(''operator''::public\.pdc_role\)%'/);
  assert.match(check, /LIKE '%is_pdc_role\(''administrator''::public\.pdc_role\)%'/);
  assert.match(check, /13057027/);
  assert.match(check, /fbafc3cd-09ff-414d-a29a-60529c0d3fca/);
  assert.match(check, /parts_received/);
  assert.doesNotMatch(check, /::(?:pg_catalog\.)?regprocedure/);
  assert.match(check, /AS ok/);
  assert.match(check, /AS detail/);
  assert.doesNotMatch(check, /expected_function_md5\s*\)\s*(=|<>|!=)\s*[0-9]+/i);
  assert.equal((up.match(/\$note556\$/g) || []).length, 2);
  assert.equal((up.match(/\$chk556\$/g) || []).length, 2);
  assert.equal((up.match(/\$list556\$/g) || []).length, 2);
  assert.equal(scanSql(up).length, 0);
  assert.match(down, /structured_data->>'source' = 'email_note_556'/);
  assert.match(down, /record_pdc_vehicle_email_556\(text, uuid, text, text, text, timestamp with time zone, text, text, text, text, text\)/);
  assert.match(down, /append_vehicle_email_note_556/);
  assert.equal(scanSql(down).length, 0);
  assert.match(app, /list_vehicle_email_notes_556/);
  assert.match(app, /function vehicleEmailNotesVisible/);
  assert.match(app, /function vehicleEmailWarningHtml/);
  assert.match(app, /data-vehicle-email-warnings/);
  assert.match(app, /vehicle-email-warning-kind">Email/);
  assert.match(app, /Still waiting on parts/);
  assert.doesNotMatch(app, /append_vehicle_email_note_556/);
  assert.doesNotMatch(app, /record_pdc_vehicle_email_556/);
  assert.match(css, /#e0f2fe/);
  assert.match(css, /#0c4a6e/);
  assert.match(css, /#0284c7/);
  assert.doesNotMatch(css, /#f59e0b|#d97706|#92400e|#fef3c7|#f97316|#ea580c|#b45309|#fff7ed/i);
  assert.match(up, /clear_pdc_vehicle_email_556\(text\)/);
  assert.match(up, /list_pdc_vehicle_email_warnings_556\(text\)/);
  assert.match(up, /apply_pdc_vehicle_email_batch_556\(jsonb\)/);
  assert.match(up, /v\.stock_number = stock_token/);
  const batch = up.slice(up.indexOf('$batch556$'), up.lastIndexOf('$batch556$'));
  assert.match(batch, /n := jsonb_array_length\(p_items\)/);
  assert.match(batch, /IF n > 100 THEN/);
  assert.doesNotMatch(batch, /jsonb_array_length\(p_items\) > 100/);
  assert.match(check, /LIKE '%jsonb_array_length\(p_items\)%'/);
  assert.match(check, /LIKE '%n > 100%'/);
  assert.match(check, /public\.vehicle_email_batch_limit_probe_556\(\)/);
  assert.doesNotMatch(check, /jsonb_array_length\(p_items\) > 100/);
  assert.equal((up.match(/\$probe556\$/g) || []).length, 2);
  assert.match(down, /vehicle_email_batch_limit_probe_556/);
  assert.match(up, /key_number/);
  assert.match(up, /Prado%/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.clear_pdc_vehicle_email_556\(text\)'\)/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.list_pdc_vehicle_email_warnings_556\(text\)'\)/);
  assert.match(check, /pg_catalog\.to_regprocedure\('public\.apply_pdc_vehicle_email_batch_556\(jsonb\)'\)/);
  assert.doesNotMatch(writer, /UPDATE public\.vehicles/);
  assert.doesNotMatch(writer, /current_location/);
  assert.equal((up.match(/\$clear556\$/g) || []).length, 2);
  assert.equal((up.match(/\$read556\$/g) || []).length, 2);
  assert.equal((up.match(/\$batch556\$/g) || []).length, 2);
  const clear = up.slice(up.indexOf('$clear556$'), up.lastIndexOf('$clear556$'));
  assert.match(clear, /UPDATE public\.vehicle_timeline_events/);
  assert.doesNotMatch(clear, /UPDATE public\.vehicles/);
  assert.doesNotMatch(clear, /workshop_bookings/);
  assert.match(down, /clear_pdc_vehicle_email_556\(text\)/);
  assert.match(down, /list_pdc_vehicle_email_warnings_556\(text\)/);
  assert.match(down, /apply_pdc_vehicle_email_batch_556\(jsonb\)/);
  assert.match(app, /Stoppage email/);
  assert.match(html, /r556=2026\.10\.26\.r556/);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('list_vehicle_email_notes_556'), false);
  assert.equal(fs.readFileSync('karratha/app.js', 'utf8').includes('record_pdc_vehicle_email_556'), false);
  assert.equal(fs.readFileSync('karratha/index.html', 'utf8').includes('r556=2026.10.26.r556'), false);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F170 \|/);
});

test('the 13057027 fixture row names the email and the parts-received conflict', () => {
  const start = app.indexOf('function vehicleEmailNoteWhen');
  const end = app.indexOf('function vehicleEmailPartsEtaHost');
  const context = {
    escapeHtml(value) {
      return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[char]));
    },
  };
  vm.runInNewContext(`${app.slice(start, end)}\nthis.vehicleEmailWarningHtml = vehicleEmailWarningHtml;`, context);
  const htmlRow = context.vehicleEmailWarningHtml({
    category: 'waiting_parts',
    sender_name: 'Talin Parker',
    sender_email: 'talin.parker@pmgwa.com.au',
    to_address: 'pdc@pmgwa.com.au',
    event_at: '2026-10-26T02:00:00Z',
    subject: 'Bull bar for 13057027',
    snippet: 'Still waiting on the bull bar, due this week.',
    conflicts: true,
  });
  assert.match(htmlRow, /Still waiting on parts/);
  assert.match(htmlRow, /Talin Parker &lt;talin.parker@pmgwa.com.au&gt;/);
  assert.match(htmlRow, /pdc@pmgwa.com.au/);
  assert.match(htmlRow, /Bull bar for 13057027/);
  assert.match(htmlRow, /Still waiting on the bull bar, due this week\./);
  assert.match(htmlRow, /parts are still waiting, and the board shows parts received/);
  assert.match(htmlRow, /26 Oct 2026/);
  const quiet = context.vehicleEmailWarningHtml({ category: 'po_received', conflicts: false, snippet: 'PO received', event_at: '2026-10-26T02:00:00Z' });
  assert.doesNotMatch(quiet, /disagrees with the board/);
});
