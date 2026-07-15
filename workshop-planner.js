'use strict';

const WORKSHOP_PLAN_STORAGE_KEY = 'vehicleTrackingCoreWorkshopPlan:v1';
const WORKSHOP_VIEW_STORAGE_KEY = 'vehicleTrackingCoreWorkshopView:v1';
const WORKSHOP_BAY_SETUP_STORAGE_KEY = 'vehicleTrackingCoreWorkshopBaySetup:v1';
const WORKSHOP_START_HOUR = 8;
const WORKSHOP_END_HOUR = 16;
const WORKSHOP_DAY_MINUTES = (WORKSHOP_END_HOUR - WORKSHOP_START_HOUR) * 60;
const WORKSHOP_SNAP_MINUTES = 15;
const WORKSHOP_DEFAULT_HOURS = 3;
const WORKSHOP_STAGE_SEQUENCE = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'SUBLET'];

if (typeof CRM_BACKUP_STORAGE_KEYS !== 'undefined' && !CRM_BACKUP_STORAGE_KEYS.includes(WORKSHOP_PLAN_STORAGE_KEY)) {
  CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_PLAN_STORAGE_KEY);
}
if (typeof CRM_BACKUP_STORAGE_KEYS !== 'undefined' && !CRM_BACKUP_STORAGE_KEYS.includes(WORKSHOP_BAY_SETUP_STORAGE_KEY)) {
  CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_BAY_SETUP_STORAGE_KEY);
}

function workshopPad(value) {
  return String(value).padStart(2, '0');
}

function workshopDateKey(date = new Date()) {
  return `${date.getFullYear()}-${workshopPad(date.getMonth() + 1)}-${workshopPad(date.getDate())}`;
}

function workshopDateFromKey(value = '') {
  const match = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return null;
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), WORKSHOP_START_HOUR, 0, 0, 0);
  return Number.isNaN(date.getTime()) ? null : date;
}

function workshopIsWorkday(date = new Date()) {
  const day = date.getDay();
  return day >= 1 && day <= 5;
}

function workshopCoerceWorkDate(date = new Date(), direction = 1) {
  const next = new Date(date);
  next.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  const step = direction < 0 ? -1 : 1;
  while (!workshopIsWorkday(next)) next.setDate(next.getDate() + step);
  return next;
}

function workshopShiftWorkday(date = new Date(), amount = 1) {
  const next = workshopCoerceWorkDate(date, amount < 0 ? -1 : 1);
  let remaining = Math.abs(Number(amount) || 0);
  const step = amount < 0 ? -1 : 1;
  while (remaining > 0) {
    next.setDate(next.getDate() + step);
    if (workshopIsWorkday(next)) remaining -= 1;
  }
  return next;
}

function workshopWeekStart(value = new Date()) {
  const date = value instanceof Date ? new Date(value) : (workshopDateFromKey(value) || new Date(value));
  const safe = Number.isNaN(date.getTime()) ? new Date() : date;
  safe.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  const day = safe.getDay();
  const offset = day === 0 ? -6 : 1 - day;
  safe.setDate(safe.getDate() + offset);
  return safe;
}

function workshopWeekDates(value = new Date()) {
  const start = workshopWeekStart(value);
  return Array.from({ length: 5 }, (_, index) => workshopShiftWorkday(start, index));
}

function workshopSnapMinutes(value = 0) {
  return Math.round(Number(value || 0) / WORKSHOP_SNAP_MINUTES) * WORKSHOP_SNAP_MINUTES;
}

function workshopClampStartMinutes(value = 0) {
  return Math.max(0, Math.min(WORKSHOP_DAY_MINUTES - WORKSHOP_SNAP_MINUTES, workshopSnapMinutes(value)));
}

function workshopClampLineHours(value = 1) {
  const requestedMinutes = workshopSnapMinutes(Math.max(WORKSHOP_SNAP_MINUTES, Number(value || 1) * 60));
  return requestedMinutes / 60;
}

function workshopClampDurationHours(value = WORKSHOP_DEFAULT_HOURS) {
  return workshopClampLineHours(value || WORKSHOP_DEFAULT_HOURS);
}

function workshopIntervalsOverlap(startA, endA, startB, endB) {
  return Number(startA) < Number(endB) && Number(startB) < Number(endA);
}

function workshopMinuteOffset(date = new Date()) {
  return (date.getHours() - WORKSHOP_START_HOUR) * 60 + date.getMinutes();
}

function workshopDateAtOffset(dateKey, minuteOffset = 0) {
  const date = workshopDateFromKey(dateKey) || workshopCoerceWorkDate(new Date());
  date.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  date.setMinutes(workshopClampStartMinutes(minuteOffset));
  return date;
}

function workshopMoveToNextWorkStart(date = new Date()) {
  const next = new Date(date);
  next.setDate(next.getDate() + 1);
  next.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  return workshopCoerceWorkDate(next, 1);
}

function workshopMoveToPreviousWorkEnd(date = new Date()) {
  const previous = new Date(date);
  previous.setDate(previous.getDate() - 1);
  const coerced = workshopCoerceWorkDate(previous, -1);
  coerced.setHours(WORKSHOP_END_HOUR, 0, 0, 0);
  return coerced;
}

function workshopNormalizeStartDate(value = new Date()) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date)) {
    date = workshopCoerceWorkDate(date, 1);
    date.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
    return date;
  }
  const offset = workshopMinuteOffset(date);
  if (offset < 0) {
    date.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
    return date;
  }
  if (offset >= WORKSHOP_DAY_MINUTES) return workshopMoveToNextWorkStart(date);
  date.setSeconds(0, 0);
  const snapped = workshopClampStartMinutes(offset);
  date.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  date.setMinutes(snapped);
  return date;
}

function workshopLatestWorkMoment(value = new Date()) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date)) return workshopMoveToPreviousWorkEnd(date);
  const offset = workshopMinuteOffset(date);
  if (offset < 0) return workshopMoveToPreviousWorkEnd(date);
  if (offset >= WORKSHOP_DAY_MINUTES) {
    date.setHours(WORKSHOP_END_HOUR, 0, 0, 0);
    return date;
  }
  date.setSeconds(0, 0);
  const snapped = Math.floor(offset / WORKSHOP_SNAP_MINUTES) * WORKSHOP_SNAP_MINUTES;
  date.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  date.setMinutes(snapped);
  return date;
}

function workshopAddWorkMinutes(startValue = new Date(), minutes = 0) {
  let current = workshopNormalizeStartDate(startValue);
  let remaining = Math.max(0, Number(minutes) || 0);
  while (remaining > 0.0001) {
    const available = Math.max(0, WORKSHOP_DAY_MINUTES - workshopMinuteOffset(current));
    if (remaining <= available + 0.0001) {
      current = new Date(current.getTime() + remaining * 60000);
      return current;
    }
    remaining -= available;
    current = workshopMoveToNextWorkStart(current);
  }
  return current;
}

function workshopWorkMinutesBetween(startValue, endValue) {
  let cursor = workshopNormalizeStartDate(startValue);
  const end = endValue instanceof Date ? new Date(endValue) : new Date(endValue);
  if (Number.isNaN(end.getTime()) || end <= cursor) return 0;
  let minutes = 0;
  while (cursor < end) {
    const dayEnd = new Date(cursor);
    dayEnd.setHours(WORKSHOP_END_HOUR, 0, 0, 0);
    const segmentEnd = end < dayEnd ? end : dayEnd;
    if (segmentEnd > cursor) minutes += (segmentEnd - cursor) / 60000;
    if (end <= dayEnd) break;
    cursor = workshopMoveToNextWorkStart(cursor);
  }
  return minutes;
}

function workshopEntryStart(entry = {}) {
  return workshopNormalizeStartDate(parseIsoTimestamp(entry.startAt || '') || new Date());
}

function workshopEntryEnd(entry = {}) {
  return workshopAddWorkMinutes(workshopEntryStart(entry), workshopClampDurationHours(entry.hours) * 60);
}

function workshopEntryIsOvertime(entry = {}, now = new Date()) {
  if (!workshopEntryIsLive(entry)) return false;
  return workshopLatestWorkMoment(now) > workshopEntryEnd(entry);
}

function workshopEntryEffectiveEnd(entry = {}, now = new Date()) {
  const plannedEnd = workshopEntryEnd(entry);
  if (!workshopEntryIsOvertime(entry, now)) return plannedEnd;
  const latest = workshopLatestWorkMoment(now);
  return workshopMinuteOffset(latest) >= WORKSHOP_DAY_MINUTES ? latest : workshopAddWorkMinutes(latest, WORKSHOP_SNAP_MINUTES);
}

function workshopEntrySegmentForDate(entry = {}, dateKey = '', now = new Date()) {
  const dayStart = workshopDateFromKey(dateKey);
  if (!dayStart || !workshopIsWorkday(dayStart)) return null;
  dayStart.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  const dayEnd = new Date(dayStart);
  dayEnd.setHours(WORKSHOP_END_HOUR, 0, 0, 0);
  const start = workshopEntryStart(entry);
  const end = workshopEntryEffectiveEnd(entry, now);
  if (end <= dayStart || start >= dayEnd) return null;
  const segmentStart = start > dayStart ? start : dayStart;
  const segmentEnd = end < dayEnd ? end : dayEnd;
  const startMinutes = Math.max(0, workshopMinuteOffset(segmentStart));
  const endMinutes = Math.min(WORKSHOP_DAY_MINUTES, segmentEnd >= dayEnd ? WORKSHOP_DAY_MINUTES : workshopMinuteOffset(segmentEnd));
  return {
    start: startMinutes,
    end: Math.max(startMinutes + WORKSHOP_SNAP_MINUTES, endMinutes),
    continuesFromPrevious: start < dayStart,
    continuesNext: end > dayEnd,
  };
}

function workshopLoadPlans() {
  const rows = typeof loadJson === 'function' ? loadJson(WORKSHOP_PLAN_STORAGE_KEY, []) : [];
  return Array.isArray(rows) ? rows
    .filter(row => row && row.id && row.vehicleKey && WORKSHOP_STAGE_SEQUENCE.includes(row.stage))
    .map(row => row.status === 'completed' ? row : { ...row, hours: workshopClampDurationHours(row.hours) }) : [];
}

function workshopSavePlans(rows = []) {
  if (typeof saveJson !== 'function') return;
  const operation = () => saveJson(WORKSHOP_PLAN_STORAGE_KEY, rows);
  if (typeof runStorageTransaction === 'function') runStorageTransaction('Workshop planner save', [WORKSHOP_PLAN_STORAGE_KEY], operation);
  else operation();
  if (typeof app !== 'undefined') {
    const state = workshopState();
    state.lastSavedAt = new Date().toISOString();
  }
}

function workshopRequireOperatorProfile() {
  const authenticatedName = typeof window !== 'undefined' ? String(window.PDC_AUTH_CONTEXT?.displayName || window.PDC_AUTH_CONTEXT?.email || '').trim() : '';
  const authenticatedRole = typeof window !== 'undefined' ? String(window.PDC_AUTH_CONTEXT?.role || '').trim() : '';
  if (authenticatedName && authenticatedRole) return { name: authenticatedName, role: authenticatedRole };
  const name = typeof localStorage !== 'undefined' && typeof OPERATOR_NAME_KEY !== 'undefined' ? String(localStorage.getItem(OPERATOR_NAME_KEY) || '').trim() : '';
  const role = typeof localStorage !== 'undefined' && typeof OPERATOR_ROLE_KEY !== 'undefined' ? String(localStorage.getItem(OPERATOR_ROLE_KEY) || '').trim() : '';
  if (name && role) return { name, role };
  window.alert('Set your operator name and role before changing the Workshop Planner. No workshop data was changed.');
  return null;
}

function workshopPersistPlanAction(label = 'Workshop planner update', rows = [], vehicle = null, action = '', details = {}) {
  const operator = workshopRequireOperatorProfile();
  if (!operator) return false;
  const keys = [WORKSHOP_PLAN_STORAGE_KEY];
  if (typeof AUDIT_LOG_KEY !== 'undefined') keys.push(AUDIT_LOG_KEY);
  const operation = () => {
    const auditDetails = { by: operator.name, role: operator.role, ...details };
    if (vehicle && action && typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, action, auditDetails);
    workshopSavePlans(rows);
  };
  if (typeof runStorageTransaction === 'function') return runStorageTransaction(label, keys, operation) !== false;
  return operation() !== false;
}

function workshopRunVehiclePlanTransaction(label = 'Workshop live update', vehicle = null, operation = () => undefined) {
  const keys = [WORKSHOP_PLAN_STORAGE_KEY];
  if (typeof EDITS_KEY !== 'undefined') keys.push(EDITS_KEY);
  if (typeof AUDIT_LOG_KEY !== 'undefined') keys.push(AUDIT_LOG_KEY);
  const snapshot = vehicle && typeof vehicle === 'object' ? { ...vehicle } : null;
  try {
    if (typeof runStorageTransaction === 'function') runStorageTransaction(label, keys, operation);
    else operation();
    return true;
  } catch (error) {
    if (snapshot && vehicle) {
      Object.keys(vehicle).forEach(key => { if (!Object.prototype.hasOwnProperty.call(snapshot, key)) delete vehicle[key]; });
      Object.assign(vehicle, snapshot);
    }
    window.alert(error.message || String(error));
    return false;
  }
}

function workshopPersistVehiclePlanAction(label = 'Workshop live update', rows = [], vehicle = null, vehicleUpdates = {}, action = '', details = {}) {
  const operator = workshopRequireOperatorProfile();
  if (!operator) return false;
  return workshopRunVehiclePlanTransaction(label, vehicle, () => {
    if (vehicle && Object.keys(vehicleUpdates || {}).length && !saveVehicleEdits(vehicleKey(vehicle), vehicleUpdates, { render: false })) {
      throw new Error('The vehicle update failed.');
    }
    if (vehicle && action) recordVehicleAudit(vehicle, action, { by: operator.name, role: operator.role, ...details });
    workshopSavePlans(rows);
  });
}

function workshopOwnedBlockUpdates(entry = {}, reason = '', now = '', operator = '') {
  const clean = value => String(value || '').trim();
  return {
    pdcWorkshopBlocked: true,
    pdcWorkshopBlockPlanId: clean(entry.id),
    pdcWorkshopBlockReason: clean(reason),
    pdcWorkshopBlockedAt: now,
    pdcWorkshopBlockedBy: operator,
  };
}

function workshopOwnedBlockClearUpdates(entry = {}, vehicle = {}, now = '', operator = '') {
  const clean = value => String(value || '').trim();
  if (!vehicle.pdcWorkshopBlocked || clean(vehicle.pdcWorkshopBlockPlanId) !== clean(entry.id)) return {};
  return {
    pdcWorkshopBlocked: false,
    pdcWorkshopBlockPlanId: '',
    pdcWorkshopBlockReason: '',
    pdcWorkshopBlockedAt: '',
    pdcWorkshopBlockedBy: '',
    pdcWorkshopBlockClearedAt: now,
    pdcWorkshopBlockClearedBy: operator,
  };
}

