/* Approved Sublet work: show exact operation details and open the existing
 * canonical provider booking form. This module never creates a booking itself. */
(() => {
  'use strict';
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function jobs(vehicle={}) {
    if(vehicle.__emailVehicleServerAuthoritative!==true || vehicle.pdcQcOperationLinesProjectionPresent!==true) return [];
    return (vehicle.pdcQcOperationLines||[]).filter(l=>l.active===true && l.completed!==true && l.stageCode==='SUBLET');
  }
  function notes(vehicle={}) {
    return jobs(vehicle).map(l=>`${l.jobCardNumber?`JC ${l.jobCardNumber} · `:''}${l.description} — ${l.estimatedHours==null?'Hours need review':`${Number(l.estimatedHours)} h`}`).join('\n');
  }
  function detailsHtml(vehicle={}) {
    const lines=jobs(vehicle);
    return lines.length?`<details class="sublet-operation-details"><summary>${lines.length} Sublet job${lines.length===1?'':'s'}</summary><ul>${lines.map(l=>`<li>${esc(l.description)} <strong>${l.estimatedHours==null?'Hours need review':`${esc(l.estimatedHours)} h`}</strong></li>`).join('')}</ul></details>`:'';
  }
  const api={jobs,notes,detailsHtml};
  if(typeof module!=='undefined'&&module.exports) module.exports=api;
  if(typeof window==='undefined'||window.PDC_SUPABASE_CONFIG?.projectRef!=='cdsmnqxtyyoeoznmbidd'||typeof renderSubletHome!=='function'||window.PDC_SUBLET_INTAKE) return;
  window.PDC_SUBLET_INTAKE=api;
  const writable=()=>['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  function populate(vehicle) {
    const input=document.getElementById('sublet-create-notes');
    if(!input)return;
    input.value=notes(vehicle);
    // Full operation details remain in the queue. Let staff shorten an oversized
    // provider note themselves instead of silently losing job instructions.
    const validate=()=>input.setCustomValidity(input.maxLength>0&&input.value.length>input.maxLength?'Shorten these provider notes before booking. Full job details remain on the vehicle.':'');
    input.oninput=validate;validate();
  }
  const oldChoose=chooseSubletCreateVehicle;
  const oldOpen=openSubletCreateDialog;
  openSubletCreateDialog=function(...args){const result=oldOpen(...args);document.getElementById('sublet-create-notes')?.setCustomValidity('');return result;};
  chooseSubletCreateVehicle=function(button) {
    const selected=oldChoose(button);
    if(selected) {
      const rows=subletCreateCanonicalVehicles().filter(v=>v.__emailVehicleId===button.dataset.subletCreateVehicle);
      if(rows.length===1)populate(rows[0]);
    }
    return selected;
  };
  function book(vehicle,providerName='') {
    if(!writable())return;
    openSubletCreateDialog();
    chooseSubletCreateVehicle({dataset:{subletCreateVehicle:vehicle.__emailVehicleId,
      subletCreateVehicleVersion:String(vehicle.__emailVehicleVersion||0),
      subletCreateVehicleLabel:`${displayStockNumber(vehicle)} · ${vehicleCustomerName(vehicle)} · ${displayVehicle(vehicle)}`}});
    const providers=loadSubletProviderRecords().filter(p=>p.active!==false&&p.id&&p.name===providerName);
    if(providers.length===1)document.getElementById('sublet-create-provider').value=providers[0].id;
  }
  const oldRender=renderSubletHome;
  renderSubletHome=function(...args) {
    const result=oldRender(...args);
    const host=document.getElementById('sublet-home-content');
    if(!host)return result;
    const vehicles=subletCreateCanonicalVehicles();
    host.querySelectorAll('.sublet-summary-row').forEach(row=>{
      const open=row.querySelector('[data-open-stock]');
      const matches=vehicles.filter(v=>vehicleKey(v)===open?.dataset.openStock);
      if(matches.length!==1)return;
      const vehicle=matches[0];
      row.cells[6]?.insertAdjacentHTML('beforeend',detailsHtml(vehicle));
      if(!row.querySelector('.sublet-status-pill.is-to-book'))return;
      const button=document.createElement('button');button.type='button';button.className='small-button primary';
      button.textContent='Book Sublet';button.disabled=!writable();button.addEventListener('click',()=>book(vehicle));
      row.lastElementChild.appendChild(button);
      // For an unbooked vehicle, provider choice opens the complete booking form
      // rather than trying to mutate a booking that does not exist yet.
      const provider=row.querySelector('[data-sublet-field="pmbSubletProvider"]');
      if(provider)provider.addEventListener('change',event=>{event.stopImmediatePropagation();const name=provider.value;provider.value=pmbBaySubletProvider(vehicle)||'';book(vehicle,name);},{capture:true});
      row.querySelectorAll('input[type="date"]').forEach(input=>{input.disabled=true;input.title='Choose Book Sublet to set provider and dates.';});
    });
    return result;
  };
  if(app.currentView==='sublet')renderSubletHome();
})();
