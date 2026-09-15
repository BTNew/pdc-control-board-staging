/* Reviewed, atomic emergency scheduling from the Control Board. */
(function(root){
 'use strict';
 const PROJECT='cdsmnqxtyyoeoznmbidd';
 const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const stockKey=v=>String(v||'').trim().replace(/[^a-z0-9]/gi,'').toUpperCase();
 function createController(options){
  let preview=null,busy=false,generation=0,uncertain=false;
  function capture(){
   const c=options.context();
   if(!c?.actor||!c.token||!['operator','administrator'].includes(c.role)||c.config?.projectRef!==PROJECT
     ||c.config?.url?.replace(/\/$/,'')!=='https://'+PROJECT+'.supabase.co'||c.config?.workshop?.sharedData!==true)
    throw Error('Sign in with workshop operator access to prioritise a vehicle.');
   return {...c,generation};
  }
  function current(c){const x=options.context();return c.generation===generation&&c.actor===x?.actor&&c.token===x.token&&c.config===x.config&&c.role===x.role;}
  async function call(body,owner){
   if(!current(owner))throw Error('Your session changed. Preview the emergency plan again.');
   const abort=new AbortController();let timer;
   try{
    const response=await Promise.race([
     options.fetch(owner.config.url.replace(/\/$/,'')+'/rest/v1/rpc/prioritise_workshop_vehicle',{
      method:'POST',signal:abort.signal,headers:{apikey:owner.config.publishableKey,Authorization:'Bearer '+owner.token,'Content-Type':'application/json'},
      body:JSON.stringify(body)
     }).then(async r=>({ok:r.ok,body:await r.json()})),
     new Promise((_,reject)=>{timer=setTimeout(()=>{abort.abort();reject(Object.assign(Error('The result is not confirmed. Use Check result to safely retry this request.'),{code:'unconfirmed'}));},options.timeoutMs||95000);})
    ]);
    if(!current(owner))throw Object.assign(Error('Your session changed. Refresh the board before trying again.'),{code:'session_changed'});
    if(!response.ok||response.body?.ok!==true)throw Object.assign(Error(response.body?.message||'The emergency plan could not be prepared. Refresh and try again.'),{code:response.body?.error||'rejected'});
    return response.body;
   }catch(e){
    if(e.code)throw e;
    throw Object.assign(Error('The result is not confirmed. Use Check result to safely retry this request.'),{code:'unconfirmed'});
   }finally{clearTimeout(timer);}
  }
  async function makePreview(stock){
   if(busy)throw Error('An emergency request is already running.');
   if(uncertain)throw Error('Check the result of the previous request first.');
   stock=stockKey(stock);if(!stock||stock.length>80)throw Error('Enter a vehicle stock number.');
   const owner=capture();preview=null;busy=true;
   try{
    const result=await call({p_stock_number:stock,p_apply:false},owner);
    if(!result.can_apply||typeof result.plan_hash!=='string'||!Array.isArray(result.bookings)||!Array.isArray(result.changes))
      throw Error('The preview was incomplete. Refresh and try again.');
    preview={owner,stock,result,key:options.uuid()};return result;
   }catch(e){
    if(e.code==='unconfirmed')e.message='Preview could not be confirmed. Try Preview again; no schedule changes were saved.';
    throw e;
   }finally{busy=false;}
  }
  async function apply(){
   if(busy)throw Error('An emergency request is already running.');
   const saved=preview;if(!saved||!current(saved.owner))throw Error('Preview this vehicle first.');
   busy=true;
   try{
    const result=await call({p_stock_number:saved.stock,p_apply:true,p_plan_hash:saved.result.plan_hash,p_idempotency_key:saved.key},saved.owner);
    if(result.applied!==true)throw Object.assign(Error('The booking result could not be confirmed. Use Check result.'),{code:'unconfirmed'});
    uncertain=false;preview=null;return result;
   }catch(e){uncertain=e.code==='unconfirmed';if(!uncertain)preview=null;throw e;}finally{busy=false;}
  }
  return {preview:makePreview,apply,invalidate(){generation++;preview=null;uncertain=false;},
   get busy(){return busy;},get uncertain(){return uncertain;},get canApply(){return !!preview&&!busy&&current(preview.owner);}};
 }
 const time=v=>v?new Date(v).toLocaleString('en-AU',{timeZone:'Australia/Perth',weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}):'Not booked';
 const stage=v=>({'BUS_4X4':'Bus 4\u00d74','FITTING':'Fitting','HOIST':'Hoist','TINT':'Tint','FABRICATION':'Fabrication','ELECTRICAL':'Electrical','TYRE':'Tyre'}[v]||v);
 function summaryHtml(result){
  const rows=Array.isArray(result.bookings)?result.bookings:[];
  const changes=Array.isArray(result.changes)?result.changes:[];
  const followers=changes.filter(x=>!x.priority);
  return '<p><strong>'+esc(result.stock_number)+' \u00b7 '+esc(result.customer||'Vehicle')+'</strong></p>'+
   '<p>'+(result.applied?'Emergency schedule saved. ':'Proposed emergency schedule. ')+followers.length+' other booking'+(followers.length===1?'':'s')+(result.applied?' moved.':' will move.')+'</p>'+
   '<div class="emergency-table-wrap"><table><thead><tr><th>Station / bay</th><th>Start</th><th>Finish</th></tr></thead><tbody>'+
   rows.map(x=>'<tr><th>'+esc(stage(x.stage_code))+' \u00b7 Bay '+esc(x.bay_number)+'</th><td>'+esc(time(x.start_at))+'</td><td>'+esc(time(x.end_at))+'</td></tr>').join('')+'</tbody></table></div>'+
   (followers.length?'<details><summary>View '+followers.length+' affected booking'+(followers.length===1?'':'s')+'</summary><div class="emergency-table-wrap"><table><thead><tr><th>Stock / bay</th><th>Previous start</th><th>New start</th><th>New finish</th></tr></thead><tbody>'+
    followers.map(x=>'<tr><th>'+esc(x.stock_number)+'<small>'+esc(stage(x.stage_code))+' \u00b7 Bay '+esc(x.bay_number)+'</small></th><td>'+esc(time(x.old_start_at))+'</td><td>'+esc(time(x.new_start_at))+'</td><td>'+esc(time(x.new_end_at))+'</td></tr>').join('')+'</tbody></table></div></details>':'');
 }
 if(typeof module!=='undefined'&&module.exports)module.exports={createController,summaryHtml,stockKey};
 if(!root.document)return;
 const host=root.document.getElementById('workshop-emergency');if(!host)return;
 const input=host.querySelector('input'),previewButton=host.querySelector('[data-emergency-preview]'),applyButton=host.querySelector('[data-emergency-apply]'),
  cancel=host.querySelector('[data-emergency-cancel]'),status=host.querySelector('[data-emergency-result]');
 let uiOwner=0;
 const controller=createController({
  context:()=>({actor:root.PDC_AUTH_CONTEXT?.userId,role:root.PDC_AUTH_CONTEXT?.role,
   token:typeof getPdcSupabaseAccessToken==='function'?getPdcSupabaseAccessToken():'',config:root.PDC_SUPABASE_CONFIG}),
  fetch:(...args)=>root.fetch(...args),uuid:()=>root.crypto.randomUUID()
 });
 function controls(){
  const allowed=['operator','administrator'].includes(root.PDC_AUTH_CONTEXT?.role);
  input.disabled=controller.busy||controller.uncertain;
  previewButton.disabled=!allowed||controller.busy||controller.uncertain;
  applyButton.hidden=!controller.canApply&&!controller.busy;applyButton.disabled=!controller.canApply;
  applyButton.textContent=controller.uncertain?'Check result':'Prioritise vehicle & move bookings';
  cancel.hidden=!controller.canApply;cancel.disabled=controller.busy||controller.uncertain;
  host.setAttribute('aria-busy',String(controller.busy));
 }
 previewButton.addEventListener('click',async()=>{
  const owner=++uiOwner;status.textContent='Checking the earliest bays and affected bookings\u2026';
  const pending=controller.preview(input.value);controls();
  try{const result=await pending;if(owner===uiOwner)status.innerHTML=summaryHtml(result);}
  catch(e){if(owner===uiOwner)status.textContent=e.message;}
  finally{if(owner===uiOwner)controls();}
 });
 input.addEventListener('keydown',e=>{if(e.key==='Enter'&&!previewButton.disabled){e.preventDefault();previewButton.click();}});
 input.addEventListener('input',()=>{if(!controller.busy&&!controller.uncertain){controller.invalidate();uiOwner++;status.textContent='';controls();}});
 cancel.addEventListener('click',()=>{if(controller.busy||controller.uncertain)return;controller.invalidate();uiOwner++;status.textContent='Preview cancelled. No changes saved.';controls();});
 applyButton.addEventListener('click',async()=>{
  const owner=uiOwner;status.textContent=controller.uncertain?'Checking the result of the emergency request\u2026':'Saving the emergency schedule and moving affected bookings\u2026';
  const pending=controller.apply();controls();
  try{
   const result=await pending;if(owner!==uiOwner)return;
   status.innerHTML=summaryHtml(result);controls();
   let refreshTimer;
   try{
    const refreshes=await Promise.race([Promise.allSettled([
     typeof loadWorkshopEligibilitySnapshot==='function'?loadWorkshopEligibilitySnapshot('emergency_priority'):Promise.reject(Error('refresh')),
     typeof refreshEmailVehicleLocations==='function'?refreshEmailVehicleLocations():Promise.resolve(),
     root.__workshopDataService?.loadSnapshot?.('emergency_priority')
    ]),new Promise((_,reject)=>{refreshTimer=setTimeout(()=>reject(Error('refresh')),30000);})]);
    if(owner!==uiOwner)return;
    if(refreshes.some(x=>x.status==='rejected'))throw Error('refresh');
    if(typeof renderWorkflowBoard==='function')renderWorkflowBoard();
   }catch(_){if(owner===uiOwner)status.insertAdjacentHTML('beforeend','<p>The changes were saved. Use Refresh board to load the updated bookings.</p>');}
   finally{clearTimeout(refreshTimer);}
  }catch(e){if(owner===uiOwner)status.textContent=e.message;}
  finally{if(owner===uiOwner)controls();}
 });
 function reset(){uiOwner++;controller.invalidate();status.textContent='';input.value='';controls();}
 root.addEventListener('pdc-auth-locked',reset);root.addEventListener('pdc-auth-ready',reset);controls();
 root.PDC_EMERGENCY_PRIORITY={refresh:controls};
})(typeof window==='undefined'?globalThis:window);
