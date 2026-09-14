'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

function assertAppliedMigration(identity, requiredVersion, root = path.resolve(__dirname, '../..')) {
  assert.match(requiredVersion, /^\d{14}$/, 'Required migration version must be exact');
  const history = Array.isArray(identity.applied_database_migration_history)
    ? identity.applied_database_migration_history : [];
  const entry = [identity.observed_applied_database_migration, ...history]
    .find(migration => migration?.version === requiredVersion);
  assert.ok(entry, `Required applied migration ${requiredVersion} is missing from deployment provenance`);
  assert.equal(entry.version, requiredVersion);
  assert.equal(entry.commissioned, true, `${requiredVersion} must be commissioned`);
  assert.equal(entry.review_status, 'staging_applied', `${requiredVersion} must be applied to staging`);
  assert.equal(typeof entry.file, 'string', `${requiredVersion} must identify its migration file`);
  assert.ok(path.basename(entry.file).startsWith(`${requiredVersion}_`), `${requiredVersion} must match the migration filename`);
  const digest = crypto.createHash('sha256').update(fs.readFileSync(path.resolve(root, entry.file))).digest('hex');
  assert.equal(entry.sha256, digest, `${requiredVersion} migration content must match its recorded SHA256`);
  return entry;
}

module.exports = { assertAppliedMigration };
