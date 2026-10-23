/* One independent provider booking per approved Sublet requirement. */
(() => {
  'use strict';
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function jobs(vehicle={}) {
    if(vehicle.__emailVehicleServerAuthoritative!==true || vehicle.pdcQcOperationLinesProjectionPresent!==true) return [];
    return (vehicle.pdcQcOperationLines||[]).filter(l=>l.active===true && l.completed!==true && l.stageCode==='SUBLET');
  }
  function pending(vehicle={}) {
    return jobs(vehicle).filter(line=>!(vehicle.pdcSubletBookings||[]).some(booking=>
      booking.operationLineIdentity===line.lineIdentity && ['active','returned'].includes(booking.status)));
  }
  function notes(vehicle={},identity='') {
    return jobs(vehicle).filter(l=>!identity||l.lineIdentity===identity)
      .map(l=>`${l.jobCardNumber?`JC ${l.jobCardNumber} · `:''}${l.description}`).join('\n');
  }
  function detailsHtml(vehicle={}) {
    if(vehicle.__subletOperationDescription) return `<p class="sublet-operation-details">${esc(vehicle.__subletOperationDescription)}</p>`;
    if(vehicle.__subletBookingId) return '';
    const lines=jobs(vehicle);
    return lines.length?`<details class="sublet-operation-details"><summary>${lines.length} Sublet job${lines.length===1?'':'s'}</summary><ul>${lines.map(l=>`<li>${esc(l.description)}</li>`).join('')}</ul></details>`:'';
  }
  const api={jobs,pending,notes,detailsHtml};
  if(typeof module!=='undefined'&&module.exports) module.exports=api;
  if(typeof window==='undefined'||window.PDC_SUPABASE_CONFIG?.projectRef!=='cdsmnqxtyyoeoznmbidd'||typeof renderSubletHome!=='function'||window.PDC_SUBLET_INTAKE) return;
  window.PDC_SUBLET_INTAKE=api;
  const writable=()=>['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const canAddProvider=()=>typeof workshopTechnicianAdminCanMutate==='function'&&workshopTechnicianAdminCanMutate();
  const newProviderValue='__new_sublet_provider__';
  let providerGeneration=0;
  let previousProviderId='';
  let previousProviderEmail='';
  function providerOptions(selected='') {
    const rows=loadSubletProviderRecords().filter(row=>row.active!==false&&row.id);
    const select=document.getElementById('sublet-create-provider');
    select.innerHTML=`<option value="">Select provider</option>${canAddProvider()?`<option value="${newProviderValue}">Add new provider…</option>`:''}${rows.map(row=>`<option value="${esc(row.id)}">${esc(row.name)}</option>`).join('')}`;
    select.value=rows.some(row=>row.id===selected)?selected:'';
  }
  function showProviderEntry() {
    if(!canAddProvider())return;
    const entry=document.getElementById('sublet-new-provider');
    const select=document.getElementById('sublet-create-provider');
    previousProviderEmail=document.getElementById('sublet-create-provider-email').value;
    select.value=newProviderValue;
    entry.hidden=false;entry.style.display='grid';
    entry.querySelectorAll('input').forEach(input=>{input.disabled=false;});
    document.getElementById('sublet-new-provider-error').textContent='';
    document.getElementById('sublet-new-provider-name').focus();
  }
  function hideProviderEntry() {
    const entry=document.getElementById('sublet-new-provider');
    if(!entry)return;
    entry.hidden=true;entry.style.display='none';
    entry.querySelectorAll('input').forEach(input=>{input.disabled=true;});
  }
  async function saveNewProvider() {
    const entry=document.getElementById('sublet-new-provider');
    const error=document.getElementById('sublet-new-provider-error');
    const nameInput=document.getElementById('sublet-new-provider-name');
    const emailInput=document.getElementById('sublet-new-provider-email');
    if(entry.hidden||entry.dataset.busy==='true')return;
    error.textContent='';
    if(!canAddProvider()){error.textContent='Administrator access is required to add a provider.';return;}
    const name=nameInput.value.trim().replace(/\s+/g,' ');
    const email=emailInput.value.trim();
    if(!name){error.textContent='Enter a provider name.';nameInput.focus();return;}
    if(!subletProviderEmailValid(email)||!emailInput.reportValidity()){error.textContent='Enter a valid email address, or leave it blank.';return;}
    const service=initWorkshopReferenceDataServiceIfAvailable();
    if(!service?.addSubletProvider){error.textContent='The provider list is unavailable. Please try again.';return;}
    const generation=providerGeneration;
    const token=getPdcSupabaseAccessToken();
    const current=()=>generation===providerGeneration&&canAddProvider()&&token===getPdcSupabaseAccessToken()
      &&service===window.__workshopReferenceDataService&&document.getElementById('sublet-create-dialog')?.open;
    const select=document.getElementById('sublet-create-provider');
    entry.dataset.busy='true';select.disabled=true;
    entry.querySelectorAll('input,button').forEach(input=>{input.disabled=true;});
    try {
      await service.listSubletProviders(true);
      if(!current())return;
      if(service.getCachedSubletProviders().error)throw new Error('provider_list_unavailable');
      const matches=()=>loadSubletProviderRecords(true).filter(row=>String(row.name||'').trim().toLowerCase()===name.toLowerCase());
      let rows=matches();
      if(!rows.length){
        const result=await service.addSubletProvider(name,email);
        if(!current())return;
        if(!result?.ok&&result?.error!=='duplicate_name'){
          error.textContent=result?.error==='permission_denied'?'Administrator access is required to add a provider.':'Could not add the provider. Please try again.';return;
        }
        rows=matches();
      }
      const active=rows.filter(row=>row.active===true&&row.id);
      if(active.length!==1){error.textContent=rows.length?'This provider is inactive. Reactivate it in the provider list before booking.':'The provider list could not be refreshed. Please try again.';return;}
      providerOptions(active[0].id);
      previousProviderId=active[0].id;
      fillSubletCreateProviderEmail();
      hideProviderEntry();
      select.focus();
    } catch(_error) {
      if(current())error.textContent='Could not update the provider list. Check your connection and try again.';
    } finally {
      if(generation===providerGeneration){
        entry.dataset.busy='false';select.disabled=false;
        entry.querySelectorAll('button').forEach(button=>{button.disabled=false;});
        entry.querySelectorAll('input').forEach(input=>{input.disabled=entry.hidden;});
      }
    }
  }
  function prepareProviderEntry() {
    const select=document.getElementById('sublet-create-provider');
    const form=document.getElementById('sublet-create-form');
    if(!select||!form)return;
    if(!document.getElementById('sublet-new-provider')){
      const entry=document.createElement('section');entry.id='sublet-new-provider';entry.hidden=true;
      entry.style.cssText='display:none;gap:10px;padding:12px;border:1px solid #cbd5e1;border-radius:8px;background:#f8fafc';
      entry.innerHTML='<label>New provider name<input id="sublet-new-provider-name" autocomplete="organization" disabled></label><label>Email (optional)<input id="sublet-new-provider-email" type="email" autocomplete="email" disabled></label><div><button type="button" class="primary" data-provider-save>Add provider</button> <button type="button" class="small-button" data-provider-cancel>Cancel</button></div><small>Saved to the provider list for future bookings.</small><p id="sublet-new-provider-error" class="sublet-create-error" role="alert"></p>';
      select.closest('label').after(entry);
      entry.querySelector('[data-provider-save]').addEventListener('click',()=>void saveNewProvider());
      entry.querySelector('[data-provider-cancel]').addEventListener('click',()=>{
        hideProviderEntry();select.value=previousProviderId;
        document.getElementById('sublet-create-provider-email').value=previousProviderEmail;select.focus();
      });
      entry.addEventListener('keydown',event=>{if(event.key==='Enter'&&event.target.tagName==='INPUT'){event.preventDefault();void saveNewProvider();}});
      select.addEventListener('change',event=>{
        if(select.value===newProviderValue){event.stopImmediatePropagation();showProviderEntry();}
        else{previousProviderId=select.value;hideProviderEntry();}
      },{capture:true});
      form.addEventListener('submit',event=>{
        if(!entry.hidden||select.value===newProviderValue){event.preventDefault();event.stopImmediatePropagation();document.getElementById('sublet-new-provider-error').textContent='Add the new provider before creating the booking.';}
      },{capture:true});
    }
    const entry=document.getElementById('sublet-new-provider');
    entry.dataset.busy='false';entry.querySelectorAll('button').forEach(button=>{button.disabled=false;});
    select.disabled=false;hideProviderEntry();providerOptions();previousProviderId='';previousProviderEmail='';
  }
  function populate(vehicle,identity='') {
    const input=document.getElementById('sublet-create-notes');
    const select=document.getElementById('sublet-create-operation');
    const label=document.getElementById('sublet-create-operation-label');
    if(!input||!select||!label)return;
    const lines=pending(vehicle);
    label.hidden=jobs(vehicle).length===0;
    select.innerHTML=`<option value="">${lines.length?'Select one requirement':'All requirements already booked'}</option>${lines.map(l=>`<option value="${esc(l.lineIdentity)}">${esc(l.description)}</option>`).join('')}`;
    select.value=lines.some(l=>l.lineIdentity===identity)?identity:lines.length===1?lines[0].lineIdentity:'';
    select.onchange=()=>{input.value=select.value?notes(vehicle,select.value):'';input.setCustomValidity('');};
    select.onchange();
    input.oninput=()=>input.setCustomValidity(input.maxLength>0&&input.value.length>input.maxLength?'Shorten these provider notes before booking. Full job details remain on the vehicle.':'');
  }
  const oldChoose=chooseSubletCreateVehicle;
  const oldOpen=openSubletCreateDialog;
  // r501 (F114, Craig 23 Oct 07:55): 'all the sublet bookings need to be done from the side menu ... when you click manage
  // sublets'. The Sublet page no longer creates bookings: Create Sublet and Book Sublet are hidden (kept in the code, not
  // deleted), the dialog does not open, and dates and suppliers are changed in Manage sublets. Existing bookings still show;
  // the Back tick (returned) still works here because Manage sublets has no return control.
  const CREATE_ON_SUBLET_PAGE=false;
  const BOOK_NOTE='Book sublets from the vehicle: Vehicle Locations, open the vehicle, then Manage sublets';
  const DATES_TITLE='Due out, Due back and the supplier are set in Manage sublets (Vehicle Locations, open the vehicle, then Manage sublets).';
  const manageSublets=key=>{const vs=window.PDC_VEHICLE_SUBLETS;if(vs?.open&&key)vs.open(key);else pdcNotify(BOOK_NOTE);};
  function hideCreateControls(){
    const button=document.getElementById('sublet-create-open');
    if(!button||CREATE_ON_SUBLET_PAGE)return;
    button.hidden=true;button.style.display='none';button.setAttribute('aria-hidden','true');button.tabIndex=-1;
    if(!document.getElementById('pdc-sublet-book-note'))button.insertAdjacentHTML('afterend',`<span id="pdc-sublet-book-note" class="pdc-sublet-book-note" role="note" style="display:inline-block;padding:6px 10px;border-radius:6px;background:#fbf5e5;border:1px solid #e7d3a1;color:#6f5216;font-weight:650;font-size:13px">${BOOK_NOTE}</span>`);
  }
  hideCreateControls();
  openSubletCreateDialog=function(...args){
    if(!CREATE_ON_SUBLET_PAGE){pdcNotify(BOOK_NOTE);return false;}
    providerGeneration++;
    const result=oldOpen(...args);
    prepareProviderEntry();
    document.getElementById('sublet-create-notes')?.setCustomValidity('');
    const select=document.getElementById('sublet-create-operation');
    if(select){select.innerHTML='';select.onchange=null;}
    const label=document.getElementById('sublet-create-operation-label');if(label)label.hidden=true;
    return result;
  };
  const oldClose=closeSubletCreateDialog;
  closeSubletCreateDialog=function(...args){providerGeneration++;return oldClose(...args);};
  // The app bound this button before the intake module loaded. Route it through
  // the current dialog wrapper so the provider entry is available there too.
  document.getElementById('sublet-create-open')?.addEventListener('click',event=>{
    event.preventDefault();event.stopImmediatePropagation();openSubletCreateDialog();
  },{capture:true});
  // r501: the calendar is view only (no drag to move a date); each card has Manage sublets instead.
  document.getElementById('sublet-home-content')?.addEventListener('dragstart',event=>{
    if(CREATE_ON_SUBLET_PAGE||!event.target?.closest?.('[data-sublet-calendar-event]'))return;
    event.preventDefault();event.stopImmediatePropagation();
  },{capture:true});
  chooseSubletCreateVehicle=function(button) {
    const selected=oldChoose(button);
    if(selected) {
      const rows=subletCreateCanonicalVehicles().filter(v=>v.__emailVehicleId===button.dataset.subletCreateVehicle);
      if(rows.length===1)populate(rows[0]);
    }
    return selected;
  };
  function book(vehicle,providerName='',addProvider=false) {
    if(!writable())return;
    openSubletCreateDialog();
    chooseSubletCreateVehicle({dataset:{subletCreateVehicle:vehicle.__emailVehicleId,
      subletCreateVehicleVersion:String(vehicle.__emailVehicleVersion||0),
      subletCreateVehicleLabel:`${displayStockNumber(vehicle)} · ${vehicleCustomerName(vehicle)} · ${displayVehicle(vehicle)}`}});
    populate(vehicle,vehicle.__subletOperationIdentity||'');
    const providers=loadSubletProviderRecords().filter(p=>p.active!==false&&p.id&&p.name===providerName);
    if(providers.length===1){document.getElementById('sublet-create-provider').value=providers[0].id;previousProviderId=providers[0].id;fillSubletCreateProviderEmail();}
    if(addProvider)showProviderEntry();
  }
  const oldRender=renderSubletHome;
  renderSubletHome=function(...args) {
    const result=oldRender(...args);
    const host=document.getElementById('sublet-home-content');
    if(!host)return result;
    const createHere=typeof CREATE_ON_SUBLET_PAGE!=='undefined'&&CREATE_ON_SUBLET_PAGE;
    if(!createHere&&typeof app!=='undefined'&&app.subletViewMode==='calendar'){
      host.querySelectorAll('[data-sublet-calendar-event]').forEach(card=>{
        card.draggable=false;card.setAttribute('draggable','false');
        const openButton=card.querySelector('.sublet-calendar-event-open');
        const key=openButton?.dataset.openStock||'';
        if(openButton)openButton.setAttribute('aria-label',String(openButton.getAttribute('aria-label')||'').replace(/Drag the card to move this date, or use the date field in List View\./,'Change dates in Manage sublets.'));
        if(!key||card.querySelector('[data-pdc-manage-sublets]'))return;
        const manage=document.createElement('button');manage.type='button';manage.className='small-button pdc-sublet-manage';manage.dataset.pdcManageSublets=key;
        manage.textContent='Manage sublets';manage.title='Change this booking\'s dates or supplier in Manage sublets';
        manage.addEventListener('click',event=>{event.stopPropagation();manageSublets(key);});
        card.appendChild(manage);
      });
      return result;
    }
    // Project the queue once. Looking up each displayed row through
    // subletVehicleByKey rebuilds every vehicle's requirements every time.
    const vehiclesByKey=new Map();
    subletRows().forEach(vehicle=>{
      [vehicle.__subletBookingId,vehicle.__subletOperationKey,vehicleKey(vehicle)].filter(Boolean).forEach(key=>{
        if(!vehiclesByKey.has(key))vehiclesByKey.set(key,vehicle);
      });
    });
    host.querySelectorAll('.sublet-summary-row').forEach(row=>{
      const key=row.querySelector('[data-sublet-toggle]')?.dataset.subletToggle;
      const vehicle=vehiclesByKey.get(key);
      if(!vehicle)return;
      row.querySelector('.sublet-work-required')?.insertAdjacentHTML('beforeend',detailsHtml(vehicle));
      if(!createHere){
        const actions=row.lastElementChild;
        if(!actions)return;
        // r501: no Book Sublet here; the supplier and dates are view only on this page.
        row.querySelectorAll('[data-sublet-field="pmbSubletProvider"], [data-sublet-field="pmbSubletBookingDate"], [data-sublet-field="pmbSubletExpectedReturnDate"]').forEach(input=>{input.disabled=true;input.title=DATES_TITLE;});
        if(row.querySelector('.sublet-status-pill.is-to-book'))row.querySelectorAll('[data-sublet-returned]').forEach(input=>{input.disabled=true;input.title=DATES_TITLE;});
        const key=vehicle.__subletVehicleKey||vehicleKey(vehicle);
        if(key&&!actions.querySelector('[data-pdc-manage-sublets]')){
          const manage=document.createElement('button');manage.type='button';manage.className='small-button primary pdc-sublet-manage';manage.dataset.pdcManageSublets=key;
          manage.textContent='Manage sublets';manage.title='Set the supplier, Due out and Due back for this vehicle\'s sublets';
          manage.addEventListener('click',event=>{event.stopPropagation();manageSublets(key);});
          actions.appendChild(manage);
        }
        return;
      }
      if(!row.querySelector('.sublet-status-pill.is-to-book'))return;
      const button=document.createElement('button');button.type='button';button.className='small-button primary';
      button.textContent='Book Sublet';button.disabled=!writable();button.addEventListener('click',()=>book(vehicle));
      row.lastElementChild.appendChild(button);
      const provider=row.querySelector('[data-sublet-field="pmbSubletProvider"]');
      if(provider){
        if(canAddProvider())provider.insertAdjacentHTML('afterbegin','<option value="" data-new-sublet-provider>Add new provider…</option>');
        provider.value=pmbBaySubletProvider(vehicle)||'';
        // Keep Unassigned selected when the new option also has an empty value.
        if(!pmbBaySubletProvider(vehicle))provider.selectedIndex=Array.from(provider.options).findIndex(option=>!option.hasAttribute('data-new-sublet-provider')&&option.value==='');
        provider.addEventListener('change',event=>{
          event.stopImmediatePropagation();
          const addProvider=provider.selectedOptions[0]?.hasAttribute('data-new-sublet-provider');
          const name=provider.value;
          provider.selectedIndex=Array.from(provider.options).findIndex(option=>!option.hasAttribute('data-new-sublet-provider')&&option.value===(pmbBaySubletProvider(vehicle)||''));
          book(vehicle,name,addProvider);
        },{capture:true});
      }
      row.querySelectorAll('input[type="date"], [data-sublet-returned]').forEach(input=>{input.disabled=true;input.title='Choose Book Sublet to set provider and dates.';});
    });
    return result;
  };
  if(app.currentView==='sublet')renderSubletHome();
})();
