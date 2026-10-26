/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { scanSql, lintMigrationFiles, compareBaseline } = require('./scripts/lint_migration_safeupdate_dml.js');

const baseline = JSON.parse(fs.readFileSync('scripts/safeupdate_dml_baseline.json', 'utf8'));

test('DELETE and UPDATE without a WHERE clause fail the migration lint', () => {
  assert.deepEqual(scanSql('DELETE FROM t;'), ['DELETE FROM t']);
  assert.deepEqual(scanSql('UPDATE t SET a = 1;'), ['UPDATE t SET a = 1']);
  assert.deepEqual(scanSql('UPDATE t SET a = (SELECT 1 WHERE false);'), ['UPDATE t SET a = (SELECT 1 WHERE false)']);
  assert.deepEqual(scanSql('INSERT INTO t(a) VALUES (1) ON CONFLICT (a) DO UPDATE SET a = EXCLUDED.a;').length, 1);
  assert.deepEqual(scanSql("SELECT E'DELETE FROM secret;';"), []);
  assert.deepEqual(scanSql('WITH cte AS (DELETE FROM t RETURNING *) DELETE FROM u WHERE id = 1;'), ['DELETE FROM t RETURNING *']);
});

test('a WHERE clause, trigger event, and row lock are not bare DML', () => {
  for (const sql of [
    'DELETE FROM t WHERE true;',
    'UPDATE t SET a = 1 WHERE id = 1;',
    'INSERT INTO t(a) VALUES (1) ON CONFLICT (a) DO UPDATE SET a = EXCLUDED.a WHERE true;',
    'SELECT * FROM t FOR UPDATE;',
    'GRANT UPDATE ON t TO authenticated;',
    'REFERENCES t(id) ON DELETE CASCADE ON UPDATE CASCADE;',
    'CREATE TRIGGER t AFTER INSERT OR UPDATE OR DELETE ON public.t FOR EACH ROW EXECUTE FUNCTION f();',
    'CREATE TRIGGER t AFTER UPDATE OF a, b ON public.t FOR EACH ROW EXECUTE FUNCTION f();',
    "SELECT 'DELETE FROM t';",
  ]) {
    assert.deepEqual(scanSql(sql), [], sql);
  }
});

test('supabase/migrations match the locked safeupdate baseline', () => {
  const errors = compareBaseline(lintMigrationFiles('.'), baseline);
  assert.deepEqual(errors, []);
  assert.equal(baseline.locked_through_version, '20261020082000');
});

test('a migration newer than the lock cannot keep a bare DELETE', () => {
  const found = {
    'supabase/migrations/20261021000000_future.sql': [{
      id: 'new',
      statement: 'DELETE FROM public.future',
    }],
  };
  const errors = compareBaseline(found, {
    locked_through_version: baseline.locked_through_version,
    violations: { 'supabase/migrations/20261021000000_future.sql': ['new'] },
  });
  assert.equal(errors.some(error => error.includes('newer than')), true);
});


test('filesystem migration scan keeps portable baseline keys and still rejects newer bare DML', () => {
  const os = require('node:os'), path = require('node:path');
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-safeupdate-path-test-'));
  try {
    const dir = path.join(fixtureRoot, 'supabase', 'migrations');
    fs.mkdirSync(dir, { recursive:true });
    fs.writeFileSync(path.join(dir, '20261021000000_future.sql'), 'DELETE FROM public.future;');
    const found = lintMigrationFiles(fixtureRoot);
    const key = 'supabase/migrations/20261021000000_future.sql';
    assert.deepEqual(Object.keys(found), [key]);
    const errors = compareBaseline(found, {
      locked_through_version: baseline.locked_through_version,
      violations: { [key]: found[key].map(item => item.id) }
    });
    assert.equal(errors.length, 1);
    assert.match(errors[0], /newer than .* DELETE or UPDATE without a WHERE clause/);
  } finally {
    const absolute = path.resolve(fixtureRoot);
    assert.equal(path.dirname(absolute), path.resolve(os.tmpdir()));
    assert.ok(path.basename(absolute).startsWith('pdc-safeupdate-path-test-'));
    fs.rmSync(absolute, { recursive:true, force:true });
  }
});
