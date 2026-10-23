/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r506 (F119): widen the service manifest message-id CHECK for Outlook ids. SQL only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261023094500_r506_outlook_manifest_message_id';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const CHECK = "CHECK (gmail_message_id ~ '^[a-f0-9]+$' OR (length(gmail_message_id) BETWEEN 8 AND 512 AND gmail_message_id !~ '[[:space:]]'))";
const HEX = "CHECK (gmail_message_id ~ '^[a-f0-9]+$')";
const SAMPLE = '<01dd6288$Blat.v3.2.22$d55355b9$b9010b3753@10.255.11.20>';

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

test('widens only the codex service manifest CHECK; Karratha 135 stays hex-only', () => {
  assert.ok(up.includes(CHECK), 'up writes the widened CHECK');
  assert.match(up, /ALTER TABLE pdc_codex_intake_private\.management_email_manifests/);
  assert.doesNotMatch(up, /ALTER TABLE karratha135_intake\.management_email_manifests/);
  assert.doesNotMatch(down, /ALTER TABLE karratha135_intake\.management_email_manifests/);
  assert.match(up, /karratha135 manifest CHECK changed/);
  assert.ok(down.includes(HEX));
  assert.match(down, /non-hex/);
  assert.ok(up.includes(SAMPLE));
  assert.equal(SAMPLE.length, 56);
  assert.ok(!/\s/.test(SAMPLE));
  assert.ok(!/^[a-f0-9]+$/.test(SAMPLE));
});

test('regression check outlook_manifest_message_id_506 sort 291 F119; manifest function left alone', () => {
  assert.match(up, /outlook_manifest_message_id_506','F119'/);
  assert.match(up, /,291,'r506'\)/);
  assert.match(up, /SELECT count\(\*\)=1 FROM def WHERE d LIKE/);
  assert.match(up, /SELECT count\(\*\)=1 FROM k135 WHERE d LIKE/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND d LIKE[\s\S]*FROM def\)/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND d LIKE[\s\S]*FROM k135\)/);
  assert.match(up, /63ff5dabf94abcdf7c278fb3afa9bd96/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_manifest_message_id_506'/);
  assert.match(log, /\| F119 \|/);
  assert.ok(log.indexOf('| F118 |') < log.indexOf('| F119 |'));
  assert.ok(!log.includes('| F120 |'));
});