function workshopLoadBaySetup() {
  const saved = typeof loadJson === 'function' ? loadJson(WORKSHOP_BAY_SETUP_STORAGE_KEY, {}) : {};
  return saved && typeof saved === 'object' && !Array.isArray(saved) ? saved : {};
}

function workshopSaveBaySetup(setup = {}) {
  if (typeof saveJson === 'function') saveJson(WORKSHOP_BAY_SETUP_STORAGE_KEY, setup);
}

function workshopBaySetupKey(stage = '', bay = 0) {
  return `${normalizePmbStage(stage)}:${Number(bay) || 1}`;
}

function workshopBayMechanic(stage = '', bay = 0) {
  return cleanNavisionText(workshopLoadBaySetup()[workshopBaySetupKey(stage, bay)] || '');
}

function workshopStageBayCount(stage = '') {
  return normalizePmbStage(stage) === 'SUBLET' ? 1 : pmbStageBayCount(stage);
}

function workshopEstimatedHoursMap(vehicle = {}) {
  const value = vehicle.workshopEstimatedHoursByStage;
  return value && typeof value === 'object' && !Array.isArray(value) ? { ...value } : {};
}

function workshopEstimatedHours(vehicle = {}, stage = '') {
  const saved = Number(workshopEstimatedHoursMap(vehicle)[normalizePmbStage(stage)]);
  return Number.isFinite(saved) && saved > 0 ? workshopClampDurationHours(saved) : '';
}

function workshopAdditionalHoursMap(vehicle = {}) {
  const value = vehicle.workshopAdditionalHoursByStage;
  return value && typeof value === 'object' && !Array.isArray(value) ? { ...value } : {};
}

function workshopJobLineAssignments(vehicle = {}) {
  const value = vehicle.workshopJobLineAssignments;
  return value && typeof value === 'object' && !Array.isArray(value) ? { ...value } : {};
}

function workshopJobLineId(text = '', index = 0) {
  const source = `${index}:${cleanNavisionText(text || '').toLowerCase()}`;
  let hash = 2166136261;
  for (let position = 0; position < source.length; position += 1) {
    hash ^= source.charCodeAt(position);
    hash = Math.imul(hash, 16777619);
  }
  return `job-${(hash >>> 0).toString(36)}`;
}

function workshopImportedJobLines(vehicle = {}) {
  const structured = typeof vehiclePdcJobLines === 'function'
    ? vehiclePdcJobLines(vehicle).filter(line => line.confirmed === true && Number(line.confirmedHours) > 0 && WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(line.category || line.stage || '')))
    : [];
  const confirmed = structured.map((line, index) => ({
    id: String(line.id || workshopJobLineId(line.description, index)),
    text: cleanNavisionText(line.description || line.code || 'Reviewed work item'),
    index,
    stage: normalizePmbStage(line.category || line.stage),
    hours: workshopClampLineHours(Number(line.confirmedHours)),
    confirmed: true,
    source: 'reviewed-job-line',
  }));
  const confirmedDescriptions = new Set(confirmed.map(line => line.text.toLowerCase()));
  const tasks = Array.isArray(vehicle.poTasks) ? vehicle.poTasks : [];
  const legacy = tasks.map((text, index) => ({ id: workshopJobLineId(text, index), text: cleanNavisionText(text || ''), index, source: 'legacy-po-task' }))
    .filter(line => line.text && !confirmedDescriptions.has(line.text.toLowerCase()));
  return [...confirmed, ...legacy];
}

function workshopDetectedStageForLine(text = '', vehicle = {}) {
  const value = cleanNavisionText(text || '');
  if (/\bbus\s*4\s*x\s*4\b/i.test(value)) return 'BUS_4X4';
  if (/\b(sublet|sub-let|sub let|outsourc|external)\b/i.test(value)) return 'SUBLET';
  const defs = typeof PRODUCTION_FLOW_DEFS !== 'undefined' ? PRODUCTION_FLOW_DEFS : [];
  const detected = defs.find(def => def.search?.test(value));
  if (detected?.stage) return normalizePmbStage(detected.stage);
  if (/\bbus\s*4\s*x\s*4\b/i.test(cleanNavisionText(vehicle.masterBuildDepartment || vehicle.masterAdditionalPitting || ''))) return 'BUS_4X4';
  return normalizePmbStage(inferredPmbStage(vehicle));
}

function workshopJobLineHours(text = '') {
  const match = cleanNavisionText(text || '').match(/\b(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b/i);
  const hours = match ? Number(match[1]) : 1;
  return Number.isFinite(hours) && hours > 0 ? workshopClampLineHours(hours) : 1;
}

function workshopResolvedJobLines(vehicle = {}) {
  const assignments = workshopJobLineAssignments(vehicle);
  return workshopImportedJobLines(vehicle).map(line => {
    const saved = assignments[line.id] || {};
    const stage = WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(saved.stage))
      ? normalizePmbStage(saved.stage)
      : WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(line.stage))
        ? normalizePmbStage(line.stage)
        : workshopDetectedStageForLine(line.text, vehicle);
    const savedHours = Number(saved.hours);
    const importedHours = Number(line.hours);
    return {
      ...line,
      stage,
      hours: Number.isFinite(savedHours) && savedHours > 0
        ? workshopClampLineHours(savedHours)
        : Number.isFinite(importedHours) && importedHours > 0
          ? workshopClampLineHours(importedHours)
          : workshopJobLineHours(line.text),
    };
  });
}

function workshopStageJobLines(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  return workshopResolvedJobLines(vehicle).filter(line => line.stage === normalizedStage);
}

function workshopCalculatedStageHours(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  const importedHours = workshopStageJobLines(vehicle, normalizedStage).reduce((sum, line) => sum + Number(line.hours || 0), 0);
  const additionalHours = Number(workshopAdditionalHoursMap(vehicle)[normalizedStage] || 0);
  const total = importedHours + (Number.isFinite(additionalHours) ? Math.max(0, additionalHours) : 0);
  if (total > 0) return workshopClampDurationHours(total);
  return workshopEstimatedHours(vehicle, normalizedStage) || WORKSHOP_DEFAULT_HOURS;
}

function workshopLoadView() {
  const saved = typeof loadJson === 'function' ? loadJson(WORKSHOP_VIEW_STORAGE_KEY, {}) : {};
  const rawDate = workshopDateFromKey(saved?.date || '') || new Date();
  const date = workshopCoerceWorkDate(rawDate, 1);
  return {
    date: workshopDateKey(date),
    stage: WORKSHOP_STAGE_SEQUENCE.includes(saved?.stage) ? saved.stage : 'FABRICATION',
    selectedPlanId: '',
    search: '',
  };
}

function workshopSaveView(state = {}) {
  if (typeof saveJson === 'function') saveJson(WORKSHOP_VIEW_STORAGE_KEY, { date: state.date, stage: state.stage });
}

function workshopState() {
  if (!app.workshopPlanner) app.workshopPlanner = workshopLoadView();
  return app.workshopPlanner;
}

function workshopVehicle(key = '') {
  const cleanKey = String(key || '').trim();
  return cleanKey && typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null;
}

function workshopPlanId(vehicleKeyValue = '', stage = '') {
  return `${normalizePmbStage(stage)}::${String(vehicleKeyValue || '').trim()}`;
}

function workshopEntryDate(entry = {}) {
  const date = parseIsoTimestamp(entry.startAt || '');
  return date ? workshopDateKey(date) : '';
}

function workshopEntryInterval(entry = {}) {
  const startDate = workshopEntryStart(entry);
  const hours = workshopClampDurationHours(entry.hours);
  const endDate = workshopAddWorkMinutes(startDate, hours * 60);
  return { startDate, endDate, start: workshopMinuteOffset(startDate), hours };
}

function workshopHasConflict(candidate = {}, rows = workshopLoadPlans(), now = new Date()) {
  if (!candidate.bay || candidate.status === 'completed') return null;
  const candidateStart = workshopEntryStart(candidate);
  const candidateEnd = workshopEntryEffectiveEnd(candidate, now);
  return rows.find(row => {
    if (row.id === candidate.id || row.status === 'completed') return false;
    if (row.stage !== candidate.stage || Number(row.bay) !== Number(candidate.bay)) return false;
    const otherStart = workshopEntryStart(row);
    const otherEnd = workshopEntryEffectiveEnd(row, now);
    return workshopIntervalsOverlap(candidateStart.getTime(), candidateEnd.getTime(), otherStart.getTime(), otherEnd.getTime());
  }) || null;
}

function workshopRequireNoBayConflict(candidate = {}, rows = workshopLoadPlans()) {
  const conflict = workshopHasConflict(candidate, rows);
  if (!conflict) return true;
  const vehicle = workshopVehicle(conflict.vehicleKey);
  const identity = vehicle ? (displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'another vehicle') : 'another vehicle';
  const area = candidate.stage === 'SUBLET' ? 'the Sublet provider row' : `${pmbStageLabel(candidate.stage)} Bay ${candidate.bay}`;
  window.alert(`${area} already has ${identity} booked during that time. Overlapping workshop bookings are blocked; choose another bay or time.`);
  return false;
}

function workshopAssigneeConflict(entry = {}, rows = workshopLoadPlans()) {
  const assignee = cleanNavisionText(entry.assignee || '').toLowerCase();
  if (!assignee || entry.stage === 'SUBLET' || entry.status === 'completed') return null;
  const start = workshopEntryStart(entry);
  const end = workshopEntryEffectiveEnd(entry);
  return rows.find(other => {
    if (other.id === entry.id || other.status === 'completed' || other.stage === 'SUBLET') return false;
    if (other.stage === entry.stage && Number(other.bay) === Number(entry.bay)) return false;
    if (cleanNavisionText(other.assignee || '').toLowerCase() !== assignee) return false;
    const otherStart = workshopEntryStart(other);
    const otherEnd = workshopEntryEffectiveEnd(other);
    return workshopIntervalsOverlap(start.getTime(), end.getTime(), otherStart.getTime(), otherEnd.getTime());
  }) || null;
}

function workshopEntryHasAssigneeConflict(entry = {}, rows = workshopLoadPlans()) {
  return Boolean(workshopAssigneeConflict(entry, rows));
}

function workshopRequireAvailableAssignee(entry = {}, rows = workshopLoadPlans()) {
  const conflict = workshopAssigneeConflict(entry, rows);
  if (!conflict) return true;
  const vehicle = workshopVehicle(conflict.vehicleKey);
  const identity = vehicle ? (displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'another vehicle') : 'another vehicle';
  window.alert(`${entry.assignee} is already booked on ${identity} at that time. Move one booking or choose another mechanic.`);
  return false;
}

function workshopEntryIsLive(entry = {}) {
  if (!['started', 'stoppage'].includes(entry.status)) return false;
  if (entry.stage === 'SUBLET') return true;
  const vehicle = workshopVehicle(entry.vehicleKey);
  return Boolean(vehicle && Number(pmbBayNumber(vehicle, entry.stage)) === Number(entry.bay));
}

function workshopCascadePlans(rows = workshopLoadPlans()) {
  // Collision policy: never move another booking implicitly. All newly created or edited
  // overlaps are rejected before persistence, while existing imported/legacy rows remain visible.
  return { rows: rows.map(entry => ({ ...entry, hours: entry.status === 'completed' ? entry.hours : workshopClampDurationHours(entry.hours) })), changed: false };
}

function workshopCascadeAndSave(rows = workshopLoadPlans(), now = new Date()) {
  const cascaded = workshopCascadePlans(rows, now);
  if (cascaded.changed) workshopSavePlans(cascaded.rows);
  return cascaded.rows;
}

function workshopTimeLabelFromMinutes(minutes = 0) {
  const total = WORKSHOP_START_HOUR * 60 + Number(minutes || 0);
  const hour = Math.floor(total / 60);
  const minute = total % 60;
  const suffix = hour >= 12 ? 'pm' : 'am';
  const displayHour = hour % 12 || 12;
  return `${displayHour}:${workshopPad(minute)} ${suffix}`;
}

