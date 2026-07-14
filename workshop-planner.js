'use strict';

const WORKSHOP_PLAN_STORAGE_KEY = 'vehicleTrackingCoreWorkshopPlan:v1';
const WORKSHOP_VIEW_STORAGE_KEY = 'vehicleTrackingCoreWorkshopView:v1';
const WORKSHOP_START_HOUR = 8;
const WORKSHOP_END_HOUR = 16;
const WORKSHOP_DAY_MINUTES = (WORKSHOP_END_HOUR - WORKSHOP_START_HOUR) * 60;
const WORKSHOP_SNAP_MINUTES = 15;
const WORKSHOP_DEFAULT_HOURS = 1;
const WORKSHOP_STAGE_SEQUENCE = ['BUS_4X4', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];

if (typeof CRM_BACKUP_STORAGE_KEYS !== 'undefined' && !CRM_BACKUP_STORAGE_KEYS.includes(WORKSHOP_PLAN_STORAGE_KEY)) {
  CRM_BACKUP_STORAGE_KEYS.push(WORKSHOP_PLAN_STORAGE_KEY);
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

function workshopSnapMinutes(value = 0) {
  return Math.round(Number(value || 0) / WORKSHOP_SNAP_MINUTES) * WORKSHOP_SNAP_MINUTES;
}

function workshopClampStartMinutes(value = 0) {
  return Math.max(0, Math.min(WORKSHOP_DAY_MINUTES - WORKSHOP_SNAP_MINUTES, workshopSnapMinutes(value)));
}

function workshopClampDurationHours(value = WORKSHOP_DEFAULT_HOURS, startMinutes = 0) {
  const requestedMinutes = workshopSnapMinutes(Math.max(WORKSHOP_SNAP_MINUTES, Number(value || WORKSHOP_DEFAULT_HOURS) * 60));
  const available = Math.max(WORKSHOP_SNAP_MINUTES, WORKSHOP_DAY_MINUTES - workshopClampStartMinutes(startMinutes));
  return Math.min(requestedMinutes, available) / 60;
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

function workshopLoadPlans() {
  const rows = typeof loadJson === 'function' ? loadJson(WORKSHOP_PLAN_STORAGE_KEY, []) : [];
  return Array.isArray(rows) ? rows.filter(row => row && row.id && row.vehicleKey && WORKSHOP_STAGE_SEQUENCE.includes(row.stage)) : [];
}

function workshopSavePlans(rows = []) {
  if (typeof saveJson === 'function') saveJson(WORKSHOP_PLAN_STORAGE_KEY, rows);
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
  return typeof selectedVehicle === 'function' ? selectedVehicle(cleanKey) : null;
}

function workshopPlanId(vehicleKeyValue = '', stage = '') {
  return `${normalizePmbStage(stage)}::${String(vehicleKeyValue || '').trim()}`;
}

function workshopEntryDate(entry = {}) {
  const date = parseIsoTimestamp(entry.startAt || '');
  return date ? workshopDateKey(date) : '';
}

function workshopEntryInterval(entry = {}) {
  const date = parseIsoTimestamp(entry.startAt || '');
  const start = date ? workshopClampStartMinutes(workshopMinuteOffset(date)) : 0;
  const hours = workshopClampDurationHours(entry.hours, start);
  return { start, end: start + hours * 60, hours };
}

function workshopHasConflict(candidate = {}, rows = workshopLoadPlans()) {
  if (!candidate.bay || candidate.status === 'completed') return null;
  const candidateDate = workshopEntryDate(candidate);
  const interval = workshopEntryInterval(candidate);
  return rows.find(row => {
    if (row.id === candidate.id || row.status === 'completed') return false;
    if (row.stage !== candidate.stage || Number(row.bay) !== Number(candidate.bay)) return false;
    if (workshopEntryDate(row) !== candidateDate) return false;
    const other = workshopEntryInterval(row);
    return workshopIntervalsOverlap(interval.start, interval.end, other.start, other.end);
  }) || null;
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
  return `${workshopTimeLabelFromMinutes(interval.start)}–${workshopTimeLabelFromMinutes(interval.end)}`;
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
  const def = pmbStageJobDef(normalizedStage);
  return app.data.filter(vehicle => {
    if (statusCategory(vehicle) !== 'pmb') return false;
    if (def && pdcJobComplete(vehicle, def)) return false;
    const isCurrentStage = normalizePmbStage(inferredPmbStage(vehicle)) === normalizedStage;
    const isRequired = def ? pdcJobRequired(vehicle, def) : false;
    return isRequired || isCurrentStage;
  }).sort((a, b) => String(displayStockNumber(a) || '').localeCompare(String(displayStockNumber(b) || '')));
}

function workshopVehicleSearchText(vehicle = {}) {
  return [vehicleKey(vehicle), displayStockNumber(vehicle), vehicle.keyNumber, vehicle.pdcJobcard, vehicleCustomerName(vehicle), vehicle.vehicle, vehicle.toyotaVehicle, consultantName(vehicle)]
    .filter(Boolean).join(' ').toLowerCase();
}

function workshopQueueCardHtml(vehicle = {}) {
  const key = vehicleKey(vehicle);
  const blocked = isPdcBlocked(vehicle);
  return `<article class="workshop-queue-card ${blocked ? 'is-blocked' : ''}" draggable="true" data-workshop-vehicle-key="${escapeHtml(key)}" title="Drag onto a bay at the required start time">
    <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small>${escapeHtml(vehicle.keyNumber ? `Key ${vehicle.keyNumber}` : vehicle.pdcJobcard ? `JC ${vehicle.pdcJobcard}` : vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')}</small>
    ${blocked ? '<em>STOPPAGE</em>' : ''}
  </article>`;
}

function workshopOtherDateCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const date = parseIsoTimestamp(entry.startAt || '');
  return `<button class="workshop-other-date-card" type="button" data-workshop-open-plan="${escapeHtml(entry.id)}" data-workshop-open-date="${escapeHtml(workshopEntryDate(entry))}">
    <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(date ? date.toLocaleDateString('en-AU', { weekday: 'short', day: '2-digit', month: '2-digit' }) : 'Date unknown')} · Bay ${escapeHtml(entry.bay)}</span>
  </button>`;
}

function workshopPlanChipHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  const interval = workshopEntryInterval(entry);
  const left = (interval.start / WORKSHOP_DAY_MINUTES) * 100;
  const width = ((interval.end - interval.start) / WORKSHOP_DAY_MINUTES) * 100;
  const actualBay = pmbBayNumber(vehicle, entry.stage);
  const started = Number(actualBay) === Number(entry.bay);
  const blocked = isPdcBlocked(vehicle);
  const selected = workshopState().selectedPlanId === entry.id;
  const classes = [blocked ? 'is-blocked' : '', started ? 'is-started' : '', selected ? 'is-selected' : ''].filter(Boolean).join(' ');
  return `<article class="workshop-plan-chip ${classes}" draggable="true" data-workshop-plan-id="${escapeHtml(entry.id)}" style="--plan-left:${left}%;--plan-width:${width}%;" title="${escapeHtml(`${workshopEntryTimeLabel(entry)} · click for job details · drag to reschedule`)}">
    <button type="button" data-workshop-select-plan="${escapeHtml(entry.id)}">
      <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
      <span>${escapeHtml(vehicle.keyNumber ? `Key ${vehicle.keyNumber}` : vehicle.pdcJobcard ? `JC ${vehicle.pdcJobcard}` : vehicleCustomerName(vehicle) || 'Unknown')}</span>
      <small>${escapeHtml(workshopEntryTimeLabel(entry))}</small>
    </button>
    <span class="workshop-plan-resize" data-workshop-resize-plan="${escapeHtml(entry.id)}" title="Drag to change duration"></span>
  </article>`;
}

