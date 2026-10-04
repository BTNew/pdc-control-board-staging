(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.PDC_WORKSHOP_BOOKING_TIMING = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const timestamp = value => value instanceof Date ? value.getTime() : typeof value === 'number' ? value : Date.parse(value || '');

  // Both planner views project the same canonical booking. Projection is display
  // only: it never rewrites the scheduled range or substitutes actual start time.
  function effectiveEnd(booking, options = {}) {
    const plannedEnd = timestamp(options.plannedEnd ?? booking.scheduled_end_at);
    if (!Number.isFinite(plannedEnd)) return NaN;
    if (booking.status === 'completed') {
      const actualEnd = timestamp(booking.actual_end_at);
      return Number.isFinite(actualEnd) ? Math.max(plannedEnd, actualEnd) : plannedEnd;
    }
    if (booking.status !== 'started' && booking.status !== 'stoppage') return plannedEnd;
    const moment = timestamp(booking.status === 'stoppage' ? booking.stoppage_started_at : options.now);
    if (!Number.isFinite(moment)) return plannedEnd;
    const latest = Number(options.latestWorkMoment(moment));
    if (!Number.isFinite(latest) || latest <= plannedEnd) return plannedEnd;
    if (booking.status === 'started') return latest;
    const stoppedEnd = Number(options.addWorkMinutes(latest, options.incrementMinutes));
    return Number.isFinite(stoppedEnd) ? Math.max(plannedEnd, stoppedEnd) : plannedEnd;
  }

  return Object.freeze({ effectiveEnd });
});
