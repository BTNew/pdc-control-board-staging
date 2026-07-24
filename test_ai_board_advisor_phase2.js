'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const advisor = require('./ai-board-advisor.js');

function deepFreeze(value) {
  if (!value || typeof value !== 'object' || Object.isFrozen(value)) return value;
  Object.values(value).forEach(deepFreeze);
  return Object.freeze(value);
}

const input = deepFreeze({
  nowIso: '2026-07-20T04:00:00.000Z',
  bookingCoverage: true,
  vehicles: [
    {
      identity: 'shared:vehicle-a', stock: '10000001', customer: 'Test A', description: 'Hilux',
      currentStage: 'FAB', stageAgeDays: 8, stageAgeLimitDays: 3, deliveryAt: '2026-07-22T00:00:00.000Z', blocked: true,
      blockReason: 'Awaiting engineering confirmation', requiredStages: ['FAB', 'ELEC'], completedStages: [],
      parts: { required: true, complete: false, stoppage: true, reason: 'Back order', eta: '2026-07-19T00:00:00.000Z' },
      jobLines: [{ description: 'Fit canopy', hours: null, confirmed: false }],
    },
    {
      identity: 'shared:vehicle-b', stock: '10000002', customer: 'Test B', description: 'Prado',
      currentStage: 'TINT', stageAgeDays: 1, deliveryAt: '2026-08-20T00:00:00.000Z', blocked: false,
      requiredStages: ['TINT'], completedStages: [], parts: { required: false, complete: false, stoppage: false }, jobLines: [],
    },
  ],
  bookings: [
    { id: 'booking-a', vehicleIdentity: 'shared:vehicle-a', stage: 'FAB', bay: '1', status: 'stoppage', startAt: '2026-07-20T01:00:00.000Z', endAt: '2026-07-20T05:00:00.000Z', stoppageReason: 'Awaiting material' },
    { id: 'booking-b', vehicleIdentity: 'shared:vehicle-b', stage: 'FAB', bay: '1', status: 'planned', startAt: '2026-07-20T03:00:00.000Z', endAt: '2026-07-20T06:00:00.000Z' },
  ],
});
const before = JSON.stringify(input);
const first = advisor.analyze(input);
const second = advisor.analyze(input);
assert.strictEqual(JSON.stringify(input), before, 'analysis must not mutate its frozen input');
assert.deepStrictEqual(first, second, 'same input and explicit clock must produce deterministic output');
assert.strictEqual(first.bookingCoverage, true);
assert.ok(first.findings.some(item => item.rule === 'BAY_OVERLAP'), 'same-lane overlap must be detected');
assert.ok(first.findings.some(item => item.rule === 'PARTS_STOPPAGE'), 'Parts stoppage must be detected');
assert.ok(first.findings.some(item => item.rule === 'PARTS_ETA_OVERDUE'), 'overdue Parts ETA must be detected');
assert.ok(first.findings.some(item => item.rule === 'DELIVERY_RISK'), 'near delivery with outstanding work must be detected');
assert.ok(first.findings.some(item => item.rule === 'LABOUR_UNCONFIRMED'), 'unconfirmed labour must be detected');
assert.ok(first.findings.some(item => item.rule === 'STAGE_STALE' && item.evidence.some(value => value.includes('configured limit 3'))), 'stage ageing must use and expose the configured threshold');
assert.ok(first.findings.some(item => item.rule === 'BOOKING_STOPPAGE'), 'booking stoppage must be detected');
assert.ok(first.findings.some(item => item.rule === 'UNSCHEDULED_REQUIRED_STAGE' && item.evidence.some(value => value.includes('elec'))), 'outstanding unscheduled stage must be detected with authoritative coverage');
assert.strictEqual(first.findings[0].severity, 'critical', 'critical findings must sort first');
assert.ok(first.findings.every(item => !('action' in item) && !('callback' in item) && !('mutation' in item)), 'findings must contain display evidence only');
for (const item of first.findings) {
  const renderedText = [item.title, item.explanation, item.recommendation, ...(item.evidence || [])].filter(Boolean).join(' ');
  assert.ok(!/\bstoppage\b/.test(renderedText), `AI finding ${item.rule} must render STOPPAGE in uppercase: ${renderedText}`);
}

