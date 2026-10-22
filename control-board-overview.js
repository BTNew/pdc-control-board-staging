(function (root, factory) {
  'use strict';
  const timing = root.PDC_WORKSHOP_BOOKING_TIMING || (typeof require === 'function' ? require('./workshop-booking-timing.js') : null);
  const layout = root.PDC_WORKSHOP_DEPARTMENTS || (typeof require === 'function' ? require('./pdc-workshop-departments.js') : null);
  const api = factory(timing, layout);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ControlBoardOverview = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function (timing, layout) {
  'use strict';
  const labels = Object.freeze({ BUS_4X4: 'Bus 4×4', TINT: 'Tint', HOIST: 'Hoist', FITTING: 'Fitting', FABRICATION: 'Fabrication', ELECTRICAL: 'Electrical', TYRE: 'Tyre' });
  const activeStatuses = new Set(['queued', 'planned', 'started', 'stoppage']);
  const text = value => String(value == null ? '' : value).trim();
  const escape = value => text(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const stageLabel = stage => labels[stage] || text(stage);
  // r483 (F96): Dept 139 bays carry Craig's names and numbers ('Fitting · Bay 06'); other stations keep 'Bay NN'.
  const bayText = (stage, number) => layout?.pmbBayLabel?.(stage, number) || `Bay ${String(number).padStart(2, '0')}`;
  const identity = vehicle => ({
    key: text(vehicle.key_number) || '—', job: text(vehicle.job_card_number) || '—',
    stock: text(vehicle.stock_number) || '—', customer: text(vehicle.customer_name) || 'Customer not recorded',
    description: text(vehicle.vehicle_description) || [vehicle.make, vehicle.model].map(text).filter(Boolean).join(' ') || 'Vehicle details pending',
  });
  const itemIdentity = item => {
    const result = identity(item.vehicle);
    const job = text(item.displayIdentity?.job || item.displayIdentity?.jobCard);
    if (!text(item.vehicle?.job_card_number) && job) result.job = job;
    if (!text(item.vehicle?.key_number) && text(item.displayIdentity?.key)) result.key = text(item.displayIdentity.key);
    return result;
  };
  const visibleVehicle = vehicle => vehicle && !vehicle.deleted_at && vehicle.is_deleted !== true && vehicle.visible_on_board !== false && (!vehicle.lifecycle_state || vehicle.lifecycle_state === 'active');
  const compareTime = (a, b) => {
    const live = item => item.status === 'started' || item.status === 'stoppage' ? 0 : 1;
    const time = item => Date.parse(item.source.scheduled_start_at || item.source.start_at || '') || Number.MAX_SAFE_INTEGER;
    return live(a) - live(b) || time(a) - time(b) || a.id.localeCompare(b.id);
  };

  function buildModel(snapshot, options = {}) {
    if (!Array.isArray(snapshot?.board?.bays) || !Array.isArray(snapshot?.board?.bookings)) return null;
    const search = text(options.search).toLowerCase();
    const order = options.stageOrder || Object.keys(labels);
    const department = layout?.normalize(options.department) || '';
    const visible = stage => !layout || layout.stageVisible(stage, department);
    const rank = stage => { const index = order.indexOf(stage); return index < 0 ? order.length : index; };
    const bays = new Map();
    snapshot.board.bays.forEach(bay => {
      const id = text(bay.bay_id), stage = text(bay.stage_code);
      if (id && labels[stage] && visible(stage) && !bay.deleted_at && !bays.has(id)) bays.set(id, { bay, stage, items: [], total: 0 });
    });
    const columns = [...bays.values()].sort((a, b) => rank(a.stage) - rank(b.stage) || Number(a.bay.bay_number) - Number(b.bay.bay_number) || text(a.bay.bay_id).localeCompare(text(b.bay.bay_id)));
    const waiting = [], bookedWork = new Set(), seenBookings = new Set(), seenCandidates = new Set(), seenBlocks = new Set();
    snapshot.board.bookings.forEach(source => {
      const id = text(source.booking_id), stage = text(source.stage_code), status = text(source.status);
      const vehicle = source.vehicle;
      if (!id || seenBookings.has(id) || !labels[stage] || !visible(stage) || !activeStatuses.has(status) || source.deleted_at || !visibleVehicle(vehicle)) return;
      seenBookings.add(id);
      const vehicleId = text(source.vehicle_id || vehicle.id);
      if (vehicleId) bookedWork.add(`${vehicleId}:${stage}`);
      const column = bays.get(text(source.bay_id));
      const displayIdentity = vehicleId ? options.displayIdentities?.get?.(`${vehicleId.toLowerCase()}:${stage}`) : null;
      const item = { kind: 'booking', id, stage, status, vehicle, source, displayIdentity, unassignedBay: !!source.bay_id && (!column || column.stage !== stage) };
      if (column && column.stage === stage) column.items.push(item);
      else waiting.push(item);
    });
    (snapshot.candidates || []).forEach(source => {
      const stage = text(source.stage_code), vehicle = source.vehicle, vehicleId = text(vehicle?.id);
      const id = `${vehicleId}:${stage}`;
      if (!vehicleId || !labels[stage] || !visible(stage) || !visibleVehicle(vehicle) || bookedWork.has(id) || seenCandidates.has(id)) return;
      seenCandidates.add(id);
      waiting.push({ kind: 'candidate', id, stage, status: 'waiting', vehicle, source, displayIdentity: options.displayIdentities?.get?.(`${vehicleId.toLowerCase()}:${stage}`), unassignedBay: false });
    });
    (snapshot.board.admin_blocks || []).forEach(source => {
      const id = text(source.admin_block_id || source.block_id || source.id), column = bays.get(text(source.bay_id));
      if (!id || seenBlocks.has(id) || !column || source.deleted_at || source.status === 'cancelled') return;
      seenBlocks.add(id);
      column.items.push({ kind: 'admin', id, stage: column.stage, status: 'admin', vehicle: {}, source });
    });
    const matches = (item, column) => {
      if (!search) return true;
      const person = itemIdentity(item);
      return [person.key, person.job, person.stock, person.customer, person.description, stageLabel(item.stage), column ? `Bay ${column.bay.bay_number}` : 'Unallocated', column ? layout?.pmbBayLabel?.(column.stage, column.bay.bay_number) : '', column?.bay.display_name, item.source.label].map(text).join(' ').toLowerCase().includes(search);
    };
    columns.forEach(column => {
      column.items.sort(compareTime);
      column.total = column.items.length;
      column.items = column.items.filter(item => matches(item, column));
    });
    waiting.sort((a, b) => rank(a.stage) - rank(b.stage) || text(a.vehicle.stock_number).localeCompare(text(b.vehicle.stock_number), undefined, { numeric: true }) || compareTime(a, b));
    const matchedWaiting = waiting.filter(item => matches(item));
    // r483 (F96): a Dept 139 bay above its station's planner count that is inactive and empty (Fab Bays 03-13, hidden by
    // Craig) is not drawn; any other inactive bay, or one that still holds a booking or block, stays visible as before.
    const retired = column => column.bay.is_active === false && column.total === 0 && Number(column.bay.bay_number) > (layout?.PMB_BAY_COUNTS?.[column.stage] ?? Infinity);
    const shownColumns = columns.filter(column => !retired(column));
    const visibleColumns = search ? shownColumns.filter(column => column.items.length > 0) : shownColumns;
    return { department, calendar: snapshot.board.calendar, generatedAt: snapshot.generated_at, columns: visibleColumns, waiting: matchedWaiting, waitingTotal: waiting.length, totalBookings: seenBookings.size, totalWaiting: waiting.length, totalBays: shownColumns.length, search,
      matchingItems: matchedWaiting.length + columns.reduce((n, column) => n + column.items.length, 0),
      stages: [...new Set(visibleColumns.map(column => column.stage))] };
  }

  function cardHtml(item, waiting = false) {
    if (item.kind === 'admin') return `<div class="control-board-bay-card is-admin" data-control-board-match><strong>${escape(item.source.label || 'Admin block')}</strong><span>Admin block</span></div>`;
    const person = itemIdentity(item);
    const state = { started: 'Live', stoppage: 'Stoppage', planned: 'Planned', queued: 'Queued', waiting: 'Unallocated' }[item.status] || '';
    const action = item.kind === 'booking' ? 'Open booking' : 'Open workshop';
    const title = `${action} · ${stageLabel(item.stage)} · ${state}\nKey ${person.key} · Job card ${person.job}\nStock ${person.stock}\n${person.customer}\n${person.description}`;
    return `<button type="button" class="control-board-bay-card is-${escape(item.status)}" data-control-board-match data-control-board-item="${escape(item.kind)}" data-control-board-id="${escape(item.id)}" title="${escape(title)}" aria-label="${escape(title.replace(/\n/g, ' · '))}">
      ${waiting ? `<span class="control-board-card-station">${escape(stageLabel(item.stage))}${item.unassignedBay ? ' · Check bay allocation' : ''}</span>` : ''}
      <strong>Key ${escape(person.key)} · JC ${escape(person.job)}</strong>
      <span>Stock ${escape(person.stock)}</span>
      <span class="control-board-card-customer">${escape(person.customer)}</span>
      <span class="control-board-card-vehicle">${escape(person.description)}</span>
    </button>`;
  }

  const DAY = 86400000;
  const PERTH_OFFSET = 8 * 3600000;
  const dayNames = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  function dateKey(value) {
    const ms = value instanceof Date ? value.getTime() : Date.parse(text(value));
    return Number.isFinite(ms) ? new Date(ms + PERTH_OFFSET).toISOString().slice(0, 10) : '';
  }
  function validDate(value) {
    const key = text(value);
    const ms = Date.parse(`${key}T00:00:00Z`);
    return /^\d{4}-\d{2}-\d{2}$/.test(key) && Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 10) === key ? key : '';
  }
  function shiftDate(value, offset) {
    return validDate(value) ? new Date(Date.parse(`${value}T00:00:00Z`) + offset * DAY).toISOString().slice(0, 10) : '';
  }
  function searchDateRange(model, options = {}) {
    const config = calendarConfig(model.calendar);
    const projection = config && timing ? bookingProjection(config, options.now || new Date()) : null;
    const bookings = model.columns.flatMap(column => column.items).filter(item => item.kind === 'booking');
    const ranges = bookings.map(item => ({ start: Date.parse(item.source.scheduled_start_at), end: projection ? projection(item.source) : Date.parse(item.source.scheduled_end_at) }))
      .filter(range => Number.isFinite(range.start) && Number.isFinite(range.end) && range.end > range.start);
    if (!ranges.length) return null;
    const startDate = dateKey(new Date(Math.min(...ranges.map(range => range.start))));
    const endDate = dateKey(new Date(Math.max(...ranges.map(range => range.end)) - 1));
    return { startDate, dayCount: Math.min(56, Math.max(1, Math.round((Date.parse(endDate) - Date.parse(startDate)) / DAY) + 1)) };
  }
  const clockMinutes = value => {
    const match = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(text(value));
    return match && +match[1] < 24 && +match[2] < 60 ? +match[1] * 60 + +match[2] : NaN;
  };
  function unionWindows(windows) {
    const result = [];
    windows.filter(w => w.end > w.start).sort((a, b) => a.start - b.start || a.end - b.end).forEach(w => {
      const last = result[result.length - 1];
      if (last && w.start <= last.end) last.end = Math.max(last.end, w.end);
      else result.push({ start: w.start, end: w.end });
    });
    return result;
  }
  function calendarConfig(raw) {
    if (!raw || !Array.isArray(raw.working_week) || !raw.working_week.length || !Array.isArray(raw.closures) || !Array.isArray(raw.break_windows) || !Array.isArray(raw.overtime_windows)) return null;
    if ([...raw.closures, ...raw.break_windows, ...raw.overtime_windows].some(value => !value || typeof value !== 'object')) return null;
    const start = clockMinutes(raw.day_start_time), end = clockMinutes(raw.day_end_time);
    if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end || raw.working_week.some(day => !dayNames.includes(text(day).toLowerCase()))) return null;
    const normalize = windows => windows.map(w => ({ start: clockMinutes(w.start), end: clockMinutes(w.end), date: w.date ? validDate(w.date) : '', scope: text(w.scope || w.day || 'global').toLowerCase(), rawDate: w.date }));
    const breaks = normalize(raw.break_windows), overtime = normalize(raw.overtime_windows);
    if ([...breaks, ...overtime].some(w => !Number.isFinite(w.start) || !Number.isFinite(w.end) || w.start >= w.end || (w.rawDate && !w.date) || !['global', 'working_day', ...dayNames].includes(w.scope)) || raw.closures.some(c => !validDate(c.date))) return null;
    const increment = Number(raw.scheduling_increment_minutes ?? 15);
    if (!Number.isFinite(increment) || increment <= 0 || increment > 1440) return null;
    return { start, end, increment, working: new Set(raw.working_week.map(day => text(day).toLowerCase())), closed: new Set(raw.closures.map(c => c.date)), breaks, overtime };
  }
  function windowsForDate(config, date) {
    const day = dayNames[new Date(`${date}T00:00:00Z`).getUTCDay()];
    if (!config.working.has(day) || config.closed.has(date)) return [];
    const applies = w => w.date ? w.date === date : ['global', 'working_day', day].includes(w.scope);
    let windows = unionWindows([{ start: config.start, end: config.end }, ...config.overtime.filter(applies)]);
    config.breaks.filter(applies).forEach(excluded => {
      windows = windows.flatMap(w => excluded.end <= w.start || excluded.start >= w.end ? [w] : [
        ...(excluded.start > w.start ? [{ start: w.start, end: excluded.start }] : []),
        ...(excluded.end < w.end ? [{ start: excluded.end, end: w.end }] : []),
      ]);
    });
    return windows;
  }
  function bookingCalendarConfig(config, booking, cache) {
    const bay = Number(booking.bay_number ?? booking.bay?.bay_number);
    if (booking.bus_calendar_version !== 1 || text(booking.stage_code || booking.stage?.code) !== 'BUS_4X4'
        || !Number.isInteger(bay) || bay < 1 || bay > 10) return config;
    const end = [8, 9].includes(bay) ? 840 : 900;
    if (!cache.has(end)) cache.set(end, { ...config, start: 360, end,
      working: new Set(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']), overtime: [] });
    return cache.get(end);
  }
  function calendarBookingProjection(config, now) {
    // Cache calendar windows across every bay; a large board should calculate
    // the same date once. All arithmetic is explicitly Perth time.
    const cache = new Map();
    const windows = date => {
      if (!cache.has(date)) cache.set(date, windowsForDate(config, date));
      return cache.get(date);
    };
    const midnight = date => Date.parse(`${date}T00:00:00+08:00`);
    const latestWorkMoment = value => {
      let date = dateKey(new Date(value));
      const minute = Math.floor((value - midnight(date)) / 60000);
      for (let days = 0; days < 370; days++, date = shiftDate(date, -1)) {
        const limit = days ? 1440 : minute;
        const eligible = windows(date).filter(window => window.start <= limit);
        if (eligible.length) return midnight(date) + Math.min(limit, eligible[eligible.length - 1].end) * 60000;
      }
      return NaN;
    };
    const addWorkMinutes = (value, minutes) => {
      let date = dateKey(new Date(value)), remaining = minutes;
      let minute = Math.floor((value - midnight(date)) / 60000);
      for (let days = 0; days < 370; days++, date = shiftDate(date, 1), minute = 0) {
        for (const window of windows(date)) {
          const start = Math.max(minute, window.start);
          if (start >= window.end) continue;
          const available = window.end - start;
          if (remaining <= available) return midnight(date) + (start + remaining) * 60000;
          remaining -= available;
        }
      }
      return NaN;
    };
    return booking => timing.effectiveEnd(booking, { now, latestWorkMoment, addWorkMinutes, incrementMinutes: config.increment });
  }
  function bookingProjection(config, now, calendars = new Map()) {
    const projections = new Map();
    return booking => {
      const scoped = bookingCalendarConfig(config, booking, calendars);
      if (!projections.has(scoped)) projections.set(scoped, calendarBookingProjection(scoped, now));
      return projections.get(scoped)(booking);
    };
  }
  // r467 (F80): zoom levels. Day is today's view (default). Week and Month squeeze
  // more days across the screen; Month rows go slimline (coloured blocks, hover
  // title Key / JC / customer, no inline text). Display only. Saved per user per
  // device in localStorage (pdc.control-board-zoom.v1:<user id>).
  const ZOOM_LEVELS = Object.freeze(['day', 'week', 'month']);
  const ZOOM = Object.freeze({ day: { label: 'Day', lane: 48 }, week: { label: 'Week', dayWidth: 150, minDays: 14, lane: 48 }, month: { label: 'Month', dayWidth: 34, minDays: 31, lane: 14 } });
  const zoomLevel = value => ZOOM_LEVELS.includes(value) ? value : 'day';
  const zoomKey = scope => `pdc.control-board-zoom.v1:${text(scope?.PDC_AUTH_CONTEXT?.userId) || 'anonymous'}`;
  const zoomStorage = scope => { try { return scope?.localStorage || null; } catch (_) { return null; } };
  const globalScope = () => typeof window !== 'undefined' ? window : null;
  function getZoom(scope = globalScope()) {
    try { return zoomLevel(zoomStorage(scope)?.getItem(zoomKey(scope))); } catch (_) { return 'day'; }
  }
  function setZoom(level, scope = globalScope()) {
    const value = zoomLevel(level);
    try { zoomStorage(scope)?.setItem(zoomKey(scope), value); } catch (_) { /* private mode: the view still changes */ }
    return value;
  }
  // r464 (F77): a booking's pieces on consecutive days are one bar. buildTimeline
  // still cuts a booking into per-day pieces (segments, used by the parity checks);
  // the bar spans from the first piece of a run to its last, so a job that runs past
  // the day divider reads as one job. A closed day between two pieces (a weekend or
  // closure) starts a new bar, so Friday and Monday stay separate. Display only: the
  // pieces stay as `parts` for the tooltip and the click date.
  function joinedBars(pieces, lane) {
    const runs = [];
    pieces.forEach(piece => {
      const run = runs[runs.length - 1];
      if (run && piece.day - run[run.length - 1].day <= 1) run.push(piece); else runs.push([piece]);
    });
    const bookingMs = pieces.reduce((n, piece) => n + piece.end - piece.start, 0);
    return runs.map(run => {
      const first = run[0], last = run[run.length - 1];
      if (run.length === 1) return { ...first, lane, parts: run };
      return { item: first.item, day: first.day, date: first.date, start: first.start, end: last.end, lane, parts: run,
        left: first.left, width: last.left + last.width - first.left, historicalOnClosure: run.some(piece => piece.historicalOnClosure),
        continuesFromPrevious: first.continuesFromPrevious, continuesNext: last.continuesNext, joined: true,
        bookingMs: runs.length > 1 ? bookingMs : null };
    });
  }
  function buildTimeline(model, options = {}) {
    const config = calendarConfig(model.calendar);
    if (!config || !timing) return null;
    const now = options.now instanceof Date ? options.now : new Date(options.now || Date.now());
    const calendars = new Map(), effectiveEnd = bookingProjection(config, now, calendars);
    const startDate = validDate(options.startDate) || dateKey(model.generatedAt) || dateKey(now);
    const zoom = zoomLevel(options.zoom), zoomed = ZOOM[zoom];
    const dayCount = Math.max(1, Math.min(56, Math.max(zoomed.minDays || 0, Math.floor(Number(options.dayCount) || 14))));
    const axisStart = Math.min(config.start, ...config.overtime.map(w => w.start));
    const axisEnd = Math.max(config.end, ...config.overtime.map(w => w.end));
    const dayWidth = zoomed.dayWidth || Math.max(640, (axisEnd - axisStart) / 60 * 64), width = dayWidth * dayCount;
    const firstMs = Date.parse(`${startDate}T00:00:00+08:00`), lastMs = firstMs + dayCount * DAY;
    const days = Array.from({ length: dayCount }, (_, day) => {
      const date = shiftDate(startDate, day);
      return { date, startMs: firstMs + day * DAY, windows: windowsForDate(config, date) };
    });
    const scopedWindows = new Map();
    const windowsForBookingDay = (bookingCalendar, day) => {
      if (bookingCalendar === config) return day.windows;
      if (!scopedWindows.has(bookingCalendar)) scopedWindows.set(bookingCalendar, new Map());
      const cache = scopedWindows.get(bookingCalendar);
      if (!cache.has(day.date)) cache.set(day.date, windowsForDate(bookingCalendar, day.date));
      return cache.get(day.date);
    };
    const outside = [], unscheduled = [];
    const rows = model.columns.map(column => {
      const segments = [], bars = [], unplotted = [], laneEnds = [];
      const sorted = [...column.items].sort((a, b) => Date.parse(a.source.scheduled_start_at) - Date.parse(b.source.scheduled_start_at) || a.id.localeCompare(b.id));
      sorted.forEach(item => {
        const bookingCalendar = bookingCalendarConfig(config, item.source, calendars);
        const start = Date.parse(item.source.scheduled_start_at), plannedEnd = Date.parse(item.source.scheduled_end_at), end = effectiveEnd(item.source);
        if (!Number.isFinite(start) || !Number.isFinite(plannedEnd) || plannedEnd <= start || !Number.isFinite(end) || end <= start) { const entry = { item, reason: 'Booking time unavailable' }; unscheduled.push(entry); unplotted.push(entry); return; }
        if (end <= firstMs || start >= lastMs) { outside.push({ item, reason: 'Outside displayed dates', date: dateKey(item.source.scheduled_start_at) }); return; }
        const pieces = [];
        const from = Math.max(0, Math.floor((start - firstMs) / DAY)), to = Math.min(dayCount - 1, Math.floor((end - 1 - firstMs) / DAY));
        for (let day = from; day <= to; day++) {
          const historicalOnClosure = bookingCalendar.closed.has(days[day].date) && bookingCalendar.working.has(dayNames[new Date(`${days[day].date}T00:00:00Z`).getUTCDay()]);
          const displayWindows = historicalOnClosure ? [{ start: config.start, end: config.end }]
            : windowsForBookingDay(bookingCalendar, days[day]);
          for (const window of displayWindows) {
            const a = Math.max(start, days[day].startMs + window.start * 60000), b = Math.min(end, days[day].startMs + window.end * 60000);
            if (b <= a) continue;
            const startMinute = (a - days[day].startMs) / 60000, endMinute = (b - days[day].startMs) / 60000;
            const left = day * dayWidth + (startMinute - axisStart) / (axisEnd - axisStart) * dayWidth;
            pieces.push({ item, day, date: days[day].date, start: a, end: b, left, historicalOnClosure,
              continuesFromPrevious: start < days[day].startMs, continuesNext: end > days[day].startMs + DAY,
              width: (endMinute - startMinute) / (axisEnd - axisStart) * dayWidth });
          }
        }
        if (!pieces.length) { const entry = { item, reason: 'Outside current workshop hours' }; unscheduled.push(entry); unplotted.push(entry); return; }
        let lane = laneEnds.findIndex(end => end <= pieces[0].left + 0.01);
        if (lane < 0) lane = laneEnds.length;
        laneEnds[lane] = pieces[pieces.length - 1].left + pieces[pieces.length - 1].width;
        pieces.forEach(piece => segments.push({ ...piece, lane }));
        bars.push(...joinedBars(pieces, lane));
      });
      return { ...column, segments, bars, unplotted, laneCount: Math.max(1, laneEnds.length) };
    });
    const nowDay = Math.floor((now.getTime() - firstMs) / DAY), nowMinutes = (now.getTime() - firstMs - nowDay * DAY) / 60000;
    const nowLeft = nowDay >= 0 && nowDay < dayCount && nowMinutes >= axisStart && nowMinutes <= axisEnd ? nowDay * dayWidth + (nowMinutes - axisStart) / (axisEnd - axisStart) * dayWidth : null;
    return { rows, days, outside, unscheduled, startDate, dayCount, dayWidth, width, axisStart, axisEnd, nowLeft, today: dateKey(now), zoom };
  }
  function timeLabel(minutes) {
    const hour = Math.floor(minutes / 60), remainder = Math.round(minutes % 60);
    return `${hour % 12 || 12}${remainder ? ':' + String(remainder).padStart(2, '0') : ''} ${hour < 12 ? 'am' : 'pm'}`;
  }
  function timelineCard(segment) {
    const item = segment.item, person = itemIdentity(item);
    const state = { started: 'Live', stoppage: 'Stoppage', planned: 'Planned', queued: 'Queued', admin: 'Admin block' }[item.status];
    const title = item.kind === 'admin' ? item.source.label || 'Admin block' : `Key ${person.key} · JC ${person.job} · Stock ${person.stock}\n${person.customer}\n${person.description}`;
    const midnight = Date.parse(`${segment.date}T00:00:00+08:00`);
    const partLabel = part => { const dayStart = Date.parse(`${part.date}T00:00:00+08:00`); return `${part.date} · ${timeLabel((part.start - dayStart) / 60000)}–${timeLabel((part.end - dayStart) / 60000)}`; };
    const hours = ms => `${Math.round(ms / 360000) / 10} h`;
    const timingLabel = segment.joined
      ? `One booking · ${hours(segment.parts.reduce((n, part) => n + part.end - part.start, 0))} over ${segment.parts.length} parts${segment.continuesFromPrevious ? ' · Continued from previous day' : ''}${segment.continuesNext ? ' · Continues next working day' : ''}${segment.bookingMs ? ` · Booking total ${hours(segment.bookingMs)}` : ''}${segment.historicalOnClosure ? ' · Recorded booking on closure' : ''}\n${segment.parts.map(part => `${partLabel(part)} · ${hours(part.end - part.start)}`).join('\n')}`
      : `${segment.date} · ${timeLabel((segment.start - midnight) / 60000)}–${timeLabel((segment.end - midnight) / 60000)}${segment.continuesFromPrevious ? ' · Continued from previous day' : ''}${segment.continuesNext ? ' · Continues next working day' : ''}${segment.historicalOnClosure ? ' · Recorded booking on closure' : ''}`;
    const joinedParts = segment.joined ? ` data-control-board-parts="${segment.parts.map(part => `${part.date}@${Math.round((part.left - segment.left) * 10) / 10}-${Math.round((part.left + part.width - segment.left) * 10) / 10}`).join(' ')}"` : '';
    const tag = item.kind === 'admin' ? 'div' : 'button';
    return `<${tag} ${tag === 'button' ? 'type="button"' : ''} class="control-board-timeline-job is-${escape(item.status)}${segment.width < 130 ? ' is-short' : ''}${segment.joined ? ' is-joined' : ''}" style="left:${segment.left}px;width:${segment.width}px;top:${segment.lane * 48 + 5}px" data-control-board-match data-control-board-item="${escape(item.kind)}" data-control-board-id="${escape(item.id)}" data-control-board-date="${segment.date}"${joinedParts} title="${escape(`${state} · ${title}\n${timingLabel}`)}" aria-label="${escape(`${state} · ${title} · ${timingLabel}`.replace(/\n/g, ' · '))}">
      <strong>${item.kind === 'admin' ? escape(title) : `Key ${escape(person.key)} · JC ${escape(person.job)}`}</strong>
      ${item.kind === 'admin' ? '' : `<span class="control-board-timeline-customer">${escape(person.customer)}</span>`}
      ${item.kind === 'admin' ? '' : (typeof window !== 'undefined' ? window.PdcFitters?.progressHtml(item.source.fitter_progress, true) || '' : '')}
    </${tag}>`;
  }
  // r467: Month bars are plain coloured blocks; the hover title follows Craig's
  // label rule (Key + JC + customer, never Stock).
  function monthCard(segment) {
    const item = segment.item, person = itemIdentity(item);
    const state = { started: 'Live', stoppage: 'Stoppage', planned: 'Planned', queued: 'Queued', admin: 'Admin block' }[item.status];
    const parts = segment.parts || [segment];
    const dates = `${parts[0].date}${parts.length > 1 ? ` to ${parts[parts.length - 1].date}` : ''}`;
    const label = item.kind === 'admin' ? text(item.source.label) || 'Admin block' : `Key ${person.key} · JC ${person.job} · ${person.customer}`;
    const tag = item.kind === 'admin' ? 'div' : 'button';
    return `<${tag} ${tag === 'button' ? 'type="button"' : ''} class="control-board-timeline-job is-${escape(item.status)} is-zoom-block" style="left:${segment.left}px;width:${Math.max(2, segment.width)}px;top:${segment.lane * ZOOM.month.lane + 3}px" data-control-board-match data-control-board-item="${escape(item.kind)}" data-control-board-id="${escape(item.id)}" data-control-board-date="${segment.date}" title="${escape(`${label}\n${state} · ${dates}`)}" aria-label="${escape(`${label} · ${state} · ${dates}`)}"></${tag}>`;
  }
  function zoomControls(zoom) {
    const index = ZOOM_LEVELS.indexOf(zoom), outLevel = ZOOM_LEVELS[Math.min(ZOOM_LEVELS.length - 1, index + 1)], inLevel = ZOOM_LEVELS[Math.max(0, index - 1)];
    return `<span class="control-board-zoom" role="group" aria-label="Timeline zoom"><button type="button" data-control-board-zoom="${outLevel}"${outLevel === zoom ? ' disabled' : ''} title="Zoom out: more days across the screen">− Zoom out</button>${ZOOM_LEVELS.map(level => `<button type="button" data-control-board-zoom="${level}" aria-pressed="${level === zoom}"${level === zoom ? ' class="is-active"' : ''}>${ZOOM[level].label}</button>`).join('')}<button type="button" data-control-board-zoom="${inLevel}"${inLevel === zoom ? ' disabled' : ''} title="Zoom in: more detail">Zoom in +</button></span>`;
  }
  function render(model, options = {}) {
    const timeline = buildTimeline(model, { ...options, zoom: options.zoom || getZoom() });
    if (!timeline) return '<div class="workshop-connection-banner offline_error" role="status"><strong>Workshop timeline unavailable</strong><span>The workshop calendar could not be loaded. Refresh board to try again.</span></div>';
    const zoom = timeline.zoom, compact = zoom !== 'day', laneHeight = ZOOM[zoom].lane;
    const formatDay = key => new Date(`${key}T12:00:00Z`).toLocaleDateString('en-AU', zoom === 'month' ? { timeZone: 'UTC', weekday: 'narrow', day: 'numeric' } : { timeZone: 'UTC', weekday: 'short', day: 'numeric', month: 'short' });
    const tickMinutes = Array.from({ length: Math.floor((timeline.axisEnd - timeline.axisStart) / 60) + 1 }, (_, i) => timeline.axisStart + i * 60);
    if (tickMinutes[tickMinutes.length - 1] !== timeline.axisEnd) {
      // Leave room for the exact closing label (for example 4:30 pm) rather
      // than overlapping it with the preceding hourly label.
      if (timeline.axisEnd - tickMinutes[tickMinutes.length - 1] < 60 && tickMinutes.length > 1) tickMinutes.pop();
      tickMinutes.push(timeline.axisEnd);
    }
    const ticks = tickMinutes.map(minute => `<span style="left:${(minute - timeline.axisStart) / (timeline.axisEnd - timeline.axisStart) * 100}%">${escape(timeLabel(minute))}</span>`).join('');
    const days = timeline.days.map(day => `<div class="control-board-timeline-day${day.date === timeline.today ? ' is-today' : ''}${day.windows.length ? '' : ' is-closed'}" style="width:${timeline.dayWidth}px"><strong${zoom === 'month' && !day.windows.length ? ' title="Closed"' : ''}>${escape(formatDay(day.date))}${day.windows.length || zoom === 'month' ? '' : ' · Closed'}</strong><div class="control-board-time-ticks">${compact ? '' : ticks}</div></div>`).join('');
    const shading = timeline.days.map((day, index) => {
      let cursor = timeline.axisStart;
      const closed = [];
      [...day.windows, { start: timeline.axisEnd, end: timeline.axisEnd }].forEach(window => {
        if (window.start > cursor) closed.push({ start: cursor, end: window.start });
        cursor = Math.max(cursor, window.end);
      });
      return closed.map(window => `<span class="control-board-closed-time" style="left:${index * timeline.dayWidth + (window.start - timeline.axisStart) / (timeline.axisEnd - timeline.axisStart) * timeline.dayWidth}px;width:${(window.end - window.start) / (timeline.axisEnd - timeline.axisStart) * timeline.dayWidth}px" aria-hidden="true"></span>`).join('');
    }).join('');
    let previousStage = '';
    const rows = timeline.rows.map(row => {
      const stationClass = `station-${escape(row.stage.toLowerCase())}`, label = stageLabel(row.stage);
      const groupId = row.stage === 'BUS_4X4' ? 'bus-'+(layout?.groupForBay(row.bay.bay_number)?.id || '') : row.stage;
      const groupLabel = row.stage === 'BUS_4X4' ? 'Bus 4×4 · '+(layout?.groupForBay(row.bay.bay_number)?.label || label) : label+(layout?.SHARED.includes(row.stage) ? ' · shared 138 / 139' : '');
      const group = previousStage !== groupId ? `<div class="control-board-timeline-department ${stationClass}" data-control-board-stage="${escape(row.stage)}"><strong>${escape(groupLabel)}</strong><span></span></div>` : '';
      previousStage = groupId;
      const note = row.bay.is_active === false ? 'Inactive · existing bookings only' : `${text(row.bay.technician_name) || 'Unassigned'} · ${Number(row.bay.efficiency_percent) || 100}%`;
      const missing = row.unplotted.map(entry => `<button type="button" class="control-board-unplotted" data-control-board-match data-control-board-item="${escape(entry.item.kind)}" data-control-board-id="${escape(entry.item.id)}" title="${escape(entry.reason)}">${escape(entry.item.vehicle.stock_number || entry.item.source.label || 'Job')} · ${escape(entry.reason)}</button>`).join('');
      return `${group}<div class="control-board-timeline-bay ${stationClass}" data-control-board-bay="${escape(row.bay.bay_id)}" aria-label="${escape(`${label} ${bayText(row.stage, row.bay.bay_number)}`)}" style="--row-height:${zoom === 'month' ? Math.max(22, row.laneCount * laneHeight + 6) : Math.max(58, row.laneCount * 48 + 10)}px"><div class="control-board-timeline-bay-label"><button type="button" data-control-board-planner="${escape(row.stage)}" data-control-board-group="${escape(layout?.groupForBay(row.stage === 'BUS_4X4' ? row.bay.bay_number : 0)?.id || '')}" title="Open ${escape(label)} planner"><strong>${escape(bayText(row.stage, row.bay.bay_number))}</strong><span>${model.search ? row.items.length : row.total}</span></button><small title="${escape(note)}">${escape(note)}</small>${missing}</div><div class="control-board-timeline-track">${shading}${(row.bars || row.segments).map(zoom === 'month' ? monthCard : timelineCard).join('')}</div></div>`;
    }).join('');
    const outside = timeline.outside.length ? `<button class="small-button" type="button" data-control-board-reveal="${escape(timeline.outside[0].date)}">${timeline.outside.length} bookings outside these dates · Show</button>` : '';
    const waiting = model.waiting.length ? `<div class="control-board-timeline-waiting"><strong>Unallocated · ${model.waiting.length}</strong><div>${model.waiting.map(item => cardHtml(item, true)).join('')}</div></div>` : '';
    return `<div class="control-board-timeline-toolbar"><div><strong>${model.search ? model.columns.length : model.totalBays} bays · ${model.search ? model.columns.reduce((n, column) => n + column.items.filter(item => item.kind === 'booking').length, 0) + model.waiting.filter(item => item.kind === 'booking').length : model.totalBookings} bookings · ${model.search ? model.waiting.length : model.totalWaiting} unallocated</strong><span>${model.search ? `${model.matchingItems} matching jobs · Only matching bays shown · ` : ''}Scroll down for bays and right for later days. Perth time.</span></div><div class="control-board-timeline-dates"><button type="button" data-control-board-shift="-${timeline.dayCount}" aria-label="Previous ${timeline.dayCount} days">‹</button><label>From <input type="date" data-control-board-start value="${timeline.startDate}" aria-label="Timeline start date"></label><button type="button" data-control-board-today>Today</button><button type="button" data-control-board-shift="${timeline.dayCount}" aria-label="Next ${timeline.dayCount} days">›</button><button type="button" data-control-board-more${timeline.dayCount >= 56 ? ' disabled' : ''}>More days →</button>${zoomControls(zoom)}</div></div>
      <nav class="control-board-department-links" aria-label="Jump to workshop department">${(layout ? layout.options(model.department).filter(option => model.stages.includes(option.stage)) : model.stages.map(stage => ({stage,label:stageLabel(stage),group:''}))).map(option => `<button type="button" data-control-board-planner="${escape(option.stage)}" data-control-board-group="${escape(option.group)}">${escape(option.label)}</button>`).join('')}<span class="control-board-job-legend"><i class="is-planned"></i>Planned <i class="is-started"></i>Live <i class="is-stoppage"></i>Stoppage <i class="is-admin"></i>Admin block</span></nav>
      ${outside}${model.search && !model.matchingItems ? '<p class="control-board-no-results" role="status">No matching jobs. Clear the search to see all work.</p>' : ''}
      <div class="control-board-timeline-shell${compact ? ` is-zoom-${zoom}` : ''}" style="--timeline-width:${timeline.width}px;--day-width:${timeline.dayWidth}px;--hour-width:${compact ? timeline.dayWidth : timeline.dayWidth / ((timeline.axisEnd - timeline.axisStart) / 60)}px">
        <div class="control-board-timeline-sticky-header">
          <div class="control-board-timeline-header-viewport"><div class="control-board-timeline-axis"><div class="control-board-timeline-axis-corner">Workshop / Bay</div><div class="control-board-timeline-days">${days}</div></div></div>
          <div class="control-board-pan-row"><span>Drag to pan ↔</span><div class="control-board-pan-rail" tabindex="0" role="scrollbar" aria-label="Pan workshop timeline to earlier or later dates" aria-orientation="horizontal" aria-controls="control-board-timeline-scroll" aria-valuemin="0" aria-valuemax="0" aria-valuenow="0" title="Drag left or right. Use arrow keys, Page Up / Down, Home or End."><span class="control-board-pan-thumb" aria-hidden="true"></span></div></div>
        </div>
        <div id="control-board-timeline-scroll" class="control-board-bays-scroll control-board-timeline-scroll" tabindex="0" role="region" aria-label="Workshop timeline. Scroll down for all bays and horizontally for later days.">
          <div class="control-board-timeline-grid"><div class="control-board-timeline-body">${rows}${timeline.nowLeft === null ? '' : `<div class="control-board-timeline-now" style="left:calc(var(--bay-label-width) + ${timeline.nowLeft}px)"><b>Now</b></div>`}</div></div>
        </div>
      </div>${waiting}`;
  }
  function mountTimeline(host) {
    const shell = host.querySelector('.control-board-timeline-shell');
    const scroll = shell?.querySelector('.control-board-timeline-scroll');
    const header = shell?.querySelector('.control-board-timeline-header-viewport');
    const rail = shell?.querySelector('.control-board-pan-rail');
    const thumb = shell?.querySelector('.control-board-pan-thumb');
    if (!scroll || !header || !rail || !thumb) return () => {};
    const view = host.ownerDocument.defaultView;
    let drag = null;
    const metrics = () => {
      const max = Math.max(0, scroll.scrollWidth - scroll.clientWidth);
      const width = rail.clientWidth;
      const thumbWidth = Math.min(width, Math.max(32, width * scroll.clientWidth / Math.max(1, scroll.scrollWidth)));
      return { max, width, thumbWidth, travel: Math.max(0, width - thumbWidth) };
    };
    const sync = () => {
      const { max, thumbWidth, travel } = metrics();
      const left = Math.max(0, Math.min(max, scroll.scrollLeft));
      header.scrollLeft = left;
      thumb.style.width = `${thumbWidth}px`;
      thumb.style.transform = `translateX(${max ? left / max * travel : 0}px)`;
      rail.setAttribute('aria-valuemax', String(Math.round(max)));
      rail.setAttribute('aria-valuenow', String(Math.round(left)));
      rail.setAttribute('aria-disabled', String(!max));
    };
    const panTo = value => {
      scroll.scrollLeft = Math.max(0, Math.min(metrics().max, value));
      sync();
    };
    const stopDrag = event => {
      if (!drag || (event && event.pointerId !== drag.id)) return;
      const id = drag.id;
      drag = null;
      rail.classList.remove('is-dragging');
      if (rail.hasPointerCapture?.(id)) rail.releasePointerCapture(id);
    };
    const pointerDown = event => {
      if (event.button !== 0 || drag) return;
      const { max, travel, thumbWidth } = metrics();
      if (!max || !travel) return;
      event.preventDefault();
      rail.focus({ preventScroll: true });
      if (!thumb.contains(event.target)) {
        panTo((event.clientX - rail.getBoundingClientRect().left - thumbWidth / 2) / travel * max);
      }
      drag = { id: event.pointerId, x: event.clientX, left: scroll.scrollLeft, scale: max / travel };
      rail.classList.add('is-dragging');
      rail.setPointerCapture(event.pointerId);
    };
    const pointerMove = event => {
      if (!drag || event.pointerId !== drag.id) return;
      event.preventDefault();
      panTo(drag.left + (event.clientX - drag.x) * drag.scale);
    };
    const keyDown = event => {
      const page = Math.max(64, scroll.clientWidth - 168);
      const destinations = { ArrowLeft: scroll.scrollLeft - 64, ArrowRight: scroll.scrollLeft + 64, PageUp: scroll.scrollLeft - page, PageDown: scroll.scrollLeft + page, Home: 0, End: metrics().max };
      if (!Object.hasOwn(destinations, event.key)) return;
      event.preventDefault();
      panTo(destinations[event.key]);
    };
    const wheel = event => {
      if (!event.shiftKey && Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
      const delta = event.shiftKey && !event.deltaX ? event.deltaY : event.deltaX;
      if (!delta || !metrics().max) return;
      event.preventDefault();
      const factor = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? scroll.clientWidth : 1;
      panTo(scroll.scrollLeft + delta * factor);
    };
    const listeners = [[scroll, 'scroll', sync], [rail, 'pointerdown', pointerDown], [rail, 'pointermove', pointerMove], [rail, 'pointerup', stopDrag], [rail, 'pointercancel', stopDrag], [rail, 'lostpointercapture', stopDrag], [rail, 'keydown', keyDown], [header, 'wheel', wheel], [rail, 'wheel', wheel]];
    listeners.forEach(([node, type, fn]) => node.addEventListener(type, fn, { passive: type === 'scroll' }));
    // r464: a joined bar opens the planner on the day that was clicked, as the
    // separate per-day bars did. Keyboard activation keeps the first day.
    const joinedClick = event => {
      const bar = event.target.closest?.('button.control-board-timeline-job.is-joined[data-control-board-parts]');
      if (!bar || !event.detail) return;
      const x = event.clientX - bar.getBoundingClientRect().left;
      const parts = bar.dataset.controlBoardParts.split(' ').map(entry => { const [date, range] = entry.split('@'); const [a, b] = range.split('-').map(Number); return { date, a, b }; });
      const hit = parts.find(part => x >= part.a && x <= part.b) || parts.reduce((best, part) => Math.min(Math.abs(x - part.a), Math.abs(x - part.b)) < Math.min(Math.abs(x - best.a), Math.abs(x - best.b)) ? part : best);
      bar.dataset.controlBoardDate = hit.date;
    };
    scroll.addEventListener('click', joinedClick, true);
    // r467: the zoom buttons sit in the toolbar. Save the level, keep about the same
    // date at the left edge, and redraw through the board's own renderWorkflowBoard.
    const zoomClick = event => {
      const button = event.target.closest?.('button[data-control-board-zoom]');
      if (!button || button.disabled || !host.contains(button)) return;
      const next = zoomLevel(button.dataset.controlBoardZoom);
      if (next === getZoom(view)) return;
      const oldWidth = Number.parseFloat(shell.style.getPropertyValue('--day-width')) || 0;
      setZoom(next, view);
      if (oldWidth) scroll.scrollLeft = scroll.scrollLeft * (ZOOM[next].dayWidth || 672) / oldWidth;
      if (typeof view.renderWorkflowBoard === 'function') view.renderWorkflowBoard();
    };
    host.addEventListener?.('click', zoomClick);
    const resize = view.ResizeObserver ? new view.ResizeObserver(sync) : null;
    resize?.observe(scroll);
    resize?.observe(rail);
    if (!resize) view.addEventListener('resize', sync);
    sync();
    return () => {
      stopDrag();
      listeners.forEach(([node, type, fn]) => node.removeEventListener(type, fn));
      scroll.removeEventListener('click', joinedClick, true);
      host.removeEventListener?.('click', zoomClick);
      resize?.disconnect();
      if (!resize) view.removeEventListener('resize', sync);
    };
  }
  return Object.freeze({ buildModel, buildTimeline, render, mountTimeline, stageLabel, dateKey, shiftDate, searchDateRange, getZoom, setZoom, ZOOM_LEVELS });
});
