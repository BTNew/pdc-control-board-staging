/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r570 (F184) / sort 341. The latest sheet is the active 138/139 list.
// A new card stays in the New vehicle section. A 138/139 board vehicle absent from
// the sheet is archived off the PMB board. Broome Toyota Sales (37047) and Karratha
// Sales (14450) are not written. Department 135 stays frozen. Pin count stays 241.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml');
const R = p => fs.readFileSync(path.join(__dirname, p), 'utf8');
const MIG = 'supabase/migrations/20261027220000_r569_service_whole_archive.sql';
const DOWN = 'supabase/rollbacks/20261027220000_r569_service_whole_archive.down.sql';
const mig = R(MIG), down = R(DOWN);
const ROWS_OLD = '5807a896cef15f81030f84a1b68a597b', ROWS_NEW = '9be0883b1a555f48f3c1ba9fa111c891';
const APPLY_OLD = 'fc3717a5215de94c93ebb2c7facfe744', APPLY_NEW = 'b62fb7c29ffd2a1629f214f696e5cb14';
const CAPTURE = '7870d544117de6a5465b8212f0d228b7';
const FINISH = '3e5c6b28e7c025a6ebbae61879ff3a82';
const PMB = '9808feb2a0a93a79b0d67aebdca0a4aa';
const KARRATHA = 'a033c7d7719ae588e8a9aa1b26bf2fbf';
const KARRATHA_CAPTURE = '3fca9ba755a6d30f9b6ac642da084b9b';
const KARRATHA_FINISH = 'f4480286dba918f82061bd6daffb4d43';
const KARRATHA_PMB = 'fbc4f46f10b8581feca8742da2c5ab98';
const UP_MD5 = '016d5af6dd1feeeade5071723084ac78', DOWN_MD5 = '00dbbbdb4234cf0cb2fcad7c8c411652';
const RETIRED_PINS = ['51cb7e1dbe842ba00f4259dfe3f42cce', 'a3cd014a46d9cac7512f3c853ac1a5a4', '5822588a7d3fed675a83b21909e41e48', '196d0fe24813802a4ad72b0e2c39f4da'];

function between(src, startMark, endMark) {
  const start = src.indexOf(startMark);
  const end = src.indexOf(endMark);
  assert.ok(start >= 0 && end > start, startMark);
  return src.slice(start, end);
}

test('migration is guarded, LF only, and pins only rows and apply', () => {
  const raw = fs.readFileSync(path.join(__dirname, MIG));
  assert.equal(raw.includes(13), false, 'no CR byte in the migration');
  assert.equal(fs.readFileSync(path.join(__dirname, DOWN)).includes(13), false, 'no CR byte in the rollback');
  assert.equal(crypto.createHash('md5').update(raw).digest('hex'), UP_MD5);
  assert.equal(crypto.createHash('md5').update(fs.readFileSync(path.join(__dirname, DOWN))).digest('hex'), DOWN_MD5);
  assert.equal(scanSql(mig).length, 0);
  assert.equal(scanSql(down).length, 0);
  assert.match(mig, /SET LOCAL lock_timeout = '2s';/);
  assert.match(mig, /NOT BETWEEN 2 AND 45/);
  assert.match(mig, /cdsmnqxtyyoeoznmbidd/);
  assert.match(mig, /r570: staging only/);
  assert.match(mig, /pin count is not 241/);
  assert.match(mig, /check_name='pmb_key_gate_562' AND fault_id='F176' AND sort_order=335 AND added_in='r562'/);
  assert.match(mig, /check_name='parts_stoppage_manual_567' AND fault_id='F181' AND sort_order=338/);
  assert.match(mig, /check_name='bay_job_pause_569' AND fault_id='F183' AND sort_order=340 AND added_in='r569'/);
  assert.match(mig, /sort_order=341 OR fault_id='F184' OR check_name='service_whole_archive_570'/);
  assert.match(mig, /does not treat r562 \/ F176 \/ sort 335 as free/);
  assert.doesNotMatch(mig, /sort 335, F176 and r562 were free/);
  for (const m of [ROWS_OLD, ROWS_NEW, APPLY_OLD, APPLY_NEW, CAPTURE, FINISH, PMB, KARRATHA, KARRATHA_CAPTURE, KARRATHA_FINISH, KARRATHA_PMB]) {
    assert.ok(mig.includes(m), m);
  }
  assert.ok(mig.includes(`SET prosrc_md5='${ROWS_NEW}', release='r570'`));
  assert.ok(mig.includes(`SET prosrc_md5='${APPLY_NEW}', release='r570'`));
  assert.equal((mig.match(/SET prosrc_md5=/g) || []).length, 2);
  for (const retired of RETIRED_PINS) assert.equal(mig.includes(retired), false, retired);
  assert.match(mig, /count\(\*\) FROM pdc_ops\.expected_function_md5\)<>241/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.pdc_pilbara_service_preview_v1/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION karratha135_pdc\./);
  assert.doesNotMatch(mig, /::regprocedure/);
  assert.match(mig, /to_regprocedure/);
});

