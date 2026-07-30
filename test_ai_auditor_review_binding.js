'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const start = app.indexOf('function pdcAuditorReviewCandidates');
const end = app.indexOf('function pdcAuditorProjectedReports', start);
assert.ok(start >= 0 && end > start, 'review binding implementation missing');
const context = vm.createContext({ pdcAuditorSafeText: value => String(value || '') });
vm.runInContext(app.slice(start, end), context);

const source = { operational_revision: 'op-rev-1', rule_set_hash: 'b'.repeat(64) };
const finding = (id, entity = 'vehicle-1') => ({ id, ruleId: 'BOOKING_WITHOUT_ACTIVE_WORK', vehicleId: entity, scope: [entity] });
const queue = (id, entity = 'vehicle-1') => ({
  finding_id: id,
  stable_fingerprint: 'a'.repeat(64),
  evidence_fingerprint: 'c'.repeat(64),
  last_seen_run_id: '22222222-2222-4222-8222-222222222222',
  run_operational_revision: source.operational_revision,
  run_rule_set_hash: source.rule_set_hash,
  run_model_key: 'deterministic-stage-a-rules',
  rule_key: 'booking_without_active_work',
  entity_type: 'vehicle',
  entity_id: entity,
  lifecycle_status: 'current',
  decision: null,
});

const one = context.pdcAuditorBindReviewFindings([finding('ui-1')], [queue('11111111-1111-4111-8111-111111111111')], source);
assert.ok(one[0].review, 'one card to one exact persisted finding must bind');

const manyCards = context.pdcAuditorBindReviewFindings(
  [finding('ui-1'), finding('ui-2')],
  [queue('11111111-1111-4111-8111-111111111111')],
  source,
);
assert.ok(manyCards.every(item => item.review === null), 'two cards to one finding must both fail closed');

const manyRows = context.pdcAuditorBindReviewFindings(
  [finding('ui-1')],
  [queue('11111111-1111-4111-8111-111111111111'), queue('33333333-3333-4333-8333-333333333333')],
  source,
);
assert.strictEqual(manyRows[0].review, null, 'one card to two findings must fail closed');

const malformed = queue('bad-id');
assert.strictEqual(context.pdcAuditorBindReviewFindings([finding('ui-1')], [malformed], source)[0].review, null, 'malformed identities must fail closed');

const staleSource = queue('11111111-1111-4111-8111-111111111111');
staleSource.run_operational_revision = 'old-revision';
assert.strictEqual(context.pdcAuditorBindReviewFindings([finding('ui-1')], [staleSource], source)[0].review, null, 'source-revision mismatch must fail closed');

const executionBearing = queue('11111111-1111-4111-8111-111111111111');
executionBearing.decision = { status: 'approved', operational_change: true };
assert.strictEqual(context.pdcAuditorBindReviewFindings([finding('ui-1')], [executionBearing], source)[0].review, null, 'execution-bearing decisions must be rejected');

console.log('AI Auditor review binding passed: globally one-to-one, source-bound and fail-closed');
