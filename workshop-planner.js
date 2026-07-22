'use strict';

const WORKSHOP_PLAN_STORAGE_KEY = 'vehicleTrackingCoreWorkshopPlan:v1';
const WORKSHOP_VIEW_STORAGE_KEY = 'vehicleTrackingCoreWorkshopView:v1';
const WORKSHOP_BAY_SETUP_STORAGE_KEY = 'vehicleTrackingCoreWorkshopBaySetup:v1';
const WORKSHOP_DETAIL_SESSION_KEY = 'vehicleTrackingCoreWorkshopDetailPanel:v1';
// Stage 2A final remediation: all authoritative planner configuration is
// integer minutes or validated collections. Fractional clock hours are never
// stored and are never passed to Date APIs.
const WORKSHOP_STAGE_SEQUENCE = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION', 'SUBLET'];
const WORKSHOP_VISIBLE_STAGE_SEQUENCE = WORKSHOP_STAGE_SEQUENCE.filter(stage => stage !== 'SUBLET');
const WORKSHOP_DAY_NAME_TO_INDEX = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
const WORKSHOP_INDEX_TO_DAY_NAME = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const WORKSHOP_BOOT_CONFIG = Object.freeze({
  dayStartMinutes: 8 * 60,
  dayEndMinutes: 16 * 60,
  dayLengthMinutes: 8 * 60,
  schedulingIncrementMinutes: 15,
  defaultBookingDurationMinutes: 3 * 60,
  workingDayIndexes: Object.freeze([1, 2, 3, 4, 5]),
  closureDateKeys: Object.freeze([]),
  breakWindowsByDateOrScope: Object.freeze([]),
  overtimeWindowsByDateOrScope: Object.freeze([]),
  technicianLeaveByTechnicianId: Object.freeze({}),
});
let WORKSHOP_PLANNER_CONFIG = { ...WORKSHOP_BOOT_CONFIG, workingDayIndexes: [...WORKSHOP_BOOT_CONFIG.workingDayIndexes] };
let WORKSHOP_CONFIG_AUTHORITY = 'boot';

function workshopClockMinutes(value) {
  const match = typeof value === 'string' && value.match(/^([01][0-9]|2[0-3]):([0-5][0-9])$/);
  return match ? Number(match[1]) * 60 + Number(match[2]) : null;
}

function workshopSetClock(date, minutesFromMidnight) {
  const copy = new Date(date);
  const minutes = Number(minutesFromMidnight);
  copy.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0);
  return copy;
}

function workshopValidDateKey(value) {
  const match = typeof value === 'string' && value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return '';
  const candidate = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return candidate.getFullYear() === Number(match[1])
    && candidate.getMonth() === Number(match[2]) - 1
    && candidate.getDate() === Number(match[3]) ? value : '';
}

function workshopNormalizeWindows(value) {
  if (!Array.isArray(value)) return null;
  const normalized = [];
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
    const startMinutes = workshopClockMinutes(item.start);
    const endMinutes = workshopClockMinutes(item.end);
    if (!Number.isInteger(startMinutes) || !Number.isInteger(endMinutes) || startMinutes >= endMinutes) return null;
    const dateKey = item.date == null ? '' : workshopValidDateKey(item.date);
    if (item.date != null && !dateKey) return null;
    const scope = String(item.scope || item.day || 'global').trim().toLowerCase();
    if (scope !== 'global' && scope !== 'working_day' && !Object.prototype.hasOwnProperty.call(WORKSHOP_DAY_NAME_TO_INDEX, scope)) return null;
    normalized.push(Object.freeze({ startMinutes, endMinutes, dateKey, scope }));
  }
  return normalized;
}

function workshopNormalizeLeave(value) {
  if (!Array.isArray(value)) return null;
  const byTechnician = {};
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
    const technicianId = String(item.technician_id || '').trim();
    const dateKey = workshopValidDateKey(item.date);
    if (!technicianId || !dateKey) return null;
    if (!byTechnician[technicianId]) byTechnician[technicianId] = [];
    if (!byTechnician[technicianId].includes(dateKey)) byTechnician[technicianId].push(dateKey);
  }
  Object.values(byTechnician).forEach(keys => Object.freeze(keys.sort()));
  return Object.freeze(byTechnician);
}

function workshopConfigurationFromRows(rows) {
  if (!rows || typeof rows !== 'object') return null;
  const dayStartMinutes = workshopClockMinutes(rows.day_start_time?.value);
  const dayEndMinutes = workshopClockMinutes(rows.day_end_time?.value);
  const schedulingIncrementMinutes = Number(rows.scheduling_increment_minutes?.value);
  const defaultBookingDurationMinutes = Number(rows.default_booking_duration_minutes?.value);
  const workingWeek = rows.working_week?.value;
  const closures = rows.closures?.value;
  const breakWindows = workshopNormalizeWindows(rows.break_windows?.value);
  const overtimeWindows = workshopNormalizeWindows(rows.overtime_windows?.value);
  const technicianLeave = workshopNormalizeLeave(rows.technician_leave?.value);
  if (!Number.isInteger(dayStartMinutes) || !Number.isInteger(dayEndMinutes) || dayStartMinutes >= dayEndMinutes
      || !Number.isInteger(schedulingIncrementMinutes) || schedulingIncrementMinutes <= 0
      || !Number.isInteger(defaultBookingDurationMinutes) || defaultBookingDurationMinutes <= 0
      || !Array.isArray(workingWeek) || workingWeek.length < 1
      || !Array.isArray(closures) || breakWindows === null || overtimeWindows === null || technicianLeave === null) return null;
  const workingDayIndexes = workingWeek.map(name => WORKSHOP_DAY_NAME_TO_INDEX[String(name || '').toLowerCase()]);
  if (workingDayIndexes.some(value => !Number.isInteger(value)) || new Set(workingDayIndexes).size !== workingDayIndexes.length) return null;
  const closureDateKeys = closures.map(item => workshopValidDateKey(item && item.date));
  if (closureDateKeys.some(value => !value)) return null;
  return Object.freeze({
    dayStartMinutes,
    dayEndMinutes,
    dayLengthMinutes: dayEndMinutes - dayStartMinutes,
    schedulingIncrementMinutes,
    defaultBookingDurationMinutes,
    workingDayIndexes: Object.freeze([...workingDayIndexes].sort()),
    closureDateKeys: Object.freeze([...new Set(closureDateKeys)].sort()),
    breakWindowsByDateOrScope: Object.freeze(breakWindows),
    overtimeWindowsByDateOrScope: Object.freeze(overtimeWindows),
    technicianLeaveByTechnicianId: technicianLeave,
  });
}

function workshopSyncConfigFromSharedSettings() {
  if (typeof window === 'undefined' || !window.__workshopReferenceDataService) return false;
  const service = window.__workshopReferenceDataService;
  if (typeof service.getCachedWorkshopConfiguration !== 'function') return false;
  const cached = service.getCachedWorkshopConfiguration();
  if (!cached || !new Set(['connected_read_only', 'connected_editable']).has(cached.state)) {
    WORKSHOP_CONFIG_AUTHORITY = WORKSHOP_CONFIG_AUTHORITY === 'shared_valid' ? 'shared_stale' : 'shared_unavailable';
    return false;
  }
  const next = workshopConfigurationFromRows(cached.rows);
  if (!next) {
    WORKSHOP_CONFIG_AUTHORITY = WORKSHOP_CONFIG_AUTHORITY === 'shared_valid' ? 'shared_stale' : 'shared_invalid';
    return false;
  }
  const changed = JSON.stringify(next) !== JSON.stringify(WORKSHOP_PLANNER_CONFIG);
  WORKSHOP_PLANNER_CONFIG = next;
  WORKSHOP_CONFIG_AUTHORITY = 'shared_valid';
  return changed;
}

function workshopConfigurationAllowsNewScheduling() {
  if (typeof window === 'undefined' || !window.__workshopReferenceDataService) return true;
  return WORKSHOP_CONFIG_AUTHORITY === 'shared_valid';
}

if (typeof window !== 'undefined') {
  try { workshopSyncConfigFromSharedSettings(); } catch (_err) { WORKSHOP_CONFIG_AUTHORITY = 'shared_invalid'; }
}

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
  const valid = workshopValidDateKey(String(value || ''));
  if (!valid) return null;
  const [year, month, day] = valid.split('-').map(Number);
  return workshopSetClock(new Date(year, month - 1, day), WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
}

function workshopDefaultBookingHours() {
  return WORKSHOP_PLANNER_CONFIG.defaultBookingDurationMinutes / 60;
}

function workshopIsConfiguredWorkingDay(date = new Date()) {
  return WORKSHOP_PLANNER_CONFIG.workingDayIndexes.includes(date.getDay());
}

function workshopIsClosureDate(date = new Date()) {
  return WORKSHOP_PLANNER_CONFIG.closureDateKeys.includes(workshopDateKey(date));
}

function workshopIsWorkday(date = new Date()) {
  return workshopIsConfiguredWorkingDay(date) && !workshopIsClosureDate(date);
}

function workshopCoerceWorkDate(date = new Date(), direction = 1) {
  let next = workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
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
  return workshopSetClock(next, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
}

function workshopWeekStart(value = new Date()) {
  const date = value instanceof Date ? new Date(value) : (workshopDateFromKey(value) || new Date(value));
  let safe = Number.isNaN(date.getTime()) ? new Date() : date;
  safe = workshopSetClock(safe, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  const day = safe.getDay();
  safe.setDate(safe.getDate() + (day === 0 ? -6 : 1 - day));
  return safe;
}

function workshopWeekDates(value = new Date()) {
  const start = workshopWeekStart(value);
  return Array.from({ length: 7 }, (_, index) => {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    return workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  }).filter(date => workshopIsConfiguredWorkingDay(date));
}

function workshopSnapMinutes(value = 0) {
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  return Math.round(Number(value || 0) / increment) * increment;
}

function workshopClampStartMinutes(value = 0) {
  return Math.max(0, Math.min(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes - WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, workshopSnapMinutes(value)));
}

function workshopClampLineHours(value = 1) {
  const requestedMinutes = workshopSnapMinutes(Math.max(WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, Number(value || 1) * 60));
  return requestedMinutes / 60;
}

function workshopClampDurationHours(value = workshopDefaultBookingHours()) {
  return Math.max(1, workshopClampLineHours(value || workshopDefaultBookingHours()));
}

function workshopIntervalsOverlap(startA, endA, startB, endB) {
  return Number(startA) < Number(endB) && Number(startB) < Number(endA);
}

function workshopMinuteOfDay(date = new Date()) {
  return date.getHours() * 60 + date.getMinutes();
}

function workshopMinuteOffset(date = new Date()) {
  return workshopMinuteOfDay(date) - WORKSHOP_PLANNER_CONFIG.dayStartMinutes;
}

function workshopWindowApplies(window, date) {
  if (window.dateKey) return window.dateKey === workshopDateKey(date);
  if (window.scope === 'global' || window.scope === 'working_day') return true;
  return WORKSHOP_DAY_NAME_TO_INDEX[window.scope] === date.getDay();
}

function workshopSubtractWindows(windows, exclusions) {
  let result = windows.map(window => ({ ...window }));
  for (const excluded of exclusions) {
    const next = [];
    for (const window of result) {
      if (!workshopIntervalsOverlap(window.startMinutes, window.endMinutes, excluded.startMinutes, excluded.endMinutes)) {
        next.push(window);
        continue;
      }
      if (excluded.startMinutes > window.startMinutes) next.push({ ...window, endMinutes: excluded.startMinutes });
      if (excluded.endMinutes < window.endMinutes) next.push({ ...window, startMinutes: excluded.endMinutes });
    }
    result = next;
  }
  return result.filter(window => window.endMinutes > window.startMinutes);
}

function workshopAvailabilityWindowsForDate(dateValue = new Date()) {
  const date = dateValue instanceof Date ? new Date(dateValue) : workshopDateFromKey(dateValue);
  if (!date || !workshopIsWorkday(date)) return [];
  const overtime = WORKSHOP_PLANNER_CONFIG.overtimeWindowsByDateOrScope
    .filter(window => workshopWindowApplies(window, date))
    .map(window => ({ ...window, overtime: true }));
  const regular = [{ startMinutes: WORKSHOP_PLANNER_CONFIG.dayStartMinutes, endMinutes: WORKSHOP_PLANNER_CONFIG.dayEndMinutes, overtime: false }];
  const breaks = WORKSHOP_PLANNER_CONFIG.breakWindowsByDateOrScope.filter(window => workshopWindowApplies(window, date));
  const windows = workshopSubtractWindows([...regular, ...overtime], breaks)
    .sort((a, b) => a.startMinutes - b.startMinutes || a.endMinutes - b.endMinutes);
  const merged = [];
  for (const window of windows) {
    const previous = merged[merged.length - 1];
    if (previous && previous.endMinutes >= window.startMinutes && previous.overtime === window.overtime) {
      previous.endMinutes = Math.max(previous.endMinutes, window.endMinutes);
    } else merged.push({ ...window });
  }
  return merged;
}

function workshopBreakWindowsForDate(dateValue = new Date()) {
  const date = dateValue instanceof Date ? dateValue : workshopDateFromKey(dateValue);
  return date ? WORKSHOP_PLANNER_CONFIG.breakWindowsByDateOrScope.filter(window => workshopWindowApplies(window, date)) : [];
}

function workshopDateAtOffset(dateKey, minuteOffset = 0) {
  const date = workshopDateFromKey(dateKey) || workshopCoerceWorkDate(new Date());
  return workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayStartMinutes + workshopClampStartMinutes(minuteOffset));
}

function workshopMoveToNextWorkStart(date = new Date()) {
  const next = new Date(date);
  next.setDate(next.getDate() + 1);
  return workshopNormalizeStartDate(workshopCoerceWorkDate(next, 1));
}

function workshopMoveToPreviousWorkEnd(date = new Date()) {
  const previous = new Date(date);
  previous.setDate(previous.getDate() - 1);
  const workDate = workshopCoerceWorkDate(previous, -1);
  const windows = workshopAvailabilityWindowsForDate(workDate);
  return workshopSetClock(workDate, windows.length ? windows[windows.length - 1].endMinutes : WORKSHOP_PLANNER_CONFIG.dayEndMinutes);
}

function workshopNormalizeStartDate(value = new Date()) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date)) date = workshopCoerceWorkDate(date, 1);
  for (let guard = 0; guard < 370; guard += 1) {
    const windows = workshopAvailabilityWindowsForDate(date);
    const minute = workshopMinuteOfDay(date);
    for (const window of windows) {
      if (minute <= window.startMinutes) return workshopSetClock(date, window.startMinutes);
      if (minute < window.endMinutes) {
        const snapped = Math.ceil(minute / WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes) * WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
        return workshopSetClock(date, Math.min(snapped, window.endMinutes));
      }
    }
    date = workshopCoerceWorkDate(new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1), 1);
  }
  return workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
}

function workshopLatestWorkMoment(value = new Date()) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date)) return workshopMoveToPreviousWorkEnd(date);
  const windows = workshopAvailabilityWindowsForDate(date);
  const minute = workshopMinuteOfDay(date);
  let latest = null;
  for (const window of windows) {
    if (minute < window.startMinutes) break;
    latest = workshopSetClock(date, Math.min(minute, window.endMinutes));
    if (minute <= window.endMinutes) break;
  }
  return latest || workshopMoveToPreviousWorkEnd(date);
}

function workshopAddWorkMinutes(startValue = new Date(), minutes = 0) {
  let current = workshopNormalizeStartDate(startValue);
  let remaining = Math.max(0, Number(minutes) || 0);
  while (remaining > 0) {
    const windows = workshopAvailabilityWindowsForDate(current);
    const minute = workshopMinuteOfDay(current);
    const window = windows.find(item => minute >= item.startMinutes && minute < item.endMinutes)
      || windows.find(item => minute < item.startMinutes);
    if (!window) {
      current = workshopMoveToNextWorkStart(current);
      continue;
    }
    if (minute < window.startMinutes) current = workshopSetClock(current, window.startMinutes);
    const available = window.endMinutes - workshopMinuteOfDay(current);
    if (remaining <= available) return new Date(current.getTime() + remaining * 60000);
    remaining -= available;
    const nextWindow = windows.find(item => item.startMinutes >= window.endMinutes && item.endMinutes > window.endMinutes);
    current = nextWindow ? workshopSetClock(current, nextWindow.startMinutes) : workshopMoveToNextWorkStart(current);
  }
  return current;
}

function workshopWorkMinutesBetween(startValue, endValue) {
  const start = startValue instanceof Date ? new Date(startValue) : new Date(startValue);
  const end = endValue instanceof Date ? new Date(endValue) : new Date(endValue);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start) return 0;
  let date = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  let total = 0;
  while (date <= end) {
    for (const window of workshopAvailabilityWindowsForDate(date)) {
      const windowStart = workshopSetClock(date, window.startMinutes);
      const windowEnd = workshopSetClock(date, window.endMinutes);
      const overlapStart = start > windowStart ? start : windowStart;
      const overlapEnd = end < windowEnd ? end : windowEnd;
      if (overlapEnd > overlapStart) total += (overlapEnd - overlapStart) / 60000;
    }
    date.setDate(date.getDate() + 1);
  }
  return total;
}

function workshopEntryStart(entry = {}) {
  return parseIsoTimestamp(entry.startAt || '') || workshopNormalizeStartDate(new Date());
}

function workshopEntryEnd(entry = {}) {
  const start = workshopEntryStart(entry);
  const durationMinutes = workshopClampDurationHours(entry.hours) * 60;
  // Historical rows on a date that later became closed remain renderable at
  // their recorded wall-clock position; closure/leave only block new writes.
  if (!workshopIsWorkday(start)) return new Date(start.getTime() + durationMinutes * 60000);
  return workshopAddWorkMinutes(start, durationMinutes);
}

function workshopEntryUsesConfiguredOvertime(entry = {}) {
  const start = workshopEntryStart(entry);
  const end = workshopEntryEnd(entry);
  let date = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  while (date <= end) {
    for (const window of workshopAvailabilityWindowsForDate(date).filter(item => item.overtime)) {
      if (workshopIntervalsOverlap(start, end, workshopSetClock(date, window.startMinutes), workshopSetClock(date, window.endMinutes))) return true;
    }
    date.setDate(date.getDate() + 1);
  }
  return false;
}

function workshopEntryIsOvertime(entry = {}, now = new Date()) {
  if (!workshopEntryIsLive(entry)) return false;
  return workshopLatestWorkMoment(now) > workshopEntryEnd(entry);
}

function workshopEntryEffectiveEnd(entry = {}, now = new Date()) {
  const plannedEnd = workshopEntryEnd(entry);
  if (!workshopEntryIsOvertime(entry, now)) return plannedEnd;
  const latest = workshopLatestWorkMoment(now);
  return workshopAddWorkMinutes(latest, WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes);
}

