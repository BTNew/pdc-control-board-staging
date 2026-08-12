'use strict';

const assert = require('assert');
const navigation = require('./workshop-navigation');

(function deterministicTileFilters() {
  const input = { stageCode: 'MECH', bayNumber: 3, vehicleId: 'vehicle-7', stockNumber: 'P123' };
  const first = navigation.buildWorkBookingsNavigationIntent(input);
  const second = navigation.buildWorkBookingsNavigationIntent({ ...input });

  assert.deepStrictEqual(first, second, 'identical tiles must produce deterministic navigation intents');
  assert.deepStrictEqual(first, {
    route: 'vehicle-detail',
    view: 'work-bookings',
    tab: 'work-bookings',
    vehicleId: 'vehicle-7',
    stockNumber: 'P123',
    filters: { station: 'MECH', bay: '3' },
  });
  assert.deepStrictEqual(
    navigation.buildWorkBookingsNavigationIntent({ station: 'QC' }).filters,
    { station: 'QC' },
    'missing bay must be omitted rather than serialized as an accidental wildcard',
  );
})();

(function exactStockBookingResolution() {
  const bookings = [
    { id: 'booking-1', stockNumber: 'p123', stageCode: 'MECH', bayNumber: 2, scheduledStartAt: '2026-08-14T08:00:00Z' },
    { id: 'booking-2', stockNumber: 'P123', stageCode: 'MECH', bayNumber: 2, scheduledStartAt: '2026-08-14T10:00:00Z' },
    { id: 'booking-3', stockNumber: 'P123', stageCode: 'MECH', bayNumber: 3, scheduledStartAt: '2026-08-14T10:00:00Z' },
  ];
  const target = navigation.resolveStockResultTarget({
    stock: 'p-ignored',
    stockNumber: 'p123',
    stationCode: 'mech',
    bayNumber: '02',
    bookingDate: '2026-08-14',
    scheduledStartAt: '2026-08-14T10:00:00+00:00',
  }, bookings);

  assert(target, 'an exact date/bay/time locator must resolve');
  assert.strictEqual(target.bookingId, 'booking-2');
  assert.deepStrictEqual(target.filters, { station: 'MECH', bay: '2', date: '2026-08-14' });
  assert.strictEqual(
    navigation.resolveStockResultTarget({ stockNumber: 'P123', date: '2026-08-14' }, bookings),
    null,
    'an ambiguous stock/date result must fail closed',
  );
  assert.strictEqual(
    navigation.resolveStockResultTarget({ stockNumber: 'P123', bay: 9, date: '2026-08-14' }, bookings),
    null,
    'a nonexistent exact booking must fail closed',
  );
})();

(function staleHighlightReplacementAndClear() {
  assert.strictEqual(typeof navigation.replaceWorkshopHighlight, 'function', 'CommonJS runtime must export the DOM highlight bridge');
  const events = [];
  const controller = navigation.createWorkshopHighlightController({
    applyHighlight: (target, state) => events.push(['apply', target, state.pulseClass]),
    clearHighlight: (target, state) => events.push(['clear', target, state.pulseClass]),
  });

  controller.replace('booking-1');
  controller.replace('booking-2');
  assert.deepStrictEqual(events.map(event => event.slice(0, 2)), [
    ['apply', 'booking-1'],
    ['clear', 'booking-1'],
    ['apply', 'booking-2'],
  ], 'a replacement must clear the stale target before applying the next highlight');
  assert.strictEqual(controller.getCurrent().target, 'booking-2');
  controller.clear();
  assert.strictEqual(controller.getCurrent(), null);
  assert.deepStrictEqual(events[3].slice(0, 2), ['clear', 'booking-2']);
})();

(function reducedMotionContract() {
  const normal = navigation.highlightPresentation(false);
  assert.strictEqual(normal.animate, true);
  assert.strictEqual(normal.pulseClass, navigation.WORKSHOP_PULSE_CLASS);

  const reduced = navigation.highlightPresentation({ matches: true });
  assert.strictEqual(reduced.active, true, 'reduced motion must retain a visible highlight');
  assert.strictEqual(reduced.reducedMotion, true);
  assert.strictEqual(reduced.animate, false, 'reduced motion must disable animation');
  assert.strictEqual(reduced.pulseClass, navigation.WORKSHOP_REDUCED_MOTION_CLASS);
})();

(function hoursPrecedenceAndEvidence() {
  const manual = navigation.projectWorkshopHours({
    sourceEstimatedHours: 4,
    aiEstimatedHours: 3,
    protectedHours: 5,
    manualOverrideHours: 6,
  });
  assert.strictEqual(manual.schedulingHours, 6);
  assert.strictEqual(manual.rule, 'manual_override');
  assert.strictEqual(manual.evidence.selectedField, 'manualOverrideHours');

  const protectedProjection = navigation.projectWorkshopHours({
    sourceEstimatedHours: 4,
    aiEstimatedHours: 3,
    protectedHours: 5,
  });
  assert.strictEqual(protectedProjection.schedulingHours, 5);
  assert.strictEqual(protectedProjection.rule, 'protected');

  const source = navigation.projectWorkshopHours({ sourceEstimatedHours: 4, aiEstimatedHours: 3 });
  assert.strictEqual(source.schedulingHours, 4);
  assert.strictEqual(source.rule, 'source');

  const ai = navigation.projectWorkshopHours({ aiEstimatedHours: 3 });
  assert.strictEqual(ai.schedulingHours, 3);
  assert.strictEqual(ai.rule, 'ai_fallback');

  const explicitZero = navigation.projectWorkshopHours({ sourceEstimatedHours: 0, aiEstimatedHours: 3 });
  assert.strictEqual(explicitZero.schedulingHours, 0, 'zero source hours must remain an explicit estimate');
  assert.strictEqual(explicitZero.rule, 'source');

  const unavailable = navigation.projectWorkshopHours({ sourceEstimatedHours: -1, aiEstimatedHours: 'unknown' });
  assert.strictEqual(unavailable.schedulingHours, null);
  assert.strictEqual(unavailable.rule, 'unavailable');
  assert.strictEqual(unavailable.evidence.selectedField, null);
})();

console.log('Workshop navigation/search/highlight/hours helpers passed');
