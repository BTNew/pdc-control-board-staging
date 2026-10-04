/* Tune Tag # = parts location; Block Number = physical vehicle key. */
(() => {
  'use strict';
  const values = (vehicle, field) => [...new Set((vehicle?.tuneServiceLocations?.jobs || [])
    .map(j => String(j[field] ?? '').trim()).filter(Boolean))];
  const text = (vehicle, field) => values(vehicle, field).join(' / ') || 'Not supplied';
  const onSite = vehicle => typeof vehiclePdcLocation === 'function' && vehiclePdcLocation(vehicle) === 'PMB';
  const partsLocation = vehicle => {
    const location = values(vehicle, 'parts_location').join(' / ');
    return location ? `<span class="tune-parts-location" title="${escapeHtml('Parts location: ' + location)}" aria-label="${escapeHtml('Parts location: ' + location)}">${escapeHtml(location)}</span>` : '';
  };
  const detail = vehicle => (vehicle?.tuneServiceLocations?.jobs || []).map(j => {
    const date = j.snapshot_at ? new Date(j.snapshot_at).toLocaleString('en-AU',{timeZone:'Australia/Perth'}) : 'Unknown';
    return `<div class="tune-service-location-job"><b>${escapeHtml(j.ro_number)}</b><span>Parts location: ${escapeHtml(j.parts_location || 'Not supplied')} · Vehicle key: ${escapeHtml(j.vehicle_key_number || 'Not supplied')}</span><small>Tune report: ${escapeHtml(date)} (Perth)</small></div>`;
  }).join('');
  if (typeof module !== 'undefined') module.exports={values,text};
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef!=='cdsmnqxtyyoeoznmbidd' || window.PDC_SERVICE_LOCATIONS) return;
  if (typeof vehicleIdentityCells === 'function') {
    const prior=vehicleIdentityCells;
    vehicleIdentityCells=vehicle=>prior(vehicle).map(cell=>onSite(vehicle)&&cell.label==='Key'&&values(vehicle,'vehicle_key_number').length
      ? {...cell,value:values(vehicle,'vehicle_key_number').length===1 ? values(vehicle,'vehicle_key_number')[0] : 'Check job cards'} : cell);
  }
  if (typeof incomingVehicleDetailRow === 'function') {
    const prior=incomingVehicleDetailRow;
    incomingVehicleDetailRow=(vehicle,...args)=>{
      const html=prior(vehicle,...args);
      if (!onSite(vehicle)) return html;
      return html.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)(<\/span>)/,(_,start,end)=>start+partsLocation(vehicle)+end)
        .replace('<div class="incoming-vehicle-detail-grid">','<div class="incoming-vehicle-detail-grid">'+detail(vehicle));
    };
  }
  const style=document.createElement('style');
  style.textContent='.incoming-card-main:has(.tune-parts-location){display:grid!important;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:6px!important}.tune-parts-location{max-width:72px;font-size:11px;font-weight:650;line-height:1.2;text-align:right;overflow-wrap:anywhere;color:#334155}.tune-service-location-job{display:flex;flex-direction:column;gap:4px}.tune-service-location-job small{color:#64748b}';
  document.head.appendChild(style);
  window.PDC_SERVICE_LOCATIONS='2026.09.14.03';
  if(typeof refreshAllViews==='function') refreshAllViews();
})();
