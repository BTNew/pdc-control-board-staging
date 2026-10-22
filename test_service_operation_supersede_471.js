// r471 (F84): a service line re-sent with the bay / parts-location code appended ('X' -> 'X 05K4F') became a second
// immutable version of the same Dept + R/O + Line #, so the stock was held (ambiguous_existing_operation). r471 adds a
// private, append-only supersession record (with a tested undo), makes the change candidate ignore superseded versions,
// and makes the preparer keep the live description when only a trailing bay code differs. These tests check the files,
// the guards, the pins, that no real stock / R/O / operation ids are in Git, the fault log and docs, and run the Python tests.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { spawnSync } = require('node:child_process');
const R = p => fs.readFileSync(path.join(__dirname, p), 'utf8');
const MIG = 'supabase/migrations/20261022021500_r471_service_operation_supersede.sql';
const DOWN = 'supabase/rollbacks/20261022021500_r471_service_operation_supersede.down.sql';
const mig = R(MIG), down = R(DOWN), sqlt = R('tests/service_operation_supersede_471.sql');
const py = R('tools/import-rules/revolution_service_wsublet.py'), t471 = R('tools/import-rules/test_revolution_service_wsublet_471.py');

test('migration: guarded (window, staging, tick, check runner, candidate md5 + ACL, preview, apply, 772, QC lines), once only', () => {
  assert.match(mig, /SET LOCAL lock_timeout = '2s';/);
  assert.match(mig, /NOT BETWEEN 2 AND 45/);
  for (const m of ['0aaaa15690ca286ed0db87fc72271d5a', 'fa4651cce7bb0fdb8985857779b62d93', 'cc5dee40fa5a86fc1caa3704af318744',
    '375bffc2dced95a7a5c74c3273dbccb3', 'fc3717a5215de94c93ebb2c7facfe744', 'b47709fd384dd20db09ac96cc1b305c7', 'a93005010cf96ab6eb804ef879039861']) assert.ok(mig.includes(m), m);
  assert.match(mig, /r471: already applied/); assert.match(mig, /sort_order=270 OR fault_id='F84'/);
  assert.doesNotMatch(mig, /CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/);
  assert.doesNotMatch(mig, /\bDELETE FROM public\.(vehicles|jobs|pdc_pilbara_service_operations|workshop_bookings)\b/i);
  assert.doesNotMatch(mig, /\bUPDATE public\.(vehicles|jobs|pdc_pilbara_service_operations|workshop_bookings)\b/i);
});
test('supersession table: private (RLS, no grants), append-only, one row per retired version, undo only via pdc.r471_undo', () => {
  assert.match(mig, /CREATE TABLE public\.pdc_service_operation_supersessions_471/);
  assert.match(mig, /superseded_operation_id uuid PRIMARY KEY/);
  assert.match(mig, /ENABLE ROW LEVEL SECURITY/); assert.match(mig, /REVOKE ALL ON (TABLE )?public\.pdc_service_operation_supersessions_471 FROM/);
  assert.match(mig, /pdc\.r471_undo/); assert.match(mig, /BEFORE TRUNCATE ON public\.pdc_service_operation_supersessions_471/);
  assert.match(mig, /rule text NOT NULL CHECK \(rule IN \('owner_decision','trailing_bay_code_471'\)\)/);
});
test('supersede_operation_471 refuses anything it cannot prove: same line, kept version live, no work recorded, no live booking', () => {
  for (const s of ['not_the_same_line', 'invalid_input', 'staging only', 'pg_advisory_xact_lock', 'p_live_booking_ok boolean DEFAULT false'])
    assert.ok(mig.includes(s), s);
  assert.match(mig, /active=false/); assert.match(mig, /'manual_operator'/);
  assert.match(mig, /47100000-0000-5000-8000-000000000471/);
});
test('candidate: only change is ignoring superseded versions (count and select); pins at r471 (4); check F84 sort 270', () => {
  const body = mig.slice(mig.indexOf('CREATE OR REPLACE FUNCTION public.pdc_tune_operation_change_candidate_20260912'));
  assert.equal((body.slice(0, body.indexOf('$function$;') > 0 ? body.indexOf('$function$;') : body.length).match(/pdc_service_operation_supersessions_471 s WHERE s\.superseded_operation_id=o\.operation_id/g) || []).length, 2);
  assert.match(mig, /'ambiguous_existing_operation'/);
  assert.match(mig, /WHERE release='r471'\)<>4/);
  assert.doesNotMatch(mig, /oid::regprocedure::text/, 'pins must be schema-qualified literals');
  assert.match(mig, /\('public\.pdc_tune_operation_change_candidate_20260912\(uuid,jsonb\)'\)\) v\(sig\)/);
  assert.match(mig, /check_name='protected_function_md5s'\) INTO x;/);
  assert.match(mig, /a pin does not resolve under search_path pg_catalog/);
  assert.match(mig, /'service_operation_supersede_471'/); assert.match(mig, /\$chk\$,true,270,'r471'\);/);
  assert.match(sqlt, /3781d764a2aedf1bbfddab707a1ccfd9/); assert.match(sqlt, /^ROLLBACK;/m);
});
test('rollback: refuses while supersessions exist, restores the CRLF candidate (md5 cc5dee40), removes pins, check and objects', () => {
  assert.match(down, /SET LOCAL lock_timeout = '2s';/);
  assert.match(down, /pdc_service_operation_supersessions_471/);
  assert.match(down, /cc5dee40fa5a86fc1caa3704af318744/); assert.match(down, /chr\(13\)\|\|chr\(10\)/);
  assert.match(down, /DROP SCHEMA pdc_service_supersede_private/);
  assert.match(down, /LOCK TABLE public\.vehicles, public\.pdc_pilbara_service_operations, public\.vehicle_workshop_line_adjustments, public\.pdc_service_operation_supersessions_471 IN ACCESS EXCLUSIVE MODE;/);
  assert.match(down, /check_name='service_operation_supersede_471'/); assert.match(down, /release='r471'/);
});
test('preparer: trailing bay code means the same line; tight pattern; raw Operation Desc kept; provenance recorded', () => {
  assert.match(py, /BAY_CODE_RULE = 'r471_trailing_bay_code_same_line'/);
  assert.match(py, /BAY_CODE_PATTERN = r'\[0-9\]\{2\}\[A-Z\]\[0-9\]\[A-Z\]'/);
  assert.match(py, /def canonicalise_bay_code_descriptions\(rows, existing\):/);
  assert.match(py, /def existing_lines_from_operations\(operations, superseded_ids=\(\)\):/);
  assert.match(py, /BAY_CODE_PROVENANCE_KEY = 'description_bay_code_r471'/);
  for (const s of ['HAEVY', 'SUSP 17C6B', '04K2B', '04K2A', '05K4F']) assert.ok(t471.includes(s), s);
});
test('no real stock numbers, R/O numbers or operation ids in r471 files (synthetic fixtures only)', () => {
  const all = mig + down + sqlt + t471 + R('test_service_operation_supersede_471.js');
  assert.doesNotMatch(all, /\b1[0-3][0-9]{6}\b/, 'stock-like number');
  assert.doesNotMatch(all, /\bU1[0-9]{5}\b|\bIS6[0-9]{7}\b/, 'stock number');
  assert.doesNotMatch(all, /\bJ13[89](?!9000[0-9]{2}\b)[0-9]{6}\b/, 'real R/O');
  assert.doesNotMatch(all, /\b[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b/, 'v4 uuid');
});
test('fault log F84 after F81, docs section for r471', () => {
  const log = R('docs/FAULT_LOG.md');
  assert.match(log, /^\| F84 \| 22 Oct 09:40 \| /m); assert.ok(log.indexOf('| F84 |') > log.indexOf('| F81 |'));
  assert.match(log, /service_operation_supersede_471/); assert.match(log, /r471_trailing_bay_code_same_line/);
  const doc = R('docs/revolution-service-email.md');
  assert.match(doc, /## Bay code on a re-sent line — r471 \(F84\), 22 October 2026/);
  for (const s of ['description_bay_code_r471', 'pdc_service_operation_supersessions_471', '3781d764a2aedf1bbfddab707a1ccfd9']) assert.ok(doc.includes(s), s);
});
test('python preparer tests pass (skipped when python3 is not installed)', t => {
  const probe = spawnSync('python3', ['--version']);
  if (probe.error || probe.status !== 0) return t.skip('python3 not available');
  const r = spawnSync('python3', ['-B', '-m', 'unittest', 'test_revolution_service_wsublet', 'test_revolution_service_wsublet_468', 'test_revolution_service_wsublet_471'],
    { cwd: path.join(__dirname, 'tools/import-rules'), encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /Ran 29 tests/);
});