const ambiguous = advisor.analyze({
  nowIso: input.nowIso,
  bookingCoverage: true,
  vehicles: [
    { identity: 'shared:duplicate', stock: '1', requiredStages: ['FAB'], completedStages: [] },
    { identity: 'shared:duplicate', stock: '2', requiredStages: ['FAB'], completedStages: [] },
  ],
  bookings: [{ id: 'ambiguous-booking', vehicleIdentity: 'shared:duplicate', stage: 'FAB', bay: '1', status: 'planned', startAt: '2026-07-21T00:00:00Z', endAt: '2026-07-21T01:00:00Z' }],
});
assert.ok(ambiguous.findings.some(item => item.rule === 'DATA_VEHICLE_IDENTITY_DUPLICATE'));
assert.ok(ambiguous.findings.some(item => item.rule === 'DATA_BOOKING_VEHICLE_UNRESOLVED'));
assert.ok(!ambiguous.findings.some(item => item.rule === 'UNSCHEDULED_REQUIRED_STAGE'), 'ambiguous vehicle identity must suppress identity-dependent advice');

const malformed = advisor.analyze({
  nowIso: input.nowIso,
  bookingCoverage: true,
  vehicles: [{ identity: 'shared:safe', stock: '3' }],
  bookings: [
    { id: 'duplicate', vehicleIdentity: 'shared:safe', startAt: 'bad', endAt: 'bad' },
    { id: 'duplicate', vehicleIdentity: 'shared:safe', startAt: '2026-07-20T00:00:00Z', endAt: '2026-07-20T01:00:00Z' },
  ],
});
assert.ok(malformed.findings.some(item => item.rule === 'DATA_BOOKING_ID_DUPLICATE'));
assert.ok(!malformed.findings.some(item => item.rule === 'DATA_BOOKING_INTERVAL_INVALID'), 'duplicate booking advice must be suppressed rather than guessing which row is authoritative');

const noCoverage = advisor.analyze({
  nowIso: input.nowIso,
  bookingCoverage: false,
  vehicles: [{ identity: 'shared:no-coverage', stock: '4', requiredStages: ['FAB'], completedStages: [] }],
  bookings: [{ id: 'ignored', vehicleIdentity: 'shared:no-coverage', stage: 'FAB', status: 'stoppage', startAt: 'bad', endAt: 'bad' }],
});
assert.ok(!noCoverage.findings.some(item => item.rule.startsWith('BOOKING_') || item.rule === 'BAY_OVERLAP' || item.rule === 'UNSCHEDULED_REQUIRED_STAGE'), 'booking advice must be omitted without authoritative booking coverage');

const atStageLimit = advisor.analyze({
  nowIso: input.nowIso,
  bookingCoverage: false,
  vehicles: [{ identity: 'shared:stage-limit', stock: '5', currentStage: 'FAB', stageAgeDays: 4, stageAgeLimitDays: 4, requiredStages: ['FAB'], completedStages: [] }],
});
assert.ok(!atStageLimit.findings.some(item => item.rule === 'STAGE_STALE'), 'a vehicle exactly at its configured stage limit is not overdue');

const overStageLimit = advisor.analyze({
  nowIso: input.nowIso,
  bookingCoverage: false,
  vehicles: [{ identity: 'shared:stage-overdue', stock: '6', currentStage: 'FAB', stageAgeDays: 5, stageAgeLimitDays: 4, requiredStages: ['FAB'], completedStages: [] }],
});
assert.ok(overStageLimit.findings.some(item => item.rule === 'STAGE_STALE'), 'a vehicle over its configured stage limit is overdue');

const invalidClock = advisor.analyze({ nowIso: 'not-a-date', vehicles: [], bookings: [], bookingCoverage: true });
assert.strictEqual(invalidClock.findings.length, 1);
assert.strictEqual(invalidClock.findings[0].rule, 'DATA_ANALYSIS_CLOCK_INVALID');

const source = fs.readFileSync(path.join(__dirname, 'ai-board-advisor.js'), 'utf8');
[
  /localStorage\s*\./,
  /sessionStorage\s*\./,
  /\bfetch\s*\(/,
  /XMLHttpRequest/,
  /WebSocket/,
  /EventSource/,
  /saveVehicleEdits/,
  /runStorageTransaction/,
  /workshopSavePlans/,
  /applyEmailReview/,
  /rejectEmailReview/,
  /create_workshop_booking/,
  /move_workshop_booking/,
  /complete_workshop_booking/,
].forEach(pattern => assert.ok(!pattern.test(source), `advisor module must not contain authority/network primitive ${pattern}`));

console.log('Phase Two advisory AI pure and no-authority checks passed');