function workshopCompletedCardHtml(entry = {}) {
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return '';
  return `<button class="workshop-completed-card" type="button" data-workshop-select-plan="${escapeHtml(entry.id)}">
    <strong>✓ ${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')}</strong>
    <span>${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</span>
    <small>Bay ${escapeHtml(entry.bay)} · ${escapeHtml(workshopEntryTimeLabel(entry))}</small>
  </button>`;
}

function workshopTimeAxisHtml() {
  return Array.from({ length: WORKSHOP_END_HOUR - WORKSHOP_START_HOUR + 1 }, (_, index) => {
    const left = (index / (WORKSHOP_END_HOUR - WORKSHOP_START_HOUR)) * 100;
    return `<span style="left:${left}%">${escapeHtml(workshopTimeLabelFromMinutes(index * 60))}</span>`;
  }).join('');
}

function workshopBayRowsHtml(stage = '', dateKey = '', rows = []) {
  const count = pmbStageBayCount(stage);
  return Array.from({ length: count }, (_, index) => {
    const bay = index + 1;
    const plans = rows.filter(entry => entry.stage === stage && Number(entry.bay) === bay && workshopEntryDate(entry) === dateKey && entry.status !== 'completed')
      .sort((a, b) => String(a.startAt).localeCompare(String(b.startAt)));
    const started = plans.find(entry => {
      const vehicle = workshopVehicle(entry.vehicleKey);
      return vehicle && Number(pmbBayNumber(vehicle, stage)) === bay;
    });
    const assignee = started ? cleanNavisionText(started.assignee || pmbBayMechanic(workshopVehicle(started.vehicleKey))) : '';
    return `<div class="workshop-bay-row">
      <div class="workshop-bay-label"><strong>Bay ${workshopPad(bay)}</strong><span>${escapeHtml(assignee || (stage === 'TYRE' && bay === 2 ? 'Wheel alignment' : plans.length ? `${plans.length} planned` : 'Available'))}</span></div>
      <div class="workshop-bay-lane" data-workshop-drop-bay="${bay}" data-workshop-drop-stage="${escapeHtml(stage)}">
        ${plans.map(workshopPlanChipHtml).join('')}
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

function workshopDetailHtml(entry = null) {
  if (!entry) return `<div class="workshop-job-detail is-empty"><strong>Job details</strong><span>Select a planned vehicle to view, start, complete, reschedule or remove it.</span></div>`;
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (!vehicle) return `<div class="workshop-job-detail is-empty"><strong>Vehicle unavailable</strong><span>Remove this stale planner entry.</span></div>`;
  const start = parseIsoTimestamp(entry.startAt || '');
  const localValue = start ? `${workshopDateKey(start)}T${workshopPad(start.getHours())}:${workshopPad(start.getMinutes())}` : '';
  const actualBay = pmbBayNumber(vehicle, entry.stage);
  const started = Number(actualBay) === Number(entry.bay);
  const completed = entry.status === 'completed';
  return `<form class="workshop-job-detail" data-workshop-detail-form data-workshop-plan-form-id="${escapeHtml(entry.id)}">
    <div class="workshop-detail-identity">
      <strong>${escapeHtml(displayStockNumber(vehicle) || vehicle.order || 'No stock')} · ${escapeHtml(vehicleCustomerName(vehicle) || 'Unknown customer')}</strong>
      <span>${escapeHtml(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle')} · ${escapeHtml(pmbStageLabel(entry.stage))} Bay ${escapeHtml(entry.bay)}${started ? ' · IN BAY NOW' : ' · PLANNED'}</span>
    </div>
    <label><span>Start</span><input name="startAt" type="datetime-local" step="900" value="${escapeHtml(localValue)}" required ${completed ? 'disabled' : ''} /></label>
    <label><span>Hours</span><input name="hours" type="number" min="0.25" max="8" step="0.25" value="${escapeHtml(entry.hours)}" required ${completed ? 'disabled' : ''} /></label>
    <label><span>Technician</span><select name="assignee" ${completed ? 'disabled' : ''}>${workshopMechanicOptions(entry.assignee || pmbBayMechanic(vehicle))}</select></label>
    <div class="workshop-detail-actions">
      ${completed ? '<span class="badge success">Completed</span>' : '<button class="primary" type="submit">Save plan</button>'}
      <button class="small-button" type="button" data-workshop-open-vehicle="${escapeHtml(entry.vehicleKey)}">Open vehicle</button>
      ${completed ? '' : `<button class="small-button" type="button" data-workshop-start-plan="${escapeHtml(entry.id)}" ${started ? 'disabled' : ''}>${started ? 'In bay' : 'Start in bay'}</button>
      <button class="small-button active-lite" type="button" data-workshop-complete-plan="${escapeHtml(entry.id)}">Complete work</button>`}
      <button class="text-button danger-text" type="button" data-workshop-remove-plan="${escapeHtml(entry.id)}">Remove plan</button>
    </div>
  </form>`;
}

function renderWorkshopPlanner() {
  const root = document.querySelector('#workshop-planner-root');
  if (!root) return;
  const state = workshopState();
  let plans = workshopSyncCompletedPlans();
  if (state.selectedPlanId && !plans.some(entry => entry.id === state.selectedPlanId)) state.selectedPlanId = '';
  const selected = plans.find(entry => entry.id === state.selectedPlanId) || null;
  const stage = WORKSHOP_STAGE_SEQUENCE.includes(state.stage) ? state.stage : 'FABRICATION';
  const dateKey = state.date;
  const search = String(state.search || '').trim().toLowerCase();
  const activePlans = plans.filter(entry => entry.stage === stage && entry.status !== 'completed');
  const plannedKeys = new Set(activePlans.map(entry => entry.vehicleKey));
  const queue = workshopStageVehicles(stage).filter(vehicle => !plannedKeys.has(vehicleKey(vehicle)) && (!search || workshopVehicleSearchText(vehicle).includes(search)));
  const otherDates = activePlans.filter(entry => workshopEntryDate(entry) !== dateKey);
  const completed = plans.filter(entry => entry.stage === stage && entry.status === 'completed' && workshopEntryDate(entry) === dateKey);
  const todaysPlans = activePlans.filter(entry => workshopEntryDate(entry) === dateKey);
  const stageTabs = WORKSHOP_STAGE_SEQUENCE.map(value => `<button type="button" class="workshop-stage-tab ${value === stage ? 'active' : ''}" data-workshop-stage="${escapeHtml(value)}"><span>${escapeHtml(pmbStageLabel(value))}</span><strong>${workshopStageVehicles(value).length}</strong></button>`).join('');
  root.innerHTML = `<div class="workshop-planner">
    <header class="workshop-planner-header">
      <div><h2>Workshop bay planner</h2><p>Plan future jobs without changing the live physical bay. Workdays are Monday–Friday, 8:00am–4:00pm.</p></div>
      <div class="workshop-date-controls">
        <button class="small-button" type="button" data-workshop-date-shift="-1">‹ Previous</button>
        <input type="date" data-workshop-date value="${escapeHtml(dateKey)}" />
        <button class="small-button" type="button" data-workshop-today>Today</button>
        <button class="small-button" type="button" data-workshop-date-shift="1">Next ›</button>
      </div>
    </header>
    <div class="workshop-date-summary"><strong>${escapeHtml(workshopDateLabel(dateKey))}</strong><span>${todaysPlans.length} planned · ${completed.length} completed · ${queue.length} waiting</span></div>
    <nav class="workshop-stage-tabs" aria-label="Workshop departments">${stageTabs}</nav>
    ${workshopDetailHtml(selected)}
    <div class="workshop-board-shell">
      <aside class="workshop-side-panel workshop-waiting-panel">
        <div class="workshop-side-heading"><strong>Awaiting schedule</strong><span>${queue.length}</span></div>
        <label class="workshop-search"><span>Search vehicles</span><input type="search" data-workshop-search value="${escapeHtml(state.search || '')}" placeholder="Stock, key, customer…" /></label>
        <div class="workshop-side-list">${queue.map(workshopQueueCardHtml).join('') || '<div class="workshop-empty">No unscheduled vehicles in this department.</div>'}</div>
        ${otherDates.length ? `<div class="workshop-other-dates"><strong>Scheduled other days</strong>${otherDates.map(workshopOtherDateCardHtml).join('')}</div>` : ''}
      </aside>
      <section class="workshop-timeline-scroll">
        <div class="workshop-timeline">
          <div class="workshop-time-header"><div class="workshop-bay-label"><strong>${escapeHtml(pmbStageLabel(stage))} bays</strong><span>${escapeHtml(`${pmbStageBayCount(stage)} physical bay${pmbStageBayCount(stage) === 1 ? '' : 's'}`)}</span></div><div class="workshop-time-axis">${workshopTimeAxisHtml()}</div></div>
          <div class="workshop-now-line" data-workshop-now-line hidden><span>Now</span></div>
          ${workshopBayRowsHtml(stage, dateKey, plans)}
        </div>
      </section>
      <aside class="workshop-side-panel workshop-completed-panel">
        <div class="workshop-side-heading"><strong>Completed</strong><span>${completed.length}</span></div>
        <div class="workshop-side-list">${completed.map(workshopCompletedCardHtml).join('') || '<div class="workshop-empty">Nothing completed on this board date.</div>'}</div>
      </aside>
    </div>
    <footer class="workshop-board-note"><strong>How to use:</strong> drag a waiting vehicle onto a bay and time. Drag a planned block to reschedule it. Select it to adjust duration or technician, then use <b>Start in bay</b> when the vehicle physically enters the bay.</footer>
  </div>`;
  bindWorkshopPlanner(root);
  updateWorkshopNowLine(root);
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
  root.querySelector('[data-workshop-search]')?.addEventListener('input', event => {
    workshopState().search = event.target.value;
    renderWorkshopPlanner();
    const input = document.querySelector('[data-workshop-search]');
    input?.focus();
    input?.setSelectionRange(input.value.length, input.value.length);
  });
  root.querySelectorAll('[data-workshop-vehicle-key]').forEach(card => card.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'copy';
    event.dataTransfer.setData('application/x-workshop-vehicle-key', card.dataset.workshopVehicleKey);
    event.dataTransfer.setData('text/plain', card.dataset.workshopVehicleKey);
  }));
  root.querySelectorAll('[data-workshop-plan-id]').forEach(chip => chip.addEventListener('dragstart', event => {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('application/x-workshop-plan-id', chip.dataset.workshopPlanId);
  }));
  root.querySelectorAll('[data-workshop-drop-bay]').forEach(lane => bindWorkshopLane(lane));
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
  root.querySelector('[data-workshop-detail-form]')?.addEventListener('submit', saveWorkshopDetailForm);
  root.querySelector('[data-workshop-open-vehicle]')?.addEventListener('click', event => openVehicleModal(event.currentTarget.dataset.workshopOpenVehicle));
  root.querySelector('[data-workshop-start-plan]')?.addEventListener('click', event => startWorkshopPlan(event.currentTarget.dataset.workshopStartPlan));
  root.querySelector('[data-workshop-complete-plan]')?.addEventListener('click', event => completeWorkshopPlan(event.currentTarget.dataset.workshopCompletePlan));
  root.querySelector('[data-workshop-remove-plan]')?.addEventListener('click', event => removeWorkshopPlan(event.currentTarget.dataset.workshopRemovePlan));
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
    const startMinutes = workshopClampStartMinutes(((event.clientX - rect.left) / Math.max(1, rect.width)) * WORKSHOP_DAY_MINUTES);
    const planId = event.dataTransfer.getData('application/x-workshop-plan-id');
    const vehicleKeyValue = event.dataTransfer.getData('application/x-workshop-vehicle-key') || event.dataTransfer.getData('text/plain');
    scheduleWorkshopVehicle({ planId, vehicleKeyValue, stage: lane.dataset.workshopDropStage, bay: Number(lane.dataset.workshopDropBay), dateKey: workshopState().date, startMinutes });
  });
}

function scheduleWorkshopVehicle({ planId = '', vehicleKeyValue = '', stage = '', bay = 0, dateKey = '', startMinutes = 0 } = {}) {
  const rows = workshopLoadPlans();
  const existing = rows.find(entry => entry.id === planId) || rows.find(entry => entry.id === workshopPlanId(vehicleKeyValue, stage));
  const vehicle = workshopVehicle(existing?.vehicleKey || vehicleKeyValue);
  if (!vehicle) return;
  const normalizedStage = normalizePmbStage(stage);
  const start = workshopDateAtOffset(dateKey, startMinutes);
  const defaultHours = existing?.hours || pmbBayHours(vehicle) || WORKSHOP_DEFAULT_HOURS;
  const hours = workshopClampDurationHours(defaultHours, startMinutes);
  const now = nowIsoString();
  const candidate = {
    ...(existing || {}),
    id: existing?.id || workshopPlanId(vehicleKey(vehicle), normalizedStage),
    vehicleKey: vehicleKey(vehicle),
    stage: normalizedStage,
    bay: Number(bay),
    startAt: start.toISOString(),
    hours,
    assignee: existing?.assignee || pmbBayMechanic(vehicle) || '',
    status: existing?.status === 'started' ? 'started' : 'planned',
    createdAt: existing?.createdAt || now,
    updatedAt: now,
  };
  const conflict = workshopHasConflict(candidate, rows);
  if (conflict) {
    const other = workshopVehicle(conflict.vehicleKey);
    window.alert(`Bay ${candidate.bay} already has ${displayStockNumber(other) || 'another vehicle'} planned at that time. Choose another time or bay.`);
    return;
  }
  const nextRows = existing ? rows.map(entry => entry.id === existing.id ? candidate : entry) : [...rows, candidate];
  if (typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, existing ? 'Workshop plan rescheduled' : 'Workshop plan created', {
    stage: pmbStageLabel(normalizedStage), bay: candidate.bay, startAt: candidate.startAt, hours: candidate.hours, assignee: candidate.assignee || 'Unassigned'
  });
  workshopSavePlans(nextRows);
  workshopState().selectedPlanId = candidate.id;
  renderWorkshopPlanner();
}

function saveWorkshopDetailForm(event) {
  event.preventDefault();
  const form = event.currentTarget;
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === form.dataset.workshopPlanFormId);
  if (!entry) return;
  const data = new FormData(form);
  const start = new Date(String(data.get('startAt') || ''));
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
  const candidate = {
    ...entry,
    startAt: start.toISOString(),
    hours: workshopClampDurationHours(Number(data.get('hours') || WORKSHOP_DEFAULT_HOURS), startMinutes),
    assignee: cleanNavisionText(data.get('assignee') || ''),
    updatedAt: nowIsoString(),
  };
  const conflict = workshopHasConflict(candidate, rows);
  if (conflict) {
    const other = workshopVehicle(conflict.vehicleKey);
    window.alert(`That time overlaps ${displayStockNumber(other) || 'another vehicle'} in Bay ${candidate.bay}.`);
    return;
  }
  workshopSavePlans(rows.map(row => row.id === entry.id ? candidate : row));
  const vehicle = workshopVehicle(entry.vehicleKey);
  if (vehicle && typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, 'Workshop plan updated', {
    stage: pmbStageLabel(entry.stage), bay: entry.bay, startAt: candidate.startAt, hours: candidate.hours, assignee: candidate.assignee || 'Unassigned'
  });
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
  await assignPmbVehicleToBay(entry.vehicleKey, entry.stage, entry.bay, entry.startAt);
  const refreshed = workshopVehicle(entry.vehicleKey);
  if (!refreshed || Number(pmbBayNumber(refreshed, entry.stage)) !== Number(entry.bay)) return;
  saveVehicleEdits(entry.vehicleKey, {
    pmbBayScheduledStartAt: entry.startAt,
    pmbBayEstimatedHours: String(entry.hours),
    pmbBayMechanic: cleanNavisionText(entry.assignee || ''),
  }, { render: false });
  const next = { ...entry, status: 'started', startedAt: entry.startedAt || nowIsoString(), updatedAt: nowIsoString() };
  workshopSavePlans(rows.map(row => row.id === entry.id ? next : row));
  renderWorkshopPlanner();
}

function completeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry || !vehicle) return;
  if (Number(pmbBayNumber(vehicle, entry.stage)) !== Number(entry.bay)) {
    window.alert('Use “Start in bay” first. This keeps the live physical-bay record accurate before work is completed.');
    return;
  }
  completePmbBayWork(entry.vehicleKey, entry.stage);
  const refreshed = workshopVehicle(entry.vehicleKey);
  const def = refreshed ? pmbStageJobDef(entry.stage) : null;
  if (!refreshed || !def || !pdcJobComplete(refreshed, def)) return;
  const next = { ...entry, status: 'completed', completedAt: refreshed[def.completeAtKey] || nowIsoString(), updatedAt: nowIsoString() };
  workshopSavePlans(rows.map(row => row.id === entry.id ? next : row));
  renderWorkshopPlanner();
}

function removeWorkshopPlan(planId = '') {
  const rows = workshopLoadPlans();
  const entry = rows.find(row => row.id === planId);
  const vehicle = entry ? workshopVehicle(entry.vehicleKey) : null;
  if (!entry) return;
  if (!window.confirm(`Remove the workshop plan for ${displayStockNumber(vehicle) || 'this vehicle'}?\n\nThis removes only the future plan; it does not delete or move the vehicle.`)) return;
  if (vehicle && typeof recordVehicleAudit === 'function') recordVehicleAudit(vehicle, 'Workshop plan removed', {
    stage: pmbStageLabel(entry.stage), bay: entry.bay, startAt: entry.startAt
  });
  workshopSavePlans(rows.filter(row => row.id !== planId));
  workshopState().selectedPlanId = '';
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
  const original = workshopEntryInterval(entry);
  const onMove = moveEvent => {
    const deltaMinutes = workshopSnapMinutes(((moveEvent.clientX - originX) / Math.max(1, lane.getBoundingClientRect().width)) * WORKSHOP_DAY_MINUTES);
    const hours = workshopClampDurationHours((original.end - original.start + deltaMinutes) / 60, original.start);
    chip.style.setProperty('--plan-width', `${(hours * 60 / WORKSHOP_DAY_MINUTES) * 100}%`);
    chip.dataset.previewHours = String(hours);
  };
  const onUp = () => {
    document.removeEventListener('pointermove', onMove);
    document.removeEventListener('pointerup', onUp);
    const hours = Number(chip.dataset.previewHours || entry.hours);
    delete chip.dataset.previewHours;
    const candidate = { ...entry, hours, updatedAt: nowIsoString() };
    const conflict = workshopHasConflict(candidate, rows);
    if (conflict) {
      window.alert('That duration would overlap another vehicle in this bay.');
      renderWorkshopPlanner();
      return;
    }
    workshopSavePlans(rows.map(row => row.id === entry.id ? candidate : row));
    workshopState().selectedPlanId = entry.id;
    renderWorkshopPlanner();
  };
  document.addEventListener('pointermove', onMove);
  document.addEventListener('pointerup', onUp);
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    WORKSHOP_START_HOUR,
    WORKSHOP_END_HOUR,
    WORKSHOP_DAY_MINUTES,
    WORKSHOP_STAGE_SEQUENCE,
    workshopIsWorkday,
    workshopCoerceWorkDate,
    workshopShiftWorkday,
    workshopSnapMinutes,
    workshopClampStartMinutes,
    workshopClampDurationHours,
    workshopIntervalsOverlap,
    workshopDateKey,
    workshopDateFromKey,
    workshopLoadPlans,
    workshopHasConflict,
    scheduleWorkshopVehicle,
  };
}