function workshopEntryTimeLabel(entry = {}) {
  const interval = workshopEntryInterval(entry);
  const sameDay = workshopDateKey(interval.startDate) === workshopDateKey(interval.endDate);
  const start = interval.startDate.toLocaleString('en-AU', sameDay ? { hour: 'numeric', minute: '2-digit' } : { weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  const end = interval.endDate.toLocaleString('en-AU', sameDay ? { hour: 'numeric', minute: '2-digit' } : { weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  return `${start}–${end}`;
}

function workshopDateLabel(dateKey = '') {
  const date = workshopDateFromKey(dateKey);
  return date ? date.toLocaleDateString('en-AU', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '';
}

function workshopSyncCompletedPlans(rows = workshopLoadPlans()) {
  let changed = false;
  const next = rows.map(entry => {
    if (entry.status === 'completed') return entry;
    const vehicle = workshopVehicle(entry.vehicleKey);
    const def = vehicle ? pmbStageJobDef(entry.stage) : null;
    if (!vehicle || !def || !pdcJobComplete(vehicle, def)) return entry;
    changed = true;
    return { ...entry, status: 'completed', completedAt: vehicle[def.completeAtKey] || nowIsoString(), updatedAt: nowIsoString() };
  });
  if (changed) workshopSavePlans(next);
  return next;
}

function workshopStageVehicles(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (typeof pmbVehiclesNeedingStationWork === 'function' && normalizedStage !== 'SUBLET') {
    return pmbVehiclesNeedingStationWork(normalizedStage);
  }
  const def = pmbStageJobDef(normalizedStage);
  return app.data.filter(vehicle => {
    if (statusCategory(vehicle) !== 'pmb') return false;
    const currentStage = normalizePmbStage(inferredPmbStage(vehicle));
    if (normalizedStage === 'SUBLET') {
      const hasSubletJobLine = workshopImportedJobLines(vehicle)
        .some(line => workshopDetectedStageForLine(line.text, vehicle) === 'SUBLET');
      return currentStage === 'SUBLET'
        || hasSubletJobLine
        || Boolean(cleanNavisionText(vehicle.pmbSubletProvider || vehicle.pmbSubletBookingDate || vehicle.pmbSubletExpectedReturnDate || ''));
    }
    const requiredAndIncomplete = Boolean(def && pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def));
    const currentAndIncomplete = currentStage === normalizedStage && (!def || !pdcJobComplete(vehicle, def));
    return requiredAndIncomplete || currentAndIncomplete;
  }).sort((a, b) => String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || '')));
}

function workshopVehicleSearchText(vehicle = {}) {
  return [vehicleKey(vehicle), displayStockNumber(vehicle), vehicle.keyNumber, vehicle.pdcJobcard, vehicleCustomerName(vehicle), vehicle.vehicle, vehicle.toyotaVehicle, consultantName(vehicle)]
    .filter(Boolean).join(' ').toLowerCase();
}

function workshopSearchRank(vehicle = {}, query = '') {
  const clean = cleanNavisionText(query || '').toLowerCase();
  const exactFields = [vehicleKey(vehicle), displayStockNumber(vehicle), vehicleKeyNumber(vehicle), vehicleJobcardNumber(vehicle)]
    .map(value => cleanNavisionText(value || '').toLowerCase());
  if (exactFields.includes(clean)) return 0;
  const customer = cleanNavisionText(vehicleCustomerName(vehicle) || '').toLowerCase();
  if (customer === clean) return 1;
  if (exactFields.some(value => value.startsWith(clean))) return 2;
  if (customer.startsWith(clean)) return 3;
  return 4;
}

function workshopFindSearchVehicle(query = '') {
  const clean = cleanNavisionText(query || '').toLowerCase();
  if (!clean) return null;
  return app.data.filter(vehicle => statusCategory(vehicle) === 'pmb' && workshopVehicleSearchText(vehicle).includes(clean))
    .sort((a, b) => workshopSearchRank(a, clean) - workshopSearchRank(b, clean))[0] || null;
}

function workshopScrollToHighlightedVehicle(root = document) {
  const key = workshopState().highlightVehicleKey;
  if (!key) return;
  window.requestAnimationFrame(() => {
    const target = Array.from(root.querySelectorAll('[data-workshop-locate-key]')).find(element => element.dataset.workshopLocateKey === key);
    target?.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
  });
}

function workshopRevealSearchMatch(query = '') {
  const state = workshopState();
  state.search = cleanNavisionText(query || '');
  if (!state.search) {
    state.highlightVehicleKey = '';
    state.selectedPlanId = '';
    renderWorkshopPlanner();
    return;
  }
  const vehicle = workshopFindSearchVehicle(state.search);
  if (!vehicle) {
    state.highlightVehicleKey = '';
    renderWorkshopPlanner();
    return;
  }
  const key = vehicleKey(vehicle);
  const plans = workshopLoadPlans().filter(entry => entry.vehicleKey === key && entry.status !== 'completed')
    .sort((a, b) => (a.stage === state.stage ? -1 : 0) - (b.stage === state.stage ? -1 : 0) || workshopEntryStart(a) - workshopEntryStart(b));
  const plan = plans[0];
  state.highlightVehicleKey = key;
  if (plan) {
    state.stage = plan.stage;
    state.date = workshopEntryDate(plan);
    state.selectedPlanId = plan.id;
    workshopSaveView(state);
    renderWorkshopPlanner();
    return;
  }
  const stage = normalizePmbStage(inferredPmbStage(vehicle));
  if (WORKSHOP_STAGE_SEQUENCE.includes(stage)) state.stage = stage;
  state.selectedPlanId = '';
  workshopSaveView(state);
  renderWorkshopPlanner();
  if (!stage) openVehicleModal(key);
}

function workshopPartsSummary(vehicle = {}) {
  const status = partsDepartmentStatus(vehicle);
  const label = partsDepartmentStatusLabel(status);
  const eta = partsWorstEtaLabel(vehicle);
  const countdown = partsWorstEtaCountdownLabel(vehicle);
  return {
    status,
    label,
    eta,
    text: `${label}${eta && !['issued', 'notrequired'].includes(status) ? ` · ETA ${eta}${countdown ? ` (${countdown})` : ''}` : ''}`,
  };
}

function workshopNextWorkdayDate(anchor = new Date()) {
  const next = anchor instanceof Date ? new Date(anchor) : new Date(anchor);
  if (Number.isNaN(next.getTime())) return workshopNextWorkdayDate(new Date());
  next.setDate(next.getDate() + 1);
  return workshopCoerceWorkDate(next, 1);
}

function workshopNextDayFittingPartsWarnings(anchor = new Date(), rows = workshopLoadPlans()) {
  const targetDate = workshopNextWorkdayDate(anchor);
  const dateKey = workshopDateKey(targetDate);
  const seen = new Set();
  const warnings = [];
  (Array.isArray(rows) ? rows : []).forEach(entry => {
    if (normalizePmbStage(entry?.stage) !== 'FITTING' || Number(entry.bay) < 1 || Number(entry.bay) > workshopStageBayCount('FITTING') || entry.status === 'completed' || !workshopEntrySegmentForDate(entry, dateKey)) return;
    const vehicle = workshopVehicle(entry.vehicleKey);
    if (!vehicle || seen.has(entry.vehicleKey)) return;
    const partsStatus = partsDepartmentStatus(vehicle);
    if (['onorder', 'issued', 'notrequired'].includes(partsStatus)) return;
    seen.add(entry.vehicleKey);
    warnings.push({ entry, vehicle, partsStatus });
  });
  warnings.sort((a, b) => Number(a.entry.bay) - Number(b.entry.bay) || workshopEntryStart(a.entry) - workshopEntryStart(b.entry));
  return { targetDate, dateKey, warnings };
}

function workshopNextDayFittingWarningEmailBody(result = {}) {
  const targetDate = result.targetDate instanceof Date ? result.targetDate : workshopNextWorkdayDate();
  const warnings = Array.isArray(result.warnings) ? result.warnings : [];
  const dateLabel = targetDate.toLocaleDateString('en-AU', { weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' });
  return [
    'Hi PMG team,',
    '',
    'WARNING — the following vehicles are booked into fitting bays on the next workday without parts confirmed:',
    `Booking date: ${dateLabel}`,
    `Affected vehicles: ${warnings.length}`,
    '',
    ...warnings.flatMap(({ entry, vehicle, partsStatus }) => {
      const segment = workshopEntrySegmentForDate(entry, workshopDateKey(targetDate));
      const start = segment ? workshopTimeLabelFromMinutes(segment.start) : workshopEntryTimeLabel(entry);
      const eta = partsWorstEtaLabel(vehicle);
      return [
        `- JC ${vehicleJobcardNumber(vehicle) || 'TBA'} · Stock ${displayStockNumber(vehicle) || entry.vehicleKey || 'TBA'}`,
        `  ${vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle'} · ${vehicleCustomerName(vehicle) || 'Unknown customer'}`,
        `  Fitting Bay ${entry.bay} from ${start} · Parts: ${partsDepartmentStatusLabel(partsStatus)}${eta ? ` · ETA ${eta}` : ''}`,
      ];
    }),
    '',
    'Please confirm the required parts before these vehicles enter the fitting bays, or update the workshop booking.',
    '',
    'Kind Regards,',
  ].join('\n');
}

function draftWorkshopNextDayFittingWarningEmail() {
  const result = workshopNextDayFittingPartsWarnings(new Date());
  if (!result.warnings.length) {
    window.alert(`No next-workday Fitting bookings were found with unconfirmed parts for ${result.targetDate.toLocaleDateString('en-AU')}.`);
    return false;
  }
  const recipient = '';
  const dateLabel = result.targetDate.toLocaleDateString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' });
  const subject = `PDC WARNING - Fitting bookings without confirmed parts - ${dateLabel}`;
  result.warnings.forEach(({ vehicle }) => {
    if (typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, 'Next-day fitting parts warning email drafted', { recipient: 'Selected in email client', bookingDate: result.dateKey });
  });
  window.location.href = `mailto:${encodeURIComponent(recipient)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(workshopNextDayFittingWarningEmailBody(result))}`;
  return true;
}

function workshopQueueCardHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const blocked = isPdcBlocked(vehicle);
  const parts = workshopPartsSummary(vehicle);
  const highlighted = workshopState().highlightVehicleKey === key;
  return `<article class="workshop-queue-card ${blocked ? 'is-blocked' : ''} ${highlighted ? 'is-search-match' : ''}" draggable="true" data-workshop-vehicle-key="${escapeHtml(key)}" data-workshop-job-vehicle="${escapeHtml(key)}" data-workshop-locate-key="${escapeHtml(key)}" title="Drag onto a bay, or use Schedule">
    <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')} · ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small class="workshop-parts-line parts-${escapeHtml(parts.status)}">Parts: ${escapeHtml(parts.text)}</small>
    ${blocked ? '<em>STOPPAGE</em>' : ''}
    <button class="workshop-schedule-button" type="button" data-workshop-schedule-vehicle="${escapeHtml(key)}">Schedule</button>
  </article>`;
}

function workshopOtherDateCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const date = parseIsoTimestamp(entry.startAt || '');
  return `<button class="workshop-other-date-card" type="button" data-workshop-open-plan="${escapeHtml(entry.id)}" data-workshop-open-date="${escapeHtml(workshopEntryDate(entry))}">
    <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(date ? date.toLocaleDateString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit' }) : 'Date unknown')} · ${escapeHtml(entry.stage === 'SUBLET' ? 'Sublet' : `Bay ${entry.bay}`)}</span>
  </button>`;
}

function workshopPlanChipHtml(entry = {}, dateKey = '', rows = workshopLoadPlans()) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const segment = workshopEntrySegmentForDate(entry, dateKey);
  if (!segment) return '';
  const left = (segment.start / WORKSHOP_DAY_MINUTES) * 100;
  const width = ((segment.end - segment.start) / WORKSHOP_DAY_MINUTES) * 100;
  const actualBay = pmbBayNumber(vehicle, entry.stage);
  const started = entry.stage === 'SUBLET' ? workshopEntryIsLive(entry) : Number(actualBay) === Number(entry.bay);
  const blocked = isPdcBlocked(vehicle);
  const overtime = workshopEntryIsOvertime(entry);
  const assigneeConflict = workshopEntryHasAssigneeConflict(entry, rows);
  const selected = workshopState().selectedPlanId === entry.id;
  const highlighted = workshopState().highlightVehicleKey === entry.vehicleKey;
  const parts = workshopPartsSummary(vehicle);
  const draggable = entry.status === 'planned';
  const classes = [blocked ? 'is-blocked' : '', started ? 'is-started' : '', overtime ? 'is-overtime' : '', assigneeConflict ? 'has-assignee-conflict' : '', entry.status === 'stoppage' ? 'is-stoppage' : '', selected ? 'is-selected' : '', highlighted ? 'is-search-match' : '', segment.continuesFromPrevious ? 'continues-from-previous' : '', segment.continuesNext ? 'continues-next' : ''].filter(Boolean).join(' ');
  const conflictNote = assigneeConflict ? ` · WARNING: ${entry.assignee} is booked on another vehicle at this time` : '';
  return `<article class="workshop-plan-chip ${classes}" ${draggable ? 'draggable="true"' : ''} data-workshop-plan-id="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}" style="--plan-left:${left}%;--plan-width:${width}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · ${entry.hours}h total${conflictNote} · double-click for vehicle job${draggable ? ' · drag to reschedule' : ' · live job stays in its bay'}`)}">
    <button type="button" data-workshop-select-plan="${escapeHtml(entry.id)}">
      <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')} · ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
      <small>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</small>
      <small>${escapeHtml(`${entry.hours}h · Parts ${parts.label}${parts.eta && !['issued', 'notrequired'].includes(parts.status) ? ` · ETA ${parts.eta}` : ''}`)}</small>
    </button>
    <span class="workshop-plan-resize" data-workshop-resize-plan="${escapeHtml(entry.id)}" title="Drag to change duration"></span>
  </article>`;
}

function workshopCompletedCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const actual = Number(entry.actualHours);
  const timeSummary = Number.isFinite(actual) ? `Actual ${actual}h · Est ${entry.hours}h` : workshopEntryTimeLabel(entry);
  const highlighted = workshopState().highlightVehicleKey === entry.vehicleKey;
  return `<button class="workshop-completed-card ${highlighted ? 'is-search-match' : ''}" type="button" data-workshop-select-plan="${escapeHtml(entry.id)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}">
    <strong>✓ ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small>${escapeHtml(entry.stage === 'SUBLET' ? 'Sublet' : `Bay ${entry.bay}`)} · ${escapeHtml(timeSummary)}</small>
  </button>`;
}

function workshopTimeAxisHtml() {
  return Array.from({ length: WORKSHOP_END_HOUR - WORKSHOP_START_HOUR + 1 }, (_, index) => {
    const left = (index / (WORKSHOP_END_HOUR - WORKSHOP_START_HOUR)) * 100;
    return `<span style="left:${left}%">${escapeHtml(workshopTimeLabelFromMinutes(index * 60))}</span>`;
  }).join('');
}

function workshopBayRowsHtml(stage = '', dateKey = '', rows = []) {
  const count = workshopStageBayCount(stage);
  return Array.from({ length: count }, (_, index) => {
    const bay = index + 1;
    const plans = rows.filter(entry => entry.stage === stage && Number(entry.bay) === bay && entry.status !== 'completed' && workshopEntrySegmentForDate(entry, dateKey))
      .sort((a, b) => String(a.startAt).localeCompare(String(b.startAt)));
    const defaultAssignee = workshopBayMechanic(stage, bay);
    const bayLabel = stage === 'SUBLET' ? 'Sublet / Provider' : `Bay ${workshopPad(bay)}`;
    const assigneeLabel = stage === 'SUBLET' ? 'Default provider' : 'Bay mechanic';
    return `<div class="workshop-bay-row">
      <div class="workshop-bay-label"><div class="workshop-bay-label-heading"><strong>${escapeHtml(bayLabel)}</strong><button type="button" data-workshop-weekly-stage="${escapeHtml(stage)}" data-workshop-weekly-bay="${bay}">Week</button></div><span>${escapeHtml(stage === 'TYRE' && bay === 2 ? 'Wheel alignment' : plans.length ? `${plans.length} planned` : 'Available')}</span><label><small>${escapeHtml(assigneeLabel)}</small><select data-workshop-bay-mechanic-stage="${escapeHtml(stage)}" data-workshop-bay-mechanic-number="${bay}">${workshopAssigneeOptions(stage, defaultAssignee)}</select></label></div>
      <div class="workshop-bay-lane" data-workshop-drop-bay="${bay}" data-workshop-drop-stage="${escapeHtml(stage)}">
        ${plans.map(entry => workshopPlanChipHtml(entry, dateKey, rows)).join('')}
      </div>
    </div>`;
  }).join('');
}

function workshopMechanicOptions(selected = '') {
  const cleanSelected = cleanNavisionText(selected || '');
  const names = loadMechanics();
  const options = cleanSelected && !names.includes(cleanSelected) ? [cleanSelected, ...names] : names;
  return `<option value="">Unassigned</option>${options.map(name => `<option value="${escapeHtml(name)}"${name === cleanSelected ? ' selected' : ''}>${escapeHtml(name)}</option>`).join('')}`;
}

function workshopAssigneeOptions(stage = '', selected = '') {
  return normalizePmbStage(stage) === 'SUBLET' ? subletProviderOptionsHtml(selected) : workshopMechanicOptions(selected);
}

function workshopProgressSummary(entry = {}, now = new Date()) {
  if (entry.status === 'completed') {
    const actual = Number(entry.actualHours);
    return Number.isFinite(actual) ? `Completed ${actual.toFixed(2)}h · estimated ${entry.hours}h` : `Completed · estimated ${entry.hours}h`;
  }
  if (!['started', 'stoppage'].includes(entry.status)) return `Estimated ${entry.hours}h · not started`;
  const elapsed = workshopWorkMinutesBetween(workshopEntryStart(entry), workshopLatestWorkMoment(now));
  const openStop = entry.status === 'stoppage' && entry.stoppageAt
    ? workshopWorkMinutesBetween(parseIsoTimestamp(entry.stoppageAt), workshopLatestWorkMoment(now))
    : 0;
  const workedHours = Math.max(0, elapsed - Number(entry.stoppageMinutes || 0) - openStop) / 60;
  const remainingHours = Math.max(0, Number(entry.hours || 0) - workedHours);
  return `Worked ${workedHours.toFixed(2)}h · ${remainingHours.toFixed(2)}h estimated remaining`;
}

function workshopDetailHtml(entry = null) {
  if (!entry) return `<div class="workshop-job-detail is-empty"><strong>Job details</strong><span>Select a planned vehicle to view, start, complete or reschedule it. Drag a planned job back to the left panel to return it to Unallocated.</span></div>`;
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return `<div class="workshop-job-detail is-empty"><strong>Vehicle unavailable</strong><span>This plan is retained for administrator review.</span></div>`;
  const start = parseIsoTimestamp(entry.startAt || '');
  const localValue = start ? `${workshopDateKey(start)}T${workshopPad(start.getHours())}:${workshopPad(start.getMinutes())}` : '';
  const actualBay = pmbBayNumber(vehicle, entry.stage);
  const started = entry.stage === 'SUBLET' ? workshopEntryIsLive(entry) : Number(actualBay) === Number(entry.bay);
  const completed = entry.status === 'completed';
  const stopped = entry.status === 'stoppage';
  const overtime = workshopEntryIsOvertime(entry);
  const assigneeConflict = workshopEntryHasAssigneeConflict(entry);
  const parts = workshopPartsSummary(vehicle);
  const stageLines = workshopStageJobLines(vehicle, entry.stage);
  const progress = workshopProgressSummary(entry);
  const stationLabel = entry.stage === 'SUBLET' ? 'Sublet / Provider' : `${pmbStageLabel(entry.stage)} Bay ${entry.bay}`;
  return `<form class="workshop-job-detail" data-workshop-detail-form data-workshop-plan-form-id="${escapeHtml(entry.id)}">
    <div class="workshop-detail-identity">
      <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')} · ${escapeHtml(stationLabel)}${started ? ' · STARTED' : ' · PLANNED'}${overtime ? ' · OVERTIME' : ''}</span>
      <small>${stageLines.length ? `Imported ${escapeHtml(pmbStageLabel(entry.stage))} work: ${escapeHtml(stageLines.map(line => line.text).join(' · '))}` : `No imported ${escapeHtml(pmbStageLabel(entry.stage))} lines · time is manual/default`}</small>
      <small>Parts: ${escapeHtml(parts.text)}</small>
      <small>${escapeHtml(progress)}</small>
      ${assigneeConflict ? `<small class="workshop-assignee-warning">⚠ ${escapeHtml(entry.assignee)} is booked on another vehicle at this time.</small>` : ''}
    </div>
    <label><span>Start</span><input name="startAt" type="datetime-local" step="900" value="${escapeHtml(localValue)}" required ${completed || started ? 'disabled' : ''} /></label>
    <label><span>Planned hours</span><input name="hours" type="number" min="0.25" step="0.25" value="${escapeHtml(entry.hours)}" required ${completed ? 'disabled' : ''} /></label>
    <label><span>${entry.stage === 'SUBLET' ? 'Provider' : 'Technician'}</span><select name="assignee" ${completed ? 'disabled' : ''}>${workshopAssigneeOptions(entry.stage, entry.assignee || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle))}</select></label>
    <div class="workshop-detail-actions">
      ${completed ? '<span class="badge success">Completed</span>' : '<button class="primary" type="submit">Save plan</button>'}
      <button class="small-button" type="button" data-workshop-open-job="${escapeHtml(entry.vehicleKey)}">Vehicle job</button>
      <button class="small-button" type="button" data-workshop-open-vehicle="${escapeHtml(entry.vehicleKey)}">Full vehicle</button>
      ${completed ? '' : `<button class="small-button" type="button" data-workshop-extend-plan="${escapeHtml(entry.id)}" data-workshop-extend-hours="0.25">+15m</button>
      <button class="small-button" type="button" data-workshop-extend-plan="${escapeHtml(entry.id)}" data-workshop-extend-hours="0.5">+30m</button>
      <button class="small-button" type="button" data-workshop-extend-plan="${escapeHtml(entry.id)}" data-workshop-extend-hours="1">+1h</button>
      <button class="small-button" type="button" data-workshop-start-plan="${escapeHtml(entry.id)}" ${started ? 'disabled' : ''}>${started ? 'Started' : 'Start job'}</button>
      <button class="small-button ${stopped ? 'active-lite' : ''}" type="button" ${stopped ? `data-workshop-resume-plan="${escapeHtml(entry.id)}"` : `data-workshop-stop-plan="${escapeHtml(entry.id)}"`}>${stopped ? 'Resume job' : 'Stoppage'}</button>
      <button class="small-button active-lite" type="button" data-workshop-complete-plan="${escapeHtml(entry.id)}">Complete work</button>`}
    </div>
  </form>`;
}

function renderWorkshopPlanner() {
  const root = document.querySelector('#workshop-planner-root');
  if (!root) return;
  const state = workshopState();
  const requestedStage = normalizePmbStage(app.pendingWorkshopStage || '');
  if (WORKSHOP_STAGE_SEQUENCE.includes(requestedStage)) {
    state.stage = requestedStage;
    state.selectedPlanId = '';
    app.pendingWorkshopStage = '';
  }
  let plans = workshopCascadeAndSave(workshopSyncCompletedPlans());
  if (state.selectedPlanId && !plans.some(entry => entry.id === state.selectedPlanId)) state.selectedPlanId = '';
  const selected = plans.find(entry => entry.id === state.selectedPlanId) || null;
  const stage = WORKSHOP_STAGE_SEQUENCE.includes(state.stage) ? state.stage : 'FABRICATION';
  const dateKey = state.date;
  const search = String(state.search || '').trim().toLowerCase();
  const activePlans = plans.filter(entry => entry.stage === stage && entry.status !== 'completed');
  const plannedKeys = new Set(activePlans.map(entry => entry.vehicleKey));
  const queue = workshopStageVehicles(stage).filter(vehicle => !plannedKeys.has(vehicleKey(vehicle)) && (!search || workshopVehicleSearchText(vehicle).includes(search)));
  const completed = plans.filter(entry => {
    if (entry.stage !== stage || entry.status !== 'completed') return false;
    const completedDate = parseIsoTimestamp(entry.completedAt || '');
    return workshopDateKey(completedDate || workshopEntryStart(entry)) === dateKey;
  });
  const todaysPlans = activePlans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
  const assigneeConflicts = todaysPlans.filter(entry => workshopEntryHasAssigneeConflict(entry, plans)).length;
  const stageTabs = WORKSHOP_STAGE_SEQUENCE.map(value => `<button type="button" class="workshop-stage-tab ${value === stage ? 'active' : ''}" data-workshop-stage="${escapeHtml(value)}"><span>${escapeHtml(pmbStageLabel(value))}</span><strong>${workshopStageVehicles(value).length}</strong></button>`).join('');
  root.innerHTML = `<div class="workshop-planner">
    <header class="workshop-planner-header">
      <div><h2>Workshop bay planner</h2><p>Monday–Friday, 8:00am–4:00pm. Long jobs carry into the next workday; overlapping bay bookings are blocked.</p></div>
      <div class="workshop-date-controls">
        <button class="small-button" type="button" data-workshop-date-shift="-1">‹ Previous</button>
        <input type="date" data-workshop-date aria-label="Workshop planner date" value="${escapeHtml(dateKey)}" />
        <button class="small-button" type="button" data-workshop-date-shift="1">Next ›</button>
        <button class="small-button" type="button" data-workshop-today>Today</button>
        <button class="small-button" type="button" data-workshop-weekly-view>Weekly view</button>
        <button class="small-button warning-button" type="button" data-workshop-parts-warning>Draft next-day parts warning</button>
      </div>
    </header>
    <div class="workshop-date-summary"><strong>${escapeHtml(workshopDateLabel(dateKey))}</strong><span>${todaysPlans.length} planned · ${completed.length} completed · ${queue.length} waiting${assigneeConflicts ? ` · ⚠ ${assigneeConflicts} mechanic clash${assigneeConflicts === 1 ? '' : 'es'}` : ''} · Saved automatically${state.lastSavedAt ? ` ${escapeHtml(new Date(state.lastSavedAt).toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' }))}` : ''}</span></div>
    <nav class="workshop-stage-tabs" aria-label="Workshop departments">${stageTabs}</nav>
    ${workshopDetailHtml(selected)}
    <div class="workshop-board-shell">
      <aside class="workshop-side-panel workshop-waiting-panel">
        <div class="workshop-side-heading"><strong>Awaiting schedule</strong><span>${queue.length}</span></div>
        <div class="workshop-unallocated-drop" data-workshop-unallocated-drop><strong>Return to Unallocated</strong><span>Planned or live: choose Just move or Stoppage</span></div>
        <label class="workshop-search"><span>Search and locate vehicle</span><input type="search" data-workshop-search value="${escapeHtml(state.search || '')}" placeholder="Stock, key, JC, customer…" /></label>
        <div class="workshop-side-list">${queue.map(workshopQueueCardHtml).join('') || '<div class="workshop-empty">No unscheduled vehicles in this department.</div>'}</div>
      </aside>
      <section class="workshop-timeline-scroll">
        <div class="workshop-timeline">
          <div class="workshop-time-header"><div class="workshop-bay-label"><strong>${escapeHtml(stage === 'SUBLET' ? 'Sublet row' : `${pmbStageLabel(stage)} bays`)}</strong><span>${escapeHtml(stage === 'SUBLET' ? 'External provider planning' : `${workshopStageBayCount(stage)} physical bay${workshopStageBayCount(stage) === 1 ? '' : 's'}`)}</span></div><div class="workshop-time-axis">${workshopTimeAxisHtml()}</div></div>
          <div class="workshop-now-line" data-workshop-now-line hidden><span>Now</span></div>
          ${workshopBayRowsHtml(stage, dateKey, plans)}
        </div>
      </section>
      <aside class="workshop-side-panel workshop-completed-panel">
        <div class="workshop-side-heading"><strong>Completed</strong><span>${completed.length}</span></div>
        <div class="workshop-side-list">${completed.map(workshopCompletedCardHtml).join('') || '<div class="workshop-empty">Nothing completed on this board date.</div>'}</div>
      </aside>
    </div>
    <footer class="workshop-board-note"><strong>How to use:</strong> drag a waiting vehicle onto a bay to add it at the earliest open sequence time, or use Schedule for a specific date and time. If the day is full, automatic sequencing continues on the next workday. Double-click any vehicle to open its job. Existing bookings are never moved and overlaps remain blocked.</footer>
  </div>`;
  bindWorkshopPlanner(root);
  updateWorkshopNowLine(root);
  setupWorkshopPlannerClock();
  workshopScrollToHighlightedVehicle(root);
}

function bindWorkshopPlanner(root) {
  root.querySelectorAll('[data-workshop-stage]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    state.stage = button.dataset.workshopStage;
    state.selectedPlanId = '';
    workshopSaveView(state);
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-date-shift]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    const current = workshopDateFromKey(state.date) || new Date();
    state.date = workshopDateKey(workshopShiftWorkday(current, Number(button.dataset.workshopDateShift)));
    state.selectedPlanId = '';
    workshopSaveView(state);
    renderWorkshopPlanner();
  }));
  root.querySelector('[data-workshop-today]')?.addEventListener('click', () => {
    const state = workshopState();
    state.date = workshopDateKey(workshopCoerceWorkDate(new Date(), 1));
    state.selectedPlanId = '';
    workshopSaveView(state);
    renderWorkshopPlanner();
  });
  root.querySelector('[data-workshop-date]')?.addEventListener('change', event => {
    const selected = workshopDateFromKey(event.target.value);
    if (!selected) return;
    const coerced = workshopCoerceWorkDate(selected, 1);
    if (workshopDateKey(coerced) !== event.target.value) window.alert('Workshop boards run Monday to Friday. The date has been moved to the next workday.');
    const state = workshopState();
    state.date = workshopDateKey(coerced);
    state.selectedPlanId = '';
    workshopSaveView(state);
    renderWorkshopPlanner();
  });
  const searchInput = root.querySelector('[data-workshop-search]');
  searchInput?.addEventListener('input', event => {
    workshopState().search = event.target.value;
    window.clearTimeout(app.workshopPlannerSearchTimer);
    app.workshopPlannerSearchTimer = window.setTimeout(() => workshopRevealSearchMatch(event.target.value), 350);
  });
  searchInput?.addEventListener('keydown', event => {
    if (event.key !== 'Enter') return;
    event.preventDefault();
    window.clearTimeout(app.workshopPlannerSearchTimer);
    workshopRevealSearchMatch(event.currentTarget.value);
  });
  root.querySelector('[data-workshop-weekly-view]')?.addEventListener('click', () => {
    const selected = workshopLoadPlans().find(entry => entry.id === workshopState().selectedPlanId && entry.stage === workshopState().stage);
    openWorkshopWeeklyView(workshopState().stage, Number(selected?.bay) || 1, workshopState().date);
  });
  root.querySelector('[data-workshop-parts-warning]')?.addEventListener('click', draftWorkshopNextDayFittingWarningEmail);
  root.querySelectorAll('[data-workshop-bay-mechanic-stage]').forEach(select => select.addEventListener('change', () => saveWorkshopBayMechanic(select.dataset.workshopBayMechanicStage, Number(select.dataset.workshopBayMechanicNumber), select.value)));
  root.querySelectorAll('[data-workshop-weekly-stage]').forEach(button => button.addEventListener('click', () => openWorkshopWeeklyView(button.dataset.workshopWeeklyStage, Number(button.dataset.workshopWeeklyBay), workshopState().date)));
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'copy';
    event.dataTransfer.setData('application/x-workshop-vehicle-key', card.dataset.workshopVehicleKey);
    event.dataTransfer.setData('text/plain', card.dataset.workshopVehicleKey);
  }));
  root.querySelectorAll('[data-workshop-schedule-vehicle]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openWorkshopScheduleModal(button.dataset.workshopScheduleVehicle, workshopState().stage, workshopState().date);
  }));
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', chip.dataset.workshopPlanId);
  }));
  root.querySelectorAll('[data-workshop-job-vehicle]').forEach(card => card.addEventListener('dblclick', event => {
    event.preventDefault();
    const plan = workshopLoadPlans().find(entry => entry.id === card.dataset.workshopPlanId);
    openWorkshopVehicleJob(card.dataset.workshopJobVehicle, plan?.stage || workshopState().stage);
  }));
  root.querySelectorAll('[data-workshop-drop-bay]').forEach(lane => bindWorkshopLane(lane));
  bindWorkshopUnallocatedDrop(root.querySelector('[data-workshop-unallocated-drop]'));
  root.querySelectorAll('[data-workshop-select-plan]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    workshopState().selectedPlanId = button.dataset.workshopSelectPlan;
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-open-plan]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    state.date = button.dataset.workshopOpenDate;
    state.selectedPlanId = button.dataset.workshopOpenPlan;
    workshopSaveView(state);
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-resize-plan]').forEach(handle => handle.addEventListener('pointerdown', event => startWorkshopResize(handle, event)));
  root.querySelectorAll('[data-workshop-extend-plan]').forEach(button => button.addEventListener('click', () => extendWorkshopPlan(button.dataset.workshopExtendPlan, Number(button.dataset.workshopExtendHours))));
  root.querySelector('[data-workshop-detail-form]')?.addEventListener('submit', saveWorkshopDetailForm);
  root.querySelector('[data-workshop-open-job]')?.addEventListener('click', event => openWorkshopVehicleJob(event.currentTarget.dataset.workshopOpenJob, workshopLoadPlans().find(entry => entry.id === workshopState().selectedPlanId)?.stage || workshopState().stage));
  root.querySelector('[data-workshop-open-vehicle]')?.addEventListener('click', event => openVehicleModal(event.currentTarget.dataset.workshopOpenVehicle));
  root.querySelector('[data-workshop-start-plan]')?.addEventListener('click', event => startWorkshopPlan(event.currentTarget.dataset.workshopStartPlan));
  root.querySelector('[data-workshop-stop-plan]')?.addEventListener('click', event => stopWorkshopPlan(event.currentTarget.dataset.workshopStopPlan));
  root.querySelector('[data-workshop-resume-plan]')?.addEventListener('click', event => resumeWorkshopPlan(event.currentTarget.dataset.workshopResumePlan));
  root.querySelector('[data-workshop-complete-plan]')?.addEventListener('click', event => completeWorkshopPlan(event.currentTarget.dataset.workshopCompletePlan));
}

function bindWorkshopLane(lane) {
  lane.addEventListener('dragover', event => {
    event.preventDefault();
    lane.classList.add('drag-over');
  });
  lane.addEventListener('dragleave', event => {
    if (!lane.contains(event.relatedTarget)) lane.classList.remove('drag-over');
  });
  lane.addEventListener('drop', event => {
    event.preventDefault();
    lane.classList.remove('drag-over');
    const rect = lane.getBoundingClientRect();
    const requestedStartMinutes = workshopClampStartMinutes(((event.clientX - rect.left) / Math.max(1, rect.width)) * WORKSHOP_DAY_MINUTES);
    const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
    const vehicleKeyValue = event.dataTransfer.getData('application/x-workshop-vehicle-key') || event.dataTransfer.getData('text/plain');
    const stage = lane.dataset.workshopDropStage;
    const bay = Number(lane.dataset.workshopDropBay);
    let dateKey = workshopState().date;
    let startMinutes = requestedStartMinutes;
    if (!planId && vehicleKeyValue) {
      const vehicle = workshopVehicle(vehicleKeyValue);
      const hours = vehicle ? (workshopCalculatedStageHours(vehicle, stage) || pmbBayHours(vehicle) || WORKSHOP_DEFAULT_HOURS) : WORKSHOP_DEFAULT_HOURS;
      const availableSlot = workshopFirstAvailableStartSlot(stage, bay, dateKey, hours, workshopLoadPlans());
      if (!availableSlot) {
        window.alert('No open sequence slot was found in this bay during the next 20 workdays. Choose another bay or use Schedule to select a later date.');
        return;
      }
      dateKey = availableSlot.dateKey;
      startMinutes = availableSlot.startMinutes;
    }
    scheduleWorkshopVehicle({ planId, vehicleKeyValue, stage, bay, dateKey, startMinutes });
  });
}

function saveWorkshopBayMechanic(stage = '', bay = 0, value = '') {
  const setup = workshopLoadBaySetup();
  const key = workshopBaySetupKey(stage, bay);
  const assignee = cleanNavisionText(value || '');
  if (assignee) setup[key] = assignee;
  else delete setup[key];
  if (normalizePmbStage(stage) === 'SUBLET' && assignee) saveSubletProviders([...loadSubletProviders(), assignee]);
  if (normalizePmbStage(stage) !== 'SUBLET' && assignee) saveMechanics([...loadMechanics(), assignee]);
  workshopSaveBaySetup(setup);
  const currentPlans = workshopLoadPlans();
  let skipped = 0;
  const plans = currentPlans.map(entry => {
    if (entry.stage !== normalizePmbStage(stage) || Number(entry.bay) !== Number(bay) || entry.status !== 'planned' || entry.assignee) return entry;
    const candidate = { ...entry, assignee, updatedAt: nowIsoString() };
    if (workshopAssigneeConflict(candidate, currentPlans.filter(row => row.id !== candidate.id))) {
      skipped += 1;
      return entry;
    }
    return candidate;
  });
  workshopSavePlans(plans);
  if (skipped) window.alert(`${assignee} was saved as the bay default, but ${skipped} overlapping booking${skipped === 1 ? ' was' : 's were'} left unassigned because that mechanic is already booked elsewhere.`);
  renderWorkshopPlanner();
}

function bindWorkshopUnallocatedDrop(target) {
  if (!target) return;
  target.addEventListener('dragover', event => {
    if (!Array.from(event.dataTransfer?.types || []).includes('application/x-workshop-plan-id')) return;
    event.preventDefault();
    target.classList.add('drag-over');
  });
  target.addEventListener('dragleave', event => {
    if (!target.contains(event.relatedTarget)) target.classList.remove('drag-over');
  });
  target.addEventListener('drop', event => {
    event.preventDefault();
    target.classList.remove('drag-over');
    returnWorkshopPlanToUnallocated(event.dataTransfer.getData('application/x-workshop-plan-id'));
  });
}

function workshopReturnChoiceModal(entry = {}, vehicle = {}) {
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay workshop-return-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML = `<section class="modal-card workshop-return-card">
      <button class="modal-close" type="button" data-workshop-return-cancel aria-label="Cancel">×</button>
      <header><h2>Return vehicle to PMB Unallocated</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} is leaving ${escapeHtml(pmbStageLabel(entry.stage))} Bay ${escapeHtml(entry.bay)}. The work remains open.</p></header>
      <div class="workshop-return-options">
        <label><input type="radio" name="workshopReturnChoice" value="move" checked><span><strong>Just move</strong><small>Return to Unallocated without marking the job complete or creating a stoppage.</small></span></label>
        <label><input type="radio" name="workshopReturnChoice" value="stoppage"><span><strong>Stoppage</strong><small>Return to Unallocated, keep the job open and flag the vehicle as stopped.</small></span></label>
      </div>
      <label class="workshop-return-reason" data-workshop-return-reason-wrap hidden><span>Stoppage reason</span><input type="text" data-workshop-return-reason value="${escapeHtml(entry.stoppageReason || `${pmbStageLabel(entry.stage)} stoppage`)}"></label>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-return-cancel>Cancel</button><button class="primary" type="button" data-workshop-return-apply>Return to Unallocated</button></div>
    </section>`;
    const finish = value => {
      overlay.remove();
      if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
      resolve(value);
    };
    const sync = () => {
      const choice = overlay.querySelector('[name="workshopReturnChoice"]:checked')?.value || 'move';
      overlay.querySelector('[data-workshop-return-reason-wrap]').hidden = choice !== 'stoppage';
    };
    overlay.querySelectorAll('[name="workshopReturnChoice"]').forEach(input => input.addEventListener('change', sync));
    overlay.querySelectorAll('[data-workshop-return-cancel]').forEach(button => button.addEventListener('click', () => finish(null)));
    overlay.querySelector('[data-workshop-return-apply]').addEventListener('click', () => {
      const choice = overlay.querySelector('[name="workshopReturnChoice"]:checked')?.value || 'move';
      const reason = cleanNavisionText(overlay.querySelector('[data-workshop-return-reason]')?.value || '');
      if (choice === 'stoppage' && !reason) {
        window.alert('Enter the stoppage reason.');
        return;
      }
      finish({ choice, reason });
    });
    overlay.addEventListener('click', event => { if (event.target === overlay) finish(null); });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    sync();
  });
}

async function returnWorkshopPlanToUnallocated(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  if (!entry) return;
  if (entry.status === 'completed') {
    window.alert('Completed work stays in planner history. It cannot be returned to Unallocated.');
    return;
  }
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return;
  if (!workshopRequireOperatorProfile()) return;
  if (entry.status === 'planned') {
    if (!window.confirm(`Return ${displayStockNumber(vehicle) || 'this vehicle'} to the unscheduled ${pmbStageLabel(entry.stage)} queue?\n\nThe vehicle stays in PMB and is not deleted.`)) return;
    const latestRows = workshopLoadPlans();
    const latestEntry = latestRows.find(row => row.id === entry.id);
    if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
      window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
      renderWorkshopPlanner();
      return;
    }
    workshopPersistPlanAction(
      'Workshop plan returned to queue',
      latestRows.filter(row => row.id !== entry.id),
      vehicle,
      'Workshop plan returned to queue',
      { stage: pmbStageLabel(entry.stage), bay: entry.stage === 'SUBLET' ? 'Provider row' : `Bay ${entry.bay}` },
    );
    workshopState().selectedPlanId = '';
    renderWorkshopPlanner();
    return;
  }
  const result = await workshopReturnChoiceModal(entry, vehicle);
  if (!result) return;
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const stoppage = result.choice === 'stoppage';
  const vehicleUpdates = {
    pdcLocation: 'PMB',
    manualLocation: 'PMB',
    pdcLocationLocked: true,
    pmbStage: '',
    pmbStageUpdatedAt: now,
    pmbStageEnteredAt: now,
    pmbBayStage: '',
    pmbBayNumber: '',
    pmbBayEstimatedHours: '',
    pmbBayEnteredAt: '',
    pmbBayScheduledStartAt: '',
    pmbBayMechanic: '',
    pmbSubletProvider: '',
    ...(stoppage
      ? workshopOwnedBlockUpdates(entry, result.reason, now, operator)
      : workshopOwnedBlockClearUpdates(entry, vehicle, now, operator)),
  };
  const persisted = workshopPersistVehiclePlanAction(
    'Return workshop job to Unallocated',
    rows.filter(row => row.id !== entry.id),
    vehicle,
    vehicleUpdates,
    stoppage ? 'Workshop job returned to Unallocated with stoppage' : 'Workshop job returned to Unallocated',
    { stage: pmbStageLabel(entry.stage), bay: entry.bay, reason: stoppage ? result.reason : 'Just move', by: operator },
  );
  if (!persisted) return;
  workshopState().selectedPlanId = '';
  workshopState().highlightVehicleKey = '';
  if (stoppage) {
    offerSalespersonChangeEmail(vehicle, {
      title: `${pmbStageLabel(entry.stage)} stoppage`,
      subject: 'PDC workshop stoppage',
      details: [`The vehicle was returned to PMB Unallocated with this stoppage: ${result.reason}.`, `The ${pmbStageLabel(entry.stage)} job remains open.`],
    });
  }
  renderWorkshopPlanner();
}

function workshopFirstAvailableStartMinutes(stage = '', bay = 1, dateKey = '', hours = WORKSHOP_DEFAULT_HOURS, rows = workshopLoadPlans(), notBeforeMinutes = 0) {
  const normalizedStage = normalizePmbStage(stage);
  const duration = workshopClampDurationHours(hours);
  const firstStart = workshopClampStartMinutes(notBeforeMinutes);
  for (let startMinutes = firstStart; startMinutes < WORKSHOP_DAY_MINUTES; startMinutes += 15) {
    const candidate = {
      id: '__availability_check__',
      vehicleKey: '__availability_check__',
      stage: normalizedStage,
      bay: Number(bay),
      startAt: workshopDateAtOffset(dateKey, startMinutes).toISOString(),
      hours: duration,
      status: 'planned',
    };
    if (!workshopHasConflict(candidate, rows)) return startMinutes;
  }
  return null;
}

function workshopFirstAvailableStartSlot(stage = '', bay = 1, dateKey = '', hours = WORKSHOP_DEFAULT_HOURS, rows = workshopLoadPlans(), notBeforeMinutes = 0, maxWorkdays = 20) {
  const requestedDate = workshopDateFromKey(dateKey) || new Date();
  let workDate = workshopCoerceWorkDate(requestedDate, 1);
  for (let dayIndex = 0; dayIndex < Math.max(1, Number(maxWorkdays) || 20); dayIndex += 1) {
    const candidateDateKey = workshopDateKey(workDate);
    const firstMinutes = dayIndex === 0 ? notBeforeMinutes : 0;
    const startMinutes = workshopFirstAvailableStartMinutes(stage, bay, candidateDateKey, hours, rows, firstMinutes);
    if (startMinutes !== null) return { dateKey: candidateDateKey, startMinutes };
    workDate = workshopNextWorkdayDate(workDate);
  }
  return null;
}

function workshopScheduleTimeOptions(selectedMinutes = 0) {
  return Array.from({ length: WORKSHOP_DAY_MINUTES / 15 }, (_, index) => index * 15)
    .map(minutes => `<option value="${minutes}"${minutes === Number(selectedMinutes) ? ' selected' : ''}>${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</option>`)
    .join('');
}

function openWorkshopScheduleModal(vehicleKeyValue = '', stage = '', dateKey = '') {
  const normalizedStage = normalizePmbStage(stage);
  const vehicle = workshopVehicle(vehicleKeyValue);
  if (!vehicle || !WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return;
  const hours = workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || WORKSHOP_DEFAULT_HOURS;
  const bay = 1;
  const selectedDate = workshopDateKey(workshopCoerceWorkDate(workshopDateFromKey(dateKey) || new Date(), 1));
  const firstSlot = workshopFirstAvailableStartSlot(normalizedStage, bay, selectedDate, hours);
  const scheduledDate = firstSlot?.dateKey || selectedDate;
  const startMinutes = firstSlot?.startMinutes ?? 0;
  const bayOptions = Array.from({ length: workshopStageBayCount(normalizedStage) }, (_, index) => `<option value="${index + 1}">${normalizedStage === 'SUBLET' ? 'Provider row' : `Bay ${workshopPad(index + 1)}`}</option>`).join('');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-schedule-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-schedule-card">
    <button class="modal-close" type="button" data-workshop-schedule-cancel aria-label="Cancel">×</button>
    <header><h2>Schedule ${escapeHtml(pmbStageLabel(normalizedStage))} work</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</p></header>
    <form data-workshop-schedule-form>
      <div class="workshop-schedule-grid">
        <label><span>${normalizedStage === 'SUBLET' ? 'Row' : 'Bay'}</span><select name="bay">${bayOptions}</select></label>
        <label><span>Date</span><input name="date" type="date" value="${escapeHtml(scheduledDate)}" required></label>
        <label><span>Start time</span><select name="startMinutes">${workshopScheduleTimeOptions(startMinutes)}</select></label>
        <label><span>Planned hours</span><input name="hours" type="number" min="0.25" step="0.25" value="${escapeHtml(workshopClampDurationHours(hours))}" required></label>
        <label><span>${normalizedStage === 'SUBLET' ? 'Provider' : 'Technician'}</span><select name="assignee">${workshopAssigneeOptions(normalizedStage, workshopBayMechanic(normalizedStage, bay) || pmbBayMechanic(vehicle))}</select></label>
      </div>
      <p class="workshop-schedule-note">The first open sequence time is selected automatically and may advance to the next workday. Back-to-back bookings are allowed; overlapping times are blocked.</p>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-schedule-cancel>Cancel</button><button class="primary" type="submit">Add to planner</button></div>
    </form>
  </section>`;
  const finish = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  const suggestAvailableTime = () => {
    const form = overlay.querySelector('[data-workshop-schedule-form]');
    const selected = workshopDateFromKey(form.elements.date.value);
    if (!selected) return;
    const safeDate = workshopDateKey(workshopCoerceWorkDate(selected, 1));
    form.elements.date.value = safeDate;
    const suggested = workshopFirstAvailableStartSlot(normalizedStage, Number(form.elements.bay.value), safeDate, Number(form.elements.hours.value) || hours);
    if (suggested) {
      form.elements.date.value = suggested.dateKey;
      form.elements.startMinutes.value = String(suggested.startMinutes);
    }
  };
  overlay.querySelectorAll('[data-workshop-schedule-cancel]').forEach(button => button.addEventListener('click', finish));
  overlay.querySelector('[name="bay"]')?.addEventListener('change', suggestAvailableTime);
  overlay.querySelector('[name="date"]')?.addEventListener('change', suggestAvailableTime);
  overlay.querySelector('[name="hours"]')?.addEventListener('change', suggestAvailableTime);
  overlay.querySelector('[data-workshop-schedule-form]').addEventListener('submit', event => {
    event.preventDefault();
    const form = event.currentTarget;
    const selected = workshopDateFromKey(form.elements.date.value);
    if (!selected || !workshopIsWorkday(selected)) {
      window.alert('Choose a Monday-to-Friday workshop date.');
      return;
    }
    const scheduled = scheduleWorkshopVehicle({
      vehicleKeyValue,
      stage: normalizedStage,
      bay: Number(form.elements.bay.value),
      dateKey: workshopDateKey(selected),
      startMinutes: Number(form.elements.startMinutes.value),
      hoursValue: Number(form.elements.hours.value),
      assigneeValue: form.elements.assignee.value,
    });
    if (scheduled) finish();
  });
  overlay.addEventListener('click', event => { if (event.target === overlay) finish(); });
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
  overlay.querySelector('[name="bay"]')?.focus();
}

