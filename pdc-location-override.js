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
 dialog.innerHTML=`<form><h2>Override vehicle location</h2><p data-override-vehicle></p><label>Location<select name="location">${locations.map(([value,label])=>`<option value="${value}">${label}</option>`).join('')}</select></label><label>Reason<textarea name="reason" rows="2" maxlength="500" required></textarea></label><p class="subtle">The board will show this location with a “Location overridden” warning until you clear it.</p><p data-override-normal></p><p role="alert" data-override-error></p><footer><button type="button" data-override-cancel>Cancel</button><button type="button" data-override-clear>Clear override</button><button class="primary" type="submit">Save override</button></footer></form>`;
 document.body.appendChild(dialog);let selected=null,saving=false;
 function open(v){selected={...v};const form=dialog.querySelector('form');form.elements.location.value=v.pdcLocationOverride||v.pdcLocation||'Other';form.elements.reason.value=v.pdcLocationOverrideReason||'';dialog.querySelector('[data-override-vehicle]').textContent=displayStockNumber(v)+' · '+vehicleCustomerName(v);dialog.querySelector('[data-override-normal]').textContent='Normal location: '+pdcLocationLabel(v.pdcAutomaticLocation||v.pdcLocation);dialog.querySelector('[data-override-error]').textContent='';dialog.querySelector('[data-override-clear]').hidden=!v.pdcLocationOverride;dialog.showModal();}
 async function save(clear=false){
  if(saving||!selected||!writable())return;
  const form=dialog.querySelector('form'),error=dialog.querySelector('[data-override-error]');
  if(!clear&&!form.reportValidity())return;
  saving=true;dialog.querySelectorAll('button').forEach(b=>b.disabled=true);error.textContent='';
  try{
   const config=window.PDC_SUPABASE_CONFIG,token=getPdcSupabaseAccessToken();if(!token)throw Error('Please sign in again.');
   const response=await fetch(config.url.replace(/\/$/,'')+'/rest/v1/rpc/set_pdc_vehicle_location_override',{method:'POST',headers:{apikey:config.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({p_vehicle_id:selected.__emailVehicleId,p_expected_version:selected.__emailVehicleVersion,p_location:clear?null:form.elements.location.value,p_reason:clear?'':form.elements.reason.value.trim()})});
   const result=await response.json();if(!response.ok||!result.ok)throw Error(result.code==='version_conflict'?'This vehicle changed. Close this form, refresh the vehicle and try again.':result.code||'The location could not be saved.');
   await refreshEmailVehicleLocations();renderAll();renderDetail();dialog.close();
  }catch(e){error.textContent=e.message;}finally{saving=false;dialog.querySelectorAll('button').forEach(b=>b.disabled=false);}
 }
 dialog.querySelector('form').addEventListener('submit',e=>{e.preventDefault();void save();});
 dialog.querySelector('[data-override-clear]').addEventListener('click',()=>void save(true));
 dialog.querySelector('[data-override-cancel]').addEventListener('click',()=>dialog.close());
 dialog.addEventListener('cancel',e=>{if(saving)e.preventDefault();});
 if(app.activeVehicleDetail)renderDetail();
})();
