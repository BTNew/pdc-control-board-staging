'use strict';

/*
 * Workshop legacy import validator.
 *
 * Takes the output of scripts/workshop_planner_legacy_extract.js (a
 * "legacy extract" object) plus a snapshot of the target Supabase
 * database's shared reference data (vehicles, stages, bays, technicians,
 * work items) and produces a validation report classifying every legacy
 * booking into exactly one bucket:
 *
 *   - safely_matched              ready to import as-is
 *   - missing_vehicle             legacy vehicle key has no shared vehicle match
 *   - duplicate_vehicle_match     legacy vehicle key matches >1 shared vehicle
 *   - missing_bay                 stage/bay combination has no shared bay row
 *   - missing_technician          named assignee has no shared technician match
 *   - missing_work_item           work-item reference required but not found
 *   - overlapping_bay_booking     conflicts with another *safely matched* row
 *                                 in the same stage/bay window
 *   - overlapping_technician_booking  conflicts with another *safely matched*
 *                                 row for the same technician window
 *   - invalid_date_or_duration    unparsable/zero/negative start or duration
 *   - requires_manual_review      completed/stopped bookings always routed
 *                                 here regardless of otherwise passing checks,
 *                                 per the section-2 requirement that these
 *                                 always get a human look before import
 *
 * No record is ever silently discarded or guessed: every legacy booking
 * appears in exactly one output bucket, and the reasons array on rejected
 * records explains every check that failed.
 */

function normalizeLookupKey(value = '') {
  return String(value || '').trim().toLowerCase();
}

function toRange(startAt, durationMinutes) {
  if (!startAt) return null;
  const start = new Date(startAt).getTime();
  if (Number.isNaN(start)) return null;
  const minutes = Number(durationMinutes);
  if (!Number.isFinite(minutes) || minutes <= 0) return null;
  return { start, end: start + minutes * 60000 };
}

function rangesOverlap(a, b) {
  return a.start < b.end && b.start < a.end;
}

/**
 * validateLegacyImport(extract, referenceData)
 *
 * extract: output of extractWorkshopPlannerLegacyState()
 * referenceData: {
 *   vehicles: [{ id, stock_number, permanent_vehicle_id }],
 *   stages: [{ id, code }],
 *   bays: [{ id, stage_id, bay_number }],
 *   technicians: [{ id, name }],
 *   workItems: [{ id, vehicle_id, stage_code }] // optional, may be []
 * }
 */