function extendWorkshopPlan(planId = '', additionalHours = 0) {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const delta = Number(additionalHours);
  if (!entry || entry.status === 'completed' || !Number.isFinite(delta) || delta <= 0) return false;
  const candidate = { ...entry, hours: workshopClampDurationHours(Number(entry.hours || 0) + delta), updatedAt: nowIsoString() };
  const latestRows = workshopLoadPlans();
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
    renderWorkshopPlanner();
    return false;
  }
  const otherRows = latestRows.filter(row => row.id !== candidate.id);
  if (!workshopRequireNoBayConflict(candidate, otherRows) || !workshopRequireAvailableAssignee(candidate, otherRows)) return false;
  const vehicle = workshopVehicle(entry.vehicleKey);
  const hoursMap = vehicle ? workshopEstimatedHoursMap(vehicle) : {};
  if (vehicle) hoursMap[entry.stage] = candidate.hours;
  const persisted = workshopPersistVehiclePlanAction(
    'Workshop plan time extended',
    workshopCascadePlans(latestRows.map(row => row.id === entry.id ? candidate : row)).rows,
    vehicle,
    vehicle ? { workshopEstimatedHoursByStage: hoursMap } : {},
    'Workshop plan time extended',
    { stage: pmbStageLabel(entry.stage), addedHours: delta, hours: candidate.hours },
  );
  if (!persisted) return false;
  workshopState().selectedPlanId = entry.id;
  renderWorkshopPlanner();
  return true;
}

