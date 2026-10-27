/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r572 (F186) / sort 342. Several 138/139 job cards on one vehicle stay on that
// vehicle. A new card is an insert, not a quarantine. 80/99 closes that card only.
// Department 135 stays frozen. Pin count stays 241. r563 / F177 / sort 336 is the
// live arrival age and is not reused. r571 / F185 / sort 343 stays unused.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml');
const R = p => fs.readFileSync(path.join(__dirname, p), 'utf8');
const MIG = 'supabase/migrations/20261027160000_r563_service_card_stack.sql';
const DOWN = 'supabase/rollbacks/20261027160000_r563_service_card_stack.down.sql';
const mig = R(MIG), down = R(DOWN);
const PREVIEW_OLD = '375bffc2dced95a7a5c74c3273dbccb3', PREVIEW_NEW = 'ea9a62537a146f05a01e866c636d367b';
const ROWS = '9be0883b1a555f48f3c1ba9fa111c891';
const RECONCILE = 'f4470aaa28afeb5a89fa206edb8a6076';
const KARRATHA_PREVIEW = '0d9db547209fd0b7c5843ebdb5e6486f';
const KARRATHA_CAPTURE = '3fca9ba755a6d30f9b6ac642da084b9b';
const KARRATHA_FINISH = 'f4480286dba918f82061bd6daffb4d43';
const KARRATHA_PMB = 'fbc4f46f10b8581feca8742da2c5ab98';
const UP_MD5 = '423cb9964a114ebb56b41e714035f74d', DOWN_MD5 = '85d12fc07aecc156ccb173ee23ae05f4';

test('migration is guarded, LF only, and does not pin or write vehicles', () => {
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
  assert.match(mig, /r572: staging only/);
  assert.match(mig, /pin count is not 241/);
  assert.match(mig, /service_whole_archive_570/);
  assert.match(mig, /parent r570 \/ F184 sort 341 is not applied/);
  assert.match(mig, /check_name='pmb_arrival_age_563' AND fault_id='F177' AND sort_order=336 AND added_in='r563'/);
  assert.match(mig, /sort_order=342 OR fault_id='F186'/);
  assert.doesNotMatch(mig, /sort_order=336 OR fault_id='F177'/);
  assert.doesNotMatch(mig, /::regprocedure/);
  assert.doesNotMatch(mig, /UPDATE public\.vehicles/);
  assert.doesNotMatch(mig, /workshop_bookings/);
  // The only mentions are the department 135 freeze checks. There is no patch
  // and no call, so 80/99 does not write through finish_tune_checkout.
  assert.equal((mig.match(/finish_tune_checkout/g) || []).length, 2);
  assert.equal((mig.match(/karratha135_intake' AND p\.proname='finish_tune_checkout'/g) || []).length, 2);
  assert.doesNotMatch(mig, /CREATE[\s\S]{0,120}finish_tune_checkout|PERFORM[\s\S]{0,40}finish_tune_checkout|public\.finish_tune_checkout/);
  assert.doesNotMatch(mig, /lifecycle_state=/);
  for (const token of [PREVIEW_OLD, PREVIEW_NEW, ROWS, RECONCILE, KARRATHA_PREVIEW, KARRATHA_CAPTURE, KARRATHA_FINISH, KARRATHA_PMB]) assert.ok(mig.includes(token), token);
  assert.match(mig, /service_card_attach_563/);
  assert.match(mig, /open_card_lines_missing_on_board|service_card_reconcile_flag_563/);
  assert.match(mig, /'service_card_stack_572','F186'/);
  assert.match(mig, /::pg_catalog\.text AS detail;/);
  assert.match(mig, /342, 'r572'/);
  assert.match(mig, /pins\.n FROM \(SELECT count\(\*\) AS n FROM pdc_ops\.expected_function_md5\) pins\)=241/);
  assert.doesNotMatch(mig, /expected_function_md5\)=241/);
  assert.match(down, /375bffc2dced95a7a5c74c3273dbccb3/);
  assert.match(down, /DROP FUNCTION pdc_codex_intake_private\.service_card_group_563/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='service_card_stack_572'/);
  assert.doesNotMatch(down, /fault_id='F177'/);
  assert.doesNotMatch(down, /added_in='r563'/);
  assert.doesNotMatch(down, /sort_order=336/);
});

test('named cards, a held card, and 80/99 on one card', () => {
  for (const stock of ['12710970', 'U158851', '13107437']) assert.ok(mig.includes(stock), stock);
  assert.match(mig, /owner_hold/);
  assert.match(mig, /close_vehicle/);
  assert.match(mig, /auto_close', false/);
  assert.match(mig, /dept_135|department 135/);
});

test('Python card rules pass and identity_r479 is not edited', () => {
  const whole = R('tools/import-rules/revolution_service_whole.py');
  assert.doesNotMatch(whole, /\b12710970\b/);
  assert.doesNotMatch(whole, /\bU158851\b/);
  assert.equal(whole.includes('IDENTITY_RULE'), true);
  const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
  const r = spawnSync(python, ['-m', 'unittest', 'test_revolution_service_cards'], { cwd: path.join(__dirname, 'tools/import-rules'), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
});

test('fault log F186 and the service doc name this release', () => {
  const fl = R('docs/FAULT_LOG.md');
  const doc = R('docs/revolution-service-email.md');
  assert.match(fl, /\| F186 \|/);
  assert.ok(fl.includes(UP_MD5) && fl.includes(DOWN_MD5) && fl.includes(PREVIEW_NEW));
  assert.match(doc, /## r572 \(F186\): several 138 and 139 job cards on one vehicle/);
  assert.ok(doc.includes(PREVIEW_NEW) && doc.includes('e63ab50a2220ad106f10a1a099683d0db5de4a4d74ad8eb5b494d39090ff158c'));
});
