// Sanitised public fallback. The scheduled email publisher is disabled.
(function () {
  window.PDC_EMAIL_BOARD_DATA = {
    generatedAt: "2026-07-15T07:09:02+08:00",
    source: "Sanitised public fallback - no operational intake data",
    vehicles: [],
    reviews: []
  };
  var base = window.VEHICLE_TRACKING_DATA = window.VEHICLE_TRACKING_DATA || { report: {}, vehicles: [], toyotaMatches: {} };
  base.vehicles = Array.isArray(base.vehicles) ? base.vehicles : [];
  base.report = Object.assign({}, base.report || {}, {
    emailIntakeGeneratedAt: window.PDC_EMAIL_BOARD_DATA.generatedAt,
    emailIntakeVehicleCount: 0,
    emailIntakeReviewCount: 0
  });
}());
