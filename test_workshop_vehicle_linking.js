'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const planner = require('./workshop-planner.js');
const { buildVehicleLifecycleIdentityInput } = require('./vehicle-lifecycle-actions.js');
const plannerSource = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');

assert.ok(plannerSource.includes('const vehicleRef = await workshopVerifiedCanonicalVehicleRef(vehicle);'), 'Scheduling must verify a saved canonical link');
assert.ok(plannerSource.includes('A newly saved link deliberately requires a second scheduling action'), 'Link save must not schedule');
assert.ok(!plannerSource.includes('const vehicleRef = workshopSharedVehicleRef(vehicleKey(vehicle));'), 'No legacy snapshot fallback is allowed');
assert.ok(!plannerSource.includes('p_stock_number: vehicle.stock || vehicle.stockNumber'), 'No manual identity-builder fallback is allowed');
assert.ok(plannerSource.includes('This vehicle is not yet linked to one shared vehicle record. No change was made.'), 'Exact refusal must remain');

global.buildVehicleLifecycleIdentityInput = buildVehicleLifecycleIdentityInput;

const vehicle = {
  id: 'navision-12660174',
  stock: '12660174',
  vin: 'MR0REBHVX00537433',
  order: '250040006',
  pdcJobcard: '',
};
const uuid = '6fb66a8f-7e50-48aa-a846-f05f06616ab4';
const otherUuid = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const resolvedResult = {
  outcome: 'resolved', vehicleId: uuid, version: 3,
  resolverRevision: 42, matchedBy: ['stock_number', 'vin'], isArchived: false,
};

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); },
  };
}

function resolverWith(combined) {
  return { resolve: async () => combined };
}

