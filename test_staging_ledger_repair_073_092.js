'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const repairPath = path.join(__dirname, 'scripts', 'repair_migration_ledger_073_092_staging.py');
assert.ok(fs.existsSync(repairPath), 'guarded ledger-repair script must exist');
const source = fs.readFileSync(repairPath, 'utf8').replace(/\r\n/g, '\n');

assert.match(source, /EXPECTED_STAGING_REF\s*=\s*["']cdsmnqxtyyoeoznmbidd["']/, 'exact staging ref must be pinned');
assert.match(source, /PRODUCTION_REF\s*=\s*["']vjdtsswhroyguxyfjdkt["']/, 'production ref denylist must be explicit');
assert.match(source, /EXPECTED_BRANCH\s*=\s*["']qa\/workshop-bulletproof-20260728["']/, 'QA branch must be pinned');
assert.match(source, /EXPECTED_LEDGER_HEAD\s*=\s*["']102["']/, 'ledger head sentinel must be pinned');
assert.match(source, /EXPECTED_RECONCILIATION_SHA256\s*=\s*["']34eaf7d23dfe9c8c6d4646c33402573640ef6c631c801a00e50dd9640bd83b57["']/, 'reviewed reconciliation evidence must be hash-bound');
assert.match(source, /EXPECTED_LIVE_LEDGER_ARRAY_SHA256\s*=\s*["']bc8ac3e33b3cdb91836fdbdc9c64c084244e5c70fe123aed32f122425672e772["']/, 'exact live staging ledger arrays must be hash-bound');
assert.match(source, /pg_advisory_xact_lock/, 'repair must serialize through a staging advisory lock');
assert.match(source, /lock table supabase_migrations\.schema_migrations in exclusive mode/i, 'ledger must be locked before checks/inserts');
assert.match(source, /insert into supabase_migrations\.schema_migrations/i, 'repair must be ledger-only inserts');
assert.doesNotMatch(source, /\b(update|delete|truncate)\s+(?:table\s+)?supabase_migrations\.schema_migrations/i, 'repair must never rewrite/delete ledger rows');
assert.doesNotMatch(source, /cur\.execute\(\s*(?:transaction_body|tx)\s*\(\s*source/s, 'repair must never execute historical migration SQL');
assert.match(source, /conn\.rollback\(\).*rollback_rehearsal/s, 'default path must rollback');
assert.match(source, /PDC_LEDGER_REPAIR_APPLY_CONFIRMATION/, 'apply must require an explicit environment confirmation');
assert.match(source, /validate_release_backup/, 'apply must require encrypted backup and isolated restore proof');
assert.match(source, /protected.*fingerprint/i, 'repair must reconcile protected table fingerprints');
assert.match(source, /source.*sha256/i, 'migration sources must be SHA-256 guarded');

const versions = [...source.matchAll(/^[ \t]*["'](0(?:7[3-9]|8\d|9[0-2]))["']:\s*\{/gm)].map(match => match[1]);
assert.deepStrictEqual(versions, Array.from({ length: 20 }, (_, i) => String(73 + i).padStart(3, '0')), 'repair inventory must cover exactly 073-092');

console.log('Staging ledger repair 073-092 source contract checks passed');
