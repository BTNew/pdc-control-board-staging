/* Authorised email evidence takes priority over imported parts flags. */
(() => {
  'use strict';
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== 'cdsmnqxtyyoeoznmbidd' || window.PDC_PARTS_CONFIRMATION_VERSION) return;
  const confirmation = vehicle => {
    const status = importedPartsStatus(vehicle);
    return status?.parts_complete === true && status.override_source === 'authorised_email_confirmation' ? status : null;
  };
  const priorComplete = partsStateComplete;
  partsStateComplete = vehicle => !!confirmation(vehicle) || priorComplete(vehicle);
  const priorClass = partsDepartmentStatusClass;
  partsDepartmentStatusClass = status => status === 'import:Parts complete — confirmed by Wayne' ? 'parts-status-complete' : priorClass(status);
  const time = value => new Date(value).toLocaleString('en-AU', {timeZone:'Australia/Perth'});
  const priorUpdated = partsLastUpdateLabel;
  partsLastUpdateLabel = vehicle => confirmation(vehicle)?.confirmed_at ? 'Confirmed by Wayne ' + time(confirmation(vehicle).confirmed_at) : priorUpdated(vehicle);
  const priorTitle = importedPartsTitle;
  importedPartsTitle = vehicle => {
    const status = confirmation(vehicle);
    if (!status) return priorTitle(vehicle);
    return status.label + '. Confirmed ' + time(status.confirmed_at) + ' (Perth). This email confirmation overrides import backorder flags. Original import evidence is retained.';
  };
  window.PDC_PARTS_CONFIRMATION_VERSION = '2026.09.12.01';
})();
