/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r479 (F92): 'PMG PD Service as a Whole w/Sublet' (full open-R/O snapshot). Checks the migration guards, the pins
// (schema-qualified literal signatures), that no board table is written, the rollback, that no real stock / R/O numbers
// are in Git, the fault log and docs, and runs the Python tests.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { spawnSync } = require('node:child_process');
const R = p => fs.readFileSync(path.join(__dirname, p), 'utf8');
const MIG = 'supabase/migrations/20261022043000_r479_service_whole_snapshot.sql';
const DOWN = 'supabase/rollbacks/20261022043000_r479_service_whole_snapshot.down.sql';
const mig = R(MIG), down = R(DOWN), sqlt = R('tests/service_whole_snapshot_479.sql'), t99 = R('tests/service_99_once_479.sql');
const py = R('tools/import-rules/revolution_service_whole.py'), t479 = R('tools/import-rules/test_revolution_service_whole_479.py');
const MD5 = { man_old: 'e4ba03437490bd155d4d8553285107f8', man_new: '63ff5dabf94abcdf7c278fb3afa9bd96', rows_old: '0534336e01558066cf7ec3dcb3995cd4',
  rows_new: 'b5e3ab4517bd59a1931509a2b9a1299f', key_old: '4b25c88071288d598d4ae29c50320d3b', key_new: '7db7b5482de592222cfc5828ff9e6a45',
  append_only: '1ab209a3fff8dbc2efe3051f17c42703', record: 'fe1aa81a9ff00b6071eb4c0b7ea1a4ab', reconcile: 'f4470aaa28afeb5a89fa206edb8a6076',
  review: 'a84de72c728027dcea5a2d9adb4c04ad', cap_old: '3cc871d85d84195d9f8f65113a03e1ef', cap_new: '7870d544117de6a5465b8212f0d228b7',
  used99: '574255e4c99e77830069f74ad849d9b4' };

