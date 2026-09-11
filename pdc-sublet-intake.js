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
  openSubletCreateDialog=function(...args){
    const result=oldOpen(...args);
    document.getElementById('sublet-create-notes')?.setCustomValidity('');
    const select=document.getElementById('sublet-create-operation');
    if(select){select.innerHTML='';select.onchange=null;}
    const label=document.getElementById('sublet-create-operation-label');if(label)label.hidden=true;
    return result;
  };
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
    populate(vehicle,vehicle.__subletOperationIdentity||'');
    const providers=loadSubletProviderRecords().filter(p=>p.active!==false&&p.id&&p.name===providerName);
    if(providers.length===1){document.getElementById('sublet-create-provider').value=providers[0].id;fillSubletCreateProviderEmail();}
  }
  const oldRender=renderSubletHome;
  renderSubletHome=function(...args) {
    const result=oldRender(...args);
    const host=document.getElementById('sublet-home-content');
    if(!host)return result;
    host.querySelectorAll('.sublet-summary-row').forEach(row=>{
      const key=row.querySelector('[data-sublet-toggle]')?.dataset.subletToggle;
      const vehicle=subletVehicleByKey(key);
      if(!vehicle)return;
      row.cells[6]?.insertAdjacentHTML('beforeend',detailsHtml(vehicle));
      if(!row.querySelector('.sublet-status-pill.is-to-book'))return;
      const button=document.createElement('button');button.type='button';button.className='small-button primary';
      button.textContent='Book Sublet';button.disabled=!writable();button.addEventListener('click',()=>book(vehicle));
      row.lastElementChild.appendChild(button);
      const provider=row.querySelector('[data-sublet-field="pmbSubletProvider"]');
      if(provider)provider.addEventListener('change',event=>{event.stopImmediatePropagation();const name=provider.value;provider.value='';book(vehicle,name);},{capture:true});
      row.querySelectorAll('input[type="date"], [data-sublet-returned]').forEach(input=>{input.disabled=true;input.title='Choose Book Sublet to set provider and dates.';});
    });
    return result;
  };
  if(app.currentView==='sublet')renderSubletHome();
})();