test('both creates stay in the New vehicle section and there is no QC step', () => {
  assert.match(mig, /new_board_vehicle/);
  assert.match(mig, /create_division/);
  assert.match(mig, /create_new_vehicle/);
  assert.match(mig, /dealer 14450 must not enter Broome Sales/);
  assert.match(mig, /a new as-a-Whole vehicle stays in the New vehicle section/);
  assert.match(mig, /service_whole_archive_569\(v_preview\.batch_id,v_apply_batch\)/);
  assert.doesNotMatch(mig, /was not placed on New to PMB/);
  assert.doesNotMatch(mig, /current_location='QC'/);
  assert.doesNotMatch(mig, /filtered_create_advisor_file/);
  for (const name of ['service_whole_qc_absent', 'service_whole_open_job_card', 'service_whole_missing_card', 'service_whole_qc_sheet']) {
    assert.equal(mig.includes(name), false, name);
  }
});

test('the archive body does not write Broome Sales or Karratha Sales', () => {
  const archive = between(
    mig,
    'CREATE FUNCTION pdc_codex_intake_private.service_whole_archive_569',
    'CREATE FUNCTION pdc_codex_intake_private.service_whole_unarchive_569');
  for (const banned of [
    'pdc_sales_private',
    'UPDATE public.navision_backend_records',
    'karratha135',
    'DELETE FROM public.vehicles',
    'DELETE FROM public.workshop_bookings',
  ]) assert.equal(archive.includes(banned), false, banned);
  assert.ok(archive.includes('sales_write'));
  assert.ok(archive.includes('37047'));
  assert.ok(archive.includes('14450'));
  assert.ok(archive.includes("dealer_code IN ('37047','037047','14450','014450')"));
  assert.match(mig, /p_on_sales_board does not block the PMB archive/);
  assert.match(mig, /'sales_write',false,'hide_sales',false/);
  // The division create still links the one Navision row. That write is outside the archive body.
  assert.ok(mig.includes('UPDATE public.navision_backend_records'));
  assert.match(mig, /service_whole_unarchive_569\(p_vehicle uuid\)/);
  assert.match(mig, /Broome Toyota Sales \(37047\) and Karratha Sales \(14450\)/);
});

test('check is F184 sort 341 and is safe under search_path pg_catalog', () => {
  assert.match(mig, /'service_whole_archive_570', 'F184'/);
  assert.match(mig, /true, 341, 'r570'/);
  assert.match(mig, /SYN0001/);
  assert.match(mig, /SYN14450/);
  assert.match(mig, /AS ok/);
  assert.match(mig, /AS detail/);
  assert.match(mig, /::pg_catalog\.text/);
  assert.match(mig, /set_config\('search_path','pg_catalog',true\)/);
  assert.doesNotMatch(mig, /::regprocedure/);
  assert.match(mig, /NOT EXISTS \(SELECT 1 FROM pdc_ops\.expected_function_md5 WHERE signature LIKE '%service_whole%569%'\)/);
  assert.match(mig, /strpos\(p\.prosrc, 'pdc_sales_private'\)=0/);
  assert.match(mig, /strpos\(p\.prosrc, 'UPDATE public\.navision_backend_records'\)=0/);
});