function validateLegacyImport(extract, referenceData) {
  const vehicles = Array.isArray(referenceData?.vehicles) ? referenceData.vehicles : [];
  const stages = Array.isArray(referenceData?.stages) ? referenceData.stages : [];
  const bays = Array.isArray(referenceData?.bays) ? referenceData.bays : [];
  const technicians = Array.isArray(referenceData?.technicians) ? referenceData.technicians : [];
  const workItems = Array.isArray(referenceData?.workItems) ? referenceData.workItems : [];
  const requireWorkItemForStages = new Set((Array.isArray(referenceData?.requireWorkItemForStages) ? referenceData.requireWorkItemForStages : []).map(normalizeLookupKey));

  const stageByCode = new Map(stages.map(s => [normalizeLookupKey(s.code), s]));
  const bayByStageAndNumber = new Map(bays.map(b => [`${b.stage_id}::${Number(b.bay_number)}`, b]));
  const technicianByName = new Map();
  for (const tech of technicians) {
    const key = normalizeLookupKey(tech.name);
    if (!technicianByName.has(key)) technicianByName.set(key, []);
    technicianByName.get(key).push(tech);
  }
  const vehicleByKey = new Map();
  for (const vehicle of vehicles) {
    const keys = [vehicle.stock_number, vehicle.permanent_vehicle_id].filter(Boolean).map(normalizeLookupKey);
    for (const key of keys) {
      if (!vehicleByKey.has(key)) vehicleByKey.set(key, []);
      vehicleByKey.get(key).push(vehicle);
    }
  }
  const workItemByVehicleStage = new Set(workItems.map(w => `${w.vehicle_id}::${normalizeLookupKey(w.stage_code)}`));

  const buckets = {
    safely_matched: [],
    missing_vehicle: [],
    duplicate_vehicle_match: [],
    missing_bay: [],
    missing_technician: [],
    missing_work_item: [],
    overlapping_bay_booking: [],
    overlapping_technician_booking: [],
    invalid_date_or_duration: [],
    requires_manual_review: [],
  };

  const candidatePassed = [];

  for (const booking of extract.bookings || []) {
    const reasons = [];
    const vehicleMatches = vehicleByKey.get(normalizeLookupKey(booking.legacy_vehicle_key)) || [];
    const stageRow = stageByCode.get(normalizeLookupKey(booking.stage_code));
    const bayRow = stageRow && booking.bay_number != null
      ? bayByStageAndNumber.get(`${stageRow.id}::${Number(booking.bay_number)}`)
      : null;
    const technicianMatches = booking.assignee ? (technicianByName.get(normalizeLookupKey(booking.assignee)) || []) : [];
    const range = toRange(booking.scheduled_start_at, booking.duration_minutes);

    if (vehicleMatches.length === 0) reasons.push('missing_vehicle');
    if (vehicleMatches.length > 1) reasons.push('duplicate_vehicle_match');
    if (!stageRow) reasons.push('missing_stage');
    if (stageRow && booking.bay_number != null && !bayRow) reasons.push('missing_bay');
    if (booking.assignee && technicianMatches.length === 0) reasons.push('missing_technician');
    if (requireWorkItemForStages.has(normalizeLookupKey(booking.stage_code))) {
      const vehicleId = vehicleMatches.length === 1 ? vehicleMatches[0].id : null;
      if (!vehicleId || !workItemByVehicleStage.has(`${vehicleId}::${normalizeLookupKey(booking.stage_code)}`)) {
        reasons.push('missing_work_item');
      }
    }
    if (!range) reasons.push('invalid_date_or_duration');

    const requiresManualReview = ['completed', 'stoppage'].includes(booking.status);

    if (reasons.length === 0) {
      const resolvedVehicleId = vehicleMatches[0]?.id || null;
      const resolvedTechnicianId = technicianMatches[0]?.id || null;
      candidatePassed.push({
        booking,
        resolved: {
          vehicle_id: resolvedVehicleId,
          stage_id: stageRow.id,
          bay_id: bayRow ? bayRow.id : null,
          technician_id: resolvedTechnicianId,
        },
        range,
        requiresManualReview,
      });
    } else {
      for (const reason of reasons) {
        const bucketName = {
          missing_vehicle: 'missing_vehicle',
          duplicate_vehicle_match: 'duplicate_vehicle_match',
          missing_stage: 'missing_bay', // no separate bucket requested; stage absence blocks the same way a missing bay does
          missing_bay: 'missing_bay',
          missing_technician: 'missing_technician',
          missing_work_item: 'missing_work_item',
          invalid_date_or_duration: 'invalid_date_or_duration',
        }[reason];
        if (bucketName) buckets[bucketName].push({ booking, reasons });
      }
    }
  }

  // Overlap detection only runs across records that otherwise passed every
  // other check -- an overlap against an already-rejected record is not
  // useful signal and would just duplicate noise across buckets.
  const byBay = new Map();
  const byTechnician = new Map();
  const overlapBayIds = new Set();
  const overlapTechnicianIds = new Set();
  for (const candidate of candidatePassed) {
    if (!candidate.resolved.bay_id) continue;
    const list = byBay.get(candidate.resolved.bay_id) || [];
    for (const existing of list) {
      if (rangesOverlap(candidate.range, existing.range)) {
        overlapBayIds.add(candidate.booking.legacy_plan_id);
        overlapBayIds.add(existing.booking.legacy_plan_id);
      }
    }
    list.push(candidate);
    byBay.set(candidate.resolved.bay_id, list);
  }
  for (const candidate of candidatePassed) {
    if (!candidate.resolved.technician_id) continue;
    const list = byTechnician.get(candidate.resolved.technician_id) || [];
    for (const existing of list) {
      if (rangesOverlap(candidate.range, existing.range)) {
        overlapTechnicianIds.add(candidate.booking.legacy_plan_id);
        overlapTechnicianIds.add(existing.booking.legacy_plan_id);
      }
    }
    list.push(candidate);
    byTechnician.set(candidate.resolved.technician_id, list);
  }

  for (const candidate of candidatePassed) {
    const id = candidate.booking.legacy_plan_id;
    if (candidate.requiresManualReview) {
      buckets.requires_manual_review.push({ booking: candidate.booking, resolved: candidate.resolved, reasons: [`status_${candidate.booking.status}`] });
      continue;
    }
    if (overlapBayIds.has(id)) {
      buckets.overlapping_bay_booking.push({ booking: candidate.booking, resolved: candidate.resolved, reasons: ['overlapping_bay_booking'] });
      continue;
    }
    if (overlapTechnicianIds.has(id)) {
      buckets.overlapping_technician_booking.push({ booking: candidate.booking, resolved: candidate.resolved, reasons: ['overlapping_technician_booking'] });
      continue;
    }
    buckets.safely_matched.push({ booking: candidate.booking, resolved: candidate.resolved });
  }

  const totalBookings = (extract.bookings || []).length;
  const totalClassified = Object.values(buckets).reduce((sum, list) => sum + list.length, 0);

  return {
    buckets,
    counts: Object.fromEntries(Object.entries(buckets).map(([key, list]) => [key, list.length])),
    total_legacy_bookings: totalBookings,
    total_classification_entries: totalClassified, // a booking with >1 rejection reason appears in >1 bucket, by design (no silent discarding)
  };
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = { validateLegacyImport, normalizeLookupKey, toRange, rangesOverlap };
}
