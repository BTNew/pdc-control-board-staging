/* Shared board-location override; lifecycle and completion evidence stay separate. */
(() => {
 'use strict';
 if(typeof window==='undefined'||window.PDC_SUPABASE_CONFIG?.projectRef!=='cdsmnqxtyyoeoznmbidd'||window.PDC_LOCATION_OVERRIDE)return;
 window.PDC_LOCATION_OVERRIDE=true;
 const locations=[['PMB','PMB'],['YH','Yard Hold'],['IT','In Transit'],['PIT','PIT'],['QC','QC'],['RFT','RFT'],['Other','Other']];
 const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const writable=()=>['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
 const previousLocation=vehiclePdcLocation,previousCategory=statusCategory,previousLabel=pdcLocationLabel;
 vehiclePdcLocation=function(vehicle){return vehicle?.pdcLocationOverride||previousLocation(vehicle);};
 pdcLocationLabel=function(value){return value==='IT'?'In Transit':value==='Other'?'Other':previousLabel(value);};
 statusCategory=function(vehicle){return ({PMB:'pmb',YH:'yardhold',IT:'prodtransit',PIT:'pit',QC:'qc',RFT:'rft',Other:'other'})[vehicle?.pdcLocationOverride]||previousCategory(vehicle);};
 const previousStatus=formatStatus;
 formatStatus=function(vehicle){return previousStatus(vehicle)+(vehicle?.pdcLocationOverride?`<span class="badge location-override-warning" title="${esc(vehicle.pdcLocationOverrideReason)}">Location overridden</span>`:'');};
 const previousDetail=renderDetail;
 renderDetail=function(...args){
  const result=previousDetail(...args),v=app.activeVehicleDetail;
  const host=document.querySelector('#vehicle-detail .vehicle-detail-header');
  if(!host||!v?.__emailVehicleId||!writable())return result;
  const button=document.createElement('button');button.type='button';button.className='small-button';button.textContent=v.pdcLocationOverride?'Edit location override':'Override location';
  button.addEventListener('click',()=>open(v));host.querySelector('.vehicle-detail-header-tools')?.appendChild(button);return result;
 };
 const dialog=document.createElement('dialog');dialog.className='location-override-dialog';
 dialog.setAttribute('aria-labelledby','location-override-title');
 dialog.innerHTML=`<form><h2 id="location-override-title">Override vehicle location</h2><p data-override-vehicle></p><label>Location<select name="location">${locations.map(([value,label])=>`<option value="${value}">${label}</option>`).join('')}</select></label><label>Reason<textarea name="reason" rows="2" maxlength="500" required></textarea></label><p class="subtle">The board will show this location with a “Location overridden” warning until you clear it.</p><p data-override-normal></p><p role="alert" data-override-error></p><footer><button type="button" data-override-cancel>Cancel</button><button type="button" data-override-refresh hidden>Retry refresh</button><button type="button" data-override-clear>Clear override</button><button class="primary" type="submit">Save override</button></footer></form>`;
 document.body.appendChild(dialog);
 let selected=null,selectedActor=null,saving=false,generation=0,activeRequest=null,savedReceipt=null;
 const form=dialog.querySelector('form'),error=dialog.querySelector('[data-override-error]');
 function current(request){return activeRequest===request&&request.generation===generation&&dialog.open&&request.actor===window.PDC_AUTH_CONTEXT?.userId&&writable();}
 function controls(){
  dialog.querySelectorAll('button').forEach(button=>{button.disabled=saving;});
  form.elements.location.disabled=saving||Boolean(savedReceipt);
  form.elements.reason.disabled=saving||Boolean(savedReceipt);
  dialog.querySelector('[type="submit"]').disabled=saving||Boolean(savedReceipt);
  dialog.querySelector('[data-override-clear]').disabled=saving||Boolean(savedReceipt);
  dialog.querySelector('[data-override-refresh]').hidden=!savedReceipt;
  dialog.querySelector('[data-override-cancel]').textContent=savedReceipt?'Close':'Cancel';
 }
 function reset(){
  generation+=1;activeRequest?.controller.abort();activeRequest=null;selected=null;selectedActor=null;saving=false;savedReceipt=null;
  form.reset();error.textContent='';dialog.querySelector('[data-override-vehicle]').textContent='';dialog.querySelector('[data-override-normal]').textContent='';controls();
 }
 function dismiss(){if(dialog.open)dialog.close();reset();}
 function open(v){
  if(!writable()||saving||dialog.open)return;
  reset();selected={...v};selectedActor=window.PDC_AUTH_CONTEXT?.userId;form.elements.location.value=v.pdcLocationOverride||v.pdcLocation||'Other';form.elements.reason.value=v.pdcLocationOverrideReason||'';
  dialog.querySelector('[data-override-vehicle]').textContent=displayStockNumber(v)+' · '+vehicleCustomerName(v);
  dialog.querySelector('[data-override-normal]').textContent='Normal location: '+pdcLocationLabel(v.pdcAutomaticLocation||v.pdcLocation);
  dialog.querySelector('[data-override-clear]').hidden=!v.pdcLocationOverride;dialog.showModal();
 }
 function begin(){
  const request={generation,actor:window.PDC_AUTH_CONTEXT?.userId,controller:new AbortController()};
  activeRequest=request;saving=true;controls();error.textContent='';return request;
 }
 async function readback(request){
  let timeout;
  const refreshed=await Promise.race([refreshEmailVehicleLocations(),new Promise(resolve=>{timeout=setTimeout(()=>resolve(false),20000);})]).finally(()=>clearTimeout(timeout));
  if(!current(request))return false;
  const row=(app.emailVehicleLocationRows||[]).find(item=>String(item.id||'')===savedReceipt.vehicleId);
  const matches=refreshed===true&&row&&Number(row.version)>=savedReceipt.version
   &&String(row.location_override||'')===savedReceipt.location&&String(row.location_override_reason||'').trim()===savedReceipt.reason;
  if(!matches){error.textContent='The location override was saved, but its current status could not be confirmed. Retry refresh before making another change.';return false;}
  renderAll();renderDetail();dismiss();return true;
 }
 async function save(clear=false){
  if(saving||savedReceipt||!selected||selectedActor!==window.PDC_AUTH_CONTEXT?.userId||!writable()||!dialog.open)return;
  if(!clear&&!form.reportValidity())return;
  const vehicleId=selected.__emailVehicleId,version=Number(selected.__emailVehicleVersion);
  const location=clear?'':form.elements.location.value,reason=clear?'':form.elements.reason.value.trim();
  if(!reason&&!clear){error.textContent='Enter a reason for the override.';return;}
  const request=begin();let timeout;
  try{
   const config=window.PDC_SUPABASE_CONFIG,token=getPdcSupabaseAccessToken();if(!token)throw Error('Please sign in again.');
   timeout=setTimeout(()=>request.controller.abort(),20000);
   const response=await fetch(config.url.replace(/\/$/,'')+'/rest/v1/rpc/set_pdc_vehicle_location_override',{method:'POST',signal:request.controller.signal,headers:{apikey:config.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({p_vehicle_id:vehicleId,p_expected_version:version,p_location:location||null,p_reason:reason})});
   const result=await response.json();if(!current(request))return;
   if(!response.ok||result?.ok!==true)throw Error(result?.code==='version_conflict'?'This vehicle changed. Close this form, refresh the vehicle and try again.':result?.code||'The location could not be saved.');
   if(result.code!=='location_override_saved'||Number(result.vehicle_version)!==version+1)throw Error('The save response could not be verified. Close this form and refresh the vehicle before retrying.');
   savedReceipt={vehicleId,version:Number(result.vehicle_version),location,reason};
   await readback(request);
  }catch(e){if(current(request))error.textContent=savedReceipt?'The location override was saved, but refresh failed. Retry refresh before making another change.':e.name==='AbortError'?'The save response could not be confirmed. Close this form and refresh the vehicle before retrying.':e.message;}
  finally{clearTimeout(timeout);if(current(request)){activeRequest=null;saving=false;controls();}}
 }
 async function retryRefresh(){
  if(saving||!savedReceipt||!selected||selectedActor!==window.PDC_AUTH_CONTEXT?.userId||!writable()||!dialog.open)return;
  const request=begin();
  try{await readback(request);}catch(e){if(current(request))error.textContent='The location override was saved, but refresh failed. Retry refresh before making another change.';}
  finally{if(current(request)){activeRequest=null;saving=false;controls();}}
 }
 dialog.querySelector('form').addEventListener('submit',e=>{e.preventDefault();void save();});
 dialog.querySelector('[data-override-clear]').addEventListener('click',()=>void save(true));
 dialog.querySelector('[data-override-cancel]').addEventListener('click',dismiss);
 dialog.querySelector('[data-override-refresh]').addEventListener('click',()=>void retryRefresh());
 dialog.addEventListener('cancel',e=>{if(saving)e.preventDefault();});
 dialog.addEventListener('close',()=>{if(!dialog.open)reset();});
 window.addEventListener('pdc-auth-locked',dismiss);
 window.addEventListener('pdc-auth-ready',()=>{if(dialog.open&&(!writable()||selectedActor!==window.PDC_AUTH_CONTEXT?.userId))dismiss();});
 if(app.activeVehicleDetail)renderDetail();
})();