function workshopConfirmOtherDepartmentPlans(candidate = {}, rows = []) {
  if (!candidate.vehicleKey || candidate.status !== 'planned') return true;
  const otherPlans = rows.filter(row => row.id !== candidate.id
    && row.vehicleKey === candidate.vehicleKey
    && row.stage !== candidate.stage
    && row.status !== 'completed');
  if (!otherPlans.length) return true;
  const details = otherPlans.slice(0, 8).map(row => {
    const when = parseIsoTimestamp(row.startAt);
    const whenLabel = when ? when.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'time not set';
    const place = row.stage === 'SUBLET' ? 'Provider row' : `Bay ${workshopPad(row.bay)}`;
    return `• ${pmbStageLabel(row.stage)} · ${place} · ${whenLabel}`;
  }).join('\n');
  return window.confirm(`This vehicle is also planned by another department:\n\n${details}\n\nContinue with the ${pmbStageLabel(candidate.stage)} booking?`);
}

function scheduleWorkshopVehicle({ planId = '', vehicleKeyValue = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, hoursValue = null, assigneeValue = null } = {}) {
  const rows = workshopLoadPlans();
  const existing = rows.find(entry => entry.id === planId) || rows.find(entry => entry.id === workshopPlanId(vehicleKeyValue, stage));
  const vehicle = workshopVehicle(existing?.vehicleKey || vehicleKeyValue);
  if (!vehicle) return false;
  if (existing && ['started', 'stoppage', 'completed'].includes(existing.status)) {
    window.alert('Started, stopped and completed jobs stay fixed on the planner. Resolve the live job before rescheduling it.');
    return false;
  }
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage) || Number(bay) < 1 || Number(bay) > workshopStageBayCount(normalizedStage)) {
    window.alert('Choose a valid workshop bay.');
    return false;
  }
  const start = workshopDateAtOffset(dateKey, startMinutes);
  // Parts completion remains an RFT gate, not an entry gate for Tint, Tyre or Sublet. Planning itself never moves a vehicle into a physical bay.
  const requestedHours = Number(hoursValue);
  const defaultHours = Number.isFinite(requestedHours) && requestedHours > 0
    ? requestedHours
    : existing?.hours || workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || WORKSHOP_DEFAULT_HOURS;
  const hours = workshopClampDurationHours(defaultHours);
  const now = nowIsoString();
  const candidate = {
    ...(existing || {}),
    id: existing?.id || workshopPlanId(vehicleKey(vehicle), normalizedStage),
    vehicleKey: vehicleKey(vehicle),
    stage: normalizedStage,
    bay: Number(bay),
    startAt: start.toISOString(),
    hours,
    assignee: assigneeValue === null
      ? existing?.assignee || workshopBayMechanic(normalizedStage, bay) || pmbBayMechanic(vehicle) || ''
      : cleanNavisionText(assigneeValue || ''),
    status: 'planned',
    createdAt: existing?.createdAt || now,
    updatedAt: now,
  };
  const latestRows = workshopLoadPlans();
  const latestExisting = latestRows.find(row => row.id === candidate.id);
  if ((existing && (!latestExisting || latestExisting.updatedAt !== existing.updatedAt)) || (!existing && latestExisting)) {
    window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
    renderWorkshopPlanner();
    return false;
  }
  const conflictRows = latestRows.filter(row => row.id !== candidate.id);
  if (!workshopRequireNoBayConflict(candidate, conflictRows)) return false;
  if (!workshopRequireAvailableAssignee(candidate, conflictRows)) return false;
  if (!workshopConfirmOtherDepartmentPlans(candidate, latestRows)) return false;
  const nextRows = latestExisting ? latestRows.map(entry => entry.id === latestExisting.id ? candidate : entry) : [...latestRows, candidate];
  const persisted = workshopPersistPlanAction(
    existing ? 'Workshop plan rescheduled' : 'Workshop plan created',
    workshopCascadePlans(nextRows).rows,
    vehicle,
    existing ? 'Workshop plan rescheduled' : 'Workshop plan created',
    { stage: pmbStageLabel(normalizedStage), bay: normalizedStage === 'SUBLET' ? 'Provider row' : `Bay ${bay}`, startAt: candidate.startAt, hours: candidate.hours, assignee: candidate.assignee || 'Unassigned' },
  );
  if (!persisted) return false;
  workshopState().selectedPlanId = candidate.id;
  renderWorkshopPlanner();
  return true;
}

