'use strict';

const WORKSHOP_PLAN_STORAGE_KEY = 'vehicleTrackingCoreWorkshopPlan:v1';
const WORKSHOP_VIEW_STORAGE_KEY = 'vehicleTrackingCoreWorkshopView:v1';
const WORKSHOP_BAY_SETUP_STORAGE_KEY = 'vehicleTrackingCoreWorkshopBaySetup:v1';
const WORKSHOP_PLANNER_RUNTIME_VERSION = '2026.09.09.03-fitting-duration-coherence';
const WORKSHOP_DEPLOYMENT_MANIFEST_URL = 'deployment-manifest.json';
const WORKSHOP_DEPLOYMENT_RELOADS_KEY = 'vehicleTrackingCoreWorkshopDeploymentReloads:v1';
let workshopDeploymentFreshnessCheck = null;


// r407 (F20): planner messages are a non-blocking, accessible toast instead of
// window.alert(). Errors use role="alert" (assertive) and stay until dismissed;
// info messages use role="status" (polite) and clear after a few seconds.
// window.confirm() is kept where a real yes/no decision is needed.
function workshopNotify(message, tone = 'error') {
  const text = String(message ?? '').trim();
  if (!text) return;
  const kind = tone === 'info' ? 'info' : 'error';
  if (typeof document === 'undefined' || !document.body || typeof document.createElement !== 'function') {
    if (typeof console !== 'undefined' && typeof console.warn === 'function') console.warn(text);
    return;
  }
  let region = document.getElementById('workshop-toast-region');
  if (!region) {
    region = document.createElement('div');
    region.id = 'workshop-toast-region';
    region.className = 'workshop-toast-region';
    document.body.appendChild(region);
  }
  const toast = document.createElement('div');
  toast.className = `workshop-toast is-${kind}`;
  toast.setAttribute('role', kind === 'info' ? 'status' : 'alert');
  toast.setAttribute('aria-live', kind === 'info' ? 'polite' : 'assertive');
  toast.setAttribute('aria-atomic', 'true');
  const body = document.createElement('span');
  body.className = 'workshop-toast-message';
  body.textContent = text;
  const close = document.createElement('button');
  close.type = 'button';
  close.className = 'workshop-toast-close';
  close.setAttribute('aria-label', 'Dismiss message');
  close.textContent = '×';
  close.addEventListener('click', () => toast.remove());
  toast.append(body, close);
  region.appendChild(toast);
  while (region.children.length > 4) region.firstElementChild.remove();
  if (kind === 'info') setTimeout(() => toast.remove(), 8000);
}

function workshopDeploymentManifestIdentity(manifest = {}) {
  const siteVersion = typeof manifest.siteVersion === 'string' ? manifest.siteVersion.trim() : '';
  const plannerVersion = typeof manifest.workshopPlannerVersion === 'string' ? manifest.workshopPlannerVersion.trim() : '';
  const safeVersion = value => value.length <= 128 && /^[A-Za-z0-9._-]+$/.test(value);
  return safeVersion(siteVersion) && safeVersion(plannerVersion)
    ? `${siteVersion}|${plannerVersion}`
    : '';
}

function workshopClaimDeploymentReload(identity = '') {
  if (!identity || typeof window === 'undefined') return false;
  try {
    const storage = window.sessionStorage;
    if (!storage?.getItem || !storage?.setItem) return false;
    const identityKey = `${WORKSHOP_DEPLOYMENT_RELOADS_KEY}:${identity}`;
    if (storage.getItem(identityKey) === '1') return false;
    storage.setItem(identityKey, '1');
    return true;
  } catch (_) {
    return false;
  }
}

async function workshopEnsureCurrentDeployment() {
  if (typeof fetch !== 'function') return true;
  if (workshopDeploymentFreshnessCheck) return workshopDeploymentFreshnessCheck;
  workshopDeploymentFreshnessCheck = (async () => {
    try {
      const separator = WORKSHOP_DEPLOYMENT_MANIFEST_URL.includes('?') ? '&' : '?';
      const response = await fetch(`${WORKSHOP_DEPLOYMENT_MANIFEST_URL}${separator}fresh=${Date.now()}`, {
        cache: 'no-store',
        credentials: 'same-origin',
      });
      if (!response.ok) return true;
      const manifest = await response.json();
      const identity = workshopDeploymentManifestIdentity(manifest);
      if (!identity) return true;
      if (manifest?.workshopPlannerVersion === WORKSHOP_PLANNER_RUNTIME_VERSION) return true;
      if (!workshopClaimDeploymentReload(identity)) return false;
      if (typeof window !== 'undefined' && window.location?.replace) {
        const next = new URL(window.location.href);
        next.searchParams.set('deployment', manifest.siteVersion);
        window.location.replace(next.toString());
      }
      return false;
    } catch (_) {
      // A manifest outage must not replace the existing server-side validation.
      return true;
    } finally {
      workshopDeploymentFreshnessCheck = null;
    }
  })();
  return workshopDeploymentFreshnessCheck;
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  const checkFreshness = () => { void workshopEnsureCurrentDeployment(); };
  window.addEventListener('focus', checkFreshness);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') checkFreshness();
  });
  window.setTimeout?.(checkFreshness, 0);
}

// Stage 2A final remediation: all authoritative planner configuration is
// integer minutes or validated collections. Fractional clock hours are never
// stored and are never passed to Date APIs.
const WORKSHOP_ELIGIBILITY_RUNTIME = globalThis.PDC_WORKSHOP_ELIGIBILITY
  || (typeof require === 'function' ? require('./workshop-eligibility.js') : null);
if (!WORKSHOP_ELIGIBILITY_RUNTIME) throw new Error('Canonical workshop eligibility module failed to load');
const WORKSHOP_BOOKING_TIMING = globalThis.PDC_WORKSHOP_BOOKING_TIMING
  || (typeof require === 'function' ? require('./workshop-booking-timing.js') : null);
if (!WORKSHOP_BOOKING_TIMING) throw new Error('Workshop booking timing module failed to load');

const WORKSHOP_STAGE_SEQUENCE = Object.freeze(WORKSHOP_ELIGIBILITY_RUNTIME.workshopPlannerStageCodes());
const WORKSHOP_VISIBLE_STAGE_SEQUENCE = WORKSHOP_STAGE_SEQUENCE;
const WORKSHOP_DAY_NAME_TO_INDEX = { sunday: 0, monday: 1, tuesday: 2, wednesday: 3, thursday: 4, friday: 5, saturday: 6 };
const WORKSHOP_INDEX_TO_DAY_NAME = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const WORKSHOP_BOOT_CONFIG = Object.freeze({
  dayStartMinutes: 7 * 60,
  dayEndMinutes: 17 * 60,
  dayLengthMinutes: 10 * 60,
  schedulingIncrementMinutes: 15,
  // One hour is only a fail-safe when no authoritative operation estimate exists.
  // The original three-hour test/default must never override a job's estimated time.
  defaultBookingDurationMinutes: 60,
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

// r406 (F17): the planner works in Perth time whatever the device's timezone.
// Perth has no daylight saving, so its wall clock is always UTC+8: a Perth
// calendar day is exactly 24 hours, and each Perth date/time field is the UTC
// field of the instant moved forward 8 hours. Planner date maths never uses
// getHours/getDate/getDay/setHours/setDate or new Date(y, m, d), which follow
// the device's zone. Each helper is self-contained (offset written inline).
function workshopSetClock(date, minutesFromMidnight) {
  const perth = new Date(new Date(date).getTime() + 8 * 3600000);
  return new Date(Date.UTC(perth.getUTCFullYear(), perth.getUTCMonth(), perth.getUTCDate(), 0, Number(minutesFromMidnight) || 0) - 8 * 3600000);
}

// The Perth day of the week (0 = Sunday) of an instant.
function workshopPerthWeekday(value = new Date()) {
  return new Date(new Date(value).getTime() + 8 * 3600000).getUTCDay();
}

// Perth calendar days are 24 hours long, so adding days is plain arithmetic.
function workshopPerthAddDays(value = new Date(), days = 0) {
  return new Date(new Date(value).getTime() + Number(days || 0) * 86400000);
}

// Value for <input type="datetime-local">, in Perth time.
function workshopPerthLocalInputValue(value) {
  return new Date(new Date(value).getTime() + 8 * 3600000).toISOString().slice(0, 16);
}

// A datetime-local value has no zone; it is always read as Perth time.
// Full ISO timestamps (with Z or an offset) keep their own zone.
function workshopParsePerthLocalInput(value = '') {
  const text = String(value || '').trim();
  return /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(text) ? new Date(`${text.length === 16 ? `${text}:00` : text}+08:00`) : new Date(text);
}

function workshopValidDateKey(value) {
  const match = typeof value === 'string' && value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return '';
  const candidate = new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
  return candidate.getUTCFullYear() === Number(match[1])
    && candidate.getUTCMonth() === Number(match[2]) - 1
    && candidate.getUTCDate() === Number(match[3]) ? value : '';
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
  // r406: the Perth calendar date.
  return new Date(new Date(date).getTime() + 8 * 3600000).toISOString().slice(0, 10);
}

function workshopDateFromKey(value = '') {
  const valid = workshopValidDateKey(String(value || ''));
  if (!valid) return null;
  const [year, month, day] = valid.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day, 0, WORKSHOP_PLANNER_CONFIG.dayStartMinutes) - 8 * 3600000);
}

function workshopCalendarDateKeyOffset(value = '', days = 0) {
  const date = workshopDateFromKey(value);
  if (!date) return '';
  return workshopDateKey(new Date(date.getTime() + Number(days || 0) * 86400000));
}

function workshopDefaultBookingHours() {
  return WORKSHOP_PLANNER_CONFIG.defaultBookingDurationMinutes / 60;
}

function workshopBusShift(context = null) {
  if (!context || String(context.stage || context.stage_code || '').toUpperCase() !== 'BUS_4X4') return null;
  const bay = Number(context.bay ?? context.bay_number);
  if (!Number.isInteger(bay) || bay < 1 || bay > 10) return null;
  let vehicle = context.calendarVehicle || null;
  if (!vehicle && (context.sharedVehicleId || context.vehicleKey)) vehicle = workshopVehicle(context.sharedVehicleId || context.vehicleKey, 'BUS_4X4');
  const codes = Array.isArray(vehicle?.department_codes) ? vehicle.department_codes : Array.isArray(vehicle?.pdcDepartmentCodes) ? vehicle.pdcDepartmentCodes : [];
  // Department membership is supplied by the scoped snapshot. Never infer it
  // from Bus4x4, the selected department filter, vehicle model or stock text.
  const is138 = context.busCalendarVersion === 1 || vehicle?.bus_workflow_department138 === true || codes.some(code => String(code) === '138');
  return is138 ? { startMinutes:360, endMinutes:[8,9].includes(bay) ? 840 : 900 } : null;
}

function workshopCalendarStartMinutes(context = null) {
  return workshopBusShift(context)?.startMinutes ?? WORKSHOP_PLANNER_CONFIG.dayStartMinutes;
}

function workshopIsConfiguredWorkingDay(date = new Date(), context = null) {
  const weekday = new Date(new Date(date).getTime() + 8 * 3600000).getUTCDay();
  if (workshopBusShift(context)) return weekday >= 1 && weekday <= 5;
  return WORKSHOP_PLANNER_CONFIG.workingDayIndexes.includes(weekday);
}

function workshopIsClosureDate(date = new Date(), context = null) {
  const key = workshopDateKey(date);
  if (WORKSHOP_PLANNER_CONFIG.closureDateKeys.includes(key)) return true;
  if (!workshopBusShift(context)) return false;
  const calendar = typeof window !== 'undefined' ? window.__workshopDataService?.getLastSnapshot?.()?.planning_calendar : null;
  return calendar?.verified === true && Array.isArray(calendar.closures) && calendar.closures.includes(key);
}

function workshopIsWorkday(date = new Date(), context = null) {
  return workshopIsConfiguredWorkingDay(date, context) && !workshopIsClosureDate(date, context);
}

function workshopCoerceWorkDate(date = new Date(), direction = 1, context = null) {
  let next = workshopSetClock(date, workshopCalendarStartMinutes(context));
  const step = direction < 0 ? -1 : 1;
  while (!workshopIsWorkday(next, context)) next = new Date(next.getTime() + step * 86400000);
  return next;
}

// Perth has no daylight saving, so its wall clock is always UTC+8.
function workshopPerthMinutesOfDay(value = new Date()) {
  const time = value instanceof Date ? value.getTime() : new Date(value).getTime();
  if (!Number.isFinite(time)) return NaN;
  return Math.floor(((time / 60000) + 8 * 60) % 1440 + 1440) % 1440;
}

// After the shift has finished in Perth, "today" in the planner is the next
// workday: nothing more can be placed today, and staff working late or
// planning the morning should land on tomorrow (r403).
function workshopDefaultOpenDateKey(value = new Date()) {
  const candidate = value instanceof Date ? new Date(value) : new Date(value);
  let safe = Number.isNaN(candidate.getTime()) ? new Date() : candidate;
  const dayEnd = Number(typeof WORKSHOP_PLANNER_CONFIG !== 'undefined' ? WORKSHOP_PLANNER_CONFIG?.dayEndMinutes : NaN);
  const shiftOver = Number.isFinite(dayEnd) && dayEnd > 0 && workshopPerthMinutesOfDay(safe) >= dayEnd
    && workshopIsWorkday(safe);
  if (shiftOver) safe = new Date(safe.getTime() + 86400000);
  return workshopDateKey(workshopCoerceWorkDate(safe, 1));
}

function workshopShiftWorkday(date = new Date(), amount = 1) {
  let next = workshopCoerceWorkDate(date, amount < 0 ? -1 : 1);
  let remaining = Math.abs(Number(amount) || 0);
  const step = amount < 0 ? -1 : 1;
  while (remaining > 0) {
    next = new Date(next.getTime() + step * 86400000);
    if (workshopIsWorkday(next)) remaining -= 1;
  }
  return workshopSetClock(next, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
}

function workshopWeekStart(value = new Date()) {
  const date = value instanceof Date ? new Date(value) : (workshopDateFromKey(value) || new Date(value));
  let safe = Number.isNaN(date.getTime()) ? new Date() : date;
  safe = workshopSetClock(safe, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  const day = new Date(safe.getTime() + 8 * 3600000).getUTCDay();
  return new Date(safe.getTime() + (day === 0 ? -6 : 1 - day) * 86400000);
}

function workshopWeekDates(value = new Date()) {
  const start = workshopWeekStart(value);
  return Array.from({ length: 7 }, (_, index) => {
    return workshopSetClock(new Date(start.getTime() + index * 86400000), WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
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

// Canonical operation-line estimates are stored in decimal hours but the
// server enforces their exact whole-minute total. Do not snap those estimates
// to the planner's 15-minute start-time grid (for example 15.3h is 918
// minutes, not 915 or 930). Start times remain grid-aligned; duration is exact.
function workshopExactDurationHours(value = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return 0;
  const minutes = Math.round(numeric * 60);
  return minutes >= 1 ? minutes / 60 : 0;
}

function workshopExactDurationMinutesFromHours(value = 0) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return 0;
  const minutes = Math.round(numeric * 60);
  return minutes >= 1 ? minutes : 0;
}

function workshopIntervalsOverlap(startA, endA, startB, endB) {
  return Number(startA) < Number(endB) && Number(startB) < Number(endA);
}

function workshopMinuteOfDay(date = new Date()) {
  // r406: Perth minutes since midnight (Perth is always UTC+8).
  const time = new Date(date).getTime();
  return Math.floor((((time / 60000) + 8 * 60) % 1440 + 1440) % 1440);
}

function workshopMinuteOffset(date = new Date()) {
  return workshopMinuteOfDay(date) - WORKSHOP_PLANNER_CONFIG.dayStartMinutes;
}

function workshopWindowApplies(window, date) {
  if (window.dateKey) return window.dateKey === workshopDateKey(date);
  if (window.scope === 'global' || window.scope === 'working_day') return true;
  return WORKSHOP_DAY_NAME_TO_INDEX[window.scope] === new Date(new Date(date).getTime() + 8 * 3600000).getUTCDay();
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

function workshopAvailabilityWindowsForDate(dateValue = new Date(), context = null) {
  const date = dateValue instanceof Date ? new Date(dateValue) : workshopDateFromKey(dateValue);
  if (!date || !workshopIsWorkday(date, context)) return [];
  const shift = workshopBusShift(context);
  const overtime = (shift ? [] : WORKSHOP_PLANNER_CONFIG.overtimeWindowsByDateOrScope)
    .filter(window => workshopWindowApplies(window, date))
    .map(window => ({ ...window, overtime: true }));
  const regular = [{ startMinutes: shift?.startMinutes ?? WORKSHOP_PLANNER_CONFIG.dayStartMinutes, endMinutes: shift?.endMinutes ?? WORKSHOP_PLANNER_CONFIG.dayEndMinutes, overtime: false }];
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

function workshopMoveToNextWorkStart(date = new Date(), context = null) {
  const next = new Date(new Date(date).getTime() + 86400000);
  return workshopNormalizeStartDate(workshopCoerceWorkDate(next, 1, context), context);
}

function workshopMoveToPreviousWorkEnd(date = new Date(), context = null) {
  const previous = new Date(new Date(date).getTime() - 86400000);
  const workDate = workshopCoerceWorkDate(previous, -1, context);
  const windows = workshopAvailabilityWindowsForDate(workDate, context);
  return workshopSetClock(workDate, windows.length ? windows[windows.length - 1].endMinutes : WORKSHOP_PLANNER_CONFIG.dayEndMinutes);
}

function workshopNormalizeStartDate(value = new Date(), context = null) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date, context)) date = workshopCoerceWorkDate(date, 1, context);
  for (let guard = 0; guard < 370; guard += 1) {
    const windows = workshopAvailabilityWindowsForDate(date, context);
    const minute = workshopMinuteOfDay(date);
    for (const window of windows) {
      if (minute <= window.startMinutes) return workshopSetClock(date, window.startMinutes);
      if (minute < window.endMinutes) {
        const snapped = Math.ceil(minute / WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes) * WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
        return workshopSetClock(date, Math.min(snapped, window.endMinutes));
      }
    }
    date = workshopCoerceWorkDate(workshopSetClock(new Date(date.getTime() + 86400000), 0), 1, context);
  }
  return workshopSetClock(date, workshopCalendarStartMinutes(context));
}

function workshopLatestWorkMoment(value = new Date(), context = null) {
  let date = value instanceof Date ? new Date(value) : new Date(value);
  if (Number.isNaN(date.getTime())) date = new Date();
  if (!workshopIsWorkday(date, context)) return workshopMoveToPreviousWorkEnd(date, context);
  const windows = workshopAvailabilityWindowsForDate(date, context);
  const minute = workshopMinuteOfDay(date);
  let latest = null;
  for (const window of windows) {
    if (minute < window.startMinutes) break;
    latest = workshopSetClock(date, Math.min(minute, window.endMinutes));
    if (minute <= window.endMinutes) break;
  }
  return latest || workshopMoveToPreviousWorkEnd(date, context);
}

function workshopAddWorkMinutes(startValue = new Date(), minutes = 0, context = null) {
  let current = startValue instanceof Date ? new Date(startValue) : new Date(startValue);
  if (Number.isNaN(current.getTime())) current = new Date();
  const initialMinute = workshopMinuteOfDay(current);
  const startsInsideWindow = workshopIsWorkday(current, context)
    && workshopAvailabilityWindowsForDate(current, context).some(window => initialMinute >= window.startMinutes && initialMinute < window.endMinutes);
  if (!startsInsideWindow) current = workshopNormalizeStartDate(current, context);
  let remaining = Math.max(0, Number(minutes) || 0);
  while (remaining > 0) {
    const windows = workshopAvailabilityWindowsForDate(current, context);
    const minute = workshopMinuteOfDay(current);
    const window = windows.find(item => minute >= item.startMinutes && minute < item.endMinutes)
      || windows.find(item => minute < item.startMinutes);
    if (!window) {
      current = workshopMoveToNextWorkStart(current, context);
      continue;
    }
    if (minute < window.startMinutes) current = workshopSetClock(current, window.startMinutes);
    const available = window.endMinutes - workshopMinuteOfDay(current);
    if (remaining <= available) return new Date(current.getTime() + remaining * 60000);
    remaining -= available;
    const nextWindow = windows.find(item => item.startMinutes >= window.endMinutes && item.endMinutes > window.endMinutes);
    current = nextWindow ? workshopSetClock(current, nextWindow.startMinutes) : workshopMoveToNextWorkStart(current, context);
  }
  return current;
}

function workshopWorkMinutesBetween(startValue, endValue, context = null) {
  const start = startValue instanceof Date ? new Date(startValue) : new Date(startValue);
  const end = endValue instanceof Date ? new Date(endValue) : new Date(endValue);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end <= start) return 0;
  let date = workshopSetClock(start, 0);
  let total = 0;
  while (date <= end) {
    for (const window of workshopAvailabilityWindowsForDate(date, context)) {
      const windowStart = workshopSetClock(date, window.startMinutes);
      const windowEnd = workshopSetClock(date, window.endMinutes);
      const overlapStart = start > windowStart ? start : windowStart;
      const overlapEnd = end < windowEnd ? end : windowEnd;
      if (overlapEnd > overlapStart) total += (overlapEnd - overlapStart) / 60000;
    }
    date = new Date(date.getTime() + 86400000);
  }
  return total;
}

function workshopEntryStart(entry = {}) {
  return parseIsoTimestamp(entry.startAt || '') || workshopNormalizeStartDate(new Date());
}

function workshopEntryEnd(entry = {}) {
  const start = workshopEntryStart(entry);
  const authoritativeEnd = parseIsoTimestamp(entry.endAt || '');
  if (authoritativeEnd && authoritativeEnd > start) return authoritativeEnd;
  const durationMinutes = (workshopExactDurationHours(entry.hours) || workshopClampDurationHours(entry.hours)) * 60;
  // Historical rows on a date that later became closed remain renderable at
  // their recorded wall-clock position; closure/leave only block new writes.
  if (!workshopIsWorkday(start)) return new Date(start.getTime() + durationMinutes * 60000);
  return workshopAddWorkMinutes(start, durationMinutes, entry);
}

function workshopEntryDisplayCalendar(entry = {}) {
  // Persisted records adopt the Bus shift only when the server marks their
  // calendar migration. Unmigrated history keeps its original display hours.
  return entry.busCalendarVersion === 1 || !entry.endAt ? entry : null;
}

function workshopEntryUsesConfiguredOvertime(entry = {}) {
  const start = workshopEntryStart(entry);
  const end = workshopEntryEnd(entry);
  let date = workshopSetClock(start, 0);
  while (date <= end) {
    for (const window of workshopAvailabilityWindowsForDate(date, workshopEntryDisplayCalendar(entry)).filter(item => item.overtime)) {
      if (workshopIntervalsOverlap(start, end, workshopSetClock(date, window.startMinutes), workshopSetClock(date, window.endMinutes))) return true;
    }
    date = new Date(date.getTime() + 86400000);
  }
  return false;
}

function workshopEntryIsOvertime(entry = {}, now = new Date()) {
  if (!workshopEntryIsLive(entry)) return false;
  const stoppageMoment = entry.status === 'stoppage' ? parseIsoTimestamp(entry.stoppageAt || '') : null;
  if (entry.status === 'stoppage' && !stoppageMoment) return false;
  const liveMoment = stoppageMoment || now;
  return workshopLatestWorkMoment(liveMoment, workshopEntryDisplayCalendar(entry)) > workshopEntryEnd(entry);
}

function workshopEntryEffectiveEnd(entry = {}, now = new Date()) {
  const calendar = workshopEntryDisplayCalendar(entry);
  return new Date(WORKSHOP_BOOKING_TIMING.effectiveEnd({
    status: entry.status,
    actual_end_at: entry.actualEndAt,
    stoppage_started_at: entry.stoppageAt,
  }, {
    plannedEnd: workshopEntryEnd(entry), now,
    latestWorkMoment: value => workshopLatestWorkMoment(new Date(value), calendar),
    addWorkMinutes: (value, minutes) => workshopAddWorkMinutes(new Date(value), minutes, calendar),
    incrementMinutes: WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes,
  }));
}

function workshopEntrySegmentForDate(entry = {}, dateKey = '', now = new Date()) {
  const calendar = workshopEntryDisplayCalendar(entry);
  let dayStart = workshopDateFromKey(dateKey);
  if (!dayStart || !workshopIsConfiguredWorkingDay(dayStart, calendar)) return null;
  dayStart = workshopSetClock(dayStart, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  let dayEnd = workshopSetClock(dayStart, WORKSHOP_PLANNER_CONFIG.dayEndMinutes);
  // A short working day uses the same timeline scale as weekdays, but its
  // continuation card must stop at that day's actual opening/closing times.
  // Keep recorded closure history visible using the original display envelope.
  if (!workshopIsClosureDate(dayStart)) {
    const windows = workshopAvailabilityWindowsForDate(dayStart, calendar);
    if (!windows.length) return null;
    dayStart = workshopSetClock(dayStart, Math.max(WORKSHOP_PLANNER_CONFIG.dayStartMinutes, windows[0].startMinutes));
    dayEnd = workshopSetClock(dayEnd, Math.min(WORKSHOP_PLANNER_CONFIG.dayEndMinutes, windows[windows.length - 1].endMinutes));
  }
  const start = workshopEntryStart(entry);
  const end = workshopEntryEffectiveEnd(entry, now);
  if (end <= dayStart || start >= dayEnd) return null;
  const segmentStart = start > dayStart ? start : dayStart;
  const segmentEnd = end < dayEnd ? end : dayEnd;
  const startMinutes = Math.max(0, workshopMinuteOffset(segmentStart));
  const displayEndMinutes = workshopMinuteOffset(dayEnd);
  const endMinutes = Math.min(displayEndMinutes, workshopMinuteOffset(segmentEnd));
  return {
    start: startMinutes,
    end: Math.min(displayEndMinutes, Math.max(startMinutes + WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, endMinutes)),
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

// Section 13 fail-closed connection status. Distinguishes the states the
// migration plan requires: Connected/editable, Connected/read-only,
// Reconnecting, Offline/read-only, Backend version incompatible.
// r561 (F175): compact status dot with tooltip (blue / grey / red — no orange).
function workshopConnectionBannerHtml() {
  const ds = window.__workshopDataService;
  const state = ds && typeof ds.getState === 'function' ? ds.getState() : 'disabled';
  const CS = window.WORKSHOP_CONNECTION_STATE || {};
  const copy = {
    [CS.CONNECTED_EDITABLE]: { cls: 'ok', text: 'Connected · shared workshop data · live editing enabled' },
    [CS.CONNECTED_READ_ONLY]: { cls: 'warn', text: 'Connected · read-only (viewer role, or editing is not yet unlocked for this account)' },
    [CS.RECONNECTING]: { cls: 'warn', text: 'Reconnecting to shared workshop data… showing the last known state' },
    [CS.OFFLINE_READ_ONLY]: { cls: 'error', text: 'Offline · showing the last known shared state, read-only until the connection recovers' },
    [CS.INCOMPATIBLE]: { cls: 'error', text: 'Backend version incompatible with this Workshop Planner build. Contact an administrator.' },
    [CS.PERMISSION_DENIED]: { cls: 'error', text: 'Access denied · this account does not have permission to view Workshop Planner station data. Contact an administrator.' },
    [CS.CONNECTING]: { cls: 'warn', text: 'Connecting to shared workshop data…' },
  }[state] || { cls: 'warn', text: 'Shared workshop mode status unknown' };
  const label = escapeHtml(copy.text);
  return `<span class="workshop-connection-banner workshop-connection-dot workshop-connection-${copy.cls}" role="status" tabindex="0" title="${label}" aria-label="${label}"><span class="sr-only">${label}</span></span>`;
}

function workshopStationSnapshotEmptyStateHtml(stage) {
  const ds = window.__workshopDataService;
  const state = ds && typeof ds.getState === 'function' ? ds.getState() : 'disabled';
  const CS = window.WORKSHOP_CONNECTION_STATE || {};
  if (state === CS.PERMISSION_DENIED) {
    return `<div class="empty-state workshop-station-unavailable" role="alert">${workshopConnectionBannerHtml()}<strong>Workshop Planner access unavailable</strong><span>This account does not have permission to view ${escapeHtml(pmbStageLabel(stage))}. Contact an administrator.</span></div>`;
  }
  return `<div class="empty-state workshop-station-loading" role="status">${workshopConnectionBannerHtml()}<strong>Loading ${escapeHtml(pmbStageLabel(stage))}</strong><span>Waiting for the selected station snapshot…</span></div>`;
}


// Maps one get_workshop_snapshot() booking DTO (see migration 012) into the
// same legacy plan-row shape the rest of this file already expects, so the
// existing rendering/interaction code needs no changes to read shared data.
function workshopMapSnapshotBookingToLegacyRow(booking = {}, vehicleById = null) {
  if (!booking || !booking.booking_id) return null;
  const sharedVehicleId = String(booking.vehicle_id || booking.vehicle?.id || '').trim();
  // A shared booking without its canonical vehicle UUID is not safe to adapt:
  // stock/permanent-id text can change or be duplicated. Fail closed instead
  // of creating a legacy row that later has to reverse-map by first match.
  if (!sharedVehicleId) return null;
  const vehicle = booking.vehicle || vehicleById?.get(sharedVehicleId) || {};
  const stage = booking.stage || {};
  const bay = booking.bay || null;
  const assignment = booking.assignment || null;
  const estimatedOperationHours = Number(booking.estimated_operation_hours);
  const storedBookingHours = Number(booking.default_duration_minutes || 0) / 60;
  const scheduledDurationMinutes = Number(booking.default_duration_minutes || 0);
  const legacyStatus = { queued: 'planned', planned: 'planned', started: 'started', stoppage: 'stoppage', completed: 'completed', deleted: 'deleted' }[booking.status] || 'planned';
  return {
    id: booking.booking_id,
    sharedBookingId: booking.booking_id,
    sharedVersion: booking.version,
    sharedStatus: booking.status,
    workCategory: booking.work_category || '',
    busCalendarVersion: booking.bus_calendar_version === 1 ? 1 : null,
    busWorkflowDepartment138: vehicle.bus_workflow_department138 === true
      || (Array.isArray(vehicle.department_codes) && vehicle.department_codes.some(code => String(code) === '138')),
    fitterProgress: booking.fitter_progress || null,
    sharedVehicleId,
    sharedBayId: bay ? String(bay.id || bay.bay_id || booking.bay_id || '') : String(booking.bay_id || ''),
    // sharedVehicleId remains the only authority. The display key is resolved
    // from the separately scoped vehicle DTO; UUID fallback keeps the booking
    // renderable without inventing or reverse-matching mutable identifiers.
    vehicleKey: vehicle.stock_number || vehicle.permanent_vehicle_id || sharedVehicleId,
    stage: normalizePmbStage(stage.code || ''),
    bay: bay ? Number(bay.bay_number) || 0 : 0,
    startAt: booking.scheduled_start_at,
    endAt: booking.scheduled_end_at,
    // The booking allocation is authoritative for chip geometry after a
    // resize/cascade. Operation-line estimates remain separate evidence and
    // must never shrink a scheduled booking back to its stale estimate.
    hours: scheduledDurationMinutes > 0
      ? workshopExactDurationHours(storedBookingHours)
      : (Number.isFinite(estimatedOperationHours) && estimatedOperationHours > 0
        ? workshopExactDurationHours(estimatedOperationHours)
        : workshopDefaultBookingHours()),
    operationEstimateHours: Number.isFinite(estimatedOperationHours) && estimatedOperationHours > 0
      ? workshopExactDurationHours(estimatedOperationHours) : 0,
    scheduledDurationMinutes: scheduledDurationMinutes > 0 ? scheduledDurationMinutes : 0,
    capacityBaseMinutes: Number(booking.capacity_base_minutes) > 0 ? Number(booking.capacity_base_minutes) : null,
    capacityEfficiencyPercent: Number(booking.capacity_efficiency_percent) > 0 ? Number(booking.capacity_efficiency_percent) : null,
    assignee: assignment ? assignment.technician_name || '' : '',
    technicianId: assignment ? assignment.technician_id || '' : '',
    helperAssignments: Array.isArray(booking.helper_assignments)
      ? booking.helper_assignments.map(row => ({ technicianId: String(row.technician_id || ''), name: String(row.technician_name || '') })).filter(row => row.technicianId)
      : (Array.isArray(booking.helper_technician_ids) ? booking.helper_technician_ids.map(id => ({technicianId:String(id),name:''})) : []),
    helperLabour: Array.isArray(booking.helper_labour) ? booking.helper_labour : [],
    helperLabourMinutes: Number(booking.helper_labour_minutes || 0),
    helperAssignmentHistory: Array.isArray(booking.helper_assignment_history)
      ? booking.helper_assignment_history.map(row => ({technicianId:String(row.technician_id || ''),name:String(row.technician_name || ''),assignedAt:row.assigned_at,releasedAt:row.released_at})).filter(row => row.technicianId) : [],
    status: legacyStatus,
    stoppageReason: booking.stoppage_reason || '',
    stoppageAt: booking.stoppage_started_at || '',
    stoppageMinutes: Number(booking.stoppage_accumulated_minutes || 0),
    actualStartAt: booking.actual_start_at || '',
    actualEndAt: booking.actual_end_at || '',
    actualHours: booking.actual_start_at && booking.actual_end_at
      ? (new Date(booking.actual_end_at).getTime() - new Date(booking.actual_start_at).getTime()) / 3600000
      : undefined,
    completedAt: booking.actual_end_at || '',
    createdAt: booking.created_at,
    updatedAt: booking.updated_at,
  };
}

function workshopAnnotateLegacyAmbiguity(rows = []) {
  const active = rows.filter(row => normalizePmbStage(row.stage) === 'HOIST'
    && !['completed', 'deleted', 'cancelled'].includes(row.status));
  const counts = new Map();
  active.forEach(row => {
    const key = `${row.sharedVehicleId}:${normalizePmbStage(row.stage)}`;
    counts.set(key, (counts.get(key) || 0) + 1);
  });
  return rows.map(row => {
    if (normalizePmbStage(row.stage) !== 'HOIST'
      || ['completed', 'deleted', 'cancelled'].includes(row.status)) return row;
    const duplicate = (counts.get(`${row.sharedVehicleId}:${normalizePmbStage(row.stage)}`) || 0) > 1;
    const completedMarker = Boolean(row.completedAt);
    if (!duplicate && !completedMarker) return row;
    return {
      ...row,
      legacyAmbiguityReason: duplicate
        ? 'Legacy review required: multiple active bookings exist for this vehicle and station.'
        : 'Legacy review required: this active booking also contains a completion marker.',
    };
  });
}

let workshopSharedPlansCache = { snapshot: null, bookings: null, rows: null };
let workshopLastAdministratorMove = null;
let workshopAdminPaletteDurationMinutes = 30;
let workshopAdminBlockFeedback = { tone: '', message: '' };
const WORKSHOP_PENDING_STARTS = new Set();
const WORKSHOP_PENDING_BAY_ASSIGNMENTS = new Set();
const WORKSHOP_PENDING_BOOKING_ACTIONS = new Map();
let workshopStartFeedback = { stage: '', message: '' };
const WORKSHOP_ADMIN_SAFE_DURATION_DAYS = 90;
let workshopActiveQueuePointerDrag = null;
let workshopActivePointerResize = null;
let workshopSuppressMouseDragUntil = 0;

function workshopAdministratorCanMove(role = (typeof window !== 'undefined' ? window.PDC_AUTH_CONTEXT?.role : '')) {
  // The existing receipt-backed RPC names are retained for deployed clients.
  // Controller is stored as operator; administrative blocks have a separate gate.
  return ['operator', 'administrator'].includes(String(role || '').trim().toLowerCase());
}

function workshopNewRequestId() {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.floor(Math.random() * 16);
    return (c === 'x' ? r : (r & 3) | 8).toString(16);
  });
}

function workshopRememberAdministratorMove(result = {}) {
  if (!result.receipt_id || !result.booking_id || !Number.isFinite(Number(result.booking_version))) return;
  workshopLastAdministratorMove = {
    receiptId: String(result.receipt_id),
    bookingId: String(result.booking_id),
    expectedVersion: Number(result.booking_version),
    undoRequestId: workshopNewRequestId(),
  };
  workshopRedrawForUndoMoveButton();
}

// r498 (F111): the planner redraws from the snapshot refresh before the move
// receipt is kept, so draw once more to show or hide 'Undo last move' now.
function workshopRedrawForUndoMoveButton() {
  if (typeof scheduleWorkshopPlannerRender === 'function') scheduleWorkshopPlannerRender();
}

function workshopAdministratorErrorDetail(result = {}) {
  const body = result && typeof result.body === 'object' ? result.body : null;
  const code = result.code || body?.code || body?.error || result.error || '';
  const message = result.message || body?.message || body?.details || body?.hint || '';
  const status = Number.isFinite(Number(result.status)) ? `HTTP ${Number(result.status)}` : '';
  return [message, code && !String(message).includes(String(code)) ? code : '', status].filter(Boolean).join(' · ');
}

async function workshopUndoLastAdministratorMove() {
  const receipt = workshopLastAdministratorMove;
  if (!receipt || !workshopAdministratorCanMove()) return false;
  const result = await workshopDispatchSharedAction('undoAdministratorBookingMove', {
    receiptId: receipt.receiptId,
    expectedVersion: receipt.expectedVersion,
    requestId: receipt.undoRequestId,
  });
  if (!result?.ok) return false;
  workshopLastAdministratorMove = null;
  workshopRedrawForUndoMoveButton();
  return true;
}

function workshopAdminBlockCanMutate(role = window.PDC_AUTH_CONTEXT?.role) {
  return String(role || '').trim().toLowerCase() === 'administrator';
}

function workshopLoadAdminBlocks() {
  if (!workshopSharedModeActive()) return [];
  const snapshot = window.__workshopDataService?.getTrustedSnapshot?.();
  const blocks = Array.isArray(snapshot?.admin_blocks) ? snapshot.admin_blocks : [];
  return blocks.map(block => ({
    id: String(block.id || ''),
    version: Number(block.version),
    stage: normalizePmbStage(block.stage_code || block.stage?.code || ''),
    bay: Number(block.bay_number || block.bay?.bay_number || 0),
    type: String(block.block_type || 'admin').toLowerCase(),
    label: cleanNavisionText(block.label || ''),
    startAt: block.scheduled_start_at,
    endAt: block.scheduled_end_at,
    durationMinutes: Number(block.duration_minutes || 0),
  })).filter(block => block.id && block.stage && block.bay && block.startAt && block.endAt);
}

function workshopAdminBlockSegments(block = {}, dateKey = '') {
  const start = parseIsoTimestamp(block.startAt);
  const end = parseIsoTimestamp(block.endAt);
  const date = workshopDateFromKey(dateKey);
  if (!start || !end || !date || !workshopIsConfiguredWorkingDay(date)) return [];
  const dayStart = workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayStartMinutes);
  const dayEnd = workshopSetClock(date, WORKSHOP_PLANNER_CONFIG.dayEndMinutes);
  if (end <= dayStart || start >= dayEnd) return [];

  // The persisted end is authoritative. Project only the configured working
  // windows for this date so a multi-day block never appears as a clipped
  // one-day wall interval or crosses a configured break.
  const segments = workshopAvailabilityWindowsForDate(date).map(window => {
    const windowStart = workshopSetClock(date, Math.max(window.startMinutes, WORKSHOP_PLANNER_CONFIG.dayStartMinutes));
    const windowEnd = workshopSetClock(date, Math.min(window.endMinutes, WORKSHOP_PLANNER_CONFIG.dayEndMinutes));
    const segmentStart = start > windowStart ? start : windowStart;
    const segmentEnd = end < windowEnd ? end : windowEnd;
    if (segmentEnd <= segmentStart) return null;
    return {
      start: Math.max(0, workshopMinuteOffset(segmentStart)),
      end: Math.min(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes, workshopMinuteOffset(segmentEnd)),
      continuesFromPrevious: segmentStart > start,
      continuesNext: segmentEnd < end,
      usesConfiguredOvertime: window.overtime === true,
    };
  }).filter(segment => segment && segment.end > segment.start);
  return segments.map((segment, index) => ({
    ...segment,
    continuesFromPrevious: segment.continuesFromPrevious || index > 0,
    continuesNext: segment.continuesNext || index < segments.length - 1,
  }));
}

function workshopAdminBlockSegment(block = {}, dateKey = '') {
  return workshopAdminBlockSegments(block, dateKey)[0] || null;
}

function workshopAdminBlockHtml(block = {}, dateKey = '') {
  const segments = workshopAdminBlockSegments(block, dateKey);
  if (!segments.length) return '';
  const label = block.label || ({ training: 'Training', sick: 'Sick leave', admin: 'Admin downtime' }[block.type] || 'Admin downtime');
  const editable = workshopAdminBlockCanMutate();
  const totalHours = Number(block.durationMinutes || 0) / 60;
  const totalLabel = Number.isInteger(totalHours) ? `${totalHours}h total` : `${totalHours.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')}h total`;
  return segments.map((segment, index) => {
    const left = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    const width = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    const continuation = segment.continuesFromPrevious ? ' · CONTINUED' : '';
    const continues = segment.continuesNext ? ' · continues next valid work interval' : '';
    const segmentLabel = `${workshopTimeLabelFromMinutes(segment.start)}–${workshopTimeLabelFromMinutes(segment.end)} · ${index === 0 ? totalLabel : 'continued'}${continuation}${continues}`;
    const controls = editable && index === 0
      ? '<span class="workshop-admin-block-controls"><button type="button" data-workshop-admin-block-rename aria-label="Rename admin block">Rename</button><button type="button" data-admin-block-nudge="-15" aria-label="Move 15 minutes earlier">−15m</button><button type="button" data-admin-block-nudge="15" aria-label="Move 15 minutes later">+15m</button><button type="button" data-admin-block-resize="15" aria-label="Extend 15 minutes">+ length</button><button type="button" data-admin-block-delete aria-label="Delete admin block">×</button></span><span class="workshop-admin-block-resize" data-admin-block-pointer-resize title="Drag to resize" aria-hidden="true"></span>'
      : '';
    return `<article class="workshop-admin-block type-${escapeHtml(block.type)}${segment.continuesFromPrevious ? ' continues-from-previous' : ''}${segment.continuesNext ? ' continues-next' : ''}${index > 0 ? ' is-continuation' : ''}" draggable="${editable && index === 0}" tabindex="0" role="group" aria-label="${escapeHtml(`${label}, ${segmentLabel}.${editable ? ' Arrow keys move; Shift plus Arrow keys resize.' : ' Read only.'}`)}" data-workshop-admin-block-id="${escapeHtml(block.id)}" data-workshop-admin-block-segment="${index + 1}" style="--plan-left:${left}%;--plan-width:${width}%;">
      <strong>ADMIN · ${escapeHtml(label)}${index > 0 ? ' · CONTINUED' : ''}</strong><small>${escapeHtml(segmentLabel)}</small>
      ${controls}
    </article>`;
  }).join('');
}

function workshopLoadPlans() {
  if (workshopSharedModeActive()) {
    const snapshot = window.__workshopDataService.getTrustedSnapshot?.();
    const bookings = snapshot && Array.isArray(snapshot.bookings) ? snapshot.bookings : null;
    if (bookings) {
      if (snapshot === workshopSharedPlansCache.snapshot
        && bookings === workshopSharedPlansCache.bookings
        && Array.isArray(workshopSharedPlansCache.rows)) {
        return workshopSharedPlansCache.rows;
      }
      const vehicleById = new Map((Array.isArray(snapshot.vehicles) ? snapshot.vehicles : [])
        .filter(vehicle => vehicle?.id)
        .map(vehicle => [String(vehicle.id), vehicle]));
      const rows = workshopAnnotateLegacyAmbiguity(bookings
        .map(booking => workshopMapSnapshotBookingToLegacyRow(booking, vehicleById))
        .filter(row => row && row.id && row.vehicleKey && WORKSHOP_STAGE_SEQUENCE.includes(row.stage))
        .map(row => row.status === 'completed' ? row : { ...row, hours: workshopExactDurationHours(row.hours) || workshopClampDurationHours(row.hours) }));
      workshopSharedPlansCache = { snapshot, bookings, rows };
      return rows;
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
    // Shared writes are owned exclusively by the protected RPC bridge. Keep
    // browser-local persistence fail-closed without imposing a global lock on
    // valid canonical bookings.
    console.error('Blocked legacy Workshop serializer in shared mode; use a protected shared action.');
    return false;
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
  workshopNotify('Set your operator name and role before changing the Workshop Planner. No workshop data was changed.');
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
// Future planning must not claim that Parts are ready or reserve stock. When a
// booking action encounters the Parts gate, retry once with an explicit,
// truthful planning-only audit reason. The database remains the authority on
// role permission and records the exception; live workshop entry/readiness
// gates are unchanged.
const WORKSHOP_PLANNING_OVERRIDE_CAPABLE_ACTIONS = new Set(['moveBooking', 'cascadeMoveBooking', 'scheduleVehicleWork', 'cascadeSchedule']);

function workshopSharedLegacyAmbiguity(payload = {}) {
  const bookingId = String(payload.bookingId || payload.targetId || '').trim();
  if (!bookingId) return null;
  if (!window.__workshopDataService || typeof window.__workshopDataService.getLastSnapshot !== 'function') return null;
  return workshopLoadPlans().find(row => row.id === bookingId && row.legacyAmbiguityReason) || null;
}

function workshopBeginBookingAction(bookingId, actionName) {
  const id = String(bookingId || '').trim().toLowerCase();
  if (!id || WORKSHOP_PENDING_BOOKING_ACTIONS.has(id)) return null;
  const token = { bookingId: id, actionName, actor: window.PDC_AUTH_CONTEXT?.userId, role: window.PDC_AUTH_CONTEXT?.role };
  WORKSHOP_PENDING_BOOKING_ACTIONS.set(id, token);
  return token;
}

function workshopEndBookingAction(token) {
  if (token && WORKSHOP_PENDING_BOOKING_ACTIONS.get(token.bookingId) === token) {
    WORKSHOP_PENDING_BOOKING_ACTIONS.delete(token.bookingId);
  }
}

// r482 (F95, Craig 22 Oct): every planner path that books or moves a bay booking comes through
// workshopDispatchSharedAction (drag/drop from Unallocated, search or Find, chip moves, the Schedule window,
// Best slot / Schedule next, the booking detail form, weekly moves, bay re-order, and the vehicle card's station
// Schedule). Before the command is sent, a booking whose start (Perth date) is before the vehicle's active parts
// ETA asks "Book anyway" or "Cancel" (pdc-parts-eta.js). Cancel sends nothing; Book anyway sends the same command,
// with p_metadata.parts_eta_warning recording the acknowledgement where the command takes metadata. No ETA, an
// ETA on or before the start date, or an unchanged start and bay asks nothing. Extend / resize keep the start.
const WORKSHOP_PARTS_ETA_ACKNOWLEDGED = new WeakMap();
const WORKSHOP_PARTS_ETA_PREVIEWS = new Map();
function workshopPartsEtaPlan(bookingId) {
  const id = String(bookingId || '').trim().toLowerCase();
  if (!id || typeof workshopLoadPlans !== 'function') return null;
  return workshopLoadPlans().find(row => String(row.sharedBookingId || row.id || '').toLowerCase() === id) || null;
}
function workshopPartsEtaGroups(actionName, payload = {}) {
  const station = code => (typeof pmbStageLabel === 'function' ? pmbStageLabel(normalizePmbStage(code)) : String(code || ''));
  const fromPlan = (plan, stageCode, bayNumber, startAt) => {
    if (!plan || !startAt) return null;
    const sameStart = Date.parse(startAt) === Date.parse(plan.startAt);
    const sameBay = normalizePmbStage(stageCode || plan.stage) === normalizePmbStage(plan.stage) && Number(bayNumber || plan.bay) === Number(plan.bay);
    if (sameStart && sameBay) return null; // nothing new is booked
    return { vehicle: { id: plan.sharedVehicleId, stock: plan.vehicleKey }, bookings: [{ station: station(stageCode || plan.stage), bay: Number(bayNumber || plan.bay) || '', start: startAt }] };
  };
  const fromVehicle = (vehicleId, stageCode, bayNumber, startAt) => {
    if (!vehicleId || !startAt) return null;
    const row = typeof workshopVehicle === 'function' ? workshopVehicle(vehicleId, normalizePmbStage(stageCode)) : null;
    return { vehicle: { id: vehicleId, stock: row?.stock || '' }, bookings: [{ station: station(stageCode), bay: Number(bayNumber) || '', start: startAt }] };
  };
  switch (actionName) {
    case 'scheduleVehicleWork':
    case 'administratorScheduleVehicle':
      return [fromVehicle(payload.vehicleId, payload.stageCode, payload.bayNumber, payload.scheduledStartAt)].filter(Boolean);
    case 'moveBooking':
    case 'cascadeMoveBooking':
    case 'administratorMoveBooking':
      return [fromPlan(workshopPartsEtaPlan(payload.bookingId), payload.stageCode, payload.bayNumber, payload.scheduledStartAt)].filter(Boolean);
    case 'changeBookingBay': {
      const plan = workshopPartsEtaPlan(payload.bookingId);
      return [fromPlan(plan, plan?.stage, payload.bayNumber, plan?.startAt)].filter(Boolean); // same start, new bay
    }
    case 'cascadeSchedule':
      if (payload.operation === 'schedule') return [fromVehicle(payload.targetId, payload.stageCode, payload.bayNumber, payload.scheduledStartAt)].filter(Boolean);
      if (payload.operation === 'move') return [fromPlan(workshopPartsEtaPlan(payload.targetId), payload.stageCode, payload.bayNumber, payload.scheduledStartAt)].filter(Boolean);
      return []; // extend keeps the start
    case 'resequenceBay': {
      if (payload.apply !== true) return [];
      const preview = WORKSHOP_PARTS_ETA_PREVIEWS.get(String(payload.planHash || ''));
      const groups = new Map();
      for (const change of Array.isArray(preview?.changes) ? preview.changes : []) {
        if (!change?.vehicle_id || !change.to_start || Date.parse(change.to_start) === Date.parse(change.from_start)) continue;
        const plan = workshopPartsEtaPlan(change.booking_id);
        const key = String(change.vehicle_id);
        if (!groups.has(key)) groups.set(key, { vehicle: { id: change.vehicle_id, stock: plan?.vehicleKey || '' }, bookings: [] });
        groups.get(key).bookings.push({ station: station(change.stage_code || plan?.stage), bay: Number(change.bay_number) || '', start: change.to_start });
      }
      return [...groups.values()];
    }
    default:
      return [];
  }
}
const WORKSHOP_PARTS_ETA_METADATA_ACTIONS = new Set(['scheduleVehicleWork', 'administratorScheduleVehicle', 'moveBooking', 'cascadeMoveBooking', 'administratorMoveBooking', 'changeBookingBay', 'cascadeSchedule']);
/** The payload to send (with the acknowledgement when asked), or null when Cancel was chosen. A replay of the
 * same payload object (the planner's uncertain-outcome retry) reuses the first answer and bytes. */
async function workshopPartsEtaConfirm(actionName, payload) {
  if (payload && typeof payload === 'object' && WORKSHOP_PARTS_ETA_ACKNOWLEDGED.has(payload)) return WORKSHOP_PARTS_ETA_ACKNOWLEDGED.get(payload);
  const guard = typeof window !== 'undefined' ? window.PDC_PARTS_ETA : null;
  if (!guard || typeof guard.confirmBookings !== 'function') return payload;
  let groups = [];
  try { groups = workshopPartsEtaGroups(actionName, payload); } catch (_) { groups = []; }
  if (!groups.length) return payload;
  const answer = await guard.confirmBookings(groups);
  if (!answer || answer.ok !== true) return null;
  if (!answer.warnings?.length) return payload;
  const ack = typeof guard.acknowledgement === 'function' ? guard.acknowledgement(answer.warnings) : null;
  const sent = ack && WORKSHOP_PARTS_ETA_METADATA_ACTIONS.has(actionName)
    ? { ...payload, metadata: { ...(payload.metadata || {}), parts_eta_warning: ack } }
    : payload;
  WORKSHOP_PARTS_ETA_ACKNOWLEDGED.set(payload, sent);
  return sent;
}

async function workshopDispatchSharedAction(actionName, payload, renderAction = renderWorkshopPlanner, options = {}) {
  if (!workshopSharedModeActive()) return null;
  const bookingId = String(payload?.bookingId || (actionName === 'cascadeSchedule' && payload?.operation !== 'schedule' ? payload?.targetId : '') || '').trim().toLowerCase();
  const suppliedToken = options.bookingActionToken;
  const actionToken = bookingId ? (suppliedToken || workshopBeginBookingAction(bookingId, actionName)) : null;
  if (bookingId && (!actionToken || actionToken.bookingId !== bookingId || WORKSHOP_PENDING_BOOKING_ACTIONS.get(bookingId) !== actionToken)) {
    return { ok: false, error: 'booking_action_in_flight' };
  }
  try {
    if (!await workshopEnsureCurrentDeployment()) return { ok: false, error: 'stale_deployment_reload' };
    if (actionToken && (actionToken.actor !== window.PDC_AUTH_CONTEXT?.userId || actionToken.role !== window.PDC_AUTH_CONTEXT?.role)) {
      return { ok: false, error: 'authority_superseded' };
    }
    const ambiguous = workshopSharedLegacyAmbiguity(payload);
    if (ambiguous) {
      const result = { ok: false, error: 'legacy_ambiguity_blocked', bookingId: ambiguous.id };
      workshopNotify(`${ambiguous.legacyAmbiguityReason} No change was made.`);
      renderAction();
      return result;
    }
    const actions = window.__workshopSharedActions;
    if (!actions || typeof actions[actionName] !== 'function') {
      workshopNotify('Shared workshop mode is connected but this action is not yet available. No change was made.');
      return { ok: false, error: 'action_unavailable' };
    }
    let result;
    const changeStartedAt = new Date(Date.now() - 60000).toISOString();
    // r482 (F95): parts ETA warning before anything is sent; Cancel sends nothing.
    const sendPayload = await workshopPartsEtaConfirm(actionName, payload);
    try {
      result = sendPayload === null
        ? { ok: false, error: 'parts_eta_not_confirmed', cancelled: true }
        : await actions[actionName](sendPayload);
      if (actionName === 'resequenceBay' && payload?.apply !== true && result?.ok === true && result.plan_hash) {
        WORKSHOP_PARTS_ETA_PREVIEWS.clear();
        WORKSHOP_PARTS_ETA_PREVIEWS.set(String(result.plan_hash), result);
      }
      // Parts is tracked and warned on, but never retried through an override
      // path: a Parts-gate response now proves a stale runtime/database contract.
    } catch (error) {
      result = workshopAdministratorCanMove()
        ? { ok: false, error: 'runtime_failure', message: error?.message || String(error || '') }
        : { ok: false, error: 'runtime_failure' };
    }
    const commandCommitted = result?.ok === true || result?.committed === true;
    if ((!result || result.ok !== true) && !commandCommitted && options.suppressFailureAlert !== true) {
      workshopNotify(workshopDescribeSharedActionError(result));
    }
    if (result?.ok === true && result.refreshRequired === true && options.suppressFailureAlert !== true) {
      workshopNotify('Your change was saved, but the planner could not refresh yet. Refresh the planner before making another change.');
    }
    if (result?.ok === true && result.refreshRequired !== true && /schedule|move|extend|cascade/i.test(actionName) && window.PDC_VEHICLE_HANDOVER) {
      await window.PDC_VEHICLE_HANDOVER.warn(changeStartedAt);
    }
    if (options.suppressRender !== true) renderAction();
    return result || { ok: false, error: 'no_response' };
  } finally {
    if (!suppliedToken) workshopEndBookingAction(actionToken);
  }
}

// Human-readable, never-a-stack-trace error mapping per section 14 of the
// project brief. Falls back to a safe generic message for anything not
// explicitly mapped, so a raw Postgres/PostgREST error is never shown.
// Plain-English text for server codes that used to reach staff raw (F11).
// test_planner_error_messages_403.js checks every canonical mutation code
// has a message, so a new server code cannot ship without one.
const WORKSHOP_PLAIN_ERROR_MESSAGES = Object.freeze({
  // r417 (F32): a bay rule mismatch is a warning the planner confirms.
  bay_rule_warning: "This bay's rule does not match this booking. No change was made. Drag it again and choose OK to book it here anyway.",
  bay_rule_not_confirmed: 'No change was made. The bay rule was not overridden.',
  // r482 (F95): Cancel on the parts ETA warning.
  parts_eta_not_confirmed: 'No booking was made. The parts are not due until after that date.',
  // r424 (F38): push-back warning, bay re-order and its undo.
  later_bookings_warning: "This job would run into the same vehicle's next booking. No change was made. Drag it again and choose OK to push the later booking back.",
  later_bookings_not_confirmed: 'No change was made. The later bookings were not pushed back.',
  resequence_rejected: 'This re-order could not be saved because it would overlap another booking or break a booking rule. No change was made.',
  plan_changed: 'The bay changed while you were looking at the preview. No change was made. Drag the job again to see the new preview.',
  order_unchanged: 'That would leave the bay in the same order. No change was made.',
  not_same_bay: 'Both jobs need to be in the same bay to re-order them. Move the job into this bay first. No change was made.',
  started_job_fixed: 'A started job keeps its place and times. Stop it first, or re-order the jobs around it. No change was made.',
  resequence_too_large: 'Too many bookings would move at once. Re-order a few jobs at a time. No change was made.',
  booking_not_found: 'That booking no longer exists. The planner has refreshed; no change was made.',
  protected_booking: "This job has already been started, so it can't be moved here. No change was made. Ask a manager to re-plan it.",
  invalid_admin_block_type: 'That kind of admin block is not recognised. Choose leave, bay downtime or another listed block type. No change was made.',
  admin_block_not_found: 'That admin block no longer exists. It may have been removed by someone else. The planner has refreshed; no change was made.',
  invalid_label: 'Enter a short name for this item (letters, numbers and simple punctuation). No change was made.',
  invalid_idempotency_key: 'This action could not be sent safely. Refresh the planner and try again. No change was made.',
  idempotency_conflict: 'This action was already sent with different details. Refresh the planner to see what was saved before trying again.',
  // r569 (F183): pause the live bay job and start another one behind it.
  same_vehicle: 'Pausing a job to start another job of the same vehicle is not available here. No change was made.',
  different_station: 'That job is on a different station. No change was made.',
  not_unstarted: 'Pick an unstarted job. No change was made.',
  not_live: 'This job is not running in a bay, so it was not paused. No change was made.',
  bay_busy_with_others: 'This bay already has another booking in the time the paused job would move into. No change was made.',
  bad_duration: 'That job has no duration, so it was not started. No change was made.',
  remaining_too_long: 'The remaining time is too long to move in one step. No change was made.',
  vehicle_not_found: 'One of these vehicles is not on the board. No change was made.',
  pause_failed: 'The pause could not be saved. No change was made.',
  not_authorized: 'You do not have permission to pause a job for another one. No change was made.',
  stop_failed: 'The running job could not be paused. No change was made.',
  move_failed: 'The paused job could not be moved behind the new one. No change was made.',
  start_failed: 'The other job could not be started. No change was made.',
  receipt_not_found: 'There is nothing to undo for this action any more. Refresh the planner to see the current schedule.',
  undo_actor_mismatch: 'Only the person who made this change can undo it. Ask them, or a manager, to change it back.',
  already_undone: 'This change has already been undone. No further change was made.',
  undo_expired: 'This change is too old to undo. Make the change again by hand if it needs to go back.',
  undo_conflict: 'This change cannot be undone because the schedule has changed since. Refresh the planner and adjust it by hand. No change was made.',
});

function workshopDescribeSharedActionError(result) {
  const error = result && result.error;
  const conflict = result && result.conflict;
  if (error === '55P03') return 'The workshop is busy finishing another update. No changes were saved. Please try again shortly.';
  if (result?.outcomeUnknown === true || ['runtime_failure', 'no_response', 'request_failed'].includes(error)) {
    return 'The change could not be confirmed. Refresh the planner to check its current state before trying again.';
  }
  if (error === 'booking_action_in_flight') return 'This booking is already being updated. Wait for that change to finish.';
  if (error === 'version_conflict') {
    return 'This booking was changed by another user. The planner has refreshed to the latest version.';
  }
  if (error === 'vehicle_version_conflict') {
    return 'This vehicle changed while it was being scheduled. The latest record has been loaded; please try again.';
  }
  if (error === 'fixed_booking_conflict' || error === 'live_booking_conflict') {
    return 'This change conflicts with a job already running or on stoppage. No changes were saved. Check the occupied bay or choose another available time.';
  }
  if (error === 'admin_block_conflict') {
    return 'That time is reserved by an admin block, such as leave or bay downtime. No changes were saved. Choose an available bay or a time after the block.';
  }
  if (error === 'concurrent_queue_change' || error === 'schedule_changed') {
    return 'The schedule changed while this action was being checked. The planner has refreshed; review the latest bookings and try again.';
  }
  if (error === 'schedule_write_order_blocked' || error === 'no_available_slot') {
    return 'The affected jobs could not be safely moved into available working time. No changes were saved. Ask the controller to review the surrounding bookings.';
  }
  if (error === 'technician_unavailable') return 'An assigned mechanic is unavailable during this work. Check their assignment or leave before starting.';
  if (error === 'invalid_team') return 'Choose one primary technician and up to eight different helpers. Each person can appear only once on this team.';
  if (error === 'active_department138_booking_required') return 'Team changes require an active Department 138 booking in a physical bay. Refresh and select that booking.';
  if (error === 'request_conflict') return 'This save reference was already used for different values. Refresh and review the saved team or helper time before trying again.';
  if (error === 'invalid_helper_labour') return 'Enter 1–720 whole actual helper minutes, a valid Perth work date/time and a note describing the work.';
  if (error === 'started_department138_booking_required') return 'Helper time can be recorded after the Department 138 booking has started, including after completion.';
  if (error === 'helper_assignment_or_work_time_invalid') return 'Choose a recorded helper and a time when they were assigned as a helper on this booking, between its actual start and finish (or now if still running).';
  if (error === 'bay_already_started') {
    return 'This bay already has a running or stopped job. Complete it or release its bay before starting another.';
  }
  if (error === 'bay_overlap' || (conflict && conflict.conflict_type === 'bay_overlap')) {
    return 'That bay is already occupied during this time. The planner has refreshed to the latest version.';
  }
  if (error === 'technician_overlap' || (conflict && conflict.conflict_type === 'technician_overlap')) {
    // r531 (F145): the server names the mechanic and the booking that already holds them.
    const named = typeof workshopTechnicianOverlapDetail === 'function' ? workshopTechnicianOverlapDetail(result) : '';
    if (named) return named;
    return 'That technician is already assigned to another booking during this period. No booking was saved. Drop this vehicle on a bay whose mechanic is free for the whole job, use Best slot, or move that booking first.';
  }
  if (error === 'vehicle_overlap' || (conflict && conflict.conflict_type === 'vehicle_overlap')) {
    const detail = workshopVehicleConflictDetail(result);
    // r469 (F82): the server only pushes bookings the drop really overlaps. When pushing one of them back would land it on
    // its own vehicle's next booking, the server names both; say so plainly instead of blaming the dropped vehicle.
    const pushed = typeof workshopPushedBookingLabel === 'function' ? workshopPushedBookingLabel(result) : '';
    if (pushed && detail) return `Booking here would push ${pushed} back onto its own booking (${detail}). No changes were saved. Drop this vehicle after that job, use Best slot, or move the affected booking first.`;
    if (detail) return `This move conflicts with ${detail}. No conflicting bookings were saved. Keep at least 1 hour between this vehicle’s bookings. Use Best slot or move the affected later booking.`;
    return 'This change would overlap a vehicle’s booking in another bay or station, including any booking pushed back by the change. No conflicting bookings were saved. Use Best slot to find a time with the 1-hour buffer, or move the affected later booking.';
  }
  if (error === 'sublet_away') {
    return 'This vehicle is away on Sublet on that date. Record its actual return or choose a date after it is back.';
  }
  // r449 (F62): parts no longer gate a booking or a start (r415). These retired codes can only come from an old copy of
  // the page or the database, so say so plainly instead of asking for a parts confirmation that no longer exists.
  if (['parts_incomplete', 'parts_incomplete_blocked', 'parts_incomplete_entry', 'bus_stage_parts_required', 'stage_parts_not_ready'].includes(error)) {
    return 'Parts no longer hold up a booking. This page is out of date: refresh it and try again. If it happens again, tell an Administrator.';
  }
  if (error === 'bus_bay_vehicle_incompatible') return 'Bay 3 has a height restriction and does not take a Coaster. Drag it again and choose OK to book it there anyway (the override is logged), or select another bay.';
  if (error === 'category_bay_mismatch') return 'That bay is set up for other Bus 4×4 work. Bays 1–4 take Mechanical and Accessories; Bays 5–6 take any work (overflow); Bay 7 takes QA; Bays 8–10 take Electrical and Accessories. Drag it again and choose OK to book it there anyway (the override is logged). If the work was finished before the board, mark it done on the vehicle’s Work tab first.';
  if (error === 'bus_shift_outside_hours') return 'This booking is outside the Department 138 shift. Check its start and finish against the bay and mechanic working hours.';
  if (error === 'bus_technician_shift_conflict') return 'A technician on this team finishes at 14:00. Choose a booking within that person’s working hours or a team available for the whole booking. Supervision alone does not require a helper assignment.';
  if (error === 'bus_supplier_verification_required') return 'Supplier work still needs a physical check by the assigned technician before this bay can be completed.';
  if (error === 'not_editable' || error === 'permission_denied' || error === 'forbidden') {
    return 'You do not have permission to make this change.';
  }
  if (error === 'authority_superseded' || error === 'destroyed') {
    return 'Your workshop session changed before this action completed. No change was confirmed; the planner has refreshed.';
  }
  if (error === 'missing_expected_version') {
    return 'This action was missing required version information and was not sent. Please try again.';
  }
  if (error === 'ambiguous_vehicle_identity' || error === 'conflicting_vehicle_identity') {
    return 'This vehicle reference matches more than one shared vehicle or conflicts with its saved UUID. No change was made; the identity requires review.';
  }
  if (error === 'legacy_ambiguity_blocked') {
    return 'This legacy booking is ambiguous and remains blocked for administrator review. No change was made.';
  }
  if (error === 'vehicle_identity_not_found') {
    return 'This vehicle is not yet linked to one shared vehicle record. No change was made.';
  }
  if (error === 'booking_before_eta' || error === 'it_before_eta' || error === 'it_before_eta_plus_seven') {
    return `This IT vehicle cannot be booked before ETA + 7 days. Earliest permitted booking date: ${result.earliest_permitted_date || 'correct the vehicle ETA'}. No booking was created.`;
  }
  if (error === 'missing_or_invalid_eta' || error === 'it_eta_missing' || error === 'missing_eta') {
    return 'IT vehicles require a valid ETA to Kewdale before booking. Correct the ETA and try again. No booking was created.';
  }
  if (error === 'minimum_duration') return 'Workshop bookings must be at least 60 minutes.';
  if (error === 'past_start') return 'That suggested time has already passed. The planner has moved to the next available current or future time.';
  if (error === 'calendar_unavailable') return 'That start time is outside the configured Workshop calendar, closure, break, or overtime availability.';
  if (error === 'calendar_duration_mismatch' || error === 'invalid_schedule_interval') return 'The booking duration does not match the configured Workshop operating minutes. Choose a valid start and duration.';
  if (error === 'vehicle_inactive_or_missing') return 'This vehicle is inactive or unavailable in the shared Workshop records.';
  if (error === 'station_inactive_or_missing') return 'This Workshop station is inactive or unavailable.';
  if (error === 'location_ineligible') return 'This vehicle location is not eligible for Workshop scheduling. No booking was created.';
  if (error === 'active_booking_exists') return 'An active booking already represents this Workshop requirement. No duplicate booking was created.';
  if (error === 'vehicle_not_eligible_for_station') return 'This vehicle no longer has an outstanding requirement for that Workshop station. No booking was created.';
  if (error === 'canonical_requirement_missing_or_completed') return 'This vehicle has no incomplete canonical requirement for that Workshop station.';
  if (error === 'bay_required' || error === 'bay_inactive_or_wrong_station') return 'Choose an active bay belonging to this Workshop station.';
  if (error === 'technician_inactive_or_missing') return 'Choose an active Workshop technician.';
  if (error === 'technician_leave_conflict' || error === 'technician_on_leave') return 'That technician is on leave during this booking.';
  const plainMessage = WORKSHOP_PLAIN_ERROR_MESSAGES[error];
  if (plainMessage) return plainMessage;
  if (error === 'action_unavailable') {
    const exact = workshopAdministratorCanMove() ? workshopAdministratorErrorDetail(result) : '';
    return exact
      ? `This action failed before it could be confirmed. No change was saved. ${exact}`
      : 'This action is not currently available in shared mode. No change was made.';
  }
  const exact = workshopAdministratorCanMove() ? workshopAdministratorErrorDetail(result) : '';
  return exact ? `The server rejected this change. No update was saved. ${exact}` : 'The server rejected this change. No update was saved, and the planner has reloaded the current shared data.';
}

function workshopPushedBookingLabel(result = {}) {
  // r469 (F82): display-only label for the booking a cascade would have pushed (server snapshot, never reverse-matched).
  const object = value => value && typeof value === 'object' && !Array.isArray(value);
  const pushed = object(result) && object(result.pushed_booking) ? result.pushed_booking
    : (object(result?.body) && object(result.body.pushed_booking) ? result.body.pushed_booking : null);
  if (!pushed) return '';
  const text = value => typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60) : '';
  const stock = text(pushed.vehicle?.stock_number);
  const stage = text(pushed.stage?.display_name || pushed.stage?.code);
  const bayNumber = Number(pushed.bay?.bay_number);
  const storedBay = text(pushed.bay?.display_name);
  const bay = storedBay || (Number.isSafeInteger(bayNumber) && bayNumber > 0 ? `Bay ${bayNumber}` : '');
  const where = [stage, bay].filter(Boolean).join(' ');
  if (!stock && !where) return '';
  return [stock ? `stock ${stock}` : 'a later booking', where ? `(${where})` : ''].filter(Boolean).join(' ');
}

function workshopVehicleConflictDetail(result = {}) {
  // Error details are display-only. Never reverse-match a stock/key or read an
  // untrusted/previous-session snapshot to identify the conflicting booking.
  const object = value => value && typeof value === 'object' && !Array.isArray(value);
  const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.trim()) ? value.trim().toLowerCase() : '';
  const text = value => typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 100) : '';
  const envelopes = [result, result.body].filter(object);
  for (const container of envelopes.slice()) {
    for (const field of ['message', 'details']) {
      if (typeof container[field] !== 'string' || container[field].length > 8192) continue;
      const raw = container[field].trim().replace(/^Workshop Planner validation rejected booking:\s*/, '');
      if (!raw.startsWith('{')) continue;
      try {
        const parsed = JSON.parse(raw);
        if (object(parsed) && parsed.error === 'vehicle_overlap') envelopes.push(parsed);
      } catch (_) { /* Incomplete or non-JSON errors keep the generic message. */ }
    }
  }
  const details = envelopes.filter(value => value.error === 'vehicle_overlap' || value.conflict?.conflict_type === 'vehicle_overlap');
  const existing = details.flatMap(value => [value.conflict?.existing_booking, value.blocker]).filter(object);
  const ids = [...new Set([...details.map(value => uuid(value.conflict_booking_id)), ...existing.map(value => uuid(value.booking_id))].filter(Boolean))];
  if (ids.length !== 1) return '';
  const bookingId = ids[0];
  const direct = existing.find(value => uuid(value.booking_id) === bookingId) || {};
  let snapshot = null;
  try { snapshot = typeof window !== 'undefined' ? window.__workshopDataService?.getTrustedSnapshot?.() : null; } catch (_) { /* No authority, no enrichment. */ }
  const matches = Array.isArray(snapshot?.bookings) ? snapshot.bookings.filter(value => uuid(value?.booking_id) === bookingId) : [];
  const saved = matches.length === 1 ? matches[0] : {};
  const directVehicleId = uuid(direct.vehicle_id || direct.vehicle?.id);
  const savedVehicleId = uuid(saved.vehicle_id || saved.vehicle?.id);
  if (directVehicleId && savedVehicleId && directVehicleId !== savedVehicleId) return '';
  const booking = { ...saved, ...direct };
  const vehicleId = uuid(booking.vehicle_id || booking.vehicle?.id);
  if (booking.vehicle?.id && uuid(booking.vehicle.id) !== vehicleId) return '';
  const vehicles = vehicleId && Array.isArray(snapshot?.vehicles) ? snapshot.vehicles.filter(value => uuid(value?.id) === vehicleId) : [];
  const vehicle = booking.vehicle || (vehicles.length === 1 ? vehicles[0] : {});
  const stock = text(vehicle.stock_number);
  const stageNames = { BUS_4X4: 'Bus 4×4', TINT: 'Tint', HOIST: 'Hoist', FITTING: 'Fitting', FABRICATION: 'Fabrication', ELECTRICAL: 'Electrical', TYRE: 'Tyre' };
  const stage = stageNames[String(booking.stage?.code || booking.stage_code || '').toUpperCase()] || text(booking.stage?.display_name || booking.stage_name);
  const bayNumber = Number(booking.bay?.bay_number ?? booking.bay_number);
  const storedBay = text(booking.bay?.display_name || booking.bay_display_name);
  const bay = storedBay || (Number.isSafeInteger(bayNumber) && bayNumber > 0 ? `Bay ${bayNumber}` : '');
  const formatTime = value => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(value) || value.length > 40) return '';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '';
    return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
  };
  const start = formatTime(booking.scheduled_start_at);
  const end = formatTime(booking.scheduled_end_at);
  const location = [stage, bay].filter(Boolean).join(' · ');
  const when = start ? `scheduled ${start}${end ? ` – ${end}` : ''} (Perth time)` : '';
  if (!stock && !location && !when) return '';
  return [stock ? `stock ${stock}` : 'another booking for this vehicle', location, when].filter(Boolean).join(' · ');
}

function workshopTechnicianOverlapDetail(result = {}) {
  const text = value => typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 400) : '';
  const booking = result && result.conflict && result.conflict.existing_booking;
  const customer = booking && booking.vehicle ? text(booking.vehicle.customer_name) : '';
  const server = text(result && result.detail);
  if (server && /No booking was saved/i.test(server) && (!customer || customer.length < 4 || !server.toLowerCase().includes(customer.toLowerCase()))) return server;
  if (!booking || typeof booking !== 'object') return '';
  const tech = text(booking.assignment && booking.assignment.technician_name) || 'That technician';
  const stock = text(booking.vehicle && booking.vehicle.stock_number);
  const key = text(booking.vehicle && booking.vehicle.key_number);
  const bay = text(booking.bay && booking.bay.display_name);
  const stage = text(booking.stage && booking.stage.display_name);
  const formatTime = value => {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(value) || value.length > 40) return '';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '';
    return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
  };
  const start = formatTime(booking.scheduled_start_at);
  const end = formatTime(booking.scheduled_end_at);
  const who = [key ? `Key ${key}` : '', stock ? `stock ${stock}` : ''].filter(Boolean).join(', ');
  const place = bay && stage && bay.toLowerCase().startsWith(stage.toLowerCase()) ? bay : [stage, bay].filter(Boolean).join(' ');
  if (!who && !place) return '';
  const when = start ? `, from ${start}${end ? ` to ${end}` : ''} (Perth time)` : '';
  return `${tech} is already booked on ${who || 'another booking'}${place ? `, ${place}` : ''}${when}. No booking was saved. Drop this vehicle on a bay whose mechanic is free for the whole job, use Best slot, or move that booking first.`;
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
    workshopNotify(error.message || String(error));
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
  return pmbStageBayCount(stage);
}

function workshopEstimatedHoursMap(vehicle = {}) {
  const value = vehicle.workshopEstimatedHoursByStage;
  return value && typeof value === 'object' && !Array.isArray(value) ? { ...value } : {};
}

function workshopEstimatedHours(vehicle = {}, stage = '') {
  const saved = Number(workshopEstimatedHoursMap(vehicle)[normalizePmbStage(stage)]);
  return Number.isFinite(saved) && saved > 0 ? workshopExactDurationHours(saved) : '';
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
  const authoritativeSummaryLines = workshopSharedModeActive() && typeof authenticatedOperationSummaryLines === 'function'
    ? authenticatedOperationSummaryLines(vehicle)
    : [];
  let directOperationLines = [authoritativeSummaryLines, vehicle.pdcEmailOperationLines, vehicle.operation_lines, vehicle.operationLines]
    .find(value => Array.isArray(value) && value.length) || [];
  let boardOperationLines = [];
  if (workshopSharedModeActive() && typeof pdcSheetVehicles === 'function') {
    const canonicalId = String(vehicle.id || vehicle.vehicle_id || '').trim().toLowerCase();
    const exactBoardMatches = pdcSheetVehicles().filter(row => row?.__emailVehicleServerAuthoritative === true
      && row?.__emailVehicleIdentityConflict !== true
      && String(row.__emailVehicleId || '').trim().toLowerCase() === canonicalId);
    if (canonicalId && exactBoardMatches.length === 1) {
      const boardVehicle = exactBoardMatches[0];
      if (boardVehicle.pdcQcOperationLinesProjectionPresent === true) {
        boardOperationLines = (boardVehicle.pdcQcOperationLines || []).map(line => ({
          operation_line_id: line.sourceLineId,
          operation_no: line.operationNo,
          description: line.description,
          job_card_number: line.jobCardNumber,
          estimated_hours: line.estimatedHours,
          hours_provenance: line.hoursProvenance, estimate_basis: line.estimateBasis, review_note: line.reviewNote,
          stage_code: line.stageCode,
          work_category: line.workCategory,
        }));
        // This projection has already applied durable station/hour adjustments.
        directOperationLines = [];
      } else {
        boardOperationLines = boardVehicle.pdcEmailOperationLines || [];
      }
    }
  }
  const operationLineKey = (line = {}, index = 0) => cleanNavisionText(line.operation_line_id || line.operationLineId || '')
    || [cleanNavisionText(line.operation_no || line.operationNo || '').toUpperCase(), cleanNavisionText(line.description || '').toLowerCase(), cleanNavisionText(line.job_card_number || line.jobCardNumber || '')].join('\0')
    || `row:${index}`;
  const authoritativeLineMap = new Map();
  boardOperationLines.forEach((line, index) => authoritativeLineMap.set(operationLineKey(line, index), line));
  directOperationLines.forEach((line, index) => {
    const key = operationLineKey(line, index);
    authoritativeLineMap.set(key, { ...(authoritativeLineMap.get(key) || {}), ...line });
  });
  const authoritativeOperationLines = [...authoritativeLineMap.values()];
  const authenticated = authoritativeOperationLines.slice(0, 50).flatMap((line, index) => {
    const operationNo = cleanNavisionText(line.operation_no || line.operationNo || '').toUpperCase();
    const text = cleanNavisionText(line.description || '');
    const rawStage = line.stage_code || line.stageCode || line.work_key || line.workKey || '';
    const stage = typeof vehicleWorkshopStageCode === 'function'
      ? normalizePmbStage(vehicleWorkshopStageCode(rawStage))
      : normalizePmbStage(rawStage);
    if (!text || !operationNo || !WORKSHOP_STAGE_SEQUENCE.includes(stage)) return [];
    const rawHours = line.estimatedHours ?? line.estimated_hours ?? line.hours;
    const hours = rawHours === null || rawHours === undefined || String(rawHours).trim() === '' ? null : Number(rawHours);
    const sourceId = cleanNavisionText(line.operation_line_id || line.operationLineId || line.sourceLineId || '');
    return [{
      id: sourceId ? `source:${sourceId}` : workshopJobLineId(`${operationNo}:${text}`, index),
      text,
      operationNo,
      jobCardNumber: cleanNavisionText(line.job_card_number || line.jobCardNumber || vehicleJobcardNumber(vehicle) || ''),
      index,
      stage,
      workCategory: String(line.work_category || line.workCategory || ''),
      hours: Number.isFinite(hours) && hours >= 0 ? hours : null,
      hoursProvenance: String(line.hours_provenance || line.hoursProvenance || ''),
      estimateBasis: String(line.estimate_basis || line.estimateBasis || ''),
      confirmed: String(line.hours_provenance || line.hoursProvenance || '')!=='ai_estimated',
      source: 'authenticated-operation-line',
    }];
  });
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
  const authenticatedDescriptions = new Set(authenticated.map(line => `${line.stage}\0${line.text.toLowerCase()}`));
  const nonDuplicateConfirmed = confirmed.filter(line => !authenticatedDescriptions.has(`${line.stage}\0${line.text.toLowerCase()}`));
  const confirmedDescriptions = new Set([...authenticated, ...nonDuplicateConfirmed].map(line => line.text.toLowerCase()));
  const tasks = Array.isArray(vehicle.poTasks) ? vehicle.poTasks : [];
  const legacy = tasks.map((text, index) => ({ id: workshopJobLineId(text, index), text: cleanNavisionText(text || ''), index, source: 'legacy-po-task' }))
    .filter(line => line.text && !confirmedDescriptions.has(line.text.toLowerCase()));
  return [...authenticated, ...nonDuplicateConfirmed, ...legacy];
}

function workshopDetectedStageForLine(text = '', vehicle = {}) {
  const value = cleanNavisionText(text || '');
  if (/\bbus\s*4\s*x\s*4\b/i.test(value)) return 'BUS_4X4';
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
  const assignments = workshopSharedModeActive() ? {} : workshopJobLineAssignments(vehicle);
  return workshopImportedJobLines(vehicle).map(line => {
    const saved = assignments[line.id] || {};
    const stage = WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(saved.stage))
      ? normalizePmbStage(saved.stage)
      : WORKSHOP_STAGE_SEQUENCE.includes(normalizePmbStage(line.stage))
        ? normalizePmbStage(line.stage)
        : workshopDetectedStageForLine(line.text, vehicle);
    const savedHours = Number(saved.hours);
    const importedHours = Number(line.hours);
    const hasExactAuthenticatedHours = line.source === 'authenticated-operation-line' && Number.isFinite(importedHours) && importedHours >= 0;
    const exactAuthenticatedHours = hasExactAuthenticatedHours ? workshopExactDurationHours(importedHours) : 0;
    return {
      ...line,
      stage,
      hours: hasExactAuthenticatedHours
        ? exactAuthenticatedHours
        : Number.isFinite(savedHours) && savedHours > 0
        ? workshopClampLineHours(savedHours)
        : Number.isFinite(importedHours) && importedHours > 0
          ? workshopClampLineHours(importedHours)
          : workshopJobLineHours(line.text),
    };
  });
}

function workshopStageJobLines(vehicle = {}, stage = '', category = undefined) {
  const normalizedStage = normalizePmbStage(stage);
  const selected = normalizedStage === 'BUS_4X4'
    ? (category === undefined && typeof workshopSelectedBusGroup === 'function' ? workshopSelectedBusGroup()?.code : category) : '';
  return workshopResolvedJobLines(vehicle).filter(line => line.stage === normalizedStage && (!selected || selected === 'BUS_WHOLE_JOB' || line.workCategory === selected));
}

function workshopCalculatedStageHours(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  const stageLines = workshopStageJobLines(vehicle, normalizedStage);
  const authenticatedLines = stageLines.filter(line => line.source === 'authenticated-operation-line' && Number(line.hours) > 0);
  const additionalHours = Number(workshopAdditionalHoursMap(vehicle)[normalizedStage] || 0);
  const authoritativeHours = workshopEstimatedHours(vehicle, normalizedStage);
  // The scoped station snapshot has already applied durable operation-line
  // station adjustments. Raw imported lines still carry their original
  // work_key, so summing those first can submit another station's duration.
  if (workshopSharedModeActive() && vehicle.__workshopStationSnapshotAuthoritative === true && authoritativeHours) return authoritativeHours;
  if (workshopSharedModeActive() && authenticatedLines.length) {
    const exactLineHours = authenticatedLines.reduce((sum, line) => sum + Number(line.hours || 0), 0);
    return workshopExactDurationHours(exactLineHours + (Number.isFinite(additionalHours) ? Math.max(0, additionalHours) : 0));
  }
  if (authoritativeHours) return authoritativeHours;
  const importedHours = stageLines.reduce((sum, line) => sum + Number(line.hours || 0), 0);
  const total = importedHours + (Number.isFinite(additionalHours) ? Math.max(0, additionalHours) : 0);
  if (total > 0) return workshopClampDurationHours(total);
  return workshopDefaultBookingHours();
}

function workshopSchedulingDuration(vehicle = {}, stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (workshopSharedModeActive()) {
    const authoritativeHours = workshopExactDurationHours(workshopEstimatedHours(vehicle, normalizedStage));
    return authoritativeHours > 0
      ? { hours: authoritativeHours, minutes: Math.round(authoritativeHours * 60) }
      : null;
  }
  const localHours = workshopExactDurationHours(
    workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || workshopDefaultBookingHours(),
  );
  return localHours > 0 ? { hours: localHours, minutes: Math.round(localHours * 60) } : null;
}

// Operation hours remain the labour estimate. Only destination-bay allocation
// uses efficiency; persisted booking hours are already allocated time.
function workshopBayAllocatedHours(stage = '', bay = 0, baseHours = 0) {
  const hours = Number(baseHours);
  if (!Number.isFinite(hours) || hours <= 0) return null;
  if (!workshopSharedModeActive()) return hours;
  const capacity = window.PDC_PLANNER_CAPACITY;
  return typeof capacity?.allocatedHours === 'function'
    ? capacity.allocatedHours(normalizePmbStage(stage), Number(bay), hours)
    : null;
}

function workshopBayAllocatedBaseMinutes(stage = '', bay = 0, baseMinutes = 0) {
  const minutes = Number(baseMinutes);
  if (!Number.isFinite(minutes) || minutes <= 0) return null;
  if (!workshopSharedModeActive()) return minutes / 60;
  const capacity = window.PDC_PLANNER_CAPACITY;
  return typeof capacity?.allocatedBaseMinutes === 'function'
    ? capacity.allocatedBaseMinutes(normalizePmbStage(stage), Number(bay), minutes)
    : null;
}

function workshopBookingDestinationHours(entry = null, stage = '', bay = 0, baseHours = 0) {
  if (entry && ['started', 'stoppage', 'completed'].includes(entry.status)) return Number(entry.hours) > 0 ? Number(entry.hours) : null;
  if (entry && normalizePmbStage(entry.stage) === normalizePmbStage(stage)) {
    if (Number(entry.bay) === Number(bay)) return Number(entry.hours) > 0 ? Number(entry.hours) : null;
    const durableBase = Number(entry.capacityBaseMinutes);
    if (durableBase > 0) return workshopBayAllocatedBaseMinutes(stage, bay, durableBase);
    // A booking created before capacity metadata existed was at normal speed.
    // Retain any manual allocation when moving it for the first time.
    const applied = Number(entry.capacityEfficiencyPercent) || 100;
    return workshopBayAllocatedBaseMinutes(stage, bay, Number(entry.hours) * 60 * applied / 100);
  }
  return workshopBayAllocatedHours(stage, bay, baseHours);
}

function workshopManualDurationAllocation(requestedHours = 0, importedHours = 0) {
  const requested = Number(requestedHours);
  const imported = Number(importedHours);
  if (!Number.isFinite(requested) || requested < 1) return null;
  const safeImported = Number.isFinite(imported) ? Math.max(0, imported) : 0;
  const total = workshopClampDurationHours(requested);
  if (total + 0.000001 < safeImported) return null;
  return {
    total,
    additional: Number(Math.max(0, total - safeImported).toFixed(2)),
  };
}

function workshopManualDurationSharedPayload(plan = {}, requestedHours = 0) {
  const nextHours = workshopExactDurationHours(requestedHours);
  const previousHours = workshopExactDurationHours(plan.hours);
  return {
    operation: nextHours > previousHours ? 'extend' : 'resize',
    targetId: plan.sharedBookingId || plan.id,
    targetExpectedVersion: plan.sharedVersion,
    stageCode: plan.stage,
    bayNumber: Number(plan.bay),
    scheduledStartAt: plan.startAt,
    durationMinutes: Math.round(nextHours * 60),
    shiftMinutes: Math.max(0, Math.round((nextHours - previousHours) * 60)),
    metadata: { source: 'manual_estimated_time' },
  };
}

function workshopDurationInputValue(hours = 0) {
  const minutes = Math.max(1, Math.round(Number(hours || 0) * 60));
  return String(Number((minutes / 60).toFixed(4)));
}

function workshopStageEstimateSharedPayload(vehicle = {}, plan = {}, stage = '', requestedMinutes = 0) {
  return {
    vehicleId: vehicle.sharedVehicleId || vehicle.id,
    vehicleExpectedVersion: Number(vehicle.version),
    bookingId: plan.sharedBookingId || plan.id,
    bookingExpectedVersion: Number(plan.sharedVersion),
    stageCode: normalizePmbStage(stage),
    totalMinutes: Math.max(1, Math.round(Number(requestedMinutes))),
    idempotencyKey: workshopNewRequestId(),
  };
}

function workshopLoadView() {
  const saved = typeof loadJson === 'function' ? loadJson(WORKSHOP_VIEW_STORAGE_KEY, {}) : {};
  const rawDate = workshopDateFromKey(saved?.date || '') || new Date();
  const date = workshopCoerceWorkDate(rawDate, 1);
  return {
    date: workshopDateKey(date),
    stage: WORKSHOP_STAGE_SEQUENCE.includes(saved?.stage) ? saved.stage : 'FABRICATION',
    busBayGroup: window.PDC_WORKSHOP_DEPARTMENTS?.category(saved?.busBayGroup)?.id || 'mechanical',
    busShowAllBays: saved?.busShowAllBays === true,
    selectedPlanId: '',
    search: '',
    searchKey: '',
    searchOpen: false,
    searchHighlightPlanId: '',
    detailManualOpen: false,
    detailCollapsedForSelection: false,
    focusedBookingMode: false,
    focusedBookingId: '',
    focusedBookingError: '',
  };
}

function workshopSaveView(state = {}) {
  if (typeof saveJson === 'function') saveJson(WORKSHOP_VIEW_STORAGE_KEY, { date: state.date, stage: state.stage, busBayGroup: state.busBayGroup || 'mechanical', busShowAllBays:state.busShowAllBays === true });
}

function workshopState() {
  if (!app.workshopPlanner) app.workshopPlanner = workshopLoadView();
  return app.workshopPlanner;
}

function workshopApplyOpenDateDefault(state = workshopState(), now = new Date()) {
  if (typeof app === 'undefined' || app.pendingWorkshopOpenToday !== true) return false;
  state.date = workshopDefaultOpenDateKey(now);
  workshopClearSelectedDetail(state);
  workshopSaveView(state);
  app.pendingWorkshopOpenToday = false;
  return true;
}

function workshopClearSelectedDetail(state = workshopState()) {
  state.selectedPlanId = '';
  state.searchHighlightPlanId = '';
  state.searchNotice = '';
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = false;
  state.focusedBookingMode = false;
  state.focusedBookingId = '';
  state.focusedBookingError = '';
}

function workshopSelectPlanForDetail(planId = '') {
  const state = workshopState();
  state.selectedPlanId = String(planId || '');
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = Boolean(state.selectedPlanId);
  state.searchNotice = '';
}

function workshopVehicle(key = '', stage = '') {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return null;
  if (!workshopSharedModeActive()) {
    return typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null;
  }
  // Shared mode is fail-closed: browser-local vehicle/customer/note records
  // cannot supplement or replace the authoritative scoped snapshot.
  const snapshot = window.__workshopDataService?.getLastSnapshot?.();
  const vehicles = Array.isArray(snapshot?.vehicles) ? snapshot.vehicles : [];
  const matches = vehicles.filter(vehicle => [vehicle.id, vehicle.stock_number, vehicle.permanent_vehicle_id]
    .some(value => String(value || '').trim() === cleanKey));
  if (matches.length !== 1) return null;
  const plannerRow = workshopSnapshotVehicleToPlannerRow(
    matches[0],
    Array.isArray(snapshot?.work_items) ? snapshot.work_items : [],
    stage || window.__activeWorkshopPlannerStage || '',
  );
  const normalizeStage = value => typeof normalizePmbStage === 'function'
    ? normalizePmbStage(value)
    : String(value || '').trim().toUpperCase();
  const requestedStage = normalizeStage(stage || window.__activeWorkshopPlannerStage || '');
  if (!requestedStage) return plannerRow;
  if (!Array.isArray(snapshot?.outstanding_candidates)) return plannerRow;
  const authorityMatches = snapshot.outstanding_candidates.filter(row => {
    if (String(row?.vehicle_id || '').trim() !== String(matches[0]?.id || '').trim()) return false;
    const rowStage = normalizeStage(row?.stage_code || row?.stage || requestedStage);
    return rowStage === requestedStage;
  });
  if (authorityMatches.length !== 1) {
    return { ...plannerRow, __workshopOutstanding: { existingBooking: false, scheduleEnabled: false, disabledReason: 'authority_unavailable' } };
  }
  const authority = workshopCategoryAuthority(authorityMatches[0], requestedStage);
  const authoritativeHours = Number(authority.estimated_hours);
  return {
    ...plannerRow,
    workshopEstimatedHoursByStage: authoritativeHours > 0
      ? { ...plannerRow.workshopEstimatedHoursByStage, [requestedStage]: authoritativeHours }
      : requestedStage === 'BUS_4X4' && authority.work_category ? {...plannerRow.workshopEstimatedHoursByStage, BUS_4X4:null} : plannerRow.workshopEstimatedHoursByStage,
    __workshopOutstanding: {
      workCategory: authority.work_category || '',
      // r417 (F32): every Bus 4x4 category with its hours, so a drop can book the bay's own category.
      workCategories: Array.isArray(authorityMatches[0]?.work_categories) ? authorityMatches[0].work_categories : [],
      categoryCompleted: authority.completed === true,
      existingBooking: authority.existing_booking === true,
      scheduleEnabled: authority.schedule_enabled === true,
      disabledReason: authority.disabled_reason || '',
    },
  };
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
const WORKSHOP_LINK_ALIAS_PATTERN = /^(?:source:[a-z0-9_-]+|permanent_vehicle_id|vin):[A-Z0-9][A-Z0-9:._/-]*$/;
const WORKSHOP_LINK_MATCH_FIELDS = new Set(['vehicle_id', 'stock_number', 'vin', 'job_card_number', 'permanent_vehicle_id', 'source_record_id']);
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
    'p_permanent_vehicle_id', 'p_source_system', 'p_source_record_id',
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
  add('source_record_id', input.p_source_record_id, { sourceSystem: input.p_source_system, sourceRecordId: input.p_source_record_id });
  return probes;
}

function workshopVehicleLinkRemediation(outcome = '', hasSavedLink = false) {
  const messages = {
    not_found: 'Create or import exactly one canonical shared vehicle through the approved Stage 2B importer, then run link verification again.',
    ambiguous: 'Manual identity review is required: resolve duplicate normalized candidates without selecting by row order, then retry.',
    conflict: 'Manual identity review is required: correct the conflicting saved UUID or identifier evidence, then retry.',
    invalid_input: 'Correct the reported browser-local identity field, then run deterministic link verification again.',
    unstable_identity: 'Add one stable browser-local identifier (source record, permanent vehicle ID, or VIN) before linking; stock number alone is not a durable edit key.',
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
      : String(vehicle.stock || vehicle.id || '').trim(),
    stockNumber: input.p_stock_number || null,
    vin: input.p_vin || null,
    jobCardNumber: input.p_job_card_number || null,
    permanentVehicleId: input.p_permanent_vehicle_id || null,

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
    : String(vehicle.stock || vehicle.id || '').trim();
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
// "<STAGE>-BAY-<NN>" (zero-padded).
// This lookup itself returns null when shared bay data is unavailable or
// unmatched. New scheduling/move guards interpret that state fail-closed via
// workshopBayAvailabilityStatus(); only existing/historical rendering uses
// the intentionally lenient workshopBayIsActive() compatibility helper.
function workshopQaBayLabel(name = '', bayNumber = 0) {
  const pad = String(bayNumber).padStart(2, '0');
  const label = String(name || '').replace(/[·•]/g, '-').replace(/\s+/g, ' ').trim().toLowerCase();
  if (!label) return false;
  return [`qa - bay ${pad}`, `qa - bay ${bayNumber}`, `qa - bus4x4 bay ${pad}`, `qa - bus 4x4 bay ${pad}`].includes(label);
}

function workshopSnapshotBayRef(stage = '', bayNumber = 0) {
  const service = typeof window !== 'undefined' ? window.__workshopDataService : null;
  const snapshot = service && typeof service.getLastSnapshot === 'function' ? service.getLastSnapshot() : null;
  const lists = [
    ...(snapshot && Array.isArray(snapshot.bookings) ? snapshot.bookings : []),
    ...(snapshot && Array.isArray(snapshot.active_stoppages) ? snapshot.active_stoppages : []),
  ];
  for (const booking of lists) {
    const bookingStage = normalizePmbStage(booking?.stage?.code || booking?.stage_code || '');
    const bay = booking?.bay || null;
    const number = Number(bay?.bay_number ?? booking?.bay_number);
    if (bookingStage !== stage || number !== bayNumber) continue;
    const id = String(bay?.id || bay?.bay_id || booking?.bay_id || '').trim();
    const code = String(bay?.code || `${stage}-BAY-${String(bayNumber).padStart(2, '0')}`);
    if (!id || !code.startsWith(`${stage}-BAY-`)) continue;
    return {
      id,
      code,
      bay_number: bayNumber,
      display_name: bay?.display_name || bay?.bay_name || '',
      version: Number.isInteger(bay?.version) ? bay.version : 0,
      default_technician_id: bay && Object.prototype.hasOwnProperty.call(bay, 'default_technician_id') ? bay.default_technician_id : null,
      is_active: bay?.is_active !== false,
    };
  }
  return null;
}

function workshopSharedBayRef(stage = '', bay = 0) {
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  let normalizedStage = '';
  try { if (typeof normalizePmbStage === 'function') normalizedStage = normalizePmbStage(stage); } catch (_error) { normalizedStage = ''; }
  if (!normalizedStage && typeof globalThis.normalizePmbStage === 'function') normalizedStage = globalThis.normalizePmbStage(stage);
  if (!normalizedStage) normalizedStage = String(stage || '').trim().toUpperCase();
  const bayNumber = Number(bay) || 1;
  const expectedCode = `${normalizedStage}-BAY-${String(bayNumber).padStart(2, '0')}`;
  const cached = service && typeof service.getCachedWorkshopBays === 'function' ? service.getCachedWorkshopBays() : null;
  const rows = cached && Array.isArray(cached.rows) ? cached.rows : [];
  const byCode = rows.find(row => row && row.code === expectedCode);
  if (byCode) return byCode;
  const byNumber = rows.find(row => row && Number(row.bay_number) === bayNumber && String(row.code || '').startsWith(`${normalizedStage}-BAY-`));
  if (byNumber) return byNumber;
  if (normalizedStage === 'BUS_4X4') {
    const byQaLabel = rows.find(row => row && String(row.code || '').startsWith('BUS_4X4-BAY-') && Number(row.bay_number) === bayNumber && workshopQaBayLabel(row.display_name, bayNumber));
    if (byQaLabel) return byQaLabel;
  }
  return workshopSnapshotBayRef(normalizedStage, bayNumber);
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

function workshopTechnicianNameById(id = '') {
  const cleanId = String(id || '').trim();
  if (!cleanId) return '';
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  const rows = service?.getCachedTechnicians?.()?.rows || [];
  const technician = rows.find(row => row && String(row.id || '') === cleanId);
  return technician ? cleanNavisionText(technician.name) : '';
}

function workshopNextScheduleTechnician(stage = '', bay = 0, vehicle = null, { followsBay = true, manualValue = '' } = {}) {
  const bayDefault = workshopBayMechanic(stage, bay) || (typeof pmbBayMechanic === 'function' ? pmbBayMechanic(vehicle) : '') || '';
  // r535 (F149): Schedule no longer asks for a technician. A new booking uses
  // the bay's default mechanic. A caller that already chose a name can still pass it.
  if (followsBay) return bayDefault;
  return cleanNavisionText(manualValue || '');
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
  const hours = workshopExactDurationHours(entry.hours) || workshopClampDurationHours(entry.hours);
  const endDate = workshopEntryEnd(entry);
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

function workshopStartedBayConflict(candidate = {}, rows = workshopLoadPlans()) {
  if (!candidate.bay) return null;
  return rows.find(row => row.id !== candidate.id
    && row.status === 'started'
    && row.stage === candidate.stage
    && Number(row.bay) === Number(candidate.bay)) || null;
}

function workshopRequireNoBayConflict(candidate = {}, rows = workshopLoadPlans()) {
  const conflict = workshopHasConflict(candidate, rows);
  if (!conflict) return true;
  const vehicle = workshopVehicle(conflict.vehicleKey);
  const identity = vehicle ? (displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'another vehicle') : 'another vehicle';
  const area = workshopBayChoiceLabel(candidate.stage, candidate.bay);
  workshopNotify(`${area} already has ${identity} booked during that time. Overlapping workshop bookings are blocked; choose another bay or time.`);
  return false;
}

function workshopResolveConflictByNextSlot(candidate = {}, rows = workshopLoadPlans()) {
  const conflict = workshopHasConflict(candidate, rows);
  if (!conflict) return candidate;
  const conflictVehicle = workshopVehicle(conflict.vehicleKey);
  const identity = conflictVehicle ? (displayStockNumber(conflictVehicle) || vehicleJobcardNumber(conflictVehicle) || 'another vehicle') : 'another vehicle';
  const area = workshopBayChoiceLabel(candidate.stage, candidate.bay);
  const requestedStart = workshopEntryStart(candidate);
  const requestedMinutes = workshopMinuteOffset(requestedStart);
  const nextSlot = workshopFirstAvailableStartSlot(
    candidate.stage,
    candidate.bay,
    workshopDateKey(requestedStart),
    candidate.hours,
    rows,
    requestedMinutes,
    260,
    new Date(),
    [],
    candidate.assignee || '',
  );
  if (!nextSlot) {
    workshopNotify(`${area} already has ${identity} booked during that time. No open sequence slot was found in this bay during the next 260 workdays; choose another bay or a later date.`);
    return null;
  }
  const nextStart = workshopDateAtOffset(nextSlot.dateKey, nextSlot.startMinutes);
  const nextLabel = nextStart.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric', hour: 'numeric', minute: '2-digit' });
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
    const slot = workshopFirstAvailableStartSlot(row.stage, row.bay, workshopDateKey(originalStart), row.hours, settled, workshopMinuteOffset(originalStart), 260, new Date(), [], row.assignee || '');
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
      const label = start ? start.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' }) : 'time TBC';
      return `• ${identity} → ${label}`;
    }).join('\n');
    const noun = moved.length === 1 ? 'booking' : 'bookings';
    if (!window.confirm(`This time overlaps ${moved.length} queued planned ${noun} in this bay.\n\nMove the queued ${noun} to the next open slot${moved.length === 1 ? '' : 's'}?\n\n${details}`)) return null;
  }
  return { rows: settled, moved };
}

function workshopShiftEveryLaterPlannedRow(candidate = {}, otherRows = [], shiftMinutes = 0) {
  // A live overrun must never round backwards and leave a queued card
  // overlapping the live card. Round the delay up to the next planner tick.
  const rawDelay = Math.max(0, Number(shiftMinutes) || 0);
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  const delay = rawDelay > 0 ? Math.ceil(rawDelay / increment) * increment : 0;
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

function workshopEntryTechnicianIds(entry = {}) {
  return [...new Set([workshopTechnicianIdForEntry(entry), ...(entry.helperAssignments || []).map(row => row.technicianId)].filter(Boolean))];
}

function workshopBookingTeamLabel(entry = {}) {
  const primary = cleanNavisionText(entry.assignee || '');
  const helpers = (entry.helperAssignments || []).map(row => cleanNavisionText(row.name || '') || 'Assigned helper');
  return [primary ? `Primary: ${primary}` : '', helpers.length ? `Helpers: ${helpers.join(', ')}` : ''].filter(Boolean).join(' · ');
}

function workshopTechnicianIsOnLeave(technicianId = '', dateValue = new Date()) {
  const dates = WORKSHOP_PLANNER_CONFIG.technicianLeaveByTechnicianId[String(technicianId || '')] || [];
  return dates.includes(workshopDateKey(dateValue));
}

function workshopNewBookingValidation(entry = {}, now = null) {
  if (!workshopConfigurationAllowsNewScheduling()) return { ok: false, error: 'configuration_unavailable' };
  const start = parseIsoTimestamp(entry.startAt || '');
  if (!start) return { ok: false, error: 'invalid_start' };
  const requestedDurationMinutes = Math.round(Number(entry.hours ?? workshopDefaultBookingHours()) * 60);
  if (!Number.isFinite(requestedDurationMinutes) || requestedDurationMinutes < 1) {
    return { ok: false, error: 'minimum_duration', minimumMinutes: 1 };
  }
  const referenceNow = now instanceof Date ? new Date(now) : now ? new Date(now) : null;
  if (referenceNow && !Number.isNaN(referenceNow.getTime())) {
    referenceNow.setSeconds(0, 0);
    const status = cleanNavisionText(entry.status || 'planned').toLowerCase();
    if (['queued', 'planned'].includes(status) && start < referenceNow) {
      return { ok: false, error: 'past_start', now: referenceNow.toISOString() };
    }
  }
  if (workshopIsClosureDate(start, entry)) return { ok: false, error: 'closure_date', date: workshopDateKey(start) };
  if (!workshopIsConfiguredWorkingDay(start, entry)) return { ok: false, error: 'non_working_day', date: workshopDateKey(start) };
  const startMinute = workshopMinuteOfDay(start);
  const startWindow = workshopAvailabilityWindowsForDate(start, entry).find(window => startMinute >= window.startMinutes && startMinute < window.endMinutes);
  if (!startWindow) {
    const inBreak = workshopBreakWindowsForDate(start).some(window => startMinute >= window.startMinutes && startMinute < window.endMinutes);
    return { ok: false, error: inBreak ? 'break_window' : 'outside_work_window', date: workshopDateKey(start), minute: startMinute };
  }
  const durationMinutes = requestedDurationMinutes;
  const technicianIds = workshopEntryTechnicianIds(entry);
  let usesOvertime = false;
  let current = new Date(start);
  let remaining = durationMinutes;
  // Visit each occupied work window once. Restarting the calendar calculation
  // for every minute made long jobs expensive for every possible Best slot.
  while (remaining > 0) {
    const windows = workshopAvailabilityWindowsForDate(current, entry);
    const minute = workshopMinuteOfDay(current);
    const containingWindow = windows.find(window => minute >= window.startMinutes && minute < window.endMinutes)
      || windows.find(window => minute < window.startMinutes);
    if (!containingWindow) { current = workshopMoveToNextWorkStart(current, entry); continue; }
    if (minute < containingWindow.startMinutes) current = workshopSetClock(current, containingWindow.startMinutes);
    const dateKey = workshopDateKey(current);
    usesOvertime = usesOvertime || containingWindow.overtime === true;
    const technicianId = technicianIds.find(id => workshopTechnicianIsOnLeave(id, current));
    if (technicianId) {
      return { ok: false, error: 'technician_on_leave', date: dateKey, technicianId };
    }
    const available = containingWindow.endMinutes - workshopMinuteOfDay(current);
    if (remaining <= available) break;
    remaining -= available;
    const nextWindow = windows.find(window => window.startMinutes >= containingWindow.endMinutes && window.endMinutes > containingWindow.endMinutes);
    current = nextWindow ? workshopSetClock(current, nextWindow.startMinutes) : workshopMoveToNextWorkStart(current, entry);
  }
  return { ok: true, usesOvertime };
}

function workshopRequireSchedulableCandidate(entry = {}) {
  if (!WORKSHOP_ELIGIBILITY_RUNTIME.workshopIsPlannerStage(normalizePmbStage(entry.stage))) {
    workshopNotify('This work type does not have a Workshop Planner. No scheduling change was made.');
    return false;
  }
  const validationNow = typeof nowIsoString === 'function' ? parseIsoTimestamp(nowIsoString()) : new Date();
  const result = workshopNewBookingValidation(entry, validationNow || new Date());
  if (result.ok) return true;
  const messages = {
    configuration_unavailable: 'Shared planner configuration is loading, unavailable, or invalid. New scheduling is blocked until valid shared settings are confirmed.',
    invalid_start: 'Choose a valid workshop start date and time.',
    past_start: 'Workshop jobs cannot be placed in the past. Choose the current or a future time.',
    minimum_duration: 'Workshop Planner bookings must be at least one operational minute.',
    closure_date: 'That date is configured as a workshop closure and cannot accept a new booking.',
    non_working_day: 'That date is not part of the configured working week.',
    break_window: 'The proposed booking interval overlaps a configured non-bookable break window.',
    outside_work_window: 'The proposed booking interval extends outside regular hours and configured overtime windows.',
    technician_on_leave: 'That technician is on configured leave during the proposed booking interval and cannot receive the assignment.',
  };
  workshopNotify(messages[result.error] || 'That booking is not schedulable under the current shared configuration.');
  return false;
}

function workshopAssigneeConflict(entry = {}, rows = workshopLoadPlans()) {
  const assignee = cleanNavisionText(entry.assignee || '').toLowerCase();
  const technicianIds = workshopEntryTechnicianIds(entry);
  if ((!assignee && !technicianIds.length) || ['completed','deleted','cancelled'].includes(entry.status)) return null;
  const start = workshopEntryStart(entry);
  const end = workshopEntryEffectiveEnd(entry);
  return rows.find(other => {
    if (other.id === entry.id || ['completed','deleted','cancelled'].includes(other.status)) return false;
    if (other.stage === entry.stage && Number(other.bay) === Number(entry.bay)) return false;
    const otherIds = workshopEntryTechnicianIds(other);
    const sharedTechnician = technicianIds.some(id => otherIds.includes(id));
    const sameLegacyName = assignee && cleanNavisionText(other.assignee || '').toLowerCase() === assignee;
    if (!sharedTechnician && !sameLegacyName) return false;
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
  workshopNotify(`A technician on this team is already booked on ${identity} at that time. Move one booking or choose an available team.`);
  return false;
}

function workshopEntryIsLive(entry = {}) {
  if (!['started', 'stoppage'].includes(entry.status)) return false;

  // Shared snapshots already contain canonical booking, vehicle and bay
  // identities. Do not depend on a lagging browser-local PMB bay mirror.
  if (entry.sharedBookingId && entry.sharedVehicleId && entry.sharedBayId && Number(entry.bay) > 0) return true;

  const vehicle = workshopVehicle(entry.vehicleKey);
  return Boolean(vehicle && Number(pmbBayNumber(vehicle, entry.stage)) === Number(entry.bay));
}

function workshopCascadePlans(rows = workshopLoadPlans(), now = new Date()) {
  // Shared Workshop rows are already authoritative. Never apply a reversible
  // browser-only overrun cascade: it makes later chips appear shifted and then
  // snap backwards when the live/STOPPAGE anchor leaves the current page.
  // Persisted server cascade receipts are the only source of shared positions.
  const shared = workshopSharedModeActive();
  if (shared) return { rows: rows.map(entry => ({ ...entry })), changed: false };
  let nextRows = rows.map(entry => ({
    ...entry,
    hours: entry.status === 'completed'
      ? entry.hours
      : workshopClampDurationHours(entry.hours),
  }));
  let changed = nextRows.some((entry, index) => entry.hours !== rows[index].hours);
  const scheduleAnchors = nextRows
    .filter(entry => {
      if (workshopEntryIsLive(entry)) return workshopEntryIsOvertime(entry, now);
      return entry.status === 'completed' && workshopEntryEffectiveEnd(entry, now) > workshopEntryEnd(entry);
    })
    .sort((a, b) => workshopEntryStart(a) - workshopEntryStart(b));
  for (const live of scheduleAnchors) {
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
  const start = interval.startDate.toLocaleString('en-AU', sameDay ? { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' } : { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  const end = interval.endDate.toLocaleString('en-AU', sameDay ? { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' } : { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  return `${start}–${end}`;
}

function workshopSlotSummary(stage = '', bay = 1, dateKey = '', startMinutes = 0) {
  const normalizedStage = normalizePmbStage(stage);
  const start = workshopDateAtOffset(dateKey, startMinutes);
  const when = start.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', hour: 'numeric', minute: '2-digit' });
  const area = `${pmbStageLabel(normalizedStage)} · ${workshopBayText(normalizedStage, bay, true)}`;
  return `${area} · ${when}`;
}

function workshopSchedulableBayNumbers(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return [];
  const bays = [];
  for (let bay = 1; bay <= workshopStageBayCount(normalizedStage); bay += 1) {
    if (workshopBayAvailabilityStatus(normalizedStage, bay) === 'active') bays.push(bay);
  }
  return bays;
}

function workshopBestStageSlot(stage = '', dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0, notAfterDateKey = '', vehicleWindows = [], fallbackAssignee = '', assignedMechanic = null, existingEntry = null, calendarVehicle = null) {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return null;
  let best = null;
  const slotCategory = existingEntry?.workCategory || calendarVehicle?.__workshopOutstanding?.workCategory || '';
  const slotBays = workshopCategoryOwnBays(normalizedStage, slotCategory);
  for (const bay of workshopSchedulableBayNumbers(normalizedStage).filter(number => normalizedStage !== 'BUS_4X4' || slotBays.includes(number))) {
    // New work must only be offered against a positively confirmed active
    // shared bay. Existing/historical bookings still use the deliberately
    // lenient rendering path in workshopBayIsActive().
    const assignee = assignedMechanic === null ? workshopBayMechanic(normalizedStage, bay) || fallbackAssignee : assignedMechanic;
    const allocatedHours = workshopBookingDestinationHours(existingEntry, normalizedStage, bay, hours);
    if (!(allocatedHours > 0)) continue;
    const slot = workshopFirstAvailableStartSlot(normalizedStage, bay, dateKey, allocatedHours, rows, notBeforeMinutes, 260, new Date(), vehicleWindows, assignee, notAfterDateKey, calendarVehicle || (existingEntry ? workshopVehicle(existingEntry.sharedVehicleId || existingEntry.vehicleKey, normalizedStage) : null));
    if (!slot) continue;
    if (notAfterDateKey && slot.dateKey > notAfterDateKey) continue;
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
  return date ? date.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }) : '';
}

function workshopSyncCompletedPlans(rows = workshopLoadPlans(), options = {}) {
  const persist = options.persist !== false;
  let changed = false;
  const next = rows.map(entry => {
    if (entry.status === 'completed') return entry;
    const vehicle = workshopVehicle(entry.vehicleKey);
    const def = vehicle ? pmbStageJobDef(entry.stage) : null;
    if (!vehicle || !def || !pdcJobComplete(vehicle, def)) return entry;
    changed = true;
    return { ...entry, status: 'completed', completedAt: vehicle[def.completeAtKey] || nowIsoString(), updatedAt: nowIsoString() };
  });
  if (changed && persist && !workshopSharedModeActive()) workshopSavePlans(next);
  return next;
}

function workshopStageVehicles(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_ELIGIBILITY_RUNTIME.workshopIsPlannerStage(normalizedStage)) return [];
  const def = pmbStageJobDef(normalizedStage);
  const pmbCandidates = typeof pmbVehiclesNeedingStationWork === 'function' ? pmbVehiclesNeedingStationWork(normalizedStage) : [];
  const preArrivalCandidates = (app.data || []).filter(vehicle => {
    const planningLocation = workshopVehiclePlanningLocation(vehicle);
    if (planningLocation !== 'IT') return false;
    const etaConstraint = workshopVehicleEtaConstraint(vehicle);
    if (!etaConstraint.ok) return false;
    const requiredAndIncomplete = Boolean(def && pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def));
    return requiredAndIncomplete;
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
  const estimatedHoursByStage = vehicle.workshop_estimated_hours_by_stage;
  const pmbJobs = {};
  stageWorkItems.forEach(item => {
    const key = String(item.work_key || jobDef?.key || '').trim();
    if (!key) return;
    pmbJobs[key] = {
      required: item.required === true,
      completed: item.completed === true,
      completedAt: item.completed_at || null,
      notes: ''
    };
  });
  return {
    __workshopStationSnapshotAuthoritative: true,
    id: vehicle.id,
    sharedVehicleId: vehicle.id,
    bus_workflow_department138: vehicle.bus_workflow_department138 === true,
    department_codes: Array.isArray(vehicle.department_codes) ? vehicle.department_codes.slice() : [],
    permanentVehicleId: vehicle.permanent_vehicle_id || '',
    vehicleKey: vehicle.stock_number || vehicle.permanent_vehicle_id || vehicle.id,
    // This station snapshot is restricted to planner operators/admins. Customer
    // name is approved for the tile; notes and broad vehicle fields stay absent.
    stock: vehicle.stock_number || '',
    stockNumber: vehicle.stock_number || '',
    vin: vehicle.vin || '',
    jobCardNumber: vehicle.job_card_number || '',
    jobCardNumbers: Array.isArray(vehicle.job_card_numbers) ? vehicle.job_card_numbers.filter(value => typeof value === 'string') : [],
    keyNumber: vehicle.key_number || '',
    vehicle: vehicle.vehicle_description || vehicle.model || '',
    client: vehicle.customer_name || '',
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
    workshopEstimatedHoursByStage: estimatedHoursByStage && typeof estimatedHoursByStage === 'object' && !Array.isArray(estimatedHoursByStage)
      ? { ...estimatedHoursByStage }
      : {},
    version: vehicle.version
  };
}

function workshopPlannerVehiclesForStage(stage = '') {
  const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  if (!dedicatedStage || !workshopSharedModeActive()) return workshopStageVehicles(stage);
  const snapshot = window.__workshopDataService?.getLastSnapshot?.();
  const snapshotVehicles = Array.isArray(snapshot?.vehicles) ? snapshot.vehicles : [];
  const bookings = Array.isArray(snapshot?.bookings) ? snapshot.bookings : [];
  const workItems = Array.isArray(snapshot?.work_items) ? snapshot.work_items : [];
  const canonicalEligibility = WORKSHOP_ELIGIBILITY_RUNTIME.workshopCanonicalEligibility({
    stage: dedicatedStage,
    vehicles: snapshotVehicles,
    workItems,
    bookings,
  });
  const canonicalById = new Map(canonicalEligibility.candidates.map(row => [String(row.vehicle?.id || '').trim(), row]).filter(([id]) => id));
  const authoritativeRows = Array.isArray(snapshot?.outstanding_candidates) ? snapshot.outstanding_candidates : null;
  const authoritativeById = authoritativeRows
    ? new Map(authoritativeRows.map(row => [String(row?.vehicle_id || '').trim(), row]).filter(([id]) => id))
    : null;
  const eligibleVehicleIds = new Set(authoritativeById ? authoritativeById.keys() : canonicalById.keys());
  const scopedVehicles = snapshotVehicles.filter(vehicle => eligibleVehicleIds.has(String(vehicle?.id || '').trim()));
  const workItemsByVehicle = new Map();
  workItems.forEach(item => {
    const vehicleId = String(item?.vehicle_id || '').trim();
    if (!vehicleId) return;
    const vehicleItems = workItemsByVehicle.get(vehicleId) || [];
    vehicleItems.push(item);
    workItemsByVehicle.set(vehicleId, vehicleItems);
  });
  return scopedVehicles.map(vehicle => {
    const vehicleId = String(vehicle.id || '').trim();
    const authority = workshopCategoryAuthority(authoritativeById?.get(vehicleId), dedicatedStage);
    const displayWorkItems = Array.isArray(authority?.requirements)
      ? authority.requirements
      : (workItemsByVehicle.get(vehicleId) || []);
    const scoped = workshopSnapshotVehicleToPlannerRow(vehicle, displayWorkItems, dedicatedStage);
    const fallback = canonicalById.get(vehicleId);
    const outstanding = {
      workCategory: authority?.work_category || '',
      // r417 (F32): every Bus 4x4 category with its hours, so a drop can book the bay's own category.
      workCategories: Array.isArray(authoritativeById?.get(vehicleId)?.work_categories) ? authoritativeById.get(vehicleId).work_categories : [],
      categoryCompleted: authority?.completed === true,
      existingBooking: authority ? authority.existing_booking === true : fallback?.existingBooking === true,
      scheduleEnabled: authority ? authority.schedule_enabled === true : fallback?.schedule?.enabled === true,
      disabledReason: authority?.disabled_reason || fallback?.schedule?.reason || '',
    };
    return {
      ...scoped,
      pmbJobs: { ...scoped.pmbJobs },
      workshopEstimatedHoursByStage: Number(authority?.estimated_hours) > 0
        ? { ...scoped.workshopEstimatedHoursByStage, [dedicatedStage]: Number(authority.estimated_hours) }
        : dedicatedStage === 'BUS_4X4' && authority?.work_category ? {...scoped.workshopEstimatedHoursByStage, BUS_4X4:null} : scoped.workshopEstimatedHoursByStage,
      __workshopOutstanding: outstanding,
      sharedVehicleId: vehicle.id,
      id: vehicle.id
    };
  }).filter(vehicle => vehicle.__workshopOutstanding?.categoryCompleted !== true).sort((a, b) => String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || '')));
}

function workshopRefreshDedicatedDate(dateKey = '') {
  const stage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  const service = window.__workshopDataService;
  if (!stage || !service || typeof service.setScope !== 'function') return false;
  service.setScope({ stageCode: stage, dateFrom: dateKey, dateTo: dateKey });
  return true;
}

function workshopVehiclePlanningLocation(vehicle = {}) {
  const direct = vehicle.pdcLocation || vehicle.currentLocation || vehicle.current_location || vehicle.manualLocation || '';
  const projected = typeof vehiclePdcLocation === 'function' ? vehiclePdcLocation(vehicle) : '';
  const normalized = cleanNavisionText(direct || projected || '').toUpperCase();
  if (normalized === 'YH' || normalized.includes('YARD HOLD')) return 'YH';
  if (normalized === 'IT' || normalized.includes('IN TRANSIT')) return 'IT';
  return statusCategory(vehicle) === 'pmb' || normalized === 'PMB' ? 'PMB' : normalized;
}

function workshopVehicleEtaConstraint(vehicle = {}) {
  const location = workshopVehiclePlanningLocation(vehicle);
  if (location === 'YH') return { required: false, ok: true, location, earliestDateKey: '', bestSlotEarliestDateKey: '' };
  if (location !== 'IT') return { required: false, ok: true, location, earliestDateKey: '', bestSlotEarliestDateKey: '' };
  const supplied = typeof kewdaleEtaValue === 'function' ? kewdaleEtaValue(vehicle) : '';
  const raw = cleanNavisionText(supplied || vehicle.eta_to_kewdale || vehicle.navisionKewdaleEta || vehicle.etaAtKewdale || vehicle.navisionEtaDate || '');
  const iso = raw.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  let parsed = null;
  if (iso) {
    // r406: midnight Perth on the ETA date.
    const isoDate = new Date(Date.UTC(Number(iso[1]), Number(iso[2]) - 1, Number(iso[3])));
    if (isoDate.getUTCFullYear() === Number(iso[1])
      && isoDate.getUTCMonth() === Number(iso[2]) - 1
      && isoDate.getUTCDate() === Number(iso[3])) parsed = new Date(isoDate.getTime() - 8 * 3600000);
  } else if (raw && typeof parseDateAU === 'function') {
    // parseDateAU builds a device-local midnight from d/m/y; keep that calendar date, in Perth.
    const local = parseDateAU(raw);
    parsed = local && !Number.isNaN(local.getTime())
      ? new Date(Date.UTC(local.getFullYear(), local.getMonth(), local.getDate()) - 8 * 3600000)
      : local;
  }
  if (!parsed || Number.isNaN(parsed.getTime())) return { required: true, ok: false, location, raw, earliestDateKey: '', bestSlotEarliestDateKey: '', reason: raw ? 'invalid_eta' : 'missing_eta' };
  const earliestBookingDate = new Date(parsed.getTime() + 7 * 86400000);
  const earliestDateKey = workshopDateKey(earliestBookingDate);
  return {
    required: true,
    ok: true,
    location,
    raw,
    earliestDateKey,
    bestSlotEarliestDateKey: earliestDateKey,
  };
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
    workshopNotify(`${result.location} vehicles require a valid ETA to Kewdale before they can be booked. Correct the ETA and try again. No booking was created.`);
  } else {
    workshopNotify(`This ${result.location} vehicle cannot be booked before ETA + 7 days. Earliest permitted booking date: ${result.earliestDateKey}. No booking was created.`);
  }
  return false;
}

function workshopEtaRiskForEntry(entry = {}, vehicle = workshopVehicle(entry.vehicleKey)) {
  if (!vehicle || entry.status === 'completed') return null;
  const result = workshopEtaScheduleValidation(vehicle, entry.startAt || entry.scheduledStartAt || '');
  return result.required && !result.ok ? result : null;
}

function workshopEtaRiskLabel(risk = null) {
  if (!risk) return '';
  if (risk.reason === 'missing_eta') return 'ETA RISK · ETA missing';
  if (risk.reason === 'invalid_eta') return 'ETA RISK · ETA invalid';
  return `ETA RISK · earliest ${risk.earliestDateKey || 'unknown'}`;
}

// r566 (F180): shared with Vehicle Locations table search (pdc-workshop-vehicle-search.js).
let workshopVehicleSearchApi;
function workshopVehicleSearchDeps() {
  return {
    cleanNavisionText, vehicleKey, displayStockNumber, vehicleKeyNumber, vehicleJobcardNumber, vehicleCustomerName, displayVehicle,
  };
}
function getWorkshopVehicleSearchApi() {
  if (!workshopVehicleSearchApi) {
    const factory = globalThis.PDC_WORKSHOP_VEHICLE_SEARCH_FACTORY
      || (typeof require === 'function' ? require('./pdc-workshop-vehicle-search.js') : null);
    if (!factory?.create) throw new Error('pdc-workshop-vehicle-search.js must load before workshop planner search runs');
    workshopVehicleSearchApi = globalThis.PDC_WORKSHOP_VEHICLE_SEARCH || factory.create(workshopVehicleSearchDeps);
    globalThis.PDC_WORKSHOP_VEHICLE_SEARCH = workshopVehicleSearchApi;
  }
  return workshopVehicleSearchApi;
}
function workshopSearchJobCards(vehicle = {}) { return getWorkshopVehicleSearchApi().workshopSearchJobCards(vehicle); }
function workshopSearchKeyToken(value = '') { return getWorkshopVehicleSearchApi().workshopSearchKeyToken(value); }
function workshopVehicleKeyToken(vehicle = {}) { return getWorkshopVehicleSearchApi().workshopVehicleKeyToken(vehicle); }
function workshopSearchCriteria(state = typeof workshopState === 'function' ? workshopState() : {}) {
  return getWorkshopVehicleSearchApi().workshopSearchCriteria({ searchKey: state?.searchKey, search: state?.search });
}
function workshopSearchCriteriaKey(criteria = {}) { return getWorkshopVehicleSearchApi().workshopSearchCriteriaKey(criteria); }
function workshopSearchIsActive(criteria = {}) { return getWorkshopVehicleSearchApi().workshopSearchIsActive(criteria); }
function workshopSearchVehicleMatches(vehicle = {}, criteria = {}) { return getWorkshopVehicleSearchApi().workshopSearchVehicleMatches(vehicle, criteria); }
function workshopVehicleSearchText(vehicle = {}) { return getWorkshopVehicleSearchApi().workshopVehicleSearchText(vehicle); }
function workshopSearchRank(vehicle = {}, query = '') { return getWorkshopVehicleSearchApi().workshopSearchRank(vehicle, query); }

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
  return workshopSearchMatchRows(query, plans);
}

function workshopSearchMatchRows(query = '', plans = workshopLoadPlans(), options = {}) {
  const criteria = query && typeof query === 'object' ? query : { text: query || '', key: '' };
  const clean = cleanNavisionText(criteria.text || '').toLowerCase();
  // Extracted tests may load only this function. Keep the old text-length gate when helpers are absent.
  const active = typeof globalThis.workshopSearchIsActive === 'function'
    ? globalThis.workshopSearchIsActive(criteria)
    : clean.length >= 2;
  if (!active) return [];
  const lookup = options.ignoreLookup || typeof workshopCurrentSearchLookup !== 'function' ? null : workshopCurrentSearchLookup(criteria);
  // A post-drop refresh clears trusted authority. Keep matching the last
  // outstanding rows so search does not flash "No booking found".
  const searchService = window.__workshopDataService;
  const snapshot = searchService?.getTrustedSnapshot?.() || searchService?.getLastSnapshot?.() || null;
  const snapshotWorkItems = Array.isArray(snapshot?.work_items) ? snapshot.work_items : [];
  const snapshotRows = (Array.isArray(snapshot?.vehicles) ? snapshot.vehicles : [])
    .map(vehicle => workshopSnapshotVehicleToPlannerRow(vehicle, snapshotWorkItems, workshopState().stage));
  const eligibilityRows = (Array.isArray(app.workshopEligibilitySnapshot?.candidates) ? app.workshopEligibilitySnapshot.candidates : [])
    .map(candidate => candidate?.vehicle ? workshopSnapshotVehicleToPlannerRow(candidate.vehicle, candidate.work_items || candidate.requirements || [], candidate.stage_code || workshopState().stage) : null)
    .filter(Boolean);
  const projectionRows = new Set([...snapshotRows, ...eligibilityRows]);
  const projectionRank = vehicle => vehicle.__emailVehicleServerAuthoritative === true ? 3 : projectionRows.has(vehicle) ? 2 : 0;
  const pool = [...new Map([...app.data, ...snapshotRows, ...eligibilityRows].map(vehicle => {
    const sharedId = String(vehicle?.sharedVehicleId || vehicle?.id || '').trim();
    const key = sharedId || String(vehicleKey(vehicle) || '').trim();
    return [key, vehicle];
  }).filter(([key]) => key)).values()].sort((a, b) => projectionRank(b) - projectionRank(a));
  // A legacy row can resolve to the same UUID while retaining an old customer
  // account in its dealer field. Keep the canonical projection at deduplication
  // so stale display fields cannot suppress its scoped read request.
  return pool
    .filter(vehicle => (typeof globalThis.workshopSearchVehicleMatches === 'function'
      ? globalThis.workshopSearchVehicleMatches(vehicle, criteria)
      : workshopVehicleSearchText(vehicle).includes(clean)))
    .map(vehicle => {
      const key = vehicleKey(vehicle);
      const sharedRef = workshopSharedModeActive() ? workshopSharedVehicleRef({ vehicleKey: key, sharedVehicleId: vehicle.sharedVehicleId || (vehicle.__emailVehicleServerAuthoritative === true ? vehicle.__emailVehicleId : '') }) : null;
      // Board and eligibility projections can hold a verified vehicle absent
      // from this station snapshot. Their UUID selects only this scoped read;
      // navigation still verifies the exact booking in a fresh target snapshot.
      const projectedId = vehicle.__emailVehicleServerAuthoritative === true
        ? String(vehicle.__emailVehicleId || '').trim()
        : snapshotRows.includes(vehicle) || eligibilityRows.includes(vehicle)
          ? String(vehicle.sharedVehicleId || vehicle.id || '').trim() : '';
      const canonicalId = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(projectedId) ? projectedId : sharedRef?.vehicleId;
      const vehicleIdentity = canonicalId ? `shared:${canonicalId}` : `legacy:${key}`;
      const remote = lookup?.status === 'ready' ? lookup.matches.get(vehicleIdentity) : null;
      const bookingRows = remote?.ok ? remote.bookings : (Array.isArray(plans) ? plans : []);
      const bookings = workshopSortBookingsClosest(bookingRows.filter(entry => (
        !['completed', 'deleted', 'cancelled'].includes(entry.status) && workshopPlanVehicleIdentity(entry) === vehicleIdentity
        && normalizePmbStage(entry.stage) === normalizePmbStage(workshopState().stage)
        && (entry.stage !== 'BUS_4X4' || typeof workshopSelectedBusGroup !== 'function' || !workshopSelectedBusGroup()?.code
          || (entry.workCategory && entry.workCategory !== 'BUS_WHOLE_JOB' ? entry.workCategory === workshopSelectedBusGroup().code
            : !(Number(entry.bay) > 0) || workshopSelectedBusGroup().bays.includes(Number(entry.bay))))
      )));
      const stationAuthority = sharedRef?.vehicleId
        ? (Array.isArray(snapshot?.outstanding_candidates) ? snapshot.outstanding_candidates : []).find(candidate => (
          String(candidate?.vehicle_id || '').trim() === String(sharedRef.vehicleId)
          && normalizePmbStage(candidate?.stage_code || candidate?.stage || workshopState().stage) === normalizePmbStage(workshopState().stage)
        ))
        : null;
      const categoryAuthority = typeof workshopCategoryAuthority === 'function'
        ? workshopCategoryAuthority(stationAuthority, workshopState().stage) : stationAuthority;
      const candidateAuthority = categoryAuthority?.completed === true || categoryAuthority?.disabled_reason === 'no_category_work' ? null : categoryAuthority;
      const eligibilityCandidate = canonicalId ? (app.workshopEligibilitySnapshot?.candidates || []).find(candidate => (
        String(candidate?.vehicle?.id || candidate?.vehicle_id || '') === canonicalId
        && normalizePmbStage(candidate?.stage_code || candidate?.stage || '') === normalizePmbStage(workshopState().stage)
      )) : null;
      const eligibilityInfo = typeof workshopCategoryAuthority === 'function'
        ? workshopCategoryAuthority(eligibilityCandidate, workshopState().stage) : eligibilityCandidate;
      return {
        vehicle,
        vehicleKey: key,
        vehicleIdentity,
        returnedBookings: workshopReturnedQueuePlans(plans, workshopState().stage,
          workshopState().stage === 'BUS_4X4' && typeof workshopSelectedBusGroup === 'function' ? workshopSelectedBusGroup()?.code || '' : '')
          .filter(entry => workshopPlanVehicleIdentity(entry) === vehicleIdentity),
        rank: workshopSearchRank(vehicle, clean || criteria.key || ''),
        archived: Boolean(vehicle.isArchived || vehicle.archivedAt || statusCategory(vehicle) === 'deleted'),
        bookings,
        bookingLookupError: remote && !remote.ok ? remote.error || 'request_failed' : '',
        candidateInLane: Boolean(candidateAuthority),
        candidateHasWork: Boolean(eligibilityInfo && eligibilityInfo.completed !== true && eligibilityInfo.disabled_reason !== 'no_category_work'),
        candidateAvailable: candidateAuthority?.schedule_enabled === true && candidateAuthority?.existing_booking !== true,
        candidateDisabledReason: candidateAuthority?.disabled_reason || eligibilityInfo?.disabled_reason || '',
      };
    })
    .filter(item => options.ignoreLookup || !lookup?.limited || lookup.matches.has(item.vehicleIdentity))
    .filter(item => options.includeUnmatched || item.bookings.length || item.returnedBookings.length || item.candidateInLane || item.candidateHasWork || item.bookingLookupError)
    // Board and station projections can use different local keys for the same
    // canonical vehicle. Collapse only the resolved identity, never the stock.
    .filter((item, index, matches) => matches.findIndex(other => other.vehicleIdentity === item.vehicleIdentity) === index)
    .sort((a, b) => a.rank - b.rank
      || String(displayStockNumber(a.vehicle) || a.vehicleKey).localeCompare(String(displayStockNumber(b.vehicle) || b.vehicleKey))
      || a.vehicleKey.localeCompare(b.vehicleKey));
}


// Search owns a separate read-only booking lookup. Its results never enter the
// station snapshot or become scheduling authority for the visible board.
function workshopCurrentSearchLookup(query = '') {
  const lookup = workshopState().bookingSearchLookup;
  const service = window.__workshopDataService;
  const criteria = query && typeof query === 'object' ? query : { text: query || '', key: workshopState().searchKey || '' };
  // A post-drop refresh clears trusted authority but keeps the last snapshot.
  // Search may keep showing that snapshot. It must not treat the gap as an outage.
  const displayed = service?.getTrustedSnapshot?.() || service?.getLastSnapshot?.() || null;
  const criteriaKey = typeof globalThis.workshopSearchCriteriaKey === 'function'
    ? globalThis.workshopSearchCriteriaKey(criteria)
    : cleanNavisionText(criteria.text || '').toLowerCase();
  return lookup && lookup.snapshot && lookup.service === service
    && lookup.query === criteriaKey
    && displayed && lookup.snapshot === displayed ? lookup : null;
}

function workshopMapSearchBookings(result = {}, vehicle = {}) {
  const vehicleId = String(result.vehicleId || '').trim();
  if (!result.ok || !vehicleId || !Array.isArray(result.bookings)) return [];
  return result.bookings.filter(booking => ['planned', 'queued', 'started', 'stoppage'].includes(booking.status))
    .map(booking => workshopMapSnapshotBookingToLegacyRow({
      ...booking,
      vehicle_id: vehicleId,
      vehicle: { id: vehicleId, stock_number: displayStockNumber(vehicle) || vehicleId },
      version: booking.booking_version,
      stage: { code: booking.stage_code },
      bay: { bay_number: booking.bay_number },
    }))
    .filter(entry => entry && WORKSHOP_STAGE_SEQUENCE.includes(entry.stage)
      && entry.bay > 0 && parseIsoTimestamp(entry.startAt || ''));
}

async function workshopLookupSearchVehicle(match = {}) {
  const service = window.__workshopDataService;
  const vehicleId = String(match.vehicleIdentity || '').startsWith('shared:') ? match.vehicleIdentity.slice(7) : '';
  const dealerCode = typeof vehicleWorkshopDetailRequestDealerCode === 'function'
    ? vehicleWorkshopDetailRequestDealerCode(match.vehicle || {}, window.PDC_SUPABASE_CONFIG || {}) : '';
  if (!vehicleId || !dealerCode || typeof service?.lookupVehicleBookings !== 'function') return { ok: false, error: 'booking_lookup_unavailable' };
  try {
    const result = await service.lookupVehicleBookings(vehicleId, dealerCode);
    if (!result?.ok || result.vehicleId !== vehicleId) return { ok: false, error: result?.error || 'booking_lookup_unavailable' };
    return { ok: true, bookings: workshopMapSearchBookings(result, match.vehicle) };
  } catch (_error) {
    return { ok: false, error: 'request_failed' };
  }
}

async function workshopLoadSearchBookings(query = '') {
  const state = workshopState();
  const service = window.__workshopDataService;
  if (!workshopSharedModeActive() || typeof service?.lookupVehicleBookings !== 'function') return;
  if (!service.getTrustedSnapshot?.()) {
    const retained = service.getLastSnapshot?.();
    if (!retained || state.bookingSearchLookup?.snapshot !== retained) state.bookingSearchLookup = null;
    return;
  }
  const criteria = query && typeof query === 'object'
    ? query
    : typeof query === 'string'
      ? { text: query, key: state.searchKey || '' }
      : (typeof globalThis.workshopSearchCriteria === 'function'
        ? globalThis.workshopSearchCriteria(state)
        : { text: state.search || '', key: state.searchKey || '' });
  const criteriaKey = typeof globalThis.workshopSearchCriteriaKey === 'function'
    ? globalThis.workshopSearchCriteriaKey(criteria)
    : cleanNavisionText(criteria.text || '').toLowerCase();
  const active = typeof globalThis.workshopSearchIsActive === 'function'
    ? globalThis.workshopSearchIsActive(criteria)
    : cleanNavisionText(criteria.text || '').length >= 2;
  if (!active) { state.bookingSearchLookup = null; return; }
  const current = workshopCurrentSearchLookup(criteria);
  if (current?.status === 'loading' || current?.status === 'ready') return current.promise;
  const candidates = workshopSearchMatchRows(criteria, workshopLoadPlans(), { includeUnmatched: true, ignoreLookup: true });
  const lookup = { query: criteriaKey, service, snapshot: service.getTrustedSnapshot?.(), status: 'loading', matches: new Map(), limited: candidates.length > 25 };
  state.bookingSearchLookup = lookup;
  lookup.promise = (async () => {
    const selected = candidates.slice(0, 25);
    const currentCriteriaKey = () => (typeof globalThis.workshopSearchCriteriaKey === 'function' && typeof globalThis.workshopSearchCriteria === 'function'
      ? globalThis.workshopSearchCriteriaKey(globalThis.workshopSearchCriteria(state))
      : cleanNavisionText(state.search || '').toLowerCase());
    const current = () => state.bookingSearchLookup === lookup && currentCriteriaKey() === criteriaKey
      && window.__workshopDataService === service && lookup.snapshot === service.getTrustedSnapshot?.();
    if (!current()) return;
    if (typeof service.lookupVehicleBookingsBatch === 'function') {
      const requests = selected.map(match => ({ match,
        vehicleId: String(match.vehicleIdentity || '').startsWith('shared:') ? match.vehicleIdentity.slice(7) : '',
        dealerCode: typeof vehicleWorkshopDetailRequestDealerCode === 'function'
          ? vehicleWorkshopDetailRequestDealerCode(match.vehicle || {}, window.PDC_SUPABASE_CONFIG || {}) : '',
      }));
      const valid = requests.filter(request => request.vehicleId && request.dealerCode);
      let response;
      try {
        response = valid.length ? await service.lookupVehicleBookingsBatch(valid.map(({ vehicleId, dealerCode }) => ({ vehicleId, dealerCode }))) : { ok: true, results: [] };
      } catch (_error) { response = { ok: false, error: 'request_failed' }; }
      if (!current()) return;
      for (const request of requests) {
        const result = response?.ok && Array.isArray(response.results)
          ? response.results.find(result => result.vehicleId === request.vehicleId && result.dealerCode === request.dealerCode) : null;
        lookup.matches.set(request.match.vehicleIdentity, result?.ok
          ? { ok: true, bookings: workshopMapSearchBookings(result, request.match.vehicle) }
          : { ok: false, error: result?.error || response?.error || 'booking_lookup_unavailable' });
      }
    } else if (selected.length <= 4) {
      // Compatibility for a briefly mixed frontend deployment stays bounded.
      const results = await Promise.all(selected.map(match => workshopLookupSearchVehicle(match)));
      if (!current()) return;
      selected.forEach((match, index) => lookup.matches.set(match.vehicleIdentity, results[index]));
    } else {
      selected.forEach(match => lookup.matches.set(match.vehicleIdentity, { ok: false, error: 'booking_search_upgrade_required' }));
    }
    if (!current()) return;
    lookup.status = 'ready';
  })();
  return lookup.promise;
}

function workshopBookingSearchStatus(entry = {}) {
  return entry.status === 'completed' ? 'Completed' : entry.status === 'stoppage' ? 'STOPPAGE' : entry.status === 'started' ? 'Live' : 'Planned';
}

function workshopBookingSearchMeta(entry = {}) {
  const start = parseIsoTimestamp(entry.startAt || '');
  const end = start ? workshopEntryEnd(entry) : null;
  const dateOptions = { timeZone: 'Australia/Perth' };
  const startDate = start?.toLocaleDateString('en-AU', dateOptions);
  const endDate = end?.toLocaleDateString('en-AU', dateOptions);
  return {
    station: pmbStageLabel(entry.stage) || entry.stage || 'Unknown work group',
    bay: entry.bay ? workshopBayText(entry.stage, entry.bay) : 'Bay —',
    date: !start ? 'Unknown date' : endDate && endDate !== startDate ? `${startDate} → ${endDate}` : startDate,
    time: !start || !end ? 'Unknown time' : `${start.toLocaleTimeString('en-AU', { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' })}–${end.toLocaleTimeString('en-AU', { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' })}`,
    status: workshopBookingSearchStatus(entry),
  };
}

function workshopSearchResultsHtml(query = '', plans = workshopLoadPlans()) {
  const criteria = query && typeof query === 'object' ? query : { text: query || '', key: typeof workshopState === 'function' ? workshopState().searchKey || '' : '' };
  const lookupRequired = workshopSharedModeActive() && typeof window.__workshopDataService?.lookupVehicleBookings === 'function';
  const lookup = workshopCurrentSearchLookup(criteria);
  const searchService = window.__workshopDataService;
  if (lookupRequired && !searchService?.getTrustedSnapshot?.() && !searchService?.getLastSnapshot?.()) return '<div class="workshop-search-state" role="status"><strong>Bookings temporarily unavailable</strong><span>Waiting for the workshop connection to refresh.</span></div>';
  if (lookupRequired && (!lookup || lookup.status !== 'ready')) return '<div class="workshop-search-state" role="status"><strong>Finding bookings…</strong><span>Checking this vehicle in the selected station across all dates.</span></div>';
  const matches = workshopSearchMatches(criteria, plans);
  const active = typeof globalThis.workshopSearchIsActive === 'function'
    ? globalThis.workshopSearchIsActive(criteria)
    : cleanNavisionText(criteria.text || '').length >= 2;
  if (!active) return '';
  if (!matches.length) return '<div class="workshop-search-state" role="status"><strong>No booking found</strong><span>No booking or outstanding work matched in this station.</span></div>';
  const ambiguous = matches.length > 1
    ? `<div class="workshop-search-state is-warning" role="status"><strong>Multiple matching vehicles</strong><span>${matches.length} vehicles matched. Choose a specific vehicle and booking; nothing was selected automatically.</span></div>`
    : '';
  const rows = matches.map(match => {
    const vehicle = match.vehicle;
    const identity = {
      key: vehicleKeyNumber(vehicle) || '—',
      stock: displayStockNumber(vehicle) || '—',
      jobcard: workshopSearchJobCards(vehicle).join(', ') || '—',
      customer: vehicleCustomerName(vehicle) || 'Unknown customer',
      description: displayVehicle(vehicle) || 'Vehicle description unavailable',
    };
    const archived = match.archived ? '<span class="workshop-search-alert">Archived vehicle</span>' : '';
    if (!match.archived && match.returnedBookings?.length) return match.returnedBookings.map(entry => `<button type="button" class="workshop-search-result is-unbooked" data-workshop-select-returned-plan="${escapeHtml(entry.id)}" draggable="true" data-workshop-search-drag-plan="${escapeHtml(entry.id)}">
      <span class="workshop-search-result-vehicle"><strong>Key ${escapeHtml(identity.key)} · Stock ${escapeHtml(identity.stock)} · JC ${escapeHtml(identity.jobcard)}</strong><span>${escapeHtml(identity.customer)} · ${escapeHtml(identity.description)}</span></span>
      <span class="workshop-search-result-state"><strong>Drag to a bay</strong><span>Unallocated · ${escapeHtml(Number(entry.hours).toFixed(2))} hours retained. Or select to open this booking.</span></span>
    </button>`).join('');
    if (match.bookingLookupError) return `<article class="workshop-search-result" aria-disabled="true" data-workshop-search-error="${escapeHtml(match.bookingLookupError)}" data-workshop-search-identity-kind="${String(match.vehicleIdentity || '').startsWith('shared:') ? 'canonical' : 'legacy'}"><span class="workshop-search-result-vehicle"><strong>Stock ${escapeHtml(identity.stock)} · ${escapeHtml(identity.customer)}</strong></span><span class="workshop-search-result-state"><strong>Bookings could not be checked</strong><span>${match.bookingLookupError === 'booking_search_upgrade_required' ? 'Refine the search to a specific vehicle, or refresh the planner.' : 'Refresh the search to try again.'}</span></span></article>`;
    if (!match.bookings.length) {
      if (!match.candidateAvailable || match.archived) {
        const reason = match.archived
          ? 'Archived vehicles cannot be scheduled.'
          : (match.candidateDisabledReason ? workshopOutstandingDisabledReasonLabel(match.candidateDisabledReason)
            : 'This vehicle is not currently available in the selected station candidate lane.');
        return `<article class="workshop-search-result is-unbooked is-scheduling-disabled" aria-disabled="true">
          <span class="workshop-search-result-vehicle"><strong>Key ${escapeHtml(identity.key)} · Stock ${escapeHtml(identity.stock)} · JC ${escapeHtml(identity.jobcard)}</strong><span>${escapeHtml(identity.customer)} · ${escapeHtml(identity.description)}</span></span>
          <span class="workshop-search-result-state">${archived}<strong>Scheduling unavailable</strong><span>${escapeHtml(reason)}</span></span>
        </article>`;
      }
      return `<button type="button" class="workshop-search-result is-unbooked" data-workshop-search-unbooked-identity="${escapeHtml(match.vehicleIdentity)}" draggable="true" data-workshop-search-drag-vehicle="${escapeHtml(match.vehicleIdentity)}">
        <span class="workshop-search-result-vehicle"><strong>Key ${escapeHtml(identity.key)} · Stock ${escapeHtml(identity.stock)} · JC ${escapeHtml(identity.jobcard)}</strong><span>${escapeHtml(identity.customer)} · ${escapeHtml(identity.description)}</span></span>
        <span class="workshop-search-result-state">${archived}<strong>Drag to a bay</strong><span>Or select to highlight this vehicle in Unallocated.</span></span>
      </button>`;
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
  const limitNotice = lookup?.limited ? '<div class="workshop-search-state" role="status">Showing the first 25 matching vehicles. Refine the search for another vehicle.</div>' : '';
  return `${ambiguous}${limitNotice}<div class="workshop-search-results-list">${rows}</div>`;
}

function workshopSearchControlHtml(query = '', plans = workshopLoadPlans()) {
  const state = workshopState();
  const criteria = { key: state.searchKey || '', text: query || state.search || '' };
  const open = state.searchOpen && workshopSearchIsActive(criteria);
  const filled = workshopSearchKeyToken(criteria.key) || cleanNavisionText(criteria.text);
  return `<section class="workshop-booking-search${open ? ' is-open' : ''}" aria-label="Find a workshop booking">
    <label><span>Key number</span><input type="search" role="combobox" aria-autocomplete="list" data-workshop-search-key value="${escapeHtml(criteria.key)}" placeholder="Key number" autocomplete="off" aria-controls="workshop-booking-search-results" aria-expanded="${open ? 'true' : 'false'}" /></label>
    <label><span>Stock, job card, customer or vehicle</span><input type="search" role="combobox" aria-autocomplete="list" data-workshop-search value="${escapeHtml(criteria.text)}" placeholder="Stock, job card, customer or vehicle" autocomplete="off" aria-controls="workshop-booking-search-results" aria-expanded="${open ? 'true' : 'false'}" /></label>
    <button type="button" class="small-button" data-workshop-search-clear ${filled ? '' : 'disabled'}>Clear</button>
    <div id="workshop-booking-search-results" class="workshop-search-results" ${open ? '' : 'hidden'}>${open ? workshopSearchResultsHtml(criteria, plans) : ''}</div>
  </section>`;
}

// r470 (F83): the planner re-renders on every live refresh and clock update. Scrolling to the found booking on each render
// made the page scroll up and down by itself after a Find. Scroll (and pulse) once per selection; later renders keep the
// highlight styling but never move the page.
let WORKSHOP_HIGHLIGHT_SCROLL_DONE = '';

function workshopHighlightScrollSignature(state = workshopState()) {
  const key = state.highlightVehicleKey || '';
  const planId = state.searchHighlightPlanId || '';
  if (!key && !planId) return '';
  return `${Number(state.highlightScrollRequest || 0)}|${key}|${planId}`;
}

function workshopScrollToHighlightedVehicle(root = document) {
  if (app.pendingWorkshopBookingLink?.search === true) return;
  const state = workshopState();
  const key = state.highlightVehicleKey;
  const planId = state.searchHighlightPlanId;
  const signature = workshopHighlightScrollSignature(state);
  if (!signature) { WORKSHOP_HIGHLIGHT_SCROLL_DONE = ''; return; }
  if (signature === WORKSHOP_HIGHLIGHT_SCROLL_DONE) return;
  window.requestAnimationFrame(() => {
    if (workshopHighlightScrollSignature(workshopState()) !== signature || WORKSHOP_HIGHLIGHT_SCROLL_DONE === signature) return;
    const bookingTarget = planId ? Array.from(root.querySelectorAll('[data-workshop-plan-id]')).find(element => element.dataset.workshopPlanId === planId) : null;
    const vehicleTarget = key ? Array.from(root.querySelectorAll('[data-workshop-locate-key]')).find(element => element.dataset.workshopLocateKey === key) : null;
    const target = planId ? bookingTarget : vehicleTarget;
    // Not drawn yet (e.g. the planner is still moving to that date): try again on the next render.
    if (target) WORKSHOP_HIGHLIGHT_SCROLL_DONE = signature;
    target?.scrollIntoView({ behavior: window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches ? 'auto' : 'smooth', block: 'center', inline: 'center' });
    if (target && window.WorkshopNavigation?.replaceWorkshopHighlight) {
      window.WorkshopNavigation.replaceWorkshopHighlight(root, target, {
        highlightClass: 'is-workshop-navigation-pulse',
        reducedMotionClass: 'is-workshop-navigation-pulse-reduced-motion',
        staleSelector: '.is-workshop-navigation-pulse, .is-workshop-navigation-pulse-reduced-motion',
      });
      const previousTabIndex = target.getAttribute('tabindex');
      if (typeof target.focus === 'function') {
        if (previousTabIndex === null) target.setAttribute('tabindex', '-1');
        target.focus({ preventScroll: true });
      }
      const clearHighlight = () => {
        target.classList.remove('is-workshop-navigation-pulse', 'is-workshop-navigation-pulse-reduced-motion');
        if (previousTabIndex === null) target.removeAttribute('tabindex');
      };
      target.addEventListener('pointerdown', clearHighlight, { once: true });
      target.addEventListener('keydown', clearHighlight, { once: true });
      window.setTimeout(clearHighlight, 5000);
    }
  });
}

async function workshopSelectSearchBooking(bookingId = '', vehicleIdentity = '') {
  window.clearTimeout(app.workshopPlannerSearchTimer);
  const state = workshopState();
  const query = state.search;
  const selectionGeneration = state.bookingSearchSelectionGeneration = (state.bookingSearchSelectionGeneration || 0) + 1;
  state.bookingNavigationError = '';
  let plans = workshopLoadPlans();
  if (workshopSharedModeActive() && typeof window.__workshopDataService?.lookupVehicleBookings === 'function') {
    const service = window.__workshopDataService;
    const searchCriteria = typeof globalThis.workshopSearchCriteria === 'function'
      ? globalThis.workshopSearchCriteria(state)
      : { text: state.search || '', key: state.searchKey || '' };
    const match = workshopSearchMatchRows(searchCriteria, plans, { includeUnmatched: true }).find(item => item.vehicleIdentity === vehicleIdentity);
    if (!match) return false;
    const result = await workshopLookupSearchVehicle(match);
    if (window.__workshopDataService !== service || state.search !== query || state.bookingSearchSelectionGeneration !== selectionGeneration) return false;
    if (!result.ok) {
      state.bookingNavigationError = 'This booking could not be checked. Please search again.';
      renderWorkshopPlanner();
      return false;
    }
    plans = result.bookings;
  }
  const entry = workshopResolveBookingSelection(plans, bookingId, vehicleIdentity);
  if (!entry || normalizePmbStage(entry.stage) !== normalizePmbStage(state.stage)
      || (entry.stage === 'BUS_4X4' && typeof workshopSelectedBusGroup === 'function'
        && workshopSelectedBusGroup()?.code && (entry.workCategory && entry.workCategory !== 'BUS_WHOLE_JOB' ? entry.workCategory !== workshopSelectedBusGroup().code
          : !workshopSelectedBusGroup().bays.includes(Number(entry.bay))))) {
    state.bookingSearchLookup = null;
    state.searchOpen = true;
    workshopRefreshSearchResults(document.querySelector('#workshop-planner-root') || document, null, state.search);
    return false;
  }
  state.stage = entry.stage;
  state.date = workshopEntryDate(entry);
  state.selectedPlanId = entry.id;
  state.highlightVehicleKey = entry.vehicleKey;
  state.searchHighlightPlanId = entry.id;
  state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
  state.searchOpen = false;
  state.detailCollapsedForSelection = true;
  state.detailManualOpen = false;
  state.searchNotice = '';
  state.focusedBookingMode = false;
  state.focusedBookingId = '';
  workshopSaveView(state);
  if (workshopSharedModeActive()) {
    app.pendingWorkshopOpenToday = false;
    app.pendingWorkshopBookingLink = { bookingId: entry.id, vehicleId: entry.sharedVehicleId, stage: entry.stage, date: state.date, search: true, focused: false };
    const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
    if (dedicatedStage !== entry.stage && typeof openWorkshopPlannerForStage === 'function') {
      openWorkshopPlannerForStage(entry.stage);
    } else {
      const service = window.__workshopDataService;
      const scope = service?.getScope?.();
      if (scope?.stageCode === entry.stage && scope?.dateFrom === state.date && scope?.dateTo === state.date) {
        await service.loadSnapshot?.('booking_search_navigation');
      } else {
        await service?.setScope?.({ stageCode: entry.stage, dateFrom: state.date, dateTo: state.date });
      }
      if (window.__workshopDataService !== service || state.bookingSearchSelectionGeneration !== selectionGeneration) return false;
      renderWorkshopPlanner();
    }
  } else renderWorkshopPlanner();
  return true;
}

function workshopResolveFocusedBooking(pending = {}, plans = [], stage = '') {
  const bookingId = String(pending.bookingId || '').trim();
  const normalizedStage = normalizePmbStage(stage || pending.stage || '');
  const matches = plans.filter(entry => normalizePmbStage(entry.stage) === normalizedStage
    && String(entry.sharedBookingId || '').trim() === bookingId
    && workshopEntryDate(entry) === String(pending.date || '').trim());
  if (!bookingId || matches.length !== 1) {
    return { ok: false, error: matches.length > 1 ? 'ambiguous_booking_id' : 'booking_not_in_scoped_snapshot' };
  }
  const entry = matches[0];
  const vehicle = workshopVehicle(entry.vehicleKey, normalizedStage);
  const operationLines = vehicle
    ? workshopStageJobLines(vehicle, normalizedStage).filter(line => line.source === 'authenticated-operation-line')
    : [];
  if (!vehicle || !operationLines.length || operationLines.some(line => !Number.isFinite(Number(line.hours)))) {
    return { ok: false, error: 'authenticated_operation_lines_unavailable' };
  }
  return { ok: true, entry, vehicle, operationLines };
}

function workshopResetFocusedBooking() {
  const state = workshopState();
  state.focusedBookingMode = false;
  state.focusedBookingId = '';
  state.focusedBookingError = '';
  state.selectedPlanId = '';
  state.searchHighlightPlanId = '';
  state.searchNotice = '';
  state.detailManualOpen = false;
  state.detailCollapsedForSelection = false;
  if (typeof app !== 'undefined') app.pendingWorkshopBookingLink = null;
}

function workshopExitFocusedBooking() {
  workshopResetFocusedBooking();
  workshopSaveView(workshopState());
  renderWorkshopPlanner();
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
  state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
  state.searchOpen = false;
  state.detailCollapsedForSelection = false;
  state.detailManualOpen = true;
  state.searchNotice = '';
  workshopSaveView(state);
  renderWorkshopPlanner();
  return true;
}

function workshopRevealSearchMatch(query = '', field = 'text') {
  const state = workshopState();
  if (field === 'clear') {
    state.search = '';
    state.searchKey = '';
  } else if (field === 'key') state.searchKey = cleanNavisionText(query || '');
  else state.search = cleanNavisionText(query || '');
  state.searchOpen = workshopSearchIsActive(workshopSearchCriteria(state));
  state.bookingNavigationError = '';
  if (!state.searchOpen) {
    state.bookingSearchLookup = null;
    state.highlightVehicleKey = '';
    state.searchHighlightPlanId = '';
    state.searchNotice = '';
  }
  renderWorkshopPlanner();
}

function workshopDropLaneAtPoint(clientX, clientY) {
  const nodes = typeof document.elementsFromPoint === 'function'
    ? document.elementsFromPoint(clientX, clientY)
    : [typeof document.elementFromPoint === 'function' ? document.elementFromPoint(clientX, clientY) : null];
  for (const node of nodes || []) {
    const lane = node?.closest?.('[data-workshop-drop-bay]');
    if (lane) return lane;
  }
  return null;
}

// Mouse and touch both use pointer capture. Native HTML5 drop from a card
// deep in .workshop-side-list fires dragstart/dragend and never drop: Chrome
// hit-tests from the scrolled source. The search overlay has the same gap,
// because pointer-events changes during a native drag do not retarget it.
function workshopStartPointerDragSession(source, downEvent, root, session = {}) {
  if (source?.getAttribute?.('aria-disabled') === 'true') return;
  const nestedControl = downEvent.target?.closest?.('button, a, input, select, textarea');
  if (nestedControl && nestedControl !== source) return;
  if (workshopActiveQueuePointerDrag) return;
  const pointerId = downEvent.pointerId;
  const startX = downEvent.clientX;
  const startY = downEvent.clientY;
  let activeLane = null;
  let activated = false;
  let pointerFrame = null;
  let pendingPointer = null;
  workshopActiveQueuePointerDrag = { pointerId, source };
  const cancelPointerFrame = () => {
    if (pointerFrame !== null) window.cancelAnimationFrame?.(pointerFrame);
    pointerFrame = null;
    pendingPointer = null;
  };
  const cleanup = () => {
    cancelPointerFrame();
    window.removeEventListener('pointermove', move);
    window.removeEventListener('pointerup', finish);
    window.removeEventListener('pointercancel', cancel);
    source.removeEventListener?.('lostpointercapture', cancel);
    if (source.hasPointerCapture?.(pointerId)) source.releasePointerCapture(pointerId);
    if (activeLane) activeLane.classList.remove('drag-over');
    workshopSetDragPreview(null);
    workshopClearLanePreviews(root);
    root?.querySelector?.('#workshop-booking-search-results')?.classList.remove('is-dragging');
    if (workshopActiveQueuePointerDrag?.source === source) workshopActiveQueuePointerDrag = null;
    workshopSuppressMouseDragUntil = Date.now() + 750;
  };
  const activate = () => {
    if (activated) return;
    activated = true;
    if (source.dataset) source.dataset.workshopPointerDragged = '1';
    source.setPointerCapture?.(pointerId);
    source.addEventListener?.('lostpointercapture', cancel);
    root?.querySelector?.('#workshop-booking-search-results')?.classList.add('is-dragging');
    const preview = session.preview?.();
    if (preview) workshopSetDragPreview(preview);
  };
  const paintPointer = event => {
    const lane = workshopDropLaneAtPoint(event.clientX, event.clientY);
    if (activeLane && activeLane !== lane) {
      activeLane.classList.remove('drag-over');
      workshopHideLanePreview(activeLane);
    }
    activeLane = lane;
    if (!lane) return;
    lane.classList.add('drag-over');
    workshopPaintLanePointer(lane, event.clientX, event.clientY);
  };
  const move = event => {
    if (event.pointerId !== pointerId) return;
    if (!activated && Math.hypot(event.clientX - startX, event.clientY - startY) < 8) return;
    activate();
    event.preventDefault();
    pendingPointer = { clientX: event.clientX, clientY: event.clientY };
    if (pointerFrame !== null) return;
    if (typeof window.requestAnimationFrame !== 'function') { paintPointer(pendingPointer); return; }
    pointerFrame = window.requestAnimationFrame(() => {
      const pointer = pendingPointer;
      pointerFrame = null;
      pendingPointer = null;
      if (pointer) paintPointer(pointer);
    });
  };
  const finish = event => {
    if (event.pointerId !== pointerId) return;
    cancelPointerFrame();
    if (activated) paintPointer(event);
    const lane = activeLane;
    const stage = lane?.dataset.workshopDropStage;
    const bay = Number(lane?.dataset.workshopDropBay);
    const dateKey = workshopState().date;
    const startMinutes = Number(lane?.dataset.workshopRequestedStartMinutes);
    cleanup();
    if (!activated || !lane || !stage || !Number.isFinite(bay) || !Number.isFinite(startMinutes)) return;
    session.onDrop?.({ stage, bay, dateKey, startMinutes });
  };
  const cancel = event => {
    if (event?.pointerId != null && event.pointerId !== pointerId) return;
    cleanup();
  };
  window.addEventListener('pointermove', move, { passive: false });
  window.addEventListener('pointerup', finish);
  window.addEventListener('pointercancel', cancel);
}

function workshopBindSearchDragResults(root) {
  root.querySelectorAll('[data-workshop-search-drag-plan], [data-workshop-search-drag-vehicle]').forEach(button => {
    if (button.dataset.searchDragBound === '1') return;
    button.dataset.searchDragBound = '1';
    button.addEventListener('dragstart', event => {
      if (workshopActiveQueuePointerDrag) { event.preventDefault(); return; }
      if (!event.dataTransfer || !window.__workshopDataService?.getTrustedSnapshot?.()) {
        event.preventDefault(); return;
      }
      const planId = button.dataset.workshopSearchDragPlan;
      if (planId) {
        const plan = workshopReturnedPlanForAction(planId);
        if (!plan) { event.preventDefault(); return; }
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('application/x-workshop-plan-id', plan.id);
        workshopSetDragPreview({ type: 'plan', hours: Number(plan.hours), entry: plan });
      } else {
        const dragCriteria = typeof globalThis.workshopSearchCriteria === 'function'
          ? globalThis.workshopSearchCriteria()
          : { text: workshopState().search || '', key: workshopState().searchKey || '' };
        const match = workshopSearchMatches(dragCriteria, workshopLoadPlans()).find(item =>
          item.vehicleIdentity === button.dataset.workshopSearchDragVehicle && item.candidateAvailable
          && !item.archived && !item.bookingLookupError && !item.bookings.length && !item.returnedBookings?.length);
        if (!match) { event.preventDefault(); return; }
        const vehicle = workshopVehicle(match.vehicleKey, workshopState().stage);
        const hours = workshopSchedulingDuration(vehicle, workshopState().stage)?.hours;
        if (!(hours > 0)) { event.preventDefault(); return; }
        event.dataTransfer.effectAllowed = 'copy';
        event.dataTransfer.setData('application/x-workshop-vehicle-key', match.vehicleKey);
        event.dataTransfer.setData('text/plain', match.vehicleKey);
        workshopSetDragPreview({ type: 'queue', hours });
      }
      // Keep the drag source alive, but let lanes under the search receive drops.
      root.querySelector('#workshop-booking-search-results')?.classList.add('is-dragging');
    });
    button.addEventListener('pointerdown', downEvent => {
      const planId = button.dataset.workshopSearchDragPlan;
      workshopStartPointerDragSession(button, downEvent, root, {
        preview() {
          if (planId) {
            const plan = workshopReturnedPlanForAction(planId);
            return plan ? { type: 'plan', hours: Number(plan.hours), entry: plan } : null;
          }
          const match = workshopSearchDragVehicle(button);
          const hours = match ? workshopSchedulingDuration(workshopVehicle(match.vehicleKey, workshopState().stage), workshopState().stage)?.hours : 0;
          return hours > 0 ? { type: 'queue', hours } : null;
        },
        onDrop({ stage, bay, dateKey, startMinutes }) {
          if (!window.__workshopDataService?.getTrustedSnapshot?.()) return;
          if (planId) {
            const plan = workshopReturnedPlanForAction(planId, { explain: true });
            if (!plan) return;
            void moveWorkshopDroppedPlan(plan.id, stage, bay, dateKey, startMinutes, { preferRequestedTime: true });
            return;
          }
          const match = workshopSearchDragVehicle(button);
          const hours = match ? workshopSchedulingDuration(workshopVehicle(match.vehicleKey, workshopState().stage), workshopState().stage)?.hours : 0;
          if (!match || !(hours > 0)) return;
          void scheduleWorkshopVehicle({ vehicleKeyValue: match.vehicleKey, stage, bay, dateKey, startMinutes, hoursValue: hours, preferRequestedTime: true });
        },
      });
    });
    button.addEventListener('click', event => {
      if (button.dataset.workshopPointerDragged !== '1') return;
      delete button.dataset.workshopPointerDragged;
      event.preventDefault();
      event.stopPropagation();
    }, true);
    button.addEventListener('dragend', () => {
      root.querySelector('#workshop-booking-search-results')?.classList.remove('is-dragging');
      workshopSetDragPreview(null);
      workshopClearLanePreviews(root);
    });
  });
}

function workshopSearchDragVehicle(button) {
  const dragCriteria = typeof globalThis.workshopSearchCriteria === 'function'
    ? globalThis.workshopSearchCriteria()
    : { text: workshopState().search || '', key: workshopState().searchKey || '' };
  return workshopSearchMatches(dragCriteria, workshopLoadPlans()).find(item =>
    item.vehicleIdentity === button.dataset.workshopSearchDragVehicle && item.candidateAvailable
    && !item.archived && !item.bookingLookupError && !item.bookings.length && !item.returnedBookings?.length) || null;
}

function workshopBindDragAutoScroll(root) {
  if (root.dataset.dragAutoScrollBound === '1') return;
  root.dataset.dragAutoScrollBound = '1';
  let frame = null, point = null, lastAt = 0;
  const stop = () => {
    if (frame !== null) window.cancelAnimationFrame(frame);
    frame = null; point = null; lastAt = 0;
    root.querySelector('#workshop-booking-search-results')?.classList.remove('is-dragging');
  };
  const velocity = (value, low, high) => {
    const edge = 65;
    if (value < low || value > high) return 0;
    return value < low + edge ? -Math.ceil(18 * (1 - (value - low) / edge))
      : value > high - edge ? Math.ceil(18 * (1 - (high - value) / edge)) : 0;
  };
  const tick = () => {
    frame = null;
    if (!point || !root.isConnected || !workshopCurrentDragPreview() || Date.now() - lastAt > 500) { stop(); return; }
    const dy = velocity(point.y, 0, window.innerHeight);
    if (dy) window.scrollBy(0, dy);
    const scroller = root.querySelector('.workshop-timeline-scroll');
    if (scroller) {
      const r = scroller.getBoundingClientRect();
      if (point.y >= r.top && point.y <= r.bottom) {
        const dx = velocity(point.x, Math.max(0, r.left), Math.min(window.innerWidth, r.right));
        if (dx) scroller.scrollLeft += dx;
      }
    }
    frame = window.requestAnimationFrame(tick);
  };
  const move = event => {
    if (!root.isConnected || !workshopCurrentDragPreview()) return;
    point = {x:event.clientX,y:event.clientY}; lastAt = Date.now();
    if (frame === null) frame = window.requestAnimationFrame(tick);
  };
  root.addEventListener('dragover', move);
  root.addEventListener('pointermove', move);
  root.addEventListener('drop', stop);
  root.addEventListener('dragend', stop);
  root.addEventListener('pointerup', stop);
  root.addEventListener('pointercancel', stop);
}

function workshopBindSearchResultButtons(root = document) {
  workshopBindSearchDragResults(root);
  root.querySelectorAll('[data-workshop-select-returned-plan]').forEach(button => {
    if (button.dataset.returnedSelectionBound === '1') return;
    button.dataset.returnedSelectionBound = '1';
    button.addEventListener('click', () => workshopSelectReturnedPlan(button.dataset.workshopSelectReturnedPlan));
  });
  root.querySelectorAll('[data-workshop-search-booking-id]').forEach(button => button.addEventListener('click', () => {
    void workshopSelectSearchBooking(button.dataset.workshopSearchBookingId, button.dataset.workshopSearchVehicleIdentity);
  }));
  root.querySelectorAll('[data-workshop-search-unbooked-identity]').forEach(button => button.addEventListener('click', () => {
    void workshopSelectUnbookedSearchVehicle(button.dataset.workshopSearchUnbookedIdentity);
  }));
}

async function workshopSelectUnbookedSearchVehicle(vehicleIdentity = '') {
  const state = workshopState();
  const selectionGeneration = state.bookingSearchSelectionGeneration = (state.bookingSearchSelectionGeneration || 0) + 1;
  const searchCriteria = typeof globalThis.workshopSearchCriteria === 'function'
    ? globalThis.workshopSearchCriteria(state)
    : { text: state.search || '', key: state.searchKey || '' };
  const match = workshopSearchMatches(searchCriteria, workshopLoadPlans()).find(item => item.vehicleIdentity === vehicleIdentity && !item.bookings.length && item.candidateAvailable && !item.archived);
  if (!match) {
    state.searchOpen = true;
    renderWorkshopPlanner();
    return false;
  }
  if (workshopSharedModeActive() && typeof window.__workshopDataService?.lookupVehicleBookings === 'function') {
    const service = window.__workshopDataService;
    const query = state.search;
    const result = await workshopLookupSearchVehicle(match);
    if (window.__workshopDataService !== service || state.search !== query || state.bookingSearchSelectionGeneration !== selectionGeneration) return false;
    if (!result.ok) {
      state.bookingNavigationError = 'This vehicle’s bookings could not be checked. Please search again.';
      renderWorkshopPlanner();
      return false;
    }
    const stationBookings = result.bookings.filter(entry =>
      normalizePmbStage(entry.stage) === normalizePmbStage(state.stage)
      && (entry.stage !== 'BUS_4X4' || !workshopSelectedBusGroup()?.code
        || (entry.workCategory && entry.workCategory !== 'BUS_WHOLE_JOB' ? entry.workCategory === workshopSelectedBusGroup().code
          : workshopSelectedBusGroup().bays.includes(Number(entry.bay)))));
    if (stationBookings.length) {
      const closest = workshopSortBookingsClosest(stationBookings)[0];
      return workshopSelectSearchBooking(closest.id, vehicleIdentity);
    }
  }
  state.highlightVehicleKey = match.vehicleKey;
  state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
  state.searchHighlightPlanId = '';
  state.selectedPlanId = '';
  state.searchOpen = false;
  state.detailCollapsedForSelection = true;
  state.detailManualOpen = false;
  state.searchNotice = 'Unbooked vehicle highlighted in the candidate lane. Choose Best slot or Schedule.';
  workshopSaveView(state);
  renderWorkshopPlanner();
  return true;
}

async function workshopRefreshSearchResults(root = document, input = null, query = '') {
  const state = workshopState();
  if (input?.hasAttribute?.('data-workshop-search-key')) state.searchKey = cleanNavisionText(query || '');
  else if (input || query !== undefined) state.search = cleanNavisionText(query || '');
  const criteria = workshopSearchCriteria(state);
  state.searchOpen = workshopSearchIsActive(criteria);
  const results = root.querySelector('#workshop-booking-search-results');
  const control = input?.closest('.workshop-booking-search') || root.querySelector?.('.workshop-booking-search');
  const clear = control?.querySelector('[data-workshop-search-clear]');
  if (results) {
    results.innerHTML = state.searchOpen ? workshopSearchResultsHtml(criteria) : '';
    results.hidden = !state.searchOpen;
  }
  control?.classList.toggle('is-open', state.searchOpen);
  control?.querySelectorAll('input').forEach(field => field.setAttribute('aria-expanded', state.searchOpen ? 'true' : 'false'));
  if (clear) clear.disabled = !workshopSearchKeyToken(state.searchKey) && !cleanNavisionText(state.search);
  workshopBindSearchResultButtons(root);
  await workshopLoadSearchBookings(criteria);
  if (workshopSearchCriteriaKey(workshopSearchCriteria()) !== workshopSearchCriteriaKey(criteria) || (input && !input.isConnected)) return;
  const currentResults = root.querySelector('#workshop-booking-search-results');
  if (currentResults?.isConnected) {
    currentResults.innerHTML = state.searchOpen ? workshopSearchResultsHtml(criteria) : '';
    workshopBindSearchResultButtons(root);
  }
}

function workshopPartsSummary(vehicle = {}) {
  const projected = typeof canonicalVehicleWorkState === 'function' && typeof partsJobDef === 'function'
    ? canonicalVehicleWorkState(vehicle, partsJobDef())
    : null;
  const status = projected?.state === 'stoppage'
    ? 'stoppage'
    : projected?.state === 'completed'
      ? 'issued'
      : projected?.state === 'booked'
        ? 'onorder'
        : projected?.state === 'none'
          ? 'notrequired'
          : partsDepartmentStatus(vehicle);
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
  return workshopCoerceWorkDate(new Date(next.getTime() + 86400000), 1);
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
  const dateLabel = targetDate.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric' });
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
        `  ${workshopBayChoiceLabel(entry.stage, entry.bay)} from ${start} · Parts: ${partsDepartmentStatusLabel(partsStatus)}${eta ? ` · ETA ${eta}` : ''}`,
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
    workshopNotify(`No next-workday Fitting bookings were found with unconfirmed parts for ${result.targetDate.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth' })}.`, 'info');
    return false;
  }
  const recipient = '';
  const dateLabel = result.targetDate.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' });
  const subject = `PDC WARNING - Fitting bookings without confirmed parts - ${dateLabel}`;
  result.warnings.forEach(({ vehicle }) => {
    if (typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, 'Next-day fitting parts warning email drafted', { recipient: 'Selected in email client', bookingDate: result.dateKey });
  });
  window.location.href = `mailto:${encodeURIComponent(recipient)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(workshopNextDayFittingWarningEmailBody(result))}`;
  return true;
}

function workshopQueueVehicleDescription(vehicle = {}) {
  return cleanNavisionText(
    (typeof displayVehicle === 'function' ? displayVehicle(vehicle) : '')
      || vehicle.vehicle_description || vehicle.vehicleDescription || vehicle.model || ''
  ) || 'Model not listed';
}

function workshopVehicleIdentitySummaryHtml(vehicle = {}) {
  const stock = cleanNavisionText(typeof displayStockNumber === 'function' ? displayStockNumber(vehicle) : vehicle.stock || vehicle.stock_number) || 'Unknown';
  const stackedCards = typeof pdcOpenJobCardLabel === 'function' ? pdcOpenJobCardLabel(vehicle) : '';
  const jobCard = stackedCards || cleanNavisionText(typeof vehicleJobcardNumber === 'function' ? vehicleJobcardNumber(vehicle) : vehicle.jobcard || vehicle.job_card_number) || 'Unknown';
  const location = cleanNavisionText(vehicle.sourceLocationStatus || vehicle.navisionLocationStatus || vehicle.currentLocation || vehicle.pdcLocation) || 'Unknown';
  return `<strong><span class="vehicle-copyable-field">JC ${escapeHtml(jobCard)}</span> · <span class="vehicle-copyable-field">Stock ${escapeHtml(stock)}</span></strong><small class="workshop-vehicle-location">Location: ${escapeHtml(location)}</small>`;
}

function workshopQueueEstimatedLabel(vehicle = {}, stage = '') {
  const duration = workshopSchedulingDuration(vehicle, stage);
  if (duration) return `${duration.hours.toFixed(2)}h`;
  const lines = workshopStageJobLines(vehicle, stage).filter(line => line.source === 'authenticated-operation-line');
  if (!lines.length || lines.some(line => line.hours === null || line.hours === undefined || !Number.isFinite(Number(line.hours)))) return 'Hours unknown';
  const minutes = lines.reduce((sum, line) => sum + Math.round(Number(line.hours || 0) * 60), 0);
  return `${(minutes / 60).toFixed(2)}h`;
}

function workshopQueueCardHtml(vehicle = {}, stage = workshopState().stage, dateKey = workshopState().date, rows = workshopLoadPlans()) {
  const key = vehicleKey(vehicle);
  const blocked = isPdcBlocked(vehicle);
  const parts = workshopPartsSummary(vehicle);
  const highlighted = workshopState().highlightVehicleKey === key;
  const hoursLabel = workshopQueueEstimatedLabel(vehicle, stage);
  const duration = workshopSchedulingDuration(vehicle, stage);
  const hours = duration?.hours || 0;
  const etaConstraint = workshopVehicleEtaConstraint(vehicle);
  const etaDisabled = etaConstraint.required && !etaConstraint.ok;
  const authoritative = vehicle.__workshopOutstanding;
  const existingBooking = authoritative?.existingBooking === true;
  const authorityDisabled = !!authoritative && authoritative.scheduleEnabled !== true;
  const durationDisabled = workshopSharedModeActive() && !duration;
  const schedulingDisabled = authorityDisabled || etaDisabled || existingBooking || durationDisabled;

  const etaExplanation = etaConstraint.reason === 'missing_eta'
    ? `${etaConstraint.location} · ETA to Kewdale is missing; scheduling disabled`
    : etaConstraint.reason === 'invalid_eta'
      ? `${etaConstraint.location} · ETA to Kewdale is invalid; scheduling disabled`
      : '';
  // Availability is resolved against fresh authority when Best slot is clicked.
  // Do not search every bay and future day merely to paint the waiting list.
  const authorityExplanation = workshopOutstandingDisabledReasonLabel(authoritative?.disabledReason);
  const disabledExplanation = existingBooking
    ? 'An active booking already represents this requirement'
    : durationDisabled ? workshopOutstandingDisabledReasonLabel('estimated_duration_missing')
      : authorityDisabled ? authorityExplanation : etaExplanation;
  return `<article class="workshop-queue-card workshop-unallocated-vehicle-pill ${blocked ? 'is-blocked' : ''} ${highlighted ? 'is-search-match' : ''} ${schedulingDisabled ? 'is-scheduling-disabled' : ''}" draggable="${schedulingDisabled ? 'false' : 'true'}" ${schedulingDisabled ? 'aria-disabled="true"' : ''} tabindex="0" role="group" aria-label="${escapeHtml(`Vehicle ${displayStockNumber(vehicle) || key}. Press Enter to open job.`)}" data-workshop-vehicle-key="${escapeHtml(key)}" data-workshop-job-vehicle="${escapeHtml(key)}" data-workshop-locate-key="${escapeHtml(key)}" title="${escapeHtml(schedulingDisabled ? disabledExplanation : 'Drag onto a bay, use Best slot, or use Schedule')}">
    ${workshopVehicleIdentitySummaryHtml(vehicle)}
    ${['TINT','TYRE'].includes(stage) ? '<small>Shared '+escapeHtml(stage === 'TINT' ? 'Tint' : 'Tyres')+' work · linked to original job card</small>' : ''}
    <span>${escapeHtml(workshopQueueVehicleDescription(vehicle))}</span>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small class="workshop-estimated-hours-line">Estimated: ${escapeHtml(hoursLabel)}</small>
    ${etaConstraint.required ? `<small class="workshop-eta-line ${etaConstraint.ok ? '' : 'is-invalid'}">${escapeHtml(etaConstraint.ok ? `${etaConstraint.location} · Earliest ETA + 7 booking ${etaConstraint.earliestDateKey} · Best slot from ${etaConstraint.bestSlotEarliestDateKey}` : etaExplanation)}</small>` : ''}
    <small class="workshop-parts-line parts-${escapeHtml(parts.status)}">Parts: ${escapeHtml(parts.text)}</small>
    ${existingBooking ? '<small class="workshop-booked-line">Active booking exists · shown here because the requirement remains outstanding</small>' : ''}

    ${blocked ? '<em>STOPPAGE</em>' : ''}
    ${schedulingDisabled ? `<small class="workshop-scheduling-unavailable-reason">${escapeHtml(disabledExplanation)}</small>` : ''}
    <div class="workshop-queue-actions">

      ${!schedulingDisabled ? `<button class="workshop-schedule-button best-slot" type="button" data-workshop-best-slot-vehicle="${escapeHtml(key)}" data-workshop-best-slot-stage="${escapeHtml(stage)}" data-workshop-best-slot-hours="${escapeHtml(hours)}">Best slot</button>` : ''}
      <button class="workshop-schedule-button" type="button" data-workshop-schedule-vehicle="${escapeHtml(key)}" ${schedulingDisabled ? `disabled title="${escapeHtml(disabledExplanation)}"` : ''}>${existingBooking ? 'Already booked' : schedulingDisabled ? 'Scheduling unavailable' : 'Schedule'}</button>
    </div>
  </article>`;
}

function workshopOutstandingDisabledReasonLabel(reason = '') {
  const messages = {
    location_ineligible: 'Vehicle location is not eligible for Workshop Planner scheduling',
    missing_eta: 'ETA to Kewdale is required before this in-transit vehicle can be scheduled',
    it_eta_missing: 'ETA to Kewdale is required before this in-transit vehicle can be scheduled',
    it_before_eta: 'This in-transit vehicle cannot be scheduled before its ETA to Kewdale',
    active_booking_exists: 'An active booking already represents this requirement',
    estimated_duration_missing: 'Estimated hours are required before this vehicle can be scheduled into a bay',
    vehicle_not_eligible_for_station: 'This vehicle no longer has an outstanding requirement for this department',
  };
  return messages[String(reason || '').trim()] || 'Current shared Workshop authority does not permit this booking';
}

const WORKSHOP_INCREMENTAL_RENDER_BATCH = 12;

function workshopIncrementalRenderRows(rows = [], limit = WORKSHOP_INCREMENTAL_RENDER_BATCH, highlightedVehicleKey = '') {
  const safeRows = Array.isArray(rows) ? rows : [];
  const safeLimit = Math.max(WORKSHOP_INCREMENTAL_RENDER_BATCH, Number(limit) || WORKSHOP_INCREMENTAL_RENDER_BATCH);
  const highlightedIndex = highlightedVehicleKey
    ? safeRows.findIndex(row => vehicleKey(row) === highlightedVehicleKey) : -1;
  // A searched candidate must be rendered before we promise to highlight it.
  // Pin only an off-page match; keep authority, disabled state and totals intact.
  const orderedRows = highlightedIndex >= safeLimit
    ? [safeRows[highlightedIndex], ...safeRows.slice(0, highlightedIndex), ...safeRows.slice(highlightedIndex + 1)]
    : safeRows;
  return {
    visible: orderedRows.slice(0, safeLimit),
    remaining: Math.max(0, safeRows.length - safeLimit),
  };
}

function workshopIncrementalLoadMoreHtml(kind = '', batch = {}) {
  if (!batch.remaining) return '';
  return `<button class="workshop-load-more" type="button" data-workshop-load-more="${escapeHtml(kind)}">Show next ${Math.min(WORKSHOP_INCREMENTAL_RENDER_BATCH, batch.remaining)} · ${batch.remaining} remaining</button>`;
}

function workshopOtherDateCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const date = parseIsoTimestamp(entry.startAt || '');
  return `<button class="workshop-other-date-card" type="button" data-workshop-open-plan="${escapeHtml(entry.id)}" data-workshop-open-date="${escapeHtml(workshopEntryDate(entry))}">
    <strong>${escapeHtml(displayStockNumber(vehicle) || 'No stock')}</strong>
    <span>${escapeHtml(date ? date.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: '2-digit', month: '2-digit' }) : 'Date unknown')} · ${escapeHtml(workshopBayText(entry.stage, entry.bay))}</span>
  </button>`;
}

// r569 (F183): other unstarted jobs on this station, for a different vehicle.
// A queued row is already stored as planned on the planner chip.
function workshopPauseForOtherChoices(live, rows) {
  const status = String(live?.status || '').toLowerCase();
  if (!live || !['started', 'stoppage'].includes(status)) return [];
  const stage = typeof normalizePmbStage === 'function' ? normalizePmbStage(live.stage) : '';
  const vehicle = String(live.sharedVehicleId || '');
  if (!stage || !vehicle) return [];
  return (Array.isArray(rows) ? rows : []).filter(row => {
    if (!row || row.id === live.id) return false;
    const rowStatus = String(row.status || '').toLowerCase();
    if (!['planned', 'queued'].includes(rowStatus)) return false;
    const rowStage = typeof normalizePmbStage === 'function' ? normalizePmbStage(row.stage) : '';
    if (rowStage !== stage) return false;
    if (!row.sharedVehicleId || row.sharedVehicleId === vehicle) return false;
    if (!row.sharedBookingId) return false;
    return true;
  }).slice(0, 8);
}

function workshopPlanLifecycleActionsHtml(entry = {}) {
  const planId = String(entry.id || '');
  const status = String(entry.status || 'planned').toLowerCase();
  if (!planId || ['completed', 'cancelled'].includes(status)) return '';
  if (entry.legacyAmbiguityReason) return `<div class="workshop-legacy-ambiguity" role="status" title="${escapeHtml(entry.legacyAmbiguityReason)}">Legacy review required · editing blocked</div>`;
  const pauseButton = `<button type="button" data-workshop-pause-for-other="${escapeHtml(planId)}" aria-label="Pause this job and start another in this bay">Pause for another job</button>`;
  if (status === 'stoppage') {
    return `<div class="workshop-plan-lifecycle-actions"><button type="button" data-workshop-resume-plan="${escapeHtml(planId)}" aria-label="Resume job">Resume job</button>${pauseButton}<button class="workshop-complete-action" type="button" data-workshop-complete-plan="${escapeHtml(planId)}" aria-label="Complete job">Complete</button></div>`;
  }
  if (status === 'started') {
    return `<div class="workshop-plan-lifecycle-actions"><button type="button" data-workshop-stop-plan="${escapeHtml(planId)}" aria-label="Place job on STOPPAGE">STOPPAGE</button>${pauseButton}<button class="workshop-complete-action" type="button" data-workshop-complete-plan="${escapeHtml(planId)}" aria-label="Complete job">Complete</button></div>`;
  }
  const pending = WORKSHOP_PENDING_STARTS.has(planId);
  return `<div class="workshop-plan-lifecycle-actions"><button type="button" data-workshop-start-plan="${escapeHtml(planId)}" aria-label="${pending ? 'Starting job' : 'Start job'}" ${pending ? 'disabled aria-busy="true"' : ''}>${pending ? 'Starting…' : 'Start job'}</button></div>`;
}

// r493 (F106): a started job whose bay is outside its working time right now
// (break, end of day, weekend, holiday or closure) is shown as Paused in amber,
// matching the fitter job clock, which does not count that time. Display only.
function workshopEntryPausedNow(entry = {}, now = new Date()) {
  if (String(entry?.status || '').toLowerCase() !== 'started') return false;
  try {
    const stage = String(entry.stage || '').toUpperCase();
    // Same Bus bay shift as the planner's Closed shading (6 am - 3 pm, bays 8 / 9 to 2 pm).
    const context = stage === 'BUS_4X4' ? { stage, bay: Number(entry.bay), busCalendarVersion: 1 } : null;
    const minute = workshopMinuteOfDay(now);
    return !workshopAvailabilityWindowsForDate(new Date(now), context).some(window => minute >= window.startMinutes && minute < window.endMinutes);
  } catch (_) { return false; }
}

function workshopPlanChipHtml(entry = {}, dateKey = '', rows = workshopLoadPlans(), visibleSegment = null) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const segment = visibleSegment || workshopEntrySegmentForDate(entry, dateKey);
  if (!segment) return '';
  const left = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const width = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const started = String(entry.status || '').toLowerCase() === 'started';
  const pausedNow = started && typeof workshopEntryPausedNow === 'function' && workshopEntryPausedNow(entry);
  const blocked = isPdcBlocked(vehicle);
  const overtime = workshopEntryIsOvertime(entry);
  const assigneeConflict = workshopEntryHasAssigneeConflict(entry, rows);
  const selected = workshopState().selectedPlanId === entry.id;
  const highlighted = workshopState().searchHighlightPlanId
    ? workshopState().searchHighlightPlanId === entry.id
    : workshopState().highlightVehicleKey === entry.vehicleKey;
  const parts = workshopPartsSummary(vehicle);
  const etaRisk = workshopEtaRiskForEntry(entry, vehicle);
  const etaRiskLabel = workshopEtaRiskLabel(etaRisk);
  const draggable = entry.status !== 'completed' && !entry.legacyAmbiguityReason;
  const savedTechnician = cleanNavisionText(entry.assignee || '')
    || (typeof workshopTechnicianNameById === 'function' ? workshopTechnicianNameById(entry.technicianId) : '');
  const assignee = savedTechnician || workshopBayMechanic(entry.stage, entry.bay) || '';
  const statusLabel = entry.status === 'completed' ? 'COMPLETED' : entry.status === 'stoppage' ? 'STOPPAGE' : entry.status === 'started' ? (pausedNow ? 'PAUSED' : 'LIVE') : 'PLANNED';
  const lifecycleActionsHtml = workshopPlanLifecycleActionsHtml(entry);
  const classes = [blocked ? 'is-blocked' : '', started ? 'is-started' : '', pausedNow ? 'is-paused' : '', overtime ? 'is-overtime' : '', etaRisk ? 'is-eta-risk' : '', segment.usesConfiguredOvertime ? 'uses-configured-overtime' : '', segment.historicalOnClosure ? 'historical-on-closure' : '', assigneeConflict ? 'has-assignee-conflict' : '', entry.status === 'stoppage' ? 'is-stoppage' : '', lifecycleActionsHtml ? 'has-lifecycle-actions' : '', selected ? 'is-selected' : '', highlighted ? 'is-search-match' : '', segment.continuesFromPrevious ? 'continues-from-previous' : '', segment.continuesNext ? 'continues-next' : ''].filter(Boolean).join(' ');
  const conflictNote = assigneeConflict ? ` · WARNING: ${entry.assignee} is booked on another vehicle at this time` : '';
  const timeLabel = workshopEntryTimeLabel(entry);
  return `<article class="workshop-plan-chip ${classes}" ${draggable ? 'draggable="true"' : ''} data-workshop-plan-id="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}" style="--plan-left:${left}%;--plan-width:${width}%;" title="${escapeHtml(`${timeLabel} · ${entry.hours}h total${conflictNote} · double-click to open the vehicle${entry.status === 'completed' ? ' · completed history stays fixed' : entry.status === 'planned' ? ' · drag to reschedule' : ' · drag to move this live job safely'}`)}">
    <button class="workshop-plan-main" type="button" data-workshop-select-plan="${escapeHtml(entry.id)}">
      <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')} · ${escapeHtml(displayStockNumber(vehicle) || 'No stock')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
      <small class="workshop-plan-customer">${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</small>
      ${entry.workCategory ? `<small class="workshop-plan-category">${escapeHtml(window.PDC_WORKSHOP_DEPARTMENTS?.categoryLabel(entry.workCategory) || entry.workCategory)}</small>` : ''}
      ${entry.helperAssignments?.length ? `<small class="workshop-plan-team">${escapeHtml(workshopBookingTeamLabel(entry))}</small>` : ''}
      <small>${escapeHtml(`${statusLabel}${assignee ? ` · ${assignee}` : ''}${overtime ? ' · OVERTIME' : ''}${segment.usesConfiguredOvertime ? ' · CONFIGURED OVERTIME' : ''}${segment.historicalOnClosure ? ' · HISTORICAL CLOSURE' : ''}`)}</small>
      ${entry.legacyAmbiguityReason ? `<small class="workshop-legacy-ambiguity">${escapeHtml(entry.legacyAmbiguityReason)}</small>` : ''}
      <small class="workshop-plan-time">${escapeHtml(`${timeLabel} · ${workshopDurationInputValue(entry.hours)} h`)}</small>
      ${workshopStageJobLines(vehicle,entry.stage).some(line=>line.hoursProvenance==='ai_estimated')?'<small class="pdc-ai-estimate pdc-ai-estimate-badge">Includes AI estimate</small>':''}
      <small class="workshop-plan-hours">${escapeHtml(`Parts ${parts.label}${parts.eta && !['issued', 'notrequired'].includes(parts.status) ? ` · ETA ${parts.eta}` : ''}`)}</small>
      ${etaRiskLabel ? `<small class="workshop-eta-risk-label">${escapeHtml(etaRiskLabel)}</small>` : ''}
    </button>
    ${lifecycleActionsHtml}
    ${window.PdcFitters?.progressHtml(entry.fitterProgress, true, { resettable: true, paused: entry.status === 'stoppage' ? 'Stoppage' : pausedNow ? 'Outside working time' : '' }) || ''}
    ${entry.legacyAmbiguityReason ? '' : `<span class="workshop-plan-resize" data-workshop-resize-plan="${escapeHtml(entry.id)}" title="Drag to change duration"></span>`}
  </article>`;
}


function workshopTimeAxisHtml() {
  const tickCount = Math.floor(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / 60);
  return Array.from({ length: tickCount + 1 }, (_, index) => {
    const left = ((index * 60) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    return `<span style="left:${left}%">${escapeHtml(workshopTimeLabelFromMinutes(index * 60))}</span>`;
  }).join('');
}

function workshopTimelineCssVariables() {
  const dayLength = Math.max(60, Number(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) || 60);
  const halfHourWidth = ((30 / dayLength) * 100).toFixed(6);
  const hourWidth = ((60 / dayLength) * 100).toFixed(6);
  return `--workshop-half-hour-width:${halfHourWidth}%;--workshop-hour-width:${hourWidth}%;`;
}

function workshopDropPreviewHtml({ vertical = false } = {}) {
  return `<div class="workshop-drop-preview${vertical ? ' is-vertical' : ''}" hidden aria-hidden="true"><span class="workshop-drop-preview-line"></span><span class="workshop-drop-preview-pill"></span></div>`;
}

function workshopUnavailableTimeHtml(dateKey = '', { vertical = false, stage = '', bay = 0 } = {}) {
  // Physical Bus bay shading uses the established bay shift, independently of
  // a booking's department/history. This is display-only calendar context.
  const calendarContext = stage === 'BUS_4X4' ? { stage, bay, busCalendarVersion: 1 } : null;
  const closed = workshopSubtractWindows([
    { startMinutes: WORKSHOP_PLANNER_CONFIG.dayStartMinutes, endMinutes: WORKSHOP_PLANNER_CONFIG.dayEndMinutes },
  ], workshopAvailabilityWindowsForDate(dateKey, calendarContext));
  return closed.map(window => {
    const start = window.startMinutes - WORKSHOP_PLANNER_CONFIG.dayStartMinutes;
    const end = window.endMinutes - WORKSHOP_PLANNER_CONFIG.dayStartMinutes;
    const label = `Closed ${workshopTimeLabelFromMinutes(start)}–${workshopTimeLabelFromMinutes(end)}`;
    return `<div class="workshop-closed-time${vertical ? ' is-vertical' : ''}" style="--closed-start:${(start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%;--closed-size:${((end - start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%;" aria-label="${escapeHtml(label)}"><span>Closed</span></div>`;
  }).join('');
}


function workshopDepartmentLayout() {
  return typeof window === 'object' ? window.PDC_WORKSHOP_DEPARTMENTS : null;
}
// r450 (F63): a whole-job booking (BUS_WHOLE_JOB) holds every unbooked Bus
// line for one technician. In a category view it shows by bay (like an old
// whole-job booking), because it holds work from several categories; the
// filters below test entry.workCategory !== 'BUS_WHOLE_JOB' inline.
function workshopCategoryAuthority(authority, stage) {
  if (!authority || stage !== 'BUS_4X4') return authority;
  const layout = workshopDepartmentLayout();
  const routeCategory = typeof app === 'object' ? layout?.categoryForView?.(app.currentRequestedView) : null;
  return layout?.selectedCategory(authority, routeCategory?.code || layout.category(workshopState().busBayGroup)?.code || 'BUS_MECHANICAL') || authority;
}
function workshopSelectedBusGroup() {
  const layout = workshopDepartmentLayout();
  if (!layout) return null;
  const state = workshopState();
  // The route owns station scope, including after search, detail jumps and refresh.
  const routeCategory = typeof app === 'object' ? layout.categoryForView?.(app.currentRequestedView) : null;
  if (routeCategory && !routeCategory.external) return routeCategory;
  return state.focusedBookingMode || state.busShowAllBays ? null : layout.category(state.busBayGroup);
}
// r399: a booking may only be offered bays its Bus 4x4 work category accepts.
// In the all-bays view workshopVisibleBays() lists every bay, so a Mechanical
// card was offered Bay 8 and the database refused it.
// r417 (F32): Best slot and the default bay still use these bays. The Schedule
// bay list also shows the other visible bays; choosing one asks the planner to
// confirm (server warning bay_rule_warning) and the override is logged.
// r447 (F60): the category's own bays come first, then the overflow Bays 5-6
// (no warning either), so the default bay is always one of its own bays.
function workshopCategoryBays(stage, workCategory = '') {
  const visible = workshopVisibleBays(stage);
  if (stage !== 'BUS_4X4' || !workCategory) return visible;
  const layout = workshopDepartmentLayout();
  const allowed = layout?.allowedBays?.(workCategory);
  if (!Array.isArray(allowed)) return visible;
  const own = layout?.preferredBays?.(workCategory) || allowed;
  const free = visible.filter(number => allowed.includes(Number(number)));
  return [...free.filter(number => own.includes(Number(number))), ...free.filter(number => !own.includes(Number(number)))];
}
// r447 (F60): Best slot only offers the category's own bays (never the
// overflow Bays 5-6), the same bays Book all stations uses on the server.
function workshopCategoryOwnBays(stage, workCategory = '') {
  const bays = workshopCategoryBays(stage, workCategory);
  if (stage !== 'BUS_4X4' || !workCategory) return bays;
  const own = workshopDepartmentLayout()?.preferredBays?.(workCategory);
  return Array.isArray(own) ? bays.filter(number => own.includes(Number(number))) : bays;
}

// r417 (F32): dropping a vehicle on a bay that is another outstanding
// category's own bay books that category (Bay 8 -> Electrical), so a job whose
// Mechanical work is booked or done goes in without a warning.
function workshopBayAwareCategory(candidate = {}, stageCode = '', bayNumber = 0) {
  const layout = workshopDepartmentLayout();
  const current = String(candidate.workCategory || '');
  if (stageCode !== 'BUS_4X4' || !current || !layout?.category) return null;
  const bay = Number(bayNumber);
  const allowed = layout.allowedBays?.(current);
  if (!Array.isArray(allowed) || allowed.includes(bay)) return null;
  const rows = Array.isArray(candidate.workCategories) ? candidate.workCategories : [];
  for (const row of rows) {
    const code = String(row?.work_category || '');
    const own = layout.category(code);
    const hours = Number(row?.estimated_hours);
    if (!own || own.external || code === current || !own.bays.includes(bay)) continue;
    if (row.completed === true || row.existing_booking === true || row.schedule_enabled !== true || !(hours > 0)) continue;
    return { code, label: own.label, minutes: Math.round(hours * 60) };
  }
  return null;
}
function workshopVisibleBays(stage) {
  const selected = stage === 'BUS_4X4' ? workshopSelectedBusGroup() : null;
  return selected ? [...selected.bays] : Array.from({length:workshopStageBayCount(stage)},(_,i)=>i+1);
}
function workshopBayStoredName(stage, bay) {
  // Extracted tests may omit workshopSharedBayRef. Prefer the local binding when present.
  let sharedRef = null;
  try { if (typeof workshopSharedBayRef === 'function') sharedRef = workshopSharedBayRef; } catch (_error) { sharedRef = null; }
  if (!sharedRef && typeof globalThis.workshopSharedBayRef === 'function') sharedRef = globalThis.workshopSharedBayRef;
  return sharedRef ? String(sharedRef(stage, bay)?.display_name || '').trim() : '';
}
function workshopBayChoiceLabel(stage,bay) {
  // r549 (F163): the saved display name is the on-screen label. The station plus
  // padded bay number stays the fallback when that name is blank.
  let sharedRef = null;
  try { if (typeof workshopSharedBayRef === 'function') sharedRef = workshopSharedBayRef; } catch (_error) { sharedRef = null; }
  if (!sharedRef && typeof globalThis.workshopSharedBayRef === 'function') sharedRef = globalThis.workshopSharedBayRef;
  const stored = sharedRef ? String(sharedRef(stage, bay)?.display_name || '').trim() : '';
  if (stored) return stored;
  return workshopDepartmentLayout()?.bayLabel(stage,bay) || 'Bay '+workshopPad(bay);
}
// r483 (F96): a Dept 139 bay reads with Craig's name and number ('Fitting · Bay 06');
// every other station (Bus 4x4, shared Tint / Tyre) keeps its plain 'Bay N' text.
// r549: a saved display_name wins over that text.
function workshopBayText(stage = '', bay = '', pad = false) {
  // r548 (F162): bay 0 is a missing bay_id. It reads Unallocated, never Bay 00.
  const number = Number(bay);
  if (!Number.isInteger(number) || number < 1) return 'Unallocated';
  // r549 (F163): a saved display_name wins over the layout label.
  let sharedRef = null;
  try { if (typeof workshopSharedBayRef === 'function') sharedRef = workshopSharedBayRef; } catch (_error) { sharedRef = null; }
  if (!sharedRef && typeof globalThis.workshopSharedBayRef === 'function') sharedRef = globalThis.workshopSharedBayRef;
  const stored = sharedRef ? String(sharedRef(stage, number)?.display_name || '').trim() : '';
  if (stored) return stored;
  const layout = typeof workshopDepartmentLayout === 'function' ? workshopDepartmentLayout() : null;
  let stageCode = '';
  try { if (typeof normalizePmbStage === 'function') stageCode = normalizePmbStage(stage); } catch (_error) { stageCode = ''; }
  if (!stageCode && typeof globalThis.normalizePmbStage === 'function') stageCode = globalThis.normalizePmbStage(stage);
  if (!stageCode) stageCode = String(stage || '').trim().toUpperCase();
  const named = layout?.pmbBayLabel?.(stageCode, number);
  return named || `Bay ${pad ? workshopPad(number) : number}`;
}
let workshopBayRenameOpen = '';
function workshopBayRenameButton(stage, bay, label) {
  if (typeof workshopAdministratorCanMove !== 'function' || !workshopAdministratorCanMove()) return '';
  return `<button type="button" class="workshop-bay-rename" data-workshop-bay-rename-stage="${escapeHtml(stage)}" data-workshop-bay-rename-bay="${bay}" aria-label="Rename ${escapeHtml(label)}" title="Rename this bay">✎</button>`;
}
function workshopBayRenameForm(stage, bay, label) {
  return `<form class="workshop-bay-rename-form" data-workshop-bay-rename-form data-workshop-bay-rename-stage="${escapeHtml(stage)}" data-workshop-bay-rename-bay="${bay}"><input type="text" maxlength="40" value="${escapeHtml(label)}" data-workshop-bay-rename-input aria-label="Bay name on screen"><button type="submit">Save</button><button type="button" data-workshop-bay-rename-cancel>Cancel</button></form>`;
}
async function workshopSaveBayDisplayName(stage, bay, raw) {
  const name = String(raw || '').trim();
  if (name.length > 40) {
    workshopNotify('A bay name can be up to 40 characters. Leave it blank to use the standard name.');
    return;
  }
  const ref = typeof workshopSharedBayRef === 'function' ? workshopSharedBayRef(stage, bay) : null;
  const service = typeof window !== 'undefined' ? window.__workshopReferenceDataService : null;
  if (!ref?.id || typeof service?.setWorkshopBayDisplayName !== 'function') {
    workshopNotify('This bay name cannot be saved until the bay list has loaded.');
    return;
  }
  const result = await service.setWorkshopBayDisplayName(ref.id, ref.version, name);
  if (!result || result.ok !== true) {
    workshopNotify(result?.error === 'version_conflict' ? 'This bay changed in another window. The planner has the latest name.' : 'The bay name was not saved.');
    return;
  }
  workshopBayRenameOpen = '';
  const saved = String(result.bay?.display_name || name || workshopBayChoiceLabel(stage, bay)).trim();
  workshopNotify(`${saved || 'The bay'} is now the name on screen. The bay number is unchanged.`, 'info');
  renderWorkshopPlanner();
}
function workshopBayRowsHtml(stage = '', dateKey = '', rows = []) {
  const count = workshopStageBayCount(stage);
  // Reuse calculations within this render only, so live timing and reference changes
  // are still recomputed on the next render without a cross-snapshot cache.
  const plansByBay = new Map();
  const blocksByBay = new Map();
  for (const entry of rows) {
    const bay = Number(entry.bay);
    if (entry.stage !== stage || !Number.isInteger(bay) || bay < 1 || bay > count || entry.status === 'completed') continue;
    const segment = workshopEntrySegmentForDate(entry, dateKey);
    if (!segment) continue;
    if (!plansByBay.has(bay)) plansByBay.set(bay, []);
    plansByBay.get(bay).push({ entry, segment });
  }
  for (const block of count > 0 ? workshopLoadAdminBlocks() : []) {
    const bay = Number(block.bay);
    if (block.stage !== stage || !Number.isInteger(bay) || bay < 1 || bay > count || !workshopAdminBlockSegment(block, dateKey)) continue;
    if (!blocksByBay.has(bay)) blocksByBay.set(bay, []);
    blocksByBay.get(bay).push(block);
  }
  const unavailableByCalendar = new Map();
  return workshopVisibleBays(stage).map(bay => {
    const calendarKey = stage === 'BUS_4X4' ? ([8, 9].includes(bay) ? 'bus-short' : 'bus-standard') : 'shared';
    if (!unavailableByCalendar.has(calendarKey)) unavailableByCalendar.set(calendarKey, workshopUnavailableTimeHtml(dateKey, { stage, bay }));
    const unavailableHtml = unavailableByCalendar.get(calendarKey);
    const plans = (plansByBay.get(bay) || [])
      .sort((a, b) => String(a.entry.startAt).localeCompare(String(b.entry.startAt)));
    const defaultAssignee = workshopBayMechanic(stage, bay);
    const adminBlocks = blocksByBay.get(bay) || [];
    const bayLabel = workshopBayChoiceLabel(stage,bay);
    const assigneeLabel = 'Bay mechanic';
    const renameOpen = typeof workshopBayRenameOpen === 'string' && workshopBayRenameOpen === `${stage}:${bay}` && typeof workshopBayRenameForm === 'function';
    const bayHeading = renameOpen
      ? workshopBayRenameForm(stage, bay, bayLabel)
      : `<strong>${escapeHtml(bayLabel)}</strong>${typeof workshopBayRenameButton === 'function' ? workshopBayRenameButton(stage, bay, bayLabel) : ''}`;
    return `<div class="workshop-bay-row">
      <div class="workshop-bay-label"><div class="workshop-bay-label-heading">${bayHeading}<button type="button" data-workshop-weekly-stage="${escapeHtml(stage)}" data-workshop-weekly-bay="${bay}">Week</button></div><span>${escapeHtml(stage === 'TYRE' && bay === 2 ? 'Wheel alignment' : plans.length ? `${plans.length} planned` : 'Available')}</span><label><small>${escapeHtml(assigneeLabel)}</small><select data-workshop-bay-mechanic-stage="${escapeHtml(stage)}" data-workshop-bay-mechanic-number="${bay}"${WORKSHOP_PENDING_BAY_ASSIGNMENTS.has(`${stage}:${bay}`) ? ' disabled aria-busy="true"' : ''}>${workshopAssigneeOptions(stage, defaultAssignee)}</select></label></div>
      <div class="workshop-bay-lane" data-workshop-drop-bay="${bay}" data-workshop-drop-stage="${escapeHtml(stage)}">
        ${unavailableHtml}
        ${workshopDropPreviewHtml()}
        ${adminBlocks.map(block => workshopAdminBlockHtml(block, dateKey)).join('')}
        ${plans.map(({ entry, segment }) => workshopPlanChipHtml(entry, dateKey, rows, segment)).join('')}
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
  return workshopMechanicOptions(selected);
}

function workshopCurrentDragPreview() {
  return app.workshopDragPreview || null;
}

function workshopSetDragPreview(preview = null) {
  if (!preview) workshopCancelLanePreviewFrame();
  app.workshopDragPreview = preview || null;
}

let workshopLanePreviewFrame = null;
let workshopPendingLanePreview = null;
const workshopLanePreviewPaints = new WeakMap();

function workshopCancelLanePreviewFrame(lane = null) {
  if (lane && workshopPendingLanePreview?.lane !== lane) return;
  if (workshopLanePreviewFrame !== null) window.cancelAnimationFrame?.(workshopLanePreviewFrame);
  workshopLanePreviewFrame = null;
  workshopPendingLanePreview = null;
}

function workshopPaintLanePointer(lane, clientX, clientY, vertical = false) {
  if (!lane || lane.isConnected === false) return;
  // Read the current geometry at paint/drop time: horizontal and page scrolling
  // may move the lane during a drag, so a drag-start rectangle is not safe.
  const rect = lane.getBoundingClientRect();
  const position = vertical ? clientY - rect.top : clientX - rect.left;
  const extent = vertical ? rect.height : rect.width;
  const minutes = workshopClampStartMinutes((position / Math.max(1, extent)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
  workshopUpdateLanePreview(lane, minutes);
}

function workshopQueueLanePreview(lane, event, vertical = false) {
  workshopPendingLanePreview = { lane, clientX: event.clientX, clientY: event.clientY, vertical };
  if (workshopLanePreviewFrame !== null) return;
  if (typeof window.requestAnimationFrame !== 'function') {
    workshopFlushLanePreview(lane, event, vertical);
    return;
  }
  workshopLanePreviewFrame = window.requestAnimationFrame(() => {
    const pending = workshopPendingLanePreview;
    workshopLanePreviewFrame = null;
    workshopPendingLanePreview = null;
    if (pending) workshopPaintLanePointer(pending.lane, pending.clientX, pending.clientY, pending.vertical);
  });
}

function workshopFlushLanePreview(lane, event, vertical = false) {
  workshopCancelLanePreviewFrame();
  // A release can arrive before the next animation frame or at a new position.
  // Resolve that final position synchronously before the existing save checks.
  workshopPaintLanePointer(lane, event.clientX, event.clientY, vertical);
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
  if (!workshopPendingLanePreview || scope === document || scope === workshopPendingLanePreview.lane || scope.contains?.(workshopPendingLanePreview.lane)) workshopCancelLanePreviewFrame();
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
  workshopCancelLanePreviewFrame(lane);
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
  const safeMinutes = workshopClampStartMinutes(startMinutes);
  const stage = lane.dataset.workshopDropStage || lane.dataset.workshopWeekDropStage || '';
  const bay = Number(lane.dataset.workshopDropBay || lane.dataset.workshopWeekDropBay || 0);
  const baseHours = Number(dragPreview?.hours || workshopDefaultBookingHours());
  const allocatedHours = dragPreview?.type === 'queue'
    ? workshopBayAllocatedHours(stage, bay, baseHours)
    : dragPreview?.type === 'plan' && dragPreview.entry
      ? workshopBookingDestinationHours(dragPreview.entry, stage, bay, baseHours)
      : baseHours;
  if (!(allocatedHours > 0)) { preview.hidden = true; return; }
  const hours = Math.max(1 / 60, allocatedHours);
  const dateKey = lane.dataset.workshopWeekDropDate || workshopState().date;
  if (lane.dataset.workshopRequestedStartMinutes !== String(safeMinutes)) lane.dataset.workshopRequestedStartMinutes = String(safeMinutes);
  workshopSetDropTarget({ stage, bay, dateKey, startMinutes: safeMinutes });
  const paintKey = `${safeMinutes}:${hours}:${WORKSHOP_PLANNER_CONFIG.dayLengthMinutes}`;
  const previousPaint = workshopLanePreviewPaints.get(lane);
  if (!preview.hidden && previousPaint?.preview === preview && previousPaint.key === paintKey) return;
  workshopLanePreviewPaints.set(lane, { preview, key: paintKey });
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

function workshopFocusedOperationLinesHtml(vehicle = {}, stage = '') {
  const lines = workshopStageJobLines(vehicle, stage).filter(line => line.source === 'authenticated-operation-line');
  const exactTotalMinutes = lines.reduce((sum, line) => sum + Math.round(Number(line.hours || 0) * 60), 0);
  const exactTotal = exactTotalMinutes / 60;
  return `<section class="workshop-focused-operation-lines" aria-label="Authenticated operation lines"><strong>Authenticated operation lines · ${exactTotal.toFixed(2)} h exact (${exactTotalMinutes} min)</strong><ul>${lines.map(line => `<li><span>${escapeHtml(line.operationNo || 'Operation')}</span> ${escapeHtml(line.text)} <b class="${line.hoursProvenance==='ai_estimated'?'pdc-ai-estimate':''}">${line.hoursProvenance==='ai_estimated'?'AI estimate · ':''}${Number(line.hours || 0).toFixed(2)} h</b></li>`).join('')}</ul></section>`;
}

function workshopTeamRoster() {
  const rows = window.__workshopReferenceDataService?.getCachedTechnicians?.()?.rows;
  return (Array.isArray(rows) ? rows : []).filter(row => row.active !== false && WORKSHOP_UUID_PATTERN.test(String(row.id || '')))
    .map(row => ({id:String(row.id),name:String(row.name || '')})).sort((a,b) => a.name.localeCompare(b.name));
}

function workshopHelperLabourTechnicians(entry = {}) {
  return [...new Map([...(entry.helperAssignmentHistory || []), ...(entry.helperAssignments || [])]
    .filter(row => row.technicianId).map(row => [row.technicianId, row])).values()];
}

function workshopHelperLabourHtml(entry = {}) {
  const helpers = workshopHelperLabourTechnicians(entry);
  if (!entry.actualStartAt || !helpers.length || !['started','stoppage','completed','queued'].includes(entry.status)) return '';
  const history = Array.isArray(entry.helperLabour) ? entry.helperLabour : [];
  const pending = workshopState().helperLabourPending;
  const retry = pending?.payload?.bookingId === entry.sharedBookingId ? pending.payload : null;
  const workedAt = retry?.workedAt || entry.actualEndAt || new Date().toISOString();
  const localTime = new Date(Date.parse(workedAt) + 8 * 3600000).toISOString().slice(0,16);
  const canManage = ['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const disabled = canManage && window.__workshopSharedActions?.recordHelperLabour ? '' : 'disabled';
  return `<form class="workshop-booking-team" data-workshop-helper-labour-form data-workshop-booking-id="${escapeHtml(entry.sharedBookingId)}" data-workshop-booking-version="${escapeHtml(entry.sharedVersion)}">
    <strong>Record helper time</strong><p>Actual helper labour: ${escapeHtml(Number(entry.helperLabourMinutes || 0))} minutes. This adds person-minutes separately and does not change the booking’s planned hours or elapsed job time.</p>
    ${history.length ? `<ul>${history.map(row => `<li>${escapeHtml(row.technician_name || 'Helper')}: ${escapeHtml(row.minutes)} minutes · ${escapeHtml(row.note || '')}</li>`).join('')}</ul>` : ''}
    <label><span>Helper technician</span><select name="helperTechnicianId" required ${disabled}>${helpers.map(row => `<option value="${escapeHtml(row.technicianId)}" ${row.technicianId === retry?.technicianId ? 'selected' : ''}>${escapeHtml(row.name || 'Assigned helper')}</option>`).join('')}</select></label>
    <label><span>Actual work date/time (Perth)</span><input type="datetime-local" name="helperWorkedAt" value="${escapeHtml(localTime)}" required ${disabled}></label>
    <label><span>Actual minutes worked</span><input type="number" name="helperMinutes" min="1" max="720" step="1" value="${escapeHtml(retry?.minutes || '')}" required ${disabled}></label>
    <label><span>Work performed / training note</span><input name="helperNote" maxlength="500" value="${escapeHtml(retry?.note || '')}" required ${disabled}></label>
    ${retry ? '<p role="status">The previous save could not be confirmed. Retry these same values to check that receipt without recording time twice.</p>' : ''}
    <button class="primary" type="submit" ${disabled}>${retry ? 'Retry helper time save' : 'Record helper time'}</button>
    ${canManage ? '' : '<p>Ask a controller to record actual helper time.</p>'}
  </form>`;
}

async function saveWorkshopHelperLabour(event) {
  event.preventDefault();
  if (!['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role)) return false;
  const state = workshopState();
  if (state.helperLabourSaving) return false;
  const form = event.currentTarget;
  const bookingId = String(form.dataset.workshopBookingId || '');
  const entry = workshopLoadPlans().find(row => row.sharedBookingId === bookingId);
  if (!entry || entry.stage !== 'BUS_4X4' || !entry.actualStartAt || !['started','stoppage','completed','queued'].includes(entry.status)) return false;
  const data = new FormData(form);
  const technicianId = String(data.get('helperTechnicianId') || '');
  const minutes = Number(data.get('helperMinutes'));
  const note = String(data.get('helperNote') || '').trim();
  const localTime = String(data.get('helperWorkedAt') || '');
  const date = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(localTime) ? new Date(localTime + ':00+08:00') : null;
  if (!workshopHelperLabourTechnicians(entry).some(row => row.technicianId === technicianId) || !Number.isInteger(minutes) || minutes < 1 || minutes > 720 || !note || !date || Number.isNaN(date.getTime())) {
    workshopNotify('Choose an assigned helper, a valid Perth work time, 1–720 actual minutes and a work note.'); return false;
  }
  const owner = `${window.PDC_AUTH_CONTEXT?.userId || ''}:${window.PDC_AUTH_CONTEXT?.role || ''}`;
  const intent = JSON.stringify({bookingId,technicianId,workedAt:date.toISOString(),minutes,note});
  const pending = state.helperLabourPending;
  if (pending && (pending.owner !== owner || pending.intent !== intent)) {
    workshopNotify('A previous helper-time save is unconfirmed. Refresh and resolve that save before recording different time.'); return false;
  }
  if (!pending && String(entry.sharedVersion) !== form.dataset.workshopBookingVersion) {
    workshopNotify('This booking changed. Review its recorded helper time before saving again.'); renderWorkshopPlanner(); return false;
  }
  const payload = pending?.payload || {bookingId,expectedVersion:entry.sharedVersion,technicianId,workedAt:date.toISOString(),minutes,note,requestId:workshopNewRequestId()};
  state.helperLabourPending = {owner,intent,payload};
  state.helperLabourSaving = true;
  let result;
  try { result = await workshopDispatchSharedAction('recordHelperLabour', payload, renderWorkshopPlanner, {suppressRender:true}); }
  finally { state.helperLabourSaving = false; }
  const uncertain = !result || result.outcomeUnknown === true || ['runtime_failure','request_failed','no_response','authority_superseded'].includes(result.error);
  if (!uncertain) state.helperLabourPending = null;
  renderWorkshopPlanner();
  return result?.ok === true;
}

function workshopBookingTeamHtml(entry = {}) {
  const department138 = entry.busWorkflowDepartment138 === true || entry.busCalendarVersion === 1 || workshopBusShift(entry);
  if (entry.stage !== 'BUS_4X4' || !department138 || !workshopSharedModeActive() || !WORKSHOP_UUID_PATTERN.test(String(entry.sharedBookingId || ''))) return '';
  const helpers = Array.isArray(entry.helperAssignments) ? entry.helperAssignments : [];
  const summary = workshopBookingTeamLabel(entry) || 'No technicians assigned';
  if (['completed','deleted','cancelled'].includes(entry.status) || !entry.bay) return `<section class="workshop-booking-team"><strong>Team on this booking</strong><p>${escapeHtml(summary)}</p></section>${workshopHelperLabourHtml(entry)}`;
  const roster = workshopTeamRoster();
  const knownIds = new Set(roster.map(row => row.id));
  const recorded = [...(entry.technicianId && !knownIds.has(entry.technicianId) ? [{id:entry.technicianId,name:entry.assignee || 'Recorded primary'}] : []), ...helpers.filter(row => !knownIds.has(row.technicianId)).map(row => ({id:row.technicianId,name:row.name || 'Recorded helper'}))];
  const options = [...roster, ...recorded];
  const helperIds = new Set(helpers.map(row => row.technicianId));
  const canManage = ['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const disabled = canManage && roster.length && window.__workshopSharedActions?.setBookingTeam ? '' : 'disabled';
  return `<form class="workshop-booking-team" data-workshop-team-form data-workshop-booking-id="${escapeHtml(entry.sharedBookingId)}" data-workshop-booking-version="${escapeHtml(entry.sharedVersion)}">
    <strong>Team on this booking · ${escapeHtml((() => { try { if (typeof workshopBayChoiceLabel === 'function') return workshopBayChoiceLabel(entry.stage, entry.bay); } catch (_error) {} return typeof globalThis.workshopBayChoiceLabel === 'function' ? globalThis.workshopBayChoiceLabel(entry.stage, entry.bay) : ('Bay ' + entry.bay); })())}</strong>
    <p>Keep the vehicle in its one physical bay. Add technicians working together here; their other bookings and leave are checked. Planned hours stay unchanged. Record each helper’s actual labour separately.</p>
    <label><span>Primary technician</span><select name="primaryTechnicianId" required ${disabled}><option value="">Choose primary technician</option>${options.map(row => `<option value="${escapeHtml(row.id)}" ${row.id === entry.technicianId ? 'selected' : ''}>${escapeHtml(row.name)}${knownIds.has(row.id) ? '' : ' (unavailable — choose an active technician)'}</option>`).join('')}</select></label>
    <fieldset ${disabled}><legend>Helpers / training team</legend>${options.map(row => `<label class="workshop-team-choice"><input type="checkbox" name="helperTechnicianIds" value="${escapeHtml(row.id)}" ${helperIds.has(row.id) ? 'checked' : ''}>${escapeHtml(row.name)}${knownIds.has(row.id) ? '' : ' (unavailable)'}</label>`).join('')}</fieldset>
    <label><span>Team note (optional)</span><input name="teamNote" maxlength="500" placeholder="For example: completing mechanical training together" ${disabled}></label>
    <button class="primary" type="submit" ${disabled}>Save team</button>${!canManage ? '<p>Ask a controller to change the team.</p>' : disabled ? '<p role="status">The active technician roster or team action is unavailable. Refresh before changing the team.</p>' : ''}
  </form>${workshopHelperLabourHtml(entry)}`;
}

async function saveWorkshopBookingTeam(event) {
  event.preventDefault();
  if (!['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role)) return false;
  const form = event.currentTarget;
  const bookingId = String(form.dataset.workshopBookingId || '');
  const entry = workshopLoadPlans().find(row => row.sharedBookingId === bookingId);
  if (!entry || entry.stage !== 'BUS_4X4' || !entry.bay || ['completed','deleted','cancelled'].includes(entry.status)
      || String(entry.sharedVersion) !== form.dataset.workshopBookingVersion) {
    workshopNotify('This booking changed. Review its current team before saving again.');
    renderWorkshopPlanner(); return false;
  }
  const data = new FormData(form);
  const primaryTechnicianId = String(data.get('primaryTechnicianId') || '');
  const helperTechnicianIds = [...new Set(data.getAll('helperTechnicianIds').map(String))];
  const rosterIds = new Set(workshopTeamRoster().map(row => row.id));
  if (!rosterIds.has(primaryTechnicianId) || helperTechnicianIds.some(id => !rosterIds.has(id))) {
    workshopNotify('Choose active technicians for every team role. No team change was sent.'); return false;
  }
  if (helperTechnicianIds.includes(primaryTechnicianId)) {
    workshopNotify('The primary technician is already on this booking. Untick them from Helpers before saving.'); return false;
  }
  const result = await workshopDispatchSharedAction('setBookingTeam', {
    bookingId, expectedVersion:entry.sharedVersion, primaryTechnicianId, helperTechnicianIds,
    requestId:workshopNewRequestId(), note:String(data.get('teamNote') || '').trim(),
  });
  return result?.ok === true;
}

function workshopDetailPanelHtml(entry = null, plans = [], options = {}) {
  const state = workshopState();
  const focused = options.focused === true;
  const expandedForSelection = Boolean(entry) && !state.detailCollapsedForSelection;
  const expanded = state.detailManualOpen || expandedForSelection;
  const panelClass = expanded ? 'workshop-detail-panel is-expanded' : 'workshop-detail-panel is-collapsed';
  const toggleLabel = expanded ? 'Collapse Job details' : 'Expand Job details';
  const selectedVehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  const selectedLabel = selectedVehicle ? displayStockNumber(selectedVehicle) || vehicleJobcardNumber(selectedVehicle) || 'Selected booking' : '';
  return `<section class="${panelClass}" data-workshop-detail-panel>
    <header class="workshop-detail-summary">
      <div><strong>Job details</strong><span>${entry ? `${escapeHtml(selectedLabel)} selected` : 'Select a planned booking to view, edit or reschedule it.'}</span></div>
      <div class="workshop-detail-summary-actions">
        ${focused ? '<button type="button" class="small-button" data-workshop-focused-back>Back to Workshop planner</button>' : ''}
        <button type="button" class="workshop-detail-toggle" data-workshop-detail-toggle aria-expanded="${expanded ? 'true' : 'false'}" aria-controls="workshop-detail-content" aria-label="${toggleLabel}" title="${toggleLabel}"><span aria-hidden="true">⌄</span></button>
      </div>
    </header>
    <div id="workshop-detail-content" class="workshop-detail-content" ${expanded ? '' : 'hidden'}>
      ${focused && entry ? workshopFocusedOperationLinesHtml(workshopVehicle(entry.vehicleKey), entry.stage) : workshopBookingNavigatorHtml(entry, plans)}
      ${workshopDetailHtml(entry, { focused })}
    </div>
  </section>`;
}

// A bay selection is an operational station surface, not a duplicate Vehicle
// Detail page. Keep only its source work and schedule/lifecycle controls.
function workshopStationSelectionHtml(entry = null) {
  if (!entry) return '';
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '<section class="workshop-station-selection" role="status">Selected station work is unavailable. Refresh the planner.</section>';
  const completed = entry.status === 'completed';
  const started = entry.status === 'started';
  const stopped = entry.status === 'stoppage';
  const start = parseIsoTimestamp(entry.startAt || '');
  const localValue = start ? workshopPerthLocalInputValue(start) : '';
  return `<section class="workshop-station-selection" data-workshop-detail-panel>
    <header><strong>${escapeHtml(pmbStageLabel(entry.stage))} work required</strong><span>${escapeHtml(stopped ? 'STOPPAGE' : entry.status || 'planned')}</span></header>
    ${workshopRequiredJobsForStageHtml(vehicle, entry.stage, workshopStageJobLines(vehicle, entry.stage))}
    <form class="workshop-station-selection-controls" data-workshop-detail-form data-workshop-plan-form-id="${escapeHtml(entry.id)}">
      <label><span>Start</span><input name="startAt" type="datetime-local" step="900" value="${escapeHtml(localValue)}" required ${completed || started ? 'disabled' : ''}></label>
      <label><span>Exact planned hours</span><input name="hours" type="number" min="0.0166667" step="any" inputmode="decimal" value="${escapeHtml(workshopExactDurationHours(entry.hours).toFixed(2))}" required ${completed ? 'disabled' : ''}></label>
      <label><span>Technician</span><select name="assignee" ${completed ? 'disabled' : ''}>${workshopAssigneeOptions(entry.stage, entry.assignee || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle))}</select></label>
      <div class="workshop-station-selection-actions">

        ${completed ? '<span class="badge success">Completed</span>' : '<button class="primary" type="submit">Save plan</button>'}
        ${completed ? '' : `<button class="small-button" type="button" data-workshop-start-plan="${escapeHtml(entry.id)}" ${started || WORKSHOP_PENDING_STARTS.has(entry.id) ? 'disabled' : ''} ${WORKSHOP_PENDING_STARTS.has(entry.id) ? 'aria-busy="true"' : ''}>${started ? 'Started' : WORKSHOP_PENDING_STARTS.has(entry.id) ? 'Starting…' : 'Start job'}</button><button class="small-button ${stopped ? 'active-lite' : ''}" type="button" ${stopped ? `data-workshop-resume-plan="${escapeHtml(entry.id)}"` : `data-workshop-stop-plan="${escapeHtml(entry.id)}"`}>${stopped ? 'Resume job' : 'STOPPAGE'}</button><button class="small-button active-lite" type="button" data-workshop-complete-plan="${escapeHtml(entry.id)}">Complete work</button>`}
      </div>
    </form>
    ${workshopBookingTeamHtml(entry)}
  </section>`;
}

function workshopDetailHtml(entry = null, options = {}) {
  const focused = options.focused === true;
  if (!entry) return `<div class="workshop-job-detail is-empty"><strong>Job details</strong><span>Select a planned vehicle to view, start, complete or reschedule it. Drag a planned job back to the left panel to return it to Unallocated.</span></div>`;
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return `<div class="workshop-job-detail is-empty"><strong>Vehicle unavailable</strong><span>This plan is retained for administrator review.</span></div>`;
  if (entry.legacyAmbiguityReason) {
    return `<div class="workshop-job-detail workshop-legacy-review-detail" role="status">
      <strong>Legacy review required · editing blocked</strong>
      <span>${escapeHtml(entry.legacyAmbiguityReason)}</span>
      <div class="workshop-detail-actions">
        <button class="small-button" type="button" data-workshop-open-job="${escapeHtml(entry.vehicleKey)}">Vehicle panel</button>
        <button class="small-button" type="button" data-workshop-open-vehicle="${escapeHtml(entry.vehicleKey)}">Full vehicle</button>
      </div>
    </div>`;
  }
  const start = parseIsoTimestamp(entry.startAt || '');
  const localValue = start ? workshopPerthLocalInputValue(start) : '';
  const started = String(entry.status || '').toLowerCase() === 'started';
  const completed = entry.status === 'completed';
  const stopped = entry.status === 'stoppage';
  const overtime = workshopEntryIsOvertime(entry);
  const assigneeConflict = workshopEntryHasAssigneeConflict(entry);
  const parts = workshopPartsSummary(vehicle);
  const stageLines = workshopStageJobLines(vehicle, entry.stage);
  const progress = workshopProgressSummary(entry);
  const stationLabel = `${pmbStageLabel(entry.stage)} ${workshopBayText(entry.stage, entry.bay)}`;
  const stageAssignee = cleanNavisionText(entry.assignee || '') || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle) || '';
  const statusTone = completed ? 'success' : stopped ? 'warning' : started ? 'info' : 'neutral';
  const statusLabel = completed ? 'Completed' : stopped ? 'STOPPAGE' : started ? 'Live' : 'Planned';
  const previousBay = Number(entry.bay) > 1 ? Number(entry.bay) - 1 : 0;
  const nextBay = Number(entry.bay) < workshopStageBayCount(entry.stage) ? Number(entry.bay) + 1 : 0;
  const bestBaySlot = completed
    ? null
    : workshopBestStageSlot(entry.stage, workshopEntryDate(entry), entry.hours, workshopLoadPlans().filter(row => row.id !== entry.id), workshopMinuteOffset(workshopEntryStart(entry)), '', [], pmbBayMechanic(vehicle) || '', entry.assignee || null, entry);
  const bestBaySummary = bestBaySlot ? workshopSlotSummary(entry.stage, bestBaySlot.bay, bestBaySlot.dateKey, bestBaySlot.startMinutes) : '';
  const durationInput = `<input name="hours" type="number" min="0.0166667" step="any" inputmode="decimal" value="${escapeHtml(workshopExactDurationHours(entry.hours).toFixed(2))}" required ${completed ? 'disabled' : ''} />`;
  const legacyScheduleControls = focused ? '' : [
    completed || !previousBay ? '' : `<button class="small-button" type="button" data-workshop-quick-move-plan="${escapeHtml(entry.id)}" data-workshop-quick-move-stage="${escapeHtml(entry.stage)}" data-workshop-quick-move-bay="${previousBay}">← ${escapeHtml(workshopBayChoiceLabel(entry.stage, previousBay))}</button>`,
    completed || !nextBay ? '' : `<button class="small-button" type="button" data-workshop-quick-move-plan="${escapeHtml(entry.id)}" data-workshop-quick-move-stage="${escapeHtml(entry.stage)}" data-workshop-quick-move-bay="${nextBay}">${escapeHtml(workshopBayChoiceLabel(entry.stage, nextBay))} →</button>`,
    completed || !bestBaySlot ? '' : `<button class="small-button" type="button" data-workshop-best-bay-plan="${escapeHtml(entry.id)}">Best bay/time</button>`,
    `<button class="small-button" type="button" data-workshop-open-job="${escapeHtml(entry.vehicleKey)}">Vehicle panel</button>`,
    `<button class="small-button" type="button" data-workshop-open-vehicle="${escapeHtml(entry.vehicleKey)}">Full vehicle</button>`,
  ].join('');
  const lifecycleControls = completed ? '' : `<button class="small-button" type="button" data-workshop-start-plan="${escapeHtml(entry.id)}" ${started || WORKSHOP_PENDING_STARTS.has(entry.id) ? 'disabled' : ''} ${WORKSHOP_PENDING_STARTS.has(entry.id) ? 'aria-busy="true"' : ''}>${started ? 'Started' : WORKSHOP_PENDING_STARTS.has(entry.id) ? 'Starting…' : 'Start job'}</button>
      <button class="small-button ${stopped ? 'active-lite' : ''}" type="button" ${stopped ? `data-workshop-resume-plan="${escapeHtml(entry.id)}"` : `data-workshop-stop-plan="${escapeHtml(entry.id)}"`}>${stopped ? 'Resume job' : 'STOPPAGE'}</button>
      <button class="small-button active-lite" type="button" data-workshop-complete-plan="${escapeHtml(entry.id)}">Complete work</button>`;
  return `<form class="workshop-job-detail" data-workshop-detail-form data-workshop-plan-form-id="${escapeHtml(entry.id)}">
    <div class="workshop-detail-identity">
      <strong>${escapeHtml(displayStockNumber(vehicle) || 'No stock')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')} · ${escapeHtml(stationLabel)}${started ? ' · STARTED' : ' · PLANNED'}${overtime ? ' · OVERTIME' : ''}</span>
      <small class="workshop-detail-status-line"><span class="badge ${statusTone}">${statusLabel}</span>${stageAssignee ? ` <span class="workshop-inline-meta">${escapeHtml(`Technician ${stageAssignee}`)}</span>` : ''}</small>
      <small>${stageLines.length ? `Imported ${escapeHtml(pmbStageLabel(entry.stage))} work: ${escapeHtml(stageLines.map(line => line.text).join(' · '))}` : `No imported ${escapeHtml(pmbStageLabel(entry.stage))} lines · time is manual/default`}</small>
      <small>Parts: ${escapeHtml(parts.text)}</small>
      <small>${escapeHtml(progress)}</small>
      ${bestBaySlot ? `<small class="workshop-slot-hint">Next open bay/time: ${escapeHtml(bestBaySummary)}</small>` : ''}
      ${assigneeConflict ? `<small class="workshop-assignee-warning">⚠ ${escapeHtml(entry.assignee)} is booked on another vehicle at this time.</small>` : ''}
    </div>
    <label><span>Start</span><input name="startAt" type="datetime-local" step="900" value="${escapeHtml(localValue)}" required ${completed || started ? 'disabled' : ''} /></label>
    <label><span>Exact planned hours</span>${durationInput}</label>
    <label><span>Technician</span><select name="assignee" ${completed ? 'disabled' : ''}>${workshopAssigneeOptions(entry.stage, entry.assignee || workshopBayMechanic(entry.stage, entry.bay) || pmbBayMechanic(vehicle))}</select></label>
    <div class="workshop-detail-actions">
      ${completed ? '<span class="badge success">Completed</span>' : '<button class="primary" type="submit">Save plan</button>'}
      ${focused || completed ? '' : `<button class="small-button" type="button" data-workshop-open-plan-week="${escapeHtml(entry.id)}">Week</button>`}
      ${legacyScheduleControls}
      ${lifecycleControls}
    </div>
  </form>${workshopBookingTeamHtml(entry)}`;
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
      ? `<div class="workshop-link-readiness-table"><table><thead><tr><th>Vehicle</th><th>Status</th><th>Shared UUID / reason</th></tr></thead><tbody>${reviewRows.map(row => `<tr><td><strong>${escapeHtml(displayStockNumber(row.vehicle) || vehicleKey(row.vehicle) || 'No stock')}</strong><span>${escapeHtml(workshopVehicleLinkIdentityInput(row.vehicle).vin || 'No VIN')}</span></td><td>${escapeHtml(labels[row.status] || row.status)}</td><td>${escapeHtml(row.diagnostic.sharedUuid || workshopVehicleLinkVisibleReason(row.diagnostic))}</td></tr>`).join('') || '<tr><td colspan="3">All reviewed vehicles are already linked.</td></tr>'}</tbody></table></div>`
      : '<p class="warning-banner">Vehicle identities and shared UUIDs are restricted to operator and administrator review.</p>'}`;
}

async function workshopOpenVehicleLinkReadinessReview() {
  if (!workshopSharedModeActive()) {
    workshopNotify('Shared vehicle-link readiness is available only while the shared Workshop backend is active.');
    return;
  }
  if (!workshopVehicleLinkCanPersist()) {
    workshopNotify('Shared vehicle-link readiness is restricted to operators and administrators.');
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
  progress.textContent = `Readiness report generated ${new Date(report.generatedAt).toLocaleString('en-AU', { timeZone: 'Australia/Perth' })}.`;
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

function workshopEnsureDedicatedShell(root, stage = '') {
  let shell = root.querySelector(':scope > .workshop-planner-dedicated');
  if (!shell) {
    root.innerHTML = `<div class="workshop-planner workshop-planner-dedicated" data-planner-stage="">
      <div data-workshop-station-content><div class="empty-state workshop-station-loading" role="status"><strong>Loading selected station</strong><span>Preparing its bays and bookings…</span></div></div>
    </div>`;
    shell = root.querySelector(':scope > .workshop-planner-dedicated');
  }
  shell.dataset.plannerStage = stage;
  return shell.querySelector('[data-workshop-station-content]');
}

function workshopSelectedDateBookingCount(activeRows = [], completedRows = [], snapshot = null, authoritative = false) {
  const canonical = Number(snapshot?.counts?.selected_date_bookings);
  if (authoritative && Number.isFinite(canonical) && canonical >= 0) return canonical;
  return activeRows.length + completedRows.length;
}

function workshopShiftAdminStart(startValue, deltaMinutes = 0) {
  if (deltaMinutes >= 0) return workshopAddWorkMinutes(startValue, deltaMinutes);
  let cursor = parseIsoTimestamp(startValue) || new Date(startValue);
  let remaining = Math.abs(Math.trunc(deltaMinutes));
  while (remaining > 0) {
    cursor = new Date(cursor.getTime() - 60000);
    if (workshopAvailabilityWindowsForDate(cursor).some(window => {
      const minute = workshopMinuteOfDay(cursor);
      return minute >= window.startMinutes && minute < window.endMinutes;
    })) remaining -= 1;
  }
  return cursor;
}

async function workshopMoveAdminBlock(block = {}, stage = '', bay = 0, startAt = '') {
  if (!block.id || !Number.isInteger(block.version)) return false;
  const result = await workshopDispatchSharedAction('moveAdminBlock', {
    blockId: block.id, expectedVersion: block.version,
    stageCode: normalizePmbStage(stage || block.stage), bayNumber: Number(bay || block.bay),
    scheduledStartAt: startAt || block.startAt,
    metadata: { source: 'planner_admin_block_move' },
  });
  return result?.ok === true;
}

async function workshopResizeAdminBlock(block = {}, durationMinutes = 0) {
  const duration = Math.max(WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, workshopSnapMinutes(durationMinutes));
  const result = await workshopDispatchSharedAction('resizeAdminBlock', {
    blockId: block.id, expectedVersion: block.version, durationMinutes: duration,
    metadata: { source: 'planner_admin_block_resize' },
  });
  return result?.ok === true;
}

async function workshopRenameAdminBlock(block = {}) {
  const current = String(block.label || '').trim();
  const label = window.prompt('Admin block label', current);
  if (label === null || !label.trim() || label.trim() === current) return false;
  const result = await workshopDispatchSharedAction('renameAdminBlock', {
    blockId: block.id, expectedVersion: block.version, label: label.trim(),
    metadata: { source: 'planner_admin_block_rename' },
  });
  return result?.ok === true;
}

async function workshopDeleteAdminBlock(block = {}) {
  if (!window.confirm(`Delete this ${block.type || 'admin'} downtime block? Eligible future planned vehicle/Admin rows will compact atomically toward the next valid operational minute; started, fixed and historical rows remain unchanged.`)) return false;
  const result = await workshopDispatchSharedAction('deleteAdminBlock', {
    blockId: block.id, expectedVersion: block.version,
    reason: 'Removed from Workshop Planner', metadata: { source: 'planner_admin_block_delete' },
  });
  return result?.ok === true;
}

async function workshopCurrentGlobalRevision(fallback = null) {
  const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null;
  const config = window.PDC_SUPABASE_CONFIG || {};
  if (!token || !config.url) return Number.isFinite(Number(fallback)) ? Number(fallback) : null;
  try {
    const response = await fetch(`${String(config.url).replace(/\/$/, '')}/rest/v1/workshop_revision?select=revision&id=eq.1&limit=1`, {
      headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}` },
    });
    if (!response.ok) return Number.isFinite(Number(fallback)) ? Number(fallback) : null;
    const rows = await response.json();
    const revision = Number(Array.isArray(rows) ? rows[0]?.revision : null);
    return Number.isFinite(revision) ? revision : (Number.isFinite(Number(fallback)) ? Number(fallback) : null);
  } catch (_error) {
    return Number.isFinite(Number(fallback)) ? Number(fallback) : null;
  }
}

function workshopAdminBlockSetFeedback(tone = '', message = '') {
  workshopAdminBlockFeedback = { tone: String(tone || ''), message: String(message || '') };
}

function workshopAdminBlockFormatTime(value) {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
}

function workshopAdminBlockSuccessMessage(result = {}) {
  const block = result.admin_block || {};
  const cascade = result.cascade || result.repack || {};
  const count = Number(cascade.shifted_count || 0);
  const minutes = Number(block.duration_minutes || 0);
  const hours = minutes / 60;
  const duration = Number.isInteger(hours) ? `${hours} h` : `${hours.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')} h`;
  const suffix = ` · cascaded ${count} planned row${count === 1 ? '' : 's'}`;
  // r549 (F163): prefer a saved display_name. Otherwise keep the plain Bay N
  // text this receipt has always used (unpadded), including when stage is blank.
  let bayLabel = '';
  try {
    if (typeof workshopBayStoredName === 'function') {
      bayLabel = String(workshopBayStoredName(block.stage_code || block.stage, block.bay_number) || '').trim();
    }
  } catch (_error) { bayLabel = ''; }
  if (!bayLabel && typeof globalThis.workshopBayStoredName === 'function') {
    bayLabel = String(globalThis.workshopBayStoredName(block.stage_code || block.stage, block.bay_number) || '').trim();
  }
  if (!bayLabel) bayLabel = `Bay ${block.bay_number || '—'}`;
  return `Admin block placed in ${bayLabel} at ${workshopAdminBlockFormatTime(block.scheduled_start_at)} · ${duration} total${suffix}.`;
}

function workshopAdminBlockResultSummary(result = {}) {
  return workshopAdminBlockSuccessMessage(result);
}

function workshopAdminBlockFailureSummary(result = {}) {
  if (result.error === 'fixed_booking_conflict') {
    const blocker = result.blocker || {};
    const nearest = result.nearest_available_slot || {};
    const blockerText = blocker.booking_id
      ? `Blocked by ${String(blocker.status || 'fixed').toUpperCase()} booking ${blocker.booking_id}${blocker.scheduled_start_at ? ` (${workshopAdminBlockFormatTime(blocker.scheduled_start_at)}–${workshopAdminBlockFormatTime(blocker.scheduled_end_at)})` : ''}.`
      : 'A fixed/live booking occupies that time.';
    const nearestText = nearest.scheduled_start_at
      ? `Nearest exact available slot: ${workshopAdminBlockFormatTime(nearest.scheduled_start_at)}–${workshopAdminBlockFormatTime(nearest.scheduled_end_at)}.`
      : 'No exact available slot was found in the configured horizon.';
    return `${blockerText} ${nearestText} No change was saved.`;
  }
  return workshopDescribeSharedActionError(result);
}

async function workshopCreateAdminBlockRequest(payload = {}) {
  workshopAdminBlockSetFeedback('pending', 'Placing Admin block… checking the current bay, schedule and booking versions.');
  renderWorkshopPlanner();
  const result = await workshopDispatchSharedAction('createAdminBlock', payload, renderWorkshopPlanner, { suppressFailureAlert: true });
  if (result?.ok === true) workshopAdminBlockSetFeedback('success', workshopAdminBlockResultSummary(result));
  else workshopAdminBlockSetFeedback('error', workshopAdminBlockFailureSummary(result));
  renderWorkshopPlanner();
  return result;
}

async function workshopCreatePaletteAdminBlock(stage = '', bay = 0, dateKey = '', startMinutes = 0, durationMinutes = 30) {
  if (!workshopSharedModeActive() || !workshopAdminBlockCanMutate()) return false;
  const snapshot = window.__workshopDataService?.getTrustedSnapshot?.();
  if (!snapshot || !Number.isFinite(Number(snapshot.revision))) {
    workshopAdminBlockSetFeedback('error', 'The current shared Workshop schedule is still loading. No Admin block was created.');
    renderWorkshopPlanner();
    return false;
  }
  const expectedRevision = await workshopCurrentGlobalRevision(snapshot.revision);
  if (!Number.isFinite(Number(expectedRevision))) {
    workshopAdminBlockSetFeedback('error', 'The shared Workshop revision could not be read. No Admin block was created.');
    renderWorkshopPlanner();
    return false;
  }
  const start = workshopDateAtOffset(dateKey, startMinutes);
  const result = await workshopCreateAdminBlockRequest({
    expectedRevision: Number(expectedRevision),
    stageCode: stage,
    bayNumber: Number(bay),
    blockType: 'admin',
    label: 'Admin downtime',
    scheduledStartAt: start.toISOString(),
    durationMinutes: workshopSnapMinutes(Number(durationMinutes) || 30),
    requestId: workshopNewRequestId(),
    metadata: { source: 'planner_admin_palette' },
  });
  return result?.ok === true;
}

function workshopAdminDurationHoursValue(minutes = 30) {
  const hours = workshopSnapMinutes(Number(minutes) || 30) / 60;
  return String(Number(hours.toFixed(2)));
}

function workshopAdminSafeDurationMinutes() {
  return Math.max(WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes, WORKSHOP_ADMIN_SAFE_DURATION_DAYS * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
}

function workshopAdminDurationInputMinutes(value = 0, unit = 'hours') {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) return null;
  const minutes = unit === 'working_days' ? numeric * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes : numeric * 60;
  const snapped = workshopSnapMinutes(minutes);
  return snapped > 0 && snapped <= workshopAdminSafeDurationMinutes() ? snapped : null;
}

function bindWorkshopAdminPalette(root) {
  const palette = root.querySelector('[data-workshop-admin-palette]');
  if (!palette) return;
  const durationInput = palette.querySelector('[data-workshop-admin-palette-duration]');
  const durationUnit = palette.querySelector('[data-workshop-admin-palette-unit]');
  const tile = palette.querySelector('[data-workshop-admin-palette-tile]');
  const label = palette.querySelector('[data-workshop-admin-palette-label]');
  const updateDuration = () => {
    const unit = durationUnit?.value || 'hours';
    const minutes = workshopAdminDurationInputMinutes(Number(durationInput?.value) || 0.5, unit);
    if (!minutes) {
      workshopAdminBlockSetFeedback('error', `Admin duration must be between 0.25 hours and ${WORKSHOP_ADMIN_SAFE_DURATION_DAYS} configured working days.`);
      return;
    }
    workshopAdminPaletteDurationMinutes = minutes;
    if (durationInput) durationInput.value = unit === 'working_days'
      ? String(Number((workshopAdminPaletteDurationMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes).toFixed(2)))
      : workshopAdminDurationHoursValue(workshopAdminPaletteDurationMinutes);
    if (label) label.textContent = unit === 'working_days'
      ? `Admin · ${(workshopAdminPaletteDurationMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes).toFixed(2)} working days`
      : `Admin · ${workshopAdminDurationHoursValue(workshopAdminPaletteDurationMinutes)} h`;
    if (tile) tile.dataset.adminPaletteDuration = String(workshopAdminPaletteDurationMinutes);
  };
  durationInput?.addEventListener('change', updateDuration);
  durationInput?.addEventListener('input', updateDuration);
  durationUnit?.addEventListener('change', updateDuration);
  tile?.addEventListener('dragstart', event => {
    updateDuration();
    event.dataTransfer.effectAllowed = 'copy';
    event.dataTransfer.setData('application/x-workshop-admin-palette', 'admin');
    event.dataTransfer.setData('application/x-workshop-admin-duration-minutes', String(workshopAdminPaletteDurationMinutes));
    workshopSetDragPreview({ type: 'admin-block', hours: workshopAdminPaletteDurationMinutes / 60 });
  });
  tile?.addEventListener('keydown', event => {
    if (event.key !== 'Enter' && event.key !== ' ') return;
    event.preventDefault();
    openWorkshopAdminBlockModal();
  });
}

function openWorkshopAdminBlockModal() {
  if (!workshopSharedModeActive() || !workshopAdminBlockCanMutate()) return;
  const snapshot = window.__workshopDataService?.getTrustedSnapshot?.();
  if (!snapshot || !Number.isFinite(Number(snapshot.revision))) {
    workshopNotify('The current shared workshop schedule is still loading. Try again in a moment.');
    return;
  }
  const stage = workshopState().stage;
  const dateKey = workshopState().date;
  const bayOptions = Array.from({ length: workshopStageBayCount(stage) }, (_, index) => `<option value="${index + 1}">${escapeHtml(workshopBayText(stage, index + 1, true))}</option>`).join('');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-admin-block-overlay';
  overlay.setAttribute('role', 'dialog'); overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-labelledby', 'workshop-admin-block-title');
  overlay.innerHTML = `<section class="modal-card workshop-admin-block-modal"><button class="modal-close" type="button" data-admin-block-cancel aria-label="Close">×</button>
    <header><h2 id="workshop-admin-block-title">Add yellow Admin block</h2><p>Reserve selected operational time for training, sick leave or administration. Only queued planned rows may be repacked.</p></header>
    <form data-admin-block-form><div class="workshop-schedule-grid">
      <label><span>Type</span><select name="blockType"><option value="training">Training</option><option value="sick">Sick leave</option><option value="admin">Admin downtime</option></select></label>
      <label><span>Label (optional)</span><input name="label" maxlength="120" placeholder="Team training" /></label>
      <label><span>Physical bay</span><select name="bay">${bayOptions}</select></label>
      <label><span>Date</span><input name="date" type="date" value="${escapeHtml(dateKey)}" required /></label>
      <label><span>Start time</span><select name="startMinutes">${workshopScheduleTimeOptions(0)}</select></label>
      <label><span>Duration unit</span><select name="durationUnit"><option value="hours">Hours</option><option value="working_days">Working days</option></select></label>
      <label><span>Duration</span><input name="durationValue" type="number" min="0.25" step="0.25" value="0.5" required aria-label="Admin block duration" /></label>
    </div><p class="workshop-schedule-note">Hours and working days are converted to exact configured operational minutes. Breaks, closures, weekends and overtime are skipped. The safe representational bound is ${WORKSHOP_ADMIN_SAFE_DURATION_DAYS} configured working days; longer requests receive an inline error.</p>
    <div class="edit-actions"><button class="secondary" type="button" data-admin-block-cancel>Cancel</button><button class="primary" type="submit">Create Admin block</button></div></form></section>`;
  const opener = document.activeElement;
  const close = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
    if (opener?.isConnected && typeof opener.focus === 'function') opener.focus();
  };
  overlay.querySelectorAll('[data-admin-block-cancel]').forEach(button => button.addEventListener('click', close));
  overlay.addEventListener('keydown', event => {
    if (event.key !== 'Escape') return;
    event.preventDefault();
    close();
  });
  overlay.querySelector('[data-admin-block-form]').addEventListener('submit', async event => {
    event.preventDefault();
    const form = event.currentTarget;
    const expectedRevision = await workshopCurrentGlobalRevision(snapshot.revision);
    if (!Number.isFinite(Number(expectedRevision))) {
      workshopNotify('The shared Workshop revision could not be read. No Admin block was created.');
      return;
    }
    const start = workshopDateAtOffset(form.elements.date.value, Number(form.elements.startMinutes.value));
    const durationMinutes = workshopAdminDurationInputMinutes(form.elements.durationValue.value, form.elements.durationUnit.value);
    if (!durationMinutes) {
      workshopAdminBlockSetFeedback('error', `Admin duration must be between 0.25 hours and ${WORKSHOP_ADMIN_SAFE_DURATION_DAYS} configured working days.`);
      return;
    }
    const result = await workshopCreateAdminBlockRequest({
      expectedRevision: Number(expectedRevision), stageCode: stage,
      bayNumber: Number(form.elements.bay.value), blockType: form.elements.blockType.value,
      label: cleanNavisionText(form.elements.label.value), scheduledStartAt: start.toISOString(),
      durationMinutes,
      requestId: workshopNewRequestId(),
      metadata: { source: 'planner_admin_block_create' },
    });
    if (result?.ok) close();
  });
  overlay.addEventListener('click', event => { if (event.target === overlay) close(); });
  document.body.appendChild(overlay); document.body.classList.add('modal-open');
  overlay.querySelector('[name="blockType"]')?.focus();
}

function workshopUnallocatedHeadingCounts(outstanding = [], returnedPlans = [], counts = null) {
  const returnedIds = new Set((returnedPlans || []).map(entry => String(entry?.sharedVehicleId || '')).filter(Boolean));
  const outstandingList = Array.isArray(outstanding) ? outstanding : [];
  const returnedOutstanding = outstandingList.filter(vehicle => returnedIds.has(String(vehicle?.sharedVehicleId || vehicle?.id || ''))).length;
  const outstandingCount = Number(counts?.outstanding_candidates);
  const unscheduledCount = Number(counts?.unscheduled_candidates);
  // The station snapshot already counts outstanding work and active bookings.
  // A partial vehicle array must not replace those totals. Queued bayless
  // returns are active bookings in that count, and they belong in Unallocated.
  if (Number.isFinite(outstandingCount) && Number.isFinite(unscheduledCount)) {
    return {
      unallocated: unscheduledCount + returnedOutstanding,
      booked: Math.max(0, outstandingCount - unscheduledCount - returnedOutstanding),
    };
  }
  const booked = outstandingList.filter(vehicle => {
    const id = String(vehicle?.sharedVehicleId || vehicle?.id || '');
    return vehicle?.__workshopOutstanding?.existingBooking === true && !returnedIds.has(id);
  }).length;
  const unallocated = outstandingList.filter(vehicle => vehicle?.__workshopOutstanding?.existingBooking !== true).length + returnedOutstanding;
  return { unallocated, booked };
}

function workshopReturnedQueuePlans(plans, stage, category = '') {
  return plans.filter(entry => entry.stage === stage && (entry.sharedStatus === 'queued'
    // r424 (F38): stopped in a bay, then dragged to Unallocated (see workshopPlanStoppedUnallocated).
    || (entry.sharedStatus === 'stoppage' && Boolean(entry.actualStartAt) && !entry.actualEndAt))
    && !entry.sharedBayId && Number(entry.bay) === 0
    && (!category || !entry.workCategory || entry.workCategory === 'BUS_WHOLE_JOB' || entry.workCategory === category));
}

// r424 (F38): a job stopped in a bay and then dragged to Unallocated (for
// example waiting on parts) shows with the returned jobs. Re-planning it ends
// the stoppage (reason kept in its history), keeps the time already worked and
// books only the remaining hours.
function workshopPlanStoppedUnallocated(entry) {
  return Boolean(entry && entry.sharedStatus === 'stoppage' && !entry.sharedBayId && Number(entry.bay) === 0
    && entry.actualStartAt && !entry.actualEndAt);
}

// A booking that was started, stopped and then returned to the queue keeps
// its actual start (time already worked). r415 (F31): the planner or
// controller re-plans it like any other queued job; the server resumes it,
// keeps the time worked in its history and books only the remaining hours.
const WORKSHOP_STARTED_BEFORE_HINT = 'Started before · time worked is kept';
const WORKSHOP_STARTED_BEFORE_MESSAGE = 'This job was started before and returned to the queue. Re-planning it keeps the time already worked and books only the remaining hours.';

function workshopPlanStartedBefore(entry) {
  if (!entry) return false;
  const status = String(entry.sharedStatus || entry.status || '');
  return status === 'queued' && Boolean(entry.actualStartAt) && !entry.actualEndAt;
}

function workshopReturnedQueueCardHtml(entry) {
  const vehicle = workshopVehicle(entry.vehicleKey, entry.stage);
  if (!vehicle) return '';
  const identity = displayStockNumber(vehicle) || entry.vehicleKey;
  const stopped = workshopPlanStoppedUnallocated(entry);
  const startedBefore = stopped || workshopPlanStartedBefore(entry);
  const startedHint = stopped
    ? ['Stopped', cleanNavisionText(entry.stoppageReason || ''), 'time worked is kept'].filter(Boolean).join(' · ')
    : WORKSHOP_STARTED_BEFORE_HINT;
  const disabled = '';
  return `<article class="workshop-queue-card workshop-unallocated-vehicle-pill${startedBefore ? ' is-started-before' : ''}" draggable="true" tabindex="0" role="group"${startedBefore ? ' data-workshop-started-before="1"' : ''}
    data-workshop-plan-id="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" data-workshop-locate-key="${escapeHtml(entry.vehicleKey)}"
    aria-label="${escapeHtml(`Vehicle ${identity}. ${startedBefore ? `${startedHint}. ` : ''}Press Enter to open the vehicle.`)}" title="${escapeHtml(startedBefore ? `${WORKSHOP_STARTED_BEFORE_MESSAGE} Drag onto a bay, use Best slot, or use Schedule.` : 'Drag onto a bay, use Best slot, or use Schedule')}">
    ${workshopVehicleIdentitySummaryHtml(vehicle)}
    <span>${escapeHtml(workshopQueueVehicleDescription(vehicle))}</span>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small class="workshop-estimated-hours-line">Estimated: ${escapeHtml(Number(entry.hours).toFixed(2))} h</small>
    ${startedBefore ? `<small class="workshop-started-before-hint" role="note">${escapeHtml(startedHint)}</small>` : ''}
    <div class="workshop-queue-actions">
      <button type="button" class="workshop-schedule-button best-slot" data-workshop-returned-best-slot="${escapeHtml(entry.id)}"${disabled}>Best slot</button>
      <button type="button" class="workshop-schedule-button" data-workshop-returned-schedule="${escapeHtml(entry.id)}"${disabled}>Schedule</button>
    </div></article>`;
}

function workshopReturnedPlanForAction(planId, { explain = false } = {}) {
  const state = workshopState();
  if (workshopSharedModeActive() && !window.__workshopDataService?.getTrustedSnapshot?.()) return null;
  const category = state.stage === 'BUS_4X4' ? workshopSelectedBusGroup()?.code || '' : '';
  const plan = workshopReturnedQueuePlans(workshopLoadPlans(), state.stage, category).find(entry => entry.id === planId) || null;
  return plan;
}

function workshopSelectReturnedPlan(planId) {
  const state = workshopState();
  const category = state.stage === 'BUS_4X4' ? workshopSelectedBusGroup()?.code || '' : '';
  const plan = workshopReturnedQueuePlans(workshopLoadPlans(), state.stage, category).find(entry => entry.id === planId);
  if (!plan || (workshopSharedModeActive() && !window.__workshopDataService?.getTrustedSnapshot?.())) return false;
  workshopSelectPlanForDetail(plan.id);
  state.searchOpen = false;
  state.searchHighlightPlanId = plan.id;
  state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
  renderWorkshopPlanner();
  openWorkshopVehicleJob(plan.vehicleKey, plan.stage, plan.id);
  return true;
}

function renderWorkshopPlanner(options = {}) {
  const projectionOnly = options.projectionOnly === true;
  if (workshopSharedModeActive()) workshopSyncConfigFromSharedSettings();
  const root = document.querySelector('#workshop-planner-root');
  if (!root) return;
  // A direct interaction may paint before the snapshot's queued frame runs.
  // Consume that frame while retaining later refreshes and their new state.
  // Clock projections leave full legacy reconciliation to the queued render.
  if (!projectionOnly && typeof cancelWorkshopPlannerRender === 'function') cancelWorkshopPlannerRender();
  const state = workshopState();
  if (typeof app.pendingBusBayGroup === 'string') { state.busBayGroup = app.pendingBusBayGroup; delete app.pendingBusBayGroup; }
  if (typeof app.pendingBusShowAllBays === 'boolean') { state.busShowAllBays = app.pendingBusShowAllBays; delete app.pendingBusShowAllBays; }
  const pendingBookingLink = typeof app !== 'undefined' ? app.pendingWorkshopBookingLink : null;
  const pendingWorkContext = typeof app !== 'undefined' ? app.pendingVehicleWorkContext : null;
  if ((pendingBookingLink || pendingWorkContext) && !workshopDepartmentLayout()?.categoryForView?.(app.currentRequestedView)) state.busBayGroup = '';
  if (pendingWorkContext?.station && normalizePmbStage(pendingWorkContext.station) === normalizePmbStage(state.stage)) {
    if (pendingWorkContext.bay) state.bay = String(pendingWorkContext.bay);
    app.pendingVehicleWorkContext = null;
  }
  if (pendingBookingLink && /^\d{4}-\d{2}-\d{2}$/.test(String(pendingBookingLink.date || ''))) state.date = pendingBookingLink.date;
  workshopApplyOpenDateDefault(state);
  const dedicatedStage = normalizePmbStage(window.__activeWorkshopPlannerStage || '');
  const pendingStage = normalizePmbStage(app.pendingWorkshopStage || '');
  const requestedStage = dedicatedStage || pendingStage;
  if (WORKSHOP_STAGE_SEQUENCE.includes(requestedStage)) {
    const stageChanged = state.stage !== requestedStage;
    state.stage = requestedStage;
    // A dedicated station re-renders after selection and Realtime refresh.
    // Preserve detail unless navigation actually changed the station.
    if (stageChanged || pendingStage) workshopClearSelectedDetail(state);
    app.pendingWorkshopStage = '';
  }
  const stage = dedicatedStage || (WORKSHOP_VISIBLE_STAGE_SEQUENCE.includes(state.stage) ? state.stage : 'FABRICATION');
  const sharedModeActive = workshopSharedModeActive();
  const renderHost = dedicatedStage ? workshopEnsureDedicatedShell(root, stage) : root;
  if (dedicatedStage && sharedModeActive && !window.__workshopDataService?.getLastSnapshot?.()) {
    renderHost.innerHTML = workshopStationSnapshotEmptyStateHtml(stage);
    return;
  }
  const authoritativePlans = dedicatedStage
    ? workshopLoadPlans()
    : workshopSyncCompletedPlans(undefined, { persist: !projectionOnly });
  // Clock-driven movement is a pure projection. Authoritative booking rows
  // change only after an explicit protected mutation succeeds.
  let plans = workshopCascadePlans(authoritativePlans, new Date()).rows;
  if (dedicatedStage) plans = plans.filter(entry => entry.stage === dedicatedStage);
  const navigationScope = window.__workshopDataService?.getScope?.();
  if (pendingBookingLink?.search === true) {
    // A Control Board or search jump must not retain a previous single-job view.
    state.focusedBookingMode = false;
    state.focusedBookingId = '';
    state.focusedBookingError = '';
  }
  // Vehicle-card links need the same fresh destination as search links. The
  // retained snapshot can exist while a refresh still withholds trusted rows.
  const searchNavigationReady = (pendingBookingLink?.search !== true && pendingBookingLink?.focused !== true) || (
    window.__workshopDataService?.getTrustedSnapshot?.()
    && navigationScope?.stageCode === stage
    && navigationScope?.dateFrom === pendingBookingLink.date
    && navigationScope?.dateTo === pendingBookingLink.date
  );
  if (pendingBookingLink && normalizePmbStage(pendingBookingLink.stage || '') === stage && searchNavigationReady) {
    if (pendingBookingLink.focused === true) {
      const focused = workshopResolveFocusedBooking(pendingBookingLink, plans, stage);
      state.focusedBookingMode = true;
      state.focusedBookingError = focused.ok ? '' : `This booking could not be opened safely (${focused.error}). The scoped authoritative snapshot was not changed.`;
      state.focusedBookingId = focused.ok ? focused.entry.id : '';
      state.selectedPlanId = focused.ok ? focused.entry.id : '';
      state.searchHighlightPlanId = focused.ok ? focused.entry.id : '';
      state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
      state.search = '';
      state.searchOpen = false;
      state.detailManualOpen = focused.ok;
      workshopSaveView(state);
      app.pendingWorkshopBookingLink = null;
    } else {
      const pendingPlan = plans.find(entry => !['completed', 'deleted', 'cancelled'].includes(entry.status)
        && String(entry.id || '') === String(pendingBookingLink.bookingId || '')
        && (!pendingBookingLink.vehicleId || String(entry.sharedVehicleId || '') === String(pendingBookingLink.vehicleId)));
      if (pendingPlan) {
        state.selectedPlanId = pendingPlan.id;
        state.highlightVehicleKey = pendingPlan.vehicleKey;
        state.searchHighlightPlanId = pendingPlan.id;
        state.highlightScrollRequest = (state.highlightScrollRequest || 0) + 1; // r470 (F83): scroll to it once
        if (pendingBookingLink.search === true) {
          state.detailManualOpen = false;
          state.detailCollapsedForSelection = true;
          state.searchOpen = false;
        }
        state.search = pendingPlan.vehicle?.stock || pendingPlan.vehicle?.customer || pendingPlan.vehicle?.id || '';
        workshopSaveView(state);
        app.pendingWorkshopBookingLink = null;
      } else if (pendingBookingLink.search === true) {
        const scope = window.__workshopDataService?.getScope?.();
        if (window.__workshopDataService?.getTrustedSnapshot?.() && scope?.stageCode === stage
          && scope?.dateFrom === pendingBookingLink.date && scope?.dateTo === pendingBookingLink.date) {
          state.bookingNavigationError = 'This booking changed or is no longer active. Search again to find its current position.';
          state.searchHighlightPlanId = '';
          state.highlightVehicleKey = '';
          state.selectedPlanId = '';
          app.pendingWorkshopBookingLink = null;
        }
      }
    }
  }
  if (state.focusedBookingMode && state.focusedBookingId) {
    const focusedMatches = plans.filter(entry => String(entry.sharedBookingId || '').trim() === String(state.focusedBookingId).trim());
    if (focusedMatches.length !== 1) {
      state.focusedBookingError = 'The focused booking is no longer present in the scoped authoritative snapshot. No local position or candidate was substituted.';
      state.selectedPlanId = '';
    } else {
      state.focusedBookingError = '';
      state.selectedPlanId = focusedMatches[0].id;
      state.stage = focusedMatches[0].stage;
      state.date = workshopEntryDate(focusedMatches[0]);
    }
  } else if (state.selectedPlanId && !plans.some(entry => entry.id === state.selectedPlanId)) workshopClearSelectedDetail(state);
  const selected = plans.find(entry => entry.id === state.selectedPlanId) || null;
  const focusedBookingMode = state.focusedBookingMode === true;
  const focusedPlans = focusedBookingMode ? (selected ? plans.filter(entry => entry.id === selected.id) : []) : plans;
  const dateKey = state.date;
  const selectedCategoryBays = stage === 'BUS_4X4' ? new Set(workshopVisibleBays(stage).map(Number)) : null;
  const activePlans = (focusedBookingMode ? focusedPlans : plans.filter(entry => entry.stage === stage))
    .filter(entry => entry.status !== 'completed' && Number(entry.bay) > 0
      && (!selectedCategoryBays || selectedCategoryBays.has(Number(entry.bay))));
  const stageVehicleList = workshopPlannerVehiclesForStage(stage);
  const returnedPlans = focusedBookingMode ? [] : workshopReturnedQueuePlans(plans, stage,
    stage === 'BUS_4X4' ? workshopSelectedBusGroup()?.code || '' : '');
  const returnedVehicleIds = new Set(returnedPlans.map(entry => entry.sharedVehicleId));
  const outstanding = focusedBookingMode ? [] : stageVehicleList;
  const unscheduled = focusedBookingMode ? [] : outstanding.filter(vehicle => vehicle.__workshopOutstanding?.existingBooking !== true
    || returnedVehicleIds.has(vehicle.sharedVehicleId || vehicle.id));
  const queueHeading = focusedBookingMode
    ? { unallocated: 0, booked: 0 }
    : workshopUnallocatedHeadingCounts(outstanding, returnedPlans, window.__workshopDataService?.getLastSnapshot?.()?.counts);
  let unallocatedHeadingCount = queueHeading.unallocated;
  let alreadyBookedOutstanding = queueHeading.booked;
  const queueHeadingTrusted = !sharedModeActive || !dedicatedStage || Boolean(window.__workshopDataService?.getTrustedSnapshot?.());
  if (!focusedBookingMode && !queueHeadingTrusted && state.retainedQueueHeading?.stage === stage && state.retainedQueueHeading?.dateKey === dateKey) {
    unallocatedHeadingCount = state.retainedQueueHeading.unallocated;
    alreadyBookedOutstanding = state.retainedQueueHeading.booked;
  } else if (!focusedBookingMode && queueHeadingTrusted && sharedModeActive && dedicatedStage) {
    state.retainedQueueHeading = { stage, dateKey, unallocated: unallocatedHeadingCount, booked: alreadyBookedOutstanding };
  }
  // Once a vehicle is assigned to this station's physical bay it is no longer
  // actionable in the Outstanding candidates pile. The authoritative total is
  // still retained separately for reporting and reconciliation.
  const queue = focusedBookingMode ? [] : unscheduled.filter(vehicle => !returnedVehicleIds.has(vehicle.sharedVehicleId || vehicle.id));
  const incrementalScope = `${stage}:${dateKey}`;
  if (state.incrementalRenderScope !== incrementalScope) {
    state.incrementalRenderScope = incrementalScope;
    state.incrementalQueueLimit = WORKSHOP_INCREMENTAL_RENDER_BATCH;
  }
  const queueBatch = workshopIncrementalRenderRows(queue, state.incrementalQueueLimit, state.highlightVehicleKey);
  const todaysPlans = activePlans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
  const selectedDateBookingCount = todaysPlans.length;
  const assigneeConflicts = todaysPlans.filter(entry => workshopEntryHasAssigneeConflict(entry, plans)).length;
  const stageVehicleCounts = dedicatedStage
    ? new Map([[stage, stageVehicleList.length]])
    : new Map(WORKSHOP_VISIBLE_STAGE_SEQUENCE.map(value => [value, value === stage ? stageVehicleList.length : workshopStageVehicles(value).length]));
  const stageTabs = workshopDepartmentLayout() || dedicatedStage || focusedBookingMode ? '' : WORKSHOP_VISIBLE_STAGE_SEQUENCE.map(value => `<button type="button" class="workshop-stage-tab ${value === stage ? 'active' : ''}" data-workshop-stage="${escapeHtml(value)}"><span>${escapeHtml(pmbStageLabel(value))}</span><strong>${stageVehicleCounts.get(value)}</strong></button>`).join('');
  const sharedBanner = sharedModeActive ? workshopConnectionBannerHtml() : '';
  // r561 (F175): one compact header — single small title, status dot, one control row.
  const plannerTitleText = focusedBookingMode ? 'Focused Workshop booking' : (workshopDepartmentLayout()?.plannerTitle(stage) || 'Workshop bay planner');
  const plannerSubtitle = `${stage === 'BUS_4X4' ? 'Use the left menu to choose a work category. Open Control Board to see all bays.' : stage === 'TINT' || stage === 'TYRE' ? 'One shared schedule for both departments.' : `${pmbStageLabel(stage)} · individual PMB bays`} Configured breaks and closures remain visible on the schedule.`;
  const primaryExtras = [
    !focusedBookingMode && sharedModeActive && workshopAdminBlockCanMutate() ? `<div class="workshop-admin-palette" data-workshop-admin-palette><span class="workshop-admin-palette-hint">Drag to a bay</span><button class="workshop-admin-palette-tile" type="button" draggable="true" data-workshop-admin-palette-tile data-admin-palette-duration="${workshopAdminPaletteDurationMinutes}"><span data-workshop-admin-palette-label>Admin · ${workshopAdminDurationHoursValue(workshopAdminPaletteDurationMinutes)} h</span></button><label class="workshop-admin-palette-duration"><span>Unit</span><select data-workshop-admin-palette-unit aria-label="Admin block duration unit"><option value="hours">Hours</option><option value="working_days">Working days</option></select><span>Duration</span><input type="number" min="0.25" step="0.25" value="${workshopAdminDurationHoursValue(workshopAdminPaletteDurationMinutes)}" data-workshop-admin-palette-duration aria-label="Admin block duration" /></label></div>` : '',
    !focusedBookingMode ? '<button class="small-button warning-button" type="button" data-workshop-parts-warning>Draft next-day parts warning</button>' : '',
  ].filter(Boolean).join('');
  const overflowControls = [
    stage === 'BUS_4X4' ? '<a class="small-button" href="docs/bus4x4-user-guide.html" target="_blank" rel="noopener">Department 138 user guide</a>' : '',
    focusedBookingMode ? '<button class="small-button" type="button" data-workshop-focused-back>← Back to Workshop planner</button>' : '',
    !focusedBookingMode && sharedModeActive && workshopLastAdministratorMove && workshopAdministratorCanMove() ? '<button class="small-button" type="button" data-workshop-undo-admin-move>Undo last move</button>' : '',
    !focusedBookingMode && sharedModeActive && workshopBayResequenceUndoAvailable() ? '<button class="small-button" type="button" data-workshop-undo-bay-resequence>Undo re-order</button>' : '',
  ].filter(Boolean).join('');
  renderHost.innerHTML = `<div class="${dedicatedStage ? 'workshop-planner workshop-station-board' : 'workshop-planner'}${focusedBookingMode ? ' is-focused-booking' : ''}" data-planner-stage="${escapeHtml(stage)}">
    <header class="workshop-planner-header">
      <div class="workshop-planner-brand">
        ${sharedBanner}
        <h2 class="workshop-planner-title" title="${escapeHtml(plannerSubtitle)}">${escapeHtml(plannerTitleText)}</h2>
      </div>
      <div class="workshop-date-controls">
        <div class="workshop-date-nav">
          <input type="date" data-workshop-date aria-label="Workshop planner date" value="${escapeHtml(dateKey)}" />
          <span class="workshop-date-shift-group" aria-label="Change workshop date">
            <button class="small-button" type="button" data-workshop-date-shift="-1">‹ Previous</button>
            <button class="small-button" type="button" data-workshop-date-shift="1">Next ›</button>
          </span>
        </div>
        ${focusedBookingMode ? '' : '<button class="small-button" type="button" data-workshop-today>Today</button><button class="small-button" type="button" data-workshop-refresh-vehicle data-pdc-operational-refresh data-pdc-refresh-route="workshop">Refresh Vehicle</button>'}
        ${!focusedBookingMode && sharedModeActive && workshopAdminBlockCanMutate() ? '<button class="small-button workshop-admin-block-add" type="button" data-workshop-add-admin-block>+ Admin block</button>' : ''}
        <div class="workshop-header-primary-extras">${primaryExtras}</div>
        ${overflowControls ? `<details class="workshop-header-more"><summary class="small-button workshop-header-more-summary" aria-label="More planner controls">⋯</summary><div class="workshop-header-more-panel">${overflowControls}</div></details>` : ''}
        ${!focusedBookingMode && workshopAdminBlockFeedback.message ? `<div class="workshop-admin-block-feedback ${escapeHtml(workshopAdminBlockFeedback.tone)}" role="status" aria-live="polite">${escapeHtml(workshopAdminBlockFeedback.message)}</div>` : ''}
      </div>
    </header>

    ${workshopStartFeedback.stage === stage && workshopStartFeedback.message ? `<div class="workshop-search-state" role="status" aria-live="polite">${escapeHtml(workshopStartFeedback.message)}</div>` : ''}
    <div class="workshop-date-summary"><strong>${escapeHtml(workshopDateLabel(dateKey))}</strong><span>${selectedDateBookingCount} active bookings on selected date · ${outstanding.length} outstanding · ${unscheduled.length} unscheduled${assigneeConflicts ? ` · ⚠ ${assigneeConflicts} mechanic clash${assigneeConflicts === 1 ? '' : 'es'}` : ''} · Saved automatically${state.lastSavedAt ? ` ${escapeHtml(new Date(state.lastSavedAt).toLocaleTimeString('en-AU', { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' }))}` : ''}</span><div class="workshop-status-legend"><span class="planned">Planned</span><span class="admin">Admin block</span><span class="live">Live</span><span class="stoppage">STOPPAGE</span></div></div>
    ${focusedBookingMode ? '' : workshopSearchControlHtml(state.search || '', plans)}
    ${state.bookingNavigationError ? `<div class="workshop-search-state is-warning" role="alert">${escapeHtml(state.bookingNavigationError)}</div>` : ''}
    ${!focusedBookingMode && typeof pdcWorkshopDepartmentControls === 'function' ? pdcWorkshopDepartmentControls() : ''}
    ${stage === 'TINT' || stage === 'TYRE' ? '<p class="workshop-board-note">Shared by Departments 138 and 139. All bookings are shown and reserve the same physical bays.</p>' : ''}
    ${stageTabs ? `<nav class="workshop-stage-tabs" aria-label="Workshop departments">${stageTabs}</nav>` : ''}
    ${focusedBookingMode && state.focusedBookingError ? `<section class="workshop-focused-booking-error" role="alert"><strong>Focused booking unavailable</strong><span>${escapeHtml(state.focusedBookingError)}</span><button type="button" class="small-button" data-workshop-focused-back>Back to Workshop planner</button></section>` : ''}
    <div class="workshop-board-shell">
      ${focusedBookingMode ? '' : `<aside class="workshop-side-panel workshop-waiting-panel">
        <div class="workshop-side-heading"><strong>Unallocated vehicles</strong><span>${unallocatedHeadingCount} unallocated · ${alreadyBookedOutstanding} already booked in bays</span></div>
        <div class="workshop-unallocated-drop" data-workshop-unallocated-drop><strong>Return to Unallocated</strong><span>Planned or live: choose Just move or STOPPAGE</span></div>
        <div class="workshop-side-list">${returnedPlans.map(workshopReturnedQueueCardHtml).join('')}${queueBatch.visible.map(vehicle => workshopQueueCardHtml(vehicle, stage, dateKey, plans)).join('') || (returnedPlans.length ? '' : '<div class="workshop-empty">No outstanding requirements in this department.</div>')}${workshopIncrementalLoadMoreHtml('queue', queueBatch)}</div>
      </aside>`}
      <section class="workshop-timeline-scroll">
        <div class="workshop-scroll-cue" role="note">Swipe or scroll schedule horizontally →</div>
        <div class="workshop-timeline" style="${workshopTimelineCssVariables()}">
          <div class="workshop-time-header"><div class="workshop-bay-label"><strong>${escapeHtml(`${pmbStageLabel(stage)} bays`)}</strong><span>${escapeHtml(`${workshopVisibleBays(stage).length} physical bay${workshopVisibleBays(stage).length === 1 ? '' : 's'}`)}</span></div><div class="workshop-time-axis">${workshopTimeAxisHtml()}</div></div>
          <div class="workshop-now-line" data-workshop-now-line hidden><span>Now</span></div>
          ${workshopBayRowsHtml(stage, dateKey, focusedPlans)}
        </div>
      </section>

    </div>
    ${focusedBookingMode ? '<div class="workshop-board-note">Focused booking mode shows only the selected canonical booking. Use Back to Workshop planner to return to the full station board.</div>' : '<div class="workshop-board-note">How to use: drag a waiting vehicle or planned booking onto the exact bay/time you want. If that spot overlaps only queued planned work, the planner keeps your dropped booking there and offers to push the later queue back-to-back behind it. Use Best slot for the fastest bay suggestion, or use Schedule to put it in the next free slot of a chosen bay, or into a chosen place in the bay order. If a day is full, automatic sequencing continues on the next workday. Live overlap stays blocked, while live jobs can still be moved safely with the bay quick controls or drag/drop. The red current-time line stays visible on the planner and clamps to the workshop edge outside work hours. Double-click any vehicle to open the vehicle panel.</div>'}
  </div>`;
  bindWorkshopPlanner(renderHost);
  updateWorkshopNowLine(renderHost);
  setupWorkshopPlannerClock();
  workshopScrollToHighlightedVehicle(renderHost);
  window.__pdcEnsureOperationalRefreshControls?.();
}

function bindWorkshopPlanner(root) {
  if (typeof pdcWorkshopDepartmentChanged === 'function') root.querySelector('[data-workshop-department]')?.addEventListener('change',pdcWorkshopDepartmentChanged);
  if (root.dataset.workshopIncrementalBound !== '1') {
    root.dataset.workshopIncrementalBound = '1';
    root.addEventListener('click', event => {
      const button = event.target.closest?.('[data-workshop-load-more]');
      if (!button || !root.contains(button)) return;
      const state = workshopState();
      if (button.dataset.workshopLoadMore !== 'queue') return;
      state.incrementalQueueLimit = (Number(state.incrementalQueueLimit) || WORKSHOP_INCREMENTAL_RENDER_BATCH) + WORKSHOP_INCREMENTAL_RENDER_BATCH;
      renderWorkshopPlanner();
    });
  }
  workshopBindDragAutoScroll(root);
  root.querySelectorAll('[data-workshop-focused-back]').forEach(button => button.addEventListener('click', workshopExitFocusedBooking));
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
  root.querySelector('[data-workshop-undo-admin-move]')?.addEventListener('click', async () => {
    await workshopUndoLastAdministratorMove();
  });
  root.querySelector('[data-workshop-undo-bay-resequence]')?.addEventListener('click', async () => {
    await workshopUndoLastBayResequence();
  });
  root.querySelector('[data-workshop-today]')?.addEventListener('click', () => {
    const state = workshopState();
    state.date = workshopDefaultOpenDateKey(new Date());
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    if (!workshopRefreshDedicatedDate(state.date)) renderWorkshopPlanner();
  });
  root.querySelector('[data-workshop-date]')?.addEventListener('change', event => {
    const selected = workshopDateFromKey(event.target.value);
    if (!selected) return;
    const coerced = workshopCoerceWorkDate(selected, 1);
    if (workshopDateKey(coerced) !== event.target.value) workshopNotify('Workshop boards run Monday to Friday. The date has been moved to the next workday.', 'info');
    const state = workshopState();
    state.date = workshopDateKey(coerced);
    workshopClearSelectedDetail(state);
    workshopSaveView(state);
    if (!workshopRefreshDedicatedDate(state.date)) renderWorkshopPlanner();
  });
  const searchInputs = [...root.querySelectorAll('[data-workshop-search], [data-workshop-search-key]')];
  searchInputs.forEach(searchInput => {
  searchInput.addEventListener('focus', event => {
    const state = workshopState();
    const field = event.currentTarget.hasAttribute('data-workshop-search-key') ? 'key' : 'text';
    if (field === 'key') state.searchKey = event.currentTarget.value;
    else state.search = event.currentTarget.value;
    state.searchOpen = workshopSearchIsActive(workshopSearchCriteria(state));
    const results = root.querySelector('#workshop-booking-search-results');
    if (results && state.searchOpen) {
      results.hidden = false;
      const lookup = workshopCurrentSearchLookup(workshopSearchCriteria(state));
      if (lookup?.status === 'ready' && [...lookup.matches.values()].some(result => !result.ok)) state.bookingSearchLookup = null;
      void workshopRefreshSearchResults(root, event.currentTarget, event.currentTarget.value);
    }
  });
  searchInput.addEventListener('input', event => {
    const input = event.currentTarget;
    const state = workshopState();
    if (input.hasAttribute('data-workshop-search-key')) state.searchKey = input.value;
    else state.search = input.value;
    window.clearTimeout(app.workshopPlannerSearchTimer);
    app.workshopPlannerSearchTimer = window.setTimeout(() => {
      if (input.isConnected) workshopRefreshSearchResults(root, input, input.value);
    }, 180);
  });
  searchInput.addEventListener('keydown', async event => {
    if (event.key === 'Escape') {
      event.preventDefault();
      const state = workshopState();
      state.searchOpen = false;
      const results = root.querySelector('#workshop-booking-search-results');
      if (results) results.hidden = true;
      root.querySelectorAll('[data-workshop-search], [data-workshop-search-key]').forEach(field => field.setAttribute('aria-expanded', 'false'));
      return;
    }
    if (event.key !== 'Enter') return;
    event.preventDefault();
    window.clearTimeout(app.workshopPlannerSearchTimer);
    const state = workshopState();
    const input = event.currentTarget;
    if (input.hasAttribute('data-workshop-search-key')) state.searchKey = input.value;
    else state.search = input.value;
    const criteria = workshopSearchCriteria(state);
    await workshopLoadSearchBookings(criteria);
    if (workshopSearchCriteriaKey(workshopSearchCriteria()) !== workshopSearchCriteriaKey(criteria)) return;
    const matches = workshopSearchMatches(criteria);
    if (matches.length === 1 && matches[0].bookings.length) {
      workshopSelectSearchBooking(matches[0].bookings[0].id, matches[0].vehicleIdentity);
      return;
    }
    workshopRevealSearchMatch(input.value, input.hasAttribute('data-workshop-search-key') ? 'key' : 'text');
  });
  });
  root.querySelector('[data-workshop-search-clear]')?.addEventListener('click', () => workshopRevealSearchMatch('', 'clear'));
  workshopBindSearchResultButtons(root);
  const searchState = workshopState();
  if (searchState.searchOpen && workshopSearchIsActive(workshopSearchCriteria(searchState))
    && window.__workshopDataService?.getTrustedSnapshot?.() && !workshopCurrentSearchLookup(workshopSearchCriteria(searchState))) {
    void workshopRefreshSearchResults(root, root.querySelector('[data-workshop-search]'), searchState.search);
  }
  root.querySelector('[data-workshop-detail-toggle]')?.addEventListener('click', () => {
    const state = workshopState();
    const selected = workshopLoadPlans().some(entry => entry.id === state.selectedPlanId);
    if (selected) state.detailCollapsedForSelection = !state.detailCollapsedForSelection;
    else state.detailManualOpen = !state.detailManualOpen;
    renderWorkshopPlanner();
  });

  root.querySelectorAll('[data-workshop-booking-nav]').forEach(button => button.addEventListener('click', () => {
    if (button.dataset.workshopBookingNav) workshopOpenBookingById(button.dataset.workshopBookingNav, button.dataset.workshopBookingVehicleIdentity);
  }));
  root.querySelector('[data-workshop-booking-jump]')?.addEventListener('change', event => workshopOpenBookingById(event.currentTarget.value, event.currentTarget.dataset.workshopBookingVehicleIdentity));
  root.querySelector('[data-workshop-add-admin-block]')?.addEventListener('click', openWorkshopAdminBlockModal);
  root.querySelector('[data-workshop-link-readiness]')?.addEventListener('click', () => { void workshopOpenVehicleLinkReadinessReview(); });
  root.querySelector('[data-workshop-parts-warning]')?.addEventListener('click', draftWorkshopNextDayFittingWarningEmail);
  root.querySelectorAll('[data-workshop-bay-mechanic-stage]').forEach(select => select.addEventListener('change', () => saveWorkshopBayMechanic(select.dataset.workshopBayMechanicStage, Number(select.dataset.workshopBayMechanicNumber), select.value)));
  root.querySelectorAll('[data-workshop-bay-rename-stage]').forEach(button => {
    if (button.closest('form')) return;
    button.addEventListener('click', () => {
      workshopBayRenameOpen = `${button.dataset.workshopBayRenameStage}:${button.dataset.workshopBayRenameBay}`;
      renderWorkshopPlanner();
      document.querySelector('[data-workshop-bay-rename-input]')?.focus();
    });
  });
  root.querySelector('[data-workshop-bay-rename-cancel]')?.addEventListener('click', () => {
    workshopBayRenameOpen = '';
    renderWorkshopPlanner();
  });
  root.querySelector('[data-workshop-bay-rename-form]')?.addEventListener('submit', event => {
    event.preventDefault();
    const form = event.currentTarget;
    void workshopSaveBayDisplayName(form.dataset.workshopBayRenameStage, Number(form.dataset.workshopBayRenameBay), form.querySelector('[data-workshop-bay-rename-input]')?.value || '');
  });
  root.querySelectorAll('[data-workshop-weekly-stage]').forEach(button => button.addEventListener('click', () => openWorkshopWeeklyView(button.dataset.workshopWeeklyStage, Number(button.dataset.workshopWeeklyBay), workshopState().date)));
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => {
    card.addEventListener('dragstart', event => {
      if (Date.now() < workshopSuppressMouseDragUntil || workshopActiveQueuePointerDrag) {
        event.preventDefault();
        return;
      }
      event.dataTransfer.effectAllowed = 'copy';
      event.dataTransfer.setData('application/x-workshop-vehicle-key', card.dataset.workshopVehicleKey);
      event.dataTransfer.setData('text/plain', card.dataset.workshopVehicleKey);
      const vehicle = workshopVehicle(card.dataset.workshopVehicleKey, workshopState().stage);
      workshopSetDragPreview({
        type: 'queue',
        hours: workshopSchedulingDuration(vehicle, workshopState().stage)?.hours || 0,
      });
    });
    card.addEventListener('pointerdown', downEvent => {
      const vehicle = workshopVehicle(card.dataset.workshopVehicleKey, workshopState().stage);
      workshopStartPointerDragSession(card, downEvent, root, {
        preview: () => ({
          type: 'queue',
          hours: workshopSchedulingDuration(vehicle, workshopState().stage)?.hours || 0,
        }),
        onDrop: ({ stage, bay, dateKey, startMinutes }) => {
          void scheduleWorkshopVehicle({ vehicleKeyValue: card.dataset.workshopVehicleKey, stage, bay, dateKey, startMinutes, preferRequestedTime: true });
        },
      });
    });
  });
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(root), 0);
  }));
  root.querySelectorAll('[data-workshop-schedule-vehicle]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    openWorkshopScheduleModal(button.dataset.workshopScheduleVehicle, workshopState().stage, workshopState().date);
  }));
  root.querySelectorAll('[data-workshop-best-slot-vehicle]').forEach(button => button.addEventListener('click', async event => {
    event.preventDefault();
    event.stopPropagation();
    if (button.disabled) return;
    button.disabled = true;
    button.setAttribute('aria-busy', 'true');
    try {
      await workshopScheduleVehicleNextAvailable({
        vehicleKeyValue: button.dataset.workshopBestSlotVehicle,
        stage: button.dataset.workshopBestSlotStage,
        hours: Number(button.dataset.workshopBestSlotHours),
      });
    } finally {
      if (button.isConnected) {
        button.disabled = false;
        button.removeAttribute('aria-busy');
      }
    }
  }));
  root.querySelectorAll('[data-workshop-returned-schedule]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault(); event.stopPropagation();
    const plan = workshopReturnedPlanForAction(button.dataset.workshopReturnedSchedule, { explain: true });
    if (plan) openWorkshopScheduleModal(plan.vehicleKey, plan.stage, workshopState().date, plan.id);
  }));
  root.querySelectorAll('[data-workshop-returned-best-slot]').forEach(button => button.addEventListener('click', async event => {
    event.preventDefault(); event.stopPropagation();
    if (button.disabled) return;
    const plan = workshopReturnedPlanForAction(button.dataset.workshopReturnedBestSlot, { explain: true });
    if (!plan) return;
    button.disabled = true;
    try { await workshopScheduleVehicleNextAvailable({vehicleKeyValue:plan.vehicleKey,stage:plan.stage,planId:plan.id}); }
    finally { if (button.isConnected) button.disabled = false; }
  }));
  root.querySelectorAll('[data-workshop-admin-block-id]').forEach(chip => {
    const block = workshopLoadAdminBlocks().find(row => row.id === chip.dataset.workshopAdminBlockId);
    if (!block) return;
    if (!workshopAdminBlockCanMutate()) return;
    chip.addEventListener('dragstart', event => {
      event.dataTransfer.effectAllowed = 'move';
      event.dataTransfer.setData('application/x-workshop-admin-block-id', block.id);
      workshopSetDragPreview({ type: 'admin-block', hours: block.durationMinutes / 60 });
    });
    chip.addEventListener('dragend', () => { workshopSetDragPreview(null); setTimeout(() => workshopClearLanePreviews(root), 0); });
    chip.addEventListener('keydown', event => {
      if (!['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
      event.preventDefault();
      const delta = event.key === 'ArrowRight' ? WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes : -WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
      if (event.shiftKey) void workshopResizeAdminBlock(block, block.durationMinutes + delta);
      else void workshopMoveAdminBlock(block, block.stage, block.bay, workshopShiftAdminStart(block.startAt, delta).toISOString());
    });
    chip.querySelectorAll('[data-admin-block-nudge]').forEach(button => button.addEventListener('click', event => {
      event.stopPropagation();
      const delta = Number(button.dataset.adminBlockNudge);
      void workshopMoveAdminBlock(block, block.stage, block.bay, workshopShiftAdminStart(block.startAt, delta).toISOString());
    }));
    chip.querySelectorAll('[data-admin-block-resize]').forEach(button => button.addEventListener('click', event => {
      event.stopPropagation(); void workshopResizeAdminBlock(block, block.durationMinutes + Number(button.dataset.adminBlockResize));
    }));
    chip.querySelector('[data-workshop-admin-block-rename]')?.addEventListener('click', event => { event.stopPropagation(); void workshopRenameAdminBlock(block); });
    chip.querySelector('[data-admin-block-delete]')?.addEventListener('click', event => { event.stopPropagation(); void workshopDeleteAdminBlock(block); });
    chip.querySelector('[data-admin-block-pointer-resize]')?.addEventListener('pointerdown', event => {
      event.preventDefault(); event.stopPropagation();
      const resizeToken = {};
      workshopActivePointerResize = resizeToken;
      const startX = event.clientX; const initial = block.durationMinutes;
      const laneWidth = chip.parentElement?.getBoundingClientRect().width || 1;
      const cancel = () => {
        window.removeEventListener('pointerup', finish);
        window.removeEventListener('pointercancel', cancel);
        if (workshopActivePointerResize === resizeToken) workshopActivePointerResize = null;
      };
      const finish = upEvent => {
        cancel();
        const deltaMinutes = workshopSnapMinutes(((upEvent.clientX - startX) / laneWidth) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
        if (deltaMinutes) void workshopResizeAdminBlock(block, initial + deltaMinutes);
      };
      window.addEventListener('pointerup', finish, { once: true });
      window.addEventListener('pointercancel', cancel, { once: true });
    });
  });
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragstart', event => {
    const entry = workshopLoadPlans().find(row => row.id === chip.dataset.workshopPlanId);
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', chip.dataset.workshopPlanId);
    workshopSetDragPreview({ type: 'plan', hours: Number(entry?.hours) || workshopDefaultBookingHours(), entry });
  }));
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(root), 0);
  }));
  root.querySelectorAll('[data-workshop-job-vehicle]').forEach(card => card.addEventListener('keydown', event => {
    if (event.target !== card || !['Enter', ' '].includes(event.key)) return;
    event.preventDefault();
    const plan = workshopLoadPlans().find(entry => entry.id === card.dataset.workshopPlanId);
    openWorkshopVehicleJob(card.dataset.workshopJobVehicle, plan?.stage || workshopState().stage, plan?.id || '');
  }));
  root.querySelectorAll('[data-workshop-job-vehicle]').forEach(card => card.addEventListener('dblclick', event => {
    event.preventDefault();
    const plan = workshopLoadPlans().find(entry => entry.id === card.dataset.workshopPlanId);
    openWorkshopVehicleJob(card.dataset.workshopJobVehicle, plan?.stage || workshopState().stage, plan?.id || '');
  }));
  root.querySelectorAll('[data-workshop-drop-bay]').forEach(lane => bindWorkshopLane(lane));
  bindWorkshopAdminPalette(root);
  bindWorkshopUnallocatedDrop(root.querySelector('[data-workshop-unallocated-drop]'));
  root.querySelectorAll('[data-workshop-select-plan]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    if (event.detail === 0) {
      const plan = workshopLoadPlans().find(entry => entry.id === button.dataset.workshopSelectPlan);
      if (plan) openWorkshopVehicleJob(plan.vehicleKey, plan.stage, plan.id);
      return;
    }
    workshopSelectPlanForDetail(button.dataset.workshopSelectPlan);
    root.querySelectorAll('[data-workshop-plan-id]').forEach(card => card.classList.toggle('is-selected', card.dataset.workshopPlanId === button.dataset.workshopSelectPlan));
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
    const vehicle = workshopVehicle(plan.vehicleKey);
    const bestSlot = workshopBestStageSlot(plan.stage, workshopEntryDate(plan), plan.hours, workshopLoadPlans().filter(row => row.id !== plan.id), workshopMinuteOffset(workshopEntryStart(plan)), '', [], vehicle ? pmbBayMechanic(vehicle) || '' : '', plan.assignee || null, plan);
    if (!bestSlot) return;
    const currentDate = workshopEntryDate(plan);
    const currentMinutes = workshopMinuteOffset(workshopEntryStart(plan));
    if (bestSlot.bay === Number(plan.bay) && bestSlot.dateKey === currentDate && bestSlot.startMinutes === currentMinutes) {
      workshopNotify('This job is already in the earliest open bay/time for its current stage.', 'info');
      return;
    }
    void moveWorkshopDroppedPlan(plan.id, plan.stage, bestSlot.bay, bestSlot.dateKey, bestSlot.startMinutes);
  }));
  root.querySelectorAll('[data-workshop-resize-plan]').forEach(handle => handle.addEventListener('pointerdown', event => startWorkshopResize(handle, event)));
  root.querySelectorAll('[data-workshop-extend-plan]').forEach(button => button.addEventListener('click', () => extendWorkshopPlan(button.dataset.workshopExtendPlan, Number(button.dataset.workshopExtendHours))));
  root.querySelector('[data-workshop-detail-form]')?.addEventListener('submit', saveWorkshopDetailForm);
  root.querySelector('[data-workshop-team-form]')?.addEventListener('submit', saveWorkshopBookingTeam);
  root.querySelector('[data-workshop-helper-labour-form]')?.addEventListener('submit', saveWorkshopHelperLabour);
  root.querySelector('[data-workshop-open-job]')?.addEventListener('click', event => {
    const selectedPlan = workshopLoadPlans().find(entry => entry.id === workshopState().selectedPlanId);
    openWorkshopVehicleJob(event.currentTarget.dataset.workshopOpenJob, selectedPlan?.stage || workshopState().stage, selectedPlan?.id || '');
  });
  root.querySelector('[data-workshop-open-vehicle]')?.addEventListener('click', event => openVehicleModal(event.currentTarget.dataset.workshopOpenVehicle));
  root.querySelectorAll('[data-workshop-start-plan]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    void startWorkshopPlan(event.currentTarget.dataset.workshopStartPlan);
  }));
  root.querySelectorAll('[data-workshop-stop-plan]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    void stopWorkshopPlan(event.currentTarget.dataset.workshopStopPlan);
  }));
  root.querySelectorAll('[data-workshop-pause-for-other]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    void pauseBayForOtherJob(event.currentTarget.dataset.workshopPauseForOther);
  }));
  root.querySelectorAll('[data-workshop-resume-plan]').forEach(button => button.addEventListener('click', event => {
    event.preventDefault();
    event.stopPropagation();
    void resumeWorkshopPlan(event.currentTarget.dataset.workshopResumePlan);
  }));
  root.querySelectorAll('[data-workshop-complete-plan]').forEach(button => button.addEventListener('click', event => completeWorkshopPlan(event.currentTarget.dataset.workshopCompletePlan)));
}

function bindWorkshopLane(lane) {
  lane.addEventListener('dragover', event => {
    event.preventDefault();
    lane.classList.add('drag-over');
    workshopQueueLanePreview(lane, event);
  });
  lane.addEventListener('dragleave', event => {
    if (!lane.contains(event.relatedTarget)) {
      lane.classList.remove('drag-over');
      workshopHideLanePreview(lane);
    }
  });
  lane.addEventListener('drop', event => {
    event.preventDefault();
    workshopFlushLanePreview(lane, event);
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
    const adminBlockId = event.dataTransfer.getData('application/x-workshop-admin-block-id');
    const adminPalette = event.dataTransfer.getData('application/x-workshop-admin-palette');
    const adminDurationMinutes = Number(event.dataTransfer.getData('application/x-workshop-admin-duration-minutes')) || 30;
    const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
    const vehicleKeyValue = event.dataTransfer.getData('application/x-workshop-vehicle-key') || event.dataTransfer.getData('text/plain');
    const dragHours = Number(event.dataTransfer.getData('application/x-workshop-duration-hours'));
    event.dataTransfer.dropEffect = adminPalette || adminBlockId || planId ? 'move' : 'copy';
    const stage = targetStage;
    const bay = targetBay;
    const dateKey = targetDate;
    const startMinutes = requestedStartMinutes;
    if (adminPalette) {
      void workshopCreatePaletteAdminBlock(stage, bay, dateKey, startMinutes, adminDurationMinutes);
      return;
    }
    if (adminBlockId) {
      const block = workshopLoadAdminBlocks().find(row => row.id === adminBlockId);
      if (block) void workshopMoveAdminBlock(block, stage, bay, workshopDateAtOffset(dateKey, startMinutes).toISOString());
      return;
    }
    if (planId) {
      void moveWorkshopDroppedPlan(planId, stage, bay, dateKey, startMinutes, { preferRequestedTime: true });
      return;
    }
    scheduleWorkshopVehicle({ planId, vehicleKeyValue, stage, bay, dateKey, startMinutes, hoursValue: Number.isFinite(dragHours) && dragHours > 0 ? dragHours : null, preferRequestedTime: true });
  });
}

function workshopBayAssignmentError(result = {}) {
  const code = result.error || result.code || result.detail?.code || 'request_failed';
  if (code === 'assignment_cancelled' || code === 'authority_superseded') return '';
  if (code === 'assignment_in_progress') return 'This bay assignment is still saving. Please wait for it to finish.';
  if (code === 'permission_denied' || code === 'not_authenticated') return 'Your session could not authorise this change. Sign in again.';
  if (code === 'technician_already_assigned_to_bay') return `This technician is already assigned to ${result.conflict?.bay_code || result.detail?.conflict?.bay_code || 'another bay'}. Clear that assignment before choosing this bay.`;
  if (code === 'version_conflict' || code === 'bay_assignment_changed') return 'This bay was assigned by another session. Its latest assignment has been loaded; review it before choosing a technician again.';
  if (code === 'technician_inactive' || code === 'technician_not_found') return 'This technician is no longer active in the roster. Refresh and choose an active technician.';
  if (code === 'network_error' || code === 'request_timeout' || code === 'bay_refresh_failed' || code === 'request_failed') return 'The bay assignment could not be confirmed. Check the connection and try again.';
  return `The bay assignment could not be saved (${code}). ${result.detail?.message || 'Refresh the bay list and try again.'}`;
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
      workshopNotify('This bay could not be matched to a shared bay record, so the default technician could not be saved. Reload the page and try again.');
      return;
    }
    let technicianId = null;
    if (assignee) {
      const technicianRef = workshopReferenceTechnicianRef(assignee);
      if (!technicianRef) {
        workshopNotify(`"${assignee}" could not be matched to an active technician in the shared roster. The bay default was not changed.`);
        return;
      }
      technicianId = technicianRef.technicianId;
    }
    const service = window.__workshopReferenceDataService;
    if (!service || typeof service.setBayDefaultTechnician !== 'function') {
      workshopNotify('The shared reference-data service is not available, so the bay default could not be saved.');
      return;
    }
    const pendingKey = `${stage}:${Number(bay)}`;
    if (WORKSHOP_PENDING_BAY_ASSIGNMENTS.has(pendingKey)) return;
    const currentView = app.currentView;
    const currentStage = workshopState().stage;
    const currentDate = workshopState().date;
    const readToken = () => typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null;
    const currentToken = readToken();
    const currentUser = window.PDC_AUTH_CONTEXT?.userId;
    const currentRole = window.PDC_AUTH_CONTEXT?.role;
    const isCurrent = () => app.currentView === currentView && workshopState().stage === currentStage && workshopState().date === currentDate
      && currentToken === readToken() && currentUser === window.PDC_AUTH_CONTEXT?.userId && currentRole === window.PDC_AUTH_CONTEXT?.role;
    let defaultSaved = false;
    WORKSHOP_PENDING_BAY_ASSIGNMENTS.add(pendingKey);
    renderWorkshopPlanner();
    try {
      const result = await service.setBayDefaultTechnician(bayRef.id, bayRef.version, technicianId, {
        observedTechnicianId: bayRef.default_technician_id,
        isCurrent,
      });
      if (!result || !result.ok) {
        const message = workshopBayAssignmentError(result || {});
        if (message && isCurrent()) workshopNotify(message);
        return;
      }
      defaultSaved = true;
      if (result.refreshRequired) {
        if (isCurrent()) workshopNotify('The technician assignment was saved, but the latest bay list could not be confirmed. Refresh before assigning more technicians.');
        return;
      }
      if (!isCurrent() || result.alreadyApplied) return;

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
          if (!isCurrent()) break;
          const assignResult = await window.__workshopSharedActions.assignBookingTechnician({
            bookingId: entry.sharedBookingId || entry.id,
            expectedVersion: entry.sharedVersion,
            technicianId,
          });
          if (!assignResult || !assignResult.ok) skipped += 1;
        }
        if (skipped && isCurrent()) workshopNotify(`${assignee} was saved as the bay default, but ${skipped} overlapping booking${skipped === 1 ? ' was' : 's were'} left unassigned because that mechanic is already booked elsewhere.`);
        return;
      }
    } catch (_) {
      if (isCurrent()) workshopNotify(defaultSaved
        ? 'The bay default was saved, but updating its unassigned bookings could not be completed. Refresh to check the booking assignments.'
        : 'The bay assignment could not be confirmed. Check the connection, refresh the bay list and try again.');
    } finally {
      WORKSHOP_PENDING_BAY_ASSIGNMENTS.delete(pendingKey);
      if (isCurrent()) renderWorkshopPlanner();
    }
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
  if (skipped) workshopNotify(`${assignee} was saved as the bay default, but ${skipped} overlapping booking${skipped === 1 ? ' was' : 's were'} left unassigned because that mechanic is already booked elsewhere.`);
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
      <header><h2>Return vehicle to PMB Unallocated</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} is leaving ${escapeHtml(workshopBayChoiceLabel(entry.stage, entry.bay))}. The work remains open.</p></header>
      <div class="workshop-return-options">
        <label><input type="radio" name="workshopReturnChoice" value="move" checked><span><strong>Just move</strong><small>Return to Unallocated without marking the job complete or creating a STOPPAGE.</small></span></label>
        <label><input type="radio" name="workshopReturnChoice" value="stoppage"><span><strong>STOPPAGE</strong><small>Return to Unallocated, keep the job open and flag the vehicle as stopped.</small></span></label>
      </div>
      <label class="workshop-return-reason" data-workshop-return-reason-wrap hidden><span>STOPPAGE reason</span><input type="text" data-workshop-return-reason value="${escapeHtml(entry.stoppageReason || `${pmbStageLabel(entry.stage)} STOPPAGE`)}"></label>
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
        workshopNotify('Enter the STOPPAGE reason.');
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
    workshopNotify('Completed work stays in planner history. It cannot be returned to Unallocated.');
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
      workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
      renderWorkshopPlanner();
      return;
    }
    workshopPersistPlanAction(
      'Workshop plan returned to queue',
      latestRows.filter(row => row.id !== entry.id),
      vehicle,
      'Workshop plan returned to queue',
      { stage: pmbStageLabel(entry.stage), bay: workshopBayChoiceLabel(entry.stage, entry.bay) },
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

    ...(stoppage
      ? workshopOwnedBlockUpdates(entry, result.reason, now, operator)
      : workshopOwnedBlockClearUpdates(entry, vehicle, now, operator)),
  };
  const persisted = workshopPersistVehiclePlanAction(
    'Return workshop job to Unallocated',
    rows.filter(row => row.id !== entry.id),
    vehicle,
    vehicleUpdates,
    stoppage ? 'Workshop job returned to Unallocated with STOPPAGE' : 'Workshop job returned to Unallocated',
    { stage: pmbStageLabel(entry.stage), bay: entry.bay, reason: stoppage ? result.reason : 'Just move', by: operator },
  );
  if (!persisted) return;
  workshopState().selectedPlanId = '';
  workshopState().highlightVehicleKey = '';
  if (stoppage) {
    offerSalespersonChangeEmail(vehicle, {
      title: `${pmbStageLabel(entry.stage)} STOPPAGE`,
      subject: 'PDC workshop STOPPAGE',
      details: [`The vehicle was returned to PMB Unallocated with this STOPPAGE: ${result.reason}.`, `The ${pmbStageLabel(entry.stage)} job remains open.`],
    });
  }
  renderWorkshopPlanner();
}

function workshopRequirePlannerStage(stage = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (WORKSHOP_ELIGIBILITY_RUNTIME.workshopIsPlannerStage(normalizedStage)) return normalizedStage;
  workshopNotify('This work type does not have a Workshop Planner. No scheduling change was made.');
  return '';
}

function workshopNotBeforeMinutesForDate(dateKey = '', referenceNow = new Date()) {
  const now = referenceNow instanceof Date ? new Date(referenceNow) : new Date(referenceNow);
  if (Number.isNaN(now.getTime()) || workshopDateKey(now) !== String(dateKey || '')) return 0;
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  const offset = workshopMinuteOffset(now);
  return Math.max(0, Math.ceil(offset / increment) * increment);
}

function workshopAdminBlockConflict(candidate = {}, blocks = workshopLoadAdminBlocks()) {
  const start = workshopEntryStart(candidate), end = workshopEntryEnd(candidate);
  return blocks.find(block => normalizePmbStage(block.stage) === normalizePmbStage(candidate.stage)
    && Number(block.bay) === Number(candidate.bay)
    && workshopIntervalsOverlap(start, end, parseIsoTimestamp(block.startAt), parseIsoTimestamp(block.endAt))) || null;
}

function workshopFirstAvailableStartMinutes(stage = '', bay = 1, dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0, vehicleWindows = [], assigneeValue = null, calendarVehicle = null) {
  const normalizedStage = normalizePmbStage(stage);
  const duration = workshopExactDurationHours(hours) || workshopClampDurationHours(hours);
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  const rawNotBefore = Math.max(0, Number(notBeforeMinutes) || 0);
  if (rawNotBefore >= WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) return null;
  const firstStart = Math.ceil(rawNotBefore / increment) * increment;
  const adminBlocks = workshopLoadAdminBlocks();
  const assignee = assigneeValue === null ? workshopBayMechanic(normalizedStage, bay) : assigneeValue;
  if (assignee && workshopSharedModeActive() && !workshopSelectedTechnicianRef(assignee)) return null;
  for (let startMinutes = firstStart; startMinutes < WORKSHOP_PLANNER_CONFIG.dayLengthMinutes; startMinutes += WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes) {
    const candidate = {
      id: '__availability_check__',
      vehicleKey: '__availability_check__',
      calendarVehicle,
      stage: normalizedStage,
      bay: Number(bay),
      startAt: workshopDateAtOffset(dateKey, startMinutes).toISOString(),
      hours: duration,
      status: 'planned',
      assignee,
    };
    if (!workshopHasConflict(candidate, rows) && !workshopAdminBlockConflict(candidate, adminBlocks)
      && !workshopAssigneeConflict(candidate, rows)
      && (!vehicleWindows.length || window.PDC_VEHICLE_HANDOVER?.fits(workshopEntryStart(candidate), workshopEntryEnd(candidate), vehicleWindows))
      && workshopNewBookingValidation(candidate).ok) return startMinutes;
  }
  return null;
}

function workshopFirstAvailableStartSlot(stage = '', bay = 1, dateKey = '', hours = workshopDefaultBookingHours(), rows = workshopLoadPlans(), notBeforeMinutes = 0, maxWorkdays = 260, referenceNow = new Date(), vehicleWindows = [], assigneeValue = null, notAfterDateKey = '', calendarVehicle = null) {
  const requestedDate = workshopDateFromKey(dateKey) || new Date();
  let workDate = workshopCoerceWorkDate(requestedDate, 1);
  for (let dayIndex = 0; dayIndex < Math.max(1, Number(maxWorkdays) || 260); dayIndex += 1) {
    const candidateDateKey = workshopDateKey(workDate);
    if (notAfterDateKey && candidateDateKey > notAfterDateKey) return null;
    const currentTimeFloor = workshopNotBeforeMinutesForDate(candidateDateKey, referenceNow);
    const firstMinutes = dayIndex === 0 ? Math.max(notBeforeMinutes, currentTimeFloor) : currentTimeFloor;
    const startMinutes = workshopFirstAvailableStartMinutes(stage, bay, candidateDateKey, hours, rows, firstMinutes, vehicleWindows, assigneeValue, calendarVehicle);
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
  if (!workshopRequirePlannerStage(entry.stage) || !workshopRequirePlannerStage(stage)) return false;
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
        workshopNotify(messages[availability] || 'This bay is not currently available for new bookings.');
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
    if (!workshopConfirmOtherDepartmentPlans(candidate, rows)) return false;
    const requestedLabel = `${workshopBayChoiceLabel(nextStage, nextBay)} · ${workshopEntryTimeLabel(candidate)}`;
    if (!window.confirm(`Move this live workshop job to ${requestedLabel}?\n\nThis updates the live bay allocation and keeps the job started/STOPPAGE history.`)) return false;
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
  const requestedLabel = `${workshopBayChoiceLabel(nextStage, nextBay)} · ${workshopEntryTimeLabel({ ...entry, stage: nextStage, bay: nextBay, startAt: nextStart })}`;
  if (!window.confirm(`Move this live workshop job to ${requestedLabel}?\n\nThis updates the live bay allocation and keeps the job started/STOPPAGE history.`)) return false;
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
    from: `${workshopBayChoiceLabel(entry.stage, entry.bay)} · ${workshopEntryTimeLabel(entry)}`,
    to: requestedLabel,
    status: entry.status,
    assignee: candidate.assignee || 'Unassigned',
  };
  const persisted = await assignPmbVehicleToBay(entry.vehicleKey, candidate.stage, candidate.bay, candidate.startAt, {
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
    workshopNotify('Completed workshop jobs stay fixed in history.');
    return Promise.resolve(false);
  }
  const resequenceTarget = workshopResequenceTarget(entry, stage, bay, dateKey, startMinutes, workshopLoadPlans());
  if (resequenceTarget) return workshopResequenceDrop(entry, resequenceTarget);
  if (entry.status === 'planned' || workshopPlanStoppedUnallocated(entry)) return Promise.resolve(scheduleWorkshopVehicle({ planId, stage, bay, dateKey, startMinutes, preferRequestedTime }));
  return moveWorkshopLivePlan(planId, stage, bay, dateKey, startMinutes);
}

// r424 (F38): drag a booking onto another booking in the same bay to change
// the order. The planner chooses "Move ahead of" or "Swap with", sees a
// preview of every booking that would move (the server lays the bay out again
// with each booking's own hours and the bay's shift hours; started jobs keep
// their times), and applies it in one transaction. Undo is offered for 30
// minutes. No window.confirm here: the choice and the preview are dialogs.
let workshopLastBayResequence = null;
const WORKSHOP_BAY_RESEQUENCE_UNDO_MS = 30 * 60 * 1000;
const WORKSHOP_RESEQUENCE_STATUSES = new Set(['planned', 'stoppage']);

function workshopResequenceTarget(entry, stage, bay, dateKey, startMinutes, rows) {
  if (!entry || !workshopSharedModeActive() || !entry.sharedBookingId || !Array.isArray(rows)) return null;
  if (!WORKSHOP_RESEQUENCE_STATUSES.has(String(entry.sharedStatus || ''))) return null;
  if (!(Number(bay) > 0) || Number(bay) !== Number(entry.bay) || normalizePmbStage(stage) !== normalizePmbStage(entry.stage)) return null;
  const dropStart = workshopDateAtOffset(dateKey, startMinutes).getTime();
  const minutes = Math.max(1, Math.round((Number(entry.hours) || 0) * 60));
  const dropEnd = dropStart + minutes * 60000;
  if (!Number.isFinite(dropStart)) return null;
  const hits = rows
    .filter(row => row && row.id !== entry.id && row.sharedBookingId && WORKSHOP_RESEQUENCE_STATUSES.has(String(row.sharedStatus || ''))
      && normalizePmbStage(row.stage) === normalizePmbStage(entry.stage) && Number(row.bay) === Number(entry.bay))
    .map(row => ({ row, start: Date.parse(row.startAt), end: Date.parse(row.endAt) }))
    .filter(item => Number.isFinite(item.start) && Number.isFinite(item.end) && item.start < dropEnd && dropStart < item.end)
    .sort((a, b) => a.start - b.start);
  return hits.length ? hits[0].row : null;
}

function workshopResequenceLabel(entry) {
  const vehicle = entry ? workshopVehicle(entry.vehicleKey, entry.stage) : null;
  const keyNumber = vehicle ? cleanNavisionText(vehicleKeyNumber(vehicle) || '') : '';
  if (keyNumber) return `Key ${keyNumber}`;
  return (vehicle && displayStockNumber(vehicle)) || String(entry?.vehicleKey || 'this job');
}

function workshopResequenceWhen(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false });
}

function workshopResequenceDialog(title, bodyHtml, buttons) {
  return new Promise(resolve => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay workshop-schedule-overlay workshop-resequence-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', title);
    overlay.innerHTML = `<section class="modal-card workshop-schedule-card workshop-resequence-card">
      <button class="modal-close" type="button" data-workshop-resequence-choice="" aria-label="Cancel">×</button>
      <header><h2>${escapeHtml(title)}</h2></header>
      ${bodyHtml}
      <div class="edit-actions">${buttons.map(button => `<button class="${escapeHtml(button.className || 'secondary')}" type="button" data-workshop-resequence-choice="${escapeHtml(button.value)}">${escapeHtml(button.label)}</button>`).join('')}</div>
    </section>`;
    let done = false;
    const finish = value => {
      if (done) return;
      done = true;
      overlay.remove();
      if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
      resolve(value || '');
    };
    overlay.querySelectorAll('[data-workshop-resequence-choice]').forEach(button => button.addEventListener('click', () => finish(button.dataset.workshopResequenceChoice)));
    overlay.addEventListener('keydown', event => { if (event.key === 'Escape') finish(''); });
    document.body.appendChild(overlay);
    document.body.classList.add('modal-open');
    overlay.querySelector('.primary')?.focus?.();
  });
}

function workshopResequencePreviewHtml(preview) {
  const changes = Array.isArray(preview?.changes) ? preview.changes : [];
  const rows = changes.map(change => {
    const who = [change.key_number ? `Key ${change.key_number}` : '', String(change.work_category || '').replace(/^BUS_/, '').toLowerCase(), change.bay_number ? `Bay ${change.bay_number}` : '']
      .filter(Boolean).join(' · ');
    return `<li>${escapeHtml(who)}: ${escapeHtml(workshopResequenceWhen(change.from_start) || 'Unallocated')} → <strong>${escapeHtml(workshopResequenceWhen(change.to_start))}</strong>${change.resumed ? ' <small>(stopped job re-planned · time worked kept)</small>' : ''}</li>`;
  }).join('');
  const other = Number(preview?.other_bays) > 0
    ? `<p class="workshop-schedule-note">${escapeHtml(`${preview.other_bays} later booking${Number(preview.other_bays) === 1 ? '' : 's'} for the same vehicle in another bay move back too, so nothing overlaps.`)}</p>` : '';
  return `<p>These bookings will move (Perth time). Each keeps its own hours; started jobs keep their times.</p><ul class="workshop-resequence-changes">${rows}</ul>${other}`;
}

async function workshopResequenceDrop(entry, target) {
  if (!workshopAdministratorCanMove()) {
    workshopNotify('Only a planner or controller can change the order of a bay. No change was made.');
    renderWorkshopPlanner();
    return false;
  }
  const moving = workshopResequenceLabel(entry);
  const other = workshopResequenceLabel(target);
  const mode = await workshopResequenceDialog(`Change the order in Bay ${Number(entry.bay)}`,
    `<p>${escapeHtml(`You dropped ${moving} on ${other}.`)}</p>`,
    [{ value: '', label: 'Cancel' }, { value: 'swap', label: `Swap with ${other}` }, { value: 'ahead', label: `Move ahead of ${other}`, className: 'primary' }]);
  if (!mode) { renderWorkshopPlanner(); return false; }
  const base = {
    bookingId: entry.sharedBookingId,
    expectedVersion: entry.sharedVersion,
    targetBookingId: target.sharedBookingId,
    mode,
    metadata: { source: 'planner_bay_resequence', reason: 'website_drag_drop' },
  };
  const preview = await workshopDispatchSharedAction('resequenceBay', { ...base, apply: false, requestId: workshopNewRequestId() });
  if (!preview || preview.ok !== true || !preview.plan_hash) return false;
  const apply = await workshopResequenceDialog(mode === 'swap' ? `Swap ${moving} and ${other}` : `Move ${moving} ahead of ${other}`,
    workshopResequencePreviewHtml(preview),
    [{ value: '', label: 'Cancel' }, { value: 'apply', label: 'Apply', className: 'primary' }]);
  if (apply !== 'apply') { workshopNotify('No change was made.', 'info'); renderWorkshopPlanner(); return false; }
  const result = await workshopDispatchSharedAction('resequenceBay', { ...base, apply: true, planHash: preview.plan_hash, requestId: workshopNewRequestId() });
  if (!result || result.ok !== true) return false;
  if (result.receipt_id) workshopLastBayResequence = { receiptId: String(result.receipt_id), undoRequestId: workshopNewRequestId(), at: Date.now(), bay: Number(entry.bay) };
  workshopNotify(`Bay ${Number(entry.bay)} re-ordered. Use “Undo re-order” within 30 minutes to put it back.`, 'info');
  renderWorkshopPlanner();
  return true;
}

function workshopBayResequenceUndoAvailable(now = Date.now()) {
  return Boolean(workshopLastBayResequence && now - workshopLastBayResequence.at < WORKSHOP_BAY_RESEQUENCE_UNDO_MS && workshopAdministratorCanMove());
}

async function workshopUndoLastBayResequence() {
  const receipt = workshopLastBayResequence;
  if (!receipt || !workshopBayResequenceUndoAvailable()) { workshopLastBayResequence = null; renderWorkshopPlanner(); return false; }
  const result = await workshopDispatchSharedAction('undoBayResequence', { receiptId: receipt.receiptId, requestId: receipt.undoRequestId });
  if (!result || result.ok !== true) {
    if (['undo_expired', 'already_undone', 'receipt_not_found', 'undo_actor_mismatch'].includes(result?.error)) workshopLastBayResequence = null;
    return false;
  }
  workshopLastBayResequence = null;
  workshopNotify('The re-order was undone.', 'info');
  renderWorkshopPlanner();
  return true;
}

function workshopScheduleTimeOptions(selectedMinutes = 0) {
  const increment = WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes;
  return Array.from({ length: Math.ceil(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / increment) }, (_, index) => index * increment)
    .map(minutes => `<option value="${minutes}"${minutes === Number(selectedMinutes) ? ' selected' : ''}>${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</option>`)
    .join('');
}

const WORKSHOP_SCHEDULE_DIALOG_RPCS = new Set([
  'administrator_schedule_workshop_vehicle',
  'administrator_move_workshop_booking',
  'schedule_vehicle_work',
  'move_workshop_booking',
  'cascade_workshop_schedule',
  'cascade_workshop_booking_move',
]);

function workshopBindScheduleCommitClose(service, finish) {
  let closed = false;
  const closeOnce = () => {
    if (closed) return false;
    closed = true;
    if (typeof finish === 'function') finish();
    return true;
  };
  const previous = typeof service?.setWriteCommittedListener === 'function'
    ? service.setWriteCommittedListener((rpcName, body) => {
      if (body?.ok === true && WORKSHOP_SCHEDULE_DIALOG_RPCS.has(rpcName)) closeOnce();
    })
    : null;
  return {
    closeOnce,
    restore() {
      if (typeof service?.setWriteCommittedListener === 'function') service.setWriteCommittedListener(previous || null);
    },
  };
}

// r535 (F149): Schedule no longer asks for a date, a start time, planned hours
// or a technician. The bay queue is the order already on the planner. A running
// job stays in that order and nothing is offered in front of it.
function workshopBayQueueRows(stage = '', bay = 0, excludeId = '') {
  const normalized = normalizePmbStage(stage);
  const number = Number(bay);
  return workshopLoadPlans()
    .filter(row => row && row.id !== excludeId
      && normalizePmbStage(row.stage) === normalized
      && Number(row.bay) === number
      && !['completed', 'deleted'].includes(String(row.status || ''))
      && !['completed', 'deleted'].includes(String(row.sharedStatus || '')))
    .sort((a, b) => workshopEntryStart(a) - workshopEntryStart(b) || String(a.id).localeCompare(String(b.id)));
}

function workshopBayQueueMovable(row = {}) {
  return String(row.status || '') !== 'started' && String(row.sharedStatus || '') !== 'started';
}

function workshopBayQueueLabel(entry = {}) {
  const vehicle = typeof workshopVehicle === 'function' ? workshopVehicle(entry.vehicleKey, entry.stage) : null;
  const text = value => typeof cleanNavisionText === 'function' ? cleanNavisionText(value || '') : String(value || '').trim();
  const key = text(typeof vehicleKeyNumber === 'function' ? vehicleKeyNumber(vehicle || {}) : '') || 'Key not listed';
  const stock = text(typeof displayStockNumber === 'function' ? displayStockNumber(vehicle || {}) : '') || text(entry.vehicleKey) || 'Stock not listed';
  const customer = text(typeof vehicleCustomerName === 'function' ? vehicleCustomerName(vehicle || {}) : '') || 'Customer not listed';
  const model = text(vehicle ? workshopQueueVehicleDescription(vehicle) : '') || 'Model not listed';
  return { key, stock, customer, model };
}

function workshopBayQueueHtml(rows = []) {
  if (!rows.length) return '<p class="workshop-bay-order-empty">No vehicles are queued in this bay.</p>';
  const parts = [];
  rows.forEach(row => {
    if (workshopBayQueueMovable(row)) parts.push(`<button class="workshop-insert-here" type="button" data-workshop-insert-before="${escapeHtml(row.id)}">Insert here</button>`);
    const label = workshopBayQueueLabel(row);
    parts.push(`<div class="workshop-bay-order-vehicle">Key ${escapeHtml(label.key)} · Stock ${escapeHtml(label.stock)} · ${escapeHtml(label.customer)} · ${escapeHtml(label.model)}</div>`);
  });
  parts.push('<button class="workshop-insert-here" type="button" data-workshop-insert-end>Insert here</button>');
  return parts.join('');
}

function workshopBayQueuePlacement(stage = '', bay = 0, targetId = '', excludeId = '') {
  const queue = workshopBayQueueRows(stage, bay, excludeId);
  if (!targetId) {
    if (!queue.length) return { kind: 'next' };
    const end = workshopEntryEnd(queue[queue.length - 1]);
    return { kind: 'end', dateKey: workshopDateKey(end), startMinutes: workshopMinuteOffset(end), reference: end };
  }
  const target = queue.find(row => String(row.id) === String(targetId));
  if (!target || !workshopBayQueueMovable(target)) return { kind: 'blocked' };
  const start = workshopEntryStart(target);
  return { kind: 'before', dateKey: workshopDateKey(start), startMinutes: workshopMinuteOffset(start) };
}

function openWorkshopScheduleModal(vehicleKeyValue = '', stage = '', dateKey = '', planId = '') {
  const returnedPlan = planId ? workshopReturnedPlanForAction(planId) : null;
  if (planId && !returnedPlan) return;
  const normalizedStage = normalizePmbStage(stage);
  const vehicle = workshopVehicle(vehicleKeyValue, normalizedStage);
  if (!vehicle || !WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return;
  const etaConstraint = workshopVehicleEtaConstraint(vehicle);
  if (etaConstraint.required && !etaConstraint.ok) {
    workshopRequireEtaSchedule(vehicle, '');
    return;
  }
  const duration = returnedPlan ? {hours:Number(returnedPlan.operationEstimateHours)||Number(returnedPlan.hours)} : workshopSchedulingDuration(vehicle, normalizedStage);
  if (workshopSharedModeActive() && !duration) {
    workshopNotify('Estimated hours are required before this vehicle can be scheduled into a bay. No booking was created.');
    return;
  }
  let baseHours = duration?.hours || workshopDefaultBookingHours();
  const scheduleCategory = returnedPlan?.workCategory || vehicle.__workshopOutstanding?.workCategory || '';
  // r450 (F63): when 2+ Bus categories are unbooked, the controller can book the
  // whole job (every unbooked line) to one technician as one booking instead.
  const categoryHours = baseHours;
  const wholeJob = !returnedPlan && normalizedStage === 'BUS_4X4' && scheduleCategory && scheduleCategory !== 'BUS_WHOLE_JOB'
    ? workshopDepartmentLayout()?.wholeJobChoice?.(vehicle.__workshopOutstanding?.workCategories) || null : null;
  let workCategory = scheduleCategory;
  const categoryBays = workshopCategoryBays(normalizedStage, scheduleCategory);
  if (!categoryBays.length) {
    workshopNotify(`No bay in this view takes ${workshopDepartmentLayout()?.categoryLabel?.(scheduleCategory) || 'this'} work. Open that work category's planner. No booking was created.`);
    return;
  }
  const schedulableBays = workshopSchedulableBayNumbers(normalizedStage);
  const bay = categoryBays.find(number => schedulableBays.includes(number) && workshopBayAllocatedHours(normalizedStage, number, baseHours) > 0) || categoryBays[0];
  const hours = workshopBookingDestinationHours(returnedPlan, normalizedStage, bay, baseHours);
  if (!(hours > 0)) {
    workshopNotify('Bay efficiency is still loading. Refresh the planner and try again.');
    return;
  }
  // r417 (F32): the category's own bays first, then every other visible bay (asks to confirm).
  const otherBays = workshopVisibleBays(normalizedStage).filter(number => !categoryBays.includes(number));
  const bayOptions = categoryBays.map(number => `<option value="${number}" ${number === bay ? 'selected' : ''}>${escapeHtml(workshopBayChoiceLabel(normalizedStage,number))}</option>`).join('')
    + otherBays.map(number => `<option value="${number}">${escapeHtml(`${workshopBayChoiceLabel(normalizedStage,number)} (other work – asks to confirm)`)}</option>`).join('');
  // r450 (F63): the same list for the chosen Work (category only, or the whole job).
  const bayOptionsHtml = (bays, chosen) => bays.map(number => `<option value="${number}" ${number === chosen ? 'selected' : ''}>${escapeHtml(workshopBayChoiceLabel(normalizedStage,number))}</option>`).join('')
    + workshopVisibleBays(normalizedStage).filter(number => !bays.includes(number)).map(number => `<option value="${number}">${escapeHtml(`${workshopBayChoiceLabel(normalizedStage,number)} (other work – asks to confirm)`)}</option>`).join('');
  const layout = workshopDepartmentLayout();
  const workChoiceHtml = wholeJob ? `<label class="workshop-schedule-work"><span>Work</span><select name="workCategory" data-workshop-schedule-work>
          <option value="${escapeHtml(scheduleCategory)}" selected>${escapeHtml(`${layout?.categoryLabel?.(scheduleCategory) || scheduleCategory} only (${workshopExactDurationHours(categoryHours).toFixed(2)} h)`)}</option>
          <option value="${escapeHtml(wholeJob.code)}">${escapeHtml(`Whole job to one technician – ${wholeJob.categories.map(code => layout?.categoryLabel?.(code) || code).join(' + ')} (${workshopExactDurationHours(wholeJob.hours).toFixed(2)} h)`)}</option>
        </select></label>` : '';
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-schedule-overlay';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.setAttribute('aria-label', `Schedule ${pmbStageLabel(normalizedStage)} work`);
  overlay.innerHTML = `<section class="modal-card workshop-schedule-card">
    <button class="modal-close" type="button" data-workshop-schedule-cancel aria-label="Cancel">×</button>
    <header><h2>Schedule ${escapeHtml(pmbStageLabel(normalizedStage))} work</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</p></header>
    <form data-workshop-schedule-form>
      <div class="workshop-schedule-modes" role="tablist" aria-label="How to schedule">
        <button type="button" class="is-selected" data-workshop-schedule-mode="next" role="tab" aria-selected="true">Next available</button>
        <button type="button" data-workshop-schedule-mode="order" role="tab" aria-selected="false">Bay order</button>
      </div>
      <div class="workshop-schedule-choice">
        ${workChoiceHtml}
        <label><span>Bay</span><select name="bay">${bayOptions}</select></label>
      </div>
      <div data-workshop-schedule-next>
        <p class="workshop-schedule-note">This vehicle goes into the next free slot in the bay you pick. The job's hours set how long it stays.</p>
      </div>
      <div data-workshop-schedule-order hidden>
        <p class="workshop-schedule-note">Pick where this vehicle sits. The list is the bay order. The planner works out the times.</p>
        <div class="workshop-bay-order" data-workshop-bay-order></div>
      </div>
      ${wholeJob ? `<p class="workshop-schedule-note" data-workshop-whole-job-note hidden>One booking for one technician: their job card lists every unbooked line (${escapeHtml(wholeJob.categories.map(code => layout?.categoryLabel?.(code) || code).join(', '))}). Book QA separately first if someone else does QA.</p>` : ''}
      <p class="workshop-schedule-note">Later bookings in this bay move automatically, preserving their order and duration and skipping non-working days.${etaConstraint.required ? ` ${escapeHtml(etaConstraint.location)} earliest permitted booking date: ${escapeHtml(etaConstraint.earliestDateKey)}.` : ''}</p>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-schedule-cancel>Cancel</button><button class="primary" type="submit" data-workshop-schedule-add>Add to planner</button></div>
    </form>
  </section>`;
  const finish = () => {
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  };
  let mode = 'next';
  let placing = false;
  const jobHours = () => workshopExactDurationHours(baseHours) || baseHours;
  const selectedBay = () => Number(overlay.querySelector('[data-workshop-schedule-form]')?.elements?.bay?.value);
  const commit = async (startDateKey, startMinutes) => {
    if (placing) return false;
    placing = true;
    const commitClose = workshopBindScheduleCommitClose(window.__workshopDataService, finish);
    try {
      const scheduled = await scheduleWorkshopVehicle({
        planId,
        vehicleKeyValue,
        stage: normalizedStage,
        bay: selectedBay(),
        dateKey: startDateKey,
        startMinutes,
        hoursValue: jobHours(),
        assigneeValue: null,
        cascadeNewBooking: true,
        ...(workCategory === 'BUS_WHOLE_JOB' ? { workCategoryValue: workCategory, baseHoursValue: wholeJob.hours } : {}),
      });
      if (scheduled) commitClose.closeOnce();
      return !!scheduled;
    } finally {
      commitClose.restore();
      placing = false;
    }
  };
  const placeNext = async () => {
    const now = workshopNormalizeStartDate(new Date());
    const today = workshopDateKey(now);
    const earliest = workshopDateKeyNotBefore(today, etaConstraint.earliestDateKey || '');
    const notBefore = earliest === workshopDateKey(now) ? Math.max(0, workshopMinuteOffset(now)) : 0;
    const slot = workshopFirstAvailableStartSlot(normalizedStage, selectedBay(), earliest, jobHours(), workshopLoadPlans().filter(row => row.id !== planId), notBefore, 260, new Date(), [], null, '', vehicle);
    if (!slot) {
      workshopNotify('No free slot in this bay. No booking was saved.');
      return false;
    }
    return commit(slot.dateKey, slot.startMinutes);
  };
  const placeBefore = async targetId => {
    const place = workshopBayQueuePlacement(normalizedStage, selectedBay(), targetId, planId);
    if (place.kind === 'blocked') {
      workshopNotify('That job is already running and stays where it is. Choose a place behind it. No booking was saved.');
      return false;
    }
    return commit(place.dateKey, place.startMinutes);
  };
  const placeAtEnd = async () => {
    const place = workshopBayQueuePlacement(normalizedStage, selectedBay(), '', planId);
    if (place.kind === 'next') return placeNext();
    const slot = workshopFirstAvailableStartSlot(normalizedStage, selectedBay(), place.dateKey, jobHours(), workshopLoadPlans().filter(row => row.id !== planId), place.startMinutes, 260, place.reference, [], null, '', vehicle);
    if (!slot) {
      workshopNotify('No free slot after the last vehicle in this bay. No booking was saved.');
      return false;
    }
    return commit(slot.dateKey, slot.startMinutes);
  };
  const refreshOrder = () => {
    const host = overlay.querySelector('[data-workshop-bay-order]');
    const form = overlay.querySelector('[data-workshop-schedule-form]');
    if (!host || !form) return;
    const queue = workshopBayQueueRows(normalizedStage, Number(form.elements.bay.value), planId);
    host.innerHTML = workshopBayQueueHtml(queue);
    host.querySelectorAll?.('[data-workshop-insert-before]')?.forEach(button => button.addEventListener('click', () => { void placeBefore(button.dataset.workshopInsertBefore); }));
    host.querySelectorAll?.('[data-workshop-insert-end]')?.forEach(button => button.addEventListener('click', () => { void placeAtEnd(); }));
    const add = overlay.querySelector('[data-workshop-schedule-add]');
    if (add) add.hidden = mode === 'order' && queue.length > 0;
  };
  const applyMode = next => {
    mode = next === 'order' ? 'order' : 'next';
    overlay.querySelectorAll('[data-workshop-schedule-mode]').forEach(button => {
      const on = button.dataset.workshopScheduleMode === mode;
      button.classList.toggle('is-selected', on);
      button.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    const orderPanel = overlay.querySelector('[data-workshop-schedule-order]');
    const nextPanel = overlay.querySelector('[data-workshop-schedule-next]');
    if (orderPanel) orderPanel.hidden = mode !== 'order';
    if (nextPanel) nextPanel.hidden = mode === 'order';
    refreshOrder();
  };
  overlay.querySelectorAll('[data-workshop-schedule-cancel]').forEach(button => button.addEventListener('click', finish));
  overlay.querySelectorAll('[data-workshop-schedule-mode]').forEach(button => button.addEventListener('click', () => applyMode(button.dataset.workshopScheduleMode)));
  overlay.querySelector('[data-workshop-schedule-work]')?.addEventListener('change', event => {
    const form = overlay.querySelector('[data-workshop-schedule-form]');
    workCategory = event.currentTarget.value;
    const whole = workCategory === 'BUS_WHOLE_JOB';
    baseHours = whole ? wholeJob.hours : categoryHours;
    const workBays = workshopCategoryBays(normalizedStage, workCategory);
    const current = Number(form.elements.bay.value);
    const chosen = workBays.includes(current) ? current : workBays[0];
    form.elements.bay.innerHTML = bayOptionsHtml(workBays, chosen);
    form.elements.bay.value = String(chosen);
    const note = overlay.querySelector('[data-workshop-whole-job-note]');
    if (note) note.hidden = !whole;
    refreshOrder();
  });
  overlay.querySelector('[name="bay"]')?.addEventListener('change', refreshOrder);
  overlay.querySelector('[data-workshop-schedule-form]').addEventListener('submit', async event => {
    event.preventDefault();
    if (mode === 'order' && workshopBayQueueRows(normalizedStage, selectedBay(), planId).length) {
      workshopNotify('Choose Insert here in the bay order. No booking was saved.');
      return;
    }
    await placeNext();
  });
  overlay.addEventListener('click', event => { if (event.target === overlay) finish(); });
  document.body.appendChild(overlay);
  document.body.classList.add('modal-open');
  refreshOrder();
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
      endAt: '',
      technicianId: workshopTechnicianIdForEntry(entry),
    };
    if (!workshopRequireSchedulableCandidate(candidate)) return false;
    if (!workshopConfirmOtherDepartmentPlans(candidate, rows)) return false;
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
  if (!workshopConfirmOtherDepartmentPlans(candidate, latestRows)) return false;
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
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

// A vehicle may have work in multiple departments, but active time windows
// are authoritative and may never overlap. Half-open intervals keep exact
// back-to-back bookings valid.
function workshopOtherDepartmentOverlaps(candidate = {}, rows = []) {
  if (!candidate.vehicleKey) return [];
  const candidateStart = workshopEntryStart(candidate).getTime();
  const candidateEnd = workshopEntryEnd(candidate).getTime();
  return rows.filter(row => {
    if (row.id === candidate.id) return false;
    if (row.vehicleKey !== candidate.vehicleKey) return false;
    if (row.status === 'completed' || row.status === 'deleted') return false;
    // r548 (F162): this vehicle's own unallocated bookings (no bay) never block
    // the drop. The server moves them to follow the bay that was just booked.
    // A booking that already has a bay still blocks.
    const bayNumber = Number(row.bay);
    if (!Number.isInteger(bayNumber) || bayNumber < 1) return false;
    const rowStart = workshopEntryStart(row).getTime();
    const rowEnd = workshopEntryEnd(row).getTime();
    return workshopIntervalsOverlap(candidateStart, candidateEnd, rowStart, rowEnd);
  });
}

function workshopConfirmOtherDepartmentPlans(candidate = {}, rows = []) {
  if (!candidate.vehicleKey) return true;
  const overlapping = workshopOtherDepartmentOverlaps(candidate, rows);
  if (!overlapping.length) return true;
  const details = overlapping.slice(0, 8).map(row => {
    const when = parseIsoTimestamp(row.startAt);
    const whenLabel = when ? when.toLocaleString('en-AU', { timeZone: 'Australia/Perth', dateStyle: 'short', timeStyle: 'short' }) : 'time not set';
    const place = workshopBayText(row.stage, row.bay, true);
    return `• ${pmbStageLabel(row.stage)} · ${place} · ${whenLabel}`;
  }).join('\n');
  workshopNotify(`This vehicle already has an active booking in the requested time window:\n\n${details}\n\nChoose a back-to-back or non-overlapping time. No booking was changed.`);
  return false;
}

async function workshopScheduleSharedNewBooking({
  requestedCandidate = {},
  vehicleRef = null,
  stageCode = '',
  bayNumber = 0,
  scheduledStartAt = '',
  durationMinutes = 0,
  cascade = true,
} = {}, dispatchAction = workshopDispatchSharedAction) {
  const candidateStage = normalizePmbStage(requestedCandidate.stage);
  const requestedStage = normalizePmbStage(stageCode);
  if (!WORKSHOP_ELIGIBILITY_RUNTIME.workshopIsPlannerStage(candidateStage)
      || !WORKSHOP_ELIGIBILITY_RUNTIME.workshopIsPlannerStage(requestedStage)
      || candidateStage !== requestedStage) {
    workshopNotify('This work type does not have a Workshop Planner. No scheduling change was made.');
    return false;
  }
  const assignee = cleanNavisionText(requestedCandidate.assignee || '');
  const technicianRef = assignee ? workshopSelectedTechnicianRef(assignee) : null;
  if (assignee && !technicianRef) {
    workshopNotify(`"${assignee}" could not be matched to an active technician. Re-select an active technician or clear the selection. No booking was created.`);
    return false;
  }
  const technicianId = technicianRef ? String(technicianRef.technicianId || '') : null;
  if (assignee && !technicianId) {
    workshopNotify(`"${assignee}" does not have a valid stable technician ID. No booking was created.`);
    return false;
  }
  let candidate = { ...requestedCandidate, assignee, technicianId: technicianId || '' };
  if (!Array.isArray(candidate.workCategories)) {
    const row = typeof workshopVehicle === 'function' ? workshopVehicle(candidate.vehicleKey, requestedStage) : null;
    if (Array.isArray(row?.__workshopOutstanding?.workCategories)) candidate = { ...candidate, workCategories: row.__workshopOutstanding.workCategories };
  }
  // r450 (F63): a whole job keeps its category whichever bay it is dropped on.
  const bayCategory = candidate.workCategory === 'BUS_WHOLE_JOB' ? null : workshopBayAwareCategory(candidate, requestedStage, bayNumber);
  if (bayCategory) {
    candidate = { ...candidate, workCategory: bayCategory.code };
    durationMinutes = bayCategory.minutes;
    workshopNotify(`Bay ${bayNumber} is the ${bayCategory.label} bay, so this books the vehicle's ${bayCategory.label} work.`);
  }
  if (!workshopRequireSchedulableCandidate(candidate)) return false;
  if (!workshopConfirmOtherDepartmentPlans(candidate, workshopLoadPlans())) return false;
  const managedDispatch = dispatchAction === workshopDispatchSharedAction;
  const administratorRequest = workshopAdministratorCanMove() ? {
    vehicleId: vehicleRef.vehicleId,
    vehicleExpectedVersion: vehicleRef.version,
    stageCode,
    bayNumber,
    scheduledStartAt,
    durationMinutes,
    technicianId,
    requestId: workshopNewRequestId(),
    cascade,
    metadata: { source: cascade ? 'admin_unallocated_vehicle_pill' : 'planner_best_slot', reason: cascade ? 'website_drag_drop' : 'earliest_available_space', ...(candidate.workCategory ? {work_category:candidate.workCategory} : {}) },
  } : null;
  let result = administratorRequest
    ? await dispatchAction('administratorScheduleVehicle', administratorRequest,
      renderWorkshopPlanner, { suppressFailureAlert: true, suppressRender: true })
    : { ok: false, error: 'permission_denied' };
  if (administratorRequest && (!result || ['request_failed', 'no_response', 'runtime_failure'].includes(result.error))) {
    // Retry only an uncertain transport/runtime outcome and replay the exact
    // same object and request ID. The server receipt makes a committed first
    // attempt safe to replay; changed intent always requires a new drag.
    result = await dispatchAction('administratorScheduleVehicle', administratorRequest,
      renderWorkshopPlanner, { suppressFailureAlert: true, suppressRender: true });
  }
  if (result && result.ok === false && result.error === 'vehicle_version_conflict') {
    // The idempotency key binds the expected version and every other input.
    // Never mutate the body under the same intent or issue a second key from
    // an automatic retry. The refreshed record requires a new deliberate drag.
    result = { ...result, message: result.message || 'The vehicle changed before this exact drag could be committed. Drag it again from the refreshed Unallocated list.' };
  }
  const saved = !!(result && (result.ok === true || result.committed === true));
  if (managedDispatch) {
    if (!saved) workshopNotify(workshopDescribeSharedActionError(result));
    if (workshopAdministratorCanMove() && result?.ok === true) workshopRememberAdministratorMove(result);
    try { renderWorkshopPlanner(); } catch (error) { console.error('Workshop planner refresh failed after a scheduling command.', error); }
  }
  return saved;
}

async function workshopScheduleVehicleNextAvailable({ vehicleId = '', vehicleKeyValue = '', stage = '', hours = 0, workCategory = '', planId = '' } = {}) {
  if (stage === 'BUS_4X4' && workshopDepartmentLayout()?.category(workCategory)) workshopState().busBayGroup=workshopDepartmentLayout().category(workCategory).id;
  const normalizedStage = workshopRequirePlannerStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) {
    workshopNotify('This work type does not use a Workshop bay. No booking was created.');
    return false;
  }
  const service = window.__workshopDataService;
  if (workshopSharedModeActive() && service?.setScope) {
    const dateKey = workshopState().date || workshopDefaultOpenDateKey();
    await service.setScope({ stageCode: normalizedStage, dateFrom: dateKey, dateTo: dateKey });
    if (typeof service.loadSnapshot === 'function') await service.loadSnapshot('vehicle_detail_schedule_next');
  }
  const returnedPlan = planId ? workshopReturnedPlanForAction(planId) : null;
  if (planId && !returnedPlan) { workshopNotify('This returned booking changed. Refresh and try again.'); return false; }
  const vehicle = workshopVehicle(vehicleId || vehicleKeyValue, normalizedStage);
  if (!vehicle) {
    workshopNotify('This vehicle is not present in the authoritative outstanding-work queue for this station. Refresh the Control Board and try again. No booking was created.');
    renderWorkshopPlanner();
    return false;
  }
  if (!returnedPlan && workshopSharedModeActive() && vehicle.__workshopOutstanding?.scheduleEnabled !== true) {
    workshopNotify(`${workshopOutstandingDisabledReasonLabel(vehicle.__workshopOutstanding?.disabledReason)}. No booking was created.`);
    renderWorkshopPlanner();
    return false;
  }
  // In shared mode the operation projection is the booking authority. The
  // caller's hours may be stale (or may have been derived from editable DOM
  // inputs), so it must never override adjusted server lines.
  const duration = returnedPlan ? {hours:Number(returnedPlan.operationEstimateHours)||Number(returnedPlan.hours)} : workshopSchedulingDuration(vehicle, normalizedStage);
  if (workshopSharedModeActive() && !duration) {
    workshopNotify('Estimated hours are required before this vehicle can be scheduled into a bay. No booking was created.');
    return false;
  }
  const authoritativeStageHours = duration?.hours || workshopCalculatedStageHours(vehicle, normalizedStage);
  const rawEstimate = workshopSharedModeActive()
    ? (authoritativeStageHours || pmbBayHours(vehicle) || workshopDefaultBookingHours())
    : (Number(hours) > 0 ? Number(hours) : authoritativeStageHours || pmbBayHours(vehicle) || workshopDefaultBookingHours());
  const estimate = workshopSharedModeActive()
    ? (workshopExactDurationHours(rawEstimate) || workshopClampDurationHours(rawEstimate))
    : workshopClampDurationHours(rawEstimate);
  if (workshopSharedModeActive() && !workshopSchedulableBayNumbers(normalizedStage).some(bay => workshopBayAllocatedHours(normalizedStage, bay, estimate) > 0)) {
    workshopNotify('Bay efficiency is still loading or no active bay is available. Refresh the planner and try again.');
    return false;
  }
  const etaConstraint = workshopVehicleEtaConstraint(vehicle);
  if (etaConstraint.required && !etaConstraint.ok) {
    workshopRequireEtaSchedule(vehicle, new Date(0));
    return false;
  }
  let vehicleWindows = [];
  if (workshopSharedModeActive()) {
    const ref = workshopSharedVehicleRef({vehicleKey: vehicleKey(vehicle), sharedVehicleId: vehicle.sharedVehicleId || vehicle.__emailVehicleId || vehicleId});
    try {
      if (!ref?.vehicleId || !window.PDC_VEHICLE_HANDOVER) throw new Error('Cross-station booking checks are unavailable. Refresh and try again.');
      vehicleWindows = (await window.PDC_VEHICLE_HANDOVER.read(ref.vehicleId)).windows;
    } catch (error) { workshopNotify(error.message); return false; }
  }
  const nextOperationalMoment = workshopNormalizeStartDate(new Date());
  const today = workshopDateKey(nextOperationalMoment);
  const earliestDate = workshopDateKeyNotBefore(today, etaConstraint.earliestDateKey || '');
  let slot = null;
  if (workshopSharedModeActive() && service?.setScope) {
    // The authorised station snapshot permits a maximum 31-day date offset.
    // Search consecutive authoritative windows so later days are never
    // mistaken for empty and every confirmed active bay is compared.
    let windowStart = earliestDate;
    for (let windowIndex = 0; windowIndex < 9 && !slot; windowIndex += 1) {
      const windowEnd = workshopCalendarDateKeyOffset(windowStart, 31);
      await service.setScope({ stageCode: normalizedStage, dateFrom: windowStart, dateTo: windowEnd });
      const notBeforeMinutes = windowIndex === 0 && windowStart === today
        ? Math.max(0, workshopMinuteOffset(nextOperationalMoment))
        : 0;
      slot = workshopBestStageSlot(normalizedStage, windowStart, estimate, workshopLoadPlans().filter(row => row.id !== planId), notBeforeMinutes, windowEnd, vehicleWindows, pmbBayMechanic(vehicle) || '', null, returnedPlan, vehicle);
      windowStart = workshopCalendarDateKeyOffset(windowEnd, 1);
    }
  } else {
    const notBeforeMinutes = earliestDate === today ? Math.max(0, workshopMinuteOffset(nextOperationalMoment)) : 0;
    slot = workshopBestStageSlot(normalizedStage, earliestDate, estimate, workshopLoadPlans().filter(row => row.id !== planId), notBeforeMinutes, '', vehicleWindows, pmbBayMechanic(vehicle) || '', null, returnedPlan, vehicle);
  }
  if (!slot) {
    workshopNotify('No active bay has an available operational slot in the searched planning horizon. No booking was created.');
    return false;
  }
  const state = workshopState();
  state.stage = normalizedStage;
  state.date = slot.dateKey;
  workshopSaveView(state);
  if (workshopSharedModeActive() && service?.setScope) {
    await service.setScope({ stageCode: normalizedStage, dateFrom: slot.dateKey, dateTo: slot.dateKey });
  }
  return scheduleWorkshopVehicle({
    planId,
    vehicleKeyValue: vehicleId || vehicleKeyValue,
    stage: normalizedStage,
    bay: slot.bay,
    dateKey: slot.dateKey,
    startMinutes: slot.startMinutes,
    hoursValue: estimate,
    preferRequestedTime: true,
    // The chosen space is already free; do not move unrelated later jobs.
    cascadeNewBooking: false,
  });
}

async function scheduleWorkshopVehicle({ planId = '', vehicleKeyValue = '', stage = '', bay = 0, dateKey = '', startMinutes = 0, hoursValue = null, assigneeValue = null, preferRequestedTime = false, cascadeNewBooking = true, workCategoryValue = '', baseHoursValue = 0 } = {}) {
  const rows = workshopLoadPlans();
  const existing = rows.find(entry => entry.id === planId) || rows.find(entry => entry.id === workshopPlanId(vehicleKeyValue, stage));
  if (planId && !existing) { workshopNotify('This booking changed. Refresh and try again.'); return false; }
  const vehicle = workshopVehicle(existing?.vehicleKey || vehicleKeyValue, stage);
  if (!vehicle) return false;
  if (!existing && workshopSharedModeActive() && vehicle.__workshopOutstanding?.scheduleEnabled !== true) {
    workshopNotify(`${workshopOutstandingDisabledReasonLabel(vehicle.__workshopOutstanding?.disabledReason)}. No booking was created.`);
    renderWorkshopPlanner();
    return false;
  }
  if (existing && ['started', 'stoppage', 'completed'].includes(existing.status) && !workshopPlanStoppedUnallocated(existing)) {
    workshopNotify('Started, stopped and completed jobs stay fixed on the planner. Resolve the live job before rescheduling it.');
    return false;
  }
  const normalizedStage = workshopRequirePlannerStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage) || Number(bay) < 1 || Number(bay) > workshopStageBayCount(normalizedStage)) {
    workshopNotify('Choose a valid workshop bay.');
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
      workshopNotify(messages[availability] || 'This bay is not currently available for new bookings.');
      return false;
    }
  }
  const start = workshopDateAtOffset(dateKey, startMinutes);
  if (!workshopRequireEtaSchedule(vehicle, start)) return false;
  // r450 (F63): a new whole job lasts the hours of every unbooked Bus line (Schedule window).
  const wholeJobRequested = !existing && normalizedStage === 'BUS_4X4' && workCategoryValue === 'BUS_WHOLE_JOB' && Number(baseHoursValue) > 0;
  const duration = wholeJobRequested ? { hours: Number(baseHoursValue) }
    : existing?.workCategory && Number(existing.operationEstimateHours) > 0
    ? { hours: Number(existing.operationEstimateHours) }
    : workshopSchedulingDuration(vehicle, normalizedStage);
  if (workshopSharedModeActive() && !duration) {
    workshopNotify('Estimated hours are required before this vehicle can be scheduled into a bay. No booking was created.');
    return false;
  }
  const requestedHours = Number(hoursValue);
  const defaultHours = Number.isFinite(requestedHours) && requestedHours > 0
    ? requestedHours
    : existing?.hours || workshopCalculatedStageHours(vehicle, normalizedStage) || pmbBayHours(vehicle) || workshopDefaultBookingHours();
  const canonicalSharedHours = workshopSharedModeActive()
    ? workshopBookingDestinationHours(existing, normalizedStage, bay, duration.hours)
    : 0;
  if (workshopSharedModeActive() && !(canonicalSharedHours > 0)) {
    workshopNotify('Bay efficiency is still loading. Refresh the planner and try again. No booking was changed.');
    return false;
  }
  const hours = canonicalSharedHours || workshopClampDurationHours(defaultHours);
  const requestedCandidate = {
    ...(existing || {}),
    id: existing?.id || '__new_workshop_booking__',
    calendarVehicle: vehicle,
    workCategory: existing?.workCategory || (wholeJobRequested ? workCategoryValue : '') || vehicle.__workshopOutstanding?.workCategory || '',
    stage: normalizedStage,
    bay: Number(bay),
    status: 'planned',
    startAt: start.toISOString(),
    endAt: '',
    hours,
    assignee: assigneeValue === null
      ? existing?.assignee || workshopBayMechanic(normalizedStage, bay) || pmbBayMechanic(vehicle) || ''
      : cleanNavisionText(assigneeValue || ''),
  };
  if (!workshopConfirmOtherDepartmentPlans(requestedCandidate, workshopLoadPlans())) return false;
  if (workshopSharedModeActive()) {
    const durationMinutes = Math.round(hours * 60);
    if (existing && existing.sharedBookingId) {
      if (!workshopRequireSchedulableCandidate(requestedCandidate)) return false;
      const movingBetweenBays = normalizePmbStage(existing.stage) !== normalizedStage || Number(existing.bay) !== Number(bay);
      const cascade = preferRequestedTime && movingBetweenBays;
      const action = workshopAdministratorCanMove()
        ? 'administratorMoveBooking'
        : (cascade ? 'cascadeMoveBooking' : 'moveBooking');
      const result = await workshopDispatchSharedAction(action, {
        bookingId: existing.sharedBookingId,
        expectedVersion: existing.sharedVersion,
        stageCode: normalizedStage,
        bayNumber: Number(bay),
        scheduledStartAt: start.toISOString(),
        durationMinutes,
        requestId: workshopNewRequestId(),
        cascade,
        metadata: { source: preferRequestedTime ? 'planner_chip_drop' : 'planner_booking_move', reason: 'website_drag_drop' },
      });
      if (workshopAdministratorCanMove() && result?.ok === true) workshopRememberAdministratorMove(result);
      return !!(result && (result.ok === true || result.committed === true));
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
      cascade: cascadeNewBooking,
    });
  }
  if (!workshopRequireSchedulableCandidate(requestedCandidate)) return false;
  // Parts completion remains an RFT gate, not an entry gate for Tint or Tyre. Planning itself never moves a vehicle into a physical bay.
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
    workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
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
    { stage: pmbStageLabel(normalizedStage), bay: `Bay ${resolvedCandidate.bay}`, startAt: resolvedCandidate.startAt, hours: resolvedCandidate.hours, assignee: resolvedCandidate.assignee || 'Unassigned' },
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
  if (!workshopRequirePlannerStage(entry.stage)) return;
  const data = new FormData(form);
  const start = workshopParsePerthLocalInput(String(data.get('startAt') || entry.startAt || ''));
  if (Number.isNaN(start.getTime()) || !workshopIsConfiguredWorkingDay(start)) {
    workshopNotify('Choose a date in the configured workshop working week.');
    return;
  }
  const normalizedStart = new Date(start);
  const requestedHours = Number(data.get('hours') || entry.hours || workshopDefaultBookingHours());
  if (!Number.isFinite(requestedHours) || requestedHours <= 0) {
    workshopNotify('Enter planned hours greater than zero. There is no maximum workshop duration.');
    return;
  }
  const nextAssignee = cleanNavisionText(data.get('assignee') || '');
  const exactRequestedHours = workshopExactDurationHours(requestedHours);
  if (!exactRequestedHours) {
    workshopNotify('Enter a positive duration of at least one whole operational minute.');
    return;
  }
  const requestedDetailCandidate = {
    ...entry,
    endAt: '',
    startAt: ['started', 'stoppage'].includes(entry.status) ? entry.startAt : normalizedStart.toISOString(),
    hours: exactRequestedHours,
    assignee: nextAssignee,
  };
  if (!workshopRequireSchedulableCandidate(requestedDetailCandidate)) return;
  if (!workshopConfirmOtherDepartmentPlans(requestedDetailCandidate, rows)) return;
  if (workshopSharedModeActive()) {
    const nextStartAt = ['started', 'stoppage'].includes(entry.status) ? entry.startAt : normalizedStart.toISOString();
    const nextDurationMinutes = Math.round(exactRequestedHours * 60);
    const currentDurationMinutes = Number(entry.scheduledDurationMinutes) > 0
      ? Number(entry.scheduledDurationMinutes)
      : workshopExactDurationMinutesFromHours(entry.hours);
    const extendsDuration = nextDurationMinutes > currentDurationMinutes;
    if (extendsDuration && Date.parse(nextStartAt) !== Date.parse(entry.startAt)) {
      workshopNotify('To preserve an atomic bay cascade, save the new start time first, then extend the duration.');
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
        workshopNotify(`"${nextAssignee}" could not be matched to an active technician. The booking was moved, but the technician assignment was not changed. Re-select the technician and save again.`);
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
    workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
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

function workshopDescribeStartActionError(result) {
  if (result?.error === 'vehicle_overlap') {
    return 'A protected booking for this vehicle could not be moved safely. No changes were saved. Ask the controller to check that work before starting this job.';
  }
  if (result?.error === 'technician_overlap') {
    return 'This mechanic already has another running or stopped job. No changes were saved. Complete or release that work before starting another.';
  }
  if (['no_response','runtime_failure','request_failed'].includes(result?.error) || !result) {
    return 'Start could not be confirmed. Refresh the planner to check this job before trying again.';
  }
  return workshopDescribeSharedActionError(result);
}

async function startWorkshopPlan(planId = '') {
  if (WORKSHOP_PENDING_STARTS.has(planId)) return;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (workshopSharedModeActive()) {
    // Start is a server transaction: it prioritises this job, moves unstarted
    // vehicle/queue bookings, and protects live work and admin blocks. A cached
    // local conflict check cannot decide whether the current schedule is safe.
    const bookingActionToken = workshopBeginBookingAction(entry.sharedBookingId || entry.id, 'startWork');
    if (!bookingActionToken) return;
    WORKSHOP_PENDING_STARTS.add(planId);
    workshopStartFeedback={stage:entry.stage,message:'Starting job… Checking the schedule and moving affected unstarted bookings where needed.'};
    try {
      renderWorkshopPlanner();
      const result=await workshopDispatchSharedAction('startWork', {
        bookingId: entry.sharedBookingId || entry.id,
        expectedVersion: entry.sharedVersion,
      }, renderWorkshopPlanner, {suppressRender:true,suppressFailureAlert:true,bookingActionToken});
      const shifted=result?.start_priority===true&&Number.isInteger(result.shifted_count)&&result.shifted_count>=0?result.shifted_count:null;
      workshopStartFeedback={stage:entry.stage,message:result?.ok===true
        ? result.refreshRequired===true?'The job start was confirmed, but the planner could not refresh yet. Refresh the planner before making another change.':result.already_started?'This job is already running on the planner.':`Job started.${shifted===null?'':shifted===0?' No other bookings needed to move.':` ${shifted} affected booking${shifted===1?'':'s'} moved later.`}`
        : workshopDescribeStartActionError(result)};
      if(result?.ok!==true) workshopNotify(workshopStartFeedback.message);
      return result;
    } finally {
      workshopEndBookingAction(bookingActionToken);
      WORKSHOP_PENDING_STARTS.delete(planId);
      renderWorkshopPlanner();
    }
  }
  const alreadyStarted = workshopStartedBayConflict(entry, rows);
  // Extracted Start tests may omit workshopBayChoiceLabel; fall back to Bay N.
  const startedBayLabel = (() => {
    try { if (typeof workshopBayChoiceLabel === 'function') return workshopBayChoiceLabel(entry.stage, entry.bay); } catch (_error) {}
    if (typeof globalThis.workshopBayChoiceLabel === 'function') return globalThis.workshopBayChoiceLabel(entry.stage, entry.bay);
    return `Bay ${entry.bay}`;
  })();
  if (alreadyStarted) {
    workshopNotify(`${startedBayLabel} already has a started job. Stop or complete that job before starting another in this bay.`);
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
  const auditDetails = { stage: pmbStageLabel(entry.stage), bay: startedBayLabel, hours: entry.hours, assignee: entry.assignee || 'Unassigned' };
  const persisted = await assignPmbVehicleToBay(entry.vehicleKey, entry.stage, entry.bay, next.startAt, {
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
  if (!persisted) return;
  workshopState().date = workshopDateKey(currentStart);
  workshopSaveView(workshopState());
  offerSalespersonChangeEmail(vehicle, {
    title: `${pmbStageLabel(entry.stage)} job started`,
    subject: 'PDC workshop job started',
    details: [
      `${pmbStageLabel(entry.stage)} work started at ${currentStart.toLocaleString('en-AU', { timeZone: 'Australia/Perth', dateStyle: 'short', timeStyle: 'short' })}.`,
      `${startedBayLabel}${entry.assignee ? ` · Mechanic: ${entry.assignee}` : ''}.`,
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
    const bookingActionToken = workshopBeginBookingAction(entry.sharedBookingId || entry.id, 'completeWork');
    if (!bookingActionToken) return;
    try {
      await workshopDispatchSharedAction('completeWork', {
        bookingId: entry.sharedBookingId || entry.id,
        expectedVersion: entry.sharedVersion,
        workKey: entry.stage,
      }, renderWorkshopPlanner, { bookingActionToken });
    } finally { workshopEndBookingAction(bookingActionToken); }
    return;
  }
  if (!workshopRequireOperatorProfile()) return;
  if (!['started', 'stoppage'].includes(entry.status)) {
    workshopNotify('Use “Start job” first so the workshop start time and salesperson update are recorded.');
    return;
  }
  if (Number(pmbBayNumber(vehicle, entry.stage)) !== Number(entry.bay)) {
    workshopNotify('Use “Start in bay” first. This keeps the live physical-bay record accurate before work is completed.');
    return;
  }
  const completedMoment = workshopLatestWorkMoment(new Date());
  const elapsedMinutes = workshopWorkMinutesBetween(workshopEntryStart(entry), completedMoment);
  const openStoppageMinutes = entry.status === 'stoppage' && entry.stoppageAt
    ? workshopWorkMinutesBetween(parseIsoTimestamp(entry.stoppageAt), completedMoment)
    : 0;
  const actualMinutes = Math.max(0, elapsedMinutes - Number(entry.stoppageMinutes || 0) - openStoppageMinutes);
  const actualHours = actualMinutes / 60;
  const completed = completePmbBayWork(entry.vehicleKey, entry.stage, {
    keys: [WORKSHOP_PLAN_STORAGE_KEY],
    afterComplete: (refreshed, def) => {
      const completedAt = refreshed[def.completeAtKey] || nowIsoString();
      const operator = getCurrentOperatorName();
      const clearUpdates = workshopOwnedBlockClearUpdates(entry, refreshed, completedAt, operator);
      if (Object.keys(clearUpdates).length && !saveVehicleEdits(entry.vehicleKey, clearUpdates, { render: false })) {
        throw new Error('The workshop STOPPAGE could not be cleared safely.');
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
      <header><h2>Record workshop STOPPAGE</h2><p>${escapeHtml(displayStockNumber(vehicle) || vehicleJobcardNumber(vehicle) || 'Vehicle')} · ${escapeHtml(workshopBayChoiceLabel(entry.stage, entry.bay))}</p></header>
      <label class="workshop-return-reason"><span>STOPPAGE reason</span><input type="text" data-workshop-stop-reason value="${escapeHtml(entry.stoppageReason || '')}" autocomplete="off"></label>
      <div class="edit-actions"><button class="secondary" type="button" data-workshop-stop-cancel>Cancel</button><button class="primary" type="button" data-workshop-stop-apply>Record STOPPAGE</button></div>
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
        workshopNotify('Enter the STOPPAGE reason.');
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
        workshopNotify('Enter the override reason.');
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

async function pauseBayForOtherJob(planId = '') {
  const rows = typeof workshopLoadPlans === 'function' ? workshopLoadPlans() : [];
  const live = rows.find(row => row.id === planId);
  if (!live) return;
  if (typeof workshopSharedModeActive !== 'function' || !workshopSharedModeActive()) {
    workshopNotify('Pausing a job for another one needs the live planner. No change was made.');
    return;
  }
  const choices = workshopPauseForOtherChoices(live, rows);
  if (!choices.length) {
    workshopNotify('There is no other unstarted job on this station to start in this bay. This job stays where it is.');
    return;
  }
  const lines = choices.map((row, index) => `${index + 1}. ${row.vehicleKey || 'Job'}`).join('\n');
  const answer = typeof window !== 'undefined' && typeof window.prompt === 'function'
    ? window.prompt(`Pause this job. Its remaining time moves behind the job you pick. Neither job card is closed.\n${lines}\nType a number from 1 to ${choices.length}.`, '')
    : null;
  const pick = Number(String(answer || '').trim());
  const chosen = choices[pick - 1];
  if (!chosen) return;
  await workshopDispatchSharedAction('pauseBayForOther', {
    bookingId: chosen.sharedBookingId,
    expectedVersion: chosen.sharedVersion,
    liveBookingId: live.sharedBookingId,
    liveExpectedVersion: live.sharedVersion,
  });
}

async function stopWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (workshopSharedModeActive()) {
    if (entry.status !== 'started') {
      workshopNotify('Start the job before recording a workshop STOPPAGE.');
      return;
    }
    const bookingActionToken = workshopBeginBookingAction(entry.sharedBookingId || entry.id, 'stopWork');
    if (!bookingActionToken) return;
    try {
      const reason = await workshopStoppageReasonModal(entry, vehicle);
      if (!reason) return;
      await workshopDispatchSharedAction('stopWork', {
        bookingId: entry.sharedBookingId || entry.id,
        expectedVersion: entry.sharedVersion,
        reason,
      }, renderWorkshopPlanner, { bookingActionToken });
    } finally { workshopEndBookingAction(bookingActionToken); }
    return;
  }
  if (!workshopRequireOperatorProfile()) return;
  if (entry.status !== 'started') {
    workshopNotify('Start the job before recording a workshop STOPPAGE.');
    return;
  }
  const reason = await workshopStoppageReasonModal(entry, vehicle);
  if (!reason) return;
  const now = nowIsoString();
  const operator = getCurrentOperatorName();
  const next = { ...entry, status: 'stoppage', stoppageReason: reason, stoppageAt: now, updatedAt: now };
  const persisted = workshopPersistVehiclePlanAction(
    'Record workshop STOPPAGE',
    workshopCascadePlans(rows.map(row => row.id === entry.id ? next : row)).rows,
    vehicle,
    workshopOwnedBlockUpdates(entry, reason, now, operator),
    'Workshop job STOPPAGE recorded',
    { stage: pmbStageLabel(entry.stage), reason, by: operator },
  );
  if (!persisted) return;
  offerSalespersonChangeEmail(vehicle, {
    title: `${pmbStageLabel(entry.stage)} job STOPPAGE`,
    subject: 'PDC workshop STOPPAGE',
    details: [`The workshop job has stopped: ${reason}.`, `${workshopBayChoiceLabel(entry.stage, entry.bay)}${entry.assignee ? ` · Mechanic: ${entry.assignee}` : ''}.`],
  });
  renderWorkshopPlanner();
}

async function resumeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle || entry.status !== 'stoppage') return;
  if (workshopSharedModeActive()) {
    const bookingActionToken = workshopBeginBookingAction(entry.sharedBookingId || entry.id, 'resumeWork');
    if (!bookingActionToken) return;
    try {
      await workshopDispatchSharedAction('resumeWork', {
        bookingId: entry.sharedBookingId || entry.id,
        expectedVersion: entry.sharedVersion,
      }, renderWorkshopPlanner, { bookingActionToken });
    } finally { workshopEndBookingAction(bookingActionToken); }
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
  if (workshopActivePointerResize) return;
  const planId = handle.dataset.workshopResizePlan;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const chip = handle.closest('[data-workshop-plan-id]');
  const lane = handle.closest('[data-workshop-drop-bay]');
  if (!entry || !chip || !lane) return;
  const resizeToken = {};
  workshopActivePointerResize = resizeToken;
  const originX = event.clientX;
  const originalDurationMinutes = Number(entry.scheduledDurationMinutes) > 0
    ? Number(entry.scheduledDurationMinutes)
    : workshopExactDurationMinutesFromHours(entry.hours);
  const originalHours = originalDurationMinutes / 60;
  const segment = workshopEntrySegmentForDate(entry, workshopState().date);
  const pointerId = event.pointerId;
  let previewFrame = null;
  let pendingMove = null;
  let paintedHours = null;
  const paintMove = moveEvent => {
    if (chip.isConnected === false || lane.isConnected === false) return;
    const deltaMinutes = workshopSnapMinutes(((moveEvent.clientX - originX) / Math.max(1, lane.getBoundingClientRect().width)) * WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
    const hours = Math.max(1, originalDurationMinutes + deltaMinutes) / 60;
    if (paintedHours === hours) return;
    paintedHours = hours;
    const visibleMinutes = Math.min(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes - (segment?.start || 0), hours * 60);
    chip.style.setProperty('--plan-width', `${(visibleMinutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%`);
    chip.dataset.previewHours = String(hours);
  };
  const cancelFrame = () => {
    if (previewFrame !== null && typeof window !== 'undefined') window.cancelAnimationFrame?.(previewFrame);
    previewFrame = null;
    pendingMove = null;
  };
  const onMove = moveEvent => {
    if (pointerId != null && moveEvent.pointerId !== pointerId) return;
    pendingMove = { clientX: moveEvent.clientX };
    if (previewFrame !== null) return;
    if (typeof window === 'undefined' || typeof window.requestAnimationFrame !== 'function') { paintMove(pendingMove); return; }
    previewFrame = window.requestAnimationFrame(() => {
      const pending = pendingMove;
      previewFrame = null;
      pendingMove = null;
      if (pending) paintMove(pending);
    });
  };
  const cancel = cancelEvent => {
    if (pointerId != null && cancelEvent?.pointerId != null && cancelEvent.pointerId !== pointerId) return;
    cancelFrame();
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
    document.removeEventListener('pointercancel', cancel);
    if (workshopActivePointerResize === resizeToken) workshopActivePointerResize = null;
    if (cancelEvent?.type === 'pointercancel') {
      delete chip.dataset.previewHours;
      renderWorkshopPlanner();
    }
  };
  const onUp = async upEvent => {
    if (pointerId != null && upEvent?.pointerId !== pointerId) return;
    const finalMove = Number.isFinite(upEvent?.clientX) ? upEvent : pendingMove;
    cancelFrame();
    if (finalMove) paintMove(finalMove);
    cancel();
    const hours = Number(chip.dataset.previewHours || entry.hours);
    delete chip.dataset.previewHours;
    const candidate = { ...entry, hours, endAt: '', updatedAt: nowIsoString() };
    if (!workshopRequireSchedulableCandidate(candidate) || !workshopConfirmOtherDepartmentPlans(candidate, rows)) {
      renderWorkshopPlanner();
      return;
    }
    if (workshopSharedModeActive()) {
      const nextHours = workshopExactDurationHours(hours);
      const currentDurationMinutes = originalDurationMinutes;
      const nextDurationMinutes = workshopExactDurationMinutesFromHours(nextHours);
      if (nextDurationMinutes === currentDurationMinutes) {
        renderWorkshopPlanner();
        return;
      }
      if (nextDurationMinutes < currentDurationMinutes) {
        // Shortening a chip is a normal resize: it must not enter the
        // extend-cascade contract, whose shift is only defined for a
        // positive duration increase. The old path sent operation=extend
        // with shift=0 and the server correctly rejected the mismatch.
        await workshopDispatchSharedAction('resizeBooking', {
          bookingId: entry.sharedBookingId || entry.id,
          expectedVersion: entry.sharedVersion,
          durationMinutes: nextDurationMinutes,
          metadata: { source: 'workshop_chip_resize' },
        });
        return;
      }
      await workshopDispatchSharedAction('cascadeSchedule', {
        operation: 'extend',
        targetId: entry.sharedBookingId || entry.id,
        targetExpectedVersion: entry.sharedVersion,
        stageCode: entry.stage,
        bayNumber: Number(entry.bay),
        scheduledStartAt: entry.startAt,
        durationMinutes: nextDurationMinutes,
        shiftMinutes: nextDurationMinutes - currentDurationMinutes,
      });
      return;
    }
    const latestRows = workshopLoadPlans();
    const latestEntry = latestRows.find(row => row.id === entry.id);
    if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
      workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
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
  document.addEventListener('pointercancel', cancel);
}

function workshopWeeklyCardHtml(entry = {}, dateKey = '') {
  const vehicle = workshopVehicle(entry.vehicleKey);
  const segment = workshopEntrySegmentForDate(entry, dateKey);
  if (!vehicle || !segment) return '';
  const top = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const height = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
  const draggable = entry.status !== 'completed';
  const savedTechnician = cleanNavisionText(entry.assignee || '')
    || (typeof workshopTechnicianNameById === 'function' ? workshopTechnicianNameById(entry.technicianId) : '');
  const assignee = savedTechnician || workshopBayMechanic(entry.stage, entry.bay) || '';
  const statusLabel = entry.status === 'stoppage' ? 'STOPPAGE' : entry.status === 'started' ? 'LIVE' : 'PLANNED';
  return `<article class="workshop-week-card ${entry.status !== 'planned' ? 'is-live' : ''} ${segment.usesConfiguredOvertime ? 'uses-configured-overtime' : ''} ${segment.historicalOnClosure ? 'historical-on-closure' : ''}" ${draggable ? 'draggable="true"' : ''} data-workshop-week-plan="${escapeHtml(entry.id)}" data-workshop-job-vehicle="${escapeHtml(entry.vehicleKey)}" style="--week-top:${top}%;--week-height:${height}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · ${entry.hours} hours${segment.usesConfiguredOvertime ? ' · configured overtime' : ''}${segment.historicalOnClosure ? ' · historical booking on closure' : ''}${entry.status === 'completed' ? ' · completed history stays fixed' : entry.status === 'planned' ? ' · drag to another day/time' : ' · drag to move this live job safely'}`)}">
    <strong>JC ${escapeHtml(vehicleJobcardNumber(vehicle) || 'TBA')}</strong>
    <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</span>
    <small>${escapeHtml(`${statusLabel}${assignee ? ` · ${assignee}` : ''}`)}</small>
    <em>${escapeHtml(entry.hours)}h</em>
    ${entry.helperAssignments?.length ? `<small>${escapeHtml(workshopBookingTeamLabel(entry))}</small>` : ''}
  </article>`;
}

function workshopWeeklyTimeGuideHtml() {
  const tickCount = Math.floor(WORKSHOP_PLANNER_CONFIG.dayLengthMinutes / 120) + 1;
  return Array.from({ length: tickCount }, (_, index) => {
    const minutes = index * 120;
    return `<span style="top:${(minutes / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100}%">${escapeHtml(workshopTimeLabelFromMinutes(minutes))}</span>`;
  }).join('');
}

function workshopWeeklyAdminBlockHtml(block = {}, dateKey = '') {
  const segments = workshopAdminBlockSegments(block, dateKey);
  if (!segments.length) return '';
  const label = block.label || ({ training: 'Training', sick: 'Sick leave', admin: 'Admin downtime' }[block.type] || 'Admin downtime');
  const hours = Number(block.durationMinutes || 0) / 60;
  const totalLabel = Number.isInteger(hours) ? `${hours}h total` : `${hours.toFixed(2).replace(/0+$/, '').replace(/\.$/, '')}h total`;
  return segments.map((segment, index) => {
    const top = (segment.start / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    const height = ((segment.end - segment.start) / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * 100;
    const continuation = segment.continuesFromPrevious ? ' · CONTINUED' : '';
    const continues = segment.continuesNext ? ' · continues next valid work interval' : '';
    const text = `${workshopTimeLabelFromMinutes(segment.start)}–${workshopTimeLabelFromMinutes(segment.end)} · ${index === 0 ? totalLabel : 'continued'}${continuation}${continues}`;
    return `<article class="workshop-week-admin-block${segment.continuesFromPrevious ? ' continues-from-previous' : ''}${segment.continuesNext ? ' continues-next' : ''}" aria-label="${escapeHtml(`${label}, ${text}`)}" style="--week-top:${top}%;--week-height:${height}%;"><strong>ADMIN · ${escapeHtml(label)}${index > 0 ? ' · CONTINUED' : ''}</strong><small>${escapeHtml(text)}</small>${workshopAdminBlockCanMutate() && index === 0 ? `<button type="button" class="small-button" data-workshop-week-admin-block-rename="${escapeHtml(block.id)}">Rename</button>` : ''}</article>`;
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
  if (!workshopRequireSchedulableCandidate(candidate) || !workshopConfirmOtherDepartmentPlans(candidate, rows)) return;
  if (workshopSharedModeActive()) {
    const moved = await scheduleWorkshopVehicle({ planId, stage, bay, dateKey, startMinutes, preferRequestedTime: true });
    if (moved) openWorkshopWeeklyView(stage, bay, weekKey || dateKey);
    return;
  }
  const latestRows = workshopLoadPlans();
  const latestEntry = latestRows.find(row => row.id === entry.id);
  if (!latestEntry || latestEntry.updatedAt !== entry.updatedAt) {
    workshopNotify('This workshop plan changed in another tab. The latest plan has been reloaded; please try again.');
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
    { stage: pmbStageLabel(resolvedCandidate.stage), bay: `Bay ${resolvedCandidate.bay}`, startAt: resolvedCandidate.startAt },
  );
  workshopState().selectedPlanId = resolvedCandidate.id;
  workshopState().date = workshopEntryDate(resolvedCandidate);
  workshopSaveView(workshopState());
  renderWorkshopPlanner();
  openWorkshopWeeklyView(stage, bay, weekKey || dateKey);
}

let workshopWeeklyLoadSequence = 0;
async function workshopLoadWeeklySnapshot(stage, dates) {
  const sequence = ++workshopWeeklyLoadSequence;
  const service = window.__workshopDataService;
  if (!workshopSharedModeActive() || !service?.getScope?.()?.stageCode) return true;
  const scope = { stageCode: stage, dateFrom: workshopDateKey(dates[0]), dateTo: workshopDateKey(dates[dates.length - 1]) };
  try {
    await service.setScope(scope);
  } catch (_) { return false; }
  if (sequence !== workshopWeeklyLoadSequence || window.__workshopDataService !== service) return false;
  const current = service.getScope?.();
  const snapshot = service.getTrustedSnapshot?.();
  return Boolean(snapshot && current?.stageCode === scope.stageCode
    && current.dateFrom === scope.dateFrom && current.dateTo === scope.dateTo
    && snapshot.scope?.stage_code === scope.stageCode
    && snapshot.scope.date_from === scope.dateFrom && snapshot.scope.date_to === scope.dateTo);
}

async function openWorkshopWeeklyView(stage = '', bay = 1, anchorDate = '') {
  const normalizedStage = normalizePmbStage(stage);
  if (!WORKSHOP_STAGE_SEQUENCE.includes(normalizedStage)) return;
  document.querySelector('[data-workshop-week-overlay]')?.remove();
  if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  const weekStart = workshopWeekStart(anchorDate || workshopState().date);
  const dates = workshopWeekDates(weekStart);
  if (!await workshopLoadWeeklySnapshot(normalizedStage, dates)) return;
  const plans = workshopCascadeAndSave(workshopLoadPlans()).filter(entry => entry.stage === normalizedStage && Number(entry.bay) === Number(bay) && entry.status !== 'completed');
  const columns = dates.map(date => {
    const dateKey = workshopDateKey(date);
    const isClosure = workshopIsClosureDate(date);
    const dayPlans = plans.filter(entry => workshopEntrySegmentForDate(entry, dateKey));
    const adminBlocks = workshopLoadAdminBlocks().filter(block => block.stage === normalizedStage && Number(block.bay) === Number(bay) && workshopAdminBlockSegment(block, dateKey));
    const bookedHours = dayPlans.reduce((sum, entry) => {
      const segment = workshopEntrySegmentForDate(entry, dateKey);
      return sum + (segment ? (segment.end - segment.start) / 60 : 0);
    }, 0);
    return `<section class="workshop-week-day ${isClosure ? 'is-closure' : ''}">
      <header><strong>${escapeHtml(date.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short' }))}</strong><span>${escapeHtml(date.toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit' }))}</span><small>${isClosure ? 'CLOSED · historical bookings remain visible' : `${escapeHtml(bookedHours.toFixed(bookedHours % 1 ? 1 : 0))}h booked`}</small></header>
      <div class="workshop-week-day-lane" ${isClosure ? 'aria-disabled="true"' : `data-workshop-week-drop-date="${escapeHtml(dateKey)}"`}>${workshopWeeklyTimeGuideHtml()}${workshopUnavailableTimeHtml(dateKey, { vertical: true, stage: normalizedStage, bay: Number(bay) })}${isClosure ? '' : workshopDropPreviewHtml({ vertical: true })}${adminBlocks.map(block => workshopWeeklyAdminBlockHtml(block, dateKey)).join('')}${dayPlans.map(entry => workshopWeeklyCardHtml(entry, dateKey)).join('')}</div>
    </section>`;
  }).join('');
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay workshop-week-overlay';
  overlay.dataset.workshopWeekOverlay = 'true';
  overlay.setAttribute('role', 'dialog');
  overlay.setAttribute('aria-modal', 'true');
  overlay.innerHTML = `<section class="modal-card workshop-week-card-shell">
    <button class="modal-close" type="button" data-workshop-week-close aria-label="Close weekly view">×</button>
    <header class="workshop-week-header"><div><h2>${escapeHtml(pmbStageLabel(normalizedStage))} · ${escapeHtml(workshopBayText(normalizedStage, bay))} weekly schedule</h2><p>${escapeHtml(dates[0].toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', day: 'numeric', month: 'long' }))}–${escapeHtml(dates[dates.length - 1].toLocaleDateString('en-AU', { timeZone: 'Australia/Perth', day: 'numeric', month: 'long', year: 'numeric' }))} · drag a minimised booking to another day or time</p></div><div><button class="small-button" type="button" data-workshop-week-shift="-7">‹ Previous week</button><button class="small-button" type="button" data-workshop-week-shift="7">Next week ›</button></div></header>
    <div class="workshop-week-grid" style="--workshop-week-columns:${dates.length};min-width:${Math.max(620, dates.length * 200)}px">${columns}</div>
    <footer><span>Planned jobs snap to ${escapeHtml(WORKSHOP_PLANNER_CONFIG.schedulingIncrementMinutes)} minutes and update the daily board immediately. Closures are read-only; historical bookings remain visible. Started and STOPPAGE jobs can also be moved safely, with audit and bay-state updates. Completed jobs stay fixed.</span><button class="primary" type="button" data-workshop-week-close>Done</button></footer>
  </section>`;
  const close = () => {
    workshopWeeklyLoadSequence += 1;
    overlay.remove();
    if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
    workshopRefreshDedicatedDate(workshopState().date);
  };
  overlay.querySelectorAll('[data-workshop-week-close]').forEach(button => button.addEventListener('click', close));
  overlay.querySelectorAll('[data-workshop-week-admin-block-rename]').forEach(button => button.addEventListener('click', () => {
    const block = workshopLoadAdminBlocks().find(item => item.id === button.dataset.workshopWeekAdminBlockRename);
    if (block) void workshopRenameAdminBlock(block).then(ok => { if (ok) openWorkshopWeeklyView(normalizedStage, bay, weekStart); });
  }));
  overlay.querySelectorAll('[data-workshop-week-shift]').forEach(button => button.addEventListener('click', () => {
    const nextWeek = new Date(new Date(weekStart).getTime() + Number(button.dataset.workshopWeekShift) * 86400000);
    openWorkshopWeeklyView(normalizedStage, bay, nextWeek);
  }));
  overlay.querySelectorAll('[data-workshop-week-plan][draggable="true"]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', card.dataset.workshopWeekPlan);
    const entry = workshopLoadPlans().find(row => row.id === card.dataset.workshopWeekPlan);
    workshopSetDragPreview({ type: 'week-plan', hours: Number(entry?.hours) || workshopDefaultBookingHours() });
  }));
  overlay.querySelectorAll('[data-workshop-week-plan][draggable="true"]').forEach(card => card.addEventListener('dragend', () => {
    workshopSetDragPreview(null);
    setTimeout(() => workshopClearLanePreviews(overlay), 0);
  }));
  overlay.querySelectorAll('[data-workshop-week-drop-date]').forEach(lane => {
    lane.addEventListener('dragover', event => {
      event.preventDefault();
      lane.classList.add('drag-over');
      workshopQueueLanePreview(lane, event, true);
    });
    lane.addEventListener('dragleave', event => {
      if (!lane.contains(event.relatedTarget)) {
        lane.classList.remove('drag-over');
        workshopHideLanePreview(lane);
      }
    });
    lane.addEventListener('drop', event => {
      event.preventDefault();
      workshopFlushLanePreview(lane, event, true);
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
  overlay.querySelectorAll('[data-workshop-job-vehicle]').forEach(card => card.addEventListener('dblclick', () => openWorkshopVehicleJob(card.dataset.workshopJobVehicle, normalizedStage, card.dataset.workshopPlanId || '')));
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
  if (!lines.length) return '<div class="workshop-job-lines-empty">No AI/imported job lines are attached.</div>';
  // r478 (F91): line hours are shown, not typed. Only the work area can be changed here.
  return lines.map(line => `<div class="workshop-job-line-row" data-workshop-job-line="${escapeHtml(line.id)}">
    <span title="${escapeHtml(line.text)}">${escapeHtml(line.text)}</span>
    <label><small>Work area</small><select name="line_stage_${escapeHtml(line.id)}">${workshopJobStageOptionsHtml(line.stage)}</select></label>
    <div class="workshop-job-line-hours-readonly"><small>Line hours</small><output data-workshop-line-hours-readonly>${escapeHtml(line.hours)}</output></div>
  </div>`).join('');
}

function workshopRequiredJobsForStageHtml(vehicle = {}, stage = '', stageLines = []) {
  const normalizedStage = normalizePmbStage(stage);
  const def = typeof pmbStageJobDef === 'function' ? pmbStageJobDef(normalizedStage) : null;
  const rows = [];
  const seen = new Set();
  (Array.isArray(stageLines) ? stageLines : []).forEach(line => {
    const text = cleanNavisionText(line?.text || line?.description || '');
    const operationNo = cleanNavisionText(line?.operationNo || line?.operation_no || '');
    const identity = `${operationNo.toLowerCase()}\0${text.toLowerCase()}`;
    if (!text || seen.has(identity)) return;
    seen.add(identity);
    rows.push({
      operationNo,
      text,
      hours: line?.hours,
      hoursProvenance: line?.hoursProvenance,
      jobCardNumber: cleanNavisionText(line?.jobCardNumber || line?.job_card_number || vehicleJobcardNumber(vehicle) || ''),
    });
  });
  if (!rows.length && def && pdcJobRequired(vehicle, def) && !pdcJobComplete(vehicle, def)) {
    rows.push({ operationNo: '', text: `${pmbStageLabel(normalizedStage)} work required — no imported job-line description supplied`, hours: null, jobCardNumber: '' });
  }
  if (!rows.length) return '<div class="workshop-job-lines-empty">No outstanding required jobs are recorded for this station.</div>';
  return `<ul class="workshop-required-job-list">${rows.map(line => {
    const hours = line.hours === null || line.hours === undefined || String(line.hours).trim() === ''
      ? 'Hours unknown'
      : `${Number(line.hours).toFixed(2).replace(/\.00$/, '')} h`;
    return `<li><strong>${escapeHtml(line.operationNo || 'Required')}</strong><span>${escapeHtml(line.text)}</span><em class="${line.hoursProvenance==='ai_estimated'?'pdc-ai-estimate':''}">${line.hoursProvenance==='ai_estimated'?'AI estimate · ':''}${escapeHtml(hours)}${line.jobCardNumber ? ` · JC ${escapeHtml(line.jobCardNumber)}` : ''}</em></li>`;
  }).join('')}</ul>`;
}

function workshopLocationsVehicle(key = '') {
  const cleanKey = String(key || '').trim();
  if (!cleanKey || typeof vehicleLocationsScreenRows !== 'function') return null;
  const rows = vehicleLocationsScreenRows();
  return (Array.isArray(rows) ? rows : []).find(row => {
    const id = typeof vehicleKey === 'function' ? vehicleKey(row) : '';
    if (id && id === cleanKey) return true;
    return [row?.stock, row?.stock_number, row?.id, row?.permanent_vehicle_id]
      .some(value => String(value || '').trim() === cleanKey);
  }) || null;
}

// r540 (F154): double-click, Enter and the Vehicle panel button open the Vehicle Locations
// side panel. The centred station job modal is not drawn. Team notes stay on the vehicle
// card (Open Vehicle). Each station's hour total stays on that station in the panel.
function openWorkshopVehicleJob(key = '', requestedStage = '', requestedPlanId = '') {
  void requestedStage;
  void requestedPlanId;
  document.querySelector('[data-workshop-job-overlay]')?.remove();
  if (!document.querySelector('.modal-overlay')) document.body.classList.remove('modal-open');
  const vehicle = workshopLocationsVehicle(key);
  const bucket = vehicle && typeof incomingBucketForVehicle === 'function' ? incomingBucketForVehicle(vehicle) : '';
  const open = window.PDC_VEHICLE_SLIDEOUT?.open;
  const locationKey = vehicle && typeof vehicleKey === 'function' ? vehicleKey(vehicle) : '';
  if (vehicle && bucket && locationKey && typeof open === 'function') {
    open(locationKey, bucket);
    return true;
  }
  if (typeof workshopNotify === 'function') workshopNotify('This vehicle is not on Vehicle Locations, so the side panel cannot open.', 'info');
  return false;
}

function setupWorkshopPlannerClock() {
  if (app.workshopPlannerTimer) window.clearInterval(app.workshopPlannerTimer);
  if (app.currentView !== 'workshop') return;
  app.workshopPlannerTimer = window.setInterval(() => {
    if (app.currentView !== 'workshop' || document.hidden) return;
    const active = document.activeElement;
    if (document.querySelector('.modal-overlay:not([hidden]), dialog[open]')
      || workshopActiveQueuePointerDrag || workshopActivePointerResize || workshopCurrentDragPreview()
      || WORKSHOP_PENDING_BOOKING_ACTIONS.size
      || active?.closest?.('.workshop-job-detail, .workshop-search')
      || (active?.closest?.('#workshop-planner-root') && /^(INPUT|TEXTAREA|SELECT)$/.test(active.tagName))) {
      updateWorkshopNowLine(document.querySelector('#workshop-planner-root') || document);
      return;
    }
    renderWorkshopPlanner({ projectionOnly: true });
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
  const visible = Boolean(selectedDate)
    && workshopDateKey(selectedDate) === workshopDateKey(now)
    && workshopIsWorkday(selectedDate);
  line.hidden = !visible;
  if (!visible) return;
  const timelineRect = timeline.getBoundingClientRect();
  const axisRect = axis.getBoundingClientRect();
  const clampedOffset = Math.min(Math.max(offset, 0), WORKSHOP_PLANNER_CONFIG.dayLengthMinutes);
  const left = axisRect.left - timelineRect.left + (clampedOffset / WORKSHOP_PLANNER_CONFIG.dayLengthMinutes) * axisRect.width;
  line.style.left = `${Math.round(left)}px`;
  line.querySelector('span').textContent = `Now ${now.toLocaleTimeString('en-AU', { timeZone: 'Australia/Perth', hour: 'numeric', minute: '2-digit' })}`;
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
    workshopExactDurationHours,
    workshopImportedJobLines,
    workshopResolvedJobLines,
    workshopStageJobLines,
    workshopCalculatedStageHours,
    workshopSchedulingDuration,
    workshopEnsureCurrentDeployment,
    workshopManualDurationAllocation,
    workshopManualDurationSharedPayload,
    workshopIntervalsOverlap,
    workshopAvailabilityWindowsForDate,
    workshopBusShift,
    workshopBreakWindowsForDate,
    workshopNewBookingValidation,
    workshopRequireSchedulableCandidate,
    workshopTechnicianIsOnLeave,
    workshopHasConflict,
    workshopStartedBayConflict,
    workshopRequireNoBayConflict,
    workshopResolveConflictByNextSlot,
    workshopShiftTrailingPlannedRows,
    workshopShiftEveryLaterPlannedRow,
    workshopDateKey,
    workshopDateFromKey,
    workshopCalendarDateKeyOffset,
    workshopDefaultOpenDateKey,
    workshopNormalizeStartDate,
    workshopAddWorkMinutes,
    workshopWorkMinutesBetween,
    workshopCascadePlans,
    workshopEntrySegmentForDate,
    workshopAdminBlockSegments,
    workshopAdminBlockSegment,
    workshopAdminBlockHtml,
    workshopWeeklyAdminBlockHtml,
    workshopAdminBlockSuccessMessage,
    workshopEntryStart,
    workshopEntryEnd,
    workshopEntryEffectiveEnd,
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
    workshopBayAllocatedHours,
    workshopBayAllocatedBaseMinutes,
    workshopBookingDestinationHours,
    workshopRunVehiclePlanTransaction,
    workshopRequireOperatorProfile,
    workshopNextWorkdayDate,
    workshopNextDayFittingPartsWarnings,
    workshopNextDayFittingWarningEmailBody,
    workshopAdminBlockConflict,
    workshopUnavailableTimeHtml,
    workshopEntryPausedNow,
    workshopFirstAvailableStartMinutes,
    workshopFirstAvailableStartSlot,
    workshopBestStageSlot,
    workshopSlotSummary,
    workshopVehiclePlanningLocation,
    workshopVehicleEtaConstraint,
    workshopIncrementalRenderRows,
    workshopPlanLifecycleActionsHtml,
    workshopSelectedDateBookingCount,
    workshopQueueCardHtml,
    workshopQueueEstimatedLabel,
    workshopOutstandingDisabledReasonLabel,
    workshopDateKeyNotBefore,
    workshopEtaScheduleValidation,
    workshopEtaRiskForEntry,
    workshopEtaRiskLabel,
    workshopStageVehicles,
    workshopVehicle,
    workshopSnapshotVehicleToPlannerRow,
    workshopPlannerVehiclesForStage,
    workshopRefreshDedicatedDate,
    moveWorkshopLivePlan,
    moveWorkshopDroppedPlan,
    workshopSharedModeActive,
    workshopLoadPlans,
    workshopMapSnapshotBookingToLegacyRow,
    workshopConnectionBannerHtml,
    workshopStationSnapshotEmptyStateHtml,
    workshopDescribeSharedActionError,
    workshopDispatchSharedAction,
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
    workshopScheduleVehicleNextAvailable,
    workshopSearchMatches,
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
    workshopSchedulableBayNumbers,
    workshopBestStageSlot,
    extendWorkshopPlan,
  };
  Object.defineProperties(module.exports, {
    WORKSHOP_CONFIG: { enumerable: true, get: () => WORKSHOP_PLANNER_CONFIG },
    WORKSHOP_CONFIG_AUTHORITY: { enumerable: true, get: () => WORKSHOP_CONFIG_AUTHORITY },
  });
}
