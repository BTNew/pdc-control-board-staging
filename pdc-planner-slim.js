/* Slim planner queue; presentation only. Existing scheduling and shared Admin writes remain authoritative. */
(() => {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const recorded = value => value != null && !['','—','-','unknown','tba','not recorded'].includes(String(value).trim().toLowerCase());
  function jobCard(vehicle = {}, lines = []) {
    for (const key of ['pdcJobcard','jobcard','jobCard','jobcardNumber','jobCardNumber','job_card_number','jcJobcard','jc']) {
      if (recorded(vehicle[key])) return String(vehicle[key]).trim();
    }
    return [...new Set(lines.filter(line => line.active !== false).map(line => line.jobCardNumber || line.job_card_number).filter(recorded).map(String))].join(', ');
  }
  function summaryHtml({key, jc, customer, model, duration, parts, partsStatus} = {}) {
    const jcLabel = jc && /^JC/i.test(jc) ? jc : 'JC ' + (jc || 'Not recorded');
    return `<div class="planner-slim-details"><strong>Key ${esc(key || '—')} · ${esc(jcLabel)}</strong><span title="${esc(customer)}">${esc(customer || 'Customer not recorded')}</span><span title="${esc(model)}">${esc(model || 'Model not recorded')}</span><small>Booking time: ${esc(duration)}</small><small class="workshop-parts-line parts-${esc(partsStatus)}">Parts: ${esc(parts)}</small></div>`;
  }
  function recordedKey(vehicle = {}, boardRows = []) {
    const key = row => row.keyNumber || row.key_number || row.keyNo || row.keyTag || row.pdcKeyNumber || row.vehicleKeyNumber || '';
    if (recorded(key(vehicle))) return key(vehicle);
    const id = vehicle.sharedVehicleId || vehicle.__emailVehicleId || vehicle.id;
    if (!id) return '';
    const matches = boardRows.filter(row => (row.sharedVehicleId || row.__emailVehicleId || row.id) === id);
    return matches.length === 1 && recorded(key(matches[0])) ? key(matches[0]) : '';
  }
  function compactQueue(html, details) {
    // Preserve the original article's drag identity, disabled state and scheduling
    // controls verbatim. Only replace its descriptive content.
    return html.replace(/^(<article\b[^>]*>)[\s\S]*?(<div class="workshop-queue-actions">)/, (_, start, actions) => start + summaryHtml(details) + actions);
  }
  function visibleAdminEdit(html) {
    return html.replace(/<button type="button" data-workshop-admin-block-rename[^>]*>Rename<\/button>/g, '')
      .replace(/(<span class="workshop-admin-block-controls">)/g, '<button type="button" class="planner-admin-description" data-workshop-admin-block-rename aria-label="Edit Admin description">Edit description</button>$1');
  }
  const api = {jobCard, summaryHtml, compactQueue, visibleAdminEdit, recordedKey};
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  // The planner is lazy-loaded when staff open a station, potentially long
  // after startup retries expire. Script load is the reliable ready signal.
  const plannerLoaded = event => {
    if (event.target?.id === 'workshop-planner-script') install();
  };
  if (typeof document !== 'undefined') document.addEventListener('load', plannerLoaded, true);
  function install() {
    if (window.PDC_PLANNER_SLIM_VERSION) return true;
    if (typeof workshopQueueCardHtml !== 'function' || typeof workshopAdminBlockHtml !== 'function') return false;
    const previousJobCard = vehicleJobcardNumber;
    vehicleJobcardNumber = vehicle => jobCard(vehicle) || previousJobCard(vehicle);
    const previousSnapshot = workshopSnapshotVehicleToPlannerRow;
    workshopSnapshotVehicleToPlannerRow = function(vehicle = {}, ...args) {
      const mapped = previousSnapshot(vehicle, ...args);
      return {...mapped, keyNumber: recordedKey(vehicle) || recordedKey(mapped), jobCardNumber: jobCard(vehicle) || mapped.jobCardNumber || ''};
    };
    const previousQueue = workshopQueueCardHtml;
    workshopQueueCardHtml = function(vehicle = {}, stage = workshopState().stage, ...args) {
      const parts = workshopPartsSummary(vehicle);
      return compactQueue(previousQueue(vehicle, stage, ...args), {
        key: vehicleKeyNumber(vehicle) || recordedKey(vehicle, typeof app !== 'undefined' && Array.isArray(app.emailVehicleLocationRows) ? app.emailVehicleLocationRows : []) || recordedKey(vehicle, typeof app !== 'undefined' && Array.isArray(app.data) ? app.data : []), jc: jobCard(vehicle, workshopStageJobLines(vehicle, stage)),
        customer: vehicleCustomerName(vehicle) || vehicle.customerName || vehicle.customer_name,
        model: workshopQueueVehicleDescription(vehicle), duration: workshopQueueEstimatedLabel(vehicle, stage),
        parts: parts.text, partsStatus: parts.status,
      });
    };
    const previousAdmin = workshopAdminBlockHtml;
    workshopAdminBlockHtml = (...args) => visibleAdminEdit(previousAdmin(...args));
    window.PDC_PLANNER_SLIM_VERSION = '2026.09.10.01';
    if (typeof document !== 'undefined') document.removeEventListener('load', plannerLoaded, true);
    if (typeof renderWorkshopPlanner === 'function' && window.__activeWorkshopPlannerStage) renderWorkshopPlanner();
    return true;
  }
  if (install()) return;
  let attempts = 0;
  const retry = () => { if (!install() && ++attempts < 80) setTimeout(retry, 250); };
  retry();
})();