function saveWorkshopDetailForm(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === form.dataset.workshopPlanFormId);
  if (!entry) return;
  const data = new FormData(form);
  const start = new Date(String(data.get('startAt') || entry.startAt || ''));
  if (Number.isNaN(start.getTime()) || !workshopIsWorkday(start)) {
    window.alert('Choose a Monday-to-Friday workshop date.');
    return;
  }
  const offset = workshopMinuteOffset(start);
  if (offset < 0 || offset >= WORKSHOP_DAY_MINUTES) {
    window.alert('Workshop start times must be between 8:00am and 3:45pm.');
    return;
  }
  const startMinutes = workshopClampStartMinutes(offset);
  start.setHours(WORKSHOP_START_HOUR, 0, 0, 0);
  start.setMinutes(startMinutes);
  const requestedHours = Number(data.get('hours') || entry.hours || WORKSHOP_DEFAULT_HOURS);
  if (!Number.isFinite(requestedHours) || requestedHours <= 0) {
    window.alert('Enter planned hours greater than zero. There is no maximum workshop duration.');
    return;
  }
  const candidate = {
    ...entry,
    startAt: ['started', 'stoppage'].includes(entry.status) ? entry.startAt : start.toISOString(),
    hours: workshopClampDurationHours(requestedHours),
    assignee: cleanNavisionText(data.get('assignee') || ''),
    updatedAt: nowIsoString(),
  };
  const latestRows = workshopLoadPlans();
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
    renderWorkshopPlanner();
    return;
  }
  const otherRows = latestRows.filter(row => row.id !== candidate.id);
  if (!workshopRequireNoBayConflict(candidate, otherRows)) return;
  if (!workshopRequireAvailableAssignee(candidate, otherRows)) return;
  if (!workshopConfirmOtherDepartmentPlans(candidate, latestRows)) return;
  const updatedRows = workshopCascadePlans(latestRows.map(row => row.id === entry.id ? candidate : row)).rows;
  const vehicle = workshopVehicle(entry.vehicleKey);
  const hoursMap = vehicle ? workshopEstimatedHoursMap(vehicle) : {};
  if (vehicle) hoursMap[entry.stage] = candidate.hours;
  const persisted = workshopPersistVehiclePlanAction(
    'Workshop plan details updated',
    updatedRows,
    vehicle,
    vehicle ? { workshopEstimatedHoursByStage: hoursMap } : {},
    'Workshop plan details updated',
    { stage: pmbStageLabel(entry.stage), startAt: candidate.startAt, hours: candidate.hours, assignee: candidate.assignee || 'Unassigned' },
  );
  if (!persisted) return;
  const state = workshopState();
  state.date = workshopEntryDate(candidate);
  workshopSaveView(state);
  renderWorkshopPlanner();
}

async function startWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (!workshopRequireOperatorProfile()) return;
  const currentStart = workshopNormalizeStartDate(new Date());
  const next = { ...entry, startAt: currentStart.toISOString(), status: 'started', startedAt: nowIsoString(), updatedAt: nowIsoString() };
  const otherRows = rows.filter(row => row.id !== next.id);
  if (!workshopRequireNoBayConflict(next, otherRows)) return;
  if (!workshopRequireAvailableAssignee(next, otherRows)) return;
  const nextRows = workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows;
  const auditDetails = { stage: pmbStageLabel(entry.stage), bay: entry.stage === 'SUBLET' ? 'Sublet' : `Bay ${entry.bay}`, hours: entry.hours, assignee: entry.assignee || 'Unassigned' };
  let persisted = false;
  if (entry.stage === 'SUBLET') {
    persisted = workshopPersistVehiclePlanAction(
      'Start Sublet workshop job',
      nextRows,
      vehicle,
      {
        pdcLocation: 'PMB',
        manualLocation: 'PMB',
        pdcLocationLocked: true,
        pmbStage: 'SUBLET',
        pmbStageUpdatedAt: nowIsoString(),
        pmbBayScheduledStartAt: next.startAt,
        pmbBayEstimatedHours: String(next.hours),
        pmbSubletProvider: cleanNavisionText(next.assignee || ''),
      },
      'Workshop job started',
      auditDetails,
    );
  } else {
    persisted = await assignPmbVehicleToBay(entry.vehicleKey, entry.stage, entry.bay, next.startAt, {
      keys: [WORKSHOP_PLAN_STORAGE_KEY],
      afterAssign: assignedVehicle => {
        if (!saveVehicleEdits(entry.vehicleKey, {
          pmbBayScheduledStartAt: next.startAt,
          pmbBayEstimatedHours: String(next.hours),
          pmbBayMechanic: cleanNavisionText(next.assignee || ''),
        }, { render: false })) throw new Error('The workshop start details could not be saved.');
        workshopSavePlans(nextRows);
        recordVehicleAudit(assignedVehicle, 'Workshop job started', auditDetails);
      },
    });
  }
  if (!persisted) return;
  workshopState().date = workshopDateKey(currentStart);
  workshopSaveView(workshopState());
  offerSalespersonChangeEmail(vehicle, {
    title: `${pmbStageLabel(entry.stage)} job started`,
    subject: 'PDC workshop job started',
    details: [
      `${pmbStageLabel(entry.stage)} work started at ${currentStart.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' })}.`,
      entry.stage === 'SUBLET' ? `Provider: ${entry.assignee || 'Unassigned'}.` : `Bay ${entry.bay}${entry.assignee ? ` · Mechanic: ${entry.assignee}` : ''}.`,
      `Estimated workshop time: ${entry.hours} hours.`,
    ],
  });
  renderWorkshopPlanner();
}

function completeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (!workshopRequireOperatorProfile()) return;
  if (!['started', 'stoppage'].includes(entry.status)) {
    window.alert('Use “Start job” first so the workshop start time and salesperson update are recorded.');
    return;
  }
  if (entry.stage !== 'SUBLET' && Number(pmbBayNumber(vehicle, entry.stage)) !== Number(entry.bay)) {
    window.alert('Use “Start in bay” first. This keeps the live physical-bay record accurate before work is completed.');
    return;
  }
  const completedMoment = workshopLatestWorkMoment(new Date());
  const elapsedMinutes = workshopWorkMinutesBetween(workshopEntryStart(entry), completedMoment);
  const openStoppageMinutes = entry.status === 'stoppage' && entry.stoppageAt
    ? workshopWorkMinutesBetween(parseIsoTimestamp(entry.stoppageAt), completedMoment)
    : 0;
  const actualMinutes = Math.max(0, elapsedMinutes - Number(entry.stoppageMinutes || 0) - openStoppageMinutes);
  const actualHours = actualMinutes / 60;
  if (entry.stage === 'SUBLET') {
    const completedAt = nowIsoString();
    const operator = getCurrentOperatorName();
    const next = { ...entry, status: 'completed', completedAt, actualHours: Number(actualHours.toFixed(2)), updatedAt: completedAt };
    const persisted = workshopPersistVehiclePlanAction(
      'Sublet workshop plan completed',
      workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows,
      vehicle,
      {
        pmbStage: '',
        pmbStageUpdatedAt: completedAt,
        pmbStageEnteredAt: completedAt,
        pmbBayStage: '',
        pmbBayNumber: '',
        pmbBayEstimatedHours: '',
        pmbBayEnteredAt: '',
        pmbBayScheduledStartAt: '',
        pmbBayMechanic: '',
        pmbSubletActualReturnDate: workshopDateKey(new Date()),
        pmbSubletUpdatedAt: completedAt,
        pmbSubletUpdatedBy: operator,
        ...workshopOwnedBlockClearUpdates(entry, vehicle, completedAt, operator),
      },
      'Sublet work completed',
      { provider: entry.assignee || 'Unassigned', estimatedHours: entry.hours, actualHours: next.actualHours, by: operator, returnedTo: 'PMB unallocated' },
    );
    if (!persisted) return;
    offerSalespersonChangeEmail(vehicle, {
      title: 'Sublet work completed',
      subject: 'PDC sublet work completed',
      details: [`Sublet work was completed by ${entry.assignee || 'the external provider'}.`, 'The vehicle returned to PMB Unallocated.'],
    });
    renderWorkshopPlanner();
    return;
  }
  const completed = completePmbBayWork(entry.vehicleKey, entry.stage, {
    keys: [WORKSHOP_PLAN_STORAGE_KEY],
    afterComplete: (refreshed, def) => {
      const completedAt = refreshed[def.completeAtKey] || nowIsoString();
      const operator = getCurrentOperatorName();
      const clearUpdates = workshopOwnedBlockClearUpdates(entry, refreshed, completedAt, operator);
      if (Object.keys(clearUpdates).length && !saveVehicleEdits(entry.vehicleKey, clearUpdates, { render: false })) {
        throw new Error('The workshop stoppage could not be cleared safely.');
      }
      const next = { ...entry, status: 'completed', completedAt, actualHours: Number(actualHours.toFixed(2)), updatedAt: nowIsoString() };
      recordVehicleAudit(refreshed, 'Workshop actual time recorded', { stage: pmbStageLabel(entry.stage), estimatedHours: entry.hours, actualHours: next.actualHours, by: operator });
      workshopSavePlans(workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows);
    },
  });
  if (!completed) return;
  renderWorkshopPlanner();
}

function workshopStoppageReasonModal(entry = {}, vehicle = {}) {
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay workshop-return-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML = `<section class="modal-card workshop-return-card">
      <button class="modal-close" type="button" data-workshop-stop-cancel aria-label="Cancel">×</button>
      <header><h2>Record workshop stoppage</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} · ${escapeHtml(pmbStageLabel(entry.stage))}${entry.stage === 'SUBLET' ? '' : ` Bay ${escapeHtml(entry.bay)}`}</p></header>
      <label class="workshop-return-reason"><span>Stoppage reason</span><input type="text" data-workshop-stop-reason value="${escapeHtml(entry.stoppageReason || '')}" autocomplete="off"></label>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-stop-cancel>Cancel</button><button class="primary" type="button" data-workshop-stop-apply>Record stoppage</button></div>
    </section>`;
    const finish = value => {
      overlay.remove();
      if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
      resolve(value);
    };
    overlay.querySelectorAll('[data-workshop-stop-cancel]').forEach(button => button.addEventListener('click', () => finish('')));
    overlay.querySelector('[data-workshop-stop-apply]').addEventListener('click', () => {
      const reason = cleanNavisionText(overlay.querySelector('[data-workshop-stop-reason]')?.value || '');
      if (!reason) {
        window.alert('Enter the stoppage reason.');
        return;
      }
      finish(reason);
    });
    overlay.addEventListener('click', event => { if (event.target === overlay) finish(''); });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    overlay.querySelector('[data-workshop-stop-reason]')?.focus();
  });
}

async function stopWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (!workshopRequireOperatorProfile()) return;
  if (entry.status !== 'started') {
    window.alert('Start the job before recording a workshop stoppage.');
    return;
  }
  const reason = await workshopStoppageReasonModal(entry, vehicle);
  if (!reason) return;
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const next = { ...entry, status: 'stoppage', stoppageReason: reason, stoppageAt: now, updatedAt: now };
  const persisted = workshopPersistVehiclePlanAction(
    'Record workshop stoppage',
    workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows,
    vehicle,
    workshopOwnedBlockUpdates(entry, reason, now, operator),
    'Workshop job stoppage recorded',
    { stage: pmbStageLabel(entry.stage), reason, by: operator },
  );
  if (!persisted) return;
  offerSalespersonChangeEmail(vehicle, {
    title: `${pmbStageLabel(entry.stage)} job stoppage`,
    subject: 'PDC workshop stoppage',
    details: [`The workshop job has stopped: ${reason}.`, entry.stage === 'SUBLET' ? `Provider: ${entry.assignee || 'Unassigned'}.` : `Bay ${entry.bay}${entry.assignee ? ` · Mechanic: ${entry.assignee}` : ''}.`],
  });
  renderWorkshopPlanner();
}

function resumeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle || entry.status !== 'stoppage') return;
  if (!workshopRequireOperatorProfile()) return;
  const now = nowIsoString();
  const stoppageMinutes = Number(entry.stoppageMinutes || 0) + (entry.stoppageAt
    ? workshopWorkMinutesBetween(parseIsoTimestamp(entry.stoppageAt), parseIsoTimestamp(now))
    : 0);
  const operator = getCurrentOperatorName();
  const next = { ...entry, status: 'started', resumedAt: now, stoppageAt: '', stoppageMinutes: Number(stoppageMinutes.toFixed(2)), updatedAt: now };
  const persisted = workshopPersistVehiclePlanAction(
    'Resume workshop job',
    workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows,
    vehicle,
    workshopOwnedBlockClearUpdates(entry, vehicle, now, operator),
    'Workshop job resumed',
    { stage: pmbStageLabel(entry.stage), by: operator },
  );
  if (!persisted) return;
  renderWorkshopPlanner();
}

function startWorkshopResize(handle, event) {
  event.preventDefault();
  event.stopPropagation();
  const planId = handle.dataset.workshopResizePlan;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const chip = handle.closest('[data-workshop-plan-id]');
  const lane = handle.closest('[data-workshop-drop-bay]');
  if (!entry || !chip || !lane) return;
  const originX = event.clientX;
  const originalHours = workshopClampDurationHours(entry.hours);
  const segment = workshopEntrySegmentForDate(entry, workshopState().date);
  const onMove = moveEvent => {
    const deltaMinutes = workshopSnapMinutes(((moveEvent.clientX - originX) / Math.max(1, lane.getBoundingClientRect().width)) * WORKSHOP_DAY_MINUTES);
    const hours = workshopClampDurationHours(originalHours + deltaMinutes / 60);
    const visibleMinutes = Math.min(WORKSHOP_DAY_MINUTES - (segment?.start || 0), hours * 60);
    chip.style.setProperty('--plan-width', `${(visibleMinutes / WORKSHOP_DAY_MINUTES) * 100}%`);
    chip.dataset.previewHours = String(hours);
  };
  const onUp = () => {
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
    const hours = Number(chip.dataset.previewHours || entry.hours);
    delete chip.dataset.previewHours;
    const candidate = { ...entry, hours, updatedAt: nowIsoString() };
    const latestRows = workshopLoadPlans();
    const latestEntry = latestRows.find(row => row.id === entry.id);
    if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
      window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
      renderWorkshopPlanner();
      return;
    }
    const otherRows = latestRows.filter(row => row.id !== candidate.id);
    if (!workshopRequireNoBayConflict(candidate, otherRows)) {
      renderWorkshopPlanner();
      return;
    }
    if (!workshopRequireAvailableAssignee(candidate, otherRows)) {
      renderWorkshopPlanner();
      return;
    }
    const updatedRows = workshopCascadePlans(latestRows.map(row => row.id === entry.id ? candidate : row)).rows;
    const vehicle = workshopVehicle(entry.vehicleKey);
    const hoursMap = vehicle ? workshopEstimatedHoursMap(vehicle) : {};
    if (vehicle) hoursMap[entry.stage] = candidate.hours;
    const persisted = workshopPersistVehiclePlanAction(
      'Workshop plan duration changed',
      updatedRows,
      vehicle,
      vehicle ? { workshopEstimatedHoursByStage: hoursMap } : {},
      'Workshop plan duration changed',
      { stage: pmbStageLabel(entry.stage), hours: candidate.hours },
    );
    if (!persisted) {
      renderWorkshopPlanner();
      return;
    }
    workshopState().selectedPlanId = entry.id;
    renderWorkshopPlanner();
  };
  document.addEventListener('pointermove', onMove);
  document.addEventListener('pointerup', onUp);
}

function workshopWeeklyCardHtml(entry = {}, dateKey = '') {
  const vehicle = workshopVehicle(entry.vehicleKey);
  const segment = workshopEntrySegmentForDate(entry, dateKey);
  if (!vehicle || !segment) return '';
  const top = (segment.start / WORKSHOP_DAY_MINUTES) * 100;
  const height = ((segment.end - segment.start) / WORKSHOP_DAY_MINUTES) * 100;
  const draggable = entry.status === 'planned';
  return `<article class="workshop-week-card ${entry.status !== 'planned' ? 'is-live' : ''}" ${draggable ? 'draggable="true"' : ''} data-workshop-week-plan="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" style="--week-top:${top}%;--week-height:${height}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · ${entry.hours} hours${draggable ? ' · drag to another day/time' : ' · live jobs stay fixed'}`)}">
    <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')}</strong>
    <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
    <small>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</small>
    <em>${escapeHtml(entry.hours)}h</em>
  </article>`;
}

function workshopWeeklyTimeGuideHtml() {
  return Array.from({ length: 5 }, (_, index) => {
    const minutes = index * 120;
    return `<span style="top:${(minutes / WORKSHOP_DAY_MINUTES) * 100}%">${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</span>`;
  }).join('');
}

function moveWorkshopWeeklyPlan(planId = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, weekKey = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  if (!entry || entry.status !== 'planned') return;
  const candidate = {
    ...entry,
    stage: normalizePmbStage(stage),
    bay: Number(bay),
    startAt: workshopDateAtOffset(dateKey, startMinutes).toISOString(),
    updatedAt: nowIsoString(),
  };
  const latestRows = workshopLoadPlans();
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
    openWorkshopWeeklyView(stage, bay, weekKey || dateKey);
    return;
  }
  const otherRows = latestRows.filter(row => row.id !== candidate.id);
  if (!workshopRequireNoBayConflict(candidate, otherRows)) return;
  if (!workshopRequireAvailableAssignee(candidate, otherRows)) return;
  if (!workshopConfirmOtherDepartmentPlans(candidate, latestRows)) return;
  const updated = workshopCascadePlans(latestRows.map(row => row.id === candidate.id ? candidate : row)).rows;
  workshopPersistPlanAction(
    'Workshop weekly plan moved',
    updated,
    workshopVehicle(entry.vehicleKey),
    'Workshop weekly plan moved',
    { stage: pmbStageLabel(candidate.stage), bay: candidate.stage === 'SUBLET' ? 'Provider row' : `Bay ${candidate.bay}`, startAt: candidate.startAt },
  );
  workshopState().selectedPlanId = candidate.id;
  workshopState().date = workshopEntryDate(candidate);
  workshopSaveView(workshopState());
  renderWorkshopPlanner();
  openWorkshopWeeklyView(stage, bay, weekKey || dateKey);
}

function openWorkshopWeeklyView(stage = '', bay = 1, anchorDate = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return;
  document.querySelector('[data-workshop-week-overlay]')?.remove();
  const weekStart = workshopWeekStart(anchorDate || workshopState().date);
  const dates = workshopWeekDates(weekStart);
  const plans = workshopCascadeAndSave(workshopLoadPlans()).filter(entry => entry.stage === normalizedStage && Number(entry.bay) === Number(bay) && entry.status !== 'completed');
  const columns = dates.map(date => {
    const dateKey = workshopDateKey(date);
    const dayPlans = plans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
    const bookedHours = dayPlans.reduce((sum, entry) => {
      const segment = workshopEntrySegmentForDate(entry, dateKey);
      return sum + (segment ? (segment.end - segment.start) / 60 : 0);
    }, 0);
    return `<section class="workshop-week-day">
      <header><strong>${escapeHtml(date.toLocaleDateString('en-AU', { weekday: 'short' }))}</strong><span>${escapeHtml(date.toLocaleDateString('en-AU', { day: '2-digit', month: '2-digit' }))}</span><small>${escapeHtml(bookedHours.toFixed(bookedHours % 1 ? 1 : 0))}/8h booked</small></header>
      <div class="workshop-week-day-lane" data-workshop-week-drop-date="${escapeHtml(dateKey)}">${workshopWeeklyTimeGuideHtml()}${dayPlans.map(entry => workshopWeeklyCardHtml(entry, dateKey)).join('')}</div>
    </section>`;
  }).join('');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-week-overlay';
  overlay.dataset.workshopWeekOverlay = 'true';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-week-card-shell">
    <button class="modal-close" type="button" data-workshop-week-close aria-label="Close weekly view">×</button>
    <header class="workshop-week-header"><div><h2>${escapeHtml(pmbStageLabel(normalizedStage))} · Bay ${escapeHtml(bay)} weekly schedule</h2><p>${escapeHtml(dates[0].toLocaleDateString('en-AU', { day: 'numeric', month: 'long' }))}–${escapeHtml(dates[4].toLocaleDateString('en-AU', { day: 'numeric', month: 'long', year: 'numeric' }))} · drag a minimised booking to another day or time</p></div><div><button class="small-button" type="button" data-workshop-week-shift="-5">‹ Previous week</button><button class="small-button" type="button" data-workshop-week-shift="5">Next week ›</button></div></header>
    <div class="workshop-week-grid">${columns}</div>
    <footer><span>Live and stopped jobs are fixed. Planned jobs snap to 15 minutes and update the normal daily board immediately.</span><button class="primary" type="button" data-workshop-week-close>Done</button></footer>
  </section>`;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  overlay.querySelectorAll('[data-workshop-week-close]').forEach(button => button.addEventListener('click', close));
  overlay.querySelectorAll('[data-workshop-week-shift]').forEach(button => button.addEventListener('click', () => openWorkshopWeeklyView(normalizedStage, bay, workshopShiftWorkday(weekStart, Number(button.dataset.workshopWeekShift)))));
  overlay.querySelectorAll('[data-workshop-week-plan][draggable="true"]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', card.dataset.workshopWeekPlan);
  }));
  overlay.querySelectorAll('[data-workshop-week-drop-date]').forEach(lane => {
    lane.addEventListener('dragover', event => { event.preventDefault(); lane.classList.add('drag-over'); });
    lane.addEventListener('dragleave', event => { if (!lane.contains(event.relatedTarget)) lane.classList.remove('drag-over'); });
    lane.addEventListener('drop', event => {
      event.preventDefault();
      lane.classList.remove('drag-over');
      const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
      const rect = lane.getBoundingClientRect();
      const startMinutes = workshopClampStartMinutes(((event.clientY - rect.top) / Math.max(1, rect.height)) * WORKSHOP_DAY_MINUTES);
      moveWorkshopWeeklyPlan(planId, normalizedStage, bay, lane.dataset.workshopWeekDropDate, startMinutes, workshopDateKey(weekStart));
    });
  });
  overlay.querySelectorAll('[data-workshop-job-vehicle]').forEach(card => card.addEventListener('dblclick', () => openWorkshopVehicleJob(card.dataset.workshopJobVehicle, normalizedStage)));
  overlay.addEventListener('click', event => { if (event.target === overlay) close(); });
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
}

