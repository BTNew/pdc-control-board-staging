/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r508 (F121): widen the sales receipt message-id CHECK for Outlook ids. SQL only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261023113000_r508_sales_receipt_message_id';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const CHECK = "CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))";
const OLD = "CHECK (gmail_message_id ~ '^[A-Za-z0-9_-]{6,128}$')";
const SAMPLE = '<01dd628d$Blat.v3.2.22$f9cc539a$17dcc6c7327e@10.255.11.20>';
const GRAPH = 'AAkALgAAAAAAHYQDEapmEc2byACqAC-EWg0A6DV6RczCcUaqHebcM_EZMgAAAAE9bAAA';
const MANUAL = 'manual-chat-upload-01M5C2FJ6HM3QGXXQXKVHG8G5C';

function passes(id) {
  return /^[a-f0-9]+$/.test(id) || (id.length >= 8 && id.length <= 512 && !/[\s]/.test(id));
}

test('migration files are LF only and do not name production', () => {
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.ok(!up.slice(0, 400).includes('Specialise Pty Ltd'));
  assert.ok(!down.slice(0, 400).includes('Specialise Pty Ltd'));
});

test('staging guard, release window, pin tip 212, no function rewrite', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.match(up, /expected 212 pins at tip/);
  assert.match(down, /pin count is not 212/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION/);
  assert.doesNotMatch(down, /CREATE OR REPLACE FUNCTION/);
  assert.doesNotMatch(up.replace(/--[^\n]*/g, ''), /app\.js|pdc-qc-rework\.js/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.doesNotMatch(up, /UPDATE pdc_ops\.expected_function_md5/);
});

test('widens only the sales receipt message-id CHECK; other intake CHECKs stay', () => {
  assert.ok(up.includes(CHECK), 'up writes the widened CHECK');
  assert.deepEqual(up.match(/ALTER TABLE [^\n]+/g), [
    'ALTER TABLE pdc_sales_private.sales_accessory_receipts',
    'ALTER TABLE pdc_sales_private.sales_accessory_receipts',
  ]);
  assert.deepEqual(down.match(/ALTER TABLE [^\n]+/g), [
    'ALTER TABLE pdc_sales_private.sales_accessory_receipts',
    'ALTER TABLE pdc_sales_private.sales_accessory_receipts',
  ]);
  assert.doesNotMatch(up, /ALTER TABLE karratha135_intake/);
  assert.doesNotMatch(down, /ALTER TABLE karratha135_intake/);
  assert.doesNotMatch(up, /ALTER TABLE pdc_codex_intake_private/);
  assert.doesNotMatch(up, /ALTER TABLE public\.pdc_parts_completion_email_confirmations/);
  assert.doesNotMatch(up, /ALTER TABLE pdc_parts_private/);
  assert.ok(down.includes(OLD));
  assert.match(down, /outside the old pattern/);
  assert.ok(up.includes(SAMPLE));
  assert.equal(SAMPLE.length, 58);
  assert.equal(passes(SAMPLE), true);
  assert.equal(/^[A-Za-z0-9_-]{6,128}$/.test(SAMPLE), false);
  assert.equal(passes(GRAPH), true);
  assert.equal(GRAPH.length, 68);
  assert.equal(passes(MANUAL), true);
  assert.equal(passes('Abcdef'), false);
  assert.equal(/^[A-Za-z0-9_-]{6,128}$/.test('Abcdef'), true);
  assert.ok(!/\s/.test(SAMPLE));
  const addAt = up.indexOf('ADD CONSTRAINT sales_accessory_receipts_gmail_message_id_check');
  const addEnd = up.indexOf(';', addAt);
  assert.ok(addAt > 0 && addEnd > addAt);
  assert.equal(up.slice(addAt, addEnd).includes('[A-Za-z0-9_-]{6,128}'), false);
  assert.ok(up.slice(addAt, addEnd).includes(CHECK));
});

test('regression check outlook_sales_receipt_message_id_508 sort 293 F121; prior outlook checks re-run', () => {
  assert.match(up, /outlook_sales_receipt_message_id_508','F121'/);
  assert.match(up, /,293,'r508'\)/);
  assert.match(up, /SELECT count\(\*\)=1 FROM def WHERE d LIKE/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND d LIKE[\s\S]*FROM def\)/);
  assert.match(up, /46d4b464c5c1800c8ada245fb2d33bd3/);
  assert.match(up, /outlook_manifest_message_id_506/);
  assert.match(up, /outlook_manifest_mailbox_507/);
  assert.match(up, /outlook_pdc_auth_505/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_sales_receipt_message_id_508'/);
  assert.match(log, /\| F121 \|/);
  assert.ok(log.indexOf('| F120 |') < log.indexOf('| F121 |'));
});
