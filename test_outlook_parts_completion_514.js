/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r514 (F128): Outlook parts-complete confirmations for pdc@pmgwa.com.au. SQL only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261023140000_r514_outlook_parts_completion';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const CHECK = "CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))";
const MAIL = "CHECK (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]))";
const OLD_ID = "CHECK (gmail_message_id ~ '^[a-f0-9]{10,40}$')";
const OLD_MB = "CHECK (mailbox = 'pmbcontroller@gmail.com')";
const SAMPLE = '<01dd6288$Blat.v3.2.22$heldsvc@10.255.11.20>';
const GRAPH = 'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE9bAAA';
const PERSON = 'eb02f76ec94cd0b6c824a18660432afa';
const MARK = 'f5bdb212b439fd37adb73860c5e5d4d3';

function passes(id) {
  return /^[a-f0-9]+$/.test(id) || (id.length >= 8 && id.length <= 512 && !/[\s]/.test(id));
}

function bodyOk(stock, body, subject, outlook) {
  const b = body.toLowerCase().replace(/\s+/g, ' ').trim();
  const stockRe = stock.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const exact = new RegExp(`^(parts complete( for)? ${stockRe}|${stockRe} parts complete)[.!]?$`).test(b);
  const token = new RegExp(`(^|[^A-Za-z0-9])${stock.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^A-Za-z0-9]|$)`, 'i');
  const short = outlook && /^parts complete[.!]?$/.test(b) && token.test(subject || '');
  return exact || short;
}

test('migration files are LF only and do not name production', () => {
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.ok(!up.slice(0, 400).includes('Specialise Pty Ltd'));
  assert.ok(!down.slice(0, 400).includes('Specialise Pty Ltd'));
});

test('staging guard, release window, pin tip 225, role helper untouched', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.match(up, /expected 225 pins at tip/);
  assert.match(down, /pin count is not 225/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.is_pdc_role/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.record_pdc_wayne_parts_complete_20260912/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /UPDATE pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up.replace(/--[^\n]*/g, ''), /app\.js|pdc-qc-rework\.js/);
  assert.match(up, /39a794b23d1d63117cf549d78acba4de/);
});

test('widens only the public confirmation id and mailbox CHECKs', () => {
  assert.ok(up.includes(CHECK));
  assert.ok(up.includes(MAIL));
  assert.ok(down.includes(OLD_ID));
  assert.ok(down.includes(OLD_MB));
  assert.doesNotMatch(up, /ALTER TABLE karratha135/);
  assert.doesNotMatch(down, /ALTER TABLE karratha135/);
  assert.doesNotMatch(up, /ALTER TABLE pdc_codex_intake_private/);
  assert.doesNotMatch(up, /ALTER TABLE pdc_sales_private/);
  assert.match(down, /outside the old checks/);
  assert.equal(passes(SAMPLE), true);
  assert.equal(/^[a-f0-9]{10,40}$/.test(SAMPLE), false);
  assert.equal(SAMPLE.length, 44);
  assert.equal(passes(GRAPH), true);
  assert.equal(passes('1a158481917b7196'), true);
  assert.equal(passes('<id with space@10.255.11.20>'), false);
  assert.equal(passes('x'.repeat(513)), false);
  assert.equal(passes('Abcdef'), false);
});

test('person recorder accepts pdc@ and an IS stock; legacy gmail branch stays', () => {
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.record_pdc_person_parts_complete_20260913/);
  assert.ok(up.includes(PERSON));
  assert.match(up, /microsoft_receiving_provider/);
  assert.match(up, /internet_message_id/);
  assert.match(up, /IS\[0-9\]\{8\}/);
  assert.match(up, /pmbcontroller@gmail.com/);
  assert.match(up, /gmail_receiving_provider/);
  const subject = 'Vehicle To Service Purchase Order - Stock: IS60353006 P/O: GP10403460';
  assert.equal(bodyOk('IS60353006', 'Parts complete', subject, true), true);
  assert.equal(bodyOk('IS60353006', 'parts complete for IS60353006', 'x', true), true);
  assert.equal(bodyOk('IS60353006', 'Parts complete thanks', subject, true), false);
  assert.equal(bodyOk('IS60353006', 'Parts complete', 'Vehicle To Service Purchase Order', true), false);
  assert.equal(bodyOk('13000001', 'parts complete', 'Stock: 13000001', false), false);
  assert.equal(bodyOk('13000001', 'parts complete for 13000001', 'x', false), true);
});

test('mark stays operator-only except the management connection after a pdc@ confirmation', () => {
  assert.match(up, /CREATE OR REPLACE FUNCTION public\.mark_pdc_parts_complete/);
  assert.ok(up.includes(MARK));
  assert.match(up, /where public\.vehicle_work_items\.vehicle_id = excluded\.vehicle_id\s+and public\.vehicle_work_items\.work_key = excluded\.work_key/);
  assert.match(up, /management_connection\(\)/);
  assert.match(up, /require_pdc_role\('operator'\)/);
  assert.match(up, /GRANT EXECUTE ON FUNCTION public\.mark_pdc_parts_complete\(uuid,integer\) TO authenticated;/);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.mark_pdc_parts_complete\(uuid,integer\) FROM PUBLIC, anon, authenticated, service_role;/);
  assert.doesNotMatch(up, /GRANT EXECUTE ON FUNCTION public\.mark_pdc_parts_complete\(uuid,integer\) TO service_role/);
  assert.match(up, /77887b5450188a86acf0f0da34193e11/);
  assert.match(up, /82d890802677a2ac93942d3f7b7bcd27/);
  assert.match(down, /77887b5450188a86acf0f0da34193e11/);
  assert.match(down, /82d890802677a2ac93942d3f7b7bcd27/);
  assert.match(down, /DROP TABLE pdc_ops\.r514_parts_completion_prev/);
});

test('regression check outlook_parts_completion_514 sort 301 F128', () => {
  assert.match(up, /outlook_parts_completion_514','F128'/);
  assert.match(up, /,301,'r514'\)/);
  assert.match(up, /SELECT count\(\*\)=1 FROM def_id WHERE d LIKE/);
  assert.match(up, /outlook_sales_receipt_message_id_508/);
  assert.match(up, /outlook_manifest_message_id_506/);
  assert.match(up, /outlook_manifest_mailbox_507/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_parts_completion_514'/);
  assert.match(log, /\| F128 \|/);
  assert.ok(log.includes('pdc@pmgwa.com.au'));
  assert.ok(log.includes('IS60353006'));
});
