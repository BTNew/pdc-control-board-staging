/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r505 (F118): accept Revolution PMB reports via Outlook on pdc@pmgwa.com.au; Gmail path unchanged.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cp = require('node:child_process');
const crypto = require('node:crypto');

const ID = '20261023091500_r505_outlook_pdc_mailbox';
const MIG = `supabase/migrations/${ID}.sql`;
const DOWN = `supabase/rollbacks/${ID}.down.sql`;
const up = fs.readFileSync(MIG, 'utf8');
const down = fs.readFileSync(DOWN, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const md5 = (s) => crypto.createHash('md5').update(s, 'utf8').digest('hex');

const TIP = {
  auth: '6c1a612f6ed82dfcbf5788c17d2e5d87',
  parts: '986b89b3ca9180765fdc3f70bb7b49d5',
  k135: '2f478c0f84a18f250805a3b9b1a40955',
  rows: 'b5e3ab4517bd59a1931509a2b9a1299f',
  sales: 'ee577536b060c7447e1a4ff352250b79',
  manifest: '63ff5dabf94abcdf7c278fb3afa9bd96',
};
const AFTER = {
  auth: '4df79e85792a93bbac4e484d7a2b82f3',
  parts: 'ccf492618ca11625470b691fbe029ac7',
  k135: 'b8b37ceab1d1297a6e13709cd68bc243',
  rows: '5807a896cef15f81030f84a1b68a597b',
  sales: '46d4b464c5c1800c8ada245fb2d33bd3',
};
const AFTER_DEF = {
  auth: '726bf5dfc8dffaa4add2e087185e9ac1',
  parts: '2868827fe333373debf7b40194f5d46c',
  k135: '93281316c340c4183c6c1c9385581ea2',
  rows: '9e3c016f33d61e5545839106f23b3bf8',
  sales: '0225509ce53754461cce5115c351abe6',
};

test('migration files are LF only (CRLF bodies rebuilt with chr(13) in SQL)', () => {
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
});

test('staging only, release window, never names production', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.match(up, /expected 210 pins at tip/);
});

test('tip and after prosrc md5s pinned; auth/rows/sales updated; parts+k135 inserted', () => {
  for (const [k, v] of Object.entries(TIP)) {
    if (k === 'manifest') {
      assert.ok(up.includes(v), `manifest tip ${v}`);
      continue;
    }
    assert.ok(up.includes(`'${v}'`) || up.includes(v), `tip ${k} ${v}`);
  }
  for (const [k, v] of Object.entries(AFTER)) {
    assert.ok(up.includes(v), `after ${k} ${v}`);
    assert.ok(down.includes(v), `after ${k} in down`);
  }
  for (const v of Object.values(AFTER_DEF)) assert.ok(up.includes(v), `after def ${v}`);
  assert.match(up, /INSERT INTO pdc_ops\.expected_function_md5[\s\S]*pdc_import_job_parts_csv_20260912/);
  assert.match(up, /INSERT INTO pdc_ops\.expected_function_md5[\s\S]*revolution_csv_contract_20261007/);
  assert.match(up, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5='4df79e85792a93bbac4e484d7a2b82f3'/);
});

test('Outlook path fields present; Gmail path kept', () => {
  assert.match(up, /microsoft_receiving_provider/);
  assert.match(up, /mx\[\.\]microsoft\[\.\]com/);
  assert.match(up, /internet_message_id/);
  assert.match(up, /outlook_message_id/);
  assert.match(up, /microsoft_message_id/);
  assert.match(up, /pdc@pmgwa\.com\.au/);
  assert.match(up, /gmail_receiving_provider/);
  assert.match(up, /mx\[\.\]google\[\.\]com/);
  assert.match(up, /pmbcontroller@gmail\.com/);
  assert.match(up, /noreply@revolutionsoftware\.com\.au/);
});

test('callers widened: parts, k135, rows, sales; manifest unchanged', () => {
  assert.match(up, /pdc_import_job_parts_csv_20260912/);
  assert.match(up, /revolution_csv_contract_20261007/);
  assert.match(up, /revolution_service_rows_20261006/);
  assert.match(up, /import_sales_accessories_20261020/);
  assert.match(up, /service manifest tip mismatch \(must stay unchanged\)/);
  assert.match(up, /chr\(13\)/); // CRLF rebuild for parts/k135
});

test('regression check outlook_pdc_auth_505 F118 sort 290; keeps r484 check', () => {
  assert.match(up, /\('outlook_pdc_auth_505','F118'/);
  assert.match(up, /,true,290,'r505'\)/);
  assert.match(up, /parts_auth_pdc_mailbox_484/);
  assert.match(up, /count\(\*\)=17/);
});

test('undo restores tip md5s, drops r505 pins/check, restores prior releases', () => {
  for (const v of Object.values(TIP)) {
    if (v === TIP.manifest) continue;
    assert.ok(down.includes(v), `tip ${v} in down`);
  }
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='outlook_pdc_auth_505'/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r505'/);
  assert.match(down, /release='r484'/);
  assert.match(down, /release='r479'/);
  assert.match(down, /release='r396'/);
});

test('FAULT_LOG has F118', () => {
  assert.match(log, /\| F118 \|/);
  assert.match(log, /r505/);
  assert.match(log, /outlook_pdc_auth_505/);
  assert.match(log, /microsoft_receiving_provider/);
  assert.match(log, /pdc@pmgwa\.com\.au/);
});

test('docs mention Outlook path', () => {
  const parts = fs.readFileSync('docs/revolution-parts-email.md', 'utf8');
  const svc = fs.readFileSync('docs/revolution-service-email.md', 'utf8');
  assert.match(parts, /## r505 \(F118\)/);
  assert.match(parts, /microsoft_receiving_provider/);
  assert.match(svc, /## r505 \(F118\)/);
});

test('no locked frontend files touched by this release tree', () => {
  // Static: migration must not mention app.js / pdc-qc-rework.js as change targets
  assert.doesNotMatch(up + down, /app\.js|pdc-qc-rework\.js/);
});

function localPg() {
  try {
    cp.execSync("sudo -n -u postgres psql -Atc 'select 1'", { stdio: 'pipe', timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

test(
  'local PostgreSQL: auth after-md5 + 17-case matrix + held Outlook ids',
  { skip: !localPg() && 'no local PostgreSQL' },
  () => {
    const authDef = up.slice(up.indexOf('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_parts_authenticated_20261006'), up.indexOf(';\n\n-- 2. Service rows'));
    assert.ok(authDef.includes('AS $function$'));
    const sql = `
CREATE SCHEMA IF NOT EXISTS pdc_codex_intake_private;
DROP FUNCTION IF EXISTS pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text);
${authDef};
SELECT md5(prosrc), md5(pg_get_functiondef(oid)) FROM pg_proc
 WHERE oid=to_regprocedure('pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)');
`;
    const out = cp.execSync('sudo -n -u postgres psql -v ON_ERROR_STOP=1 -At', {
      input: sql,
      encoding: 'utf8',
      timeout: 30000,
    });
    assert.match(out, new RegExp(`${AFTER.auth}\\|${AFTER_DEF.auth}`));
    const cases = cp.execSync('sudo -n -u postgres psql -v ON_ERROR_STOP=1 -At', {
      input: fs.readFileSync('tests/r505_local_harness/cases.sql', 'utf8'),
      encoding: 'utf8',
      timeout: 30000,
    });
    assert.match(cases, /passed\|17\|17/);
  }
);
