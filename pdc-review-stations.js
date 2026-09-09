/* Resolve Review operation mappings through the existing authenticated station
 * move action. This is classification only, never a physical-completion action. */
(() => {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const STATIONS = Object.freeze([
    ['FITTING', 'Fitting'], ['ELECTRICAL', 'Electrical'], ['FABRICATION', 'Fabrication'],
    ['HOIST', 'Hoist'], ['TINT', 'Tint'], ['TYRE', 'Tyre'], ['BUS_4X4', 'Bus 4x4'], ['SUBLET', 'Sublet'],
  ]);
  const stationValid = value => STATIONS.some(([code]) => code === value);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const uuid = value => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ''));
  function reviewLines(vehicle = {}) {
    if (vehicle.__emailVehicleServerAuthoritative !== true || vehicle.pdcQcComplete === true
        || vehicle.pdcQcOperationLinesProjectionPresent !== true
        || ['RFT', 'COLLECTED', 'COMPLETED'].includes(String(vehicle.pdcLocation || '').toUpperCase())) return [];
    return (vehicle.pdcQcOperationLines || []).filter(line => line.active === true && !line.completed
      && line.stageCode === 'UNALLOCATED_MAPPING_REVIEW' && line.sourceKind === 'authenticated'
      && line.lineIdentity === `source:${line.sourceLineId}` && uuid(line.sourceLineId));
  }
  function controlHtml(vehicle, line, { value = '', busy = false, writable = true, message = '', scope = 'qc' } = {}) {
    const suffix = `${scope}-${vehicle.__emailVehicleId}-${line.sourceLineId}`;
    const hours = line.estimatedHours == null ? 'Hours still need review' : `${Number(line.estimatedHours)} h · hours unchanged`;
    return `<div class="review-station-control" data-review-control data-review-vehicle="${esc(vehicle.__emailVehicleId)}" data-review-line="${esc(line.lineIdentity)}">
      <label for="review-station-${esc(suffix)}">Assign this Review item to a station</label>
      ${writable ? `<div class="review-station-fields"><select id="review-station-${esc(suffix)}" data-review-station-select ${busy ? 'disabled' : ''} aria-label="${esc(`Station for ${line.description}`)}"><option value="">Choose station…</option>${STATIONS.map(([code, name]) => `<option value="${code}"${code === value ? ' selected' : ''}>${name}</option>`).join('')}</select><button type="button" data-review-station-save ${busy || !stationValid(value) ? 'disabled' : ''}>${busy ? 'Saving…' : 'Save station'}</button></div>` : '<p>Operator or Administrator access is required to assign a station.</p>'}
      <small>${esc(hours)}. Assignment does not tick off the item.</small><span class="review-station-message" role="status" aria-live="polite">${esc(message)}</span>
    </div>`;
  }
  function movePayload(vehicle, line, stage, detail) {
    if (!uuid(vehicle.__emailVehicleId) || !stationValid(stage)
        || !reviewLines(vehicle).some(item => item.lineIdentity === line.lineIdentity)
        || detail?.vehicle_id !== vehicle.__emailVehicleId || !Array.isArray(detail.line_adjustments)) throw new Error('station_identity_unavailable');
    const matches = detail.line_adjustments.filter(a => a.line_key === line.lineIdentity);
    if (matches.length > 1) throw new Error('station_identity_ambiguous');
    const adjustment = matches[0];
    if (adjustment && (adjustment.active === false || stationValid(adjustment.stage_code))) throw new Error('stale_line_version');
    return { p_vehicle_id: vehicle.__emailVehicleId, p_adjustment_id: adjustment?.adjustment_id || null,
      p_expected_version: adjustment ? Number(adjustment.version) : 0,
      p_line_key: line.lineIdentity, p_stage_code: stage };
  }
  function verifyMove(result, vehicle, line, stage) {
    const d = result?.data, q = d?.qc_line;
    return result?.ok === true && d?.vehicle_id === vehicle.__emailVehicleId && d?.line_key === line.lineIdentity
      && d?.stage_code === stage && Number.isInteger(d?.vehicle_version_after)
      && d.vehicle_version_after > Number(vehicle.__emailVehicleVersion || 0)
      && q?.line_identity === line.lineIdentity && q?.source_line_id === line.sourceLineId
      && q?.stage_code === stage && q?.active === true && q?.completed === false
      && q?.description === line.description && q?.estimated_hours === line.estimatedHours;
  }
  const api = { STATIONS, reviewLines, controlHtml, movePayload, verifyMove };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT
      || typeof renderQualityControlPage !== 'function' || window.PDC_REVIEW_STATIONS_VERSION) return;

  const choices = new Map(), messages = new Map(), saving = new Set();
  const rowId = (v, line) => `${v.__emailVehicleId}:${line.lineIdentity}`;
  const canWrite = () => ['operator', 'administrator'].includes(String(window.PDC_AUTH_CONTEXT?.role || '').toLowerCase());
  const rowFor = id => pdcSheetVehicles().find(v => v.__emailVehicleServerAuthoritative === true && v.__emailVehicleId === id);
  function isBusy(v) {
    const key = qcPageVehicleKey(v);
    return saving.has(v.__emailVehicleId) || qcPagePhotoUploadInFlight.has(key) || qcPageRejectInFlight.has(key)
      || qcPageSignoffInFlight.has(key) || [...qcPageOperationPending.keys()].some(k => k.startsWith(`${key}::`));
  }
  function htmlFor(v, line, scope = 'qc') {
    const id = rowId(v, line);
    return controlHtml(v, line, { value: choices.get(id), message: messages.get(id), busy: isBusy(v), writable: canWrite(), scope });
  }
  function installQcControls() {
    const host = document.querySelector('#qc-page-host');
    if (!host) return;
    for (const checkbox of host.querySelectorAll('[data-qc-operation-check]')) {
      const v = qcPageVehicles().find(row => qcPageVehicleKey(row) === checkbox.dataset.qcOperationCheck);
      if (!v) continue;
      const line = reviewLines(v).find(item => item.lineIdentity === checkbox.dataset.qcLineIdentity);
      if (!line) continue;
      const row = checkbox.closest('.qc-phone-item, .qc-work-item');
      if (!row) continue;
      // Desktop's checkbox row is itself a label: keep the select beside it,
      // never nest a second form control inside the checkbox's label.
      if (row.matches('.qc-phone-item')) {
        if (!row.querySelector('[data-review-control]')) row.insertAdjacentHTML('beforeend', htmlFor(v, line));
      } else if (!row.nextElementSibling?.matches('[data-review-control]')) row.insertAdjacentHTML('afterend', htmlFor(v, line));
    }
  }
  const oldQcRender = renderQualityControlPage;
  renderQualityControlPage = function (...args) { const result = oldQcRender(...args); installQcControls(); return result; };
  const oldWorkPage = renderVehicleWorkshopWorkPage;
  renderVehicleWorkshopWorkPage = function (vehicle = {}) {
    const existing = oldWorkPage(vehicle), lines = reviewLines(vehicle);
    if (!lines.length) return existing;
    const panel = `<section class="review-station-panel"><h3>Review — assign stations</h3><p>Choose the station for each operation. Source hours and QC checks are kept.</p>${lines.map(line => `<article><strong>${esc(line.description)}</strong>${htmlFor(vehicle, line, 'work')}</article>`).join('')}</section>`;
    return panel + existing;
  };
  function rerender() {
    renderQualityControlPage();
    if (document.querySelector('#vehicle-modal')?.hidden === false) renderDetail();
  }
  function messageFor(error) {
    const code = String(error?.message || '');
    if (/stale|conflict|identity/.test(code)) return 'The operation changed in another session. Refresh and review its current station before retrying.';
    if (/unauthorized|403|401/.test(code)) return 'Sign in with an approved Operator or Administrator account.';
    if (/source_description_requires_review/.test(code)) return 'The source description needs review before it can be mapped. No description was truncated.';
    if (/source_stage_completed|completed_operation/.test(code)) return 'Completed operations are protected. This item was not moved.';
    return 'The station change could not be confirmed. Refresh before retrying; no item was ticked off.';
  }
  async function save(button) {
    const box = button.closest('[data-review-control]');
    const v = rowFor(box?.dataset.reviewVehicle);
    const line = reviewLines(v).find(l => l.lineIdentity === box?.dataset.reviewLine);
    if (!v || !line || !canWrite() || isBusy(v)) return;
    const id = rowId(v, line), stage = choices.get(id), actor = window.PDC_AUTH_CONTEXT?.userId;
    if (!stationValid(stage)) return;
    const key = qcPageVehicleKey(v), pendingKey = qcPagePendingKey(key, line.lineIdentity);
    saving.add(v.__emailVehicleId);
    qcPageOperationPending.set(pendingKey, { mapping: true });
    messages.set(id, 'Saving the station…'); rerender();
    let accepted = false;
    try {
      await qcPageOperationMutationChain;
      const detail = await loadVehicleWorkshopDetail(v, { force: true });
      const payload = movePayload(v, line, stage, detail);
      const config = window.PDC_SUPABASE_CONFIG || {};
      const token = getPdcSupabaseAccessToken();
      if (!token || actor !== window.PDC_AUTH_CONTEXT?.userId
          || new URL(config.url).hostname !== `${PROJECT}.supabase.co`) throw new Error('unauthorized');
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 30000);
      let result, response;
      try {
        response = await fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/move_vehicle_workshop_source_line_stage`, {
          method: 'POST', signal: controller.signal,
          headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });
        result = await response.json();
      } finally { clearTimeout(timer); }
      if (!response.ok || !result?.ok) throw new Error(result?.message || result?.code || String(response.status));
      if (actor !== window.PDC_AUTH_CONTEXT?.userId || !verifyMove(result, v, line, stage)) throw new Error('station_readback_mismatch');
      accepted = true;
      const note = `${line.description} moved to ${STATIONS.find(([code]) => code === stage)[1]}. ${line.estimatedHours == null ? 'The hours still need review before QC.' : 'Inspect the item, then tick it off in QC.'}`;
      messages.set(id, note); choices.delete(id);
      qcPageFeedback.set(key, { kind: 'saved', message: note });
      qcPageNotice = note;
      app.vehicleWorkshopDetailCache.delete(v.__emailVehicleId);
      if (!await refreshEmailVehicleLocations()) qcPageNotice = `${note} Tap Refresh to reload the saved station.`;
      if (document.querySelector('#vehicle-modal')?.hidden === false) await loadVehicleWorkshopDetail(rowFor(v.__emailVehicleId) || v, { force: true });
    } catch (error) {
      const note = accepted ? 'Station saved. Refresh to load its new position.' : messageFor(error);
      messages.set(id, note); qcPageFeedback.set(key, { kind: accepted ? 'saved' : 'error', message: note });
    } finally {
      saving.delete(v.__emailVehicleId); qcPageOperationPending.delete(pendingKey); rerender();
    }
  }
  document.addEventListener('change', event => {
    const select = event.target.closest?.('[data-review-station-select]');
    if (!select) return;
    const box = select.closest('[data-review-control]'), v = rowFor(box.dataset.reviewVehicle);
    const line = reviewLines(v).find(l => l.lineIdentity === box.dataset.reviewLine);
    if (!v || !line || !canWrite() || isBusy(v)) return;
    choices.set(rowId(v, line), select.value);
    const button = box.querySelector('[data-review-station-save]');
    if (button) button.disabled = !stationValid(select.value);
  });
  document.addEventListener('click', event => {
    const button = event.target.closest?.('[data-review-station-save]');
    if (!button) return;
    event.preventDefault(); event.stopPropagation(); void save(button);
  });
  window.addEventListener('pdc-auth-locked', () => { choices.clear(); messages.clear(); });
  window.PDC_REVIEW_STATIONS_VERSION = '2026.09.09.10';
  window.PDC_REVIEW_STATIONS = api;
  rerender();
})();
