'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const actions = require('./pdc-email-ai-v2-actions.js');
const eligibility = require('./workshop-eligibility.js');
const scanner = require('./scripts/check_frontend_secrets.js');

function operationPlan(hours) {
  return {
    schema_version: actions.PLAN_SCHEMA_VERSION,
    source: {
      receipt_id: '11111111-1111-4111-8111-111111111111',
      source_digest: 'a'.repeat(64), evidence_digest: 'b'.repeat(64),
      thread_id: 'synthetic-audit-thread', message_id: 'synthetic-audit-message',
      attachment_digests: ['c'.repeat(64)],
    },
    versions: {
      model: 'synthetic', prompt: 'synthetic', taxonomy: 'pdc-operation-taxonomy-approved/v1',
      rules: 'synthetic', action_contract: actions.ACTION_CONTRACT_VERSION, supabase_actions: 'synthetic',
    },
    instructions: [{
      instruction_id: 'synthetic-op-1', vehicle_id: '22222222-2222-4222-8222-222222222222',
      identity: { stock_number: 'AUDIT-0001', vin: null, backend_record_id: null },
      expected_vehicle_version: 1, action_type: 'operation_add',
      payload: {
        operation_no: 'OP1', source_row_no: 1, work_key: 'FITTING',
        description: 'Synthetic labour validation only', estimated_hours: hours,
        taxonomy_version: 'pdc-operation-taxonomy-approved/v1', taxonomy_disposition: 'classified',
        source_uid: 'synthetic-audit-source',
      },
      evidence_refs: ['synthetic:line:1'],
    }],
  };
}

test('valid two-decimal labour hours retain the exact supplied value, including zero', () => {
  for (const hours of [0, 0.01, 0.07, 0.29, 0.57, 1, 1.1, 1.13, 2.01, 2.5, 17.29, 18.01, 999.99]) {
    const input = operationPlan(hours);
    const result = actions.validatePdcEmailAiV2Plan(input);
    assert.equal(result.instructions[0].payload.estimated_hours, hours);
    assert.deepEqual(input, operationPlan(hours), 'validation must not mutate source evidence');
  }
});

test('all allowed hundredth-hour increments pass floating-point precision validation', () => {
  for (let cents = 0; cents <= 99999; cents++) {
    const hours = cents / 100;
    assert.equal(actions.validatePdcEmailAiV2Plan(operationPlan(hours)).instructions[0].payload.estimated_hours, hours);
  }
});

test('invalid labour hours remain rejected, never silently rounded', () => {
  for (const hours of [-0.01, 0.001, 0.071, 1.101, 2.001, 999.991, 1000, null, '1.10', NaN, Infinity]) {
    assert.throws(() => actions.validatePdcEmailAiV2Plan(operationPlan(hours)), /estimated_hours/);
  }
});

test('in-transit earliest dates include seven calendar days in both accepted input formats', () => {
  for (const [eta, expected] of [
    ['2026-09-15', '2026-09-22'], ['15/09/2026', '2026-09-22'],
    ['2026-09-28', '2026-10-05'], ['2026-12-29', '2027-01-05'],
    ['2028-02-25', '2028-03-03'], ['2026-02-25', '2026-03-04'],
  ]) {
    const result = eligibility.scheduleEligibility({ current_location: 'IT', eta_to_kewdale: eta });
    assert.equal(result.enabled, true);
    assert.equal(result.earliestDateKey, expected);
    assert.match(result.reason, /ETA \+ 7 days/);
  }
});

test('missing and impossible ETAs remain unschedulable', () => {
  for (const eta of ['', null, '2026-02-30', '2026-13-01', '31/04/2026', '2026-09-00', 'not-a-date']) {
    assert.equal(eligibility.scheduleEligibility({ current_location: 'IT', eta_to_kewdale: eta }).enabled, false);
  }
});

