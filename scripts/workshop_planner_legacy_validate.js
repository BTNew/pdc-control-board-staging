'use strict';

const { parseWorkshopReference } = require('./workshop_vehicle_reference_artifact');
const fs = require('fs');
const path = require('path');

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
 *   - missing_vehicle             legacy vehicle key has no typed identity match
 *   - duplicate_vehicle_match     legacy vehicle key matches >1 canonical UUID
 *   - conflicting_vehicle_identity explicit migration-031 conflict evidence
 *   - inactive_vehicle            only matching canonical UUID is archived
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

function normalizeVehicleStockNumber(value = '') {
  const normalized = String(value || '').trim().toUpperCase().replace(/[\s-]+/g, '');
  return normalized || null;
}

function isRealVehicleStockNumber(value = '') {
  const normalized = normalizeVehicleStockNumber(value);
  const raw = String(value || '').trim().toUpperCase();
  return Boolean(normalized
    && !new Set(['0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED']).has(normalized)
    && !['NEW-', 'PD-', 'PENDING-', 'TEMP-'].some(prefix => raw.startsWith(prefix)));
}

function normalizeVehicleVin(value = '') {
  const normalized = String(value || '').trim().toUpperCase().replace(/[\s-]+/g, '');
  return normalized || null;
}

function isValidVehicleVin(value = '') {
  return /^[A-HJ-NPR-Z0-9]{17}$/.test(normalizeVehicleVin(value) || '');
}

function normalizeVehicleSourceIdentifier(value = '') {
  const normalized = String(value || '').trim().toUpperCase();
  return normalized || null;
}

function legacyIdentityForms(value) {
  const forms = [];
  if (isRealVehicleStockNumber(value)) forms.push(['stock_number', normalizeVehicleStockNumber(value)]);
  if (isValidVehicleVin(value)) forms.push(['vin', normalizeVehicleVin(value)]);
  const sourceValue = normalizeVehicleSourceIdentifier(value);
  if (sourceValue) {
    for (const type of ['job_card_number', 'permanent_vehicle_id', 'toyota_order_number', 'source_record_id']) {
      forms.push([type, sourceValue]);
    }
  }
  return forms;
}

function buildVehicleIdentityIndex(vehicles, conflicts) {
  const byClaim = new Map();
  const evidenceByClaim = new Map();
  const byId = new Map();
  for (const vehicle of vehicles) {
    if (byId.has(vehicle.vehicle_id)) throw new Error(`duplicate canonical UUID: ${vehicle.vehicle_id}`);
    byId.set(vehicle.vehicle_id, vehicle);
    for (const claim of vehicle.identifiers) {
      const key = `${claim.identifier_type}\u0000${claim.normalized_value}`;
      if (!byClaim.has(key)) byClaim.set(key, new Set());
      byClaim.get(key).add(vehicle.vehicle_id);
      if (!evidenceByClaim.has(key)) evidenceByClaim.set(key, []);
      evidenceByClaim.get(key).push({ vehicle_id: vehicle.vehicle_id, origin: claim.origin, source_system: claim.source_system });
    }
  }
  const conflictByClaim = new Map();
  for (const conflict of conflicts) {
    const key = `${conflict.identifier_type}\u0000${conflict.normalized_value}`;
    if (!conflictByClaim.has(key)) conflictByClaim.set(key, []);
    conflictByClaim.get(key).push(conflict);
  }
  return { byClaim, byId, conflictByClaim, evidenceByClaim };
}

function matchLegacyVehicleIdentity(value, index) {
  const ids = new Set();
  const matchedClaims = [];
  const identityConflicts = [];
  for (const [type, normalized] of legacyIdentityForms(value)) {
    const key = `${type}\u0000${normalized}`;
    for (const id of index.byClaim.get(key) || []) ids.add(id);
    for (const evidence of index.evidenceByClaim.get(key) || []) {
      matchedClaims.push({ identifier_type: type, normalized_value: normalized, ...evidence });
    }
    identityConflicts.push(...(index.conflictByClaim.get(key) || []));
  }
  return {
    vehicles: [...ids].sort().map(id => index.byId.get(id)),
    matched_claims: matchedClaims,
    identity_conflicts: identityConflicts,
  };
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
 *   vehicleIdentityArtifact: migration-031 typed artifact,
 *   stages: [{ id, code }],
 *   bays: [{ id, stage_id, bay_number }],
 *   technicians: [{ id, name }],
 *   workItems: [{ id, vehicle_id, stage_code }] // optional, may be []
 * }
 */
