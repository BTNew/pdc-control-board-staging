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
  function compactQueue(html, details) {
    // Preserve the original article's drag identity, disabled state and scheduling
    // controls verbatim. Only replace its descriptive content.
    return html.replace(/^(<article\b[^>]*>)[\s\S]*?(<div class="workshop-queue-actions">)/, (_, start, actions) => start + summaryHtml(details) + actions);
  }
  function visibleAdminEdit(html) {
    return html.replace(/<button type="button" data-workshop-admin-block-rename[^>]*>Rename<\/button>/g, '')
      .replace(/(<span class="workshop-admin-block-controls">)/g, '<button type="button" class="planner-admin-description" data-workshop-admin-block-rename aria-label="Edit Admin description">Edit description</button>$1');
  }
  const api = {jobCard, summaryHtml, compactQueue, visibleAdminEdit};
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  function install() {
    if (window.PDC_PLANNER_SLIM_VERSION) return true;
    if (typeof workshopQueueCardHtml !== 'function' || typeof workshopAdminBlockHtml !== 'function') return false;
    const previousJobCard = vehicleJobcardNumber;
    vehicleJobcardNumber = vehicle => jobCard(vehicle) || previousJobCard(vehicle);
    const previousSnapshot = workshopSnapshotVehicleToPlannerRow;
    workshopSnapshotVehicleToPlannerRow = function(vehicle = {}, ...args) {
      return {...previousSnapshot(vehicle, ...args), keyNumber: vehicle.key_number || vehicle.keyNumber || '', jobCardNumber: jobCard(vehicle)};
    };
    const previousQueue = workshopQueueCardHtml;
    workshopQueueCardHtml = function(vehicle = {}, stage = workshopState().stage, ...args) {
      const parts = workshopPartsSummary(vehicle);
      return compactQueue(previousQueue(vehicle, stage, ...args), {
        key: vehicleKeyNumber(vehicle), jc: jobCard(vehicle, workshopStageJobLines(vehicle, stage)),
        customer: vehicleCustomerName(vehicle) || vehicle.customerName || vehicle.customer_name,
        model: workshopQueueVehicleDescription(vehicle), duration: workshopQueueEstimatedLabel(vehicle, stage),
        parts: parts.text, partsStatus: parts.status,
      });
    };
    const previousAdmin = workshopAdminBlockHtml;
    workshopAdminBlockHtml = (...args) => visibleAdminEdit(previousAdmin(...args));
    window.PDC_PLANNER_SLIM_VERSION = '2026.09.10.01';
    if (typeof renderWorkshopPlanner === 'function' && window.__activeWorkshopPlannerStage) renderWorkshopPlanner();
    return true;
  }
  if (install()) return;
  let attempts = 0;
  const retry = () => { if (!install() && ++attempts < 80) setTimeout(retry, 250); };
  retry();
})();
