// r468 (F81): Revolution added an OPTIONAL leading Type column (D data, T1 footer) to 'PMG PD Service Complete w/Sublet'.
// The preparer drops it (like the sales feed); no database function changes. These tests check the preparer, its fixtures,
// docs and fault log, that no migration or rollback was added for r468, and run the Python tests when python3 is present.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { spawnSync } = require('node:child_process');
const dir = path.join(__dirname, 'tools/import-rules');
const py = fs.readFileSync(path.join(dir, 'revolution_service_wsublet.py'), 'utf8');
const fx = fs.readFileSync(path.join(dir, 'fixtures_service_wsublet_468.py'), 'utf8');
const t468 = fs.readFileSync(path.join(dir, 'test_revolution_service_wsublet_468.py'), 'utf8');

test('preparer: optional leading Type dropped, D / T1 checked against the row shape, other values refused', () => {
  assert.match(py, /def has_type_column\(headers\):/);
  assert.match(py, /if h and h\[0\] == TYPE_COLUMN:\n\s+h = h\[1:\]/);
  assert.match(py, /Type is only accepted as the first column/);
  assert.match(py, /TYPE_DATA, TYPE_FOOTER = 'D', 'T1'/);
  assert.match(py, /only D and T1 are accepted/);
  assert.match(py, /t, cells = cells\[0\], cells\[1:\]/);
  assert.match(py, /TYPE_BASIS = 'absent_r442'/, 'manifest marker unchanged');
  assert.doesNotMatch(py, /the w\/Sublet report has no Type column'\)/, 'the r442 blanket refusal is gone');
});
test('fixtures: synthetic only, shaped like the reported file (2,572 lines, 154 stocks, 243 POs), with and without Type', () => {
  assert.match(fx, /EXPECTED = \{'lines': 2572, 'stocks': 154, 'distinct_pos': 243\}/);
  assert.match(fx, /\['T1'\] if typed/); assert.match(fx, /else 'D'\] \+ cells/);
  assert.doesNotMatch(fx + t468, /\b1[23][0-9]{6}\b/, 'no real stock numbers');
  assert.match(t468, /NO_TYPE_DIGEST_BEFORE_R468 = '[0-9a-f]{64}'/);
  for (const bad of ["'X'", "''", 'None', "'d'", "'T2'"]) assert.ok(t468.includes(bad), bad);
});
test('no SQL for r468: no migration or rollback, database bindings still refuse Type (row validator, manifest)', () => {
  for (const d of ['supabase/migrations', 'supabase/rollbacks', 'tests']) {
    assert.deepEqual(fs.readdirSync(path.join(__dirname, d)).filter(f => /r468|wsublet_468|type_column_468/i.test(f)), [], d);
  }
  const r444 = fs.readFileSync(path.join(__dirname, 'supabase/migrations/20261021083212_r444_sublet_po_descriptions.sql'), 'utf8');
  assert.match(r444, /NOT \(x->'raw_row' \? 'Type'\)/);
});
test('docs and fault log: F81 after F75, r468 section in the service email doc', () => {
  const log = fs.readFileSync(path.join(__dirname, 'docs/FAULT_LOG.md'), 'utf8');
  assert.match(log, /^\| F81 \| 22 Oct 09:15 \| Reported by Kajel/m);
  assert.ok(log.indexOf('| F81 |') > log.indexOf('| F75 |'));
  assert.match(log, /leading_type_dropped_r468/); assert.match(log, /no SQL/);
  const doc = fs.readFileSync(path.join(__dirname, 'docs/revolution-service-email.md'), 'utf8');
  assert.match(doc, /## Optional leading Type column — r468 \(F81\), 22 October 2026/);
  assert.ok(doc.indexOf('r468 (F81)') < doc.indexOf('## Sublet descriptions — r444'));
  for (const s of ['only D and T1 are accepted', 'absent_r442', 'e4ba03437490bd155d4d8553285107f8', '0534336e01558066cf7ec3dcb3995cd4']) assert.ok(doc.includes(s), s);
});
test('python preparer tests pass (skipped when python3 is not installed)', t => {
  const probe = spawnSync('python3', ['--version']);
  if (probe.error || probe.status !== 0) return t.skip('python3 not available');
  const r = spawnSync('python3', ['-m', 'unittest', 'test_revolution_service_wsublet', 'test_revolution_service_wsublet_468'], { cwd: dir, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stderr, /Ran 17 tests/);
});
