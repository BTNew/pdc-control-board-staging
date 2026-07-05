const EDITS_KEY = 'vehicleTrackingCoreNavisionOnlyEdits:v1';
const ADDED_KEY = 'vehicleTrackingCoreNavisionOnlyVehicles:v1';
const DELETED_KEY = 'vehicleTrackingCoreNavisionOnlyDeleted:v1';

const JOB_DEFS = [
  { key: 'tint', label: 'Tint', requireKey: 'pdcRequiresTint', completeKey: 'pdcCompleteTint' },
  { key: 'hoist', label: 'Hoist', requireKey: 'pdcRequiresHoist', completeKey: 'pdcCompleteHoist' },
  { key: 'fitting', label: 'Fitting', requireKey: 'pdcRequiresFitting', completeKey: 'pdcCompleteFitting', legacyRequireKey: 'pdcRequiresBuild', legacyCompleteKey: 'pdcCompleteBuild' },
  { key: 'fabrication', label: 'Fabrication', requireKey: 'pdcRequiresFabrication', completeKey: 'pdcCompleteFabrication' },
  { key: 'electrical', label: 'Electrical', requireKey: 'pdcRequiresElectrical', completeKey: 'pdcCompleteElectrical' },
  { key: 'tyre', label: 'Tyre bay', requireKey: 'pdcRequiresTyre', completeKey: 'pdcCompleteTyre' },
  { key: 'pitInspection', label: 'Pit Inspection', requireKey: 'pdcRequiresPitInspection', completeKey: 'pdcCompletePitInspection' },
  { key: 'parts', label: 'Parts', requireKey: 'pdcRequiresParts', completeKey: 'pdcCompleteParts' },
];

const PMB_STAGES = ['PMB', 'TINT', 'HOIST', 'FITTING', 'FABRICATION', 'ELECTRICAL', 'TYRE', 'PIT_INSPECTION'];

const state = {
  filter: 'all',
  search: '',
  stage: '',
  vehicles: [],
};

function $(selector) { return document.querySelector(selector); }
function $$(selector) { return Array.from(document.querySelectorAll(selector)); }

function loadJson(key, fallback) {
  try { return JSON.parse(localStorage.getItem(key) || JSON.stringify(fallback)); }
  catch { return fallback; }
}

function escapeHtml(value = '') {
  return String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[char]));
}

function clean(value = '') { return String(value || '').trim(); }

function isBlankStock(value) {
  const stock = clean(value);
  return !stock || stock === '0' || /^TBA$/i.test(stock) || stock.startsWith('PENDING-');
}

function vehicleKey(vehicle = {}) {
  const stock = clean(vehicle.stock);
  if (stock && !isBlankStock(stock)) return stock;
  return clean(vehicle.order || vehicle.id || stock);
}

function buildVehicleData() {
  const base = JSON.parse(JSON.stringify(window.VEHICLE_TRACKING_DATA?.vehicles || []));
  const edits = loadJson(EDITS_KEY, {});
  const added = loadJson(ADDED_KEY, []);
  const deleted = new Set(loadJson(DELETED_KEY, []));
  return base.concat(added)
    .filter(vehicle => !deleted.has(vehicleKey(vehicle)))
    .map(vehicle => ({ ...vehicle, ...(edits[vehicleKey(vehicle)] || edits[vehicle.stock] || {}) }));
}

function normalizeStage(value = '') {
  const text = clean(value).toUpperCase();
  if (!text) return '';
  if (text.includes('TINT')) return 'TINT';
  if ((text.includes('EXPRESS') && text.includes('HOIST')) || text.includes('PITS HOIST') || text.includes('PIT HOIST')) return 'HOIST';
  if (text.includes('HOIST') || text.includes('SUSPENSION') || text.includes('LIFT')) return 'HOIST';
  if (text.includes('FITTING') || text.includes('FITMENT') || text.includes('FITOUT') || text.includes('FIT OUT') || text.includes('BUILD') || text.includes('PDI') || text.includes('PRE DELIVERY') || text.includes('PRE-DELIVERY')) return 'FITTING';
  if (text.includes('FAB') || text.includes('TRAY') || text.includes('BODY')) return 'FABRICATION';
  if (text.includes('ELECTRICAL') || text.includes('AUTO ELEC') || text.includes('AUTO-ELEC') || text.includes('12V') || text.includes('UHF')) return 'ELECTRICAL';
  if (text.includes('TYRE') || text.includes('TIRE') || text.includes('WHEEL')) return 'TYRE';
  if (text.includes('PIT') || text.includes('INSPECTION')) return 'PIT_INSPECTION';
  return '';
}

