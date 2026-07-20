'use strict';

(function initPdcAiBoardAdvisor(root, factory) {
  const api = factory();
  if (root && typeof root === 'object') root.PdcAiBoardAdvisor = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function createPdcAiBoardAdvisor() {
  const VERSION = 'phase-2-advisory-v1';
  const SEVERITY_RANK = Object.freeze({ critical: 0, high: 1, medium: 2, low: 3 });
  const CATEGORY_RANK = Object.freeze({ data: 0, parts: 1, workshop: 2, delivery: 3, labour: 4 });
  const ACTIVE_BOOKING_STATUSES = new Set(['queued', 'planned', 'started', 'stoppage']);

  function text(value) {
    return String(value == null ? '' : value).replace(/\s+/g, ' ').trim();
  }

  function normalized(value) {
    return text(value).toLowerCase();
  }

  function uniqueStrings(values) {
    return [...new Set((Array.isArray(values) ? values : []).map(text).filter(Boolean))].sort((a, b) => a.localeCompare(b));
  }

  function validDate(value) {
    if (!value) return null;
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  function stableToken(value) {
    return normalized(value).replace(/[^a-z0-9:_-]+/g, '-').replace(/^-+|-+$/g, '') || 'unknown';
  }

  function finding(rule, severity, category, identity, values) {
    return Object.freeze({
      id: `${rule}:${stableToken(identity)}`,
      rule,
      severity,
      category,
      vehicleIdentity: text(values.vehicleIdentity),
      stock: text(values.stock),
      bookingIds: Object.freeze(uniqueStrings(values.bookingIds)),
      title: text(values.title),
      explanation: text(values.explanation),
      evidence: Object.freeze(uniqueStrings(values.evidence)),
      recommendation: text(values.recommendation),
    });
  }

  function stageSet(values) {
    return new Set((Array.isArray(values) ? values : []).map(normalized).filter(Boolean));
  }

  function analyze(input) {
    const source = input && typeof input === 'object' ? input : {};
    const now = validDate(source.nowIso);
    if (!now) {
      return Object.freeze({
        version: VERSION,
        generatedAt: '',
        bookingCoverage: false,
        bookingSource: '',
        bookingRevision: '',
        findings: Object.freeze([finding('DATA_ANALYSIS_CLOCK_INVALID', 'critical', 'data', 'analysis-clock', {
          title: 'Advisor clock is unavailable',
          explanation: 'The advisor cannot rank time-sensitive risks without an explicit valid analysis time.',
          evidence: ['No valid nowIso value was supplied'],
          recommendation: 'Refresh the advisor and confirm the device clock before relying on time-sensitive advice.',
        })]),
        counts: Object.freeze({ critical: 1, high: 0, medium: 0, low: 0, total: 1 }),
      });
    }

    const vehicles = Array.isArray(source.vehicles) ? source.vehicles : [];
    const bookings = Array.isArray(source.bookings) ? source.bookings : [];
    const bookingCoverage = source.bookingCoverage === true;
    const bookingSource = ['shared', 'local'].includes(text(source.bookingSource)) ? text(source.bookingSource) : '';
    const bookingRevision = text(source.bookingRevision);
    const results = [];
    const identities = new Map();
    const duplicateIdentities = new Set();

    vehicles.forEach((vehicle, index) => {
      const identity = text(vehicle && vehicle.identity);
      if (!identity) {
        results.push(finding('DATA_VEHICLE_IDENTITY_MISSING', 'critical', 'data', `row-${index + 1}`, {
          stock: vehicle && vehicle.stock,
          title: 'Vehicle identity is missing',
          explanation: 'This vehicle cannot be matched safely to workshop evidence.',
          evidence: [`Vehicle row ${index + 1}`, vehicle && vehicle.stock ? `Stock ${text(vehicle.stock)}` : 'Stock unavailable'],
          recommendation: 'Resolve the canonical vehicle identity before acting on scheduling advice.',
        }));
        return;
      }
      if (identities.has(identity)) duplicateIdentities.add(identity);
      else identities.set(identity, vehicle);
    });

    duplicateIdentities.forEach(identity => {
      const matches = vehicles.filter(vehicle => text(vehicle && vehicle.identity) === identity);
      results.push(finding('DATA_VEHICLE_IDENTITY_DUPLICATE', 'critical', 'data', identity, {
        vehicleIdentity: identity,
        stock: uniqueStrings(matches.map(vehicle => vehicle && vehicle.stock)).join(' / '),
        title: 'Vehicle identity is ambiguous',
        explanation: 'More than one vehicle row uses the same stable identity, so identity-dependent advice is suppressed.',
        evidence: [`Identity ${identity}`, `${matches.length} matching vehicle rows`],
        recommendation: 'Reconcile the duplicate vehicle records before changing workshop plans.',
      }));
    });

    vehicles.forEach(vehicle => {
      const identity = text(vehicle && vehicle.identity);
      if (!identity || duplicateIdentities.has(identity)) return;
      const stock = text(vehicle.stock);
      const label = stock || identity;
      const required = stageSet(vehicle.requiredStages);
      const completed = stageSet(vehicle.completedStages);
      const outstanding = [...required].filter(stage => !completed.has(stage)).sort();
      const parts = vehicle.parts && typeof vehicle.parts === 'object' ? vehicle.parts : {};

      if (vehicle.blocked === true) {
        results.push(finding('VEHICLE_BLOCKED', 'critical', 'workshop', identity, {
          vehicleIdentity: identity, stock,
          title: `Blocked vehicle ${label}`,
          explanation: 'The vehicle is flagged as blocked and should not progress without human review.',
          evidence: [text(vehicle.blockReason) || 'Blocked flag is active', text(vehicle.currentStage) && `Current stage ${text(vehicle.currentStage)}`],
          recommendation: 'Confirm the blocker owner and next safe human action.',
        }));
      }

      if (parts.stoppage === true) {
        results.push(finding('PARTS_STOPPAGE', 'critical', 'parts', identity, {
          vehicleIdentity: identity, stock,
          title: `Parts stoppage on ${label}`,
          explanation: 'Required Parts are in stoppage and may prevent downstream workshop work.',
          evidence: [text(parts.reason) || 'Parts stoppage flag is active', text(parts.eta) && `ETA ${text(parts.eta)}`],
          recommendation: 'Review the supplier status and confirm the operational plan with Parts.',
        }));
      }

      const partsEta = validDate(parts.eta);
      if (parts.required === true && parts.complete !== true && partsEta && partsEta.getTime() < now.getTime()) {
        results.push(finding('PARTS_ETA_OVERDUE', 'high', 'parts', identity, {
          vehicleIdentity: identity, stock,
          title: `Parts ETA overdue for ${label}`,
          explanation: 'The recorded Parts ETA has passed while required Parts remain incomplete.',
          evidence: [`ETA ${partsEta.toISOString()}`, 'Required Parts are incomplete'],
          recommendation: 'Confirm a revised ETA or resolve the Parts status before relying on the schedule.',
        }));
      }

      const delivery = validDate(vehicle.deliveryAt);
      if (delivery && (outstanding.length || (parts.required === true && parts.complete !== true))) {
        const days = (delivery.getTime() - now.getTime()) / 86400000;
        if (days <= 7) {
          results.push(finding('DELIVERY_RISK', days < 0 ? 'critical' : 'high', 'delivery', identity, {
            vehicleIdentity: identity, stock,
            title: `${days < 0 ? 'Delivery overdue' : 'Delivery approaching'} for ${label}`,
            explanation: 'The delivery date is close or past while required work remains incomplete.',
            evidence: [`Delivery ${delivery.toISOString().slice(0, 10)}`, outstanding.length ? `Outstanding stages: ${outstanding.join(', ')}` : '', parts.required === true && parts.complete !== true ? 'Required Parts incomplete' : ''],
            recommendation: 'Review the delivery commitment and agree priorities with the responsible staff.',
          }));
        }
      }

      const age = Number(vehicle.stageAgeDays);
      const configuredAgeLimit = Number(vehicle.stageAgeLimitDays);
      const ageLimit = Number.isFinite(configuredAgeLimit) && configuredAgeLimit >= 0 ? configuredAgeLimit : 3;
      if (Number.isFinite(age) && age > ageLimit && outstanding.length) {
        results.push(finding('STAGE_STALE', age > ageLimit + 3 ? 'high' : 'medium', 'workshop', identity, {
          vehicleIdentity: identity, stock,
          title: `${label} has remained in one stage`,
          explanation: 'The current workshop stage has not progressed while required work remains outstanding.',
          evidence: [`Stage age ${Math.floor(age)} days; configured limit ${ageLimit}`, text(vehicle.currentStage) && `Current stage ${text(vehicle.currentStage)}`, `Outstanding stages: ${outstanding.join(', ')}`],
          recommendation: 'Confirm whether the stage, blocker and expected completion are still accurate.',
        }));
      }

      const unconfirmed = (Array.isArray(vehicle.jobLines) ? vehicle.jobLines : []).filter(line => {
        if (!line || typeof line !== 'object') return false;
        const hours = Number(line.hours);
        return line.confirmed !== true || !Number.isFinite(hours) || hours <= 0;
      });
      if (unconfirmed.length) {
        results.push(finding('LABOUR_UNCONFIRMED', 'medium', 'labour', identity, {
          vehicleIdentity: identity, stock,
          title: `Labour needs confirmation for ${label}`,
          explanation: 'One or more manual work lines do not have staff-confirmed positive labour hours.',
          evidence: [`${unconfirmed.length} unconfirmed line${unconfirmed.length === 1 ? '' : 's'}`, ...unconfirmed.slice(0, 3).map(line => text(line.description))],
          recommendation: 'Have staff confirm descriptions, workshop categories and labour hours before scheduling.',
        }));
      }
    });

    if (bookingCoverage) {
      const bookingIds = new Map();
      const duplicateBookingIds = new Set();
      const validBookings = [];

      bookings.forEach((booking, index) => {
        const id = text(booking && booking.id);
        if (!id) {
          results.push(finding('DATA_BOOKING_ID_MISSING', 'critical', 'data', `row-${index + 1}`, {
            title: 'Workshop booking ID is missing',
            explanation: 'A booking without a stable ID cannot be matched or deduplicated safely.',
            evidence: [`Booking row ${index + 1}`],
            recommendation: 'Resolve the booking identity before acting on scheduling advice.',
          }));
          return;
        }
        if (bookingIds.has(id)) duplicateBookingIds.add(id);
        else bookingIds.set(id, booking);
      });

      duplicateBookingIds.forEach(id => {
        results.push(finding('DATA_BOOKING_ID_DUPLICATE', 'critical', 'data', id, {
          bookingIds: [id],
          title: 'Workshop booking ID is duplicated',
          explanation: 'The same booking ID appears more than once, so advice for that booking is suppressed.',
          evidence: [`Booking ${id}`, `${bookings.filter(booking => text(booking && booking.id) === id).length} matching rows`],
          recommendation: 'Reconcile the duplicate booking records before changing the schedule.',
        }));
      });

      bookings.forEach(booking => {
        const id = text(booking && booking.id);
        if (!id || duplicateBookingIds.has(id)) return;
        const identity = text(booking.vehicleIdentity);
        if (!identity || !identities.has(identity) || duplicateIdentities.has(identity)) {
          results.push(finding('DATA_BOOKING_VEHICLE_UNRESOLVED', 'critical', 'data', id, {
            vehicleIdentity: identity, bookingIds: [id],
            title: 'Booking vehicle cannot be resolved safely',
            explanation: 'The booking does not map to exactly one current vehicle identity.',
            evidence: [`Booking ${id}`, identity ? `Vehicle identity ${identity}` : 'Vehicle identity missing'],
            recommendation: 'Resolve the vehicle identity before relying on this booking advice.',
          }));
          return;
        }
        const start = validDate(booking.startAt);
        const end = validDate(booking.endAt);
        if (!start || !end || end.getTime() <= start.getTime()) {
          results.push(finding('DATA_BOOKING_INTERVAL_INVALID', 'critical', 'data', id, {
            vehicleIdentity: identity, stock: identities.get(identity).stock, bookingIds: [id],
            title: 'Booking time range is invalid',
            explanation: 'The booking has a missing, malformed or non-positive time interval.',
            evidence: [`Booking ${id}`, `Start ${text(booking.startAt) || 'missing'}`, `End ${text(booking.endAt) || 'missing'}`],
            recommendation: 'Correct the booking time before using schedule advice.',
          }));
          return;
        }
        validBookings.push({ ...booking, id, vehicleIdentity: identity, start, end, status: normalized(booking.status) });
      });

      validBookings.forEach(booking => {
        if (!ACTIVE_BOOKING_STATUSES.has(booking.status)) return;
        const vehicle = identities.get(booking.vehicleIdentity) || {};
        const stock = text(vehicle.stock);
        if (booking.status === 'stoppage') {
          results.push(finding('BOOKING_STOPPAGE', 'critical', 'workshop', booking.id, {
            vehicleIdentity: booking.vehicleIdentity, stock, bookingIds: [booking.id],
            title: `Workshop stoppage${stock ? ` on ${stock}` : ''}`,
            explanation: 'An active workshop booking is in stoppage.',
            evidence: [`Booking ${booking.id}`, text(booking.stage) && `Stage ${text(booking.stage)}`, text(booking.stoppageReason) || 'Stoppage reason not recorded'],
            recommendation: 'Confirm the stoppage owner, reason and safe resumption plan.',
          }));
        }
        if (booking.status === 'planned' && booking.start.getTime() < now.getTime() - 30 * 60000) {
          results.push(finding('BOOKING_OVERDUE', 'high', 'workshop', booking.id, {
            vehicleIdentity: booking.vehicleIdentity, stock, bookingIds: [booking.id],
            title: `Planned booking has not started${stock ? ` for ${stock}` : ''}`,
            explanation: 'The planned start is more than 30 minutes in the past.',
            evidence: [`Booking ${booking.id}`, `Planned start ${booking.start.toISOString()}`, text(booking.stage) && `Stage ${text(booking.stage)}`],
            recommendation: 'Confirm whether the booking should start, remain planned, or be manually re-planned.',
          }));
        }
        if (booking.status === 'started' && booking.end.getTime() < now.getTime() - 30 * 60000) {
          results.push(finding('BOOKING_OVERDUE', 'high', 'workshop', booking.id, {
            vehicleIdentity: booking.vehicleIdentity, stock, bookingIds: [booking.id],
            title: `Started booking is past its planned end${stock ? ` for ${stock}` : ''}`,
            explanation: 'The booking remains started more than 30 minutes after its planned end.',
            evidence: [`Booking ${booking.id}`, `Planned end ${booking.end.toISOString()}`, text(booking.stage) && `Stage ${text(booking.stage)}`],
            recommendation: 'Confirm progress, completion or a human-approved schedule adjustment.',
          }));
        }
      });

      const activeValid = validBookings.filter(booking => ACTIVE_BOOKING_STATUSES.has(booking.status));
      for (let leftIndex = 0; leftIndex < activeValid.length; leftIndex += 1) {
        const left = activeValid[leftIndex];
        const lane = `${normalized(left.stage)}|${normalized(left.bay)}`;
        if (lane === '|') continue;
        for (let rightIndex = leftIndex + 1; rightIndex < activeValid.length; rightIndex += 1) {
          const right = activeValid[rightIndex];
          if (`${normalized(right.stage)}|${normalized(right.bay)}` !== lane) continue;
          if (left.start.getTime() >= right.end.getTime() || right.start.getTime() >= left.end.getTime()) continue;
          const ids = [left.id, right.id].sort();
          results.push(finding('BAY_OVERLAP', 'critical', 'workshop', ids.join('--'), {
            bookingIds: ids,
            title: `Overlapping bookings in ${text(left.stage) || 'workshop'} ${text(left.bay) || 'lane'}`,
            explanation: 'Two active bookings occupy the same stage and bay during an overlapping time window.',
            evidence: [`Bookings ${ids.join(' and ')}`, `Overlap lane ${text(left.stage)} / ${text(left.bay)}`],
            recommendation: 'Review the conflict and agree a manual schedule correction before work proceeds.',
          }));
        }
      }

      vehicles.forEach(vehicle => {
        const identity = text(vehicle && vehicle.identity);
        if (!identity || duplicateIdentities.has(identity)) return;
        const required = stageSet(vehicle.requiredStages);
        const completed = stageSet(vehicle.completedStages);
        const scheduled = new Set(activeValid.filter(booking => booking.vehicleIdentity === identity).map(booking => normalized(booking.stage)).filter(Boolean));
        const unscheduled = [...required].filter(stage => !completed.has(stage) && !scheduled.has(stage)).sort();
        if (unscheduled.length) {
          results.push(finding('UNSCHEDULED_REQUIRED_STAGE', 'medium', 'workshop', identity, {
            vehicleIdentity: identity, stock: vehicle.stock,
            title: `${text(vehicle.stock) || identity} has unscheduled required work`,
            explanation: 'One or more required incomplete workshop stages have no active booking in the authoritative snapshot.',
            evidence: [`Required stages: ${unscheduled.join(', ')}`, 'No queued, planned, started or stoppage booking found for these stages'],
            recommendation: 'Review capacity and create or confirm a booking manually if appropriate.',
          }));
        }
      });
    }

    const deduped = new Map();
    results.forEach(item => { if (!deduped.has(item.id)) deduped.set(item.id, item); });
    const findings = [...deduped.values()].sort((a, b) =>
      (SEVERITY_RANK[a.severity] ?? 99) - (SEVERITY_RANK[b.severity] ?? 99) ||
      (CATEGORY_RANK[a.category] ?? 99) - (CATEGORY_RANK[b.category] ?? 99) ||
      a.rule.localeCompare(b.rule) || a.id.localeCompare(b.id));
    const counts = { critical: 0, high: 0, medium: 0, low: 0, total: findings.length };
    findings.forEach(item => { if (Object.prototype.hasOwnProperty.call(counts, item.severity)) counts[item.severity] += 1; });

    return Object.freeze({
      version: VERSION,
      generatedAt: now.toISOString(),
      bookingCoverage,
      bookingSource,
      bookingRevision,
      findings: Object.freeze(findings),
      counts: Object.freeze(counts),
    });
  }

  return Object.freeze({ VERSION, analyze });
});
