'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const plannerSource = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');

function functionBlock(source, name, nextName) {
  const start = source.indexOf(`function ${name}`);
  const end = source.indexOf(`\nfunction ${nextName}`, start + 1);
  assert(start >= 0 && end > start, `Could not extract ${name}`);
  return source.slice(start, end);
}

// Confirm/apply must give immediate, accessible feedback and reject repeat clicks.
const applyStart = appSource.indexOf('async function applySharedNavisionImport()');
const applyEnd = appSource.indexOf('\nfunction selectedPendingNavisionUpdateKeys', applyStart);
const applyBlock = appSource.slice(applyStart, applyEnd);
assert(applyBlock.includes('if (app.navisionSharedApplyInFlight === true) return;'));
assert(applyBlock.includes('setNavisionSharedApplyBusy(true)'));
assert(applyBlock.includes('await navisionWaitForBusyPaint()'));
assert(applyBlock.includes('finally'));
assert(applyBlock.includes('setNavisionSharedApplyBusy(false)'));
assert(appSource.includes('aria-busy'));
assert(appSource.includes('Applying Navision import…'));
assert(css.includes('.navision-button-spinner'));
assert(css.includes('@keyframes navision-button-spin'));

// Direct modal opening remains fail-closed while identity authority is loading;
// visible board clicks use the bounded wait helper and never weaken mutation gates.
const authorityContext = {
  console: { warn() {} },
  selectedVehicle: () => ({ id: 'vehicle-1' }),
  sharedNavisionLocationAuthorityReady: () => false,
  vehicleLocationBoardRows: () => [],
};
vm.runInNewContext(functionBlock(appSource, 'vehicleLocationActionAllowed', 'renderSharedNavisionVisibilityState'), authorityContext);
assert.strictEqual(authorityContext.vehicleLocationActionAllowed({ id: 'vehicle-1' }, 'open'), false);
assert.strictEqual(authorityContext.vehicleLocationActionAllowed({ id: 'vehicle-1', __locationIdentityReadOnly: true }, 'open'), false);
assert.strictEqual(authorityContext.vehicleLocationActionAllowed({ id: 'vehicle-1' }, 'change'), false);
assert(appSource.includes('async function openVehicleCardFromVisibleBoard'));
assert(appSource.includes('if (!sharedNavisionVisibilityConfigured()) return false;'));
assert(appSource.includes('Vehicle details are still syncing. Please click the stock number again in a moment.'));
assert(appSource.includes('openVehicleCardFromVisibleBoard(button.dataset.openStock, button)'));

// PMB vehicles with required work and no booking get a warning; booked work gets an estimated finish.
let plans = [];
const projectionContext = {
  pdcJobDefsPartsFirst: () => [{ key: 'fitting' }],
  pdcJobRequired: () => true,
  pdcJobComplete: () => false,
  pmbStageForPdcJob: () => 'FITTING',
  WORKSHOP_PLANNER_ROUTE_BY_STAGE: { FITTING: 'workshop-fitting' },
  workshopLoadPlans: () => plans,
  vehicleWorkshopDetailCanonicalId: () => '11111111-1111-4111-8111-111111111111',
  vehicleKey: () => '12546480',
  normalizePmbStage: value => String(value || '').toUpperCase(),
  workshopEntryEnd: () => new Date('2026-08-12T07:30:00Z'),
  parseIsoTimestamp: value => new Date(value),
  statusCategory: () => 'pmb',
  Date,
  Set,
};
vm.runInNewContext(functionBlock(appSource, 'vehicleWorkshopBookingProjection', 'incomingWorkChecklistHtml'), projectionContext);
let projection = projectionContext.vehicleWorkshopBookingProjection({});
assert.strictEqual(projection.bookingRequired, true);
assert.strictEqual(projection.label, 'Booking required');
assert.deepStrictEqual(Array.from(projection.missingStages), ['FITTING']);
plans = [{ sharedVehicleId: '11111111-1111-4111-8111-111111111111', stage: 'FITTING', status: 'planned', startAt: '2026-08-12T05:30:00Z', hours: 2 }];
projection = projectionContext.vehicleWorkshopBookingProjection({});
assert.strictEqual(projection.bookingRequired, false);
assert.strictEqual(projection.missingStages.length, 0);
assert(projection.label.startsWith('Est. complete '));
assert(appSource.includes('data-workshop-booking-required'));
assert(appSource.includes('Required PMB work is not booked into a workshop bay'));
assert(css.includes('.incoming-work-checks[data-workshop-booking-required="true"]'));

// An unbooked search match must be a button that highlights the candidate lane without creating a booking.
assert(plannerSource.includes('<button type="button" class="workshop-search-result is-unbooked"'));
assert(plannerSource.includes('data-workshop-search-unbooked-identity='));
assert(plannerSource.includes('Select unbooked vehicle'));
assert(!plannerSource.includes('<article class="workshop-search-result is-unbooked"'));
const plannerState = { search: '12546480', searchOpen: true, selectedPlanId: 'old' };
let rendered = 0;
const plannerContext = {
  workshopState: () => plannerState,
  workshopLoadPlans: () => [],
  workshopSearchMatches: () => [{ vehicleIdentity: 'shared:vehicle-1', vehicleKey: '12546480', bookings: [] }],
  workshopSaveView: () => {},
  renderWorkshopPlanner: () => { rendered += 1; },
};
vm.runInNewContext(functionBlock(plannerSource, 'workshopSelectUnbookedSearchVehicle', 'workshopRefreshSearchResults'), plannerContext);
assert.strictEqual(plannerContext.workshopSelectUnbookedSearchVehicle('shared:vehicle-1'), true);
assert.strictEqual(plannerState.highlightVehicleKey, '12546480');
assert.strictEqual(plannerState.searchHighlightPlanId, '');
assert.strictEqual(plannerState.selectedPlanId, '');
assert.strictEqual(plannerState.searchOpen, false);
assert(plannerState.searchNotice.includes('Choose Best slot or Schedule'));
assert.strictEqual(rendered, 1);

console.log('User UI follow-up interaction contracts passed');
