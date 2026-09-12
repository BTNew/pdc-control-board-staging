/* Authorised email evidence takes priority over imported parts flags. */
(() => {
  'use strict';
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || window.PDC_PARTS_CONFIRMATION_VERSION) return;
  const confirmation = vehicle => {
    const status = importedPartsStatus(vehicle);
    return status?.parts_complete === true && status.override_source === 'authorised_email_confirmation' ? status : null;
  };
  const priorComplete = partsStateComplete;
  partsStateComplete = vehicle => {
    if (confirmation(vehicle)) return true;
    const p = importedPartsStatus(vehicle);
    return p?.feed === 'separate_parts_status' ? p.parts_complete === true : priorComplete(vehicle);
  };
  const priorClass = partsDepartmentStatusClass;
  partsDepartmentStatusClass = status => {
    if (status === 'import:Parts complete — confirmed by Wayne' || status === 'import:All active jobs parts-ready') return 'parts-status-complete';
    if (status === 'import:Parts outstanding — see job cards') return 'parts-status-ordered';
    return priorClass(status);
  };
  const time = value => new Date(value).toLocaleString('en-AU', {timeZone:'Australia/Perth'});
  const priorUpdated = partsLastUpdateLabel;
  partsLastUpdateLabel = vehicle => confirmation(vehicle)?.confirmed_at ? 'Confirmed by Wayne ' + time(confirmation(vehicle).confirmed_at) : priorUpdated(vehicle);
  const priorTitle = importedPartsTitle;
  importedPartsTitle = vehicle => {
    const status = confirmation(vehicle);
    if (!status) {
      const p = importedPartsStatus(vehicle);
      if (p?.feed !== 'separate_parts_status') return priorTitle(vehicle);
      const jobs = (p.jobs || []).map(j => `R/O ${j.job_number} (${j.company || 'scope unconfirmed'}/${j.division || '?' }): ${j.label}`).join('\n');
      return `${p.label}\n${jobs}\nParts snapshot: ${p.parts_snapshot_at ? time(p.parts_snapshot_at) : 'Not recorded'}\nLast successful parts import: ${p.last_successful_parts_feed_import_at ? time(p.last_successful_parts_feed_import_at) : 'Not recorded'} (Perth).\n${p.meaning || ''}`;
    }
    return status.label + '. Confirmed ' + time(status.confirmed_at) + ' (Perth). This email confirmation overrides import backorder flags. Original import evidence is retained.';
  };
  if (typeof partsMatchesOperationalFilter === 'function') {
    const priorFilter = partsMatchesOperationalFilter;
    partsMatchesOperationalFilter = (vehicle = {}, filter = 'notordered') => {
      const p = importedPartsStatus(vehicle);
      if (p?.feed !== 'separate_parts_status') return priorFilter(vehicle, filter);
      if (filter === 'stoppage') return typeof isActivePartsStoppage === 'function' && isActivePartsStoppage(vehicle);
      if (partsStateComplete(vehicle)) return false;
      if (filter === 'ordered') return p.colour === 'orange';
      if (filter === 'overdue') {
        const days = partsWorstEtaDaysUntil(vehicle);
        return Number.isFinite(days) && days < 0;
      }
      return p.colour === 'grey' || p.colour === 'review';
    };
  }
  if (typeof renderPartsSummary === 'function') {
    const priorSummary = renderPartsSummary;
    renderPartsSummary = sourceRows => {
      const rows = sourceRows || partsDepartmentSourceRows();
      const result = priorSummary(rows);
      if (rows.some(v => importedPartsStatus(v)?.feed === 'separate_parts_status')) {
        const host = $('#parts-summary-grid');
        const review = host?.querySelector('[data-parts-operational-filter="notordered"] span');
        const outstanding = host?.querySelector('[data-parts-operational-filter="ordered"] span');
        if (review) review.textContent = 'Parts Need Review';
        if (outstanding) outstanding.textContent = 'Parts Outstanding';
      }
      return result;
    };
  }
  if (typeof partsQueueRowHtml === 'function') {
    const priorRow = partsQueueRowHtml;
    partsQueueRowHtml = vehicle => {
      const html = priorRow(vehicle);
      const p = importedPartsStatus(vehicle);
      if (p?.feed !== 'separate_parts_status') return html;
      const details = (p.jobs || []).map(j => `R/O ${j.job_number}: ${j.label}`).map(escapeHtml).join('<br>');
      const updated = partsLastUpdateLabel(vehicle);
      return html.replace(/<span class="parts-status-pill ([^"]*)">([^<]*)<\/span>/,
        (_, classes, label) => `<span class="parts-status-pill ${classes}" title="${escapeHtml(importedPartsTitle(vehicle))}">${label}</span><div class="subtle">${details}${updated ? '<br>' + escapeHtml(updated) : ''}</div>`);
    };
  }
  window.PDC_PARTS_CONFIRMATION_VERSION = '2026.09.12.separate-parts.2';
})();
