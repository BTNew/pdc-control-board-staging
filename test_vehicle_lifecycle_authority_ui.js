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

console.log(`PASS: lifecycle UI authority owner covers ${mutationAwaits.length} mutation await sites`);
