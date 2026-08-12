'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const planner = require('./workshop-planner.js');

const appSource = fs.readFileSync('app.js', 'utf8');

function extractSimpleFunction(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} is missing`);
  const brace = appSource.indexOf('{', start);
  let depth = 0;
  for (let index = brace; index < appSource.length; index += 1) {
    if (appSource[index] === '{') depth += 1;
    if (appSource[index] === '}') depth -= 1;
    if (depth === 0) return appSource.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const context = {
  cleanNavisionText: value => String(value || '').trim(),
  normalizePmbStage: value => String(value || '').trim().toUpperCase(),
  normalizePmbBayNumber: (value, stage) => stage && Number(value) > 0 ? String(Number(value)) : '',
};
vm.createContext(context);
vm.runInContext(`${extractSimpleFunction('partsMovementOverrideRoleAllowed')}\n${extractSimpleFunction('pmbPhysicalBayEntry')}`, context);

assert.strictEqual(context.partsMovementOverrideRoleAllowed('Manager'), true, 'Manager must be allowed to provide an override');
assert.strictEqual(context.partsMovementOverrideRoleAllowed('System Administrator'), true, 'Administrator must be allowed to provide an override');
assert.strictEqual(context.partsMovementOverrideRoleAllowed('Fitting'), false, 'Ordinary workshop roles must remain blocked');
assert.strictEqual(context.partsMovementOverrideRoleAllowed('Parts'), false, 'Parts role alone must not bypass the manager/admin gate');

assert.strictEqual(context.pmbPhysicalBayEntry('FITTING', '', 'FITTING', '2'), true, 'Same-stage no-bay to numbered-bay must count as physical entry');
assert.strictEqual(context.pmbPhysicalBayEntry('FITTING', '1', 'FITTING', '2'), false, 'Moving between bays in the same occupied station is not a fresh station entry');
assert.strictEqual(context.pmbPhysicalBayEntry('HOIST', '1', 'FITTING', '2'), true, 'Changing physical stations must count as physical entry');
assert.strictEqual(context.pmbPhysicalBayEntry('FITTING', '', 'FITTING', ''), false, 'Queue/no-bay assignment must not count as physical entry');

const priorOperationalBlock = {
  pdcBlocked: true,
  pdcBlockReason: 'Parts supplier hold',
};
const plan = { id: 'FITTING::vehicle-1' };
const owned = planner.workshopOwnedBlockUpdates(plan, 'Workshop rework', '2026-07-14T08:00:00.000Z', 'CW');
assert.strictEqual(owned.pdcWorkshopBlockPlanId, plan.id);
assert.strictEqual(owned.pdcWorkshopBlockReason, 'Workshop rework');
assert.strictEqual(priorOperationalBlock.pdcBlockReason, 'Parts supplier hold', 'Creating a planner blocker must not overwrite an unrelated blocker');

const mismatchedClear = planner.workshopOwnedBlockClearUpdates(
  { id: 'OTHER::vehicle-1' },
  { ...priorOperationalBlock, ...owned },
  '2026-07-14T09:00:00.000Z',
  'CW',
);
assert.deepStrictEqual(mismatchedClear, {}, 'Resume may not clear a blocker owned by another plan');
const matchingClear = planner.workshopOwnedBlockClearUpdates(
  plan,
  { ...priorOperationalBlock, ...owned },
  '2026-07-14T09:00:00.000Z',
  'CW',
);
assert.strictEqual(matchingClear.pdcWorkshopBlocked, false, 'Resume must clear its exact planner-owned blocker');
assert.ok(!Object.prototype.hasOwnProperty.call(matchingClear, 'pdcBlocked'), 'Planner resume must not clear the unrelated operational blocker field');
assert.ok(!Object.prototype.hasOwnProperty.call(matchingClear, 'pdcBlockReason'), 'Planner resume must not clear the unrelated operational reason');

const rollbackVehicle = { id: 'vehicle-rollback', pmbStage: 'FITTING', pdcBlockReason: 'Existing operational block' };
let rollbackAlert = '';
global.window = { alert: message => { rollbackAlert = String(message); } };
global.runStorageTransaction = (_label, _keys, operation) => operation();
const rollbackResult = planner.workshopRunVehiclePlanTransaction('Rollback behavior check', rollbackVehicle, () => {
  rollbackVehicle.pmbStage = 'HOIST';
  rollbackVehicle.newUnsafeField = 'partial write';
  throw new Error('simulated storage failure');
});
assert.strictEqual(rollbackResult, false, 'Failed multi-key workflow transaction must report failure');
assert.deepStrictEqual(rollbackVehicle, { id: 'vehicle-rollback', pmbStage: 'FITTING', pdcBlockReason: 'Existing operational block' }, 'Failed transaction must restore in-memory vehicle state');
assert.ok(rollbackAlert.includes('simulated storage failure'), 'Failed transaction must notify the operator');
delete global.runStorageTransaction;
delete global.window;

const confirmStart = appSource.indexOf('function confirmPartsIncompleteMovement(');
const confirmEnd = appSource.indexOf('async function movePmbVehicleToStage(');
const confirmSource = appSource.slice(confirmStart, confirmEnd);
assert.ok(!confirmSource.includes('recordVehicleAudit('), 'The override dialog must not write an audit before the bay movement commits');
assert.ok(!confirmSource.includes('saveVehicleEdits('), 'The override dialog must not mutate vehicle state before the bay movement commits');
assert.ok(appSource.includes("window.PDC_AUTH_CONTEXT?.displayName || window.PDC_AUTH_CONTEXT?.email || localStorage.getItem(OPERATOR_NAME_KEY)"), 'Parts-gated tile movement must use the authenticated operator identity before legacy browser-local fallback');
assert.ok(appSource.includes("window.PDC_AUTH_CONTEXT?.role || localStorage.getItem(OPERATOR_ROLE_KEY)"), 'Authenticated Administrator authority must take precedence over stale or missing browser-local operator roles');
assert.ok(appSource.includes("if (partsDecision === null) return;"), 'Cancelled override must return before mutation');
assert.ok(appSource.includes("runStorageTransaction('Assign vehicle to PMB bay', [EDITS_KEY, AUDIT_LOG_KEY, ...extraTransactionKeys]"), 'Bay assignment, override audit and vehicle edits must share one transaction');
assert.ok(appSource.includes("recordVehicleAudit(vehicle, 'Parts-incomplete movement override', partsDecision.audit)"), 'Approved override reason must be audited during the committed movement');
assert.ok(appSource.includes('const vehicle = selectedVehicle(cleanKey);'), 'Bay movement must use fail-closed vehicle lookup');

console.log('Workshop safety follow-up behavior checks passed');
