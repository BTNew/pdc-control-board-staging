'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const appPath = path.join(__dirname, 'app.js');
const appSource = fs.readFileSync(appPath, 'utf8');
const start = appSource.indexOf('let VEHICLE_LIFECYCLE_OPERATION_GENERATION = 0;');
const end = appSource.indexOf('function vehicleLifecycleAdministratorActive()', start);
assert.ok(start >= 0 && end > start, 'authority-owner helper block is present');
const helperSource = appSource.slice(start, end);

let token = 'token-a';
const actionsA = {};
const actionsB = {};
const context = {
  window: {
    PDC_AUTH_CONTEXT: { userId: 'Operator-A', role: 'Technician' },
    PDC_SUPABASE_CONFIG: {},
    __vehicleLifecycleActions: actionsA,
  },
  getPdcSupabaseAccessToken: () => token,
  vehicleLifecycleSharedModeActive: () => true,
  vehicleLifecycleSharedModeEnabled: () => true,
};
vm.createContext(context);
vm.runInContext(helperSource, context, { filename: 'app-authority-owner.js' });
const evaluate = expression => vm.runInContext(expression, context);

const ownerToken = evaluate('beginVehicleLifecycleOperation()');
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(ownerToken), true, 'owner starts current');
token = 'token-b';
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(ownerToken), false, 'token replacement invalidates owner');

token = 'token-b';
context.window.PDC_AUTH_CONTEXT = { userId: 'Operator-A', role: 'Administrator' };
const ownerPrincipal = evaluate('beginVehicleLifecycleOperation()');
context.window.PDC_AUTH_CONTEXT = { userId: 'Operator-B', role: 'Administrator' };
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(ownerPrincipal), false, 'principal replacement invalidates owner');

context.window.PDC_AUTH_CONTEXT = { userId: 'Operator-B', role: 'Administrator' };
const ownerRole = evaluate('beginVehicleLifecycleOperation()');
context.window.PDC_AUTH_CONTEXT = { userId: 'Operator-B', role: 'Technician' };
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(ownerRole), false, 'role demotion invalidates owner');

context.window.PDC_AUTH_CONTEXT = { userId: 'Operator-B', role: 'Technician' };
const ownerActions = evaluate('beginVehicleLifecycleOperation()');
context.window.__vehicleLifecycleActions = actionsB;
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(ownerActions), false, 'action bridge replacement invalidates owner');

context.window.__vehicleLifecycleActions = actionsA;
const olderOwner = evaluate('beginVehicleLifecycleOperation()');
const newerOwner = evaluate('beginVehicleLifecycleOperation()');
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(olderOwner), false, 'new operation replaces older operation owner');
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(newerOwner), true, 'new operation remains current');
evaluate('invalidateVehicleLifecycleOperations')();
assert.strictEqual(evaluate('vehicleLifecycleOperationCurrent')(newerOwner), false, 'explicit auth invalidation revokes operation owner');
assert.strictEqual(
  evaluate('vehicleLifecycleCompletionStale')({ generation: -1 }, { error: 'stale_authority' }),
  true,
  'transport stale-authority result is always suppressed',
);

