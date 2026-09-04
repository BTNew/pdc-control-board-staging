'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
assert.strictEqual((indexSource.match(/qc-pit-detail=2026\.09\.04\.01/g) || []).length, 1, 'the changed application asset has a deferred-PIT cache marker');

const migrationPath = 'supabase/staging_only/20260904010700_deferred_pit_qc_finalization.sql';
assert.ok(fs.existsSync(migrationPath), 'append-only deferred-PIT finalization successor exists');
const migrationSource = fs.readFileSync(migrationPath, 'utf8');
for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "v_head IS DISTINCT FROM '20260904010600'",
  'pdc_qc_checkable_operation_lines_10700',
  'pdc_qc_operation_line_is_deferred_pit_10700',
  'pdc_qc_require_all_operations_complete_379',
  'finalize_pdc_qc_to_rft_700',
  'finalize_pdc_qc_retest_to_rft_747',
  'set_pdc_qc_operation_completion_379',
  "VALUES('20260904010700','deferred_pit_qc_finalization'",
]) assert.ok(migrationSource.includes(marker), `migration retains required authority marker: ${marker}`);
assert.match(migrationSource, /work_key[\s\S]*PITINSPECTION/i, 'server predicate identifies PIT from retained authenticated source evidence');
assert.doesNotMatch(migrationSource, /UPDATE\s+public\.pdc_authenticated_email_operation_lines|DELETE\s+FROM\s+public\.pdc_authenticated_email_operation_lines/i, 'migration never mutates immutable operation evidence');
assert.doesNotMatch(migrationSource, /UPDATE\s+public\.vehicle_work_items[\s\S]*pitInspection/i, 'migration never invents PIT physical completion');

