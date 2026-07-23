'use strict';

(function initWorkshopEligibility(root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (root) root.PDC_WORKSHOP_ELIGIBILITY = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function workshopEligibilityFactory() {
  const STATIONS = Object.freeze([
    Object.freeze({ code: 'BUS_4X4', label: 'Bus 4x4', short: 'B4', workKey: 'BUS4X4', jobKey: 'bus4x4', route: 'planner-bus-4x4', path: 'workshop/bus-4x4', plannerEnabled: true, statusVisible: true, aliases: ['BUS_4X4', 'BUS4X4', 'BUS 4X4', 'BUS FOUR BY FOUR', '4X4 BUS', 'DEPARTMENT 138', 'DEPT 138'] }),
    Object.freeze({ code: 'TINT', label: 'Tint', short: 'T', workKey: 'TINT', jobKey: 'tint', route: 'planner-tint', path: 'workshop/tint', plannerEnabled: true, statusVisible: true, aliases: ['TINT', 'TINTING', 'WINDOW TINT'] }),
    Object.freeze({ code: 'HOIST', label: 'Hoist', short: 'H', workKey: 'HOIST', jobKey: 'hoist', route: 'planner-hoist', path: 'workshop/hoist', plannerEnabled: true, statusVisible: true, aliases: ['HOIST', 'LIFTS', 'PITS HOIST', 'PIT HOIST', 'EXPRESS HOIST'] }),
    Object.freeze({ code: 'FITTING', label: 'Fitting', short: 'F', workKey: 'FITTING', jobKey: 'fitting', route: 'planner-fitting', path: 'workshop/fitting', plannerEnabled: true, statusVisible: true, aliases: ['FITTING', 'FITMENT', 'FITOUT', 'FIT OUT', 'EXPRESS FITOUT'] }),
    Object.freeze({ code: 'FABRICATION', label: 'Fab', short: 'Fa', workKey: 'FABRICATION', jobKey: 'fabrication', route: 'planner-fab', path: 'workshop/fab', plannerEnabled: true, statusVisible: true, aliases: ['FABRICATION', 'FAB', 'FABRICATING'] }),
    Object.freeze({ code: 'ELECTRICAL', label: 'Elec', short: 'E', workKey: 'ELECTRICAL', jobKey: 'electrical', route: 'planner-elec', path: 'workshop/elec', plannerEnabled: true, statusVisible: true, aliases: ['ELECTRICAL', 'ELEC', 'AUTO ELECTRICAL', 'AUTO ELEC'] }),
    Object.freeze({ code: 'TYRE', label: 'Tyre', short: 'Ty', workKey: 'TYRE', jobKey: 'tyre', route: 'planner-tyre', path: 'workshop/tyre', plannerEnabled: true, statusVisible: true, aliases: ['TYRE', 'TYRES', 'TYRE BAY', 'TIRE', 'TIRE BAY'] }),
    Object.freeze({ code: 'PIT_INSPECTION', label: 'Pit', short: 'PI', workKey: 'PITINSPECTION', jobKey: 'pitInspection', route: 'planner-pit', path: 'workshop/pit', plannerEnabled: true, statusVisible: true, aliases: ['PIT_INSPECTION', 'PITINSPECTION', 'PIT INSPECTION', 'PIT', 'PITS', 'INSPECTION'] }),
    Object.freeze({ code: 'SUBLET', label: 'Sublet', short: 'S', workKey: 'SUBLET', jobKey: 'sublet', route: '', path: '', plannerEnabled: false, statusVisible: true, aliases: ['SUBLET', 'SUB LET', 'SUB-LET', 'OUTSOURCE', 'OUTSOURCED', 'EXTERNAL'] }),
  ]);

  function normalizedAlias(value) {
    return String(value == null ? '' : value).trim().toUpperCase().replace(/[^A-Z0-9]+/g, '');
  }

  const BY_CODE = new Map(STATIONS.map(def => [def.code, def]));
  const BY_ALIAS = new Map();
  STATIONS.forEach(def => {
    [def.code, def.workKey, def.jobKey, def.label, ...def.aliases].forEach(alias => {
      const key = normalizedAlias(alias);
      if (key) BY_ALIAS.set(key, def.code);
    });
  });

  function canonicalWorkshopStage(value) {
    return BY_ALIAS.get(normalizedAlias(value)) || '';
  }

  function workshopStageDefinition(value) {
    return BY_CODE.get(canonicalWorkshopStage(value)) || null;
  }

  function workshopPlannerStageCodes() {
    return STATIONS.filter(def => def.plannerEnabled).map(def => def.code);
  }

  function workshopPlannerStationDefinitions() {
    return STATIONS.filter(def => def.plannerEnabled);
  }

  function workshopIsPlannerStage(value) {
    return workshopStageDefinition(value)?.plannerEnabled === true;
  }

  function assertWorkshopPlannerTarget(value) {
    const def = workshopStageDefinition(value);
    if (!def || !def.plannerEnabled) throw new Error(`${value || 'Unknown'} is not a schedulable planner station`);
    return def;
  }

  function parseEtaDateKey(value) {
    const raw = String(value || '').trim();
    let match = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (match) return `${match[1]}-${match[2]}-${match[3]}`;
    match = raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
    if (!match) return '';
    const day = Number(match[1]);
    const month = Number(match[2]);
    const year = Number(match[3]);
    const date = new Date(Date.UTC(year, month - 1, day));
    if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return '';
    return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  function vehicleLocation(vehicle) {
    const raw = String(vehicle?.current_location ?? vehicle?.currentLocation ?? vehicle?.pdcLocation ?? '').trim().toUpperCase();
    if (raw === 'PMB' || raw.includes('PERTH MOTOR BODIES')) return 'PMB';
    if (raw === 'YH' || raw.includes('YARD HOLD')) return 'YH';
    if (raw === 'IT' || raw === 'IN TRANSIT') return 'IT';
    return raw;
  }

  function vehicleIsActive(vehicle) {
    const lifecycle = String(vehicle?.lifecycle_state ?? vehicle?.lifecycleState ?? 'active').trim().toLowerCase();
    return lifecycle === 'active' && !vehicle?.deleted_at && !vehicle?.deletedAt;
  }

  function scheduleEligibility(vehicle) {
    const location = vehicleLocation(vehicle);
    if (location === 'PMB' || location === 'YH') return { enabled: true, location, earliestDateKey: '', reason: '' };
    if (location !== 'IT') return { enabled: false, location, earliestDateKey: '', reason: `Location ${location || 'unknown'} is not eligible for workshop scheduling` };
    const rawEta = vehicle?.eta_to_kewdale ?? vehicle?.etaToKewdale ?? vehicle?.navisionKewdaleEta ?? vehicle?.etaAtKewdale ?? '';
    const earliestDateKey = parseEtaDateKey(rawEta);
    if (!String(rawEta || '').trim()) return { enabled: false, location, earliestDateKey: '', reason: 'ETA to Kewdale is missing' };
    if (!earliestDateKey) return { enabled: false, location, earliestDateKey: '', reason: 'ETA to Kewdale is invalid' };
    return { enabled: true, location, earliestDateKey, reason: `Scheduling available on or after ${earliestDateKey}` };
  }

  function workshopCanonicalEligibility(input) {
    const def = assertWorkshopPlannerTarget(input?.stage);
    const vehicles = Array.isArray(input?.vehicles) ? input.vehicles : [];
    const workItems = Array.isArray(input?.workItems) ? input.workItems : [];
    const bookings = Array.isArray(input?.bookings) ? input.bookings : [];
    const byVehicle = new Map(vehicles.map(vehicle => [String(vehicle.id ?? vehicle.vehicle_id ?? vehicle.vehicleKey ?? ''), vehicle]).filter(([id]) => id));
    const workByVehicle = new Map();
    workItems.forEach(item => {
      if (canonicalWorkshopStage(item?.work_key ?? item?.workKey ?? '') !== def.code) return;
      const id = String(item?.vehicle_id ?? item?.vehicleId ?? '');
      if (!id) return;
      const state = workByVehicle.get(id) || { hasRequirement: false, outstanding: false, completed: false };
      if (item.required === true) state.hasRequirement = true;
      if (item.required === true && item.completed !== true) state.outstanding = true;
      if (item.required === true && item.completed === true) state.completed = true;
      workByVehicle.set(id, state);
    });
    const activeStatuses = new Set(['queued', 'planned', 'started', 'stoppage']);
    const activeBookingByVehicle = new Map();
    bookings.forEach(entry => {
      const bookingStage = entry?.stage_code ?? entry?.stage?.code ?? entry?.stage ?? '';
      if (canonicalWorkshopStage(bookingStage) !== def.code) return;
      if (!activeStatuses.has(String(entry?.status || '').toLowerCase())) return;
      const id = String(entry?.vehicle_id ?? entry?.vehicleId ?? '');
      if (id && !activeBookingByVehicle.has(id)) activeBookingByVehicle.set(id, entry);
    });
    const candidates = [];
    const excluded = [];
    byVehicle.forEach((vehicle, id) => {
      const work = workByVehicle.get(id) || { hasRequirement: false, outstanding: false, completed: false };
      const activeBooking = activeBookingByVehicle.get(id) || null;
      let reason = '';
      if (!vehicleIsActive(vehicle)) reason = 'inactive';
      else if (!work.outstanding) reason = work.hasRequirement && work.completed ? 'completed' : 'requirement';
      const schedule = scheduleEligibility(vehicle);
      if (!reason && !['PMB', 'YH', 'IT'].includes(schedule.location)) reason = 'location';
      if (reason) {
        excluded.push({ vehicle, reason, work, existingBooking: Boolean(activeBooking), schedule });
        return;
      }
      candidates.push({ vehicle, work, existingBooking: Boolean(activeBooking), booking: activeBooking, schedule });
    });
    const identity = row => String(row.vehicle?.stock_number ?? row.vehicle?.stockNumber ?? row.vehicle?.id ?? '');
    candidates.sort((a, b) => identity(a).localeCompare(identity(b)));
    excluded.sort((a, b) => identity(a).localeCompare(identity(b)));
    return { stage: def.code, availableCount: candidates.length, candidates, excluded };
  }

  return Object.freeze({
    stationDefinitions: STATIONS,
    canonicalWorkshopStage,
    workshopStageDefinition,
    workshopPlannerStageCodes,
    workshopPlannerStationDefinitions,
    workshopIsPlannerStage,
    assertWorkshopPlannerTarget,
    parseEtaDateKey,
    vehicleLocation,
    scheduleEligibility,
    workshopCanonicalEligibility,
  });
});
