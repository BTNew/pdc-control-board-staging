/* QC repair estimates and return-to-inspection. The existing Supabase actions
 * remain the sole write authority. Source hours and completed booking history
 * are never edited by this presentation module. */
(() => {
  'use strict';
  const stageKey = value => String(value || '').trim().toUpperCase();
  function scopeOf(v = {}) {
    const s = v.pdcQcRework || v.qc_rework;
    if (!s || typeof s !== 'object') return null;
    const id = String(v.__emailVehicleId || v.sharedVehicleId || v.id || '');
    const version = Number(v.__emailVehicleVersion ?? v.version);
    const trusted = v.__emailVehicleServerAuthoritative === true || v.__workshopStationSnapshotAuthoritative === true;
    if (!trusted || String(s.vehicle_id || '') !== id) return null;
    if (s.active === true && (s.contract !== 'pdc-qc-rework-v1' || Number(s.vehicle_version) !== version
        || !Array.isArray(s.lines) || !Array.isArray(s.stages))) return { active: true, invalid: true, lines: [], stages: [] };
    return s;
  }
  function repairLines(v, stage) {
    const s = scopeOf(v);
    if (!s?.active) return null;
    return s.lines.filter(line => line.active === true && stageKey(line.stage_code) === stageKey(stage))
      .map(line => ({ id: line.line_identity, lineIdentity: line.line_identity,
        text: line.description, operationNo: line.operation_no, jobCardNumber: line.job_card_number,
        stage: stageKey(line.stage_code), hours: line.estimated_hours === null ? null : Number(line.estimated_hours),
        source: 'authenticated-operation-line', confirmed: true, qcRework: true }));
  }
  function repairHours(v, stage) {
    const s = scopeOf(v);
    if (!s?.active) return undefined;
    const entries = s.stages.filter(item => stageKey(item.stage_code) === stageKey(stage));
    const raw = entries.length === 1 ? entries[0].estimated_hours : null;
    if (raw === null || raw === undefined || raw === '') return null;
    const hours = Number(raw);
    return Number.isFinite(hours) && hours >= 0 ? hours : null;
  }
  function repairDuration(v, stage) {
    const h = repairHours(v, stage);
    if (h === undefined) return undefined;
    if (h === null) return null;
    const minutes = Math.max(1, Math.round(h * 60));
    return { hours: minutes / 60, minutes, sourceEstimatedHours: h };
  }
  function readyForReinspection(v) {
    const s = scopeOf(v);
    return Boolean(s?.active && !s.invalid && s.ready_for_qc === true && s.repairs_complete === true
      && Array.isArray(s.issues) && s.issues.length === 0
      && stageKey(v.pdcLocation || v.current_location) === 'PMB' && v.pdcQcComplete !== true);
  }
  const exported = { scopeOf, repairLines, repairHours, repairDuration, readyForReinspection };
  if (typeof module !== 'undefined' && module.exports) module.exports = exported;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd'
      || typeof mapServerVehicle !== 'function') return;
  if (window.PDC_QC_REWORK_VERSION) return;

  const oldMap = mapServerVehicle;
  mapServerVehicle = function(raw = {}) {
    const result = oldMap(raw);
    result.pdcQcRework = raw.qc_rework || null;
    result.pdcQcInspectionKey = String(raw.qc_rework?.inspection_key || '');
    return result;
  };
  if (window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE) window.PDC_EMAIL_VEHICLE_LOCATION_SERVICE.mapServerVehicle = mapServerVehicle;
  const oldPlannerMap = workshopSnapshotVehicleToPlannerRow;
  workshopSnapshotVehicleToPlannerRow = function(raw, items, stage) {
    return { ...oldPlannerMap(raw, items, stage), pdcQcRework: raw.qc_rework || null };
  };
  const oldLines = workshopStageJobLines;
  workshopStageJobLines = function(v, stage) { return repairLines(v, stage) ?? oldLines(v, stage); };
  const oldHours = workshopCalculatedStageHours;
  workshopCalculatedStageHours = function(v, stage) {
    const h = repairHours(v, stage);
    return h === undefined ? oldHours(v, stage) : h;
  };
  const oldEstimate = workshopEstimatedHours;
  workshopEstimatedHours = function(v, stage) {
    const h = repairHours(v, stage);
    return h === undefined ? oldEstimate(v, stage) : h === null ? '' : h;
  };
  const oldDuration = workshopSchedulingDuration;
  workshopSchedulingDuration = function(v, stage) {
    const duration = repairDuration(v, stage);
    return duration === undefined ? oldDuration(v, stage) : duration;
  };
  const oldRequired = workshopRequiredJobsForStageHtml;
  workshopRequiredJobsForStageHtml = function(v, stage, suppliedLines) {
    const lines = repairLines(v, stage);
    return (lines === null ? '' : '<p class="workshop-rework-note"><strong>QC repair only</strong> — previously checked items are excluded from this booking. The full checklist returns for reinspection.</p>')
      + oldRequired(v, stage, lines ?? suppliedLines);
  };
  const oldOpen = openWorkshopVehicleJob;
  openWorkshopVehicleJob = function(key, stage, plan) {
    const v = workshopVehicle(key, stage);
    const h = repairHours(v || {}, stage || window.__activeWorkshopPlannerStage);
    if (h === null) { window.alert('This QC repair needs a valid estimate and station mapping. Open the vehicle to correct the operation; the original full-job estimate will not be reused.'); return; }
    oldOpen(key, stage, plan);
    // A genuinely zero-hour source stays zero. The booking grid allocates its
    // existing minimum of one minute, labelled separately from source hours.
    if (h === 0) {
      const overlay = document.querySelector('[data-workshop-job-overlay]');
      const input = overlay?.querySelector('[name="estimated_hours"]');
      if (input) input.value = String(1 / 60);
      const total = overlay?.querySelector('[data-workshop-estimated-hours-total]');
      if (total) total.textContent = '0 source hours (1 minute minimum booking)';
    }
  };
  const oldReady = vehicleReadyForQualityControl;
  vehicleReadyForQualityControl = function(v = {}) {
    const s = scopeOf(v);
    if (!s?.active) return oldReady(v);
    return readyForReinspection(v) && !isActivePartsStoppage(v);
  };
  const oldFixFirst = fixFirstRowsHtml;
  fixFirstRowsHtml = function(rows = [], empty) {
    let html = oldFixFirst(rows, empty);
    for (const row of rows) {
      if (row.stoppageKind !== 'pmb' || !readyForReinspection(row.vehicle)) continue;
      const key = escapeHtml(vehicleKey(row.vehicle));
      html = html.replace(/<button\b[^>]*data-clear-priority-stoppage=[\s\S]*?<\/button>/g, button =>
        button.includes(`data-clear-priority-stoppage="${key}"`) && button.includes('data-stoppage-kind="pmb"')
          ? `<button class="primary fix-first-clear" type="button" data-qc-rework-return="${key}">Return to QC</button>` : button);
    }
    return html;
  };
  document.addEventListener('click', event => {
    const button = event.target.closest?.('[data-qc-rework-return]');
    if (!button) return;
    event.preventDefault(); event.stopPropagation();
    void markVehicleReadyForQualityControl(button.dataset.qcReworkReturn);
  });
  // Receipts/photos from a rejected attempt cannot satisfy the new inspection.
  // Do not clear an upload in progress, or any server-side historical evidence.
  function forgetObsoletePhotoCache() {
    for (const v of pdcSheetVehicles()) {
      if (v.__emailVehicleServerAuthoritative !== true || !v.pdcQcInspectionKey) continue;
      const key = qcPageVehicleKey(v);
      const photo = qcPhotoEvidence.get(key);
      if (qcPhotoEvidenceIsValid(photo) && String(photo.qc_inspection_key || '') !== v.pdcQcInspectionKey) qcPhotoEvidence.delete(key);
      const cache = `pdc.qc.photo.receipt.v1:${window.PDC_AUTH_CONTEXT?.userId || ''}:${v.__emailVehicleId}:${v.pdcQcRetestCycleId || 'initial'}`;
      try {
        const saved = JSON.parse(sessionStorage.getItem(cache) || 'null');
        if (saved && String(saved.photo?.qc_inspection_key || '') !== v.pdcQcInspectionKey) sessionStorage.removeItem(cache);
      } catch (_) { /* The server remains authoritative if local cache is unavailable. */ }
    }
  }
  const oldQcRender = renderQualityControlPage;
  renderQualityControlPage = function() { forgetObsoletePhotoCache(); return oldQcRender(); };
  const oldSignoff = qcPageSignoff;
  qcPageSignoff = function(key) { forgetObsoletePhotoCache(); return oldSignoff(key); };
  window.PDC_QC_REWORK_VERSION = '2026.09.09.09';
  window.PDC_QC_REWORK = exported;
  // Refresh already-mapped rows as well as subsequent server notifications.
  void refreshEmailVehicleLocations();
})();
