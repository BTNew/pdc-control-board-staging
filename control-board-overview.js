(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.ControlBoardOverview = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';
  const labels = Object.freeze({ BUS_4X4: 'Bus 4×4', TINT: 'Tint', HOIST: 'Hoist', FITTING: 'Fitting', FABRICATION: 'Fabrication', ELECTRICAL: 'Electrical', TYRE: 'Tyre' });
  const activeStatuses = new Set(['queued', 'planned', 'started', 'stoppage']);
  const text = value => String(value == null ? '' : value).trim();
  const escape = value => text(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const stageLabel = stage => labels[stage] || text(stage);
  const identity = vehicle => ({
    key: text(vehicle.key_number) || '—', job: text(vehicle.job_card_number) || '—',
    stock: text(vehicle.stock_number) || '—', customer: text(vehicle.customer_name) || 'Customer not recorded',
    description: text(vehicle.vehicle_description) || [vehicle.make, vehicle.model].map(text).filter(Boolean).join(' ') || 'Vehicle details pending',
  });
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
    const rank = stage => { const index = order.indexOf(stage); return index < 0 ? order.length : index; };
    const bays = new Map();
    snapshot.board.bays.forEach(bay => {
      const id = text(bay.bay_id), stage = text(bay.stage_code);
      if (id && labels[stage] && !bay.deleted_at && !bays.has(id)) bays.set(id, { bay, stage, items: [], total: 0 });
    });
    const columns = [...bays.values()].sort((a, b) => rank(a.stage) - rank(b.stage) || Number(a.bay.bay_number) - Number(b.bay.bay_number) || text(a.bay.bay_id).localeCompare(text(b.bay.bay_id)));
    const waiting = [], bookedWork = new Set(), seenBookings = new Set(), seenCandidates = new Set(), seenBlocks = new Set();
    snapshot.board.bookings.forEach(source => {
      const id = text(source.booking_id), stage = text(source.stage_code), status = text(source.status);
      const vehicle = source.vehicle;
      if (!id || seenBookings.has(id) || !labels[stage] || !activeStatuses.has(status) || source.deleted_at || !visibleVehicle(vehicle)) return;
      seenBookings.add(id);
      const vehicleId = text(source.vehicle_id || vehicle.id);
      if (vehicleId) bookedWork.add(`${vehicleId}:${stage}`);
      const column = bays.get(text(source.bay_id));
      const item = { kind: 'booking', id, stage, status, vehicle, source, unassignedBay: !!source.bay_id && (!column || column.stage !== stage) };
      if (column && column.stage === stage) column.items.push(item);
      else waiting.push(item);
    });
    (snapshot.candidates || []).forEach(source => {
      const stage = text(source.stage_code), vehicle = source.vehicle, vehicleId = text(vehicle?.id);
      const id = `${vehicleId}:${stage}`;
      if (!vehicleId || !labels[stage] || !visibleVehicle(vehicle) || bookedWork.has(id) || seenCandidates.has(id)) return;
      seenCandidates.add(id);
      waiting.push({ kind: 'candidate', id, stage, status: 'waiting', vehicle, source, unassignedBay: false });
    });
    (snapshot.board.admin_blocks || []).forEach(source => {
      const id = text(source.admin_block_id || source.block_id || source.id), column = bays.get(text(source.bay_id));
      if (!id || seenBlocks.has(id) || !column || source.deleted_at || source.status === 'cancelled') return;
      seenBlocks.add(id);
      column.items.push({ kind: 'admin', id, stage: column.stage, status: 'admin', vehicle: {}, source });
    });
    const matches = (item, column) => {
      if (!search) return true;
      const person = identity(item.vehicle);
      return [person.key, person.job, person.stock, person.customer, person.description, stageLabel(item.stage), column ? `Bay ${column.bay.bay_number}` : 'Unallocated', column?.bay.display_name, item.source.label].map(text).join(' ').toLowerCase().includes(search);
    };
    columns.forEach(column => {
      column.items.sort(compareTime);
      column.total = column.items.length;
      column.items = column.items.filter(item => matches(item, column));
    });
    waiting.sort((a, b) => rank(a.stage) - rank(b.stage) || text(a.vehicle.stock_number).localeCompare(text(b.vehicle.stock_number), undefined, { numeric: true }) || compareTime(a, b));
    const matchedWaiting = waiting.filter(item => matches(item));
    return { columns, waiting: matchedWaiting, waitingTotal: waiting.length, totalBookings: seenBookings.size, totalWaiting: waiting.length, totalBays: columns.length, search,
      matchingItems: matchedWaiting.length + columns.reduce((n, column) => n + column.items.length, 0),
      stages: [...new Set(columns.map(column => column.stage))] };
  }

  function cardHtml(item, waiting = false) {
    if (item.kind === 'admin') return `<div class="control-board-bay-card is-admin" data-control-board-match><strong>${escape(item.source.label || 'Admin block')}</strong><span>Admin block</span></div>`;
    const person = identity(item.vehicle);
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

  function render(model) {
    const count = (shown, total) => model.search ? `${shown} / ${total}` : String(total);
    const empty = model.search ? 'No matches in this bay' : 'No bookings';
    const waiting = `<section class="control-board-bay-column is-unallocated" aria-label="Unallocated jobs"><header class="control-board-bay-heading"><span class="control-board-department">Waiting for a bay</span><h3>Unallocated <span>${count(model.waiting.length, model.waitingTotal)}</span></h3><small>Work awaiting a booking</small></header><div class="control-board-bay-jobs">${model.waiting.map(item => cardHtml(item, true)).join('') || `<p class="control-board-bay-empty">${model.search ? 'No matching unallocated jobs' : 'No unallocated jobs'}</p>`}</div></section>`;
    const columns = model.columns.map(column => {
      const bay = column.bay, label = stageLabel(column.stage), bayName = `Bay ${String(bay.bay_number).padStart(2, '0')}`;
      const technician = text(bay.technician_name) || 'Unassigned';
      const efficiency = Number(bay.efficiency_percent);
      return `<section class="control-board-bay-column station-${escape(column.stage.toLowerCase())}${bay.is_active === false ? ' is-inactive' : ''}" data-control-board-stage="${escape(column.stage)}" data-control-board-bay="${escape(bay.bay_id)}" aria-label="${escape(`${label} ${bayName}`)}">
        <header class="control-board-bay-heading"><span class="control-board-department">${escape(label)}</span><h3>${escape(bayName)} <span>${count(column.items.length, column.total)}</span></h3><small title="${escape(technician)}">${escape(technician)}${Number.isFinite(efficiency) && efficiency > 0 ? ` · ${escape(efficiency)}%` : ''}</small><button type="button" data-control-board-planner="${escape(column.stage)}">Open planner →</button>${bay.is_active === false ? '<b class="control-board-bay-inactive">Inactive · existing bookings only</b>' : ''}</header>
        <div class="control-board-bay-jobs">${column.items.map(item => cardHtml(item)).join('') || `<p class="control-board-bay-empty">${empty}</p>`}</div>
      </section>`;
    }).join('');
    return `<div class="control-board-overview-toolbar"><div><strong>${model.totalBays} bays · ${model.totalBookings} bookings · ${model.totalWaiting} unallocated</strong><span>${model.search ? `${model.matchingItems} matching jobs · ` : ''}Scroll sideways to see every bay. Jobs run from top to bottom in booking order.</span></div><div class="control-board-scroll-actions"><button type="button" data-control-board-scroll="-1" aria-label="Scroll bays left">←</button><button type="button" data-control-board-scroll="1" aria-label="Scroll bays right">→</button></div></div>
      <nav class="control-board-department-links" aria-label="Jump to workshop department">${model.stages.map(stage => `<button type="button" data-control-board-jump="${escape(stage)}">${escape(stageLabel(stage))}</button>`).join('')}<span class="control-board-job-legend"><i class="is-planned"></i>Planned <i class="is-started"></i>Live <i class="is-stoppage"></i>Stoppage <i class="is-admin"></i>Admin block</span></nav>
      ${model.search && !model.matchingItems ? '<p class="control-board-no-results" role="status">No matching jobs. Clear the search to see all work.</p>' : ''}
      <div class="control-board-bays-scroll" tabindex="0" role="region" aria-label="All workshop bays. Scroll horizontally to view more bays."><div class="control-board-bays-row">${waiting}${columns}</div></div>`;
  }
  return Object.freeze({ buildModel, render, stageLabel });
});
