/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r509 (F122): optional trailing Create Advisor on the service preparer. Dropped before source_headers, like Type.
// No migration. Blank-advisor data rows are left out of the import. Nothing closes a board card.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = __dirname;
const dir = path.join(root, 'tools/import-rules');
const py = fs.readFileSync(path.join(dir, 'revolution_service_wsublet.py'), 'utf8');
const whole = fs.readFileSync(path.join(dir, 'revolution_service_whole.py'), 'utf8');
const t509 = fs.readFileSync(path.join(dir, 'test_revolution_service_create_advisor_509.py'), 'utf8');

test('preparer: trailing Create Advisor is dropped; blank data rows are skipped; no close', () => {
  assert.match(py, /CREATE_ADVISOR = 'Create Advisor'/);
  assert.match(py, /if h and h\[-1\] == CREATE_ADVISOR:\n\s+h = h\[:-1\]/);
  assert.match(py, /Create Advisor is only accepted as the last column/);
  assert.match(py, /if advised and kind == 'data' and norm\(advisor_value\) == '':/);
  assert.match(py, /'closes_board_cards': False/);
  assert.match(py, /trailing_create_advisor_dropped_r509/);
  assert.doesNotMatch(py, /closed_at/);
  assert.doesNotMatch(py, /\b(UPDATE|DELETE FROM|INSERT INTO)\b/);
  assert.match(whole, /CreateAdvisor-Service-as-a-Whole/);
  assert.match(whole, /never closes, hides or deletes/);
});

test('no SQL for the Create Advisor preparer: header pins stay the post-drop contract (an extra column is still refused there)', () => {
  // r509 is also the already-applied fabrication migration. That pair is not a Create Advisor change.
  const fabrication = new Set([
    '20261023130000_r509_fabrication_14_bays.sql',
    '20261023130000_r509_fabrication_14_bays.down.sql',
  ]);
  for (const d of ['supabase/migrations', 'supabase/rollbacks', 'tests']) {
    const hit = fs.readdirSync(path.join(root, d)).filter(f => /r509|create_advisor_509/i.test(f) && !fabrication.has(f));
    assert.deepEqual(hit, [], d);
  }
  const r439 = fs.readFileSync(path.join(root, 'supabase/migrations/20261021064811_r439_sublet_po_refs_and_ticks.sql'), 'utf8');
  assert.match(r439, /NOT pdc_codex_intake_private\.revolution_service_headers_439\(hdr\.b\|\|'\["PO #","Other"\]'/);
  assert.match(r439, /bfda8a3acd8a08bb36f5851ead2cd5e4/);
});

test('docs and fault log: F122 after F121, r509 section, undo is revert only', () => {
  const log = fs.readFileSync(path.join(root, 'docs/FAULT_LOG.md'), 'utf8');
  assert.match(log, /^\| F122 \| 23 Oct \| Kajel \(Email Bot\) blocked on CreateAdvisor-Service-as-a-Whole/m);
  assert.ok(log.indexOf('| F122 |') > log.indexOf('| F121 |'));
  assert.match(log, /no SQL/);
  assert.match(log, /Revert the r509 commit/);
  assert.match(log, /board_ro_missing/);
  const doc = fs.readFileSync(path.join(root, 'docs/revolution-service-email.md'), 'utf8');
  assert.match(doc, /## Optional trailing Create Advisor — r509 \(F122\), 23 October 2026/);
  for (const s of ['trailing_create_advisor_dropped_r509', 'closes_board_cards', 'bfda8a3acd8a08bb36f5851ead2cd5e4',
    'Create Advisor <> ""', 'Do not apply a close']) assert.ok(doc.includes(s), s);
  assert.doesNotMatch(t509, /\b1[0-9]{7}\b/, 'no real stock numbers');
});

test('python preparer tests pass (skipped when python3 is not installed)', t => {
  const probe = spawnSync('python3', ['--version']);
  if (probe.error || probe.status !== 0) return t.skip('python3 not available');
  const r = spawnSync('python3', ['-m', 'unittest', 'test_revolution_service_create_advisor_509', 'test_revolution_service_wsublet',
    'test_revolution_service_wsublet_468', 'test_revolution_service_whole_479'], { cwd: dir, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /\nOK(?: \(skipped=\d+\))?\n?$/);
});
