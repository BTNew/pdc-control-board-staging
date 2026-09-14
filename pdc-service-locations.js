/* Tune Tag # = parts location; Block Number = physical vehicle key. */
(() => {
  'use strict';
  const values = (vehicle, field) => [...new Set((vehicle?.tuneServiceLocations?.jobs || [])
    .map(j => String(j[field] ?? '').trim()).filter(Boolean))];
  const text = (vehicle, field) => values(vehicle, field).join(' / ') || 'Not supplied';
  const onSite = vehicle => typeof vehiclePdcLocation === 'function' && vehiclePdcLocation(vehicle) === 'PMB';
  const summary = vehicle => `<div class="tune-service-locations"><span><b>Parts location</b> ${escapeHtml(text(vehicle,'parts_location'))}</span><span><b>Vehicle key</b> ${escapeHtml(text(vehicle,'vehicle_key_number'))}</span></div>`;
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
      return html.replace(/(<span class="incoming-card-main">[\s\S]*?<\/strong>)/,(_,start)=>start+summary(vehicle))
        .replace('<div class="incoming-vehicle-detail-grid">','<div class="incoming-vehicle-detail-grid">'+detail(vehicle));
    };
  }
  const style=document.createElement('style');
  style.textContent='.tune-service-locations{display:flex;flex-direction:column;gap:3px;margin-top:6px;font-size:12px;line-height:1.4;white-space:normal}.tune-service-locations b{color:#334155}.tune-service-location-job{display:flex;flex-direction:column;gap:4px}.tune-service-location-job small{color:#64748b}.incoming-card-main:has(.tune-service-locations){overflow:visible}';
  document.head.appendChild(style);
  window.PDC_SERVICE_LOCATIONS='2026.09.14.01';
  if(typeof refreshAllViews==='function') refreshAllViews();
})();