const mutationAwaitPattern = /await lifecycleOwner\.actions(?:\.[A-Za-z0-9_]+|\[[^\]]+\])\([^;]+;/g;
const mutationAwaits = [...appSource.matchAll(mutationAwaitPattern)];
assert.ok(mutationAwaits.length >= 8, 'all lifecycle mutation families use a captured action owner');
for (const match of mutationAwaits) {
  const following = appSource.slice(match.index + match[0].length, match.index + match[0].length + 220);
  assert.match(following, /vehicleLifecycleCompletionStale\(lifecycleOwner, result\)/, `mutation at byte ${match.index} checks stale completion immediately`);
}
assert.doesNotMatch(appSource, /await window\.__vehicleLifecycleActions(?:\.|\[)/, 'no lifecycle RPC awaits read the replaceable global action bridge');

const removeVehicleSource = appSource.slice(
  appSource.indexOf('async function removeVehicle('),
  appSource.indexOf('function renderDetail()', appSource.indexOf('async function removeVehicle(')),
);
assert.match(removeVehicleSource, /window\.confirm\([\s\S]*?vehicleLifecycleOperationCurrent\(lifecycleOwner\)[\s\S]*?window\.prompt\([\s\S]*?vehicleLifecycleOperationCurrent\(lifecycleOwner\)[\s\S]*?window\.prompt\([\s\S]*?vehicleLifecycleOperationCurrent\(lifecycleOwner\)[\s\S]*?adminArchiveVehicle\([\s\S]*?,\s*lifecycleOwner\)/, 'delete dialogs revalidate and bind the pre-dialog owner');
const deletedAdminSource = appSource.slice(
  appSource.indexOf('async function runDeletedVehicleAdminAction('),
  appSource.indexOf('function renderDeletedVehicles()', appSource.indexOf('async function runDeletedVehicleAdminAction(')),
);
assert.ok(deletedAdminSource.indexOf('beginVehicleLifecycleOperation()') < deletedAdminSource.indexOf('window.confirm('), 'deleted-vehicle owner is captured before dialogs');
assert.match(deletedAdminSource, /actions\[method\]\([\s\S]*?,\s*lifecycleOwner\)/, 'restore/recreation dispatch is bound to the pre-dialog owner');
assert.ok((deletedAdminSource.match(/vehicleLifecycleOperationCurrent\(lifecycleOwner\)/g) || []).length >= 7, 'restore/recreation revalidates after every blocking dialog and before dispatch');

for (const [fnName, actionName] of [
  ['markVehicleReadyForQualityControl', 'markReadyForQc'],
  ['completeVehicleQualityControl', 'qcSignoffToRft'],
  ['moveVehiclePitLocation', 'pitTransferVehicle'],
  ['markRftVehicleCollected', 'rftCollectVehicle'],
]) {
  const fnStart = appSource.indexOf(`async function ${fnName}(`);
  assert.ok(fnStart >= 0, `${fnName} exists`);
  const nextAsync = appSource.indexOf('\nasync function ', fnStart + 1);
  const nextPlain = appSource.indexOf('\nfunction ', fnStart + 1);
  const candidates = [nextAsync, nextPlain].filter(index => index > fnStart);
  const fnEnd = candidates.length ? Math.min(...candidates) : appSource.length;
  const fnSource = appSource.slice(fnStart, fnEnd);
  const lifecycleCapturePattern = /(?:const lifecycleOwner = beginVehicleLifecycleOperation\(\);|const lifecycleOwner = vehicleLifecycleSharedModeActive\(\) \? beginVehicleLifecycleOperation\(\) : null;|let lifecycleOwner = null;[\s\S]*?lifecycleOwner = beginVehicleLifecycleOperation\(\);)/;
  const beginMatch = fnSource.match(lifecycleCapturePattern);
  const beginIndex = beginMatch ? beginMatch.index : -1;
  const confirmIndex = fnSource.indexOf('window.confirm(');
  const dispatchIndex = fnSource.indexOf(`lifecycleOwner.actions.${actionName}(`);
  assert.ok(confirmIndex >= 0, `${fnName} has confirm dialog`);
  assert.ok(beginIndex >= 0, `${fnName} captures lifecycle owner`);
  assert.ok(beginIndex < confirmIndex, `${fnName} captures lifecycle owner before confirm`);
  assert.ok(dispatchIndex > confirmIndex, `${fnName} dispatch stays after confirm`);
  const between = fnSource.slice(beginIndex, dispatchIndex);
  assert.match(between, /window\.confirm\([\s\S]*?vehicleLifecycleOperationCurrent\(lifecycleOwner\)/, `${fnName} revalidates lifecycle owner immediately after confirm`);
}

console.log(`PASS: lifecycle UI authority owner covers ${mutationAwaits.length} mutation await sites`);