(async () => {
  const input = planner.workshopVehicleLinkIdentityInput(vehicle);
  assert.deepStrictEqual(input, {
    p_stock_number: '12660174',
    p_vin: 'MR0REBHVX00537433',
    p_toyota_order_number: '250040006',
    p_source_system: 'browser_local_c4',
  });
  assert.strictEqual(input.p_vehicle_id, undefined);

  delete global.buildVehicleLifecycleIdentityInput;
  const unavailableInput = planner.workshopVehicleLinkIdentityInput(vehicle);
  assert.strictEqual(unavailableInput.__resolverBuilderMissing, true);
  assert.deepStrictEqual(Object.keys(unavailableInput), []);
  let resolverCalled = false;
  const builderMissing = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, { async resolve() { resolverCalled = true; } });
  assert.strictEqual(builderMissing.outcome, 'service_unavailable');
  assert.match(builderMissing.rejectedReason, /approved_identity_builder_missing/);
  assert.strictEqual(resolverCalled, false);
  global.buildVehicleLifecycleIdentityInput = () => { throw new Error('builder failed'); };
  const builderThrew = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult));
  assert.strictEqual(builderThrew.outcome, 'service_unavailable');
  assert.match(builderThrew.rejectedReason, /approved_identity_builder_threw/);
  global.buildVehicleLifecycleIdentityInput = () => null;
  const builderMalformed = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult));
  assert.strictEqual(builderMalformed.outcome, 'service_unavailable');
  assert.match(builderMalformed.rejectedReason, /approved_identity_builder_invalid_result/);
  global.buildVehicleLifecycleIdentityInput = buildVehicleLifecycleIdentityInput;
  const approvedProbes = planner.workshopVehicleLinkProbeInputs(vehicle, input);
  assert.deepStrictEqual(approvedProbes.map(probe => probe.identifier), ['stock_number', 'vin', 'toyota_order_number']);
  assert.deepStrictEqual(approvedProbes[0].input, planner.workshopVehicleLinkIdentityInput({ stock: input.p_stock_number }));
  assert.deepStrictEqual(approvedProbes[2].input, planner.workshopVehicleLinkIdentityInput({ toyotaOrderNumber: input.p_toyota_order_number, sourceSystem: input.p_source_system }));
  global.buildVehicleLifecycleIdentityInput = source => {
    if (source.stock && !source.vin && !source.order && !source.toyotaOrderNumber && !source.sharedVehicleId) return null;
    return buildVehicleLifecycleIdentityInput(source);
  };
  const failedProbeBuilder = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult));
  assert.strictEqual(failedProbeBuilder.outcome, 'service_unavailable');
  assert.match(failedProbeBuilder.rejectedReason, /approved_identity_builder_invalid_result/);
  global.buildVehicleLifecycleIdentityInput = buildVehicleLifecycleIdentityInput;

  const invalidInput = planner.workshopVehicleLinkIdentityInput({ stock: 'STOCK-A', stockNumber: 'STOCK-B', vin: vehicle.vin });
  assert.strictEqual(invalidInput.__invalidIdentityField, 'stock_number');
  const invalidDiagnostic = await planner.workshopResolveVehicleLinkDiagnostic({ stock: 'STOCK-A', stockNumber: 'STOCK-B', vin: vehicle.vin }, resolverWith(resolvedResult));
  assert.strictEqual(invalidDiagnostic.outcome, 'invalid_input');
  assert.strictEqual(invalidDiagnostic.linkState, 'rejected');
  const unstable = await planner.workshopResolveVehicleLinkDiagnostic({ stock: '12660174' }, resolverWith(resolvedResult));
  assert.strictEqual(unstable.outcome, 'unstable_identity');
  assert.match(unstable.exactRemediation, /stock number alone is not a durable edit key/i);

  const missing = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith({ outcome: 'not_found' }));
  assert.strictEqual(missing.browserLocalIdentity.stockNumber, '12660174');
  assert.strictEqual(missing.sharedUuid, null);
  assert.strictEqual(missing.outcome, 'not_found');
  assert.match(missing.exactRemediation, /approved Stage 2B importer/i);
  assert.deepStrictEqual(missing.candidateProcess.map(item => item.identifier), ['stock_number', 'vin', 'toyota_order_number']);
  const missingRows = Object.fromEntries(planner.workshopVehicleLinkDisplayRows(missing));
  assert.strictEqual(missingRows['Shared vehicle UUID'], 'Missing');
  assert.match(missingRows['Refusal reason'], /^Not found/);
  assert.strictEqual(missingRows['Saved shared UUID'], 'Not saved');
  assert.strictEqual(missingRows['Resolved shared UUID'], 'Missing');

  const partialMissing = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, {
    async resolve(probe) {
      if (probe.p_stock_number && !probe.p_vin && !probe.p_toyota_order_number && !probe.p_vehicle_id) return { outcome: 'not_found' };
      return resolvedResult;
    },
  });
  assert.strictEqual(partialMissing.outcome, 'conflict');
  assert.match(partialMissing.rejectedReason, /do_not_all_resolve|do_not_converge/);
  const ambiguousProbe = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, {
    async resolve(probe) {
      if (probe.p_vin && !probe.p_stock_number && !probe.p_toyota_order_number && !probe.p_vehicle_id) return { outcome: 'ambiguous', candidateCount: 2 };
      return resolvedResult;
    },
  });
  assert.strictEqual(ambiguousProbe.outcome, 'ambiguous');
  assert.strictEqual(ambiguousProbe.linkState, 'rejected');

  const resolved = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult));
  assert.strictEqual(resolved.outcome, 'resolved');
  assert.strictEqual(resolved.sharedUuid, uuid);
  assert.strictEqual(resolved.linkState, 'ready_to_save');

  const storage = memoryStorage();
  const corruptStorage = memoryStorage();
  corruptStorage.setItem('workshopCanonicalVehicleLinks:v1', '{broken');
  const corruptDiagnostic = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult), corruptStorage);
  assert.strictEqual(corruptDiagnostic.outcome, 'service_unavailable');
  assert.match(corruptDiagnostic.rejectedReason, /browser_local_link_store_invalid/);
  const malformedEntryStorage = memoryStorage();
  malformedEntryStorage.setItem('workshopCanonicalVehicleLinks:v1', JSON.stringify({ entries: { bad: { sharedVehicleId: uuid } } }));
  const malformedEntryDiagnostic = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult), malformedEntryStorage);
  assert.strictEqual(malformedEntryDiagnostic.outcome, 'service_unavailable');
  assert.match(malformedEntryDiagnostic.rejectedReason, /browser_local_link_store_invalid/);
  let saved = null;
  const persisted = planner.workshopPersistVerifiedCanonicalLink(vehicle, resolved, (key, updates, options) => {
    saved = { key, updates, options };
    Object.assign(vehicle, updates);
    return true;
  }, storage);
  assert.strictEqual(persisted, true);
  assert.strictEqual(saved.key, '12660174');
  assert.strictEqual(saved.updates.sharedVehicleId, uuid);
  assert.strictEqual(saved.updates.sharedVehicleLinkSource, 'browser_local_c4');
  assert.strictEqual(saved.updates.sharedVehicleLinkVehicleVersion, 3);
  assert.strictEqual(saved.updates.sharedVehicleLinkResolverRevision, 42);
  assert.deepStrictEqual(saved.options, { render: false });
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink({ ...vehicle }, { ...resolved, version: 0 }, () => true, memoryStorage()), false);
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink({ ...vehicle }, { ...resolved, sharedUuid: 12345 }, () => true, memoryStorage()), false);
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink({ ...vehicle }, { ...resolved, matchedBy: [] }, () => true, memoryStorage()), false);
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink({ ...vehicle }, { ...resolved, matchedBy: ['vin', 'vin'] }, () => true, memoryStorage()), false);
  const invalidAliasStorage = memoryStorage();
  const invalidAliasStore = JSON.parse(storage.getItem('workshopCanonicalVehicleLinks:v1'));
  const invalidAliasKey = Object.keys(invalidAliasStore.entries)[0];
  invalidAliasStore.entries[invalidAliasKey].aliases = ['guessed:value'];
  invalidAliasStorage.setItem('workshopCanonicalVehicleLinks:v1', JSON.stringify(invalidAliasStore));
  const invalidAliasDiagnostic = await planner.workshopResolveVehicleLinkDiagnostic(vehicle, resolverWith(resolvedResult), invalidAliasStorage);
  assert.strictEqual(invalidAliasDiagnostic.outcome, 'service_unavailable');

  const transitioned = { ...vehicle, stock: '12660999' };
  delete transitioned.sharedVehicleId;
  const storedAfterKeyChange = planner.workshopLookupStoredVehicleLink(transitioned, storage);
  assert.strictEqual(storedAfterKeyChange.outcome, 'resolved');
  assert.strictEqual(storedAfterKeyChange.entry.sharedVehicleId, uuid);
  const verifiedAfterKeyChange = await planner.workshopResolveVehicleLinkDiagnostic(transitioned, resolverWith({ ...resolvedResult, matchedBy: ['vehicle_id', 'vin'] }), storage);
  assert.strictEqual(verifiedAfterKeyChange.linkState, 'verified');
  assert.strictEqual(verifiedAfterKeyChange.sharedUuid, uuid);

  global.window = { PDC_AUTH_CONTEXT: { role: 'viewer' }, localStorage: storage };
  assert.strictEqual(planner.workshopVehicleLinkCanPersist(), false);
  let viewerSaveCalled = false;
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink({ ...vehicle, sharedVehicleId: '' }, resolved, () => { viewerSaveCalled = true; }, storage), false);
  assert.strictEqual(viewerSaveCalled, false);
  global.window.PDC_AUTH_CONTEXT.role = 'operator';
  assert.strictEqual(planner.workshopVehicleLinkCanPersist(), true);
  delete global.window;

  const malformedSummary = planner.workshopVehicleLinkResultSummary({ outcome: 'resolved', vehicleId: 'not-a-uuid', version: 0, resolverRevision: 0, isArchived: false });
  assert.strictEqual(malformedSummary.outcome, 'service_unavailable');
  const coercedSummary = planner.workshopVehicleLinkResultSummary({ ...resolvedResult, version: '3', resolverRevision: '42' });
  assert.strictEqual(coercedSummary.outcome, 'service_unavailable');
  assert.strictEqual(planner.workshopVehicleLinkResultSummary({ ...resolvedResult, matchedBy: [] }).outcome, 'service_unavailable');
  assert.strictEqual(planner.workshopVehicleLinkResultSummary({ ...resolvedResult, matchedBy: ['vin', 'vin'] }).outcome, 'service_unavailable');
  const nullSummary = planner.workshopVehicleLinkResultSummary(null);
  assert.strictEqual(nullSummary.outcome, 'service_unavailable');
  const unknownSummary = planner.workshopVehicleLinkResultSummary({ outcome: 'surprise' });
  assert.strictEqual(unknownSummary.outcome, 'service_unavailable');

  const malformed = await planner.workshopResolveVehicleLinkDiagnostic({ ...vehicle, sharedVehicleId: '' }, resolverWith({ outcome: 'resolved', vehicleId: 'bad', version: 'nope', resolverRevision: 0, isArchived: false }));
  assert.strictEqual(malformed.outcome, 'service_unavailable');
  assert.strictEqual(malformed.linkState, 'rejected');
  const nullResult = await planner.workshopResolveVehicleLinkDiagnostic({ ...vehicle, sharedVehicleId: '' }, resolverWith(null));
  assert.strictEqual(nullResult.outcome, 'service_unavailable');
  const thrown = await planner.workshopResolveVehicleLinkDiagnostic({ ...vehicle, sharedVehicleId: '' }, { async resolve() { throw new Error('resolver down'); } });
  assert.strictEqual(thrown.outcome, 'service_unavailable');
  assert.match(thrown.exactRemediation, /no fallback or guessed link/i);

  const archived = await planner.workshopResolveVehicleLinkDiagnostic({ ...vehicle, sharedVehicleId: '' }, resolverWith({ ...resolvedResult, isArchived: true }));
  assert.strictEqual(archived.outcome, 'archived');
  assert.strictEqual(archived.linkState, 'rejected');
  assert.strictEqual(archived.sharedUuid, null);
  assert.match(archived.exactRemediation, /archived/i);
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink(vehicle, archived, () => true, memoryStorage()), false);
  const archivedSaved = await planner.workshopResolveVehicleLinkDiagnostic({ ...vehicle, sharedVehicleId: uuid }, resolverWith({ ...resolvedResult, isArchived: true }));
  assert.strictEqual(archivedSaved.linkState, 'rejected');

  const conflicting = await planner.workshopResolveVehicleLinkDiagnostic(
    { ...vehicle, sharedVehicleId: otherUuid },
    resolverWith({ outcome: 'conflict', reason: 'conflicting_identifiers', candidateCount: 2 }),
  );
  assert.strictEqual(conflicting.outcome, 'conflict');
  assert.strictEqual(conflicting.linkState, 'rejected');
  assert.strictEqual(planner.workshopPersistVerifiedCanonicalLink(vehicle, conflicting, () => true, memoryStorage()), false);

  const ambiguous = await planner.workshopResolveVehicleLinkDiagnostic(
    { ...vehicle, sharedVehicleId: '' },
    resolverWith({ outcome: 'ambiguous', reason: 'multiple_normalized_matches', candidateCount: 2 }),
  );
  assert.strictEqual(ambiguous.outcome, 'ambiguous');
  assert.strictEqual(ambiguous.candidateCount, 2);

  for (const postSaveFailure of ['conflict', 'archived', 'service_unavailable']) {
    const rollbackVehicle = { id: vehicle.id, stock: vehicle.stock, vin: vehicle.vin, order: vehicle.order };
    const rollbackStorage = memoryStorage();
    const originalEdits = JSON.stringify({ unrelated: { note: 'keep' } });
    rollbackStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', originalEdits);
    let afterSave = false;
    const rollbackResolver = {
      async resolve() {
        if (!afterSave) return resolvedResult;
        if (postSaveFailure === 'service_unavailable') throw new Error('resolver offline after save');
        if (postSaveFailure === 'archived') return { ...resolvedResult, isArchived: true };
        return { outcome: 'conflict', reason: 'identity_changed_after_save', candidateCount: 2 };
      },
    };
    const rollbackResult = await planner.workshopVerifiedCanonicalVehicleRef(rollbackVehicle, {
      resolver: rollbackResolver,
      storage: rollbackStorage,
      modalFn: async diagnostic => diagnostic.linkState === 'ready_to_save' ? 'save' : 'close',
      saveFn: (key, updates) => {
        Object.assign(rollbackVehicle, updates);
        const edits = JSON.parse(rollbackStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1') || '{}');
        edits[key] = { ...(edits[key] || {}), ...updates };
        rollbackStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', JSON.stringify(edits));
        afterSave = true;
        return true;
      },
    });
    assert.strictEqual(rollbackResult.ok, false);
    assert.strictEqual(rollbackResult.error, 'conflicting_vehicle_identity_rolled_back');
    assert.match(rollbackResult.diagnostic.rejectedReason, /new_link_rolled_back/);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(rollbackVehicle, 'sharedVehicleId'), false);
    assert.strictEqual(rollbackStorage.getItem('workshopCanonicalVehicleLinks:v1'), null);
    assert.strictEqual(rollbackStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'), originalEdits);
  }

  const concurrentVehicle = { id: vehicle.id, stock: vehicle.stock, vin: vehicle.vin, order: vehicle.order };
  const concurrentStorage = memoryStorage();
  const concurrentReceipt = {};
  const concurrentSaved = planner.workshopPersistVerifiedCanonicalLink(concurrentVehicle, resolved, (key, updates) => {
    Object.assign(concurrentVehicle, updates);
    concurrentStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', JSON.stringify({ [key]: updates }));
    return true;
  }, concurrentStorage, concurrentReceipt);
  assert.strictEqual(concurrentSaved, true);
  const persistedLinkLayer = concurrentStorage.getItem('workshopCanonicalVehicleLinks:v1');
  concurrentStorage.setItem('vehicleTrackingCoreNavisionOnlyEdits:v1', 'concurrent-edits');
  assert.strictEqual(planner.workshopRollbackPersistedCanonicalLink(concurrentReceipt), false);
  assert.strictEqual(concurrentStorage.getItem('workshopCanonicalVehicleLinks:v1'), persistedLinkLayer);
  assert.strictEqual(concurrentStorage.getItem('vehicleTrackingCoreNavisionOnlyEdits:v1'), 'concurrent-edits');
  assert.strictEqual(concurrentVehicle.sharedVehicleId, uuid);

  const flowVehicle = { id: vehicle.id, stock: vehicle.stock, vin: vehicle.vin, order: vehicle.order };
  const flowStorage = memoryStorage();
  let modalCalls = 0;
  let saveCalls = 0;
  const flowOptions = {
    resolver: resolverWith(resolvedResult),
    storage: flowStorage,
    modalFn: async diagnostic => {
      modalCalls += 1;
      return diagnostic.linkState === 'ready_to_save' ? 'save' : 'close';
    },
    saveFn: (key, updates) => {
      saveCalls += 1;
      Object.assign(flowVehicle, updates);
      return true;
    },
  };
  const firstFlow = await planner.workshopVerifiedCanonicalVehicleRef(flowVehicle, flowOptions);
  assert.strictEqual(firstFlow.ok, false);
  assert.strictEqual(firstFlow.error, 'vehicle_link_saved_retry');
  assert.strictEqual(saveCalls, 1);
  assert.strictEqual(modalCalls, 2);
  const secondFlow = await planner.workshopVerifiedCanonicalVehicleRef(flowVehicle, flowOptions);
  assert.strictEqual(secondFlow.ok, true);
  assert.strictEqual(secondFlow.vehicleId, uuid);
  assert.strictEqual(saveCalls, 1);
  assert.strictEqual(modalCalls, 2);

  const plannerSource = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
  assert.ok(plannerSource.includes('This vehicle is not yet linked to one shared vehicle record. No change was made.'));
  assert.ok(plannerSource.includes('buildVehicleLifecycleIdentityInput({ ...vehicle, sourceSystem })'));
  assert.ok(!plannerSource.includes("add('stock_number', input.p_stock_number, { p_stock_number:"));
  assert.ok(!plannerSource.includes('workshopSharedVehicleRef(vehicleKey(vehicle))'));

  console.log('Workshop controlled vehicle-linking tests passed.');
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
}).finally(() => {
  delete global.buildVehicleLifecycleIdentityInput;
  delete global.window;
});
