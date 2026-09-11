/* Cross-station vehicle availability. Five elapsed hours between jobs. */
(() => {
 'use strict';
 const BUFFER_MS=5*60*60*1000;
 function fits(start,end,windows=[]){
  const from=+new Date(start),to=+new Date(end);
  return Number.isFinite(from)&&Number.isFinite(to)&&to>from&&windows.every(row=>{
   const busyStart=+new Date(row.start_at),busyEnd=+new Date(row.end_at);
   return Number.isFinite(busyStart)&&Number.isFinite(busyEnd)&&(to+BUFFER_MS<=busyStart||from>=busyEnd+BUFFER_MS);
  });
 }
 async function read(vehicleId=null,changedSince=null){
  const config=window.PDC_SUPABASE_CONFIG,token=getPdcSupabaseAccessToken();
  if(!token||config?.projectRef!=='cdsmnqxtyyoeoznmbidd')throw Error('Vehicle booking checks are unavailable. Refresh and try again.');
  const response=await fetch(config.url.replace(/\/$/,'')+'/rest/v1/rpc/get_pdc_vehicle_planning_windows',{method:'POST',signal:AbortSignal.timeout(20000),headers:{apikey:config.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({p_vehicle_id:vehicleId,p_changed_since:changedSince})});
  const result=await response.json();if(!response.ok||!result.ok||!Array.isArray(result.windows)||!Array.isArray(result.warnings))throw Error('Could not check bookings across all stations. Refresh and try again.');return result;
 }
 async function warn(changedSince){
  try{
   const result=await read(null,changedSince);if(!result.warnings?.length)return;
   const label=value=>new Date(value).toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'short',timeStyle:'short'});
   window.alert('Vehicle booking warning — check the next station\n\n'+result.warnings.map(w=>`Stock ${w.stock}: ${w.first_stage} Bay ${w.first_bay} finishes ${label(w.end_at)}; ${w.next_stage} Bay ${w.next_bay} starts ${label(w.next_start)}. ${w.overlap?'Bookings overlap.':'Less than the 5-hour buffer.'}`).join('\n\n')+'\n\nMove the later booking using Best slot or choose a suitable time.');
  }catch(e){window.alert('The booking change was saved, but the cross-station warning check could not finish. Refresh and check the vehicle’s next booking.');}
 }
 const api={fits,read,warn,BUFFER_MS};
 if(typeof module!=='undefined'&&module.exports)module.exports=api;
 if(typeof window!=='undefined')window.PDC_VEHICLE_HANDOVER=api;
})();