test('migration: guarded (window, lock_timeout, staging, tick, check runner, preview, apply, headers, old md5s, pins, ACLs), once only', () => {
  assert.match(mig, /SET LOCAL lock_timeout = '2s';/);
  assert.match(mig, /NOT BETWEEN 2 AND 45/);
  for (const m of ['0aaaa15690ca286ed0db87fc72271d5a', 'fa4651cce7bb0fdb8985857779b62d93', '375bffc2dced95a7a5c74c3273dbccb3',
    'fc3717a5215de94c93ebb2c7facfe744', 'bfda8a3acd8a08bb36f5851ead2cd5e4', MD5.man_old, MD5.rows_old, MD5.key_old]) assert.ok(mig.includes(m), m);
  assert.match(mig, /e4ba03437490bd155d4d8553285107f8r442/); assert.match(mig, /0534336e01558066cf7ec3dcb3995cd4r444/);
  assert.match(mig, /\{postgres=X\/postgres\}/); assert.match(mig, /r479: staging only/);
  assert.match(mig, /r479: already applied/); assert.match(mig, /sort_order=279 OR fault_id='F92'/);
});
test('migration never touches the clock tick, preview, apply or any board table', () => {
  for (const f of ['workshop_clock_tick', 'pdc_pilbara_service_preview_v1', 'pdc_pilbara_service_apply_v1', 'revolution_service_headers_439'])
    assert.doesNotMatch(mig, new RegExp('CREATE OR REPLACE FUNCTION public\\.' + f + '|CREATE OR REPLACE FUNCTION pdc_codex_intake_private\\.' + f));
  // The only board writes are the existing ones inside the key import and capture_service_status bodies (as before r479).
  const W = /\b(DELETE FROM|UPDATE|INSERT INTO|TRUNCATE)\s+(public|pdc_parts_private)\.(vehicles|jobs|pdc_pilbara_service_operations|workshop_bookings)\b/gi;
  const outsideKey = s => s.replace(/CREATE OR REPLACE FUNCTION (public\.pdc_apply_tune_key_number_v1|pdc_codex_intake_private\.capture_service_status)[\s\S]*?\$f\$;/g, '');
  for (const s of [mig, down]) { assert.equal((s.match(W) || []).length, 2); assert.doesNotMatch(outsideKey(s), W); }
});
test('pins: manifest and rows move to r479, five new pins, every signature a schema-qualified literal', () => {
  assert.ok(mig.includes(`SET prosrc_md5='${MD5.man_new}',release='r479'`)); assert.ok(mig.includes(`SET prosrc_md5='${MD5.rows_new}',release='r479'`));
  for (const [sig, m] of [['public.pdc_apply_tune_key_number_v1(uuid,uuid,uuid)', MD5.key_new], ['pdc_service_snapshot_private.append_only_479()', MD5.append_only],
    ['pdc_service_snapshot_private.record_snapshot_479(jsonb,jsonb)', MD5.record], ['pdc_service_snapshot_private.reconcile_479(text)', MD5.reconcile],
    ['pdc_service_snapshot_private.review_list_479()', MD5.review], ['pdc_codex_intake_private.capture_service_status(uuid,uuid)', MD5.cap_new],
    ['pdc_codex_intake_private.service_99_used_479(uuid,text,text,text,text)', MD5.used99]]) assert.ok(mig.includes(`('${sig}','${m}','r479'`), sig);
  assert.match(mig, /WHERE release='r479'\)<>9 THEN/);
  const block = mig.slice(mig.indexOf('INSERT INTO pdc_ops.expected_function_md5'), mig.indexOf(';', mig.indexOf('INSERT INTO pdc_ops.expected_function_md5')));
  for (const s of block.match(/\('([^']+)','[0-9a-f]{32}'/g)) assert.match(s, /^\('(public|pdc_[a-z_]+)\.[a-z0-9_]+\([a-z,]*\)'/, s);
  assert.doesNotMatch(mig, /signature=(?!')/);
});
test('snapshot schema: private (RLS, revoked), append-only, undo only via pdc.r479_undo; reconcile read-only (STABLE)', () => {
  assert.match(mig, /CREATE SCHEMA pdc_service_snapshot_private/);
  assert.match(mig, /ENABLE ROW LEVEL SECURITY/); assert.match(mig, /REVOKE ALL ON SCHEMA pdc_service_snapshot_private FROM/);
  assert.match(mig, /pdc\.r479_prune/); assert.match(mig, /pdc\.r479_undo/);
  assert.match(mig, /reconcile_479\(p_sha text DEFAULT NULL\)[\s\S]{0,200}STABLE/);
  for (const c of ['open_ro_no_board_vehicle', 'ro_all_lines_80_99_still_open', 'board_vehicle_missing', 'board_ro_missing', '_pending']) assert.ok(mig.includes(c), c);
});
test('key import: as a Whole fills a blank board key only; w/Sublet unchanged', () => {
  assert.match(mig, /board_key_not_blank_r479/); assert.match(mig, /PMG PD Service as a Whole w\/Sublet/);
});
test('a Sub Status 99 checks a vehicle out once: capture keeps every old guard and skips 99s already used (receipt / before an owner reopen)', () => {
  const cap = mig.slice(mig.indexOf('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.capture_service_status'));
  const body = cap.slice(0, cap.indexOf('$f$;'));
  assert.ok(body.includes('tune_checkout_receipts prior WHERE prior.vehicle_id=v.id'));
  assert.ok(body.includes("pdc_codex_intake_private.service_99_used_479(v.id,v.stock_number,u.company,u.division,u.ro_number) IS NULL"));
  assert.ok(mig.includes(MD5.cap_old) && down.includes(MD5.cap_old) && down.includes(MD5.cap_new));
  for (const s of ["'checkout_receipt'", "'used_before_owner_reopen'", "owner_reopen_workshop_status", "ir.created_at<a.created_at"]) assert.ok(mig.includes(s), s);
  assert.match(mig, /REVOKE ALL ON FUNCTION pdc_codex_intake_private\.service_99_used_479\(uuid,text,text,text,text\) FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(down, /DROP FUNCTION pdc_codex_intake_private\.service_99_used_479\(uuid,text,text,text,text\);/);
  assert.match(mig, /'checkout_99_used'/); assert.match(mig, /AS checkout_99_once/);
  for (const f of ['FAIL 5', 'FAIL 6', 'FAIL 9', 'FAIL 11', 'owner_reopen_workshop_status', 'ROLLBACK;']) assert.ok(t99.includes(f), f);
});
test('line endings: migration and rollback are LF only; the rollback rebuilds the staging CRLF capture body with chr(13)', () => {
  // v2 (22 Oct): apply_migration over MCP / HTTP turns CRLF into LF, so v1's CRLF capture body landed with another md5.
  const raw = (p) => fs.readFileSync(path.join(__dirname, p));
  assert.equal(raw(MIG).includes(13), false, 'no CR byte in the migration');
  assert.equal(raw(DOWN).includes(13), false, 'no CR byte in the rollback');
  assert.match(down, /EXECUTE replace\(replace\(\$cap479\$CREATE OR REPLACE FUNCTION pdc_codex_intake_private\.capture_service_status\(/);
  assert.match(down, /\$cap479\$, chr\(13\), ''\), chr\(10\), chr\(13\)\|\|chr\(10\)\);/);
  assert.ok(!mig.includes('c306c07f2729b4962bb8859884bab181') && !down.includes('c306c07f2729b4962bb8859884bab181'));
});
test('daily check F92 sort 279; final block runs protected_function_md5s and both service checks with search_path pg_catalog', () => {
  assert.match(mig, /'service_whole_snapshot_479','F92'/); assert.match(mig, /279,'r479'/);
  for (const c of ['protected_function_md5s', 'service_whole_snapshot_479', 'service_wsublet_contract_and_po_feed']) assert.ok(mig.includes(`'${c}'`), c);
  assert.match(mig, /set_config\('search_path','pg_catalog',true\)/);
});
test('rollback: restores the three bodies and the r442 / r444 pins, deletes r479 pins and check, drops the schema, refuses with snapshots', () => {
  for (const m of [MD5.man_old, MD5.rows_old, MD5.key_old]) assert.ok(down.includes(m), m);
  assert.match(down, /release='r442'/); assert.match(down, /release='r444'/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE signature IN \('public\.pdc_apply_tune_key_number_v1\(uuid,uuid,uuid\)','pdc_service_snapshot_private\.append_only_479\(\)'/);
  assert.match(down, /DROP SCHEMA pdc_service_snapshot_private CASCADE/); assert.match(down, /discard_snapshots/);
  assert.match(down, /lock_timeout = '2s'/); assert.match(down, /NOT BETWEEN 2 AND 45/);
});
test('no real stock numbers, R/Os, vehicle ids or customer data in the r479 files', () => {
  // The only addresses allowed are the report sender / mailbox already in the r442 manifest (byte-for-byte body).
  const known = new Set(R('supabase/migrations/20261021073319_r442_service_wsublet.sql').match(/[A-Za-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]+/g) || []);
  for (const [n, s] of [['mig', mig], ['down', down], ['sqlt', sqlt], ['t99', t99], ['py', py], ['t479', t479], ['harness', R('tests/r479_local_harness/schema.sql')]]) {
    assert.doesNotMatch(s, /\b1[0-9]{7}\b/, n + ': stock-like number');
    assert.doesNotMatch(s, /\bJ13[89](?!999|900)[0-9]{6}\b/, n + ': real-looking R/O');
    for (const e of s.match(/[A-Za-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]+/g) || []) assert.ok(known.has(e) || e.endsWith('@pdc.invalid'), n + ': new email address');
  }
  assert.ok(!fs.existsSync(path.join(__dirname, 'open_jobcards.xlsx')));
});
test('fault log F92 and docs', () => {
  const fl = R('docs/FAULT_LOG.md'), doc = R('docs/revolution-service-email.md');
  assert.match(fl, /^\| F92 \| 22 Oct/m); assert.match(fl, /service_whole_snapshot_479/);
  assert.match(doc, /## Full open-R\/O snapshot: "PMG PD Service as a Whole w\/Sublet" — r479 \(F92\)/);
  for (const m of Object.values(MD5).filter(m => ![MD5.man_old, MD5.rows_old, MD5.key_old].includes(m))) assert.ok(doc.includes(m), m);
});
test('Python: r479 preparer tests and the w/Sublet 442 / 468 / 471 tests pass', () => {
  const python = process.env.PYTHON || (process.platform === 'win32' ? 'python' : 'python3');
  const r = spawnSync(python, ['-m', 'unittest', 'test_revolution_service_whole_479', 'test_revolution_service_wsublet',
    'test_revolution_service_wsublet_468', 'test_revolution_service_wsublet_471', 'test_revolution_service_create_advisor_509'], { cwd: path.join(__dirname, 'tools/import-rules'), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});