function vehicleStage(vehicle = {}) {
  const pdc = clean(vehicle.pdcLocation).toUpperCase();
  if (pdc === 'RFT') return 'RFT';
  if (pdc === 'YH') return 'YH';
  const pmbStage = normalizeStage(vehicle.pmbStage || vehicle.pdcWorkStage || vehicle.workStage || '');
  if (pdc === 'PMB') return pmbStage || 'PMB';
  const nav = clean(vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || '').toUpperCase();
  if (nav.includes('YARD HOLD')) return 'YH';
  if (nav.includes('READY') && nav.includes('TRANSPORT')) return 'RFT';
  return pmbStage || 'NAVISION';
}

function stageLabel(stage = '') {
  return ({
    YH: 'Yard Hold',
    PMB: 'PMB',
    RFT: 'RFT',
    TINT: 'Tint',
    HOIST: 'Hoist',
    FITTING: 'Fitting',
    FABRICATION: 'Fabrication',
    ELECTRICAL: 'Electrical',
    TYRE: 'Tyre bay',
    PIT_INSPECTION: 'Pit Inspection',
    NAVISION: 'Navision',
  })[stage] || stage || 'Unallocated';
}

function isBlocked(vehicle = {}) {
  return Boolean(clean(vehicle.pdcBlockReason || vehicle.pdcPartsStoppageReason) || vehicle.pdcPartsStoppage === true);
}

function pdcJobRequired(vehicle = {}, def = {}) {
  if (vehicle[def.requireKey] === true || (def.legacyRequireKey && vehicle[def.legacyRequireKey] === true)) return true;
  if (vehicle[def.completeKey] === true || (def.legacyCompleteKey && vehicle[def.legacyCompleteKey] === true)) return true;
  if (def.key === 'parts') return !isBlankStock(vehicle.stock || vehicle.batch || vehicle.toyotaBatch) || vehicle.pdcPartsOrdered === true || vehicle.pdcPartsReceived === true || vehicle.pdcCompleteParts === true;
  if (def.key === 'tint') return vehicle.tintRequired === true;
  if (def.key === 'fitting') return vehicle.pdcBuildRequired === true;
  if (def.key === 'electrical') return vehicle.electricalRequired === true;
  if (def.key === 'fabrication') return vehicle.fabricationRequired === true || vehicle.trayOrdered === true || vehicle.trayFitmentComplete === true;
  return false;
}

function pdcJobComplete(vehicle = {}, def = {}) {
  if (vehicle[def.completeKey] === true || (def.legacyCompleteKey && vehicle[def.legacyCompleteKey] === true)) return true;
  if (def.key === 'parts') return vehicle.pdcPartsReceived === true;
  if (def.key === 'fabrication') return vehicle.trayFitmentComplete === true;
  return false;
}

function statusClass(vehicle = {}) {
  if (isBlocked(vehicle)) return 'blocked';
  const stage = vehicleStage(vehicle);
  if (stage === 'RFT') return 'rft';
  if (stage === 'YH') return 'yh';
  if (PMB_STAGES.includes(stage)) return 'pmb';
  return '';
}

function matchesFilter(vehicle = {}) {
  const stage = vehicleStage(vehicle);
  if (state.filter === 'pmb' && !PMB_STAGES.includes(stage)) return false;
  if (state.filter === 'blocked' && !isBlocked(vehicle)) return false;
  if (state.filter === 'rft' && stage !== 'RFT') return false;
  if (state.stage) {
    if (state.stage === 'PMB' && !PMB_STAGES.includes(stage)) return false;
    else if (state.stage === 'PARTS') {
      const partsDef = JOB_DEFS.find(def => def.key === 'parts');
      if (!partsDef || !pdcJobRequired(vehicle, partsDef) || pdcJobComplete(vehicle, partsDef)) return false;
    }
    else if (stage !== state.stage) return false;
  }
  if (state.search) {
    const haystack = [vehicle.stock, vehicle.batch, vehicle.order, vehicle.client, vehicle.toyotaCustomer, vehicle.vehicle, vehicle.toyotaVehicle, vehicle.colour, vehicle.prodMth, vehicle.toyotaStatus, vehicle.navisionSubLocationDescription].join(' ').toLowerCase();
    if (!haystack.includes(state.search.toLowerCase())) return false;
  }
  return true;
}