function workshopEntrySegmentForDate(entry = {}, dateKey = '', now = new Date()) {
  let dayStart = workshopDateFromKey(dateKey);
  if (!dayStart || !workshopIsConfiguredWorkingDay(dayStart)) return null;
  dayStart = workshopSetClock(dayStart, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  const dayEnd = workshopSetClock(dayStart, WORKSHOP_PLANNER_CONFIG.dayEndMinutes);
  const start = workshopEntryStart(entry);
  const end = workshopEntryEffectiveEnd(entry, now);
  if (end <= dayStart || start >= dayEnd) return null;
  const segmentStart = start > dayStart ? start : dayStart;
  const segmentEnd = end < dayEnd ? end : dayEnd;
  const startMinutes = Math.max(0, workshopMinuteOffset(segmentStart));
  const endMinutes = Math.min(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes, segmentEnd >= dayEnd ? WORKSHOP_PLANNER_CONFIG.dayLengthMinutes : workshopMinuteOffset(segmentEnd));
  return {
    start: startMinutes,
    end: Math.max(startMinutes + WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, endMinutes),
    continuesFromPrevious: start < dayStart,
    continuesNext: end > dayEnd,
    historicalOnClosure: workshopIsClosureDate(dayStart),
    usesConfiguredOvertime: workshopEntryUsesConfiguredOvertime(entry),
  };
}
function workshopSharedModeActive() {
  return typeof window !== 'undefined'
    && typeof window.workshopSharedModeEnabled === 'function'
    && window.workshopSharedModeEnabled(window.PDC_SUPABASE_CONFIG)
    && window.__workshopDataService
    && typeof window.__workshopDataService.isEnabled === 'function'
    && window.__workshopDataService.isEnabled();
}

// Section 13 fail-closed connection banner. Distinguishes the states the
// migration plan requires: Connected/editable, Connected/read-only,
// Reconnecting, Offline/read-only, Backend version incompatible.
function workshopConnectionBannerHtml() {
  const ds = window.__workshopDataService;
  const state = ds && typeof ds.getState === 'function' ? ds.getState() : 'disabled';
  const CS = window.WORKSHOP_CONNECTION_STATE || {};
  const copy = {
    [CS.CONNECTED_EDITABLE]: { cls: 'ok', text: 'Connected · shared workshop data · live editing available once the legacy import is approved' },
    [CS.CONNECTED_READ_ONLY]: { cls: 'warn', text: 'Connected · read-only (viewer role, or editing is not yet unlocked for this account)' },
    [CS.RECONNECTING]: { cls: 'warn', text: 'Reconnecting to shared workshop data… showing the last known state' },
    [CS.OFFLINE_READ_ONLY]: { cls: 'error', text: 'Offline · showing the last known shared state, read-only until the connection recovers' },
    [CS.INCOMPATIBLE]: { cls: 'error', text: 'Backend version incompatible with this Workshop Planner build. Contact an administrator.' },
    [CS.CONNECTING]: { cls: 'warn', text: 'Connecting to shared workshop data…' },
  }[state] || { cls: 'warn', text: 'Shared workshop mode status unknown' };
  return `<div class="workshop-connection-banner workshop-connection-${copy.cls}" role="status">${escapeHtml(copy.text)}</div>`;
}


// Maps one get_workshop_snapshot() booking DTO (see migration 012) into the
// same legacy plan-row shape the rest of this file already expects, so the
// existing rendering/interaction code needs no changes to read shared data.
function workshopMapSnapshotBookingToLegacyRow(booking = {}) {
  if (!booking || !booking.booking_id) return null;
  const vehicle = booking.vehicle || {};
  const sharedVehicleId = String(vehicle.id || booking.vehicle_id || '').trim();
  // A shared booking without its canonical vehicle UUID is not safe to adapt:
  // stock/permanent-id text can change or be duplicated. Fail closed instead
  // of creating a legacy row that later has to reverse-map by first match.
  if (!sharedVehicleId) return null;
  const stage = booking.stage || {};
  const bay = booking.bay || null;
  const assignment = booking.assignment || null;
  const legacyStatus = { queued: 'planned', planned: 'planned', started: 'started', stoppage: 'stoppage', completed: 'completed', deleted: 'deleted' }[booking.status] || 'planned';
  return {
    id: booking.booking_id,
    sharedBookingId: booking.booking_id,
    sharedVersion: booking.version,
    sharedVehicleId,
    vehicleKey: vehicle.stock_number || vehicle.permanent_vehicle_id || '',
    stage: normalizePmbStage(stage.code || ''),
    bay: bay ? Number(bay.bay_number) || 0 : 0,
    startAt: booking.scheduled_start_at,
    hours: Number(booking.default_duration_minutes || 0) / 60 || workshopDefaultBookingHours(),
    assignee: assignment ? assignment.technician_name || '' : '',
    technicianId: assignment ? assignment.technician_id || '' : '',
    status: legacyStatus,
    stoppageReason: booking.stoppage_reason || '',
    stoppageAt: booking.stoppage_started_at || '',
    stoppageMinutes: Number(booking.stoppage_accumulated_minutes || 0),
    actualHours: booking.actual_duration_minutes != null ? Number(booking.actual_duration_minutes) / 60 : undefined,
    completedAt: booking.actual_end_at || '',
    createdAt: booking.created_at,
    updatedAt: booking.updated_at,
  };
}

function workshopLoadPlans() {
  if (workshopSharedModeActive()) {
    const snapshot = window.__workshopDataService.getLastSnapshot();
    const bookings = snapshot && Array.isArray(snapshot.bookings) ? snapshot.bookings : null;
    if (bookings) {
      return bookings
        .map(workshopMapSnapshotBookingToLegacyRow)
        .filter(row => row && row.id && row.vehicleKey && WORKSHOP_STAGE_SEQUENCE.includes(row.stage))
        .map(row => row.status === 'completed' ? row : { ...row, hours: workshopClampDurationHours(row.hours) });
    }
    // Shared mode is enabled but no snapshot has loaded yet (still
    // connecting / offline-read-only): fail closed to an empty list rather
    // than silently reading stale local writes, matching the fail-closed
    // requirement in the migration plan. The planner's own connection-state
    // banner (rendered separately) tells the user why nothing is editable.
    return [];
  }
  const rows = typeof loadJson === 'function' ? loadJson(WORKSHOP_PLAN_STORAGE_KEY, []) : [];
  return Array.isArray(rows) ? rows
    .filter(row => row && row.id && row.vehicleKey && WORKSHOP_STAGE_SEQUENCE.includes(row.stage))
    .map(row => row.status === 'completed' ? row : { ...row, hours: workshopClampDurationHours(row.hours) }) : [];
}

function workshopSavePlans(rows = []) {
  if (workshopSharedModeActive()) {
    // Write-path cutover is intentionally NOT enabled yet: today's legacy
    // rows carry no stable booking_id/version pairing with the RPC layer,
    // so routing writes through schedule_vehicle_work / move_workshop_booking
    // etc. here would either invent fake versions or silently no-op. That
    // requires the approved legacy migration/reconciliation import (see
    // scripts/workshop_planner_legacy_extract.js and section 16) to run
    // first so every row has a real booking_id. Until that import is
    // approved and executed, shared mode is fail-closed for writes: no
    // operation is silently accepted, and no localStorage write happens
    // either (which would create a second, contradicting source of truth).
    if (typeof window !== 'undefined' && typeof window.alert === 'function') {
      window.alert('Shared workshop mode is connected read-only. Live editing unlocks after the approved legacy data migration runs. No change was saved.');
    }
    return;
  }
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

// Single dispatch point every workshop action function checks first when
// shared mode is active. Routes to the exact protected transactional RPC
// via window.__workshopSharedActions (see workshop-shared-actions.js),
// waits for the confirmed database result, and NEVER leaves a rejected
// change displayed: renderWorkshopPlanner() always re-renders from the
// data service's own (already-refreshed-by-mutate()) authoritative
// snapshot afterwards, whether the action succeeded or was rejected.
//
// Returns:
//   null                     shared mode is not active; caller should fall
//                             through to its existing legacy-mode logic
//                             unchanged
//   { ok: true, ... }        action succeeded
//   { ok: false, error, ... } action rejected (stale version, conflict,
//                             permission, Parts gate, etc.) -- caller
//                             should show body.error to the user via
//                             workshopDescribeSharedActionError() and stop;
//                             it must NOT apply any further local mutation
// Section 8 Parts-incomplete override retry: move_workshop_booking,
// schedule_vehicle_work, and the atomic cascade scheduler all accept an
// inline p_override_reason -- when the database rejects with
// 'parts_incomplete', prompt once for a reason and resubmit the exact same
// payload with that reason attached. The database (not this function) is the
// final authority on whether the acting user's role is actually permitted to
// override; an unauthorised user's retry is rejected again by the RPC with a
// permission error, never silently applied client-side.
const WORKSHOP_OVERRIDE_CAPABLE_ACTIONS = new Set(['moveBooking', 'scheduleVehicleWork', 'cascadeSchedule']);

async function workshopDispatchSharedAction(actionName, payload) {
  if (!workshopSharedModeActive()) return null;
  const actions = window.__workshopSharedActions;
  if (!actions || typeof actions[actionName] !== 'function') {
    window.alert('Shared workshop mode is connected but this action is not yet available. No change was made.');
    return { ok: false, error: 'action_unavailable' };
  }
  let result = await actions[actionName](payload);
  if (result && result.ok !== true && result.error === 'parts_incomplete' && WORKSHOP_OVERRIDE_CAPABLE_ACTIONS.has(actionName) && !payload.overrideReason) {
    const reason = await workshopOverrideReasonModal();
    if (reason) {
      result = await actions[actionName]({ ...payload, overrideReason: reason });
    }
  }
  if (!result || result.ok !== true) {
    window.alert(workshopDescribeSharedActionError(result));
  }
  renderWorkshopPlanner();
  return result || { ok: false, error: 'no_response' };
}

// Human-readable, never-a-stack-trace error mapping per section 14 of the
// project brief. Falls back to a safe generic message for anything not
// explicitly mapped, so a raw Postgres/PostgREST error is never shown.
function workshopDescribeSharedActionError(result) {
  const error = result && result.error;
  const conflict = result && result.conflict;
  if (error === 'version_conflict') {
    return 'This booking was changed by another user. The planner has refreshed to the latest version.';
  }
  if (error === 'bay_overlap' || (conflict && conflict.conflict_type === 'bay_overlap')) {
    return 'That bay is already occupied during this time. The planner has refreshed to the latest version.';
  }
  if (error === 'technician_overlap' || (conflict && conflict.conflict_type === 'technician_overlap')) {
    return 'That technician is already assigned to another booking during this period.';
  }
  if (error === 'parts_incomplete' || error === 'parts_incomplete_blocked') {
    return 'Parts requirements are incomplete. An authorised override and reason are required.';
  }
  if (error === 'not_editable' || error === 'permission_denied' || error === 'forbidden') {
    return 'You do not have permission to make this change.';
  }
  if (error === 'missing_expected_version') {
    return 'This action was missing required version information and was not sent. Please try again.';
  }
  if (error === 'ambiguous_vehicle_identity' || error === 'conflicting_vehicle_identity') {
    return 'This vehicle reference matches more than one shared vehicle or conflicts with its saved UUID. No change was made; the identity requires review.';
  }
  if (error === 'vehicle_identity_not_found') {
    return 'This vehicle is not yet linked to one shared vehicle record. No change was made.';
  }
  if (error === 'booking_before_eta') {
    return `This YH/IT vehicle cannot be booked before its ETA to Kewdale. Earliest permitted booking date: ${result.earliest_permitted_date || 'correct the vehicle ETA'}. No booking was created.`;
  }
  if (error === 'missing_or_invalid_eta') {
    return 'YH/IT vehicles require a valid ETA to Kewdale before booking. Correct the ETA and try again. No booking was created.';
  }
  if (error === 'action_unavailable' || error === 'no_response') {
    return 'This action is not currently available in shared mode. No change was made.';
  }
  return 'This change could not be saved. The planner has refreshed to the latest version.';
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
  // Independent-review remediation (finding 2): in shared mode, the
  // Supabase-backed default_technician_id is the SOLE authority for a
  // bay's default technician -- no browser-local fallback is
  // consulted, even if the shared lookup returns empty (no default
  // set is a real, valid state, not "value unknown, ask localStorage
  // instead"). The legacy localStorage fallback below applies ONLY
  // when shared mode is inactive (no database to read from at all).
  if (workshopSharedModeActive()) {
    return workshopBayDefaultTechnicianName(stage, bay);
  }
  const sharedDefault = workshopBayDefaultTechnicianName(stage, bay);
  if (sharedDefault) return sharedDefault;
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
  return workshopEstimatedHours(vehicle, normalizedStage) || workshopDefaultBookingHours();
}

function workshopDetailSessionPreference() {
  if (typeof sessionStorage === 'undefined') return { pinned: false };
  try {
    const saved = JSON.parse(sessionStorage.getItem(WORKSHOP_DETAIL_SESSION_KEY) || '{}');
    return { pinned: saved?.pinned === true };
  } catch (_error) {
    return { pinned: false };
  }
}

function workshopSaveDetailSessionPreference(pinned = false) {
  if (typeof sessionStorage === 'undefined') return;
  try {
    sessionStorage.setItem(WORKSHOP_DETAIL_SESSION_KEY, JSON.stringify({ pinned: pinned === true }));
  } catch (_error) {
    // The panel remains usable if browser session storage is unavailable.
  }
}

function workshopLoadView() {
  const saved = typeof loadJson === 'function' ? loadJson(WORKSHOP_VIEW_STORAGE_KEY, {}) : {};
  const rawDate = workshopDateFromKey(saved?.date || '') || new Date();
  const date = workshopCoerceWorkDate(rawDate, 1);
  const detailPreference = workshopDetailSessionPreference();
  return {
    date: workshopDateKey(date),
    stage: WORKSHOP_STAGE_SEQUENCE.includes(saved?.stage) ? saved.stage : 'FABRICATION',
    selectedPlanId: '',
    search: '',
    searchOpen: false,
    searchHighlightPlanId: '',
    detailPinnedOpen: detailPreference.pinned,
    detailManualOpen: detailPreference.pinned,
    detailCollapsedForSelection: false,
  };
}

function workshopSaveView(state = {}) {
  if (typeof saveJson === 'function') saveJson(WORKSHOP_VIEW_STORAGE_KEY, { date: state.date, stage: state.stage });
}

function workshopState() {
  if (!app.workshopPlanner) app.workshopPlanner = workshopLoadView();
  return app.workshopPlanner;
}

function workshopClearSelectedDetail(state = workshopState()) {
  state.selectedPlanId = '';
  state.searchHighlightPlanId = '';
  state.searchNotice = '';
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = state.detailPinnedOpen === true;
}

function workshopSelectPlanForDetail(planId = '') {
  const state = workshopState();
  state.selectedPlanId = String(planId || '');
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = Boolean(state.selectedPlanId) || state.detailPinnedOpen === true;
  state.searchNotice = '';
}

function workshopVehicle(key = '') {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return null;
  const local = typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null;
  if (local || !workshopSharedModeActive()) return local;
  const snapshot = window.__workshopDataService?.getLastSnapshot?.();
  const vehicles = Array.isArray(snapshot?.vehicles) ? snapshot.vehicles : [];
  const matches = vehicles.filter(vehicle => [vehicle.id, vehicle.stock_number, vehicle.permanent_vehicle_id]
    .some(value => String(value || '').trim() === cleanKey));
  if (matches.length !== 1) return null;
  return workshopSnapshotVehicleToPlannerRow(
    matches[0],
    Array.isArray(snapshot?.work_items) ? snapshot.work_items : [],
    window.__activeWorkshopPlannerStage || '',
  );
}

// Looks up a vehicle's shared Supabase id + optimistic version from the
// last loaded snapshot (see migration 012's 'vehicles' array), keyed the
// same way workshopMapSnapshotBookingToLegacyRow resolves vehicle identity
// (stock_number first, then permanent_vehicle_id). Used only by actions
// that require a vehicle-scoped expected version (schedule_vehicle_work,
// approve_parts_incomplete_override) rather than a booking-scoped one.
// Returns null if shared mode is inactive or the vehicle isn't in the
// current snapshot window -- callers must treat that as "cannot proceed",
// never fabricate a version.
function workshopNormalizeStockIdentity(value = '') {
  const raw = String(value || '').trim().toUpperCase();
  const normalized = raw.replace(/[\s-]+/g, '');
  if (!normalized || ['0', 'TBA', 'TBD', 'UNKNOWN', 'NA', 'N/A', 'NONE', 'UNASSIGNED'].includes(normalized)) return '';
  if (/^(NEW|PD|PENDING|TEMP)-/.test(raw)) return '';
  return normalized;
}

function workshopNormalizeSourceIdentity(value = '') {
  return String(value || '').trim().toUpperCase();
}

const WORKSHOP_BROWSER_LINK_SOURCE_SYSTEM = 'browser_local_c4';
const WORKSHOP_BROWSER_LINKS_KEY = 'workshopCanonicalVehicleLinks:v1';
const WORKSHOP_BROWSER_EDITS_KEY = 'vehicleTrackingCoreNavisionOnlyEdits:v1';
const WORKSHOP_VEHICLE_LINK_OUTCOMES = new Set(['resolved', 'not_found', 'ambiguous', 'conflict', 'invalid_input', 'unauthorized', 'service_unavailable']);
const WORKSHOP_UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WORKSHOP_LINK_ALIAS_PATTERN = /^(?:source:[a-z0-9_-]+|toyota_order:[a-z0-9_-]+|permanent_vehicle_id|vin):[A-Z0-9][A-Z0-9:._/-]*$/;
const WORKSHOP_LINK_MATCH_FIELDS = new Set(['vehicle_id', 'stock_number', 'vin', 'job_card_number', 'permanent_vehicle_id', 'toyota_order_number', 'source_record_id']);
const WORKSHOP_LINK_ENTRY_FIELDS = new Set([
  'sharedVehicleId', 'sharedVehicleLinkSource', 'sharedVehicleLinkVehicleVersion',
  'sharedVehicleLinkResolverRevision', 'sharedVehicleLinkMatchedBy', 'sharedVehicleLinkVerifiedAt', 'aliases',
]);

function workshopVehicleLinkIdentityInput(vehicle = {}) {
  const unavailable = reason => {
    const result = {};
    Object.defineProperty(result, '__resolverBuilderMissing', { value: true, enumerable: false });
    Object.defineProperty(result, '__resolverBuilderFailure', { value: reason, enumerable: false });
    return result;
  };
  const sourceSystem = String(vehicle.sourceSystem || vehicle.source_system || WORKSHOP_BROWSER_LINK_SOURCE_SYSTEM).trim().toLowerCase();
  if (typeof buildVehicleLifecycleIdentityInput !== 'function') return unavailable('approved_identity_builder_missing');
  let built;
  try {
    built = buildVehicleLifecycleIdentityInput({ ...vehicle, sourceSystem });
  } catch (_) {
    return unavailable('approved_identity_builder_threw');
  }
  if (!built || typeof built !== 'object' || Array.isArray(built)) return unavailable('approved_identity_builder_invalid_result');
  const allowed = [
    'p_vehicle_id', 'p_stock_number', 'p_vin', 'p_job_card_number',
    'p_permanent_vehicle_id', 'p_toyota_order_number', 'p_source_system', 'p_source_record_id',
  ];
  if (allowed.some(key => built[key] != null && typeof built[key] !== 'string')) {
    return unavailable('approved_identity_builder_invalid_result');
  }
  const clean = Object.fromEntries(allowed
    .map(key => [key, String(built[key] == null ? '' : built[key]).trim()])
    .filter(([, value]) => value));
  if (built && built.__invalidIdentityField) {
    Object.defineProperty(clean, '__invalidIdentityField', {
      value: built.__invalidIdentityField,
      enumerable: false,
      configurable: false,
    });
  }
  return clean;
}

function workshopVehicleLinkStableAliases(vehicle = {}, input = null) {
  const identity = input || workshopVehicleLinkIdentityInput(vehicle);
  if (!identity || identity.__resolverBuilderMissing || identity.__invalidIdentityField) return [];
  const aliases = [];
  const add = (kind, value) => {
    const normalized = String(value || '').trim().toUpperCase();
    if (normalized) aliases.push(`${kind}:${normalized}`);
  };
  const sourceSystem = String(identity.p_source_system || '').trim().toLowerCase();
  if (sourceSystem && identity.p_source_record_id) add(`source:${sourceSystem}`, identity.p_source_record_id);
  add('permanent_vehicle_id', identity.p_permanent_vehicle_id);
  add('vin', identity.p_vin);
  if (sourceSystem && identity.p_toyota_order_number) add(`toyota_order:${sourceSystem}`, identity.p_toyota_order_number);
  return [...new Set(aliases)];
}

function workshopVehicleLinkStorage(storage = null) {
  if (storage) return storage;
  if (typeof window !== 'undefined' && window.localStorage) return window.localStorage;
  return null;
}

function workshopLoadVehicleLinkStore(storage = null) {
  const target = workshopVehicleLinkStorage(storage);
  if (!target) return { entries: {}, valid: true };
  try {
    const parsed = JSON.parse(target.getItem(WORKSHOP_BROWSER_LINKS_KEY) || '{"entries":{}}');
    if (!parsed || !parsed.entries || typeof parsed.entries !== 'object' || Array.isArray(parsed.entries)
        || Object.keys(parsed).length !== 1 || !Object.prototype.hasOwnProperty.call(parsed, 'entries')) {
      return { entries: {}, valid: false };
    }
    const entries = { ...parsed.entries };
    const valid = Object.entries(entries).every(([key, entry]) => {
      const aliases = Array.isArray(entry?.aliases) ? entry.aliases : [];
      const matchedBy = Array.isArray(entry?.sharedVehicleLinkMatchedBy) ? entry.sharedVehicleLinkMatchedBy : [];
      const verifiedAt = entry?.sharedVehicleLinkVerifiedAt;
      return String(key).trim()
        && entry && typeof entry === 'object' && !Array.isArray(entry)
        && Object.keys(entry).length === WORKSHOP_LINK_ENTRY_FIELDS.size
        && Object.keys(entry).every(field => WORKSHOP_LINK_ENTRY_FIELDS.has(field))
        && typeof entry.sharedVehicleId === 'string' && WORKSHOP_UUID_PATTERN.test(entry.sharedVehicleId)
        && typeof entry.sharedVehicleLinkSource === 'string' && /^[a-z0-9_-]{1,64}$/.test(entry.sharedVehicleLinkSource)
        && Number.isInteger(entry.sharedVehicleLinkVehicleVersion) && entry.sharedVehicleLinkVehicleVersion > 0
        && Number.isInteger(entry.sharedVehicleLinkResolverRevision) && entry.sharedVehicleLinkResolverRevision > 0
        && aliases.length > 0 && aliases.includes(key) && new Set(aliases).size === aliases.length
        && aliases.every(alias => typeof alias === 'string' && WORKSHOP_LINK_ALIAS_PATTERN.test(alias))
        && matchedBy.length > 0 && new Set(matchedBy).size === matchedBy.length
        && matchedBy.every(field => typeof field === 'string' && WORKSHOP_LINK_MATCH_FIELDS.has(field))
        && typeof verifiedAt === 'string' && !Number.isNaN(Date.parse(verifiedAt))
        && new Date(verifiedAt).toISOString() === verifiedAt;
    });
    return valid ? { entries, valid: true } : { entries: {}, valid: false };
  } catch (_) {
    return { entries: {}, valid: false };
  }
}

function workshopLookupStoredVehicleLink(vehicle = {}, storage = null) {
  const input = workshopVehicleLinkIdentityInput(vehicle);
  const aliases = workshopVehicleLinkStableAliases(vehicle, input);
  if (!aliases.length) return { outcome: 'not_found', entry: null, aliases };
  const aliasSet = new Set(aliases);
  const store = workshopLoadVehicleLinkStore(storage);
  if (!store.valid) return { outcome: 'service_unavailable', entry: null, aliases };
  const rawMatches = Object.values(store.entries)
    .filter(entry => entry && Array.isArray(entry.aliases) && entry.aliases.some(alias => aliasSet.has(alias)));
  if (rawMatches.some(entry => !WORKSHOP_UUID_PATTERN.test(String(entry.sharedVehicleId || '').trim()))) {
    return { outcome: 'service_unavailable', entry: null, aliases };
  }
  const matches = rawMatches;
  const uuids = [...new Set(matches.map(entry => String(entry.sharedVehicleId).trim().toLowerCase()))];
  if (uuids.length > 1) return { outcome: 'conflict', entry: null, aliases };
  if (!matches.length) return { outcome: 'not_found', entry: null, aliases };
  return { outcome: 'resolved', entry: matches[0], aliases };
}

function workshopSaveStoredVehicleLink(vehicle = {}, updates = {}, storage = null) {
  const target = workshopVehicleLinkStorage(storage);
  if (!target) return false;
  const aliases = workshopVehicleLinkStableAliases(vehicle);
  if (!aliases.length
      || aliases.some(alias => !WORKSHOP_LINK_ALIAS_PATTERN.test(alias))
      || typeof updates.sharedVehicleId !== 'string' || !WORKSHOP_UUID_PATTERN.test(updates.sharedVehicleId)
      || typeof updates.sharedVehicleLinkSource !== 'string' || !/^[a-z0-9_-]{1,64}$/.test(updates.sharedVehicleLinkSource)
      || !Number.isInteger(updates.sharedVehicleLinkVehicleVersion) || updates.sharedVehicleLinkVehicleVersion < 1
      || !Number.isInteger(updates.sharedVehicleLinkResolverRevision) || updates.sharedVehicleLinkResolverRevision < 1
      || !Array.isArray(updates.sharedVehicleLinkMatchedBy) || !updates.sharedVehicleLinkMatchedBy.length
      || new Set(updates.sharedVehicleLinkMatchedBy).size !== updates.sharedVehicleLinkMatchedBy.length
      || updates.sharedVehicleLinkMatchedBy.some(field => typeof field !== 'string' || !WORKSHOP_LINK_MATCH_FIELDS.has(field))
      || typeof updates.sharedVehicleLinkVerifiedAt !== 'string'
      || Number.isNaN(Date.parse(updates.sharedVehicleLinkVerifiedAt))
      || new Date(updates.sharedVehicleLinkVerifiedAt).toISOString() !== updates.sharedVehicleLinkVerifiedAt) return false;
  const store = workshopLoadVehicleLinkStore(target);
  if (!store.valid) return false;
  const aliasSet = new Set(aliases);
  const matchingKeys = Object.entries(store.entries)
    .filter(([, entry]) => entry && Array.isArray(entry.aliases) && entry.aliases.some(alias => aliasSet.has(alias)))
    .map(([key]) => key);
  const existingUuids = [...new Set(matchingKeys
    .map(key => String(store.entries[key]?.sharedVehicleId || '').trim().toLowerCase())
    .filter(Boolean))];
  const nextUuid = String(updates.sharedVehicleId).trim().toLowerCase();
  if (existingUuids.some(uuid => uuid !== nextUuid)) return false;
  const entryKey = matchingKeys[0] || aliases[0];
  matchingKeys.slice(1).forEach(key => { delete store.entries[key]; });
  store.entries[entryKey] = { ...(store.entries[entryKey] || {}), ...updates, aliases };
  try {
    target.setItem(WORKSHOP_BROWSER_LINKS_KEY, JSON.stringify({ entries: store.entries }));
    return true;
  } catch (_) {
    return false;
  }
}

function workshopVehicleLinkProbeInputs(vehicle = {}, combinedInput = null) {
  const input = combinedInput || workshopVehicleLinkIdentityInput(vehicle);
  const probes = [];
  const add = (identifier, value, sourceVehicle) => {
    if (!String(value || '').trim()) return;
    const probeInput = workshopVehicleLinkIdentityInput(sourceVehicle);
    if (probeInput.__resolverBuilderMissing || probeInput.__invalidIdentityField || !Object.keys(probeInput).length) {
      probes.push({
        identifier,
        value: String(value).trim(),
        input: null,
        builderFailure: probeInput.__resolverBuilderFailure || probeInput.__invalidIdentityField || 'approved_identity_builder_empty_probe',
      });
      return;
    }
    probes.push({ identifier, value: String(value).trim(), input: probeInput });
  };
  add('vehicle_id', input.p_vehicle_id, { sharedVehicleId: input.p_vehicle_id });
  add('stock_number', input.p_stock_number, { stock: input.p_stock_number });
  add('vin', input.p_vin, { vin: input.p_vin });
  add('job_card_number', input.p_job_card_number, { jobCardNumber: input.p_job_card_number, sourceSystem: input.p_source_system });
  add('permanent_vehicle_id', input.p_permanent_vehicle_id, { permanentVehicleId: input.p_permanent_vehicle_id });
  add('toyota_order_number', input.p_toyota_order_number, { toyotaOrderNumber: input.p_toyota_order_number, sourceSystem: input.p_source_system });
  add('source_record_id', input.p_source_record_id, { sourceSystem: input.p_source_system, sourceRecordId: input.p_source_record_id });
  return probes;
}

function workshopVehicleLinkRemediation(outcome = '', hasSavedLink = false) {
  const messages = {
    not_found: 'Create or import exactly one canonical shared vehicle through the approved Stage 2B importer, then run link verification again.',
    ambiguous: 'Manual identity review is required: resolve duplicate normalized candidates without selecting by row order, then retry.',
    conflict: 'Manual identity review is required: correct the conflicting saved UUID or identifier evidence, then retry.',
    invalid_input: 'Correct the reported browser-local identity field, then run deterministic link verification again.',
    unstable_identity: 'Add one stable browser-local identifier (source record, permanent vehicle ID, VIN, or Toyota order number) before linking; stock number alone is not a durable edit key.',
    unauthorized: 'Use an approved staging account with resolver access; no link was saved.',
    archived: 'The canonical shared vehicle is archived. An approved administrator must restore or replace it through controlled vehicle-master review before linking.',
    service_unavailable: 'Restore the approved identity resolver service and retry; no fallback or guessed link is permitted.',
  };
  if (outcome === 'resolved') {
    return hasSavedLink
      ? 'No remediation required. The saved browser-local UUID link was re-verified against the canonical shared record.'
      : 'Save the verified canonical UUID into the browser-local edits overlay, then retry scheduling.';
  }
  return messages[outcome] || 'Manual identity review is required before scheduling.';
}

function workshopVehicleLinkResultSummary(result = null) {
  if (!result || typeof result !== 'object' || Array.isArray(result)) {
    return { outcome: 'service_unavailable', sharedUuid: null, version: null, resolverRevision: null, isArchived: null, candidateCount: null, reason: 'invalid_resolver_result', field: null, matchedBy: [] };
  }
  const reportedOutcome = String(result.outcome || '').trim();
  if (!WORKSHOP_VEHICLE_LINK_OUTCOMES.has(reportedOutcome)) {
    return { outcome: 'service_unavailable', sharedUuid: null, version: null, resolverRevision: null, isArchived: null, candidateCount: null, reason: 'invalid_resolver_outcome', field: null, matchedBy: [] };
  }
  const sharedUuid = result.vehicleId;
  const version = result.version;
  const resolverRevision = result.resolverRevision;
  if (reportedOutcome === 'resolved' && (
    typeof sharedUuid !== 'string' || !WORKSHOP_UUID_PATTERN.test(sharedUuid)
    || !Number.isInteger(version) || version < 1
    || !Number.isInteger(resolverRevision) || resolverRevision < 1
    || typeof result.isArchived !== 'boolean'
    || !Array.isArray(result.matchedBy) || !result.matchedBy.length
    || new Set(result.matchedBy).size !== result.matchedBy.length
    || result.matchedBy.some(field => typeof field !== 'string' || !WORKSHOP_LINK_MATCH_FIELDS.has(field))
  )) {
    return { outcome: 'service_unavailable', sharedUuid: null, version: null, resolverRevision: null, isArchived: null, candidateCount: null, reason: 'invalid_resolved_contract', field: null, matchedBy: [] };
  }
  return {
    outcome: reportedOutcome,
    sharedUuid: reportedOutcome === 'resolved' ? sharedUuid : null,
    version: reportedOutcome === 'resolved' ? version : null,
    resolverRevision: reportedOutcome === 'resolved' ? resolverRevision : null,
    isArchived: reportedOutcome === 'resolved' ? result.isArchived : null,
    candidateCount: Number.isInteger(result.candidateCount) && result.candidateCount >= 0 ? result.candidateCount : null,
    reason: typeof result.reason === 'string' ? result.reason : null,
    field: typeof result.field === 'string' ? result.field : null,
    matchedBy: Array.isArray(result.matchedBy) ? result.matchedBy.filter(value => typeof value === 'string') : [],
  };
}

async function workshopResolveVehicleLinkDiagnostic(vehicle = {}, resolver = null, storage = null) {
  const identityResolver = resolver || (typeof window !== 'undefined' ? window.__vehicleLifecycleIdentityResolver : null);
  const explicitSavedUuid = String(vehicle.sharedVehicleId || vehicle.shared_vehicle_id || vehicle.canonicalVehicleId || '').trim() || null;
  const storedLink = workshopLookupStoredVehicleLink(vehicle, storage);
  const storedUuid = storedLink.outcome === 'resolved' ? String(storedLink.entry.sharedVehicleId || '').trim() : null;
  const hydratedVehicle = storedUuid && !explicitSavedUuid ? { ...vehicle, sharedVehicleId: storedUuid } : vehicle;
  const input = workshopVehicleLinkIdentityInput(hydratedVehicle);
  const savedUuid = String(input.p_vehicle_id || explicitSavedUuid || storedUuid || '').trim() || null;
  const browserLocalIdentity = {
    vehicleKey: typeof vehicleKey === 'function'
      ? vehicleKey(vehicle)
      : String(vehicle.stock || vehicle.order || vehicle.id || '').trim(),
    stockNumber: input.p_stock_number || null,
    vin: input.p_vin || null,
    jobCardNumber: input.p_job_card_number || null,
    permanentVehicleId: input.p_permanent_vehicle_id || null,
    toyotaOrderNumber: input.p_toyota_order_number || null,
    sourceSystem: input.p_source_system || null,
    sourceRecordId: input.p_source_record_id || null,
    savedSharedUuid: savedUuid,
  };
  const reject = (outcome, reason, candidateProcess = []) => ({
    browserLocalIdentity,
    sharedUuid: null,
    savedSharedUuid: savedUuid,
    outcome,
    linkState: 'rejected',
    version: null,
    resolverRevision: null,
    matchedBy: [],
    candidateCount: candidateProcess.reduce((max, item) => Number.isInteger(item?.candidateCount) ? Math.max(max, item.candidateCount) : max, 0) || null,
    candidateProcess,
    rejectedReason: [outcome, reason].filter(Boolean).join(':'),
    exactRemediation: workshopVehicleLinkRemediation(outcome, false),
  });
  if (input.__resolverBuilderMissing) return reject('service_unavailable', input.__resolverBuilderFailure || 'approved_identity_builder_missing');
  if (input.__invalidIdentityField) return reject('invalid_input', input.__invalidIdentityField);
  if (storedLink.outcome === 'service_unavailable') return reject('service_unavailable', 'browser_local_link_store_invalid');
  if (!workshopVehicleLinkStableAliases(vehicle, input).length) return reject('unstable_identity', 'stable_browser_identity_missing');
  if (storedLink.outcome === 'conflict') return reject('conflict', 'browser_local_link_store_conflict');
  if (explicitSavedUuid && storedUuid && explicitSavedUuid.toLowerCase() !== storedUuid.toLowerCase()) {
    return reject('conflict', 'browser_local_saved_uuid_mismatch');
  }
  if (!identityResolver || typeof identityResolver.resolve !== 'function') return reject('service_unavailable', 'resolver_missing');
  const probes = workshopVehicleLinkProbeInputs(hydratedVehicle, input);
  const candidateProcess = [];
  for (const probe of probes) {
    let summary;
    if (!probe.input) {
      summary = {
        outcome: 'service_unavailable', sharedUuid: null, version: null, resolverRevision: null,
        isArchived: null, candidateCount: null, reason: probe.builderFailure || 'approved_identity_builder_probe_failed', field: null, matchedBy: [],
      };
    } else {
      try {
        summary = workshopVehicleLinkResultSummary(await identityResolver.resolve(probe.input, { reason: 'workshop_vehicle_link_probe', track: false }));
      } catch (_) {
        summary = workshopVehicleLinkResultSummary(null);
      }
    }
    candidateProcess.push({ identifier: probe.identifier, value: probe.value, ...summary });
  }
  let summary;
  try {
    summary = workshopVehicleLinkResultSummary(await identityResolver.resolve(input, { reason: 'workshop_vehicle_link_combined', track: true }));
  } catch (_) {
    summary = workshopVehicleLinkResultSummary(null);
  }
  const probeOutcome = candidateProcess.map(item => item.isArchived ? 'archived' : item.outcome);
  const priority = ['service_unavailable', 'unauthorized', 'archived', 'ambiguous', 'conflict', 'invalid_input'];
  const blockingProbeOutcome = priority.find(outcome => probeOutcome.includes(outcome));
  if (blockingProbeOutcome) {
    const item = candidateProcess.find(candidate => (candidate.isArchived ? 'archived' : candidate.outcome) === blockingProbeOutcome);
    return reject(blockingProbeOutcome, item?.reason || item?.field || `resolver_probe_${blockingProbeOutcome}`, candidateProcess);
  }
  const resolvedProbeUuids = candidateProcess
    .filter(item => item.outcome === 'resolved')
    .map(item => String(item.sharedUuid || '').toLowerCase());
  const hasMissingProbe = probeOutcome.includes('not_found');
  if (hasMissingProbe && resolvedProbeUuids.length) {
    return reject('conflict', 'identifier_candidates_do_not_all_resolve', candidateProcess);
  }
  if (summary.outcome === 'service_unavailable') {
    return reject('service_unavailable', summary.reason || 'resolver_combined_failed', candidateProcess);
  }
  if (summary.outcome === 'resolved' && summary.isArchived) {
    return reject('archived', 'canonical_vehicle_archived', candidateProcess);
  }
  if (summary.outcome !== 'resolved') {
    if (resolvedProbeUuids.length) return reject('conflict', 'combined_result_disagrees_with_identifier_candidates', candidateProcess);
    return reject(summary.outcome, summary.reason || summary.field, candidateProcess);
  }
  const resolvedUuid = summary.sharedUuid;
  if (hasMissingProbe || resolvedProbeUuids.some(uuid => uuid !== String(resolvedUuid).toLowerCase())) {
    return reject('conflict', 'identifier_candidates_do_not_converge', candidateProcess);
  }
  const savedLinkMatches = !!(savedUuid && resolvedUuid && savedUuid.toLowerCase() === resolvedUuid.toLowerCase());
  let outcome = summary.outcome;
  let rejectedReason = outcome === 'resolved' ? null : [outcome, summary.reason || summary.field].filter(Boolean).join(':');
  if (outcome === 'resolved' && summary.isArchived) {
    outcome = 'archived';
    rejectedReason = 'archived:canonical_vehicle_archived';
  } else if (outcome === 'resolved' && savedUuid && !savedLinkMatches) {
    outcome = 'conflict';
    rejectedReason = 'conflict:saved_uuid_mismatch';
  }
  const linkState = outcome !== 'resolved' ? 'rejected' : savedLinkMatches ? 'verified' : 'ready_to_save';
  return {
    browserLocalIdentity,
    sharedUuid: outcome === 'resolved' ? resolvedUuid : null,
    savedSharedUuid: savedUuid,
    outcome,
    linkState,
    version: outcome === 'resolved' ? summary.version : null,
    resolverRevision: outcome === 'resolved' ? summary.resolverRevision : null,
    matchedBy: outcome === 'resolved' ? [...summary.matchedBy] : [],
    candidateCount: summary.candidateCount,
    candidateProcess,
    rejectedReason,
    exactRemediation: workshopVehicleLinkRemediation(outcome, savedLinkMatches),
  };
}

function workshopVehicleLinkCanPersist() {
  if (typeof window === 'undefined') return true;
  const role = String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
  return role === 'operator' || role === 'administrator';
}

function workshopPersistVerifiedCanonicalLink(vehicle = {}, diagnostic = {}, saveFn = null, storage = null, receiptOut = null) {
  if (!workshopVehicleLinkCanPersist()) return false;
  if (!vehicle || diagnostic.outcome !== 'resolved' || diagnostic.linkState !== 'ready_to_save'
      || typeof diagnostic.sharedUuid !== 'string' || !WORKSHOP_UUID_PATTERN.test(diagnostic.sharedUuid)
      || !Number.isInteger(diagnostic.version) || diagnostic.version < 1
      || !Number.isInteger(diagnostic.resolverRevision) || diagnostic.resolverRevision < 1
      || !Array.isArray(diagnostic.matchedBy) || !diagnostic.matchedBy.length
      || new Set(diagnostic.matchedBy).size !== diagnostic.matchedBy.length
      || diagnostic.matchedBy.some(field => typeof field !== 'string' || !WORKSHOP_LINK_MATCH_FIELDS.has(field))) return false;
  const persist = saveFn || (typeof saveVehicleEdits === 'function' ? saveVehicleEdits : null);
  const target = workshopVehicleLinkStorage(storage);
  if (typeof persist !== 'function' || !target) return false;
  const key = typeof vehicleKey === 'function'
    ? vehicleKey(vehicle)
    : String(vehicle.stock || vehicle.order || vehicle.id || '').trim();
  if (!key) return false;
  const updates = {
    sharedVehicleId: diagnostic.sharedUuid,
    sharedVehicleLinkSource: diagnostic.browserLocalIdentity?.sourceSystem || WORKSHOP_BROWSER_LINK_SOURCE_SYSTEM,
    sharedVehicleLinkVehicleVersion: diagnostic.version,
    sharedVehicleLinkResolverRevision: diagnostic.resolverRevision,
    sharedVehicleLinkMatchedBy: [...(diagnostic.matchedBy || [])],
    sharedVehicleLinkVerifiedAt: typeof nowIsoString === 'function' ? nowIsoString() : new Date().toISOString(),
  };
  const previousVehicleValues = Object.fromEntries(Object.keys(updates).map(field => [field, {
    exists: Object.prototype.hasOwnProperty.call(vehicle, field),
    value: vehicle[field],
  }]));
  let previousStore;
  let previousEdits;
  try {
    previousStore = target.getItem(WORKSHOP_BROWSER_LINKS_KEY);
    previousEdits = target.getItem(WORKSHOP_BROWSER_EDITS_KEY);
  } catch (_) {
    return false;
  }
  if (!workshopSaveStoredVehicleLink(vehicle, updates, target)) return false;
  try {
    if (persist(key, updates, { render: false }) === true) {
      if (receiptOut && typeof receiptOut === 'object') {
        Object.assign(receiptOut, {
          storage: target,
          vehicle,
          previousStore,
          persistedStore: target.getItem(WORKSHOP_BROWSER_LINKS_KEY),
          previousEdits,
          persistedEdits: target.getItem(WORKSHOP_BROWSER_EDITS_KEY),
          previousVehicleValues,
          updates,
        });
      }
      return true;
    }
  } catch (_) {
    // Roll back the stable link overlay below.
  }
  try {
    if (previousStore == null) target.removeItem(WORKSHOP_BROWSER_LINKS_KEY);
    else target.setItem(WORKSHOP_BROWSER_LINKS_KEY, previousStore);
    if (previousEdits == null) target.removeItem(WORKSHOP_BROWSER_EDITS_KEY);
    else target.setItem(WORKSHOP_BROWSER_EDITS_KEY, previousEdits);
  } catch (_) {
    // Persistence still reports failure and scheduling remains blocked.
  }
  Object.entries(previousVehicleValues).forEach(([field, previous]) => {
    if (!workshopVehicleLinkValuesEqual(vehicle[field], updates[field])) return;
    if (previous.exists) vehicle[field] = previous.value;
    else delete vehicle[field];
  });
  return false;
}

function workshopVehicleLinkValuesEqual(left, right) {
  if (Array.isArray(left) || Array.isArray(right)) return JSON.stringify(left) === JSON.stringify(right);
  return left === right;
}

function workshopRollbackPersistedCanonicalLink(receipt = {}) {
  const target = receipt.storage;
  const vehicle = receipt.vehicle;
  if (!target || !vehicle || !receipt.updates || !receipt.previousVehicleValues) return false;
  let currentStore;
  let currentEdits;
  try {
    currentStore = target.getItem(WORKSHOP_BROWSER_LINKS_KEY);
    currentEdits = target.getItem(WORKSHOP_BROWSER_EDITS_KEY);
  } catch (_) {
    return false;
  }
  // Preflight both layers before touching either. A concurrent change leaves the
  // saved state intact for manual review rather than creating split authority.
  if (currentStore !== receipt.persistedStore || currentEdits !== receipt.persistedEdits) return false;
  try {
    if (receipt.previousStore == null) target.removeItem(WORKSHOP_BROWSER_LINKS_KEY);
    else target.setItem(WORKSHOP_BROWSER_LINKS_KEY, receipt.previousStore);
    if (receipt.previousEdits == null) target.removeItem(WORKSHOP_BROWSER_EDITS_KEY);
    else target.setItem(WORKSHOP_BROWSER_EDITS_KEY, receipt.previousEdits);
  } catch (_) {
    // Best-effort roll-forward keeps both persistence layers on the same saved
    // state if restoring the prior pair cannot complete.
    try {
      if (receipt.persistedStore == null) target.removeItem(WORKSHOP_BROWSER_LINKS_KEY);
      else target.setItem(WORKSHOP_BROWSER_LINKS_KEY, receipt.persistedStore);
      if (receipt.persistedEdits == null) target.removeItem(WORKSHOP_BROWSER_EDITS_KEY);
      else target.setItem(WORKSHOP_BROWSER_EDITS_KEY, receipt.persistedEdits);
    } catch (_) {
      // The caller still fails closed and requires manual browser-storage review.
    }
    return false;
  }
  try {
    if (target.getItem(WORKSHOP_BROWSER_LINKS_KEY) !== receipt.previousStore
        || target.getItem(WORKSHOP_BROWSER_EDITS_KEY) !== receipt.previousEdits) return false;
  } catch (_) {
    return false;
  }
  let restored = true;
  Object.entries(receipt.previousVehicleValues).forEach(([field, previous]) => {
    if (!workshopVehicleLinkValuesEqual(vehicle[field], receipt.updates[field])) {
      restored = false;
      return;
    }
    if (previous.exists) vehicle[field] = previous.value;
    else delete vehicle[field];
  });
  return restored;
}

function workshopVehicleLinkVisibleReason(diagnostic = {}) {
  const outcome = String(diagnostic.outcome || '').trim().toLowerCase();
  const reason = String(diagnostic.rejectedReason || '').trim().toLowerCase();
  const reasonTokens = reason.split(/[^a-z0-9_]+/).filter(Boolean);
  const staleResolverReasons = new Set(['stale', 'superseded', 'resolver_stopped']);
  if (outcome === 'stale' || reasonTokens.some(token => staleResolverReasons.has(token))) {
    return 'Stale — the saved vehicle identity or resolver result changed and must be verified again.';
  }
  const messages = {
    not_found: 'Not found — no canonical shared vehicle matched the approved browser-local identity.',
    invalid_input: 'Invalid input — a browser-local identity field must be corrected before linking.',
    ambiguous: 'Ambiguous — more than one canonical vehicle candidate matched; no candidate was selected.',
    conflict: 'Conflict — the saved UUID or identity evidence points to different canonical vehicles.',
    archived: 'Archived — the canonical shared vehicle is archived and cannot be linked for scheduling.',
    service_unavailable: 'Resolver unavailable — deterministic identity verification could not be completed.',
    unauthorized: 'Not authorized — this account cannot resolve or save a shared vehicle link.',
    unstable_identity: 'Not linked — the browser-local vehicle does not have a stable identity suitable for linking.',
  };
  if (messages[outcome]) return messages[outcome];
  if (!diagnostic.sharedUuid) return 'Not linked — no verified canonical shared vehicle UUID is available.';
  return 'No refusal — the canonical shared vehicle UUID was resolved.';
}

function workshopVehicleLinkDisplayRows(diagnostic = {}, options = {}) {
  const identity = diagnostic.browserLocalIdentity || {};
  const sanitize = options.sanitize === true;
  const shown = value => sanitize && value ? 'Restricted' : value;
  const optionalRows = [
    ['Browser-local key', shown(identity.vehicleKey)],
    ['Stock number', shown(identity.stockNumber)],
    ['VIN', shown(identity.vin)],
    ['Job card', shown(identity.jobCardNumber)],
    ['Toyota order', shown(identity.toyotaOrderNumber)],
    ['Permanent vehicle ID', shown(identity.permanentVehicleId)],
    ['Source system', shown(identity.sourceSystem)],
    ['Source record ID', shown(identity.sourceRecordId)],
  ].filter(([, value]) => value);
  const sharedUuid = diagnostic.sharedUuid ? shown(diagnostic.sharedUuid) : 'Missing';
  const rows = [
    ...optionalRows,
    ['Shared vehicle UUID', sharedUuid],
  ];
  if (!diagnostic.sharedUuid) rows.push(['Refusal reason', workshopVehicleLinkVisibleReason(diagnostic)]);
  rows.push(
    ['Saved shared UUID', identity.savedSharedUuid ? shown(identity.savedSharedUuid) : 'Not saved'],
    ['Resolved shared UUID', diagnostic.sharedUuid ? shown(diagnostic.sharedUuid) : 'Missing'],
  );
  return rows;
}

let workshopVehicleLinkModalSequence = 0;

function workshopVehicleLinkDiagnosticModal(diagnostic = {}, options = {}) {
  return new Promise(resolve => {
    const headingId = `workshop-vehicle-link-title-${++workshopVehicleLinkModalSequence}`;
    const previousFocus = document.activeElement;
    const viewerSanitized = typeof window !== 'undefined'
      && String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'viewer';
    const candidateRows = (diagnostic.candidateProcess || []).map(item => {
      const detail = item.sharedUuid
        ? (viewerSanitized ? 'Restricted' : item.sharedUuid)
        : (item.outcome ? workshopVehicleLinkVisibleReason({ outcome: item.isArchived ? 'archived' : item.outcome, rejectedReason: item.reason || item.field }) : 'No candidate');
      return `<tr>
      <td>${escapeHtml(item.identifier || '')}</td>
      <td><code>${escapeHtml(viewerSanitized && item.value ? 'Restricted' : item.value || '')}</code></td>
      <td>${escapeHtml(item.outcome || 'unknown')}</td>
      <td>${escapeHtml(detail)}</td>
    </tr>`;
    }).join('');
    const identityRows = workshopVehicleLinkDisplayRows(diagnostic, { sanitize: viewerSanitized })
      .map(([label, value]) => `<div><span>${escapeHtml(label)}</span><code>${escapeHtml(value)}</code></div>`).join('');
    const visibleReason = workshopVehicleLinkVisibleReason(diagnostic);
    const canSave = diagnostic.linkState === 'ready_to_save' && !!diagnostic.sharedUuid && workshopVehicleLinkCanPersist();
    const roleNote = diagnostic.linkState === 'ready_to_save' && !workshopVehicleLinkCanPersist()
      ? '<p class="workshop-inline-note">An operator or administrator must save the verified browser-local link.</p>'
      : '';
    const safetyRefusal = diagnostic.linkState === 'verified'
      ? ''
      : '<p class="workshop-inline-note">This vehicle is not yet linked to one shared vehicle record. No change was made.</p>';
    const statusCopy = diagnostic.linkState === 'verified'
      ? 'The canonical shared UUID is saved and re-verified. Browser-local authority remains unchanged.'
      : 'Workshop scheduling remains blocked until one canonical shared UUID is deterministically resolved and saved in the browser-local link overlay. Browser-local authority remains unchanged.';
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay workshop-vehicle-link-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-labelledby', headingId);
    overlay.innerHTML = `<section class="modal-card workshop-vehicle-link-card">
      <button class="modal-close" type="button" data-workshop-link-close aria-label="Close">×</button>
      <header><h2 id="${headingId}">${escapeHtml(options.title || (canSave ? 'Verify shared vehicle link' : diagnostic.linkState === 'verified' ? 'Shared vehicle link verified' : 'Shared vehicle link required'))}</h2>
        <p>${escapeHtml(statusCopy)}</p>${safetyRefusal}</header>
      <section class="workshop-link-identity"><h3>Browser-local identity</h3>${identityRows || '<p>No usable identity fields were supplied.</p>'}</section>
      <section><h3>Candidate matching process</h3><div class="responsive-table"><table class="data-table workshop-link-candidates"><thead><tr><th scope="col">Identifier</th><th scope="col">Normalized input</th><th scope="col">Outcome</th><th scope="col">Candidate / reason</th></tr></thead><tbody>${candidateRows || '<tr><td colspan="4">The approved resolver was unavailable; no fallback match was attempted.</td></tr>'}</tbody></table></div></section>
      <section class="workshop-link-decision"><div><span>Decision</span><strong>${escapeHtml(diagnostic.linkState || 'rejected')}</strong></div><div><span>Refusal reason</span><strong>${escapeHtml(diagnostic.linkState === 'verified' ? 'Not refused' : visibleReason)}</strong></div><div><span>Exact remediation</span><strong>${escapeHtml(diagnostic.exactRemediation || 'Manual review required.')}</strong></div></section>
      ${roleNote}
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-link-close>Close without change</button>${canSave ? '<button class="primary" type="button" data-workshop-link-save>Save verified UUID link</button>' : ''}</div>
    </section>`;
    let finished = false;
    const finish = value => {
      if (finished) return;
      finished = true;
      document.removeEventListener('keydown', onKeyDown);
      overlay.remove();
      if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
      if (previousFocus && previousFocus.isConnected && typeof previousFocus.focus === 'function') previousFocus.focus();
      resolve(value);
    };
    const onKeyDown = event => {
      if (event.key === 'Escape') {
        event.preventDefault();
        finish('close');
        return;
      }
      if (event.key !== 'Tab') return;
      const focusable = [...overlay.querySelectorAll('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')];
      if (!focusable.length) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    overlay.querySelectorAll('[data-workshop-link-close]').forEach(button => button.addEventListener('click', () => finish('close')));
    overlay.querySelector('[data-workshop-link-save]')?.addEventListener('click', () => finish('save'));
    overlay.addEventListener('click', event => { if (event.target === overlay) finish('close'); });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    document.addEventListener('keydown', onKeyDown);
    overlay.querySelector('[data-workshop-link-save], [data-workshop-link-close]')?.focus();
  });
}

async function workshopVerifiedCanonicalVehicleRef(vehicle = {}, options = {}) {
  const authoritativeRef = workshopSharedVehicleRef(vehicle);
  const authoritativeVersion = Number(authoritativeRef?.version);
  if (authoritativeRef && !authoritativeRef.error && authoritativeRef.vehicleId && Number.isInteger(authoritativeVersion)) {
    return { ok: true, vehicleId: authoritativeRef.vehicleId, version: authoritativeVersion, source: 'scoped_snapshot' };
  }
  if (authoritativeRef?.error && vehicle.sharedVehicleId) {
    return { ok: false, error: authoritativeRef.error, diagnostic: authoritativeRef };
  }
  const resolveDiagnostic = () => workshopResolveVehicleLinkDiagnostic(vehicle, options.resolver || null, options.storage || null);
  const openDiagnostic = options.modalFn || workshopVehicleLinkDiagnosticModal;
  const persistLink = options.persistFn || ((targetVehicle, diagnostic, receipt) => workshopPersistVerifiedCanonicalLink(
    targetVehicle, diagnostic, options.saveFn || null, options.storage || null, receipt,
  ));
  const diagnostic = await resolveDiagnostic();
  if (diagnostic.linkState === 'verified' && diagnostic.sharedUuid) {
    return { ok: true, vehicleId: diagnostic.sharedUuid, version: diagnostic.version, diagnostic };
  }
  const decision = await openDiagnostic(diagnostic);
  if (decision !== 'save' || diagnostic.linkState !== 'ready_to_save') return { ok: false, error: 'vehicle_identity_not_found', diagnostic };
  const receipt = {};
  if (!persistLink(vehicle, diagnostic, receipt)) {
    const failed = { ...diagnostic, outcome: 'service_unavailable', linkState: 'rejected', rejectedReason: 'browser_local_link_persist_failed', exactRemediation: 'Resolve browser-local storage persistence, then run deterministic link verification again.' };
    await openDiagnostic(failed, { title: 'Shared vehicle link was not saved' });
    return { ok: false, error: 'vehicle_link_persist_failed', diagnostic: failed };
  }
  const verified = await resolveDiagnostic();
  if (verified.linkState !== 'verified' || verified.sharedUuid !== diagnostic.sharedUuid) {
    const rolledBack = workshopRollbackPersistedCanonicalLink(receipt);
    const failed = {
      ...verified,
      linkState: 'rejected',
      rejectedReason: `${verified.rejectedReason || 'post_save_verification_failed'}:${rolledBack ? 'new_link_rolled_back' : 'rollback_conflict'}`,
      exactRemediation: rolledBack
        ? 'The newly saved browser-local link was rolled back. Resolve the reported identity condition, then run deterministic link verification again.'
        : 'Browser-local link rollback could not safely overwrite a concurrent change. Reload and complete manual identity review before scheduling.',
    };
    await openDiagnostic(failed, { title: rolledBack ? 'Shared vehicle link was rolled back' : 'Shared vehicle link rollback needs review' });
    return { ok: false, error: rolledBack ? 'conflicting_vehicle_identity_rolled_back' : 'vehicle_link_rollback_conflict', diagnostic: failed };
  }
  await openDiagnostic(verified, { title: 'Shared UUID link saved and verified' });
  return { ok: false, error: 'vehicle_link_saved_retry', diagnostic: verified };
}

function workshopVehicleLinkReadinessStatus(diagnostic = {}) {
  if (diagnostic.linkState === 'verified') return 'linked';
  if (diagnostic.linkState === 'ready_to_save') return 'resolvable_unsaved';
  return {
    not_found: 'missing_canonical_vehicle',
    ambiguous: 'ambiguous',
    conflict: 'conflicting',
    invalid_input: 'invalid_identity',
    unstable_identity: 'invalid_identity',
  }[diagnostic.outcome] || 'invalid_identity';
}

async function workshopBuildVehicleLinkReadinessReport(vehicles = [], options = {}) {
  const source = Array.isArray(vehicles) ? vehicles : [];
  const rows = new Array(source.length);
  const concurrency = Math.max(1, Math.min(8, Number(options.concurrency) || 5));
  let nextIndex = 0;
  let completed = 0;
  const worker = async () => {
    while (nextIndex < source.length) {
      const index = nextIndex;
      nextIndex += 1;
      const vehicle = source[index];
      const diagnostic = await workshopResolveVehicleLinkDiagnostic(vehicle, options.resolver || null, options.storage || null);
      rows[index] = { vehicle, diagnostic, status: workshopVehicleLinkReadinessStatus(diagnostic) };
      completed += 1;
      if (typeof options.onProgress === 'function') options.onProgress(completed, source.length, rows[index]);
    }
  };
  await Promise.all(Array.from({ length: Math.min(concurrency, source.length) }, () => worker()));
  const counts = {
    linked: 0,
    resolvable_unsaved: 0,
    missing_canonical_vehicle: 0,
    ambiguous: 0,
    conflicting: 0,
    invalid_identity: 0,
  };
  rows.forEach(row => { counts[row.status] = (counts[row.status] || 0) + 1; });
  return {
    generatedAt: typeof nowIsoString === 'function' ? nowIsoString() : new Date().toISOString(),
    total: rows.length,
    counts,
    rows,
    browserLocalAuthorityUnchanged: true,
  };
}

async function workshopPersistVehicleLinkReadinessBatch(report = {}, options = {}) {
  if (!workshopVehicleLinkCanPersist()) return { ok: false, error: 'unauthorized', saved: 0, verified: 0 };
  const ready = (Array.isArray(report.rows) ? report.rows : []).filter(row => row.status === 'resolvable_unsaved');
  const receipts = [];
  const verifiedRows = [];
  const persist = options.persistFn || ((vehicle, diagnostic, receipt) => workshopPersistVerifiedCanonicalLink(
    vehicle, diagnostic, options.saveFn || null, options.storage || null, receipt,
  ));
  const rollbackBatch = error => {
    const rollbackResults = receipts.slice().reverse().map((receipt, index) => ({
      receiptIndex: receipts.length - index - 1,
      rolledBack: workshopRollbackPersistedCanonicalLink(receipt),
    }));
    const rollbackConflicts = rollbackResults.filter(result => !result.rolledBack);
    if (rollbackConflicts.length) {
      return {
        ok: false,
        error: 'rollback_conflict',
        cause: error,
        saved: rollbackConflicts.length,
        verified: 0,
        rollbackReviewRequired: true,
        rollbackConflicts,
      };
    }
    return { ok: false, error: `${error}_rolled_back`, saved: 0, verified: 0, rollbackReviewRequired: false };
  };
  for (const row of ready) {
    if (!workshopVehicleLinkCanPersist()) return rollbackBatch('authorization_changed');
    const receipt = {};
    if (!persist(row.vehicle, row.diagnostic, receipt)) {
      return rollbackBatch('browser_local_link_persist_failed');
    }
    receipts.push(receipt);
    if (!workshopVehicleLinkCanPersist()) return rollbackBatch('authorization_changed');
    const verified = await workshopResolveVehicleLinkDiagnostic(row.vehicle, options.resolver || null, options.storage || null);
    if (verified.linkState !== 'verified' || verified.sharedUuid !== row.diagnostic.sharedUuid) {
      return rollbackBatch('post_save_verification_failed');
    }
    if (!workshopVehicleLinkCanPersist()) return rollbackBatch('authorization_changed');
    verifiedRows.push({ ...row, diagnostic: verified, status: 'linked' });
    if (typeof options.onProgress === 'function') options.onProgress(verifiedRows.length, ready.length, verifiedRows[verifiedRows.length - 1]);
  }
  return { ok: true, saved: verifiedRows.length, verified: verifiedRows.length, rows: verifiedRows, browserLocalAuthorityUnchanged: true };
}

function workshopSharedVehicleRef(vehicleReference = '') {
  if (!workshopSharedModeActive()) return null;
  const snapshot = window.__workshopDataService.getLastSnapshot();
  const vehicles = snapshot && Array.isArray(snapshot.vehicles) ? snapshot.vehicles : [];
  const requestedVehicleId = String(
    vehicleReference && typeof vehicleReference === 'object'
      ? vehicleReference.sharedVehicleId || vehicleReference.vehicleId || ''
      : ''
  ).trim();
  const requestedLegacyKey = String(
    vehicleReference && typeof vehicleReference === 'object'
      ? vehicleReference.vehicleKey || ''
      : vehicleReference || ''
  ).trim();
  const byId = requestedVehicleId
    ? vehicles.filter(v => String(v && v.id || '').trim() === requestedVehicleId)
    : [];
  const requestedStockIdentity = workshopNormalizeStockIdentity(requestedLegacyKey);
  const requestedSourceIdentity = workshopNormalizeSourceIdentity(requestedLegacyKey);
  const byLegacyKey = requestedLegacyKey
    ? vehicles.filter(v => (
      (requestedStockIdentity
        && workshopNormalizeStockIdentity(v && v.stock_number) === requestedStockIdentity)
      || (requestedSourceIdentity
        && workshopNormalizeSourceIdentity(v && v.permanent_vehicle_id) === requestedSourceIdentity)
    ))
    : [];
  const candidateVehicleIds = [...new Set([...byId, ...byLegacyKey]
    .map(v => String(v && v.id || '').trim())
    .filter(Boolean))].sort();
  const reviewError = error => ({
    ok: false,
    error,
    requestedVehicleId,
    requestedLegacyKey,
    candidateVehicleIds,
  });

  if (requestedVehicleId) {
    if (byId.length !== 1) {
      return reviewError(byId.length > 1
        ? 'ambiguous_vehicle_identity'
        : byLegacyKey.length > 0
          ? 'conflicting_vehicle_identity'
          : 'vehicle_identity_not_found');
    }
    if (requestedLegacyKey && (
      byLegacyKey.length !== 1
      || String(byLegacyKey[0].id || '').trim() !== requestedVehicleId
    )) {
      return reviewError(byLegacyKey.length > 1 || candidateVehicleIds.length > 1
        ? 'conflicting_vehicle_identity'
        : 'vehicle_identity_not_found');
    }
    return { vehicleId: byId[0].id, version: byId[0].version };
  }

  if (byLegacyKey.length === 0) return reviewError('vehicle_identity_not_found');
  if (byLegacyKey.length > 1) return reviewError('ambiguous_vehicle_identity');
  return { vehicleId: byLegacyKey[0].id, version: byLegacyKey[0].version };
}

// Same idea as workshopSharedVehicleRef but for technicians: resolves a
// legacy free-text assignee name to a shared Supabase technician id by
// scanning the technicians referenced in every booking already present in
// the current snapshot (the snapshot RPC does not currently expose a
// standalone technicians list, only technicians attached to bookings/
// assignments). Returns null (never fabricates an id) if no match is
// found. This is a defensive fallback only; new assignments must first use
// the authoritative reference roster and must never turn a failed nonblank
// lookup into an implicit unassignment.
function workshopSharedTechnicianRef(name = '') {
  if (!workshopSharedModeActive()) return null;
  const cleanName = String(name || '').trim();
  if (!cleanName) return null;
  const snapshot = window.__workshopDataService.getLastSnapshot();
  const bookingLists = [
    ...(snapshot && Array.isArray(snapshot.bookings) ? snapshot.bookings : []),
    ...(snapshot && Array.isArray(snapshot.active_stoppages) ? snapshot.active_stoppages : []),
  ];
  for (const booking of bookingLists) {
    const assignment = booking && booking.assignment;
    if (assignment && String(assignment.technician_name || '').trim() === cleanName) {
      return { technicianId: assignment.technician_id };
    }
  }
  return null;
}

// Independent-review remediation (finding 3): workshopSharedTechnicianRef()
// above ONLY finds a technician who has already appeared on a current
// booking/stoppage assignment in the live snapshot -- a valid, active
// technician who has simply never yet been assigned to anything could
// not be resolved, and the caller would then send technicianId: null,
// which UNASSIGNS rather than assigns the selected technician. This
// resolver instead looks up the STABLE technician reference table
// (window.__workshopReferenceDataService, populated by
// list_technicians -- the Stage 2A source of truth for the technician
// roster), matched by exact name, restricted to ACTIVE technicians
// only (an inactive technician must never be resolved for a NEW
// assignment; the assign_booking_technician RPC also independently
// rejects an inactive technician id, so this is defence in depth, not
// the only check). Returns { technicianId } on a match, null
// otherwise -- callers must treat null as "no valid technician found",
// not as "explicitly unassign".
function workshopReferenceTechnicianRef(name = '') {
  const cleanName = String(name || '').trim();
  if (!cleanName) return null;
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  if (!service || typeof service.getCachedTechnicians !== 'function') return null;
  const cached = service.getCachedTechnicians();
  const rows = cached && Array.isArray(cached.rows) ? cached.rows : [];
  const technician = rows.find(row => row && row.active !== false && String(row.name || '').trim() === cleanName);
  return technician ? { technicianId: technician.id } : null;
}

function workshopSelectedTechnicianRef(name = '') {
  const cleanName = String(name || '').trim();
  if (!cleanName) return null;
  const authoritative = workshopReferenceTechnicianRef(cleanName);
  if (authoritative) return authoritative;
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  const cached = service && typeof service.getCachedTechnicians === 'function'
    ? service.getCachedTechnicians()
    : null;
  const rows = cached && Array.isArray(cached.rows) ? cached.rows : [];
  // A known inactive row is authoritative and must not be resurrected by a
  // stale booking snapshot containing the same technician name.
  if (rows.some(row => row && row.active === false && String(row.name || '').trim() === cleanName)) return null;
  return workshopSharedTechnicianRef(cleanName);
}

function workshopPlanId(vehicleKeyValue = '', stage = '') {
  return `${normalizePmbStage(stage)}::${String(vehicleKeyValue || '').trim()}`;
}

// Stage 2A: workshop bay active-state and default-technician lookup.
// Always reads from the Supabase-backed shared reference service
// (window.__workshopReferenceDataService) -- independent of the
// separate workshopSharedModeActive() flag, since bay active/default-
// technician data is Stage 2A lookup/configuration data, not a
// transactional workshop write-path action. Matches by the bay's
// display code, which the migration 022 backfill derives as
// "<STAGE>-BAY-<NN>" (zero-padded) for ordinary stage bays and
// "SUBLET-ROW-1" for the single sublet row -- see migration 022.
// This lookup itself returns null when shared bay data is unavailable or
// unmatched. New scheduling/move guards interpret that state fail-closed via
// workshopBayAvailabilityStatus(); only existing/historical rendering uses
// the intentionally lenient workshopBayIsActive() compatibility helper.
function workshopSharedBayRef(stage = '', bay = 0) {
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  if (!service || typeof service.getCachedWorkshopBays !== 'function') return null;
  const cached = service.getCachedWorkshopBays();
  const rows = cached && Array.isArray(cached.rows) ? cached.rows : [];
  const normalizedStage = normalizePmbStage(stage);
  const bayNumber = Number(bay) || 1;
  const expectedCode = normalizedStage === 'SUBLET'
    ? 'SUBLET-ROW'
    : `${normalizedStage}-BAY-${String(bayNumber).padStart(2, '0')}`;
  return rows.find(row => row && row.code === expectedCode) || null;
}

// Independent-review remediation (finding 8): workshopBayIsActive()
// below is a plain boolean that collapsed "confirmed active",
// "confirmed inactive", "reference data still loading/unavailable",
// and "unknown bay mapping" into just two outcomes (true/false),
// failing OPEN (treated as active/schedulable) for the loading and
// unknown cases. That is unsafe: an inactive or genuinely unknown bay
// could accept a NEW booking simply because the reference data had
// not loaded yet. workshopBayAvailabilityStatus() returns the real,
// distinct state so callers that are about to CREATE new scheduled
// work can block on anything other than confirmed 'active', while
// code that only needs a fail-safe default for EXISTING/historical
// bookings can keep using the boolean workshopBayIsActive() below,
// unchanged, for backward compatibility.
function workshopBayAvailabilityStatus(stage = '', bay = 0) {
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  if (!service || typeof service.getCachedWorkshopBays !== 'function') {
    // No shared service at all (legacy local planner mode, or the
    // service has not been constructed on this page) -- there is no
    // shared bay reference to consult, so this genuinely cannot be
    // "unavailable" in the Stage 2A sense. Treat as active so local
    // mode continues to work exactly as before Stage 2A.
    return 'active';
  }
  const cached = service.getCachedWorkshopBays();
  const state = cached && cached.state;
  const loadingStates = ['connecting', 'reconnecting', 'offline_error', 'permission_denied'];
  if (!cached || !Array.isArray(cached.rows) || loadingStates.includes(state)) {
    return 'unavailable';
  }
  const ref = workshopSharedBayRef(stage, bay);
  if (!ref) return 'unknown';
  return ref.is_active !== false ? 'active' : 'inactive';
}

function workshopBayIsActive(stage = '', bay = 0) {
  const ref = workshopSharedBayRef(stage, bay);
  // Fail safe: unknown bay (service not loaded, or no matching row yet)
  // is treated as active so EXISTING/historical bookings always remain
  // visible/renderable -- this function is intentionally lenient and
  // must NOT be used to gate creation of NEW scheduled work (use
  // workshopBayAvailabilityStatus() for that, which fails closed).
  return ref ? ref.is_active !== false : true;
}

function workshopBayDefaultTechnicianName(stage = '', bay = 0) {
  const ref = workshopSharedBayRef(stage, bay);
  if (!ref || !ref.default_technician_id) return '';
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  if (!service || typeof service.getCachedTechnicians !== 'function') return '';
  const cached = service.getCachedTechnicians();
  const rows = cached && Array.isArray(cached.rows) ? cached.rows : [];
  const technician = rows.find(row => row && row.id === ref.default_technician_id);
  return technician ? cleanNavisionText(technician.name) : '';
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

function workshopResolveConflictByNextSlot(candidate = {}, rows = workshopLoadPlans()) {
  const conflict = workshopHasConflict(candidate, rows);
  if (!conflict) return candidate;
  const conflictVehicle = workshopVehicle(conflict.vehicleKey);
  const identity = conflictVehicle ? (displayStockNumber(conflictVehicle) || vehicleJobcardNumber(conflictVehicle) || 'another vehicle') : 'another vehicle';
  const area = candidate.stage === 'SUBLET' ? 'the Sublet provider row' : `${pmbStageLabel(candidate.stage)} Bay ${candidate.bay}`;
  const requestedStart = workshopEntryStart(candidate);
  const requestedMinutes = workshopMinuteOffset(requestedStart);
  const nextSlot = workshopFirstAvailableStartSlot(
    candidate.stage,
    candidate.bay,
    workshopDateKey(requestedStart),
    candidate.hours,
    rows,
    requestedMinutes,
  );
  if (!nextSlot) {
    window.alert(`${area} already has ${identity} booked during that time. No open sequence slot was found in this bay during the next 260 workdays; choose another bay or a later date.`);
    return null;
  }
  const nextStart = workshopDateAtOffset(nextSlot.dateKey, nextSlot.startMinutes);
  const nextLabel = nextStart.toLocaleString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric', hour: 'numeric', minute: '2-digit' });
  if (!window.confirm(`${area} already has ${identity} booked during that time.\n\nMove this booking to the next open slot in this bay instead?\n\nNext open slot: ${nextLabel}`)) return null;
  return { ...candidate, startAt: nextStart.toISOString() };
}

function workshopShiftTrailingPlannedRows(candidate = {}, otherRows = [], { confirmMove = true } = {}) {
  // Back-to-back queue support: when a start/extend/edit overlaps only PLANNED bookings
  // in the same bay, offer to push those queued bookings to the next open sequence slots.
  // Live (started/stoppage) and completed bookings are never moved.
  const sameBay = row => row.status !== 'completed' && row.stage === candidate.stage && Number(row.bay) === Number(candidate.bay);
  const bayRows = otherRows.filter(sameBay);
  const outsideRows = otherRows.filter(row => !sameBay(row));
  const candidateStart = workshopEntryStart(candidate);
  const candidateEnd = workshopEntryEffectiveEnd(candidate);
  const liveRows = bayRows.filter(row => ['started', 'stoppage'].includes(row.status));
  const liveOverlap = liveRows.some(row => workshopIntervalsOverlap(candidateStart.getTime(), candidateEnd.getTime(), workshopEntryStart(row).getTime(), workshopEntryEffectiveEnd(row).getTime()));
  if (liveOverlap) return null;
  const plannedRows = bayRows.filter(row => row.status === 'planned').sort((a, b) => String(a.startAt).localeCompare(String(b.startAt)));
  const settled = [...outsideRows, ...liveRows, candidate];
  const moved = [];
  for (const row of plannedRows) {
    if (!workshopHasConflict(row, settled)) {
      settled.push(row);
      continue;
    }
    const originalStart = workshopEntryStart(row);
    const slot = workshopFirstAvailableStartSlot(row.stage, row.bay, workshopDateKey(originalStart), row.hours, settled, workshopMinuteOffset(originalStart));
    if (!slot) return null;
    const shifted = { ...row, startAt: workshopDateAtOffset(slot.dateKey, slot.startMinutes).toISOString(), updatedAt: nowIsoString() };
    settled.push(shifted);
    moved.push(shifted);
  }
  if (moved.length && confirmMove) {
    const details = moved.slice(0, 6).map(row => {
      const vehicle = workshopVehicle(row.vehicleKey);
      const identity = vehicle ? (displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'vehicle') : 'vehicle';
      const start = parseIsoTimestamp(row.startAt);
      const label = start ? start.toLocaleString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' }) : 'time TBC';
      return `• ${identity} → ${label}`;
    }).join('\n');
    const noun = moved.length === 1 ? 'booking' : 'bookings';
    if (!window.confirm(`This time overlaps ${moved.length} queued planned ${noun} in this bay.\n\nMove the queued ${noun} to the next open slot${moved.length === 1 ? '' : 's'}?\n\n${details}`)) return null;
  }
  return { rows: settled, moved };
}

function workshopShiftEveryLaterPlannedRow(candidate = {}, otherRows = [], shiftMinutes = 0) {
  const delay = Math.max(0, workshopSnapMinutes(shiftMinutes));
  const candidateStart = workshopEntryStart(candidate);
  if (!delay || Number.isNaN(candidateStart.getTime())) return { rows: otherRows.map(row => ({ ...row })), moved: [] };
  const later = otherRows
    .filter(row => row.id !== candidate.id
      && row.status === 'planned'
      && row.stage === candidate.stage
      && Number(row.bay) === Number(candidate.bay)
      && workshopEntryStart(row) >= candidateStart)
    .sort((a, b) => workshopEntryStart(a) - workshopEntryStart(b) || String(a.id).localeCompare(String(b.id)));
  const moved = later.map(row => ({
    ...row,
    startAt: workshopAddWorkMinutes(workshopEntryStart(row), delay).toISOString(),
    updatedAt: nowIsoString(),
  }));
  const byId = new Map(moved.map(row => [row.id, row]));
  return { rows: otherRows.map(row => byId.get(row.id) || { ...row }), moved };
}

function workshopTechnicianIdForEntry(entry = {}) {
  if (entry.technicianId) return String(entry.technicianId);
  const assignee = cleanNavisionText(entry.assignee || '');
  if (!assignee) return '';
  const ref = workshopSelectedTechnicianRef(assignee);
  return ref ? String(ref.technicianId || '') : '';
}

function workshopTechnicianIsOnLeave(technicianId = '', dateValue = new Date()) {
  const dates = WORKSHOP_PLANNER_CONFIG.technicianLeaveByTechnicianId[String(technicianId || '')] || [];
  return dates.includes(workshopDateKey(dateValue));
}

function workshopNewBookingValidation(entry = {}) {
  if (!workshopConfigurationAllowsNewScheduling()) return { ok: false, error: 'configuration_unavailable' };
  const start = parseIsoTimestamp(entry.startAt || '');
  if (!start) return { ok: false, error: 'invalid_start' };
  if (workshopIsClosureDate(start)) return { ok: false, error: 'closure_date', date: workshopDateKey(start) };
  if (!workshopIsConfiguredWorkingDay(start)) return { ok: false, error: 'non_working_day', date: workshopDateKey(start) };
  const startMinute = workshopMinuteOfDay(start);
  const startWindow = workshopAvailabilityWindowsForDate(start).find(window => startMinute >= window.startMinutes && startMinute < window.endMinutes);
  if (!startWindow) {
    const inBreak = workshopBreakWindowsForDate(start).some(window => startMinute >= window.startMinutes && startMinute < window.endMinutes);
    return { ok: false, error: inBreak ? 'break_window' : 'outside_work_window', date: workshopDateKey(start), minute: startMinute };
  }
  const durationMinutes = Math.max(60, Math.round(Number(entry.hours || workshopDefaultBookingHours()) * 60));
  const technicianId = workshopTechnicianIdForEntry(entry);
  let usesOvertime = false;
  for (let offset = 0; offset < durationMinutes; offset += 1) {
    const proposedMinute = workshopAddWorkMinutes(start, offset);
    const dateKey = workshopDateKey(proposedMinute);
    if (workshopIsClosureDate(proposedMinute)) return { ok: false, error: 'closure_date', date: dateKey };
    if (!workshopIsConfiguredWorkingDay(proposedMinute)) return { ok: false, error: 'non_working_day', date: dateKey };
    const minute = workshopMinuteOfDay(proposedMinute);
    const windows = workshopAvailabilityWindowsForDate(proposedMinute);
    const containingWindow = windows.find(window => minute >= window.startMinutes && minute < window.endMinutes);
    if (!containingWindow) {
      const inBreak = workshopBreakWindowsForDate(proposedMinute).some(window => minute >= window.startMinutes && minute < window.endMinutes);
      return { ok: false, error: inBreak ? 'break_window' : 'outside_work_window', date: dateKey, minute };
    }
    usesOvertime = usesOvertime || containingWindow.overtime === true;
    if (technicianId && workshopTechnicianIsOnLeave(technicianId, proposedMinute)) {
      return { ok: false, error: 'technician_on_leave', date: dateKey, technicianId };
    }
  }
  return { ok: true, usesOvertime };
}

function workshopRequireSchedulableCandidate(entry = {}) {
  const result = workshopNewBookingValidation(entry);
  if (result.ok) return true;
  const messages = {
    configuration_unavailable: 'Shared planner configuration is loading, unavailable, or invalid. New scheduling is blocked until valid shared settings are confirmed.',
    invalid_start: 'Choose a valid workshop start date and time.',
    closure_date: 'That date is configured as a workshop closure and cannot accept a new booking.',
    non_working_day: 'That date is not part of the configured working week.',
    break_window: 'The proposed booking interval overlaps a configured non-bookable break window.',
    outside_work_window: 'The proposed booking interval extends outside regular hours and configured overtime windows.',
    technician_on_leave: 'That technician is on configured leave during the proposed booking interval and cannot receive the assignment.',
  };
  if (typeof window !== 'undefined' && typeof window.alert === 'function') window.alert(messages[result.error] || 'That booking is not schedulable under the current shared configuration.');
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

function workshopCascadePlans(rows = workshopLoadPlans(), now = new Date()) {
  let nextRows = rows.map(entry => ({ ...entry, hours: entry.status === 'completed' ? entry.hours : workshopClampDurationHours(entry.hours) }));
  let changed = nextRows.some((entry, index) => entry.hours !== rows[index].hours);
  const liveRows = nextRows
    .filter(entry => workshopEntryIsLive(entry) && workshopEntryIsOvertime(entry, now))
    .sort((a, b) => workshopEntryStart(a) - workshopEntryStart(b));
  for (const live of liveRows) {
    const delay = workshopWorkMinutesBetween(workshopEntryEnd(live), workshopEntryEffectiveEnd(live, now));
    if (delay <= 0) continue;
    const shifted = workshopShiftEveryLaterPlannedRow(live, nextRows.filter(row => row.id !== live.id), delay);
    if (!shifted.moved.length) continue;
    const byId = new Map(shifted.moved.map(row => [row.id, row]));
    nextRows = nextRows.map(row => byId.get(row.id) || row);
    changed = true;
  }
  return { rows: nextRows, changed };
}

function workshopCascadeAndSave(rows = workshopLoadPlans(), now = new Date()) {
  const cascaded = workshopCascadePlans(rows, now);
  // In shared read-only mode there is nothing to reconcile locally -- the
  // rows already came from the authoritative snapshot -- and attempting a
  // save would trip the fail-closed alert on every render. Only ever save
  // here when this file's own local-storage path is authoritative.
  if (cascaded.changed && !workshopSharedModeActive()) workshopSavePlans(cascaded.rows);
  return cascaded.rows;
}

function workshopTimeLabelFromMinutes(minutes = 0) {
  const total = WORKSHOP_PLANNER_CONFIG.dayStartMinutes + Number(minutes || 0);
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

function workshopSlotSummary(stage = '', bay = 1, dateKey = '', startMinutes = 0) {
  const normalizedStage = normalizePmbStage(stage);
  const start = workshopDateAtOffset(dateKey, startMinutes);
  const when = start.toLocaleString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  const area = normalizedStage === 'SUBLET'
    ? `${pmbStageLabel(normalizedStage)} · Provider row`
    : `${pmbStageLabel(normalizedStage)} · Bay ${workshopPad(bay)}`;
  return `${area} · ${when}`;
}

function workshopBestStageSlot(stage = '', dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0) {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return null;
  let best = null;
  for (let bay = 1; bay <= workshopStageBayCount(normalizedStage); bay += 1) {
    const slot = workshopFirstAvailableStartSlot(normalizedStage, bay, dateKey, hours, rows, notBeforeMinutes);
    if (!slot) continue;
    const candidateStart = workshopDateAtOffset(slot.dateKey, slot.startMinutes).getTime();
    const bestStart = best ? workshopDateAtOffset(best.dateKey, best.startMinutes).getTime() : Number.POSITIVE_INFINITY;
    if (!best || candidateStart < bestStart || (candidateStart === bestStart && bay < best.bay)) {
      best = { stage: normalizedStage, bay, dateKey: slot.dateKey, startMinutes: slot.startMinutes };
    }
  }
  return best;
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
  if (changed && !workshopSharedModeActive()) workshopSavePlans(next);
  return next;
}

function workshopStageVehicles(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  const def = pmbStageJobDef(normalizedStage);
  const pmbCandidates = normalizedStage === 'SUBLET'
    ? app.data.filter(vehicle => {
      if (statusCategory(vehicle) !== 'pmb') return false;
      const currentStage = normalizePmbStage(inferredPmbStage(vehicle));
      const hasSubletJobLine = workshopImportedJobLines(vehicle)
        .some(line => workshopDetectedStageForLine(line.text, vehicle) === 'SUBLET');
      return currentStage === 'SUBLET'
        || hasSubletJobLine
        || Boolean(cleanNavisionText(vehicle.pmbSubletProvider || vehicle.pmbSubletBookingDate || vehicle.pmbSubletExpectedReturnDate || ''));
    })
    : (typeof pmbVehiclesNeedingStationWork === 'function' ? pmbVehiclesNeedingStationWork(normalizedStage) : []);
  const preArrivalCandidates = app.data.filter(vehicle => {
    const planningLocation = workshopVehiclePlanningLocation(vehicle);
    if (!['YH', 'IT'].includes(planningLocation)) return false;
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
  });
  const rows = [...pmbCandidates, ...preArrivalCandidates];
  return [...new Map(rows.map(vehicle => [vehicleKey(vehicle), vehicle])).values()]
    .sort((a, b) => String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || '')));
}

function workshopSnapshotVehicleToPlannerRow(vehicle = {}, workItems = [], stage = '') {
  const rawEta = String(vehicle.eta_to_kewdale || '').trim();
  const isoEta = rawEta.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const etaToKewdale = isoEta ? `${isoEta[3]}/${isoEta[2]}/${isoEta[1]}` : rawEta;
  const jobDef = typeof pmbJobDefForStage === 'function' ? pmbJobDefForStage(stage) : null;
  const stageWorkItems = workItems.filter(item => String(item?.vehicle_id || '') === String(vehicle.id || ''));
  const pmbJobs = {};
  stageWorkItems.forEach(item => {
    const key = String(item.work_key || jobDef?.key || '').trim();
    if (!key) return;
    pmbJobs[key] = {
      required: item.required === true,
      completed: item.completed === true,
      completedAt: item.completed_at || null,
      notes: item.notes || ''
    };
  });
  return {
    id: vehicle.id,
    sharedVehicleId: vehicle.id,
    permanentVehicleId: vehicle.permanent_vehicle_id || '',
    vehicleKey: vehicle.stock_number || vehicle.permanent_vehicle_id || vehicle.id,
    stockNumber: vehicle.stock_number || '',
    vin: vehicle.vin || '',
    toyotaOrderNumber: vehicle.toyota_order_number || '',
    jobCardNumber: vehicle.job_card_number || '',
    customerName: vehicle.customer_name || '',
    customer: vehicle.customer_name || '',
    make: vehicle.make || '',
    model: vehicle.model || '',
    registration: vehicle.registration || '',
    currentLocation: vehicle.current_location || '',
    pdcLocation: vehicle.current_location || '',
    pmbStage: vehicle.pmb_stage || stage,
    pmbBayStage: vehicle.pmb_bay_stage || '',
    pmbBayNumber: vehicle.pmb_bay_number || '',
    navisionKewdaleEta: etaToKewdale,
    etaAtKewdale: etaToKewdale,
    pmbJobs,
    version: vehicle.version
  };
}

function workshopPlannerVehiclesForStage(stage = '') {
  const rows = workshopStageVehicles(stage);
  const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  if (!dedicatedStage || !workshopSharedModeActive()) return rows;
  const snapshot = window.__workshopDataService?.getLastSnapshot?.();
  const snapshotVehicles = Array.isArray(snapshot?.vehicles) ? snapshot.vehicles : [];
  const bookings = Array.isArray(snapshot?.bookings) ? snapshot.bookings : [];
  const workItems = Array.isArray(snapshot?.work_items) ? snapshot.work_items : [];
  const jobDef = typeof pmbJobDefForStage === 'function' ? pmbJobDefForStage(dedicatedStage) : null;
  const relevantVehicleIds = new Set([
    ...bookings
      .filter(booking => normalizePmbStage(booking?.stage_code || booking?.stage) === dedicatedStage)
      .map(booking => String(booking?.vehicle_id || '').trim()),
    ...workItems
      .filter(item => !jobDef || String(item?.work_key || '').replace(/_/g, '').toUpperCase() === String(jobDef.key || '').replace(/_/g, '').toUpperCase())
      .map(item => String(item?.vehicle_id || '').trim())
  ].filter(Boolean));
  const scopedVehicles = snapshotVehicles.filter(vehicle => (
    normalizePmbStage(vehicle?.pmb_stage || '') === dedicatedStage
    || relevantVehicleIds.has(String(vehicle?.id || '').trim())
  ));
  const localById = new Map(rows.map(vehicle => [String(vehicle.id || vehicle.sharedVehicleId || '').trim(), vehicle]).filter(([key]) => key));
  const localByStock = new Map(rows.map(vehicle => [String(displayStockNumber(vehicle) || '').trim(), vehicle]).filter(([key]) => key));
  return scopedVehicles.map(vehicle => {
    const local = localById.get(String(vehicle.id || '').trim())
      || localByStock.get(String(vehicle.stock_number || '').trim());
    const scoped = workshopSnapshotVehicleToPlannerRow(vehicle, workItems, dedicatedStage);
    return local ? {
      ...scoped,
      ...local,
      pmbJobs: { ...scoped.pmbJobs, ...(local.pmbJobs || {}) },
      sharedVehicleId: vehicle.id,
      id: vehicle.id
    } : scoped;
  }).sort((a, b) => String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || '')));
}

function workshopRefreshDedicatedDate(dateKey = '') {
  const stage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  const service = window.__workshopDataService;
  if (!stage || !service || typeof service.setScope !== 'function') return false;
  service.setScope({ stageCode: stage, dateFrom: dateKey, dateTo: dateKey });
  return true;
}

function workshopVehiclePlanningLocation(vehicle = {}) {
  const raw = typeof vehiclePdcLocation === 'function'
    ? vehiclePdcLocation(vehicle)
    : (vehicle.pdcLocation || vehicle.manualLocation || '');
  const normalized = cleanNavisionText(raw || '').toUpperCase();
  if (normalized === 'YH' || normalized === 'IT') return normalized;
  return statusCategory(vehicle) === 'pmb' || normalized === 'PMB' ? 'PMB' : normalized;
}

function workshopVehicleEtaConstraint(vehicle = {}) {
  const location = workshopVehiclePlanningLocation(vehicle);
  if (!['YH', 'IT'].includes(location)) return { required: false, ok: true, location, earliestDateKey: '' };
  const raw = cleanNavisionText(typeof kewdaleEtaValue === 'function' ? kewdaleEtaValue(vehicle) : (vehicle.navisionKewdaleEta || vehicle.navisionEtaDate || ''));
  const parsed = raw && typeof parseDateAU === 'function' ? parseDateAU(raw) : null;
  if (!parsed || Number.isNaN(parsed.getTime())) return { required: true, ok: false, location, raw, earliestDateKey: '', reason: raw ? 'invalid_eta' : 'missing_eta' };
  return { required: true, ok: true, location, raw, earliestDateKey: workshopDateKey(parsed) };
}

function workshopDateKeyNotBefore(value = '', minimum = '') {
  if (!minimum) return value;
  if (!value || value < minimum) return minimum;
  return value;
}

function workshopEtaScheduleValidation(vehicle = {}, scheduledStartAt = '') {
  const constraint = workshopVehicleEtaConstraint(vehicle);
  if (!constraint.required) return constraint;
  if (!constraint.ok) return constraint;
  const scheduled = scheduledStartAt instanceof Date ? scheduledStartAt : parseIsoTimestamp(scheduledStartAt);
  const scheduledDateKey = scheduled ? workshopDateKey(scheduled) : '';
  if (!scheduledDateKey || scheduledDateKey < constraint.earliestDateKey) {
    return { ...constraint, ok: false, reason: 'before_eta', scheduledDateKey };
  }
  return { ...constraint, scheduledDateKey };
}

function workshopRequireEtaSchedule(vehicle = {}, scheduledStartAt = '') {
  const result = workshopEtaScheduleValidation(vehicle, scheduledStartAt);
  if (result.ok) return true;
  if (result.reason === 'missing_eta' || result.reason === 'invalid_eta') {
    window.alert(`${result.location} vehicles require a valid ETA to Kewdale before they can be booked. Correct the ETA and try again. No booking was created.`);
  } else {
    window.alert(`This ${result.location} vehicle cannot be booked before its ETA to Kewdale. Earliest permitted booking date: ${result.earliestDateKey}. No booking was created.`);
  }
  return false;
}

function workshopEtaRiskForEntry(entry = {}, vehicle = workshopVehicle(entry.vehicleKey)) {
  if (!vehicle || entry.status === 'completed') return null;
  const result = workshopEtaScheduleValidation(vehicle, entry.startAt || entry.scheduledStartAt || '');
  return result.required && !result.ok && result.reason === 'before_eta' ? result : null;
}

function workshopVehicleSearchText(vehicle = {}) {
  return [vehicleKey(vehicle), displayStockNumber(vehicle), vehicle.keyNumber, vehicleKeyNumber(vehicle), vehicle.pdcJobcard, vehicleJobcardNumber(vehicle), vehicleCustomerName(vehicle), vehicle.vehicle, vehicle.toyotaVehicle, displayVehicle(vehicle)]
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

function workshopSortBookingsClosest(rows = [], nowValue = Date.now()) {
  const now = Number(nowValue);
  return [...rows].sort((a, b) => {
    const aParsed = parseIsoTimestamp(a?.startAt || '');
    const bParsed = parseIsoTimestamp(b?.startAt || '');
    const aStart = aParsed ? aParsed.getTime() : Number.POSITIVE_INFINITY;
    const bStart = bParsed ? bParsed.getTime() : Number.POSITIVE_INFINITY;
    const aDistance = Number.isFinite(aStart) ? Math.abs(aStart - now) : Number.POSITIVE_INFINITY;
    const bDistance = Number.isFinite(bStart) ? Math.abs(bStart - now) : Number.POSITIVE_INFINITY;
    return aDistance - bDistance || aStart - bStart || String(a.id || '').localeCompare(String(b.id || ''));
  });
}

function workshopPlanVehicleIdentity(entry = {}) {
  const sharedVehicleId = String(entry.sharedVehicleId || '').trim();
  return sharedVehicleId ? `shared:${sharedVehicleId}` : `legacy:${String(entry.vehicleKey || '').trim()}`;
}

function workshopResolveBookingSelection(plans = [], bookingId = '', vehicleIdentity = '') {
  const matches = (Array.isArray(plans) ? plans : []).filter(plan => (
    String(plan.id || '') === String(bookingId || '')
    && workshopPlanVehicleIdentity(plan) === String(vehicleIdentity || '')
  ));
  if (matches.length !== 1 || !parseIsoTimestamp(matches[0].startAt || '')) return null;
  return matches[0];
}

function workshopBookingsForEntry(plans = [], entry = {}) {
  const identity = workshopPlanVehicleIdentity(entry);
  return (Array.isArray(plans) ? plans : []).filter(plan => workshopPlanVehicleIdentity(plan) === identity);
}

function workshopSearchMatches(query = '', plans = workshopLoadPlans()) {
  const clean = cleanNavisionText(query || '').toLowerCase();
  if (clean.length < 2) return [];
  return app.data
    .filter(vehicle => workshopVehicleSearchText(vehicle).includes(clean))
    .map(vehicle => {
      const key = vehicleKey(vehicle);
      const sharedRef = workshopSharedModeActive() ? workshopSharedVehicleRef({ vehicleKey: key }) : null;
      const vehicleIdentity = sharedRef?.vehicleId ? `shared:${sharedRef.vehicleId}` : `legacy:${key}`;
      const bookings = workshopSortBookingsClosest((Array.isArray(plans) ? plans : []).filter(entry => workshopPlanVehicleIdentity(entry) === vehicleIdentity));
      return {
        vehicle,
        vehicleKey: key,
        vehicleIdentity,
        rank: workshopSearchRank(vehicle, clean),
        archived: Boolean(vehicle.isArchived || vehicle.archivedAt || statusCategory(vehicle) === 'deleted'),
        bookings,
      };
    })
    .sort((a, b) => a.rank - b.rank
      || String(displayStockNumber(a.vehicle) || a.vehicleKey).localeCompare(String(displayStockNumber(b.vehicle) || b.vehicleKey))
      || a.vehicleKey.localeCompare(b.vehicleKey));
}

function workshopBookingSearchStatus(entry = {}) {
  return entry.status === 'completed' ? 'Completed' : entry.status === 'stoppage' ? 'Stoppage' : entry.status === 'started' ? 'Live' : 'Planned';
}

function workshopBookingSearchMeta(entry = {}) {
  const start = parseIsoTimestamp(entry.startAt || '');
  const end = start ? workshopEntryEnd(entry) : null;
  return {
    station: pmbStageLabel(entry.stage) || entry.stage || 'Unknown work group',
    bay: entry.stage === 'SUBLET' ? (entry.assignee || 'Provider unassigned') : `Bay ${entry.bay || '—'}`,
    date: !start ? 'Unknown date' : start.toLocaleDateString('en-AU'),
    time: !start || !end ? 'Unknown time' : `${start.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' })}–${end.toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' })}`,
    status: workshopBookingSearchStatus(entry),
  };
}

function workshopSearchResultsHtml(query = '', plans = workshopLoadPlans()) {
  const matches = workshopSearchMatches(query, plans);
  if (cleanNavisionText(query || '').length < 2) return '';
  if (!matches.length) return '<div class="workshop-search-state" role="status"><strong>No booking found</strong><span>No vehicle matched that key, stock, job card, customer or vehicle description.</span></div>';
  const ambiguous = matches.length > 1
    ? `<div class="workshop-search-state is-warning" role="status"><strong>Multiple matching vehicles</strong><span>${matches.length} vehicles matched. Choose a specific vehicle and booking; nothing was selected automatically.</span></div>`
    : '';
  const rows = matches.map(match => {
    const vehicle = match.vehicle;
    const identity = {
      key: vehicleKeyNumber(vehicle) || '—',
      stock: displayStockNumber(vehicle) || '—',
      jobcard: vehicleJobcardNumber(vehicle) || '—',
      customer: vehicleCustomerName(vehicle) || 'Unknown customer',
      description: displayVehicle(vehicle) || 'Vehicle description unavailable',
    };
    const archived = match.archived ? '<span class="workshop-search-alert">Archived vehicle</span>' : '';
    if (!match.bookings.length) {
      return `<article class="workshop-search-result is-unbooked" data-workshop-search-vehicle-identity="${escapeHtml(match.vehicleIdentity)}">
        <div><strong>Key ${escapeHtml(identity.key)} · Stock ${escapeHtml(identity.stock)} · JC ${escapeHtml(identity.jobcard)}</strong><span>${escapeHtml(identity.customer)} · ${escapeHtml(identity.description)}</span></div>
        <div class="workshop-search-result-state">${archived}<strong>No booking found</strong><span>This vehicle has no workshop booking.</span></div>
      </article>`;
    }
    return match.bookings.map((entry, bookingIndex) => {
      const meta = workshopBookingSearchMeta(entry);
      const closest = match.bookings.length > 1 && bookingIndex === 0 ? '<span class="workshop-search-closest">Closest booking</span>' : '';
      return `<button type="button" class="workshop-search-result" data-workshop-search-booking-id="${escapeHtml(entry.id)}" data-workshop-search-vehicle-identity="${escapeHtml(match.vehicleIdentity)}">
        <span class="workshop-search-result-vehicle"><strong>Key ${escapeHtml(identity.key)} · Stock ${escapeHtml(identity.stock)} · JC ${escapeHtml(identity.jobcard)}</strong><span>${escapeHtml(identity.customer)} · ${escapeHtml(identity.description)}</span></span>
        <span class="workshop-search-result-booking"><strong>${escapeHtml(meta.station)} · ${escapeHtml(meta.bay)}</strong><span>${escapeHtml(meta.date)} · ${escapeHtml(meta.time)} · ${escapeHtml(meta.status)}</span></span>
        <span class="workshop-search-result-flags">${archived}${closest}</span>
      </button>`;
    }).join('');
  }).join('');
  return `${ambiguous}<div class="workshop-search-results-list">${rows}</div>`;
}

function workshopSearchControlHtml(query = '', plans = workshopLoadPlans()) {
  const open = workshopState().searchOpen && cleanNavisionText(query || '').length >= 2;
  return `<section class="workshop-booking-search${open ? ' is-open' : ''}" aria-label="Vehicle booking search">
    <label><span>Find a workshop booking</span><input type="search" data-workshop-search value="${escapeHtml(query)}" placeholder="Key, stock, job card, customer or vehicle" autocomplete="off" aria-controls="workshop-booking-search-results" aria-expanded="${open ? 'true' : 'false'}" /></label>
    <button type="button" class="small-button" data-workshop-search-clear ${query ? '' : 'disabled'}>Clear</button>
    <div id="workshop-booking-search-results" class="workshop-search-results" ${open ? '' : 'hidden'}>${open ? workshopSearchResultsHtml(query, plans) : ''}</div>
  </section>`;
}

function workshopScrollToHighlightedVehicle(root = document) {
  const state = workshopState();
  const key = state.highlightVehicleKey;
  const planId = state.searchHighlightPlanId;
  if (!key && !planId) return;
  window.requestAnimationFrame(() => {
    const bookingTarget = planId ? Array.from(root.querySelectorAll('[data-workshop-plan-id]')).find(element => element.dataset.workshopPlanId === planId) : null;
    const vehicleTarget = key ? Array.from(root.querySelectorAll('[data-workshop-locate-key]')).find(element => element.dataset.workshopLocateKey === key) : null;
    const target = bookingTarget || vehicleTarget;
    target?.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
  });
}

function workshopSelectSearchBooking(bookingId = '', vehicleIdentity = '') {
  window.clearTimeout(app.workshopPlannerSearchTimer);
  const state = workshopState();
  const plans = workshopLoadPlans();
  const entry = workshopResolveBookingSelection(plans, bookingId, vehicleIdentity);
  if (!entry) {
    state.searchOpen = true;
    renderWorkshopPlanner();
    return false;
  }
  const bookings = workshopSortBookingsClosest(workshopBookingsForEntry(plans, entry));
  state.stage = entry.stage;
  state.date = workshopEntryDate(entry);
  state.selectedPlanId = entry.id;
  state.highlightVehicleKey = entry.vehicleKey;
  state.searchHighlightPlanId = entry.id;
  state.searchOpen = false;
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = true;
  state.searchNotice = bookings.length > 1 ? `This vehicle has ${bookings.length} bookings. Showing the selected booking.` : '';
  workshopSaveView(state);
  renderWorkshopPlanner();
  return true;
}

function workshopOpenBookingById(bookingId = '', vehicleIdentity = '') {
  const state = workshopState();
  const entry = workshopResolveBookingSelection(workshopLoadPlans(), bookingId, vehicleIdentity);
  if (!entry) return false;
  state.stage = entry.stage;
  state.date = workshopEntryDate(entry);
  state.selectedPlanId = entry.id;
  state.highlightVehicleKey = entry.vehicleKey;
  state.searchHighlightPlanId = entry.id;
  state.searchOpen = false;
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = true;
  state.searchNotice = '';
  workshopSaveView(state);
  renderWorkshopPlanner();
  return true;
}

function workshopRevealSearchMatch(query = '') {
  const state = workshopState();
  state.search = cleanNavisionText(query || '');
  state.searchOpen = state.search.length >= 2;
  if (!state.search) {
    state.highlightVehicleKey = '';
    state.searchHighlightPlanId = '';
    state.searchNotice = '';
  }
  renderWorkshopPlanner();
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

function workshopQueueCardHtml(vehicle = {}, stage = workshopState().stage, dateKey = workshopState().date, rows = workshopLoadPlans()) {
  const key = vehicleKey(vehicle);
  const blocked = isPdcBlocked(vehicle);
  const parts = workshopPartsSummary(vehicle);
  const highlighted = workshopState().highlightVehicleKey === key;
  const hours = workshopCalculatedStageHours(vehicle, stage) || pmbBayHours(vehicle) || workshopDefaultBookingHours();
  const etaConstraint = workshopVehicleEtaConstraint(vehicle);
  const earliestQueueDate = etaConstraint.ok ? workshopDateKeyNotBefore(dateKey, etaConstraint.earliestDateKey) : dateKey;
  const bestSlot = etaConstraint.ok ? workshopBestStageSlot(stage, earliestQueueDate, hours, rows) : null;
  return `<article class="workshop-queue-card ${blocked ? 'is-blocked' : ''} ${highlighted ? 'is-search-match' : ''}" draggable="true" data-workshop-vehicle-key="${escapeHtml(key)}" data-workshop-job-vehicle="${escapeHtml(key)}" data-workshop-locate-key="${escapeHtml(key)}" title="Drag onto a bay, use Best slot, or use Schedule">
    <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')} · ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    ${etaConstraint.required ? `<small class="workshop-eta-line ${etaConstraint.ok ? '' : 'is-invalid'}">${escapeHtml(etaConstraint.ok ? `${etaConstraint.location} · earliest ${etaConstraint.earliestDateKey}` : `${etaConstraint.location} · correct missing/invalid ETA before booking`)}</small>` : ''}
    <small class="workshop-parts-line parts-${escapeHtml(parts.status)}">Parts: ${escapeHtml(parts.text)}</small>
    ${bestSlot ? `<small class="workshop-slot-hint">Best slot: ${escapeHtml(workshopSlotSummary(stage, bestSlot.bay, bestSlot.dateKey, bestSlot.startMinutes))}</small>` : ''}
    ${blocked ? '<em>STOPPAGE</em>' : ''}
    <div class="workshop-queue-actions">
      ${bestSlot ? `<button class="workshop-schedule-button best-slot" type="button" data-workshop-best-slot-vehicle="${escapeHtml(key)}" data-workshop-best-slot-stage="${escapeHtml(stage)}" data-workshop-best-slot-bay="${bestSlot.bay}" data-workshop-best-slot-date="${escapeHtml(bestSlot.dateKey)}" data-workshop-best-slot-start="${bestSlot.startMinutes}" data-workshop-best-slot-hours="${escapeHtml(hours)}">Best slot</button>` : ''}
      <button class="workshop-schedule-button" type="button" data-workshop-schedule-vehicle="${escapeHtml(key)}">Schedule</button>
    </div>
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
  const left = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const width = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const actualBay = pmbBayNumber(vehicle, entry.stage);
  const started = entry.stage === 'SUBLET' ? workshopEntryIsLive(entry) : Number(actualBay) === Number(entry.bay);
  const blocked = isPdcBlocked(vehicle);
  const overtime = workshopEntryIsOvertime(entry);
  const assigneeConflict = workshopEntryHasAssigneeConflict(entry, rows);
  const selected = workshopState().selectedPlanId === entry.id;
  const highlighted = workshopState().searchHighlightPlanId
    ? workshopState().searchHighlightPlanId === entry.id
    : workshopState().highlightVehicleKey === entry.vehicleKey;
  const parts = workshopPartsSummary(vehicle);
  const etaRisk = workshopEtaRiskForEntry(entry, vehicle);
  const draggable = entry.status !== 'completed';
  const assignee = cleanNavisionText(entry.assignee || '') || workshopBayMechanic(entry.stage, entry.bay) || '';
  const statusLabel = entry.status === 'completed' ? 'COMPLETED' : entry.status === 'stoppage' ? 'STOPPAGE' : entry.status === 'started' ? 'LIVE' : 'PLANNED';
  const classes = [blocked ? 'is-blocked' : '', started ? 'is-started' : '', overtime ? 'is-overtime' : '', etaRisk ? 'is-eta-risk' : '', segment.usesConfiguredOvertime ? 'uses-configured-overtime' : '', segment.historicalOnClosure ? 'historical-on-closure' : '', assigneeConflict ? 'has-assignee-conflict' : '', entry.status === 'stoppage' ? 'is-stoppage' : '', selected ? 'is-selected' : '', highlighted ? 'is-search-match' : '', segment.continuesFromPrevious ? 'continues-from-previous' : '', segment.continuesNext ? 'continues-next' : ''].filter(Boolean).join(' ');
  const conflictNote = assigneeConflict ? ` · WARNING: ${entry.assignee} is booked on another vehicle at this time` : '';
  return `<article class="workshop-plan-chip ${classes}" ${draggable ? 'draggable="true"' : ''} data-workshop-plan-id="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}" style="--plan-left:${left}%;--plan-width:${width}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · ${entry.hours}h total${conflictNote} · double-click for vehicle job${entry.status === 'completed' ? ' · completed history stays fixed' : entry.status === 'planned' ? ' · drag to reschedule' : ' · drag to move this live job safely'}`)}">
    <button type="button" data-workshop-select-plan="${escapeHtml(entry.id)}">
      <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')} · ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
      <small>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</small>
      <small>${escapeHtml(`${statusLabel}${assignee ? ` · ${assignee}` : ''}${segment.usesConfiguredOvertime ? ' · CONFIGURED OVERTIME' : ''}${segment.historicalOnClosure ? ' · HISTORICAL CLOSURE' : ''}`)}</small>
      <small>${escapeHtml(`${entry.hours}h · Parts ${parts.label}${parts.eta && !['issued', 'notrequired'].includes(parts.status) ? ` · ETA ${parts.eta}` : ''}`)}</small>
      ${etaRisk ? `<small class="workshop-eta-risk-label">ETA RISK · earliest ${escapeHtml(etaRisk.earliestDateKey)}</small>` : ''}
    </button>
    <span class="workshop-plan-resize" data-workshop-resize-plan="${escapeHtml(entry.id)}" title="Drag to change duration"></span>
  </article>`;
}

function workshopCompletedCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const actual = Number(entry.actualHours);
  const timeSummary = Number.isFinite(actual) ? `Actual ${actual}h · Est ${entry.hours}h` : workshopEntryTimeLabel(entry);
  const highlighted = workshopState().searchHighlightPlanId
    ? workshopState().searchHighlightPlanId === entry.id
    : workshopState().highlightVehicleKey === entry.vehicleKey;
  return `<button class="workshop-completed-card ${highlighted ? 'is-search-match' : ''}" type="button" data-workshop-select-plan="${escapeHtml(entry.id)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}">
    <strong>✓ ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small>${escapeHtml(entry.stage === 'SUBLET' ? 'Sublet' : `Bay ${entry.bay}`)} · ${escapeHtml(timeSummary)}</small>
  </button>`;
}

function workshopTimeAxisHtml() {
  const tickCount = Math.floor(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / 60);
  return Array.from({ length: tickCount + 1 }, (_, index) => {
    const left = ((index * 60) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    return `<span style="left:${left}%">${escapeHtml(workshopTimeLabelFromMinutes(index * 60))}</span>`;
  }).join('');
}

function workshopDropPreviewHtml({ vertical = false } = {}) {
  return `<div class="workshop-drop-preview${vertical ? ' is-vertical' : ''}" hidden aria-hidden="true"><span class="workshop-drop-preview-line"></span><span class="workshop-drop-preview-pill"></span></div>`;
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
        ${workshopDropPreviewHtml()}
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

function workshopCurrentDragPreview() {
  return app.workshopDragPreview || null;
}

function workshopSetDragPreview(preview = null) {
  app.workshopDragPreview = preview || null;
}

function workshopCurrentDropTarget() {
  return app.workshopDropTarget || null;
}

function workshopSetDropTarget(target = null) {
  app.workshopDropTarget = target || null;
}

function workshopClearDropTarget() {
  app.workshopDropTarget = null;
}

function workshopClearLanePreviews(scope = document) {
  scope.querySelectorAll('.workshop-drop-preview').forEach(preview => {
    preview.hidden = true;
    preview.style.removeProperty('--drop-preview-left');
    preview.style.removeProperty('--drop-preview-width');
    preview.style.removeProperty('--drop-preview-top');
    preview.style.removeProperty('--drop-preview-height');
    preview.querySelector('.workshop-drop-preview-pill')?.removeAttribute('data-preview-label');
  });
  scope.querySelectorAll('.workshop-bay-lane, .workshop-week-day-lane').forEach(lane => delete lane.dataset.workshopRequestedStartMinutes);
  workshopClearDropTarget();
}

function workshopHideLanePreview(lane) {
  const preview = lane?.querySelector('.workshop-drop-preview');
  if (!preview) return;
  preview.hidden = true;
}

function workshopPreviewLabel(minutes = 0, hours = 0) {
  const time = workshopTimeLabelFromMinutes(minutes);
  const duration = Number(hours || 0);
  return duration > 0 ? `${time} · ${duration}h` : time;
}

function workshopUpdateLanePreview(lane, startMinutes = 0) {
  const preview = lane?.querySelector('.workshop-drop-preview');
  if (!preview) return;
  const dragPreview = workshopCurrentDragPreview();
  const hours = Math.max(0.25, Number(dragPreview?.hours || workshopDefaultBookingHours()));
  const safeMinutes = workshopClampStartMinutes(startMinutes);
  const stage = lane.dataset.workshopDropStage || lane.dataset.workshopWeekDropStage || '';
  const bay = Number(lane.dataset.workshopDropBay || lane.dataset.workshopWeekDropBay || 0);
  const dateKey = lane.dataset.workshopWeekDropDate || workshopState().date;
  lane.dataset.workshopRequestedStartMinutes = String(safeMinutes);
  workshopSetDropTarget({ stage, bay, dateKey, startMinutes: safeMinutes });
  const label = workshopPreviewLabel(safeMinutes, hours);
  preview.hidden = false;
  if (preview.classList.contains('is-vertical')) {
    const height = Math.max((hours * 60 / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100, 8);
    preview.style.setProperty('--drop-preview-top', `${(safeMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%`);
    preview.style.setProperty('--drop-preview-height', `${Math.min(height, 100 - ((safeMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100))}%`);
  } else {
    const width = Math.max((hours * 60 / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100, 5);
    preview.style.setProperty('--drop-preview-left', `${(safeMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%`);
    preview.style.setProperty('--drop-preview-width', `${Math.min(width, 100 - ((safeMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100))}%`);
  }
  preview.querySelector('.workshop-drop-preview-pill')?.setAttribute('data-preview-label', label);
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

function workshopBookingNavigatorHtml(entry = null, plans = []) {
  if (!entry) return '';
  const vehicleIdentity = workshopPlanVehicleIdentity(entry);
  const bookings = workshopBookingsForEntry(plans, entry)
    .sort((a, b) => workshopEntryStart(a) - workshopEntryStart(b) || String(a.id || '').localeCompare(String(b.id || '')));
  if (bookings.length < 2) return '';
  const index = bookings.findIndex(plan => plan.id === entry.id);
  const previous = index > 0 ? bookings[index - 1] : null;
  const next = index >= 0 && index < bookings.length - 1 ? bookings[index + 1] : null;
  const state = workshopState();
  const notice = state.searchNotice || `This vehicle has ${bookings.length} bookings. Showing the selected booking.`;
  return `<nav class="workshop-booking-navigator" aria-label="Bookings for this vehicle">
    <span role="status">${escapeHtml(notice)}</span>
    <button type="button" class="small-button" data-workshop-booking-nav="${escapeHtml(previous?.id || '')}" data-workshop-booking-vehicle-identity="${escapeHtml(vehicleIdentity)}" ${previous ? '' : 'disabled'}>Previous booking</button>
    <label><span>All booking dates and times</span><select data-workshop-booking-jump data-workshop-booking-vehicle-identity="${escapeHtml(vehicleIdentity)}">${bookings.map(plan => {
      const meta = workshopBookingSearchMeta(plan);
      return `<option value="${escapeHtml(plan.id)}" ${plan.id === entry.id ? 'selected' : ''}>${escapeHtml(meta.date)} · ${escapeHtml(meta.time)} · ${escapeHtml(meta.station)} · ${escapeHtml(meta.bay)}</option>`;
    }).join('')}</select></label>
    <button type="button" class="small-button" data-workshop-booking-nav="${escapeHtml(next?.id || '')}" data-workshop-booking-vehicle-identity="${escapeHtml(vehicleIdentity)}" ${next ? '' : 'disabled'}>Next booking</button>
  </nav>`;
}

function workshopDetailPanelHtml(entry = null, plans = []) {
  const state = workshopState();
  const expandedForSelection = Boolean(entry) && !state.detailCollapsedForSelection;
  const expanded = state.detailPinnedOpen || state.detailManualOpen || expandedForSelection;
  const panelClass = expanded ? 'workshop-detail-panel is-expanded' : 'workshop-detail-panel is-collapsed';
  const toggleLabel = expanded ? 'Collapse Job details' : 'Expand Job details';
  const selectedVehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  const selectedLabel = selectedVehicle ? displayStockNumber(selectedVehicle) || vehicleJobcardNumber(selectedVehicle) || 'Selected booking' : '';
  return `<section class="${panelClass}" data-workshop-detail-panel>
    <header class="workshop-detail-summary">
      <div><strong>Job details</strong><span>${entry ? `${escapeHtml(selectedLabel)} selected` : 'Select a planned booking to view, edit or reschedule it.'}</span></div>
      <div class="workshop-detail-summary-actions">
        <button type="button" class="workshop-detail-pin${state.detailPinnedOpen ? ' is-active' : ''}" data-workshop-detail-pin aria-pressed="${state.detailPinnedOpen ? 'true' : 'false'}" title="Keep Job details open when selection is cleared">${state.detailPinnedOpen ? 'Pinned' : 'Pin'}</button>
        <button type="button" class="workshop-detail-toggle" data-workshop-detail-toggle aria-expanded="${expanded ? 'true' : 'false'}" aria-controls="workshop-detail-content" aria-label="${toggleLabel}" title="${toggleLabel}"><span aria-hidden="true">⌄</span></button>
      </div>
    </header>
    <div id="workshop-detail-content" class="workshop-detail-content" ${expanded ? '' : 'hidden'}>
      ${workshopBookingNavigatorHtml(entry, plans)}
      ${workshopDetailHtml(entry)}
    </div>
  </section>`;
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
  const stageAssignee = cleanNavisionText(entry.assignee || '') || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle) || '';
  const statusTone = completed ? 'success' : stopped ? 'warning' : started ? 'info' : 'neutral';
  const statusLabel = completed ? 'Completed' : stopped ? 'Stoppage' : started ? 'Live' : 'Planned';
  const previousBay = entry.stage !== 'SUBLET' && Number(entry.bay) > 1 ? Number(entry.bay) - 1 : 0;
  const nextBay = entry.stage !== 'SUBLET' && Number(entry.bay) < workshopStageBayCount(entry.stage) ? Number(entry.bay) + 1 : 0;
  const bestBaySlot = completed
    ? null
    : workshopBestStageSlot(entry.stage, workshopEntryDate(entry), entry.hours, workshopLoadPlans().filter(row => row.id !== entry.id), workshopMinuteOffset(workshopEntryStart(entry)));
  const bestBaySummary = bestBaySlot ? workshopSlotSummary(entry.stage, bestBaySlot.bay, bestBaySlot.dateKey, bestBaySlot.startMinutes) : '';
  return `<form class="workshop-job-detail" data-workshop-detail-form data-workshop-plan-form-id="${escapeHtml(entry.id)}">
    <div class="workshop-detail-identity">
      <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')} · ${escapeHtml(stationLabel)}${started ? ' · STARTED' : ' · PLANNED'}${overtime ? ' · OVERTIME' : ''}</span>
      <small class="workshop-detail-status-line"><span class="badge ${statusTone}">${statusLabel}</span>${stageAssignee ? ` <span class="workshop-inline-meta">${escapeHtml(entry.stage === 'SUBLET' ? `Provider ${stageAssignee}` : `Technician ${stageAssignee}`)}</span>` : ''}</small>
      <small>${stageLines.length ? `Imported ${escapeHtml(pmbStageLabel(entry.stage))} work: ${escapeHtml(stageLines.map(line => line.text).join(' · '))}` : `No imported ${escapeHtml(pmbStageLabel(entry.stage))} lines · time is manual/default`}</small>
      <small>Parts: ${escapeHtml(parts.text)}</small>
      <small>${escapeHtml(progress)}</small>
      ${bestBaySlot ? `<small class="workshop-slot-hint">Next open bay/time: ${escapeHtml(bestBaySummary)}</small>` : ''}
      ${assigneeConflict ? `<small class="workshop-assignee-warning">⚠ ${escapeHtml(entry.assignee)} is booked on another vehicle at this time.</small>` : ''}
    </div>
    <label><span>Start</span><input name="startAt" type="datetime-local" step="900" value="${escapeHtml(localValue)}" required ${completed || started ? 'disabled' : ''} /></label>
    <label><span>Planned hours</span><input name="hours" type="number" min="1" step="0.25" value="${escapeHtml(entry.hours)}" required ${completed ? 'disabled' : ''} /></label>
    <label><span>${entry.stage === 'SUBLET' ? 'Provider' : 'Technician'}</span><select name="assignee" ${completed ? 'disabled' : ''}>${workshopAssigneeOptions(entry.stage, entry.assignee || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle))}</select></label>
    <div class="workshop-detail-actions">
      ${completed ? '<span class="badge success">Completed</span>' : '<button class="primary" type="submit">Save plan</button>'}
      ${completed ? '' : `<button class="small-button" type="button" data-workshop-open-plan-week="${escapeHtml(entry.id)}">Week</button>`}
      ${completed || !previousBay ? '' : `<button class="small-button" type="button" data-workshop-quick-move-plan="${escapeHtml(entry.id)}" data-workshop-quick-move-stage="${escapeHtml(entry.stage)}" data-workshop-quick-move-bay="${previousBay}">← Bay ${escapeHtml(workshopPad(previousBay))}</button>`}
      ${completed || !nextBay ? '' : `<button class="small-button" type="button" data-workshop-quick-move-plan="${escapeHtml(entry.id)}" data-workshop-quick-move-stage="${escapeHtml(entry.stage)}" data-workshop-quick-move-bay="${nextBay}">Bay ${escapeHtml(workshopPad(nextBay))} →</button>`}
      ${completed || !bestBaySlot ? '' : `<button class="small-button" type="button" data-workshop-best-bay-plan="${escapeHtml(entry.id)}">Best bay/time</button>`}
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

function workshopLinkReadinessModalReportHtml(report = {}) {
  const labels = {
    linked: 'Linked',
    resolvable_unsaved: 'Resolvable but unsaved',
    missing_canonical_vehicle: 'Missing canonical vehicle',
    ambiguous: 'Ambiguous',
    conflicting: 'Conflicting',
    invalid_identity: 'Invalid identity',
  };
  const counts = report.counts || {};
  const canInspectIdentities = workshopVehicleLinkCanPersist();
  const reviewRows = canInspectIdentities
    ? (report.rows || []).filter(row => row.status !== 'linked').slice(0, 100)
    : [];
  return `<div class="workshop-link-readiness-summary">${Object.entries(labels).map(([key, label]) => `<div><span>${escapeHtml(label)}</span><strong>${Number(counts[key] || 0)}</strong></div>`).join('')}</div>
    <p><strong>${Number(report.total || 0)} browser-local operational vehicles reviewed.</strong> This readiness scan does not change location, workflow, bookings, identity fields or browser-local authority.</p>
    ${canInspectIdentities
      ? `<div class="workshop-link-readiness-table"><table><thead><tr><th>Vehicle</th><th>Status</th><th>Shared UUID / reason</th></tr></thead><tbody>${reviewRows.map(row => `<tr><td><strong>${escapeHtml(displayStockNumber(row.vehicle) || vehicleKey(row.vehicle) || 'No stock')}</strong><span>${escapeHtml(workshopVehicleLinkIdentityInput(row.vehicle).vin || workshopVehicleLinkIdentityInput(row.vehicle).toyotaOrder || 'No VIN/order')}</span></td><td>${escapeHtml(labels[row.status] || row.status)}</td><td>${escapeHtml(row.diagnostic.sharedUuid || workshopVehicleLinkVisibleReason(row.diagnostic))}</td></tr>`).join('') || '<tr><td colspan="3">All reviewed vehicles are already linked.</td></tr>'}</tbody></table></div>`
      : '<p class="warning-banner">Vehicle identities and shared UUIDs are restricted to operator and administrator review.</p>'}`;
}

async function workshopOpenVehicleLinkReadinessReview() {
  if (!workshopSharedModeActive()) {
    window.alert('Shared vehicle-link readiness is available only while the shared Workshop backend is active.');
    return;
  }
  if (!workshopVehicleLinkCanPersist()) {
    window.alert('Shared vehicle-link readiness is restricted to operators and administrators.');
    return;
  }
  const vehicles = typeof pdcSheetVehicles === 'function' ? pdcSheetVehicles() : [];
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-link-readiness-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-link-readiness-card"><button class="modal-close" type="button" data-workshop-link-readiness-close aria-label="Close">×</button><header><h2>Shared vehicle link readiness</h2><p data-workshop-link-readiness-progress>Reviewing 0 of ${vehicles.length} browser-local operational vehicles…</p></header><div data-workshop-link-readiness-body><div class="loading-state">Deterministic identity checks are running. No data is being changed.</div></div><div class="edit-actions"><button class="secondary" type="button" data-workshop-link-readiness-close>Close</button><button class="primary" type="button" data-workshop-link-readiness-save hidden>Save verified links</button></div></section>`;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  overlay.querySelectorAll('[data-workshop-link-readiness-close]').forEach(button => button.addEventListener('click', close));
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
  const progress = overlay.querySelector('[data-workshop-link-readiness-progress]');
  const body = overlay.querySelector('[data-workshop-link-readiness-body]');
  const saveButton = overlay.querySelector('[data-workshop-link-readiness-save]');
  const report = await workshopBuildVehicleLinkReadinessReport(vehicles, {
    onProgress: (done, total) => { if (progress) progress.textContent = `Reviewing ${done} of ${total} browser-local operational vehicles…`; },
  });
  if (!document.body.contains(overlay)) return;
  progress.textContent = `Readiness report generated ${new Date(report.generatedAt).toLocaleString('en-AU')}.`;
  body.innerHTML = workshopLinkReadinessModalReportHtml(report);
  const readyCount = Number(report.counts?.resolvable_unsaved || 0);
  saveButton.hidden = readyCount < 1 || !workshopVehicleLinkCanPersist();
  saveButton.textContent = `Save ${readyCount} verified link${readyCount === 1 ? '' : 's'}`;
  saveButton.addEventListener('click', async () => {
    if (!window.confirm(`Save ${readyCount} deterministic browser-local → shared UUID link${readyCount === 1 ? '' : 's'}?\n\nNo vehicle location, workflow step or booking will change.`)) return;
    saveButton.disabled = true;
    progress.textContent = `Saving 0 of ${readyCount} verified links…`;
    const result = await workshopPersistVehicleLinkReadinessBatch(report, {
      onProgress: (done, total) => { if (progress) progress.textContent = `Saving ${done} of ${total} verified links…`; },
    });
    if (!result.ok) {
      progress.textContent = result.rollbackReviewRequired
        ? `Batch stopped: ${result.cause || result.error}. Rollback could not safely overwrite ${result.saved} concurrent browser-local change${result.saved === 1 ? '' : 's'}; manual identity review is required before retrying.`
        : `Batch stopped and all newly written links were rolled back: ${result.error}. No unverified link was accepted.`;
      saveButton.disabled = Boolean(result.rollbackReviewRequired);
      return;
    }
    const refreshed = await workshopBuildVehicleLinkReadinessReport(vehicles);
    progress.textContent = `${result.saved} link${result.saved === 1 ? '' : 's'} saved and re-verified. No location, workflow or booking changed.`;
    body.innerHTML = workshopLinkReadinessModalReportHtml(refreshed);
    saveButton.hidden = true;
  });
}

function renderWorkshopPlanner() {
  if (workshopSharedModeActive()) workshopSyncConfigFromSharedSettings();
  const root = document.querySelector('#workshop-planner-root');
  if (!root) return;
  const state = workshopState();
  const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  const requestedStage = dedicatedStage || normalizePmbStage(app.pendingWorkshopStage || '');
  if (WORKSHOP_STAGE_SEQUENCE.includes(requestedStage)) {
    state.stage = requestedStage;
    workshopClearSelectedDetail(state);
    app.pendingWorkshopStage = '';
  }
  let plans = dedicatedStage ? workshopLoadPlans() : workshopCascadeAndSave(workshopSyncCompletedPlans());
  if (state.selectedPlanId && !plans.some(entry => entry.id === state.selectedPlanId)) workshopClearSelectedDetail(state);
  const selected = plans.find(entry => entry.id === state.selectedPlanId) || null;
  const stage = dedicatedStage || (WORKSHOP_VISIBLE_STAGE_SEQUENCE.includes(state.stage) ? state.stage : 'FABRICATION');
  const dateKey = state.date;
  const activePlans = plans.filter(entry => entry.stage === stage && entry.status !== 'completed');
  const plannedKeys = new Set(activePlans.map(entry => entry.vehicleKey));
  const stageVehicleList = workshopPlannerVehiclesForStage(stage);
  const queue = stageVehicleList.filter(vehicle => !plannedKeys.has(vehicleKey(vehicle)));
  const completed = plans.filter(entry => {
    if (entry.stage !== stage || entry.status !== 'completed') return false;
    const completedDate = parseIsoTimestamp(entry.completedAt || '');
    return workshopDateKey(completedDate || workshopEntryStart(entry)) === dateKey;
  });
  const todaysPlans = activePlans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
  const assigneeConflicts = todaysPlans.filter(entry => workshopEntryHasAssigneeConflict(entry, plans)).length;
  const stageVehicleCounts = dedicatedStage
    ? new Map([[stage, stageVehicleList.length]])
    : new Map(WORKSHOP_VISIBLE_STAGE_SEQUENCE.map(value => [value, value === stage ? stageVehicleList.length : workshopStageVehicles(value).length]));
  const stageTabs = dedicatedStage ? '' : WORKSHOP_VISIBLE_STAGE_SEQUENCE.map(value => `<button type="button" class="workshop-stage-tab ${value === stage ? 'active' : ''}" data-workshop-stage="${escapeHtml(value)}"><span>${escapeHtml(pmbStageLabel(value))}</span><strong>${stageVehicleCounts.get(value)}</strong></button>`).join('');
  const sharedModeActive = workshopSharedModeActive();
  const sharedBanner = sharedModeActive ? workshopConnectionBannerHtml() : '';
  root.innerHTML = `<div class="workshop-planner${dedicatedStage ? ' workshop-planner-dedicated' : ''}" data-planner-stage="${escapeHtml(stage)}">
    ${sharedBanner}
    <header class="workshop-planner-header">
      <div>${dedicatedStage ? '<button class="small-button workshop-back-control" type="button" data-workshop-back-control>← Back to Control Board</button>' : ''}<h2>${escapeHtml(dedicatedStage ? `${pmbStageLabel(stage)} planner` : 'Workshop bay planner')}</h2><p>Monday–Friday, 8:00am–4:00pm. Long jobs carry into the next workday; overlapping bay bookings are blocked.</p></div>
      <div class="workshop-date-controls">
        <button class="small-button" type="button" data-workshop-date-shift="-1">‹ Previous</button>
        <input type="date" data-workshop-date aria-label="Workshop planner date" value="${escapeHtml(dateKey)}" />
        <button class="small-button" type="button" data-workshop-date-shift="1">Next ›</button>
        <button class="small-button" type="button" data-workshop-today>Today</button>
        <button class="small-button" type="button" data-workshop-weekly-view>Weekly view</button>
        ${sharedModeActive && workshopVehicleLinkCanPersist() ? '<button class="small-button" type="button" data-workshop-link-readiness>Review shared links</button>' : ''}
        <button class="small-button warning-button" type="button" data-workshop-parts-warning>Draft next-day parts warning</button>
      </div>
    </header>
    <div class="workshop-date-summary"><strong>${escapeHtml(workshopDateLabel(dateKey))}</strong><span>${todaysPlans.length} planned · ${completed.length} completed · ${queue.length} waiting${assigneeConflicts ? ` · ⚠ ${assigneeConflicts} mechanic clash${assigneeConflicts === 1 ? '' : 'es'}` : ''} · Saved automatically${state.lastSavedAt ? ` ${escapeHtml(new Date(state.lastSavedAt).toLocaleTimeString('en-AU', { hour: 'numeric', minute: '2-digit' }))}` : ''}</span><div class="workshop-status-legend"><span class="planned">Planned</span><span class="live">Live</span><span class="stoppage">Stoppage</span><span class="completed">Completed</span></div></div>
    ${workshopSearchControlHtml(state.search || '', plans)}
    ${stageTabs ? `<nav class="workshop-stage-tabs" aria-label="Workshop departments">${stageTabs}</nav>` : ''}
    ${workshopDetailPanelHtml(selected, plans)}
    <div class="workshop-board-shell">
      <aside class="workshop-side-panel workshop-waiting-panel">
        <div class="workshop-side-heading"><strong>Awaiting schedule</strong><span>${queue.length}</span></div>
        <div class="workshop-unallocated-drop" data-workshop-unallocated-drop><strong>Return to Unallocated</strong><span>Planned or live: choose Just move or Stoppage</span></div>
        <div class="workshop-side-list">${queue.map(vehicle => workshopQueueCardHtml(vehicle, stage, dateKey, plans)).join('') || '<div class="workshop-empty">No unscheduled vehicles in this department.</div>'}</div>
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
    <div class="workshop-board-note">How to use: drag a waiting vehicle or planned booking onto the exact bay/time you want. If that spot overlaps only queued planned work, the planner keeps your dropped booking there and offers to push the later queue back-to-back behind it. Use Best slot for the fastest bay suggestion, or use Schedule for a specific date and time. If a day is full, automatic sequencing continues on the next workday. Live overlap stays blocked, while live jobs can still be moved safely with the bay quick controls or drag/drop. The red current-time line stays visible on the planner and clamps to the workshop edge outside work hours. Double-click any vehicle to open its job.</div>
  </div>`;
  bindWorkshopPlanner(root);
  updateWorkshopNowLine(root);
  setupWorkshopPlannerClock();
  workshopScrollToHighlightedVehicle(root);
}

function bindWorkshopPlanner(root) {
  root.querySelector('[data-workshop-back-control]')?.addEventListener('click', () => showView('workflow'));
  root.querySelectorAll('[data-workshop-stage]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    state.stage = button.dataset.workshopStage;
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-date-shift]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    const current = workshopDateFromKey(state.date) || new Date();
    state.date = workshopDateKey(workshopShiftWorkday(current, Number(button.dataset.workshopDateShift)));
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    if (!workshopRefreshDedicatedDate(state.date)) renderWorkshopPlanner();
  }));
  root.querySelector('[data-workshop-today]')?.addEventListener('click', () => {
    const state = workshopState();
    state.date = workshopDateKey(workshopCoerceWorkDate(new Date(), 1));
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    if (!workshopRefreshDedicatedDate(state.date)) renderWorkshopPlanner();
  });
  root.querySelector('[data-workshop-date]')?.addEventListener('change', event => {
    const selected = workshopDateFromKey(event.target.value);
    if (!selected) return;
    const coerced = workshopCoerceWorkDate(selected, 1);
    if (workshopDateKey(coerced) !== event.target.value) window.alert('Workshop boards run Monday to Friday. The date has been moved to the next workday.');
    const state = workshopState();
    state.date = workshopDateKey(coerced);
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    if (!workshopRefreshDedicatedDate(state.date)) renderWorkshopPlanner();
  });
  const searchInput = root.querySelector('[data-workshop-search]');
  searchInput?.addEventListener('focus', event => {
    const state = workshopState();
    state.searchOpen = cleanNavisionText(event.currentTarget.value || '').length >= 2;
    const results = root.querySelector('#workshop-booking-search-results');
    if (results && state.searchOpen) results.hidden = false;
  });
  searchInput?.addEventListener('input', event => {
    workshopState().search = event.target.value;
    window.clearTimeout(app.workshopPlannerSearchTimer);
    app.workshopPlannerSearchTimer = window.setTimeout(() => workshopRevealSearchMatch(event.target.value), 180);
  });
  searchInput?.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      event.preventDefault();
      const state = workshopState();
      state.searchOpen = false;
      const results = root.querySelector('#workshop-booking-search-results');
      if (results) results.hidden = true;
      event.currentTarget.setAttribute('aria-expanded', 'false');
      return;
    }
    if (event.key !== 'Enter') return;
    event.preventDefault();
    window.clearTimeout(app.workshopPlannerSearchTimer);
    const state = workshopState();
    const matches = workshopSearchMatches(event.currentTarget.value);
    if (matches.length === 1 && matches[0].bookings.length) {
      workshopSelectSearchBooking(matches[0].bookings[0].id, matches[0].vehicleIdentity);
      return;
    }
    workshopRevealSearchMatch(event.currentTarget.value);
  });
  root.querySelector('[data-workshop-search-clear]')?.addEventListener('click', () => workshopRevealSearchMatch(''));
  root.querySelectorAll('[data-workshop-search-booking-id]').forEach(button => button.addEventListener('click', () => {
    workshopSelectSearchBooking(button.dataset.workshopSearchBookingId, button.dataset.workshopSearchVehicleIdentity);
    workshopScrollToHighlightedVehicle(root);
  }));
  root.querySelector('[data-workshop-detail-toggle]')?.addEventListener('click', () => {
    const state = workshopState();
    const selected = workshopLoadPlans().some(entry => entry.id === state.selectedPlanId);
    if (selected) state.detailCollapsedForSelection = !state.detailCollapsedForSelection;
    else state.detailManualOpen = !state.detailManualOpen;
    renderWorkshopPlanner();
  });
  root.querySelector('[data-workshop-detail-pin]')?.addEventListener('click', () => {
    const state = workshopState();
    state.detailPinnedOpen = !state.detailPinnedOpen;
    if (state.detailPinnedOpen) state.detailManualOpen = true;
    workshopSaveDetailSessionPreference(state.detailPinnedOpen);
    renderWorkshopPlanner();
  });
  root.querySelectorAll('[data-workshop-booking-nav]').forEach(button => button.addEventListener('click', () => {
    if (button.dataset.workshopBookingNav) workshopOpenBookingById(button.dataset.workshopBookingNav, button.dataset.workshopBookingVehicleIdentity);
  }));
  root.querySelector('[data-workshop-booking-jump]')?.addEventListener('change', event => workshopOpenBookingById(event.currentTarget.value, event.currentTarget.dataset.workshopBookingVehicleIdentity));
  root.querySelector('[data-workshop-weekly-view]')?.addEventListener('click', () => {
    const selected = workshopLoadPlans().find(entry => entry.id === workshopState().selectedPlanId && entry.stage === workshopState().stage);
    openWorkshopWeeklyView(workshopState().stage, Number(selected?.bay) || 1, workshopState().date);
  });
  root.querySelector('[data-workshop-link-readiness]')?.addEventListener('click', () => { void workshopOpenVehicleLinkReadinessReview(); });
  root.querySelector('[data-workshop-parts-warning]')?.addEventListener('click', draftWorkshopNextDayFittingWarningEmail);
  root.querySelectorAll('[data-workshop-bay-mechanic-stage]').forEach(select => select.addEventListener('change', () => saveWorkshopBayMechanic(select.dataset.workshopBayMechanicStage, Number(select.dataset.workshopBayMechanicNumber), select.value)));
  root.querySelectorAll('[data-workshop-weekly-stage]').forEach(button => button.addEventListener('click', () => openWorkshopWeeklyView(button.dataset.workshopWeeklyStage, Number(button.dataset.workshopWeeklyBay), workshopState().date)));
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'copy';
    event.dataTransfer.setData('application/x-workshop-vehicle-key', card.dataset.workshopVehicleKey);
    event.dataTransfer.setData('text/plain', card.dataset.workshopVehicleKey);
    const vehicle = workshopVehicle(card.dataset.workshopVehicleKey);
    workshopSetDragPreview({
      type: 'queue',
      hours: workshopCalculatedStageHours(vehicle, workshopState().stage) || pmbBayHours(vehicle) || workshopDefaultBookingHours(),
    });
  }));
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(root), 0);
  }));
  root.querySelectorAll('[data-workshop-schedule-vehicle]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openWorkshopScheduleModal(button.dataset.workshopScheduleVehicle, workshopState().stage, workshopState().date);
  }));
  root.querySelectorAll('[data-workshop-best-slot-vehicle]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    scheduleWorkshopVehicle({
      vehicleKeyValue: button.dataset.workshopBestSlotVehicle,
      stage: button.dataset.workshopBestSlotStage,
      bay: Number(button.dataset.workshopBestSlotBay),
      dateKey: button.dataset.workshopBestSlotDate,
      startMinutes: Number(button.dataset.workshopBestSlotStart),
      hoursValue: Number(button.dataset.workshopBestSlotHours),
    });
  }));
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', chip.dataset.workshopPlanId);
    const entry = workshopLoadPlans().find(row => row.id === chip.dataset.workshopPlanId);
    workshopSetDragPreview({ type: 'plan', hours: workshopClampDurationHours(entry?.hours) || workshopDefaultBookingHours() });
  }));
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(root), 0);
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
    workshopSelectPlanForDetail(button.dataset.workshopSelectPlan);
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-open-plan]').forEach(button => button.addEventListener('click', () => {
    const state = workshopState();
    state.date = button.dataset.workshopOpenDate;
    workshopSelectPlanForDetail(button.dataset.workshopOpenPlan);
    workshopSaveView(state);
    renderWorkshopPlanner();
  }));
  root.querySelectorAll('[data-workshop-open-plan-week]').forEach(button => button.addEventListener('click', event => {
    const plan = workshopLoadPlans().find(entry => entry.id === event.currentTarget.dataset.workshopOpenPlanWeek);
    if (!plan) return;
    openWorkshopWeeklyView(plan.stage, Number(plan.bay) || 1, workshopEntryDate(plan) || workshopState().date);
  }));
  root.querySelectorAll('[data-workshop-quick-move-plan]').forEach(button => button.addEventListener('click', () => {
    const plan = workshopLoadPlans().find(entry => entry.id === button.dataset.workshopQuickMovePlan);
    if (!plan) return;
    void moveWorkshopDroppedPlan(plan.id, button.dataset.workshopQuickMoveStage, Number(button.dataset.workshopQuickMoveBay), workshopEntryDate(plan), workshopMinuteOffset(workshopEntryStart(plan)));
  }));
  root.querySelectorAll('[data-workshop-best-bay-plan]').forEach(button => button.addEventListener('click', event => {
    const plan = workshopLoadPlans().find(entry => entry.id === event.currentTarget.dataset.workshopBestBayPlan);
    if (!plan) return;
    const bestSlot = workshopBestStageSlot(plan.stage, workshopEntryDate(plan), plan.hours, workshopLoadPlans().filter(row => row.id !== plan.id), workshopMinuteOffset(workshopEntryStart(plan)));
    if (!bestSlot) return;
    const currentDate = workshopEntryDate(plan);
    const currentMinutes = workshopMinuteOffset(workshopEntryStart(plan));
    if (bestSlot.bay === Number(plan.bay) && bestSlot.dateKey === currentDate && bestSlot.startMinutes === currentMinutes) {
      window.alert('This job is already in the earliest open bay/time for its current stage.');
      return;
    }
    void moveWorkshopDroppedPlan(plan.id, plan.stage, bestSlot.bay, bestSlot.dateKey, bestSlot.startMinutes);
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
    const rect = lane.getBoundingClientRect();
    const requestedStartMinutes = workshopClampStartMinutes(((event.clientX - rect.left) / Math.max(1, rect.width)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
    workshopUpdateLanePreview(lane, requestedStartMinutes);
  });
  lane.addEventListener('dragleave', event => {
    if (!lane.contains(event.relatedTarget)) {
      lane.classList.remove('drag-over');
      workshopHideLanePreview(lane);
    }
  });
  lane.addEventListener('drop', event => {
    event.preventDefault();
    lane.classList.remove('drag-over');
    const rect = lane.getBoundingClientRect();
    const fallbackStartMinutes = workshopClampStartMinutes(((event.clientX - rect.left) / Math.max(1, rect.width)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
    const rememberedTarget = workshopCurrentDropTarget();
    const targetStage = lane.dataset.workshopDropStage;
    const targetBay = Number(lane.dataset.workshopDropBay);
    const targetDate = workshopState().date;
    const previewMinutes = Number(lane.dataset.workshopRequestedStartMinutes);
    workshopClearLanePreviews(lane);
    const requestedStartMinutes = rememberedTarget
      && rememberedTarget.stage === targetStage
      && Number(rememberedTarget.bay) === targetBay
      && rememberedTarget.dateKey === targetDate
      && Number.isFinite(Number(rememberedTarget.startMinutes))
      ? workshopClampStartMinutes(Number(rememberedTarget.startMinutes))
      : Number.isFinite(previewMinutes)
        ? previewMinutes
        : fallbackStartMinutes;
    const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
    const vehicleKeyValue = event.dataTransfer.getData('application/x-workshop-vehicle-key') || event.dataTransfer.getData('text/plain');
    const stage = targetStage;
    const bay = targetBay;
    const dateKey = targetDate;
    const startMinutes = requestedStartMinutes;
    if (planId) {
      void moveWorkshopDroppedPlan(planId, stage, bay, dateKey, startMinutes, { preferRequestedTime: true });
      return;
    }
    scheduleWorkshopVehicle({ planId, vehicleKeyValue, stage, bay, dateKey, startMinutes, preferRequestedTime: true });
  });
}

async function saveWorkshopBayMechanic(stage = '', bay = 0, value = '') {
  const assignee = cleanNavisionText(value || '');
  if (workshopSharedModeActive()) {
    // Independent-review remediation (finding 2): the bay default
    // technician is Stage 2A shared, database-authoritative lookup
    // data (workshop_bays.default_technician_id via the protected
    // set_bay_default_technician RPC) -- it must NOT be saved to
    // localStorage as a parallel, potentially-divergent source of
    // truth. Resolve the selected name to a stable technician ID via
    // the reference table (never the booking-snapshot scan, which can
    // miss a technician who has never been assigned to anything yet)
    // and call the protected RPC directly. localStorage is untouched
    // by this path entirely.
    const bayRef = workshopSharedBayRef(stage, bay);
    if (!bayRef) {
      window.alert('This bay could not be matched to a shared bay record, so the default technician could not be saved. Reload the page and try again.');
      return;
    }
    let technicianId = null;
    if (assignee) {
      const technicianRef = workshopReferenceTechnicianRef(assignee);
      if (!technicianRef) {
        window.alert(`"${assignee}" could not be matched to an active technician in the shared roster. The bay default was not changed.`);
        return;
      }
      technicianId = technicianRef.technicianId;
    }
    const service = window.__workshopReferenceDataService;
    if (!service || typeof service.setBayDefaultTechnician !== 'function') {
      window.alert('The shared reference-data service is not available, so the bay default could not be saved.');
      return;
    }
    const result = await service.setBayDefaultTechnician(bayRef.id, bayRef.version, technicianId);
    if (!result || !result.ok) {
      window.alert(`The bay default technician could not be saved (${(result && result.error) || 'unknown error'}). The shared data will refresh to show the current authoritative value.`);
      renderWorkshopPlanner();
      return;
    }

    // Backfilling the new default onto currently-unassigned planned
    // bookings in this bay remains a separate, per-booking operational
    // change through the protected assign_booking_technician RPC (one
    // booking at a time, with each booking's own expected version) --
    // unrelated to the bay-default write itself, which is now
    // complete and authoritative above.
    if (assignee && technicianId) {
      const currentPlans = workshopLoadPlans();
      const targets = currentPlans.filter(entry => entry.stage === normalizePmbStage(stage) && Number(entry.bay) === Number(bay) && entry.status === 'planned' && !entry.assignee);
      let skipped = 0;
      for (const entry of targets) {
        const assignResult = await window.__workshopSharedActions.assignBookingTechnician({
          bookingId: entry.sharedBookingId || entry.id,
          expectedVersion: entry.sharedVersion,
          technicianId,
        });
        if (!assignResult || !assignResult.ok) skipped += 1;
      }
      renderWorkshopPlanner();
      if (skipped) window.alert(`${assignee} was saved as the bay default, but ${skipped} overlapping booking${skipped === 1 ? ' was' : 's were'} left unassigned because that mechanic is already booked elsewhere.`);
      return;
    }
    renderWorkshopPlanner();
    return;
  }

  // Legacy local (non-shared) planner mode only, below this point:
  // the browser-local WORKSHOP_BAY_SETUP_STORAGE_KEY mapping remains
  // the only available store, since there is no shared database to
  // write to in this mode.
  const setup = workshopLoadBaySetup();
  const key = workshopBaySetupKey(stage, bay);
  if (assignee) setup[key] = assignee;
  else delete setup[key];
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
  if (workshopSharedModeActive()) {
    let reason = null;
    if (entry.status !== 'planned') {
      const result = await workshopReturnChoiceModal(entry, vehicle);
      if (!result) return;
      if (result.choice === 'stoppage') reason = result.reason;
    } else if (!window.confirm(`Return ${displayStockNumber(vehicle) || 'this vehicle'} to the unscheduled ${pmbStageLabel(entry.stage)} queue?\n\nThe vehicle stays in PMB and is not deleted.`)) {
      return;
    }
    await workshopDispatchSharedAction('returnWorkToQueue', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
      reason,
    });
    return;
  }
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

function workshopFirstAvailableStartMinutes(stage = '', bay = 1, dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0) {
  const normalizedStage = normalizePmbStage(stage);
  const duration = workshopClampDurationHours(hours);
  const firstStart = workshopClampStartMinutes(notBeforeMinutes);
  for (let startMinutes = firstStart; startMinutes < WORKSHOP_PLANNER_CONFIG.dayLengthMinutes; startMinutes += WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes) {
    const candidate = {
      id: '__availability_check__',
      vehicleKey: '__availability_check__',
      stage: normalizedStage,
      bay: Number(bay),
      startAt: workshopDateAtOffset(dateKey, startMinutes).toISOString(),
      hours: duration,
      status: 'planned',
    };
    if (workshopNewBookingValidation(candidate).ok && !workshopHasConflict(candidate, rows)) return startMinutes;
  }
  return null;
}

function workshopFirstAvailableStartSlot(stage = '', bay = 1, dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0, maxWorkdays = 260) {
  const requestedDate = workshopDateFromKey(dateKey) || new Date();
  let workDate = workshopCoerceWorkDate(requestedDate, 1);
  for (let dayIndex = 0; dayIndex < Math.max(1, Number(maxWorkdays) || 260); dayIndex += 1) {
    const candidateDateKey = workshopDateKey(workDate);
    const firstMinutes = dayIndex === 0 ? notBeforeMinutes : 0;
    const startMinutes = workshopFirstAvailableStartMinutes(stage, bay, candidateDateKey, hours, rows, firstMinutes);
    if (startMinutes !== null) return { dateKey: candidateDateKey, startMinutes };
    workDate = workshopNextWorkdayDate(workDate);
  }
  return null;
}

async function moveWorkshopLivePlan(planId = '', stage = '', bay = 0, dateKey = '', startMinutes = 0) {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return false;
  if (!['started', 'stoppage'].includes(entry.status)) return false;
  if (workshopSharedModeActive()) {
    const nextStage = normalizePmbStage(stage);
    const nextBay = Number(bay);
    // Stage 2A: block moving into a DIFFERENT bay the shared reference
    // service reports as inactive. Moving within the SAME bay (e.g. a
    // time-only drag) is never blocked by this check.
    const bayIsChanging = nextStage !== normalizePmbStage(entry.stage) || nextBay !== Number(entry.bay);
    if (bayIsChanging) {
      // Independent-review remediation (finding 8): fail CLOSED here
      // -- block the move for 'inactive', 'unavailable' (reference
      // data not loaded), and 'unknown' (no matching bay row), not
      // only for a confirmed-inactive bay. Only a confirmed 'active'
      // status may proceed.
      const availability = workshopBayAvailabilityStatus(nextStage, nextBay);
      if (availability !== 'active') {
        const messages = {
          inactive: 'This bay is currently marked inactive and cannot accept new bookings. Choose a different bay.',
          unavailable: 'The shared bay reference data is still loading (or unavailable). Try again in a moment before moving this job to a new bay.',
          unknown: 'This bay could not be matched to a known shared bay record, so a new booking cannot be placed here. Choose a different bay.',
        };
        window.alert(messages[availability] || 'This bay is not currently available for new bookings.');
        return false;
      }
    }
    const nextStart = workshopDateAtOffset(dateKey, startMinutes).toISOString();
    const candidate = {
      ...entry,
      stage: nextStage,
      bay: nextBay,
      startAt: nextStart,
      technicianId: workshopTechnicianIdForEntry(entry),
    };
    if (!workshopRequireSchedulableCandidate(candidate)) return false;
    const requestedLabel = `${pmbStageLabel(nextStage)} ${nextStage === 'SUBLET' ? 'provider row' : `Bay ${nextBay}`} · ${workshopEntryTimeLabel(candidate)}`;
    if (!window.confirm(`Move this live workshop job to ${requestedLabel}?\n\nThis updates the live bay allocation and keeps the job started/stoppage history.`)) return false;
    const result = await workshopDispatchSharedAction('moveBooking', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
      stageCode: nextStage,
      bayNumber: nextBay,
      scheduledStartAt: nextStart,
    });
    return !!(result && result.ok);
  }
  if (!workshopRequireOperatorProfile()) return false;
  const nextStage = normalizePmbStage(stage);
  const nextBay = Number(bay);
  const nextStart = workshopDateAtOffset(dateKey, startMinutes).toISOString();
  const requestedLabel = `${pmbStageLabel(nextStage)} ${nextStage === 'SUBLET' ? 'provider row' : `Bay ${nextBay}`} · ${workshopEntryTimeLabel({ ...entry, stage: nextStage, bay: nextBay, startAt: nextStart })}`;
  if (!window.confirm(`Move this live workshop job to ${requestedLabel}?\n\nThis updates the live bay allocation and keeps the job started/stoppage history.`)) return false;
  const candidate = {
    ...entry,
    stage: nextStage,
    bay: nextBay,
    startAt: nextStart,
    updatedAt: nowIsoString(),
  };
  const otherRows = rows.filter(row => row.id !== candidate.id);
  let plannedRowsAfterShift = null;
  if (workshopHasConflict(candidate, otherRows)) {
    const shifted = workshopShiftTrailingPlannedRows(candidate, otherRows);
    if (!shifted) {
      if (!workshopRequireNoBayConflict(candidate, otherRows)) return false;
      return false;
    }
    plannedRowsAfterShift = shifted;
  }
  if (!plannedRowsAfterShift && !workshopRequireNoBayConflict(candidate, otherRows)) return false;
  const conflictCheckRows = plannedRowsAfterShift ? plannedRowsAfterShift.rows.filter(row => row.id !== candidate.id) : otherRows;
  if (!workshopRequireAvailableAssignee(candidate, conflictCheckRows)) return false;
  if (!workshopConfirmOtherDepartmentPlans(candidate, rows)) return false;
  const baseRows = plannedRowsAfterShift
    ? rows.map(row => plannedRowsAfterShift.moved.find(item => item.id === row.id) || row)
    : rows;
  const nextRows = workshopCascadePlans(baseRows.map(row => row.id === entry.id ? candidate : row)).rows;
  const auditDetails = {
    from: `${pmbStageLabel(entry.stage)} ${entry.stage === 'SUBLET' ? 'provider row' : `Bay ${entry.bay}`} · ${workshopEntryTimeLabel(entry)}`,
    to: requestedLabel,
    status: entry.status,
    assignee: candidate.assignee || 'Unassigned',
  };
  let persisted = false;
  if (candidate.stage === 'SUBLET') {
    persisted = workshopPersistVehiclePlanAction(
      'Move live Sublet workshop job',
      nextRows,
      vehicle,
      {
        pdcLocation: 'PMB',
        manualLocation: 'PMB',
        pdcLocationLocked: true,
        pmbStage: 'SUBLET',
        pmbStageUpdatedAt: nowIsoString(),
        pmbBayScheduledStartAt: candidate.startAt,
        pmbBayEstimatedHours: String(candidate.hours),
        pmbSubletProvider: cleanNavisionText(candidate.assignee || ''),
      },
      'Live workshop job moved',
      auditDetails,
    );
  } else {
    persisted = await assignPmbVehicleToBay(entry.vehicleKey, candidate.stage, candidate.bay, candidate.startAt, {
      keys: [WORKSHOP_PLAN_STORAGE_KEY],
      afterAssign: assignedVehicle => {
        if (!saveVehicleEdits(entry.vehicleKey, {
          pmbBayScheduledStartAt: candidate.startAt,
          pmbBayEstimatedHours: String(candidate.hours),
          pmbBayMechanic: cleanNavisionText(candidate.assignee || ''),
        }, { render: false })) throw new Error('The workshop move details could not be saved.');
        workshopSavePlans(nextRows);
        recordVehicleAudit(assignedVehicle, 'Live workshop job moved', auditDetails);
      },
    });
  }
  if (!persisted) return false;
  workshopState().selectedPlanId = candidate.id;
  workshopState().date = workshopEntryDate(candidate);
  workshopSaveView(workshopState());
  renderWorkshopPlanner();
  return true;
}
function moveWorkshopDroppedPlan(planId = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, { preferRequestedTime = false } = {}) {
  const entry = workshopLoadPlans().find(row => row.id === planId);
  if (!entry) return Promise.resolve(false);
  if (entry.status === 'completed') {
    window.alert('Completed workshop jobs stay fixed in history.');
    return Promise.resolve(false);
  }
  if (entry.status === 'planned') return Promise.resolve(scheduleWorkshopVehicle({ planId, stage, bay, dateKey, startMinutes, preferRequestedTime }));
  return moveWorkshopLivePlan(planId, stage, bay, dateKey, startMinutes);
}

function workshopScheduleTimeOptions(selectedMinutes = 0) {
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  return Array.from({ length: Math.ceil(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / increment) }, (_, index) => index * increment)
    .map(minutes => `<option value="${minutes}"${minutes === Number(selectedMinutes) ? ' selected' : ''}>${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</option>`)
    .join('');
}

function openWorkshopScheduleModal(vehicleKeyValue = '', stage = '', dateKey = '') {
  const normalizedStage = normalizePmbStage(stage);
  const vehicle = workshopVehicle(vehicleKeyValue);
  if (!vehicle || !WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return;
  const etaConstraint = workshopVehicleEtaConstraint(vehicle);
  if (etaConstraint.required && !etaConstraint.ok) {
    workshopRequireEtaSchedule(vehicle, '');
    return;
  }
  const hours = workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || workshopDefaultBookingHours();
  const bay = 1;
  const selectedDate = workshopDateKeyNotBefore(workshopDateKey(workshopCoerceWorkDate(workshopDateFromKey(dateKey) || new Date(), 1)), etaConstraint.earliestDateKey);
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
        <label><span>Date</span><input name="date" type="date" value="${escapeHtml(scheduledDate)}" ${etaConstraint.earliestDateKey ? `min="${escapeHtml(etaConstraint.earliestDateKey)}"` : ''} required></label>
        <label><span>Start time</span><select name="startMinutes">${workshopScheduleTimeOptions(startMinutes)}</select></label>
        <label><span>Planned hours</span><input name="hours" type="number" min="1" step="0.25" value="${escapeHtml(workshopClampDurationHours(hours))}" required></label>
        <label><span>${normalizedStage === 'SUBLET' ? 'Provider' : 'Technician'}</span><select name="assignee">${workshopAssigneeOptions(normalizedStage, workshopBayMechanic(normalizedStage, bay) || pmbBayMechanic(vehicle))}</select></label>
      </div>
      <p class="workshop-schedule-note">Later bookings in this bay move automatically, preserving their order and duration and skipping non-working days.${etaConstraint.required ? ` ${escapeHtml(etaConstraint.location)} earliest permitted booking date: ${escapeHtml(etaConstraint.earliestDateKey)}.` : ''}</p>
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
  overlay.querySelector('[data-workshop-schedule-form]').addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const selected = workshopDateFromKey(form.elements.date.value);
    if (!selected || !workshopIsWorkday(selected)) {
      window.alert('Choose a Monday-to-Friday workshop date.');
      return;
    }
    const requestedStartMinutes = Number(form.elements.startMinutes.value);
    const scheduled = await scheduleWorkshopVehicle({
      vehicleKeyValue,
      stage: normalizedStage,
      bay: Number(form.elements.bay.value),
      dateKey: workshopDateKey(selected),
      startMinutes: requestedStartMinutes,
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

async function extendWorkshopPlan(planId = '', additionalHours = 0) {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const delta = Number(additionalHours);
  if (!entry || entry.status === 'completed' || !Number.isFinite(delta) || delta <= 0) return false;
  if (workshopSharedModeActive()) {
    const nextHours = workshopClampDurationHours(Number(entry.hours || 0) + delta);
    const candidate = {
      ...entry,
      hours: nextHours,
      technicianId: workshopTechnicianIdForEntry(entry),
    };
    if (!workshopRequireSchedulableCandidate(candidate)) return false;
    const shiftMinutes = Math.round(delta * 60);
    const result = await workshopDispatchSharedAction('cascadeSchedule', {
      operation: 'extend',
      targetId: entry.sharedBookingId || entry.id,
      targetExpectedVersion: entry.sharedVersion,
      stageCode: entry.stage,
      bayNumber: Number(entry.bay),
      scheduledStartAt: entry.startAt,
      durationMinutes: Math.round(nextHours * 60),
      shiftMinutes,
    });
    return !!(result && result.ok);
  }
  const candidate = { ...entry, hours: workshopClampDurationHours(Number(entry.hours || 0) + delta), updatedAt: nowIsoString() };
  const latestRows = workshopLoadPlans();
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
    renderWorkshopPlanner();
    return false;
  }
  const otherRows = latestRows.filter(row => row.id !== candidate.id);
  const extendShift = workshopShiftEveryLaterPlannedRow(candidate, otherRows, Math.round(delta * 60));
  const extendConflictRows = extendShift ? extendShift.rows.filter(row => row.id !== candidate.id) : otherRows;
  if (!workshopRequireNoBayConflict(candidate, extendConflictRows)) return false;
  if (!workshopRequireAvailableAssignee(candidate, extendConflictRows)) return false;
  const vehicle = workshopVehicle(entry.vehicleKey);
  const hoursMap = vehicle ? workshopEstimatedHoursMap(vehicle) : {};
  if (vehicle) hoursMap[entry.stage] = candidate.hours;
  const extendBaseRows = extendShift
    ? latestRows.map(row => extendShift.moved.find(item => item.id === row.id) || row)
    : latestRows;
  const persisted = workshopPersistVehiclePlanAction(
    'Workshop plan time extended',
    workshopCascadePlans(extendBaseRows.map(row => row.id === entry.id ? candidate : row)).rows,
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

// Section 2 fix: a vehicle is allowed to be scheduled in multiple
// departments at different times. This must only warn when the candidate's
// proposed time window actually overlaps another department's booking for
// the same vehicle - never merely because another department also has a
// booking for this vehicle at some other (non-overlapping) time.
function workshopOtherDepartmentOverlaps(candidate = {}, rows = []) {
  if (!candidate.vehicleKey) return [];
  const candidateStart = workshopEntryStart(candidate).getTime();
  const candidateEnd = workshopEntryEnd(candidate).getTime();
  return rows.filter(row => {
    if (row.id === candidate.id) return false;
    if (row.vehicleKey !== candidate.vehicleKey) return false;
    if (row.stage === candidate.stage) return false;
    if (row.status === 'completed' || row.status === 'deleted') return false;
    const rowStart = workshopEntryStart(row).getTime();
    const rowEnd = workshopEntryEnd(row).getTime();
    return workshopIntervalsOverlap(candidateStart, candidateEnd, rowStart, rowEnd);
  });
}

function workshopConfirmOtherDepartmentPlans(candidate = {}, rows = []) {
  if (!candidate.vehicleKey || candidate.status !== 'planned') return true;
  const overlapping = workshopOtherDepartmentOverlaps(candidate, rows);
  if (!overlapping.length) return true;
  const details = overlapping.slice(0, 8).map(row => {
    const when = parseIsoTimestamp(row.startAt);
    const whenLabel = when ? when.toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short' }) : 'time not set';
    const place = row.stage === 'SUBLET' ? 'Provider row' : `Bay ${workshopPad(row.bay)}`;
    return `• ${pmbStageLabel(row.stage)} · ${place} · ${whenLabel}`;
  }).join('\n');
  return window.confirm(`This vehicle's requested time overlaps another department's booking for the same vehicle:\n\n${details}\n\nContinue with the ${pmbStageLabel(candidate.stage)} booking?`);
}

async function workshopScheduleSharedNewBooking({
  requestedCandidate = {},
  vehicleRef = null,
  stageCode = '',
  bayNumber = 0,
  scheduledStartAt = '',
  durationMinutes = 0,
} = {}, dispatchAction = workshopDispatchSharedAction) {
  const assignee = cleanNavisionText(requestedCandidate.assignee || '');
  const technicianRef = assignee ? workshopSelectedTechnicianRef(assignee) : null;
  if (assignee && !technicianRef) {
    window.alert(`"${assignee}" could not be matched to an active technician. Re-select an active technician or clear the selection. No booking was created.`);
    return false;
  }
  const technicianId = technicianRef ? String(technicianRef.technicianId || '') : null;
  if (assignee && !technicianId) {
    window.alert(`"${assignee}" does not have a valid stable technician ID. No booking was created.`);
    return false;
  }
  const candidate = { ...requestedCandidate, assignee, technicianId: technicianId || '' };
  if (!workshopRequireSchedulableCandidate(candidate)) return false;
  const result = await dispatchAction('cascadeSchedule', {
    operation: 'insert',
    targetId: vehicleRef.vehicleId,
    targetExpectedVersion: vehicleRef.version,
    stageCode,
    bayNumber,
    scheduledStartAt,
    durationMinutes,
    technicianId,
    shiftMinutes: durationMinutes,
  });
  return !!(result && result.ok);
}

async function scheduleWorkshopVehicle({ planId = '', vehicleKeyValue = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, hoursValue = null, assigneeValue = null, preferRequestedTime = false } = {}) {
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
  // Stage 2A: block scheduling NEW work into a bay the shared reference
  // service reports as inactive. This never blocks moving/resizing an
  // EXISTING booking already in that bay (existing/historical bookings
  // must keep displaying their original bay even if it is later made
  // inactive) -- only a brand-new schedule into that bay is refused.
  // Independent-review remediation (finding 8): fails CLOSED for a
  // brand-new schedule -- confirmed inactive, unavailable (reference
  // data not loaded), or unknown (no matching bay row) are all
  // blocked, not only confirmed-inactive. The database's own
  // validation inside schedule_vehicle_work remains authoritative
  // regardless, but the frontend must not offer to place new work
  // into a bay it cannot confirm is genuinely active.
  if (!existing) {
    const availability = workshopBayAvailabilityStatus(normalizedStage, bay);
    if (availability !== 'active') {
      const messages = {
        inactive: 'This bay is currently marked inactive and cannot accept new bookings. Choose a different bay.',
        unavailable: 'The shared bay reference data is still loading (or unavailable). Try again in a moment before scheduling into this bay.',
        unknown: 'This bay could not be matched to a known shared bay record, so a new booking cannot be placed here. Choose a different bay.',
      };
      window.alert(messages[availability] || 'This bay is not currently available for new bookings.');
      return false;
    }
  }
  const start = workshopDateAtOffset(dateKey, startMinutes);
  if (!workshopRequireEtaSchedule(vehicle, start)) return false;
  const requestedHours = Number(hoursValue);
  const defaultHours = Number.isFinite(requestedHours) && requestedHours > 0
    ? requestedHours
    : existing?.hours || workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || workshopDefaultBookingHours();
  const hours = workshopClampDurationHours(defaultHours);
  const requestedCandidate = {
    ...(existing || {}),
    id: existing?.id || '__new_workshop_booking__',
    stage: normalizedStage,
    bay: Number(bay),
    status: 'planned',
    startAt: start.toISOString(),
    hours,
    assignee: assigneeValue === null
      ? existing?.assignee || workshopBayMechanic(normalizedStage, bay) || pmbBayMechanic(vehicle) || ''
      : cleanNavisionText(assigneeValue || ''),
  };
  if (workshopSharedModeActive()) {
    const durationMinutes = Math.round(hours * 60);
    if (existing && existing.sharedBookingId) {
      if (!workshopRequireSchedulableCandidate(requestedCandidate)) return false;
      const result = await workshopDispatchSharedAction('moveBooking', {
        bookingId: existing.sharedBookingId,
        expectedVersion: existing.sharedVersion,
        stageCode: normalizedStage,
        bayNumber: Number(bay),
        scheduledStartAt: start.toISOString(),
        durationMinutes,
      });
      return !!(result && result.ok);
    }
    const vehicleRef = await workshopVerifiedCanonicalVehicleRef(vehicle);
    if (!vehicleRef || vehicleRef.ok === false) {
      // Controlled linking owns the diagnostic UI and always fails closed.
      // A newly saved link deliberately requires a second scheduling action;
      // no operational booking is created in the link transaction.
      return false;
    }
    return workshopScheduleSharedNewBooking({
      requestedCandidate,
      vehicleRef,
      stageCode: normalizedStage,
      bayNumber: Number(bay),
      scheduledStartAt: start.toISOString(),
      durationMinutes,
    });
  }
  if (!workshopRequireSchedulableCandidate(requestedCandidate)) return false;
  // Parts completion remains an RFT gate, not an entry gate for Tint, Tyre or Sublet. Planning itself never moves a vehicle into a physical bay.
  const now = nowIsoString();
  const candidate = {
    ...requestedCandidate,
    id: existing?.id || workshopPlanId(vehicleKey(vehicle), normalizedStage),
    vehicleKey: vehicleKey(vehicle),
    stage: normalizedStage,
    bay: Number(bay),
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
  const plannedRowsAfterShift = workshopShiftEveryLaterPlannedRow(candidate, conflictRows, Math.round(candidate.hours * 60));
  const effectiveRows = plannedRowsAfterShift.rows.filter(row => row.id !== candidate.id);
  if (!workshopRequireNoBayConflict(candidate, effectiveRows)) return false;
  if (!workshopRequireAvailableAssignee(candidate, effectiveRows)) return false;
  if (!workshopConfirmOtherDepartmentPlans(candidate, latestRows)) return false;
  const baseRows = latestRows.map(entry => plannedRowsAfterShift.moved.find(item => item.id === entry.id) || entry);
  const resolvedCandidate = candidate;
  const nextRows = latestExisting ? baseRows.map(entry => entry.id === latestExisting.id ? resolvedCandidate : entry) : [...baseRows, resolvedCandidate];
  const persisted = workshopPersistPlanAction(
    existing ? 'Workshop plan rescheduled' : 'Workshop plan created',
    workshopCascadePlans(nextRows).rows,
    vehicle,
    existing ? 'Workshop plan rescheduled' : 'Workshop plan created',
    { stage: pmbStageLabel(normalizedStage), bay: normalizedStage === 'SUBLET' ? 'Provider row' : `Bay ${resolvedCandidate.bay}`, startAt: resolvedCandidate.startAt, hours: resolvedCandidate.hours, assignee: resolvedCandidate.assignee || 'Unassigned' },
  );
  if (!persisted) return false;
  workshopState().selectedPlanId = resolvedCandidate.id;
  renderWorkshopPlanner();
  return true;
}

async function saveWorkshopDetailForm(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === form.dataset.workshopPlanFormId);
  if (!entry) return;
  const data = new FormData(form);
  const start = new Date(String(data.get('startAt') || entry.startAt || ''));
  if (Number.isNaN(start.getTime()) || !workshopIsConfiguredWorkingDay(start)) {
    window.alert('Choose a date in the configured workshop working week.');
    return;
  }
  const normalizedStart = new Date(start);
  const requestedHours = Number(data.get('hours') || entry.hours || workshopDefaultBookingHours());
  if (!Number.isFinite(requestedHours) || requestedHours <= 0) {
    window.alert('Enter planned hours greater than zero. There is no maximum workshop duration.');
    return;
  }
  const nextAssignee = cleanNavisionText(data.get('assignee') || '');
  if (!workshopRequireSchedulableCandidate({
    ...entry,
    startAt: normalizedStart.toISOString(),
    hours: requestedHours,
    assignee: nextAssignee,
  })) return;
  if (workshopSharedModeActive()) {
    const nextStartAt = ['started', 'stoppage'].includes(entry.status) ? entry.startAt : normalizedStart.toISOString();
    const nextDurationMinutes = Math.round(workshopClampDurationHours(requestedHours) * 60);
    const currentDurationMinutes = Math.round(workshopClampDurationHours(entry.hours) * 60);
    const extendsDuration = nextDurationMinutes > currentDurationMinutes;
    if (extendsDuration && nextStartAt !== entry.startAt) {
      window.alert('To preserve an atomic bay cascade, save the new start time first, then extend the duration.');
      return;
    }
    const shiftMinutes = extendsDuration ? nextDurationMinutes - currentDurationMinutes : 0;
    const moveResult = extendsDuration
      ? await workshopDispatchSharedAction('cascadeSchedule', {
        operation: 'extend', targetId: entry.sharedBookingId || entry.id, targetExpectedVersion: entry.sharedVersion,
        stageCode: entry.stage, bayNumber: Number(entry.bay), scheduledStartAt: entry.startAt,
        durationMinutes: nextDurationMinutes, shiftMinutes,
      })
      : await workshopDispatchSharedAction('moveBooking', {
        bookingId: entry.sharedBookingId || entry.id, expectedVersion: entry.sharedVersion,
        stageCode: entry.stage, bayNumber: Number(entry.bay), scheduledStartAt: nextStartAt,
        durationMinutes: nextDurationMinutes,
      });
    if (!moveResult || !moveResult.ok) return;
    if (nextAssignee !== (entry.assignee || '')) {
      const nextVersion = moveResult.booking && moveResult.booking.version;
      // Independent-review remediation (finding 3): resolve by stable
      // technician ID from the reference table first (works for any
      // active technician, not only ones already visible on a current
      // booking); only fall back to the booking-snapshot scan for a
      // technician somehow present in the snapshot but not in the
      // reference cache (should not normally happen, but never worse
      // than the previous behaviour). If neither resolves, send `null`
      // explicitly only when the user actually cleared the field --
      // never as a silent misresolution of a real name.
      const technicianRef = nextAssignee
        ? (workshopReferenceTechnicianRef(nextAssignee) || workshopSharedTechnicianRef(nextAssignee))
        : null;
      if (nextAssignee && !technicianRef) {
        window.alert(`"${nextAssignee}" could not be matched to an active technician. The booking was moved, but the technician assignment was not changed. Re-select the technician and save again.`);
      } else {
        await workshopDispatchSharedAction('assignBookingTechnician', {
          bookingId: entry.sharedBookingId || entry.id,
          expectedVersion: nextVersion,
          technicianId: technicianRef ? technicianRef.technicianId : null,
        });
      }
    }
    return;
  }
  const candidate = {
    ...entry,
    startAt: ['started', 'stoppage'].includes(entry.status) ? entry.startAt : normalizedStart.toISOString(),
    hours: workshopClampDurationHours(requestedHours),
    assignee: nextAssignee,
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
  const durationDeltaMinutes = Math.max(0, Math.round((candidate.hours - workshopClampDurationHours(entry.hours)) * 60));
  const detailShift = durationDeltaMinutes > 0 ? workshopShiftEveryLaterPlannedRow(candidate, otherRows, durationDeltaMinutes) : null;
  const detailConflictRows = detailShift ? detailShift.rows : otherRows;
  let resolvedDetail = candidate;
  if (workshopHasConflict(candidate, detailConflictRows) && !detailShift) {
    resolvedDetail = workshopResolveConflictByNextSlot(candidate, otherRows);
    if (!resolvedDetail) return;
  } else if (!workshopRequireNoBayConflict(candidate, detailConflictRows)) return;
  if (!workshopRequireAvailableAssignee(resolvedDetail, detailConflictRows)) return;
  if (!workshopConfirmOtherDepartmentPlans(resolvedDetail, latestRows)) return;
  const detailBaseRows = detailShift ? latestRows.map(row => detailShift.moved.find(item => item.id === row.id) || row) : latestRows;
  const updatedRows = workshopCascadePlans(detailBaseRows.map(row => row.id === entry.id ? resolvedDetail : row)).rows;
  const vehicle = workshopVehicle(entry.vehicleKey);
  const hoursMap = vehicle ? workshopEstimatedHoursMap(vehicle) : {};
  if (vehicle) hoursMap[entry.stage] = resolvedDetail.hours;
  const persisted = workshopPersistVehiclePlanAction(
    'Workshop plan details updated',
    updatedRows,
    vehicle,
    vehicle ? { workshopEstimatedHoursByStage: hoursMap } : {},
    'Workshop plan details updated',
    { stage: pmbStageLabel(entry.stage), startAt: resolvedDetail.startAt, hours: resolvedDetail.hours, assignee: resolvedDetail.assignee || 'Unassigned' },
  );
  if (!persisted) return;
  const state = workshopState();
  state.date = workshopEntryDate(resolvedDetail);
  workshopSaveView(state);
  renderWorkshopPlanner();
}

async function startWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (workshopSharedModeActive()) {
    await workshopDispatchSharedAction('startWork', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
    });
    return;
  }
  if (!workshopRequireOperatorProfile()) return;
  const currentStart = workshopNormalizeStartDate(new Date());
  const next = { ...entry, startAt: currentStart.toISOString(), status: 'started', startedAt: nowIsoString(), updatedAt: nowIsoString() };
  const otherRows = rows.filter(row => row.id !== next.id);
  let plannedRowsAfterShift = null;
  if (workshopHasConflict(next, otherRows)) {
    const shifted = workshopShiftTrailingPlannedRows(next, otherRows);
    if (!shifted) {
      if (!workshopRequireNoBayConflict(next, otherRows)) return;
      return;
    }
    plannedRowsAfterShift = shifted;
  }
  if (!plannedRowsAfterShift && !workshopRequireNoBayConflict(next, otherRows)) return;
  const conflictCheckRows = plannedRowsAfterShift ? plannedRowsAfterShift.rows.filter(row => row.id !== next.id) : otherRows;
  if (!workshopRequireAvailableAssignee(next, conflictCheckRows)) return;
  const baseRows = plannedRowsAfterShift
    ? rows.map(row => plannedRowsAfterShift.moved.find(item => item.id === row.id) || row)
    : rows;
  const nextRows = workshopCascadePlans(baseRows.map(row => row.id === entry.id ? next : row)).rows;
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

async function completeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (workshopSharedModeActive()) {
    await workshopDispatchSharedAction('completeWork', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
      workKey: entry.stage,
    });
    return;
  }
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

// Same modal pattern as workshopStoppageReasonModal, used for the
// Parts-incomplete override retry in workshopDispatchSharedAction(). A
// blank/cancelled reason resolves to '' so the caller can treat it as "do
// not retry" without a second confirm dialog. Not a browser prompt()
// (forbidden by house style / existing test coverage) -- a proper modal
// consistent with the rest of the planner's UI.
function workshopOverrideReasonModal() {
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay workshop-return-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.innerHTML = `<section class="modal-card workshop-return-card">
      <button class="modal-close" type="button" data-workshop-override-cancel aria-label="Cancel">×</button>
      <header><h2>Parts-incomplete override</h2><p>Parts requirements are incomplete. Enter a reason to proceed. Only an authorised controller or administrator account can complete this override -- the database will reject it otherwise.</p></header>
      <label class="workshop-return-reason"><span>Override reason</span><input type="text" data-workshop-override-reason autocomplete="off"></label>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-override-cancel>Cancel</button><button class="primary" type="button" data-workshop-override-apply>Proceed with override</button></div>
    </section>`;
    const finish = value => {
      overlay.remove();
      if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
      resolve(value);
    };
    overlay.querySelectorAll('[data-workshop-override-cancel]').forEach(button => button.addEventListener('click', () => finish('')));
    overlay.querySelector('[data-workshop-override-apply]').addEventListener('click', () => {
      const reason = cleanNavisionText(overlay.querySelector('[data-workshop-override-reason]')?.value || '');
      if (!reason) {
        window.alert('Enter the override reason.');
        return;
      }
      finish(reason);
    });
    overlay.addEventListener('click', event => { if (event.target === overlay) finish(''); });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    overlay.querySelector('[data-workshop-override-reason]')?.focus();
  });
}

async function stopWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (workshopSharedModeActive()) {
    if (entry.status !== 'started') {
      window.alert('Start the job before recording a workshop stoppage.');
      return;
    }
    const reason = await workshopStoppageReasonModal(entry, vehicle);
    if (!reason) return;
    await workshopDispatchSharedAction('stopWork', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
      reason,
    });
    return;
  }
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

async function resumeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle || entry.status !== 'stoppage') return;
  if (workshopSharedModeActive()) {
    await workshopDispatchSharedAction('resumeWork', {
      bookingId: entry.sharedBookingId || entry.id,
      expectedVersion: entry.sharedVersion,
    });
    return;
  }
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
    const deltaMinutes = workshopSnapMinutes(((moveEvent.clientX - originX) / Math.max(1, lane.getBoundingClientRect().width)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
    const hours = workshopClampDurationHours(originalHours + deltaMinutes / 60);
    const visibleMinutes = Math.min(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes - (segment?.start || 0), hours * 60);
    chip.style.setProperty('--plan-width', `${(visibleMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%`);
    chip.dataset.previewHours = String(hours);
  };
  const onUp = async () => {
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
    const hours = Number(chip.dataset.previewHours || entry.hours);
    delete chip.dataset.previewHours;
    if (workshopSharedModeActive()) {
      const nextHours = workshopClampDurationHours(hours);
      const deltaMinutes = Math.max(0, Math.round((nextHours - workshopClampDurationHours(entry.hours)) * 60));
      await workshopDispatchSharedAction('cascadeSchedule', {
        operation: 'extend',
        targetId: entry.sharedBookingId || entry.id,
        targetExpectedVersion: entry.sharedVersion,
        stageCode: entry.stage,
        bayNumber: Number(entry.bay),
        scheduledStartAt: entry.startAt,
        durationMinutes: Math.round(nextHours * 60),
        shiftMinutes: deltaMinutes,
      });
      return;
    }
    const candidate = { ...entry, hours, updatedAt: nowIsoString() };
    const latestRows = workshopLoadPlans();
    const latestEntry = latestRows.find(row => row.id === entry.id);
    if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
      window.alert('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
      renderWorkshopPlanner();
      return;
    }
    const otherRows = latestRows.filter(row => row.id !== candidate.id);
    const resizeShift = workshopShiftEveryLaterPlannedRow(candidate, otherRows, Math.max(0, Math.round((candidate.hours - originalHours) * 60)));
    if (!workshopRequireNoBayConflict(candidate, resizeShift.rows)) {
      renderWorkshopPlanner();
      return;
    }
    const resizeConflictRows = resizeShift ? resizeShift.rows.filter(row => row.id !== candidate.id) : otherRows;
    if (!workshopRequireAvailableAssignee(candidate, resizeConflictRows)) {
      renderWorkshopPlanner();
      return;
    }
    const resizeBaseRows = resizeShift
      ? latestRows.map(row => resizeShift.moved.find(item => item.id === row.id) || row)
      : latestRows;
    const updatedRows = workshopCascadePlans(resizeBaseRows.map(row => row.id === entry.id ? candidate : row)).rows;
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
  const top = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const height = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const draggable = entry.status !== 'completed';
  const assignee = cleanNavisionText(entry.assignee || '') || workshopBayMechanic(entry.stage, entry.bay) || '';
  const statusLabel = entry.status === 'stoppage' ? 'STOPPAGE' : entry.status === 'started' ? 'LIVE' : 'PLANNED';
  return `<article class="workshop-week-card ${entry.status !== 'planned' ? 'is-live' : ''} ${segment.usesConfiguredOvertime ? 'uses-configured-overtime' : ''} ${segment.historicalOnClosure ? 'historical-on-closure' : ''}" ${draggable ? 'draggable="true"' : ''} data-workshop-week-plan="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" style="--week-top:${top}%;--week-height:${height}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · ${entry.hours} hours${segment.usesConfiguredOvertime ? ' · configured overtime' : ''}${segment.historicalOnClosure ? ' · historical booking on closure' : ''}${entry.status === 'completed' ? ' · completed history stays fixed' : entry.status === 'planned' ? ' · drag to another day/time' : ' · drag to move this live job safely'}`)}">
    <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')}</strong>
    <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
    <small>${escapeHtml(`${statusLabel}${assignee ? ` · ${assignee}` : ''}`)}</small>
    <em>${escapeHtml(entry.hours)}h</em>
  </article>`;
}

function workshopWeeklyTimeGuideHtml() {
  const tickCount = Math.floor(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / 120) + 1;
  return Array.from({ length: tickCount }, (_, index) => {
    const minutes = index * 120;
    return `<span style="top:${(minutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%">${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</span>`;
  }).join('');
}

async function moveWorkshopWeeklyPlan(planId = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, weekKey = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  if (!entry || entry.status === 'completed') return;
  if (entry.status !== 'planned') {
    await moveWorkshopLivePlan(planId, stage, bay, dateKey, startMinutes);
    openWorkshopWeeklyView(stage, bay, weekKey || dateKey);
    return;
  }
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
  let resolvedCandidate = candidate;
  let plannedRowsAfterShift = null;
  if (workshopHasConflict(candidate, otherRows)) {
    plannedRowsAfterShift = workshopShiftTrailingPlannedRows(candidate, otherRows);
    if (!plannedRowsAfterShift) {
      if (!workshopRequireNoBayConflict(candidate, otherRows)) return;
      return;
    }
  } else if (!workshopRequireNoBayConflict(candidate, otherRows)) return;
  const effectiveRows = plannedRowsAfterShift ? plannedRowsAfterShift.rows.filter(row => row.id !== resolvedCandidate.id) : otherRows;
  if (!workshopRequireAvailableAssignee(resolvedCandidate, effectiveRows)) return;
  if (!workshopConfirmOtherDepartmentPlans(resolvedCandidate, latestRows)) return;
  const baseRows = plannedRowsAfterShift
    ? latestRows.map(row => plannedRowsAfterShift.moved.find(item => item.id === row.id) || row)
    : latestRows;
  const updated = workshopCascadePlans(baseRows.map(row => row.id === resolvedCandidate.id ? resolvedCandidate : row)).rows;
  workshopPersistPlanAction(
    'Workshop weekly plan moved',
    updated,
    workshopVehicle(entry.vehicleKey),
    'Workshop weekly plan moved',
    { stage: pmbStageLabel(resolvedCandidate.stage), bay: resolvedCandidate.stage === 'SUBLET' ? 'Provider row' : `Bay ${resolvedCandidate.bay}`, startAt: resolvedCandidate.startAt },
  );
  workshopState().selectedPlanId = resolvedCandidate.id;
  workshopState().date = workshopEntryDate(resolvedCandidate);
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
    const isClosure = workshopIsClosureDate(date);
    const dayPlans = plans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
    const bookedHours = dayPlans.reduce((sum, entry) => {
      const segment = workshopEntrySegmentForDate(entry, dateKey);
      return sum + (segment ? (segment.end - segment.start) / 60 : 0);
    }, 0);
    return `<section class="workshop-week-day ${isClosure ? 'is-closure' : ''}">
      <header><strong>${escapeHtml(date.toLocaleDateString('en-AU', { weekday: 'short' }))}</strong><span>${escapeHtml(date.toLocaleDateString('en-AU', { day: '2-digit', month: '2-digit' }))}</span><small>${isClosure ? 'CLOSED · historical bookings remain visible' : `${escapeHtml(bookedHours.toFixed(bookedHours % 1 ? 1 : 0))}h booked`}</small></header>
      <div class="workshop-week-day-lane" ${isClosure ? 'aria-disabled="true"' : `data-workshop-week-drop-date="${escapeHtml(dateKey)}"`}>${workshopWeeklyTimeGuideHtml()}${isClosure ? '' : workshopDropPreviewHtml({ vertical: true })}${dayPlans.map(entry => workshopWeeklyCardHtml(entry, dateKey)).join('')}</div>
    </section>`;
  }).join('');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-week-overlay';
  overlay.dataset.workshopWeekOverlay = 'true';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-week-card-shell">
    <button class="modal-close" type="button" data-workshop-week-close aria-label="Close weekly view">×</button>
    <header class="workshop-week-header"><div><h2>${escapeHtml(pmbStageLabel(normalizedStage))} · Bay ${escapeHtml(bay)} weekly schedule</h2><p>${escapeHtml(dates[0].toLocaleDateString('en-AU', { day: 'numeric', month: 'long' }))}–${escapeHtml(dates[dates.length - 1].toLocaleDateString('en-AU', { day: 'numeric', month: 'long', year: 'numeric' }))} · drag a minimised booking to another day or time</p></div><div><button class="small-button" type="button" data-workshop-week-shift="-7">‹ Previous week</button><button class="small-button" type="button" data-workshop-week-shift="7">Next week ›</button></div></header>
    <div class="workshop-week-grid" style="--workshop-week-columns:${dates.length};min-width:${Math.max(620, dates.length * 200)}px">${columns}</div>
    <footer><span>Planned jobs snap to ${escapeHtml(WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes)} minutes and update the daily board immediately. Closures are read-only; historical bookings remain visible. Started and stoppage jobs can also be moved safely, with audit and bay-state updates. Completed jobs stay fixed.</span><button class="primary" type="button" data-workshop-week-close>Done</button></footer>
  </section>`;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  overlay.querySelectorAll('[data-workshop-week-close]').forEach(button => button.addEventListener('click', close));
  overlay.querySelectorAll('[data-workshop-week-shift]').forEach(button => button.addEventListener('click', () => {
    const nextWeek = new Date(weekStart);
    nextWeek.setDate(nextWeek.getDate() + Number(button.dataset.workshopWeekShift));
    openWorkshopWeeklyView(normalizedStage, bay, nextWeek);
  }));
  overlay.querySelectorAll('[data-workshop-week-plan][draggable="true"]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', card.dataset.workshopWeekPlan);
    const entry = workshopLoadPlans().find(row => row.id === card.dataset.workshopWeekPlan);
    workshopSetDragPreview({ type: 'week-plan', hours: workshopClampDurationHours(entry?.hours) || workshopDefaultBookingHours() });
  }));
  overlay.querySelectorAll('[data-workshop-week-plan][draggable="true"]').forEach(card => card.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(overlay), 0);
  }));
  overlay.querySelectorAll('[data-workshop-week-drop-date]').forEach(lane => {
    lane.addEventListener('dragover', event => {
      event.preventDefault();
      lane.classList.add('drag-over');
      const rect = lane.getBoundingClientRect();
      const startMinutes = workshopClampStartMinutes(((event.clientY - rect.top) / Math.max(1, rect.height)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
      workshopUpdateLanePreview(lane, startMinutes);
    });
    lane.addEventListener('dragleave', event => {
      if (!lane.contains(event.relatedTarget)) {
        lane.classList.remove('drag-over');
        workshopHideLanePreview(lane);
      }
    });
    lane.addEventListener('drop', event => {
      event.preventDefault();
      lane.classList.remove('drag-over');
      const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
      const rect = lane.getBoundingClientRect();
      const fallbackStartMinutes = workshopClampStartMinutes(((event.clientY - rect.top) / Math.max(1, rect.height)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
      const previewMinutes = Number(lane.dataset.workshopRequestedStartMinutes);
      const rememberedTarget = workshopCurrentDropTarget();
      const targetStage = lane.dataset.workshopWeekDropStage || normalizedStage;
      const targetBay = Number(lane.dataset.workshopWeekDropBay || bay);
      const targetDate = lane.dataset.workshopWeekDropDate;
      const startMinutes = rememberedTarget
        && rememberedTarget.stage === targetStage
        && Number(rememberedTarget.bay) === targetBay
        && rememberedTarget.dateKey === targetDate
        && Number.isFinite(Number(rememberedTarget.startMinutes))
        ? workshopClampStartMinutes(Number(rememberedTarget.startMinutes))
        : Number.isFinite(previewMinutes)
          ? previewMinutes
          : fallbackStartMinutes;
      workshopClearLanePreviews(lane);
      void moveWorkshopWeeklyPlan(planId, normalizedStage, bay, lane.dataset.workshopWeekDropDate, startMinutes, workshopDateKey(weekStart));
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
  const selectedDate = workshopDateFromKey(state.date);
  const visible = workshopIsWorkday(selectedDate || now);
  line.hidden = !visible;
  if (!visible) return;
  const timelineRect = timeline.getBoundingClientRect();
  const axisRect = axis.getBoundingClientRect();
  const clampedOffset = Math.min(Math.max(offset, 0), WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
  const left = axisRect.left - timelineRect.left + (clampedOffset / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * axisRect.width;
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
    WORKSHOP_STAGE_SEQUENCE,
    workshopClockMinutes,
    workshopSetClock,
    workshopConfigurationFromRows,
    workshopConfigurationAllowsNewScheduling,
    workshopSyncConfigFromSharedSettings,
    workshopIsConfiguredWorkingDay,
    workshopIsClosureDate,
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
    workshopAvailabilityWindowsForDate,
    workshopBreakWindowsForDate,
    workshopNewBookingValidation,
    workshopTechnicianIsOnLeave,
    workshopHasConflict,
    workshopRequireNoBayConflict,
    workshopResolveConflictByNextSlot,
    workshopShiftTrailingPlannedRows,
    workshopShiftEveryLaterPlannedRow,
    workshopDateKey,
    workshopDateFromKey,
    workshopNormalizeStartDate,
    workshopAddWorkMinutes,
    workshopWorkMinutesBetween,
    workshopCascadePlans,
    workshopEntrySegmentForDate,
    workshopEntryStart,
    workshopEntryEnd,
    workshopSortBookingsClosest,
    workshopPlanVehicleIdentity,
    workshopResolveBookingSelection,
    workshopBookingsForEntry,
    workshopEntryUsesConfiguredOvertime,
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
    workshopBestStageSlot,
    workshopSlotSummary,
    workshopVehiclePlanningLocation,
    workshopVehicleEtaConstraint,
    workshopDateKeyNotBefore,
    workshopEtaScheduleValidation,
    workshopEtaRiskForEntry,
    workshopStageVehicles,
    workshopVehicle,
    workshopSnapshotVehicleToPlannerRow,
    workshopPlannerVehiclesForStage,
    workshopRefreshDedicatedDate,
    moveWorkshopLivePlan,
    moveWorkshopDroppedPlan,
    workshopSharedModeActive,
    workshopMapSnapshotBookingToLegacyRow,
    workshopConnectionBannerHtml,
    workshopDescribeSharedActionError,
    workshopVehicleLinkIdentityInput,
    workshopVehicleLinkStableAliases,
    workshopLoadVehicleLinkStore,
    workshopLookupStoredVehicleLink,
    workshopSaveStoredVehicleLink,
    workshopVehicleLinkProbeInputs,
    workshopVehicleLinkResultSummary,
    workshopResolveVehicleLinkDiagnostic,
    workshopVehicleLinkCanPersist,
    workshopPersistVerifiedCanonicalLink,
    workshopRollbackPersistedCanonicalLink,
    workshopVehicleLinkVisibleReason,
    workshopVehicleLinkDisplayRows,
    workshopVehicleLinkDiagnosticModal,
    workshopVerifiedCanonicalVehicleRef,
    workshopVehicleLinkReadinessStatus,
    workshopBuildVehicleLinkReadinessReport,
    workshopPersistVehicleLinkReadinessBatch,
    workshopLinkReadinessModalReportHtml,
    workshopSharedVehicleRef,
    workshopSharedTechnicianRef,
    workshopReferenceTechnicianRef,
    workshopSelectedTechnicianRef,
    workshopScheduleSharedNewBooking,
    workshopSharedBayRef,
    workshopBayIsActive,
    workshopBayAvailabilityStatus,
    workshopBayDefaultTechnicianName,
    workshopBayMechanic,
    saveWorkshopBayMechanic,
    workshopOtherDepartmentOverlaps,
    workshopConfirmOtherDepartmentPlans,
    workshopDateAtOffset,
    workshopMinuteOffset,
    extendWorkshopPlan,
  };
  Object.defineProperties(module.exports, {
    WORKSHOP_CONFIG: { enumerable: true, get: () => WORKSHOP_PLANNER_CONFIG },
    WORKSHOP_CONFIG_AUTHORITY: { enumerable: true, get: () => WORKSHOP_CONFIG_AUTHORITY },
  });
}