function extractFunction(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let parens = 0;
  let open = -1;
  for (let index = appSource.indexOf('(', start); index < appSource.length; index += 1) {
    if (appSource[index] === '(') parens += 1;
    if (appSource[index] === ')' && --parens === 0) {
      open = appSource.indexOf('{', index);
      break;
    }
  }
  assert.ok(open >= 0, `body for ${name} exists`);
  let depth = 0;
  for (let index = open; index < appSource.length; index += 1) {
    if (appSource[index] === '{') depth += 1;
    if (appSource[index] === '}' && --depth === 0) return appSource.slice(start, index + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const context = {
  groupBy: (items, fn) => items.reduce((groups, item) => ((groups[fn(item)] ||= []).push(item), groups), {}),
  escapeHtml: String,
  pmbStageLabel: value => value,
  qcPageVehicleKey: () => '13048501',
  qcPageOperationPending: new Map(),
  qcPagePendingKey: (key, lineIdentity) => `${key}::${lineIdentity}`,
  qcPagePhotoUploadInFlight: new Set(),
};
vm.createContext(context);
vm.runInContext(`
  ${extractFunction('qcPageOperationLineIsDeferredPit')}
  ${extractFunction('qcPageOperationLines')}
  ${extractFunction('qcPageAllOperationLinesComplete')}
  ${extractFunction('qcPagePhotoDisabledReason')}
  ${extractFunction('qcPageOperationHoursLabel')}
  ${extractFunction('qcPageStageLabel')}
  ${extractFunction('qcPageWorkItemsHtml')}
  this.qcPageOperationLines = qcPageOperationLines;
  this.qcPageAllOperationLinesComplete = qcPageAllOperationLinesComplete;
  this.qcPagePhotoDisabledReason = qcPagePhotoDisabledReason;
  this.qcPageWorkItemsHtml = qcPageWorkItemsHtml;
`, context);

const sourceId = '99999999-9999-4999-8999-999999999999';
const genuineId = '11111111-1111-4111-8111-111111111111';
const vehicle = {
  pdcQcOperationLinesProjectionPresent: true,
  pdcEmailOperationLines: [
    { operation_line_id: sourceId, operation_no: 'OP9', work_key: 'pitInspection', description: 'PIT AND WEIGH' },
    { operation_line_id: genuineId, operation_no: 'OP10', work_key: 'fitting', description: 'Genuine fitment' },
  ],
  pdcQcOperationLines: [
    { lineIdentity: `source:${sourceId}`, sourceKind: 'authenticated', sourceLineId: sourceId, operationNo: 'OP9', stageCode: 'UNALLOCATED_MAPPING_REVIEW', description: 'PIT AND WEIGH', estimatedHours: 0, completed: false, active: true, lineVersion: 0 },
    { lineIdentity: `source:${genuineId}`, sourceKind: 'authenticated', sourceLineId: genuineId, operationNo: 'OP10', stageCode: 'UNALLOCATED_MAPPING_REVIEW', description: 'Genuine fitment', estimatedHours: 1, completed: false, active: true, lineVersion: 0 },
  ],
};

assert.strictEqual(vehicle.pdcEmailOperationLines.some(line => line.work_key === 'pitInspection'), true, 'deferred PIT remains retained source evidence');
assert.deepStrictEqual(Array.from(context.qcPageOperationLines(vehicle), line => line.operationNo), ['OP10'], 'deferred PIT is absent from checkable QC operations while genuine non-PIT remains');
assert.strictEqual(context.qcPageAllOperationLinesComplete(vehicle), false, 'genuine incomplete non-PIT operation blocks final sign-off');
const html = context.qcPageWorkItemsHtml(vehicle);
assert.doesNotMatch(html, /PIT AND WEIGH|OP9/);
assert.match(html, /Genuine fitment|OP10/);

const pitOnlyVehicle = { ...vehicle, pdcQcOperationLines: [vehicle.pdcQcOperationLines[0]] };
assert.deepStrictEqual(Array.from(context.qcPageOperationLines(pitOnlyVehicle)), [], 'deferred PIT does not enter the final-signoff predicate');

const pitPlusCompleteVehicle = {
  ...vehicle,
  pdcQcOperationLines: [vehicle.pdcQcOperationLines[0], { ...vehicle.pdcQcOperationLines[1], completed: true }],
};
assert.strictEqual(context.qcPageAllOperationLinesComplete(pitPlusCompleteVehicle), true, 'deferred PIT cannot block sign-off after genuine work is complete');

const retestSourceIds = Array.from({ length: 17 }, (_, index) => `${String(index + 1).padStart(8, '0')}-1111-4111-8111-${String(index + 1).padStart(12, '0')}`);
const deferredPitRetest = {
  __emailVehicleServerAuthoritative: true,
  __emailVehicleId: '22222222-2222-4222-8222-222222222222',
  __emailVehicleVersion: 3,
  pdcQcRetestCycleId: '33333333-3333-4333-8333-333333333333',
  pdcQcRetestFreshCycleOpen: true,
  pdcEmailOperationLines: retestSourceIds.map((id, index) => ({ operation_line_id: id, work_key: index === 0 ? 'pitInspection' : 'fitting' })),
  pdcQcOperationLines: retestSourceIds.map((id, index) => ({
    lineIdentity: `source:${id}`,
    sourceKind: 'authenticated',
    sourceLineId: id,
    operationNo: `OP${index + 1}`,
    stageCode: index === 0 ? 'UNALLOCATED_MAPPING_REVIEW' : 'FITTING',
    estimatedHours: index === 0 ? 0 : 1,
    completed: index !== 0,
    active: true,
  })),
};
assert.strictEqual(context.qcPageOperationLines(deferredPitRetest).length, 16, 'retest exposes sixteen genuine checkable lines and retains deferred PIT only in raw evidence');
assert.strictEqual(context.qcPagePhotoDisabledReason(deferredPitRetest, 'retest'), '', 'raw 17-line retest cardinality stays valid while deferred PIT is excluded from completion');

console.log('Deferred PIT QC detail regression: PASS');
