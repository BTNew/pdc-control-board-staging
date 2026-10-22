/* r462 (F75): Vehicle slide-out panel for the Vehicle Locations "Table view" (r461).
 *
 * In Table view, clicking a vehicle opens a panel that slides in from the right over the table (the Drop-down view and
 * its cards are unchanged; this file does nothing there). The panel shows:
 *   - the vehicle's own drop-down card, opened (incomingVehicleDetailRow HTML, so every icon, tick, parts colour and
 *     station state is exactly today's), bound with r461's bindBoardHandlers (the same buttons the board binds);
 *   - "Jobs & bookings": each station's job-card lines and hours, and each booking (category, bay, time, status), from
 *     the vehicle's Workshop detail (get_vehicle_workshop_detail_scoped, already read by the card's operation summary).
 * Dragging a booking onto a bay (Option A, approved by Craig 22 Oct 2026):
 *   - the panel loads that station's planner data in the background (the planner's own modules, scoped to the
 *     booking's station and date) and calls the planner's moveWorkshopDroppedPlan(planId, stage, bay, date, minutes),
 *     the exact function a planner drag calls. Its existing confirm steps run unchanged: the Dept 138 bay-rule
 *     warn-and-confirm with the logged override, Bay 3 no Coaster, QA Bay 7, the live-move confirm for started jobs.
 *   - if that station data cannot be loaded or is not ready in time (Option B), the station's planner opens with the
 *     booking selected and the target bay outlined, so the move is finished there.
 *   - started / STOPPAGE jobs: a drop onto a bay that breaks a bay rule is refused here with a message to use the
 *     planner; allowed drops use the planner's live-move confirm.
 *   - completed jobs, Pit - external and Sublet have no drag handle.
 * This file never calls an RPC or fetch itself and writes nothing to storage. Opening and closing the panel sends
 * nothing (the card's own operation summary may read the vehicle's Workshop detail, as the drop-down card does).
 * Undo: revert the PR (the table falls back to r461's side panel).
 */