function renderCounts() {
  const vehicles = state.vehicles;
  $('#count-all').textContent = vehicles.length;
  $('#count-pmb').textContent = vehicles.filter(v => PMB_STAGES.includes(vehicleStage(v))).length;
  $('#count-blocked').textContent = vehicles.filter(isBlocked).length;
  $('#count-rft').textContent = vehicles.filter(v => vehicleStage(v) === 'RFT').length;
}

function jobChips(vehicle = {}) {
  const required = JOB_DEFS.filter(def => pdcJobRequired(vehicle, def));
  if (!required.length) return '<span class="job-chip">No PDC jobs flagged</span>';
  return required.map(def => {
    const done = pdcJobComplete(vehicle, def);
    const blocked = def.key === 'parts' && isBlocked(vehicle);
    return `<span class="job-chip ${done ? 'done' : 'required'} ${blocked ? 'blocked' : ''}">${escapeHtml(def.label)} ${done ? '✓' : '•'}</span>`;
  }).join('');
}

function renderList() {
  const list = $('#mobile-list');
  const rows = state.vehicles.filter(matchesFilter).slice(0, 150);
  $('#empty-state').hidden = rows.length > 0;
  list.innerHTML = rows.map(vehicle => {
    const stage = vehicleStage(vehicle);
    const client = clean(vehicle.client || vehicle.toyotaCustomer || 'No client');
    const vehicleName = clean(vehicle.vehicle || vehicle.toyotaVehicle || 'Vehicle not set');
    return `
      <article class="vehicle-card">
        <div class="vehicle-top">
          <div>
            <h2 class="vehicle-title">${escapeHtml(client)}</h2>
            <p class="vehicle-meta">${escapeHtml(vehicleName)} · Stock ${escapeHtml(vehicle.stock || '—')}</p>
          </div>
          <span class="status-pill ${statusClass(vehicle)}">${escapeHtml(stageLabel(stage))}</span>
        </div>
        <div class="card-grid">
          <div class="card-field"><span>Batch</span><strong>${escapeHtml(vehicle.batch || vehicle.toyotaBatch || '—')}</strong></div>
          <div class="card-field"><span>Production</span><strong>${escapeHtml(vehicle.prodMth || '—')}</strong></div>
          <div class="card-field"><span>ETA</span><strong>${escapeHtml(vehicle.etaAtDealer || vehicle.navisionKewdaleEta || '—')}</strong></div>
          <div class="card-field"><span>Status</span><strong>${escapeHtml(vehicle.navisionSubLocationDescription || vehicle.toyotaStatus || '—')}</strong></div>
        </div>
        <div class="job-row">${jobChips(vehicle)}</div>
      </article>`;
  }).join('');
}

function render() {
  renderCounts();
  renderList();
}

function bindEvents() {
  $$('.summary-card').forEach(button => {
    button.addEventListener('click', () => {
      state.filter = button.dataset.filter || 'all';
      $$('.summary-card').forEach(card => card.classList.toggle('active', card === button));
      renderList();
    });
  });
  $('#mobile-search').addEventListener('input', event => {
    state.search = event.target.value;
    renderList();
  });
  $('#mobile-stage-filter').addEventListener('change', event => {
    state.stage = event.target.value;
    renderList();
  });
}

function init() {
  state.vehicles = buildVehicleData();
  const report = window.VEHICLE_TRACKING_DATA?.report || {};
  $('#mobile-as-of').textContent = `${state.vehicles.length} vehicles · ${report.asOf || 'mobile quick view'}`;
  bindEvents();
  render();
}

document.addEventListener('DOMContentLoaded', init);
