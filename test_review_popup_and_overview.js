'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const appSource = fs.readFileSync('app.js', 'utf8');
const functionSource = name => {
  const start = appSource.indexOf('function ' + name + '(');
  assert(start >= 0);
  const end = appSource.indexOf('\nfunction ', start + 10);
  return appSource.slice(start, end < 0 ? undefined : end);
};

test('native dialog owns Tab and Escape without closing or trapping the vehicle popup', () => {
  const start = appSource.indexOf("  document.addEventListener('keydown', (e) => {");
  const end = appSource.indexOf('\n  });', start);
  let handler, nativeOpen = true, trapped = 0, closed = 0;
  const context = {
    document: { addEventListener: (_, fn) => { handler = fn; }, querySelector: () => nativeOpen ? {} : null },
    $: selector => ({ hidden: selector === '#customer-modal' }),
    trapModalFocus: () => { trapped++; },
    closeCustomerModal: () => { throw Error('Wrong popup'); },
    closeVehicleModal: () => { closed++; },
  };
  vm.runInNewContext(appSource.slice(start, end + 6), context);
  handler({ key: 'Tab' }); handler({ key: 'Escape' });
  assert.equal(trapped, 0); assert.equal(closed, 0);
  nativeOpen = false;
  handler({ key: 'Tab' }); handler({ key: 'Escape' });
  assert.equal(trapped, 1); assert.equal(closed, 1);
});

test('loading and unavailable Control Board states do not report zero vehicles or empty work', () => {
  for (const state of ['loading', 'reconnecting', 'offline_error', 'permission_denied']) {
    const host = { innerHTML: '' };
    const context = {
      app: { workshopEligibilityState: state },
      $: selector => selector === '#workflow-board' ? host : null,
      document: { body: { classList: { remove() {} } } },
      workshopEligibilitySharedAuthorityEnabled: () => true,
      escapeHtml: value => String(value),
      pmbVehiclesNeedingStationWork: () => { throw Error('No counts before fresh data'); },
    };
    vm.runInNewContext(functionSource('renderWorkflowBoard'), context);
    context.renderWorkflowBoard();
    assert.match(host.innerHTML, state === 'loading' || state === 'reconnecting' ? /Loading workshop overview/ : /Workshop overview unavailable/);
    assert.doesNotMatch(host.innerHTML, /0 needing work|No PMB vehicles currently need/);
  }
});

test('Navision source count is labeled separately from the complete board population', () => {
  const context = {
    app: { sharedNavisionVisibleState: 'ready', vehicleLocationsRefreshState: 'idle', sharedNavisionVisibleRealtimeState: 'subscribed', sharedNavisionVisibleRealtimeReconciled: true },
    window: { PDC_AUTH_CONTEXT: {} }, sharedNavisionVisibilityConfigured: () => true,
    activeSharedNavisionRows: () => [{ board_activated: false }, { board_activated: true }],
    escapeHtml: value => String(value),
  };
  vm.runInNewContext(functionSource('sharedNavisionLocationsStatusHtml'), context);
  const html = context.sharedNavisionLocationsStatusHtml();
  assert.match(html, /2 Navision source records/);
  assert.match(html, /approved job imports also appear on this board/);
});

test('booking navigation replaces a pending open-today intent while normal planner entry keeps it', () => {
  const start = appSource.indexOf('  const focusedWorkshopIntent =');
  const end = appSource.indexOf('\n', appSource.indexOf('if (enteringWorkshopPlanner && !focusedWorkshopIntent)', start));
  const source = appSource.slice(start, end);
  for (const mode of ['focused', 'search', 'ordinary']) {
    const context = { app: { pendingWorkshopOpenToday: true, pendingWorkshopBookingLink: mode === 'ordinary' ? null : { [mode]: true } }, nextView: 'workshop', switchingPlannerStation: true, enteringWorkshopPlanner: true };
    vm.runInNewContext(source, context);
    assert.equal(context.app.pendingWorkshopOpenToday, mode === 'ordinary');
    if (mode !== 'ordinary') assert.equal(context.app.pendingWorkshopBookingLink[mode], true);
  }
});