test('rollback restores the rows and apply pins only', () => {
  assert.ok(down.includes(`SET prosrc_md5='${ROWS_OLD}', release='r505'`));
  assert.ok(down.includes(`SET prosrc_md5='${APPLY_OLD}', release='r442'`));
  assert.ok(down.includes(`AND prosrc_md5='${APPLY_NEW}' AND release='r570'`));
  assert.doesNotMatch(down, /fault_id='F183'/);
  assert.doesNotMatch(down, /added_in='r569'/);
  assert.doesNotMatch(down, /sort_order=340/);
  assert.doesNotMatch(down, /sort_order=342/);
  assert.equal((down.match(/SET prosrc_md5=/g) || []).length, 2);
  assert.match(down, /mailbox pdc@pmgwa.com.au allowed/);
  assert.match(down, /service apply feeds sublet POs/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='service_whole_archive_570'/);
  for (const f of [
    'service_whole_archive_569(uuid,uuid)',
    'service_whole_unarchive_569(uuid)',
    'service_whole_direct_board_569(uuid,text)',
    'service_whole_archive_decision_569(boolean,boolean,boolean,boolean,boolean)',
    'service_whole_file_guard_569(integer,integer,boolean,integer,text,text)',
    'service_whole_board_decision_569(text,boolean,text,integer,text,boolean,boolean)',
  ]) assert.match(down, new RegExp('DROP FUNCTION IF EXISTS pdc_codex_intake_private\\.' + f.replace(/[()]/g, '\\$&')));
  assert.match(down, /DROP TABLE IF EXISTS pdc_codex_intake_private\.service_whole_archive_receipt_569/);
  assert.ok(down.includes(CAPTURE) && down.includes(FINISH) && down.includes(PMB) && down.includes(KARRATHA));
  assert.match(down, /an r570 pin remains/);
  assert.match(down, /pin count changed/);
  for (const retired of RETIRED_PINS) assert.equal(down.includes(retired), false, retired);
  assert.doesNotMatch(down, /CREATE OR REPLACE FUNCTION karratha135_pdc\./);
  assert.doesNotMatch(down, /SET prosrc_md5='7870d544117de6a5465b8212f0d228b7'/);
});

test('fault log F184 and the as-a-Whole doc name this release', () => {
  const fl = R('docs/FAULT_LOG.md'), doc = R('docs/revolution-service-email.md');
  assert.match(fl, /\| F184 \|/);
  assert.match(fl, /service_whole_archive_570/);
  for (const m of [ROWS_OLD, ROWS_NEW, APPLY_OLD, APPLY_NEW, CAPTURE, FINISH, PMB, UP_MD5, DOWN_MD5, KARRATHA, KARRATHA_CAPTURE, KARRATHA_FINISH, KARRATHA_PMB, '37047', '14450']) {
    assert.ok(fl.includes(m), m);
  }
  assert.match(doc, /## r570 \(F184\): the latest sheet is the active 138 and 139 list/);
  assert.doesNotMatch(doc, /## r569 \(F183\)/);
  assert.doesNotMatch(doc, /## r562 \(F176\)/);
  assert.match(doc, /## Full open-R\/O snapshot: "PMG PD Service as a Whole w\/Sublet" — r479 \(F92\)/);
  assert.match(doc, /service_whole_unarchive_569/);
  assert.ok(doc.includes(UP_MD5) && doc.includes(DOWN_MD5) && doc.includes(APPLY_NEW));
});

test('Python: sales rows stay untouched, and the r479 preparer tests still pass', () => {
  const rules = R('tools/import-rules/revolution_service_whole.py');
  assert.doesNotMatch(rules, /\b1[0-9]{7}\b/);
  assert.match(rules, /def archive_decision/);
  assert.match(R('tools/import-rules/test_revolution_service_whole_569.py'), /test_sales_rows_stay_untouched_including_a_vehicle_on_both_boards/);
  const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
  const r = spawnSync(python, ['-m', 'unittest', 'test_revolution_service_whole_479', 'test_revolution_service_whole_569'],
    { cwd: path.join(__dirname, 'tools/import-rules'), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
});