(function vehicleSlideoutModule(root) {
  'use strict';
  const VERSION = '2026.10.22.r462';

  // ---------- Pure helpers (also used by the Node tests) ----------
  const STATIONS = Object.freeze([
    ['parts', 'Parts', ''], ['tint', 'Tint', 'TINT'], ['bus4x4', 'Bus 4×4', 'BUS_4X4'], ['hoist', 'Hoist', 'HOIST'],
    ['fitting', 'Fitting', 'FITTING'], ['fabrication', 'Fab', 'FABRICATION'], ['electrical', 'Elec', 'ELECTRICAL'],
    ['tyre', 'Tyre', 'TYRE'], ['sublet', 'Sublet', 'SUBLET'], ['pit_inspection', 'Pit – external', 'PIT_INSPECTION'], ['review', 'Review', ''],
  ]);
  const NO_BAY_STAGES = Object.freeze(['PIT_INSPECTION', 'SUBLET']);
  const LIVE = Object.freeze(['started', 'stoppage']);
  const BUS_CATS = Object.freeze([['BUS_MECHANICAL', 1], ['BUS_ELECTRICAL', 2], ['BUS_ACCESSORIES', 3], ['BUS_QA', 4]]);
  const bayFromName = name => { const m = /Bay\s*0*(\d+)/i.exec(String(name || '')); return m ? Number(m[1]) : 0; };

  // Booking rows from the vehicle's Workshop detail (preferred: it carries work_category and version) or, until that
  // has loaded, from the board's own salesWorkshopBookings.
  function bookingsFrom(detail, vehicle = {}) {
    if (detail && Array.isArray(detail.bookings)) {
      return detail.bookings.map(b => ({
        id: String(b.booking_id || ''), version: Number(b.booking_version ?? b.version) || 0, stage: String(b.stage_code || ''),
        stageName: String(b.stage_name || ''), bay: Number(b.bay_number) || bayFromName(b.bay_name), status: String(b.status || ''),
        start: b.scheduled_start_at || '', end: b.scheduled_end_at || '', category: String(b.work_category || ''),
        minutes: Number(b.default_duration_minutes) || 0, source: 'detail',
      })).filter(b => b.id);
    }
    return (vehicle.salesWorkshopBookings || []).map(b => ({
      id: String(b.bookingId || ''), version: Number(b.version) || 0, stage: String(b.stageCode || ''), stageName: String(b.stageName || ''),
      bay: Number(b.bayNumber) || bayFromName(b.bayName), status: String(b.status || ''), start: b.scheduledStartAt || '', end: b.scheduledEndAt || '',
      category: '', minutes: 0, source: 'board',
    })).filter(b => b.id);
  }

  // Which bookings get a drag handle. Completed, Pit - external and Sublet stay fixed; a Bus 4x4 booking waits for
  // its work category (Workshop detail) so the bay guide is known.
  function movable(booking) {
    if (!booking || !['planned', 'queued', 'started', 'stoppage'].includes(booking.status)) return false;
    if (!booking.stage || NO_BAY_STAGES.includes(booking.stage)) return false;
    if (booking.stage === 'BUS_4X4' && !booking.category) return false;
    return true;
  }
  const fixedReason = booking => booking.status === 'completed' ? 'Completed jobs stay fixed in history'
    : booking.stage === 'PIT_INSPECTION' ? 'Pit – external has no bay' : booking.stage === 'SUBLET' ? 'Sublet has no bay'
      : booking.stage === 'BUS_4X4' && !booking.category ? 'Loading the booking category…' : 'Fixed';

  // Client-side hint of the bay rules, from the same tables the planner uses (PDC_WORKSHOP_DEPARTMENTS). The server's
  // bay_rule_warning stays the authority; this only colours the targets and decides the started-job refusal.
  function predictedRules(booking, vehicle, bay, departments) {
    const D = departments;
    if (!booking || booking.stage !== 'BUS_4X4' || !D) return []; // Dept 139 / shared bays have no bay rules
    const out = [];
    const allowed = booking.category && booking.category !== 'BUS_WHOLE_JOB' ? D.allowedBays(booking.category) : null;
    if (Array.isArray(allowed) && !allowed.includes(bay)) {
      const bayFor = BUS_CATS.filter(([code]) => (D.preferredBays(code) || []).includes(bay)).map(([code]) => D.categoryLabel(code)).join(' and ') || 'other';
      out.push({ rule: 'category_bay_mismatch', bay_number: bay, work_category: booking.category,
        message: `Bay ${bay} is set up for ${bayFor} work, and this booking is ${D.categoryLabel(booking.category)} work.` });
    }
    const model = [vehicle?.vehicle, vehicle?.toyotaVehicle].filter(Boolean).join(' ');
    if (bay === 3 && /\bCOASTER\b/i.test(model)) out.push({ rule: 'bus_bay_vehicle_incompatible', bay_number: 3, message: 'Bay 3 has a height restriction and does not take a Coaster.' });
    return out;
  }

  // What a drop does. 'move' goes to the planner's moveWorkshopDroppedPlan; the others are messages only.
  function dropDecision(booking, bay, rules = []) {
    if (!movable(booking)) return { kind: 'fixed', reason: fixedReason(booking) };
    if (!(Number(bay) > 0)) return { kind: 'none' };
    if (Number(bay) === Number(booking.bay)) return { kind: 'same-bay' };
    if (LIVE.includes(booking.status) && rules.length) return { kind: 'blocked-live', rules };
    return { kind: 'move', rules };
  }

  // Arguments for moveWorkshopDroppedPlan: same station, the dropped bay, the booking's own start (Perth date and minute
  // offset from the planner's day start); an unallocated booking uses now and the planner finds the slot.
  function moveArguments(entry, stage, bay, helpers, now = new Date()) {
    const start = entry?.startAt ? new Date(entry.startAt) : null;
    const when = start && !Number.isNaN(start.getTime()) ? start : now;
    return [entry.id, stage, Number(bay), helpers.workshopDateKey(when), Math.max(0, Number(helpers.workshopMinuteOffset(when)) || 0)];
  }

  // One drop, start to finish, with every outside step passed in (so the Node tests can prove what is called).
  //   deps.stationEntry(booking)      -> the planner entry once the station's data is loaded, or null (not ready)
  //   deps.moveWorkshopDroppedPlan()  -> the planner's own drop function (confirms, override log, notifications)
  //   deps.openInPlanner(booking, bay, message) -> Option B
  //   deps.message(kind, text)        -> panel message
  // Returns { outcome, args? }. Never calls anything else.
  async function performDrop(booking, vehicle, bay, deps) {
    const rules = predictedRules(booking, vehicle, bay, deps.departments);
    const decision = dropDecision(booking, bay, rules);
    if (decision.kind === 'none') return { outcome: 'none' };
    if (decision.kind === 'fixed') { deps.message('fixed', decision.reason); return { outcome: 'fixed' }; }
    if (decision.kind === 'same-bay') { deps.message('same-bay', 'Same bay, so nothing moved. To change the order inside a bay, use the planner (Move ahead / Swap).'); return { outcome: 'same-bay' }; }
    if (decision.kind === 'blocked-live') {
      deps.message('blocked-live', `Bay ${bay}: ${rules.map(r => r.message).join(' ')} This job is ${booking.status === 'stoppage' ? 'on STOPPAGE' : 'started'}, so it can't go to a bay that breaks the bay rule from here. Use the planner.`);
      return { outcome: 'blocked-live', rules };
    }
    let entry = null;
    try { entry = await deps.stationEntry(booking); } catch (_) { entry = null; }
    if (!entry || typeof deps.moveWorkshopDroppedPlan !== 'function') {
      deps.openInPlanner(booking, bay, 'The station planner could not load here, so it opened with this booking selected. Drag it to the outlined bay.');
      return { outcome: 'fallback-planner' };
    }
    const args = moveArguments(entry, booking.stage, bay, deps.helpers);
    const result = await deps.moveWorkshopDroppedPlan(...args);
    return { outcome: result === true ? 'moved' : 'not-moved', args, rules };
  }

  const api = { VERSION, STATIONS, bookingsFrom, movable, predictedRules, dropDecision, moveArguments, performDrop };
  if (typeof module === 'object' && module.exports) module.exports = api;
  const VLT = root?.PDC_VEHICLE_LOCATIONS_TABLE;
  if (!root || !root.document || !VLT || typeof VLT.setDrawerOpener !== 'function' || root.PDC_VEHICLE_SLIDEOUT) {
    if (root && !root.PDC_VEHICLE_SLIDEOUT) root.PDC_VEHICLE_SLIDEOUT = api;
    return;
  }

  // ---------- Browser ----------
  const doc = root.document;
  const D = () => root.PDC_WORKSHOP_DEPARTMENTS;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const state = { key: '', bucket: '', drag: null, busy: false, detailTimer: 0, toastTimer: 0 };
  const stationOf = key => STATIONS.find(s => s[0] === key) || [key, key || 'Other', String(key || '').toUpperCase()];
  const stageToKey = code => (STATIONS.find(s => s[2] === code) || [String(code || '').toLowerCase()])[0];
  const role = () => String(root.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
  const canMove = () => ['operator', 'administrator'].includes(role()); // same roles as workshopAdministratorCanMove()
  const vehicleFor = key => root.vehicleLocationsScreenRows().find(row => root.vehicleKey(row) === key);
  const canonicalId = vehicle => (typeof root.vehicleWorkshopDetailCanonicalId === 'function' ? root.vehicleWorkshopDetailCanonicalId(vehicle) : '') || '';
  const detailOf = vehicle => {
    const id = canonicalId(vehicle);
    const cached = id && app.vehicleWorkshopDetailCache?.get?.(id);
    return cached?.status === 'ready' || cached?.detail ? cached.detail : null;
  };
  const bookingsFor = vehicle => bookingsFrom(detailOf(vehicle), vehicle);
  const plannerTech = bookingId => {
    try {
      if (typeof root.workshopLoadPlans !== 'function' || typeof root.workshopSharedModeActive !== 'function' || !root.workshopSharedModeActive()) return '';
      return root.workshopLoadPlans().find(entry => entry.sharedBookingId === bookingId)?.assignee || '';
    } catch (_) { return ''; }
  };
  const bayCount = stage => stage === 'BUS_4X4' ? 10 : Math.max(0, Number(root.pmbStageBayCount?.(stage)) || 0);
  const bayLabel = (stage, bay) => D()?.bayLabel?.(stage, bay) || `Bay ${String(bay).padStart(2, '0')}`;
  const categoryLabel = booking => booking.stage === 'BUS_4X4' ? (booking.category ? D()?.categoryLabel?.(booking.category) || booking.category : 'Bus 4×4') : (booking.stageName || stationOf(stageToKey(booking.stage))[1]);
  const when = value => { const d = new Date(value); return !value || Number.isNaN(d.getTime()) ? '' : d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false }); };
  const hours = h => `${(Math.round(h * 100) / 100).toFixed(2)} h`;
  const booked = min => !min ? '' : min < 60 ? `${min} min` : hours(min / 60);
  const STATUS = { planned: ['Booked', 'booked'], queued: ['Unallocated', 'queued'], started: ['Started', 'started'], stoppage: ['STOPPAGE', 'stoppage'], completed: ['Done', 'done'] };

  function loadStyles() {
    if (doc.querySelector('link[data-pdc-vehicle-slideout]')) return;
    const link = doc.createElement('link');
    link.rel = 'stylesheet';
    link.href = `pdc-vehicle-slideout.css?vehicle-slideout=${VERSION}`;
    link.dataset.pdcVehicleSlideout = '1';
    doc.head.appendChild(link);
  }

  function lineGroups(vehicle) {
    const groups = new Map();
    (vehicle.pdcEmailOperationLines || []).forEach(line => {
      const key = D()?.isPitLine?.({ description: line.description }) ? 'pit_inspection' : String(line.work_key || 'review');
      const g = groups.get(key) || { key, lines: 0, hours: 0, depts: new Set() };
      g.lines += 1; g.hours += Number(line.effectiveEstimatedHours ?? line.estimatedHours) || 0; if (line.department) g.depts.add(String(line.department));
      groups.set(key, g);
    });
    return groups;
  }

  function bookingRowHtml(b, dragOn) {
    const [label, tone] = STATUS[b.status] || [b.status, 'queued'];
    const drag = dragOn && movable(b);
    const tech = plannerTech(b.id);
    return `<div class="vso-booking" data-vso-booking="${esc(b.id)}">
      <span class="vso-grip${drag ? '' : ' is-fixed'}" ${drag ? 'data-vso-drag role="button" tabindex="-1"' : 'aria-disabled="true"'} title="${esc(drag ? 'Drag onto a bay' : dragOn ? fixedReason(b) : 'Read only')}">⠿</span>
      <span class="vso-cat" title="${esc(categoryLabel(b))}">${esc(categoryLabel(b))}</span>
      <span class="vso-bay">${esc(b.bay ? bayLabel(b.stage, b.bay) : NO_BAY_STAGES.includes(b.stage) ? 'No bay' : 'No bay yet')}</span>
      <span class="vso-when" title="Perth time">${esc(when(b.start))}${b.end ? ` → ${esc(when(b.end))}` : ''}</span>
      <span class="vso-hrs">${esc(booked(b.minutes))}</span>
      <span class="vso-tech" title="${esc(tech ? `Technician: ${tech}` : 'Technician shows here once the station planner data is loaded')}">${esc(tech || '—')}</span>
      <span class="vso-status ${tone}">${esc(label)}</span>
    </div>`;
  }

  function jobsHtml(vehicle) {
    const groups = lineGroups(vehicle);
    const bookings = bookingsFor(vehicle);
    const dragOn = canMove();
    const loading = !detailOf(vehicle);
    const keys = [...new Set([...STATIONS.map(s => s[0]).filter(k => groups.has(k) || bookings.some(b => stageToKey(b.stage) === k)), ...groups.keys()])];
    const rows = keys.map(key => {
      const [, label] = stationOf(key);
      const g = groups.get(key);
      const mine = bookings.filter(b => stageToKey(b.stage) === key)
        .sort((a, b) => (BUS_CATS.find(c => c[0] === a.category)?.[1] || 9) - (BUS_CATS.find(c => c[0] === b.category)?.[1] || 9));
      const note = key === 'pit_inspection' ? 'External — no bay' : key === 'sublet' ? 'Sublet — no bay (PO below)' : key === 'review' ? 'Needs a station before it can be booked' : mine.length ? '' : 'Not booked';
      return `<section class="vso-group vso-${esc(key)}">
        <header><strong>${esc(label)}</strong>${g ? `<span>${g.lines} line${g.lines === 1 ? '' : 's'} · ${hours(g.hours)}</span>${[...g.depts].sort().map(d => `<em class="vso-dept">${esc(d)}</em>`).join('')}` : ''}${note ? `<small>${esc(note)}</small>` : ''}</header>
        ${mine.map(b => bookingRowHtml(b, dragOn)).join('')}
      </section>`;
    }).join('');
    const hint = !dragOn ? 'Read only for your role' : loading ? 'Loading booking details…' : 'Drag ⠿ onto a bay to move it · times are Perth';
    return `<div class="vso-jobs" aria-label="Jobs and bookings" data-vso-detail="${loading ? 'loading' : 'ready'}"><div class="vso-section-title"><span>Jobs &amp; bookings</span><small>${esc(hint)}</small></div>${rows || '<p class="vso-empty">No job-card lines or bookings yet.</p>'}</div>`;
  }

  function occupancy(stage, bay) {
    try {
      if (typeof root.workshopLoadPlans !== 'function' || !root.workshopSharedModeActive?.()) return null;
      return root.workshopLoadPlans().filter(e => e.stage === stage && Number(e.bay) === bay && ['planned', 'started', 'stoppage'].includes(e.status)).length;
    } catch (_) { return null; }
  }
  function bayBoardHtml(booking, vehicle, hoverBay = 0) {
    const n = bayCount(booking.stage);
    const tiles = Array.from({ length: n }, (_, i) => i + 1).map(bay => {
      const rules = predictedRules(booking, vehicle, bay, D());
      const current = bay === booking.bay;
      const live = LIVE.includes(booking.status);
      const tone = current ? 'is-current' : rules.length ? (live ? 'is-blocked' : 'is-warn') : 'is-ok';
      const busy = occupancy(booking.stage, bay);
      const text = current ? 'Current bay' : rules.length ? (live ? '⛔ Use the planner' : '⚠ Asks to confirm') : '✓ Fits';
      return `<div class="vso-bay-tile ${tone}${hoverBay === bay ? ' is-hover' : ''}" data-vso-drop-bay="${bay}" title="${esc(rules.map(r => r.message).join(' ') || (current ? 'Current bay' : 'Goes here with no bay-rule warning'))}">
        <strong>${esc(bayLabel(booking.stage, bay))}</strong><span>${text}</span>${busy == null ? '' : `<small>${busy ? `${busy} booked` : 'Free'}</small>`}
      </div>`;
    }).join('');
    const guide = booking.stage === 'BUS_4X4' ? 'Dept 138 bay guide: ✓ fits · ⚠ asks to confirm (override logged)' : 'Dept 139 / shared bays: no bay rules';
    return `<div class="vso-bayboard" aria-label="Bay targets">
      <div class="vso-section-title"><span>Drop on a bay — ${esc(categoryLabel(booking))}</span><small>${esc(guide)} · same start time kept</small></div>
      <div class="vso-bay-grid" style="--vso-cols:${Math.min(Math.max(n, 1), 5)}">${tiles || '<em>No bays for this station.</em>'}</div>
    </div>`;
  }

  // ---------- Panel ----------
  function ensureShell() {
    let shell = doc.getElementById('vso-shell');
    if (shell) return shell;
    shell = doc.createElement('div');
    shell.id = 'vso-shell';
    shell.innerHTML = '<div class="vso-scrim" data-vso-close></div><aside class="vso-panel" role="dialog" aria-modal="false" aria-label="Vehicle detail"></aside><div class="vso-parity" aria-hidden="true"></div>';
    doc.body.appendChild(shell);
    shell.addEventListener('click', event => { if (event.target.closest('[data-vso-close]')) close(); });
    shell.addEventListener('pointerdown', onPointerDown);
    return shell;
  }
  const cardHtmlFor = (vehicle, bucket) => {
    const workshopProjectionAvailable = root.ensureDashboardWorkshopProjectionReady();
    const workshopPlans = workshopProjectionAvailable && typeof root.workshopLoadPlans === 'function' ? root.workshopLoadPlans() : null;
    return root.incomingVehicleDetailRow(vehicle, bucket, { workshopPlans, workshopProjectionAvailable, subletNavigation: true })
      .replace('<details class="incoming-vehicle-card', '<details open class="incoming-vehicle-card vlt-drawer-card vso-card');
  };

  function render(key, bucket, { keepScroll = false } = {}) {
    const vehicle = vehicleFor(key);
    if (!vehicle) { close(); return false; }
    const shell = ensureShell();
    const panel = shell.querySelector('.vso-panel');
    const scroll = keepScroll ? panel.querySelector('.vso-body')?.scrollTop || 0 : 0;
    const nested = keepScroll ? [...panel.querySelectorAll('.vso-body details details')].map(d => d.open) : [];
    const tile = VLT.TILE[bucket] || [bucket, '', 'unknown', String(bucket || '').toUpperCase()];
    const cardHtml = cardHtmlFor(vehicle, bucket);
    const parts = VLT.splitCard(cardHtml);
    const text = el => (el?.inner || '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
    const keyNo = text(parts.key) || '—';
    const jobs = (vehicle.pdcJobCardNumbers || []).join(' · ') || vehicle.jobCardNumber || '—';
    const depts = (vehicle.pdcDepartmentCodes || []).map(d => `<em class="vso-dept">${esc(d)}</em>`).join('') || '—';
    panel.innerHTML = `<header class="vso-head">
        <div class="vso-id"><span class="vlt-pill ${esc(tile[2])}">${esc(tile[3])}</span>
          <h3>${esc(root.displayStockNumber(vehicle) || key)}</h3><p>${esc(root.displayVehicle(vehicle) || '')}</p>
          <div class="vso-facts"><span><b>Key</b> ${esc(keyNo)}</span><span><b>JC</b> ${esc(jobs)}</span><span><b>Dept</b> ${depts}</span></div></div>
        <div class="vso-head-actions"><span class="vso-open-slot"></span><button type="button" class="vso-close" data-vso-close aria-label="Close">✕</button></div>
      </header>
      <div class="vso-body">${cardHtml}</div>
      <div class="vso-toast" role="status" hidden></div>`;
    const card = panel.querySelector('details.vso-card');
    card.querySelector('summary')?.addEventListener('click', event => { if (!event.target.closest('button, a, input, select, label')) event.preventDefault(); });
    card.querySelector('summary')?.insertAdjacentHTML('afterend', `${jobsHtml(vehicle)}<div class="vso-bayboard-slot"></div>`);
    VLT.bindBoardHandlers(panel); // r461's export: the same listeners the board binds today
    const openButton = card.querySelector('[data-open-stock]');
    if (openButton) {
      const copy = openButton.cloneNode(true);
      copy.addEventListener('click', event => { event.stopPropagation(); root.openVehicleCardFromVisibleBoard(copy.dataset.openStock, copy); });
      panel.querySelector('.vso-open-slot').appendChild(copy);
    }
    if (keepScroll) {
      const again = [...panel.querySelectorAll('.vso-body details details')];
      nested.forEach((open, index) => { if (again[index]) again[index].open = open; });
      panel.querySelector('.vso-body').scrollTop = scroll;
    }
    watchOperations(panel);
    return true;
  }

  // Craig 22 Oct 08:07: long operation descriptions are cut with an ellipsis; the full text shows on hover and on focus.
  let opsObserver = null;
  function markTruncated(panel) {
    panel.querySelectorAll('.authenticated-email-operations li > span').forEach(span => {
      const full = span.textContent.replace(/\s+/g, ' ').trim();
      if (!full) return;
      if (!span.title) span.title = full;
      const li = span.parentElement;
      const cut = span.scrollWidth > span.clientWidth + 1;
      if (cut) { li.dataset.vsoFull = full; if (!li.hasAttribute('tabindex')) li.tabIndex = 0; }
      else if (li.dataset.vsoFull) { delete li.dataset.vsoFull; }
    });
  }
  function watchOperations(panel) {
    opsObserver?.disconnect();
    const run = () => (root.requestAnimationFrame || setTimeout)(() => markTruncated(panel));
    run();
    if (typeof root.MutationObserver === 'function') {
      opsObserver = new root.MutationObserver(run);
      const host = panel.querySelector('.vso-body');
      if (host) opsObserver.observe(host, { childList: true, subtree: true });
    }
  }

  // The card's operation summary reads the Workshop detail; once it is in, redraw only the jobs section.
  function watchDetail() {
    clearTimeout(state.detailTimer);
    const started = Date.now();
    const tick = () => {
      const vehicle = state.key && vehicleFor(state.key);
      const jobs = doc.querySelector('#vso-shell .vso-jobs');
      if (!vehicle || !jobs) return;
      if (detailOf(vehicle)) { if (!state.drag && !state.busy) jobs.outerHTML = jobsHtml(vehicle); return; }
      if (Date.now() - started < 20000) state.detailTimer = setTimeout(tick, 400);
    };
    state.detailTimer = setTimeout(tick, 300);
  }

  function open(key, bucket) {
    state.key = key; state.bucket = bucket;
    if (!render(key, bucket)) return;
    const shell = ensureShell();
    doc.querySelectorAll('#vlt-table-host tr.is-open').forEach(row => row.classList.remove('is-open'));
    doc.querySelector(`#vlt-table-host tr[data-vlt-key="${CSS.escape(key)}"]`)?.classList.add('is-open');
    shell.classList.add('is-open');
    doc.body.classList.add('vso-open');
    watchDetail();
    shell.querySelector('.vso-close')?.focus({ preventScroll: true });
  }
  // Live refreshes redraw the open panel only while nobody is dragging or waiting on a move.
  function refresh(key, bucket) {
    if (key !== state.key || state.drag || state.busy) return;
    state.bucket = bucket;
    render(key, bucket, { keepScroll: true });
    doc.querySelector(`#vlt-table-host tr[data-vlt-key="${CSS.escape(key)}"]`)?.classList.add('is-open');
    watchDetail();
  }
  function close() {
    if (!state.key && !doc.getElementById('vso-shell')?.classList.contains('is-open')) return;
    state.key = ''; clearTimeout(state.detailTimer); opsObserver?.disconnect();
    const shell = doc.getElementById('vso-shell');
    shell?.classList.remove('is-open');
    doc.body.classList.remove('vso-open');
    VLT.drawerClosed();
  }
  function toast(message, actions = []) {
    const el = doc.querySelector('#vso-shell .vso-toast');
    if (!el) return;
    el.innerHTML = `<span>${esc(message)}</span>${actions.map((a, i) => `<button type="button" data-vso-toast-action="${i}">${esc(a.label)}</button>`).join('')}`;
    actions.forEach((a, i) => el.querySelector(`[data-vso-toast-action="${i}"]`).addEventListener('click', () => { el.hidden = true; a.run(); }));
    el.hidden = false;
    clearTimeout(state.toastTimer); state.toastTimer = setTimeout(() => { el.hidden = true; }, actions.length ? 15000 : 9000);
  }

  // ---------- Drag (pointer events, like the planner's own drag session) ----------
  function onPointerDown(event) {
    const grip = event.target.closest?.('[data-vso-drag]');
    if (!grip || event.button !== 0 || state.busy || !canMove()) return;
    const vehicle = vehicleFor(state.key);
    const booking = vehicle && bookingsFor(vehicle).find(b => b.id === grip.closest('[data-vso-booking]')?.dataset.vsoBooking);
    if (!booking || !movable(booking)) return;
    event.preventDefault();
    const oldToast = doc.querySelector('#vso-shell .vso-toast'); if (oldToast) oldToast.hidden = true;
    const slot = doc.querySelector('#vso-shell .vso-bayboard-slot');
    slot.innerHTML = bayBoardHtml(booking, vehicle);
    const row = grip.closest('.vso-booking');
    row.classList.add('is-dragging');
    const ghost = doc.createElement('div');
    ghost.className = 'vso-ghost';
    ghost.textContent = `${categoryLabel(booking)} · ${booking.bay ? bayLabel(booking.stage, booking.bay) : 'no bay'}`;
    doc.body.appendChild(ghost);
    state.drag = { booking, vehicle, ghost, row, bay: 0 };
    const move = e => {
      ghost.style.transform = `translate(${e.clientX + 12}px, ${e.clientY + 10}px)`;
      const tile = doc.elementsFromPoint(e.clientX, e.clientY).map(n => n.closest?.('[data-vso-drop-bay]')).find(Boolean);
      const bay = tile ? Number(tile.dataset.vsoDropBay) : 0;
      if (state.drag && bay !== state.drag.bay) {
        state.drag.bay = bay;
        doc.querySelectorAll('#vso-shell [data-vso-drop-bay]').forEach(t => t.classList.toggle('is-hover', Number(t.dataset.vsoDropBay) === bay));
      }
    };
    const up = () => {
      doc.removeEventListener('pointermove', move); doc.removeEventListener('pointerup', up); doc.removeEventListener('pointercancel', up);
      ghost.remove(); row.classList.remove('is-dragging');
      const drag = state.drag; state.drag = null;
      if (drag?.bay) drop(drag.booking, drag.vehicle, drag.bay);
      else slot.innerHTML = '';
    };
    move(event);
    doc.addEventListener('pointermove', move);
    doc.addEventListener('pointerup', up);
    doc.addEventListener('pointercancel', up);
  }

  async function drop(booking, vehicle, bay) {
    const slot = doc.querySelector('#vso-shell .vso-bayboard-slot');
    const shell = doc.getElementById('vso-shell');
    const preview = dropDecision(booking, bay, predictedRules(booking, vehicle, bay, D()));
    if (preview.kind === 'move') {
      if (slot) slot.innerHTML = bayBoardHtml(booking, vehicle, bay);
      state.busy = true;
      shell?.classList.add('is-busy');
      toast(`Loading the ${root.pmbStageLabel?.(booking.stage) || booking.stage} planner to move it to ${bayLabel(booking.stage, bay)}…`);
    } else if (slot) slot.innerHTML = '';
    let result = { outcome: 'none' };
    try {
      result = await performDrop(booking, vehicle, bay, {
        departments: D(),
        // Read lazily: the planner modules (and these helpers) may only arrive inside stationEntry().
        helpers: { workshopDateKey: when => root.workshopDateKey(when), workshopMinuteOffset: when => root.workshopMinuteOffset(when) },
        stationEntry: async b => {
          const entry = await stationEntry(b);
          const toastEl = doc.querySelector('#vso-shell .vso-toast'); if (toastEl) toastEl.hidden = true;
          return entry;
        },
        get moveWorkshopDroppedPlan() { return typeof root.moveWorkshopDroppedPlan === 'function' ? (...args) => root.moveWorkshopDroppedPlan(...args) : null; },
        openInPlanner: (b, targetBay, message) => openInPlanner(b, vehicle, targetBay, message),
        message: (kind, text) => toast(kind === 'blocked-live' ? text.replace(/^Bay (\d+)/, () => bayLabel(booking.stage, bay)) : text,
          kind === 'blocked-live' ? [{ label: 'Open in planner', run: () => openInPlanner(booking, vehicle, bay) }] : []),
      });
    } catch (error) {
      root.pdcNotify?.(error?.message || 'The move could not be completed. Nothing was changed.');
    } finally {
      state.busy = false;
      shell?.classList.remove('is-busy');
      if (slot && preview.kind === 'move') slot.innerHTML = '';
    }
    if (result.outcome === 'moved') {
      toast(`Moved to ${bayLabel(booking.stage, bay)}.`);
      if (canonicalId(vehicle) && typeof root.loadVehicleWorkshopDetail === 'function') {
        Promise.resolve(root.loadVehicleWorkshopDetail(vehicle, { force: true })).catch(() => null).then(() => { if (state.key) refresh(state.key, state.bucket); });
      }
    }
    return result;
  }

  // Load the planner modules with the planner's own loader, point the shared Workshop data service at the booking's
  // station and date, and wait for a trusted snapshot that holds this booking. null = not ready (Option B).
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  async function waitFor(test, timeoutMs) {
    const end = Date.now() + timeoutMs;
    while (Date.now() < end) { const value = test(); if (value) return value; await sleep(150); }
    return null;
  }
  async function ensurePlannerModules(timeoutMs) {
    const ready = () => typeof root.moveWorkshopDroppedPlan === 'function' && typeof root.workshopLoadPlans === 'function'
      && typeof root.buildWorkshopSharedActions === 'function' && !root.__workshopPlannerModulesLoading;
    if (ready()) return true;
    if (!root.__workshopPlannerModulesLoading && typeof root.renderWorkshopPlannerWhenReady === 'function') root.renderWorkshopPlannerWhenReady();
    return Boolean(await waitFor(ready, timeoutMs));
  }
  async function stationEntry(booking, timeoutMs = 15000) {
    const end = Date.now() + timeoutMs;
    if (!await ensurePlannerModules(timeoutMs)) return null;
    const previousStage = app.activeWorkshopPlannerStage;
    app.activeWorkshopPlannerStage = root.__workshopDataService ? '' : booking.stage; // '' = no scope change inside init
    try { root.initWorkshopSharedServicesIfEnabled?.(); } finally { app.activeWorkshopPlannerStage = previousStage; }
    const service = root.__workshopDataService;
    if (!service || typeof service.setScope !== 'function') return null;
    const start = booking.start ? new Date(booking.start) : new Date();
    const dateKey = root.workshopDateKey(Number.isNaN(start.getTime()) ? new Date() : start);
    const scope = service.getScope?.();
    if (!scope || scope.stageCode !== booking.stage || scope.dateFrom !== dateKey || scope.dateTo !== dateKey) {
      Promise.resolve(service.setScope({ stageCode: booking.stage, dateFrom: dateKey, dateTo: dateKey })).catch(() => null);
    }
    return waitFor(() => {
      const s = service.getScope?.();
      if (root.__workshopDataService !== service || !root.workshopSharedModeActive?.() || !service.getTrustedSnapshot?.()) return null;
      if (!s || s.stageCode !== booking.stage || s.dateFrom !== dateKey) return null;
      return root.workshopLoadPlans().find(entry => entry.sharedBookingId === booking.id) || null;
    }, Math.max(0, end - Date.now()));
  }

  // Option B: the existing booking link (openVehicleWorkshopBooking) opens the station planner on this booking with
  // the bays around it; the target bay lane is outlined for a minute.
  function openInPlanner(booking, vehicle, bay, message = '') {
    const start = booking.start ? new Date(booking.start) : new Date();
    const dateKey = typeof root.workshopDateKey === 'function' ? root.workshopDateKey(start) : new Date(start.getTime() + 8 * 3600000).toISOString().slice(0, 10);
    target = { stage: booking.stage, bay: Number(bay) || 0, until: Date.now() + 60000 };
    close();
    const opened = typeof root.openVehicleWorkshopBooking === 'function'
      && root.openVehicleWorkshopBooking(booking.id, booking.stage, dateKey, canonicalId(vehicle), root.displayStockNumber?.(vehicle) || '', String(booking.bay || ''), { showSurrounding: true });
    if (!opened) { target = null; root.pdcNotify?.('This booking could not be opened in the planner. Open the station planner and search for the vehicle.'); return; }
    if (message) root.pdcNotify?.(message, 'info');
    outlineTarget();
  }
  let target = null; let targetObserver = null;
  function outlineTarget() {
    const plannerRoot = doc.getElementById('workshop-planner-root');
    const paint = () => {
      if (!target || Date.now() > target.until) { targetObserver?.disconnect(); targetObserver = null; doc.querySelectorAll('.vso-target-bay').forEach(n => n.classList.remove('vso-target-bay')); target = null; return; }
      doc.querySelectorAll(`[data-workshop-drop-stage="${CSS.escape(target.stage)}"][data-workshop-drop-bay="${target.bay}"]`).forEach(n => n.classList.add('vso-target-bay'));
    };
    paint();
    if (plannerRoot && typeof root.MutationObserver === 'function' && !targetObserver) {
      targetObserver = new root.MutationObserver(paint);
      targetObserver.observe(plannerRoot, { childList: true, subtree: true });
      setTimeout(paint, 61000);
    }
  }

  // Parity helper for PDC_VEHICLE_LOCATIONS_TABLE.parity(): draws the panel's card off-screen inside the panel shell
  // (same CSS as the open panel) and returns its station strip. Binds nothing, loads nothing.
  function parityStrip(key, bucket) {
    const vehicle = vehicleFor(key);
    const host = ensureShell().querySelector('.vso-parity');
    if (!vehicle || !host) return null;
    host.innerHTML = `<div class="vso-panel-like"><div class="vso-body">${cardHtmlFor(vehicle, bucket)}</div></div>`;
    return host.querySelector('.vso-card .pdc-station-strip');
  }
  function parityDone() { const host = doc.querySelector('#vso-shell .vso-parity'); if (host) host.innerHTML = ''; }

  loadStyles();
  VLT.setDrawerOpener({ open, refresh, close, parityStrip, parityDone });
  root.PDC_VEHICLE_SLIDEOUT = Object.freeze({ ...api, open, close, refresh, parityStrip, state, stationEntry, openInPlanner });
}(typeof window !== 'undefined' ? window : globalThis));