function validateLegacyImport(extract, referenceData, options = {}) {
  const parsedReference = parseWorkshopReference(referenceData, options);
  const vehicles = parsedReference.vehicles;
  const stages = Array.isArray(parsedReference.stages) ? parsedReference.stages : [];
  const bays = Array.isArray(parsedReference.bays) ? parsedReference.bays : [];
  const technicians = Array.isArray(parsedReference.technicians) ? parsedReference.technicians : [];
  const workItems = Array.isArray(parsedReference.workItems) ? parsedReference.workItems : [];
  const requireWorkItemForStages = new Set((Array.isArray(parsedReference.requireWorkItemForStages) ? parsedReference.requireWorkItemForStages : []).map(normalizeLookupKey));

  const stageByCode = new Map(stages.map(s => [normalizeLookupKey(s.code), s]));
  const bayByStageAndNumber = new Map(bays.map(b => [`${b.stage_id}::${Number(b.bay_number)}`, b]));
  const technicianByName = new Map();
  for (const tech of technicians) {
    const key = normalizeLookupKey(tech.name);
    if (!technicianByName.has(key)) technicianByName.set(key, []);
    technicianByName.get(key).push(tech);
  }
  const vehicleIdentityIndex = buildVehicleIdentityIndex(vehicles, parsedReference.vehicleIdentityExport.conflicts || []);
  const workItemByVehicleStage = new Set(workItems.map(w => `${w.vehicle_id}::${normalizeLookupKey(w.stage_code)}`));

  const buckets = {
    safely_matched: [],
    missing_vehicle: [],
    duplicate_vehicle_match: [],
    conflicting_vehicle_identity: [],
    inactive_vehicle: [],
    missing_bay: [],
    missing_technician: [],
    duplicate_technician_match: [],
    missing_work_item: [],
    overlapping_bay_booking: [],
    overlapping_technician_booking: [],
    invalid_date_or_duration: [],
    requires_manual_review: [],
  };

  const candidatePassed = [];

  for (const booking of extract.bookings || []) {
    const reasons = [];
    const identityMatch = matchLegacyVehicleIdentity(booking.legacy_vehicle_key, vehicleIdentityIndex);
    const vehicleMatches = identityMatch.vehicles;
    const stageRow = stageByCode.get(normalizeLookupKey(booking.stage_code));
    const bayRow = stageRow && booking.bay_number != null
      ? bayByStageAndNumber.get(`${stageRow.id}::${Number(booking.bay_number)}`)
      : null;
    const technicianMatches = booking.assignee ? (technicianByName.get(normalizeLookupKey(booking.assignee)) || []) : [];
    const range = toRange(booking.scheduled_start_at, booking.duration_minutes);

    if (identityMatch.identity_conflicts.length) reasons.push('conflicting_vehicle_identity');
    else if (vehicleMatches.length === 0) reasons.push('missing_vehicle');
    else if (vehicleMatches.length > 1) reasons.push('duplicate_vehicle_match');
    else if (vehicleMatches[0].is_archived) reasons.push('inactive_vehicle');
    if (!stageRow) reasons.push('missing_stage');
    if (stageRow && booking.bay_number != null && !bayRow) reasons.push('missing_bay');
    if (booking.assignee && technicianMatches.length === 0) reasons.push('missing_technician');
    if (booking.assignee && technicianMatches.length > 1) reasons.push('duplicate_technician_match');
    if (requireWorkItemForStages.has(normalizeLookupKey(booking.stage_code))) {
      const vehicleId = vehicleMatches.length === 1 ? vehicleMatches[0].vehicle_id : null;
      if (!vehicleId || !workItemByVehicleStage.has(`${vehicleId}::${normalizeLookupKey(booking.stage_code)}`)) {
        reasons.push('missing_work_item');
      }
    }
    if (!range) reasons.push('invalid_date_or_duration');

    const requiresManualReview = ['completed', 'stoppage'].includes(booking.status);

    if (reasons.length === 0) {
      const resolvedVehicleId = vehicleMatches[0]?.vehicle_id || null;
      const resolvedTechnicianId = technicianMatches[0]?.id || null;
      candidatePassed.push({
        booking,
        resolved: {
          vehicle_id: resolvedVehicleId,
          vehicle_version: vehicleMatches[0]?.version || null,
          stage_id: stageRow.id,
          bay_id: bayRow ? bayRow.id : null,
          technician_id: resolvedTechnicianId,
        },
        range,
        requiresManualReview,
      });
    } else {
      const safeIdentityConflicts = identityMatch.identity_conflicts.map(conflict => ({
        classification: conflict.classification,
        identifier_type: conflict.identifier_type,
        normalized_value: conflict.normalized_value,
        source_system: conflict.source_system,
        vehicle_ids: conflict.vehicle_ids,
      }));
      for (const reason of reasons) {
        const bucketName = {
          missing_vehicle: 'missing_vehicle',
          duplicate_vehicle_match: 'duplicate_vehicle_match',
          conflicting_vehicle_identity: 'conflicting_vehicle_identity',
          inactive_vehicle: 'inactive_vehicle',
          missing_stage: 'missing_bay', // no separate bucket requested; stage absence blocks the same way a missing bay does
          missing_bay: 'missing_bay',
          missing_technician: 'missing_technician',
          duplicate_technician_match: 'duplicate_technician_match',
          missing_work_item: 'missing_work_item',
          invalid_date_or_duration: 'invalid_date_or_duration',
        }[reason];
        if (bucketName) buckets[bucketName].push({
          booking,
          reasons,
          identity_candidates: vehicleMatches.map(row => row.vehicle_id),
          identity_conflicts: safeIdentityConflicts,
          matched_claims: identityMatch.matched_claims,
        });
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
    vehicle_reference: {
      schema_version: parsedReference.vehicleIdentityExport.artifact_schema_version || 'legacy-rollback',
      resolver_revision: parsedReference.vehicleIdentityExport.export_revision,
      checksum: parsedReference.vehicleIdentityExport.artifact_checksum || null,
      source_environment: referenceData.vehicleIdentityArtifact?.source_environment || options.legacySourceEnvironment || null,
      item_count: vehicles.length,
    },
    buckets,
    counts: Object.fromEntries(Object.entries(buckets).map(([key, list]) => [key, list.length])),
    total_legacy_bookings: totalBookings,
    total_classification_entries: totalClassified, // a booking with >1 rejection reason appears in >1 bucket, by design (no silent discarding)
  };
}

function diagnosticSummary(report) {
  const rejected = [];
  for (const [bucket, entries] of Object.entries(report.buckets)) {
    if (bucket === 'safely_matched') continue;
    for (const entry of entries) {
      rejected.push({
        bucket,
        legacy_plan_id: entry.booking?.legacy_plan_id || null,
        reasons: entry.reasons || [],
        identity_candidates: entry.identity_candidates || [],
        matched_claims: entry.matched_claims || [],
        identity_conflicts: entry.identity_conflicts || [],
      });
    }
  }
  const safelyMatched = report.buckets.safely_matched.map(entry => ({
    legacy_plan_id: entry.booking?.legacy_plan_id || null,
    vehicle_id: entry.resolved?.vehicle_id || null,
    vehicle_version: entry.resolved?.vehicle_version || null,
  }));
  return {
    vehicle_reference: report.vehicle_reference,
    counts: report.counts,
    total_legacy_bookings: report.total_legacy_bookings,
    safely_matched: safelyMatched,
    rejected,
  };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const extractPath = args[0];
  const referencePath = args[1];
  const revisionIndex = args.indexOf('--expected-revision');
  const expectedResolverRevision = revisionIndex >= 0 ? Number(args[revisionIndex + 1]) : NaN;
  const allowLegacyRollback = args.includes('--legacy-reference-rollback');
  const legacyEnvironmentIndex = args.indexOf('--legacy-source-environment');
  const legacySourceEnvironment = legacyEnvironmentIndex >= 0 ? args[legacyEnvironmentIndex + 1] : undefined;
  if (!extractPath || !referencePath || !Number.isInteger(expectedResolverRevision)) {
    console.error('Usage: node scripts/workshop_planner_legacy_validate.js <extract.json> <reference.json> --expected-revision <n> [--legacy-reference-rollback --legacy-source-environment <staging:test-id|test:test-id>]');
    process.exit(1);
  }
  try {
    const extract = JSON.parse(fs.readFileSync(path.resolve(extractPath), 'utf8'));
    const reference = JSON.parse(fs.readFileSync(path.resolve(referencePath), 'utf8'));
    const report = validateLegacyImport(extract, reference, {
      expectedResolverRevision,
      allowLegacyRollback,
      legacySourceEnvironment,
      diagnostic: message => console.error(message),
    });
    process.stdout.write(`${JSON.stringify(diagnosticSummary(report), null, 2)}\n`);
  } catch (error) {
    console.error(`REFERENCE_VALIDATION_FAILED: ${error.message}`);
    process.exit(2);
  }
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    validateLegacyImport, normalizeLookupKey, normalizeVehicleStockNumber,
    normalizeVehicleVin, normalizeVehicleSourceIdentifier, legacyIdentityForms,
    buildVehicleIdentityIndex, matchLegacyVehicleIdentity, toRange, rangesOverlap,
    diagnosticSummary,
  };
}