function workshopJobStageOptionsHtml(selected = '') {
  const normalized = normalizePmbStage(selected);
  return `<option value="">Unallocated</option>${WORKSHOP_STAGE_SEQUENCE.map(stage => `<option value="${escapeHtml(stage)}"${stage === normalized ? ' selected' : ''}>${escapeHtml(pmbStageLabel(stage))}</option>`).join('')}`;
}

function workshopJobLineRowsHtml(vehicle = {}) {
  const lines = workshopResolvedJobLines(vehicle);
  if (!lines.length) return '<div class="workshop-job-lines-empty">No AI/imported job lines are attached. Add manual time for the current bay below.</div>';
  return lines.map(line => `<div class="workshop-job-line-row" data-workshop-job-line="${escapeHtml(line.id)}">
    <span title="${escapeHtml(line.text)}">${escapeHtml(line.text)}</span>
    <label><small>Work area</small><select name="line_stage_${escapeHtml(line.id)}">${workshopJobStageOptionsHtml(line.stage)}</select></label>
    <label><small>Line hours</small><input type="number" name="line_hours_${escapeHtml(line.id)}" min="0.25" step="0.25" value="${escapeHtml(line.hours)}"></label>
  </div>`).join('');
}

function openWorkshopVehicleJob(key = '', requestedStage = '') {
  const vehicle = workshopVehicle(key);
  if (!vehicle) return;
  const stage = WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(requestedStage)) ? normalizePmbStage(requestedStage) : (normalizePmbStage(inferredPmbStage(vehicle)) || workshopState().stage);
  document.querySelector('[data-workshop-job-overlay]')?.remove();
  const parts = workshopPartsSummary(vehicle);
  const required = pdcRequirementDefinitions(vehicle).filter(def => pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def)).map(def => def.label);
  const stageLines = workshopStageJobLines(vehicle, stage);
  const additionalHours = Number(workshopAdditionalHoursMap(vehicle)[stage] || 0);
  const calculatedHours = workshopCalculatedStageHours(vehicle, stage);
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-job-overlay';
  overlay.dataset.workshopJobOverlay = 'true';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-job-card">
    <button class="modal-close" type="button" data-workshop-job-close aria-label="Close vehicle job">×</button>
    <header><div><h2>${escapeHtml(pmbStageLabel(stage))} vehicle job</h2><p>Only ${escapeHtml(pmbStageLabel(stage))} time is shown for this bay. Allocate imported job lines to another work area when needed.</p></div><span class="badge neutral">AI lines + manual time</span></header>
    <div class="workshop-job-vehicle-summary">
      <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')} · Job Card ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')}</span>
      <small>Outstanding work: ${escapeHtml(required.join(', ') || 'None')}</small>
      <small class="workshop-parts-line parts-${escapeHtml(parts.status)}">Parts: ${escapeHtml(parts.text)}</small>
    </div>
    <form data-workshop-job-form data-workshop-job-key="${escapeHtml(vehicleKey(vehicle))}" data-workshop-job-stage="${escapeHtml(stage)}">
      <section class="workshop-current-stage-time">
        <div><strong>${escapeHtml(pmbStageLabel(stage))} planned time</strong><span>${escapeHtml(calculatedHours)} hours total · ${stageLines.length} imported line${stageLines.length === 1 ? '' : 's'} allocated here</span></div>
        <label><span>Additional manual hours for this bay</span><input type="number" name="additional_hours" min="0" step="0.25" value="${escapeHtml(additionalHours)}"></label>
      </section>
      <section class="workshop-job-lines"><header><strong>Imported job lines</strong><span>Change the work area to allocate a line elsewhere.</span></header>${workshopJobLineRowsHtml(vehicle)}</section>
      <div class="workshop-job-notes"><strong>Team notes</strong><span>${escapeHtml(teamNotesText(vehicle) || 'No additional team notes.')}</span></div>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-job-close>Cancel</button><button class="primary" type="submit">Save job allocation</button><button class="small-button" type="button" data-workshop-job-full-vehicle="${escapeHtml(vehicleKey(vehicle))}">Open full vehicle</button></div>
    </form>
  </section>`;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  overlay.querySelectorAll('[data-workshop-job-close]').forEach(button => button.addEventListener('click', close));
  overlay.addEventListener('click', event => { if (event.target === overlay) close(); });
  overlay.querySelector('[data-workshop-job-full-vehicle]')?.addEventListener('click', event => {
    const vehicleKeyValue = event.currentTarget.dataset.workshopJobFullVehicle;
    close();
    openVehicleModal(vehicleKeyValue);
  });
  overlay.querySelector('[data-workshop-job-form]')?.addEventListener('submit', event => {
    event.preventDefault();
    if (!workshopRequireOperatorProfile()) return;
    const form = event.currentTarget;
    const data = new FormData(form);
    const currentStage = normalizePmbStage(form.dataset.workshopJobStage);
    const assignments = workshopJobLineAssignments(vehicle);
    const lineRows = workshopImportedJobLines(vehicle);
    lineRows.forEach(line => {
      const lineStage = normalizePmbStage(data.get(`line_stage_${line.id}`) || '');
      const lineHours = Number(data.get(`line_hours_${line.id}`));
      assignments[line.id] = {
        stage: WORKSHOP_STAGE_SEQUENCE.includes(lineStage) ? lineStage : '',
        hours: Number.isFinite(lineHours) && lineHours > 0 ? workshopClampLineHours(lineHours) : 1,
      };
    });
    const additionalMap = workshopAdditionalHoursMap(vehicle);
    const additionalHoursValue = Number(data.get('additional_hours') || 0);
    additionalMap[currentStage] = Number.isFinite(additionalHoursValue) ? Math.max(0, additionalHoursValue) : 0;
    const hoursMap = workshopEstimatedHoursMap(vehicle);
    const stageTotals = {};
    Object.values(assignments).forEach(assignment => {
      const lineStage = normalizePmbStage(assignment.stage);
      if (!WORKSHOP_STAGE_SEQUENCE.includes(lineStage)) return;
      stageTotals[lineStage] = Number(stageTotals[lineStage] || 0) + Number(assignment.hours || 0);
    });
    WORKSHOP_STAGE_SEQUENCE.forEach(workArea => {
      const total = Number(stageTotals[workArea] || 0) + Number(additionalMap[workArea] || 0);
      if (total > 0) hoursMap[workArea] = workshopClampDurationHours(total);
    });
    const updatedPlans = workshopLoadPlans().map(entry => entry.vehicleKey === vehicleKey(vehicle) && entry.status !== 'completed' && Number(hoursMap[entry.stage]) > 0
      ? { ...entry, hours: workshopClampDurationHours(hoursMap[entry.stage]), updatedAt: nowIsoString() }
      : entry);
    const conflictingBayPlan = updatedPlans.find(entry => entry.vehicleKey === vehicleKey(vehicle) && workshopHasConflict(entry, updatedPlans.filter(other => other.id !== entry.id)));
    if (conflictingBayPlan) {
      workshopRequireNoBayConflict(conflictingBayPlan, updatedPlans.filter(entry => entry.id !== conflictingBayPlan.id));
      return;
    }
    const conflictingPlan = updatedPlans.find(entry => entry.vehicleKey === vehicleKey(vehicle) && workshopEntryHasAssigneeConflict(entry, updatedPlans));
    if (conflictingPlan) {
      workshopRequireAvailableAssignee(conflictingPlan, updatedPlans.filter(entry => entry.id !== conflictingPlan.id));
      return;
    }
    const persistAllocation = () => {
      saveVehicleEdits(vehicleKey(vehicle), {
        workshopJobLineAssignments: assignments,
        workshopAdditionalHoursByStage: additionalMap,
        workshopEstimatedHoursByStage: hoursMap,
      }, { render: false });
      recordVehicleAudit(vehicle, 'Workshop job allocation updated', {
        stage: pmbStageLabel(currentStage),
        additionalHours: additionalMap[currentStage] || 0,
        importedLines: lineRows.length,
      });
      workshopSavePlans(workshopCascadePlans(updatedPlans).rows);
    };
    if (typeof runStorageTransaction === 'function') {
      const keys = typeof trackerTransactionKeys === 'function' ? trackerTransactionKeys([WORKSHOP_PLAN_STORAGE_KEY]) : [WORKSHOP_PLAN_STORAGE_KEY];
      runStorageTransaction('Workshop job allocation updated', keys, persistAllocation);
    } else persistAllocation();
    close();
    renderWorkshopPlanner();
  });
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
  overlay.querySelector('input')?.focus();
}

function setupWorkshopPlannerClock() {
  if (app.workshopPlannerTimer) window.clearInterval(app.workshopPlannerTimer);
  if (app.currentView !== 'workshop') return;
  app.workshopPlannerTimer = window.setInterval(() => {
    if (app.currentView !== 'workshop') return;
    const active = document.activeElement;
    if (document.querySelector('.modal-overlay') || active?.closest?.('.workshop-job-detail, .workshop-search')) {
      updateWorkshopNowLine(document.querySelector('#workshop-planner-root') || document);
      return;
    }
    renderWorkshopPlanner();
  }, 60000);
}

function updateWorkshopNowLine(root = document) {
  const line = root.querySelector('[data-workshop-now-line]');
  const timeline = root.querySelector('.workshop-timeline');
  const axis = root.querySelector('.workshop-time-axis');
  if (!line || !timeline || !axis) return;
  const state = workshopState();
  const now = new Date();
  const offset = workshopMinuteOffset(now);
  const visible = workshopDateKey(now) === state.date && workshopIsWorkday(now) && offset >= 0 && offset <= WORKSHOP_DAY_MINUTES;
  line.hidden = !visible;
  if (!visible) return;
  const timelineRect = timeline.getBoundingClientRect();
  const axisRect = axis.getBoundingClientRect();
  const left = axisRect.left - timelineRect.left + (offset / WORKSHOP_DAY_MINUTES) * axisRect.width;
  line.style.left = `${Math.round(left)}px`;
  line.querySelector('span').textContent = `Now ${now.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' })}`;
}

if (typeof window !== 'undefined' && !window.__workshopPlannerStorageSyncBound) {
  window.__workshopPlannerStorageSyncBound = true;
  window.addEventListener('storage', event => {
    if (![WORKSHOP_PLAN_STORAGE_KEY, WORKSHOP_BAY_SETUP_STORAGE_KEY, WORKSHOP_VIEW_STORAGE_KEY].includes(event.key)) return;
    if (typeof app !== 'undefined' && app.currentView === 'workshop') renderWorkshopPlanner();
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    WORKSHOP_START_HOUR,
    WORKSHOP_END_HOUR,
    WORKSHOP_DAY_MINUTES,
    WORKSHOP_DEFAULT_HOURS,
    WORKSHOP_STAGE_SEQUENCE,
    workshopIsWorkday,
    workshopCoerceWorkDate,
    workshopShiftWorkday,
    workshopWeekStart,
    workshopWeekDates,
    workshopSnapMinutes,
    workshopClampLineHours,
    workshopClampStartMinutes,
    workshopClampDurationHours,
    workshopIntervalsOverlap,
    workshopHasConflict,
    workshopRequireNoBayConflict,
    workshopDateKey,
    workshopDateFromKey,
    workshopNormalizeStartDate,
    workshopAddWorkMinutes,
    workshopWorkMinutesBetween,
    workshopCascadePlans,
    workshopEntrySegmentForDate,
    workshopEntryIsOvertime,
    workshopEntryHasAssigneeConflict,
    workshopAssigneeConflict,
    workshopOwnedBlockUpdates,
    workshopOwnedBlockClearUpdates,
    workshopRunVehiclePlanTransaction,
    workshopRequireOperatorProfile,
    workshopNextWorkdayDate,
    workshopNextDayFittingPartsWarnings,
    workshopNextDayFittingWarningEmailBody,
    workshopFirstAvailableStartMinutes,
    workshopFirstAvailableStartSlot,
  };
}