test('Yard Hold and PMB do not acquire an in-transit ETA restriction', () => {
  for (const location of ['YH', 'PMB']) {
    const result = eligibility.scheduleEligibility({ current_location: location, eta_to_kewdale: '2099-01-01' });
    assert.equal(result.enabled, true);
    assert.equal(result.earliestDateKey, '');
  }
});

test('fetching a snapshot is not reported as verified business effects', async () => {
  const calls = [];
  const client = actions.createPdcEmailAiV2Actions({
    config: { projectRef: actions.STAGING_PROJECT_REF, url: actions.STAGING_SUPABASE_URL },
    getAccessToken: () => 'synthetic-test-only-not-a-credential',
    rpc: async name => {
      calls.push(name);
      return { data: name === actions.SNAPSHOT_RPC ? { ok: true, code: 'ok', data: {}, revision: 1 } : { ok: true, code: 'applied' } };
    },
  });
  const result = await client.applyPlan(operationPlan(1.1));
  assert.equal(result.ok, true);
  assert.equal(result.readback_ok, true, 'legacy fetch flag preserved');
  assert.equal(result.snapshot_fetched, true);
  assert.equal(result.effects_verified, false, 'empty snapshot proves no operation parity');
  assert.deepEqual(calls, [actions.ACTION_RPC, actions.SNAPSHOT_RPC]);
});

test('failed action or failed snapshot never claims effect verification', async () => {
  for (const failAction of [true, false]) {
    const client = actions.createPdcEmailAiV2Actions({
      config: { projectRef: actions.STAGING_PROJECT_REF, url: actions.STAGING_SUPABASE_URL },
      getAccessToken: () => 'synthetic-test-only-not-a-credential',
      rpc: async name => {
        if ((name === actions.ACTION_RPC) === failAction) return { error: { message: 'synthetic failure' } };
        return { data: { ok: true, code: 'ok', data: {}, revision: 1 } };
      },
    });
    const result = await client.applyPlan(operationPlan(0));
    assert.equal(result.ok, false);
    assert.equal(result.effects_verified, false);
    assert.equal(result.snapshot_fetched, failAction);
  }
});

test('secret scanner detects token values without flagging security vocabulary or anon JWTs', () => {
  const token = role => [
    Buffer.from(JSON.stringify({ alg: 'HS256' })).toString('base64url'),
    Buffer.from(JSON.stringify({ role })).toString('base64url'), 'synthetic_signature_only',
  ].join('.');
  assert.equal(scanner.findPrivilegedTokens('const forbidden = ["service_role", "sb_secret_"];').length, 0);
  assert.equal(scanner.findPrivilegedTokens(token('anon')).length, 0);
  assert.equal(scanner.findPrivilegedTokens(token('service_role')).length, 1);
  assert.equal(scanner.findPrivilegedTokens('sb_secret_' + 'SYNTHETIC'.repeat(4)).length, 1);
});

test('scanner finds tracked nested frontend values and treats unreadable files as errors', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pdc-scan-test-'));
  try {
    execFileSync('git', ['init', '--quiet', root], { stdio: 'pipe' });
    fs.mkdirSync(path.join(root, 'nested'));
    fs.writeFileSync(path.join(root, 'nested', 'app.js'), 'const key = "sb_secret_' + 'SYNTHETIC'.repeat(4) + '";');
    fs.writeFileSync(path.join(root, 'test_fixture.js'), 'const synthetic = "sb_secret_' + 'FIXTUREONLY'.repeat(4) + '";');
    execFileSync('git', ['add', '.'], { cwd: root, stdio: 'pipe' });
    const result = scanner.scanFrontend(root);
    assert.equal(result.scannedFiles, 1);
    assert.equal(result.findings.length, 1);
    assert.equal(result.findings[0].file, 'nested/app.js');
    assert.equal(JSON.stringify(result).includes('SYNTHETIC'), false, 'diagnostics redact token values');
    fs.unlinkSync(path.join(root, 'nested', 'app.js'));
    assert.throws(() => scanner.scanFrontend(root), /ENOENT/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});
