/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r507 (F120): widen the service manifest mailbox CHECK for the Outlook envelope. SQL only. Not applied.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const ID = '20261023101000_r507_outlook_manifest_mailbox';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const CHECK = "CHECK (mailbox = ANY (ARRAY['pmbcontroller@gmail.com'::text, 'pdc@pmgwa.com.au'::text]))";
const OLD = "CHECK (mailbox = 'pmbcontroller@gmail.com')";

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

test('widens only the codex service manifest mailbox CHECK; Karratha 135 stays pmbcontroller-only', () => {
  assert.ok(up.includes(CHECK), 'up writes the widened CHECK');
  assert.match(up, /ALTER TABLE pdc_codex_intake_private\.management_email_manifests/);
  assert.doesNotMatch(up, /ALTER TABLE karratha135_intake\.management_email_manifests/);
  assert.doesNotMatch(down, /ALTER TABLE karratha135_intake\.management_email_manifests/);
  assert.match(up, /karratha135 mailbox CHECK changed/);
  assert.ok(down.includes(OLD));
  assert.match(down, /non-pmbcontroller/);
});

test('regression check outlook_manifest_mailbox_507 sort 292 F120 uses WHERE, and re-runs r505 and r506', () => {
  assert.match(up, /outlook_manifest_mailbox_507','F120'/);
  assert.match(up, /,292,'r507'\)/);
  assert.match(up, /SELECT count\(\*\)=1 FROM def WHERE d LIKE/);
  assert.match(up, /SELECT count\(\*\)=1 FROM k135 WHERE d LIKE/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND d LIKE[\s\S]*FROM def\)/);
  assert.doesNotMatch(up, /count\(\*\)=1 AND d LIKE[\s\S]*FROM k135\)/);
  assert.match(up, /outlook_manifest_message_id_506/);
  assert.match(up, /outlook_pdc_auth_505/);
  assert.match(up, /63ff5dabf94abcdf7c278fb3afa9bd96/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_manifest_mailbox_507'/);
  assert.match(log, /\| F120 \|/);
  assert.ok(log.indexOf('| F119 |') < log.indexOf('| F120 |'));
  assert.ok(!log.includes('| F121 |'));
});
