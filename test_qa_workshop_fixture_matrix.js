'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const scriptPath = path.join(__dirname, 'scripts', 'qa_workshop_fixture_matrix.py');
assert.ok(fs.existsSync(scriptPath), 'guarded Workshop QA fixture-matrix script must exist');
const source = fs.readFileSync(scriptPath, 'utf8').replace(/\r\n/g, '\n');

assert.match(source, /EXPECTED_STAGING_REF\s*=\s*["']cdsmnqxtyyoeoznmbidd["']/, 'exact staging ref must be pinned');
assert.match(source, /PRODUCTION_REF\s*=\s*["']vjdtsswhroyguxyfjdkt["']/, 'production ref denylist must be explicit');
assert.match(source, /EXPECTED_BRANCH\s*=\s*["']qa\/workshop-bulletproof-20260728["']/, 'QA branch must be pinned');
assert.match(source, /RUN_ID\s*=\s*["']QA-WCB-20260728T130102Z["']/, 'run namespace must be pinned');
assert.match(source, /EXPECTED_LEDGER_HEAD\s*=\s*["']102["']/, 'staging ledger head must be pinned');
assert.match(source, /pg_advisory_xact_lock/, 'fixture rehearsal must serialize on a run-scoped lock');
assert.match(source, /upsert_vehicle_master_import/, 'vehicle creation must use the protected canonical product RPC');
assert.match(source, /reset role/i, 'fixture-only direct setup must reset impersonation before privileged evidence writes');
assert.match(source, /conn\.rollback\(\)/, 'rehearsal must roll back');
assert.doesNotMatch(source, /--apply|action=["']store_true["'].*apply/s, 'this reviewed stage must not expose a retained apply mode');
assert.doesNotMatch(source, /\b(delete|truncate)\s+from\b/i, 'cleanup preview must not execute destructive cleanup');

const result = spawnSync(process.env.PYTHON || 'python3', [scriptPath, '--plan', '--batch-size', '2'], {
  cwd: __dirname,
  encoding: 'utf8',
  env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' }
});
assert.strictEqual(result.status, 0, `offline fixture plan failed: ${result.stderr || result.stdout}`);
const plan = JSON.parse(result.stdout);
assert.strictEqual(plan.schema, 'pdc.qa-wcb-fixture-plan/v1');
assert.strictEqual(plan.runId, 'QA-WCB-20260728T130102Z');
assert.strictEqual(plan.mode, 'plan');
assert.strictEqual(plan.batchSizePerStage, 2);
assert.strictEqual(plan.rows.length, 16, 'two rows must be planned for each of eight stations');
assert.deepStrictEqual([...new Set(plan.rows.map(row => row.stageCode))], [
  'BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'
]);
assert.strictEqual(new Set(plan.rows.map(row => row.sourceRecordId)).size, 16, 'source records must be unique');
assert.strictEqual(new Set(plan.rows.map(row => row.workItemId)).size, 16, 'work-item IDs must be unique');
assert.ok(plan.rows.every(row => row.sourceRecordId.startsWith('QA-WCB-20260728T130102Z:')));
assert.ok(plan.rows.every(row => /^[0-9a-f-]{36}$/.test(row.workItemId)));
assert.strictEqual(plan.retainedWritesSupported, false, 'review stage must remain rollback-only');
assert.strictEqual(plan.cleanupMode, 'preview_only');

const repeat = spawnSync(process.env.PYTHON || 'python3', [scriptPath, '--plan', '--batch-size', '2'], {
  cwd: __dirname,
  encoding: 'utf8',
  env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' }
});
assert.strictEqual(repeat.status, 0, repeat.stderr);
assert.strictEqual(repeat.stdout, result.stdout, 'offline plan must be byte-deterministic');

console.log('Guarded Workshop QA fixture-matrix source and deterministic plan checks passed');
