/* New Job Cards: human station review before release to the operational board. */
(() => {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const STATIONS = Object.freeze([
    ['FITTING', 'Fitting'], ['ELECTRICAL', 'Electrical'], ['FABRICATION', 'Fabrication'],
    ['HOIST', 'Hoist'], ['TINT', 'Tint'], ['TYRE', 'Tyre'], ['BUS_4X4', 'Bus 4×4'], ['SUBLET', 'Sublet'],
  ]);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const validStation = code => STATIONS.some(([station]) => station === code);
  function reviewChoices(row) {
    return Object.fromEntries(assignmentsFor(row).map(line => [line.line_identity, line.stage_code]));
  }
  const positiveHours = value => value !== null && value !== undefined && String(value).trim() !== ''
    && Number.isFinite(Number(value)) && Number(value)>0 && Number(value)<=999.99
    && Math.abs(Number(value)*100-Math.round(Number(value)*100))<1e-8;
  function hoursFor(line, hours = {}) {
    return Object.prototype.hasOwnProperty.call(hours,line.line_identity) ? hours[line.line_identity] : line.estimated_hours;
  }
  function assignmentsFor(row, choices = {}, hours = null) {
    return (row?.operations || []).map(line => ({line_identity: line.line_identity,
      stage_code: line.department === '138' ? 'BUS_4X4' : choices[line.line_identity] ?? (validStation(line.stage_code) ? line.stage_code : ''),
      ...(hours && (line.department === '138' || (choices[line.line_identity] ?? line.stage_code) !== 'SUBLET') ? {estimated_hours:positiveHours(hoursFor(line,hours))?Number(hoursFor(line,hours)):null} : {})}));
  }
  function problems(row, choices = {}, hours = {}) {
    if (!row || row.status !== 'pending' || !Array.isArray(row.operations) || !row.operations.length) return ['No complete Job Card is available.'];
    const issues = [];
    if (assignmentsFor(row, choices).some(item => !validStation(item.stage_code))) issues.push('Choose a station for every operation.');
    const assigned = new Map(assignmentsFor(row, choices).map(item => [item.line_identity, item.stage_code]));
    if (row.operations.some(line => assigned.get(line.line_identity) !== 'SUBLET' && !positiveHours(hoursFor(line,hours)))) issues.push('Enter positive hours for workshop operations; Sublet does not require hours.');
    if (row.operations.some(line => line.completed === true || line.active !== true)) issues.push('An operation changed or has already been completed. Reload this Job Card.');
    if (new Set(row.operations.map(line => line.line_identity)).size !== row.operations.length) issues.push('Duplicate operation identity needs review.');
    return issues;
  }
  function stationGroups(row, choices = {}, drafts = {}) {
    const assignment = new Map(assignmentsFor(row, choices).map(item => [item.line_identity,item.stage_code]));
    return [['', 'Needs Review'], ...STATIONS].map(([code,label]) => {
      const lines = (row?.operations || []).filter(line => assignment.get(line.line_identity) === code);
      const hours = lines.some(line => !positiveHours(hoursFor(line,drafts))) ? null : lines.reduce((sum,line) => sum+Number(hoursFor(line,drafts)),0);
      return {code,label,lines,hours};
    });
  }
  function verifyApproval(result,row,choices,hours={}) {
    const data=result?.data;
    if (result?.ok!==true || data?.vehicle_id!==row.vehicle_id || data?.visible_on_board!==true
      || data?.bookings_created!==0 || !Array.isArray(data.operations) || data.operations.length!==row.operations.length) return false;
    return assignmentsFor(row,choices).every(wanted => {
      const before=row.operations.find(line=>line.line_identity===wanted.line_identity);
      const after=data.operations.filter(line=>line.line_identity===wanted.line_identity);
      return after.length===1 && after[0].stage_code===wanted.stage_code && after[0].description===before.description
        && after[0].source_line_id===before.source_line_id && after[0].estimated_hours===(wanted.stage_code==='SUBLET'?before.estimated_hours:Number(hoursFor(before,hours)))
        && after[0].completed===false;
    });
  }
  const api={STATIONS,reviewChoices,assignmentsFor,problems,stationGroups,verifyApproval,positiveHours,hoursFor,esc};
  if(typeof module!=='undefined' && module.exports) module.exports=api;
  if(typeof window==='undefined' || window.PDC_SUPABASE_CONFIG?.projectRef!==PROJECT
      || typeof showView!=='function' || window.PDC_NEW_VEHICLES_VERSION) return;

  let items=[],total=0,offset=0,selected=null,choices={},loading=false,saving=false,error='',notice='',sourceChanged=false;
  let unidentified=false,unidentifiedItems=[],unidentifiedTotal=0;
  let generation=0,requestKey='',approvalRequest=null,hourDrafts={};
  const limit=50;
  const readable=()=>['viewer','operator','importer','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const writable=()=>['operator','administrator'].includes(window.PDC_AUTH_CONTEXT?.role);
  const adminMenu=document.getElementById('nav-admin-menu');
  for(const view of ['emailreview','ai-auditor']) {
    const button=document.querySelector(`.nav-item[data-view="${view}"]`);
    if(button && adminMenu) {button.classList.add('nav-admin-item');adminMenu.appendChild(button);}
  }
  const nav=document.createElement('button');
  nav.type='button';nav.className='nav-item';nav.dataset.view='newvehicles';nav.dataset.short='NEW';
  nav.innerHTML='New Vehicles <span class="new-vehicle-nav-count" hidden></span>';
  document.querySelector('.nav-item[data-view="dashboard"]')?.insertAdjacentElement('beforebegin',nav);
  nav.addEventListener('click',()=>showView('newvehicles'));
  const page=document.createElement('section');page.id='newvehicles';page.className='view';
  page.setAttribute('aria-label','New vehicle Job Card review');document.querySelector('main.main')?.appendChild(page);

  async function rpc(name,payload) {
    const config=window.PDC_SUPABASE_CONFIG;
    const actor=window.PDC_AUTH_CONTEXT?.userId;
    const token=getPdcSupabaseAccessToken();
    if(!token || !actor || !readable() || new URL(config.url).hostname!==`${PROJECT}.supabase.co`) throw new Error('not_authorized');
    const abort=new AbortController(), timer=setTimeout(()=>abort.abort(),60000);
    try {
      const res=await fetch(`${config.url.replace(/\/$/,'')}/rest/v1/rpc/${name}`,{method:'POST',signal:abort.signal,
        headers:{apikey:config.publishableKey,Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify(payload)});
      const result=await res.json();
      if(actor!==window.PDC_AUTH_CONTEXT?.userId) throw new Error('session_changed');
      if(!res.ok || result?.ok!==true) throw new Error(result?.code || 'request_failed');
      return result;
    } finally {clearTimeout(timer);}
  }
  function message(err) {
    const code=String(err?.message || '');
    if(/changed|stale|conflict|already_approved/.test(code)) return 'This Job Card changed or was approved in another session. Reload it before continuing.';
    if(/authorized|session/.test(code)) return 'Sign in with an approved staff account. Only Operators and Administrators can approve.';
    if(/hours/.test(code)) return 'Workshop operations need valid hours before release. Sublet does not require hours.';
    if(/stations/.test(code)) return 'Assign every operation to a station.';
    return 'The request could not be confirmed. Refresh the queue before retrying; no success has been assumed.';
  }
  async function load({silent=false}={}) {
    if(loading || saving || !readable()) return;
    const stamp=++generation;loading=true;
    if(!silent) {error='';render();}
    try {
      const result=await rpc(unidentified?'list_pdc_unidentified_tune_reviews':'list_pdc_new_vehicle_reviews',{p_offset:offset,p_limit:limit});
      if(stamp!==generation) return;
      if(unidentified) {unidentifiedItems=result.data.items;unidentifiedTotal=result.data.total;}
      else {items=result.data.items;total=result.data.total;}
      if(selected) {
        const latest=items.find(row=>row.vehicle_id===selected.vehicle_id);
        if(!latest || latest.snapshot_hash!==selected.snapshot_hash) sourceChanged=true;
      }
      error='';
    } catch(err) {if(stamp===generation) error=message(err);}
    finally {if(stamp===generation) {loading=false;render();}}
  }
  function choose(row) {selected=row;choices=reviewChoices(row);hourDrafts={};sourceChanged=false;requestKey='';approvalRequest=null;error='';notice='';render();}
  function card(row) {
    return `<button type="button" class="nv-card" data-nv-open="${esc(row.vehicle_id)}"><span class="nv-card-top"><strong>${esc(row.stock_number)}</strong><span class="nv-new-pill">New Job Card</span></span>
      <b>${esc(row.vehicle_description || 'Vehicle details pending')}</b><span>${esc(row.customer_name || 'Customer not recorded')}</span>
      <small>${esc((row.job_cards || []).join(', ') || 'Job Card not recorded')} · ${row.operations.length} operations</small>
      <span class="nv-card-bottom">${esc(row.current_location || 'Location pending')}<small>${esc(new Date(row.received_at).toLocaleString('en-AU',{dateStyle:'medium',timeStyle:'short'}))}</small></span></button>`;
  }
  function operation(line) {
    const assigned=assignmentsFor(selected,choices).find(item=>item.line_identity===line.line_identity)?.stage_code || '';
    const suggested=STATIONS.find(([code])=>code===line.stage_code)?.[1];
    const sublet=assigned==='SUBLET';
    const value=hoursFor(line,hourDrafts),missing=!sublet&&!positiveHours(value);
    const standard=line.hours_provenance==='craig_standard_pre_delivery_1_hour';
    return `<article class="nv-operation nv-operation-pill ${missing?'nv-hours-missing':''}" draggable="${line.department!=='138'&&writable()&&!saving&&!sourceChanged}" data-nv-line="${esc(line.line_identity)}">
      <strong tabindex="0" title="${esc(line.description)}">${esc(line.description)}</strong><small>${line.department?`Dept ${esc(line.department)} · `:''}${esc(line.operation_code || (line.department ? 'Line '+line.original_line_number : line.operation_no))}</small>
      ${line.department==='138'?'<span class="nv-pill-suggestion">Bus 4×4 · Department 138</span>':!assigned&&suggested?`<span class="nv-pill-suggestion">Suggested: ${esc(suggested)}</span>`:''}
      ${sublet?'':`<label class="nv-hours-label">Hours<input type="number" min="0.01" max="999.99" step="0.01" inputmode="decimal" aria-label="Hours for ${esc(line.description)}" aria-invalid="${missing}" data-nv-hours="${esc(line.line_identity)}" value="${esc(value??'')}" placeholder="Enter hours" ${standard?'readonly':''} ${!writable()||saving||sourceChanged?'disabled':''}></label>`}
      <small class="nv-hours-hint">${sublet?'Hours not required':missing?'Hours required before approval':standard?'Pre-delivery · 1 hour standard':'Hours confirmed'}</small></article>`;
  }
  function stationSection(group, tray=false) {
    const theme=!tray&&typeof vehicleWorkshopStationPresentation==='function'?vehicleWorkshopStationPresentation(group.code):null;
    const style=theme?` style="--station-colour:${esc(theme.colour)};--station-tint:${esc(theme.tint)}"`:'';
    return `<section class="nv-station ${tray?'needs-review nv-review-tray':''}" data-nv-drop="${group.code}"${style}><header><h3>${esc(group.label)}</h3><small>${group.lines.length} items · ${group.code==='SUBLET'?'Hours not required':group.hours==null?'Hours need review':`${group.hours.toFixed(2)} h`}</small></header><div>${group.lines.map(operation).join('') || `<p class="nv-drop-hint">${tray?'All operations have been placed. Drag a pill back here to review it again.':'Drag pills here'}</p>`}</div></section>`;
  }
  function render() {
    const badge=nav.querySelector('.new-vehicle-nav-count');badge.textContent=String(total);badge.hidden=!total;
    nav.setAttribute('aria-label',`New Vehicles, ${total} awaiting review`);
    if(unidentified) {
      page.innerHTML=`<div class="nv-header"><div><h2>Unidentified Tune Review</h2><p>${unidentifiedTotal} R/O groups awaiting vehicle identity. No vehicles have been created for these groups.</p></div>
        <div class="nv-header-actions"><button data-nv-unidentified ${loading?'disabled':''}>New Vehicles</button><button data-nv-refresh ${loading?'disabled':''}>Refresh</button></div></div>
        ${error?`<div class="nv-error" role="alert">${esc(error)}</div>`:''}
        ${unidentifiedItems.map(group=>`<details class="nv-summary"><summary><strong>${esc(group.repair_order_number)}</strong> · Dept ${esc(group.department)} · ${group.operation_count} operations · ${Number(group.hours).toFixed(2)} h</summary>
          ${group.operations.map(line=>`<article class="nv-operation"><strong>${esc(line.description)}</strong><small>Line ${esc(line.line)} · ${Number(line.hours).toFixed(2)} h · ${esc(line.station)}</small></article>`).join('')}</details>`).join('') || `<p>${loading?'Loading…':'No unidentified Tune groups waiting.'}</p>`}
        <div class="nv-pagination"><button data-nv-page="-1" ${offset===0||loading?'disabled':''}>Previous</button><span>${unidentifiedTotal} groups</span><button data-nv-page="1" ${offset+unidentifiedItems.length>=unidentifiedTotal||loading?'disabled':''}>Next</button></div>`;
      page.querySelector('[data-nv-unidentified]')?.addEventListener('click',()=>{unidentified=false;offset=0;void load();});
      page.querySelector('[data-nv-refresh]')?.addEventListener('click',()=>void load());
      page.querySelectorAll('[data-nv-page]').forEach(button=>button.addEventListener('click',()=>{offset=Math.max(0,offset+Number(button.dataset.nvPage)*limit);void load();}));
      return;
    }
    const issues=selected?problems(selected,choices,hourDrafts):[];
    const groups=selected?stationGroups(selected,choices,hourDrafts):[];
    const approvalButton=()=>`<button class="primary nv-approve-button" type="button" data-nv-approve ${saving||sourceChanged||issues.length||!writable()?'disabled':''}>${saving?'Saving & adding to board…':'Approve & add to board'}</button>`;
    page.innerHTML=`<div class="nv-header"><div><span class="eyebrow">Tune / Revolution imports</span><h2>${selected?esc(selected.stock_number):'New Vehicles'}</h2>
      <p>${selected?'Review the operation stations, then approve the Job Card.':`${total} awaiting review before they enter Vehicle Locations.`}</p></div>
      <div class="nv-header-actions">${selected?approvalButton()+'<button type="button" data-nv-back>← Vehicle list</button>':'<button type="button" data-nv-unidentified '+(loading?'disabled':'')+'>Unidentified Tune Review</button>'}<button type="button" data-nv-refresh ${loading||saving?'disabled':''}>${loading?'Refreshing…':'Refresh'}</button></div></div>
      ${error?`<div class="nv-error" role="alert">${esc(error)}</div>`:''}${notice?`<div class="nv-notice" role="status">${esc(notice)}</div>`:''}
      ${selected?`<section class="nv-summary"><h3>${esc(selected.vehicle_description)}</h3><p>${esc(selected.customer_name)} · Job Card ${esc((selected.job_cards || []).join(', '))}</p><p>Location: <strong>${esc(selected.current_location || 'Pending')}</strong>${selected.eta_to_kewdale?` · Kewdale ETA: ${esc(selected.eta_to_kewdale)}`:''} · VIN: ${esc(selected.vin || 'Not recorded')}</p></section>
      ${sourceChanged?'<div class="nv-error" role="alert">Source data changed. <button type="button" data-nv-reload>Reload Job Card</button> before approving.</div>':''}
      <p class="nv-help">Drag chips into their stations. Enter positive hours in every red field before approval. Sublet does not require hours. Pre-delivery is 1 hour standard. Department 138 stays in Bus 4×4. Sublet work appears in the Sublet To book list after approval, ready to select a provider. Your choices and hours are saved when you approve.</p>
      ${stationSection(groups[0],true)}
      <div class="nv-stations">${groups.filter(group=>group.code).map(group=>stationSection(group)).join('')}</div>
      <footer class="nv-approval"><div>${issues.length?issues.map(issue=>`<p>${esc(issue)}</p>`).join(''):'<p>All operations have a station and required workshop hours.</p>'}<small>Approval adds this vehicle to its current location on the board. Nothing is booked or marked fitted.</small></div>
      ${approvalButton()}</footer>`:
      `<div class="nv-list">${items.map(card).join('') || `<div class="nv-empty"><h3>${loading?'Loading Job Cards…':error?'Queue unavailable':'No new vehicles waiting'}</h3><p>New report vehicles appear here after import processing. Existing board vehicles are not reset or pulled back into this queue.</p></div>`}</div>
      <div class="nv-pagination"><button data-nv-page="-1" ${offset===0||loading?'disabled':''}>Previous</button><span>${total?`${offset+1}–${Math.min(offset+items.length,total)} of ${total}`:'0 awaiting review'}</span><button data-nv-page="1" ${offset+items.length>=total||loading?'disabled':''}>Next</button></div>`}`;
    page.querySelectorAll('[data-nv-open]').forEach(button=>button.addEventListener('click',()=>choose(items.find(row=>row.vehicle_id===button.dataset.nvOpen))));
    page.querySelector('[data-nv-unidentified]')?.addEventListener('click',()=>{unidentified=true;offset=0;void load();});
    page.querySelector('[data-nv-refresh]')?.addEventListener('click',()=>void load());
    page.querySelector('[data-nv-back]')?.addEventListener('click',()=>{if(saving)return;selected=null;choices={};render();});
    page.querySelector('[data-nv-reload]')?.addEventListener('click',()=>{const id=selected.vehicle_id;const row=items.find(item=>item.vehicle_id===id);if(row) choose(row);else {selected=null;render();void load();}});
    page.querySelectorAll('[data-nv-page]').forEach(button=>button.addEventListener('click',()=>{offset=Math.max(0,offset+Number(button.dataset.nvPage)*limit);void load();}));
    page.querySelectorAll('[data-nv-hours]').forEach(input=>{
      input.addEventListener('input',()=>{
        hourDrafts[input.dataset.nvHours]=input.value;requestKey='';approvalRequest=null;
        const invalid=!positiveHours(input.value),tile=input.closest('[data-nv-line]');
        tile.classList.toggle('nv-hours-missing',invalid);input.setAttribute('aria-invalid',String(invalid));
        tile.querySelector('.nv-hours-hint').textContent=invalid?'Hours required before approval':'Hours confirmed';
        const issues=problems(selected,choices,hourDrafts);
        page.querySelectorAll('[data-nv-approve]').forEach(button=>button.disabled=!!(saving||sourceChanged||issues.length||!writable()));
        const info=page.querySelector('.nv-approval>div');
        info.querySelectorAll('p').forEach(p=>p.remove());
        info.insertAdjacentHTML('afterbegin',issues.length?issues.map(x=>`<p>${esc(x)}</p>`).join(''):'<p>All operations have a station and required workshop hours.</p>');
        stationGroups(selected,choices,hourDrafts).forEach(group=>{
          const total=page.querySelector(`[data-nv-drop="${group.code}"] header small`);
          if(total)total.textContent=`${group.lines.length} items · ${group.code==='SUBLET'?'Hours not required':group.hours==null?'Hours need review':group.hours.toFixed(2)+' h'}`;
        });
      });
      input.addEventListener('dragstart',event=>event.stopPropagation());
    });
    page.querySelectorAll('[data-nv-line]').forEach(tile=>tile.addEventListener('dragstart',event=>{if(saving||!writable()||sourceChanged||selected.operations.find(line=>line.line_identity===tile.dataset.nvLine)?.department==='138'){event.preventDefault();return;}event.dataTransfer.setData('text/plain',tile.dataset.nvLine);event.dataTransfer.effectAllowed='move';}));
    page.querySelectorAll('[data-nv-drop]').forEach(group=>{
      group.addEventListener('dragover',event=>{if(!saving&&writable()&&!sourceChanged){event.preventDefault();group.classList.add('nv-drop-active');}});
      group.addEventListener('dragleave',event=>{if(!group.contains(event.relatedTarget))group.classList.remove('nv-drop-active');});
      group.addEventListener('drop',event=>{event.preventDefault();group.classList.remove('nv-drop-active');if(saving||!writable()||sourceChanged)return;const id=event.dataTransfer.getData('text/plain');if(!selected.operations.some(line=>line.line_identity===id&&line.department!=='138'))return;choices[id]=group.dataset.nvDrop;requestKey='';approvalRequest=null;render();});
    });
    page.querySelectorAll('[data-nv-approve]').forEach(button=>button.addEventListener('click',()=>void approve()));
  }
  async function approve() {
    if(saving || !writable() || sourceChanged || problems(selected,choices,hourDrafts).length) return;
    const current=selected,selection={...choices},hours={...hourDrafts},actor=window.PDC_AUTH_CONTEXT.userId;
    saving=true;error='';render();
    if(!requestKey) requestKey=crypto.randomUUID();
    approvalRequest ||= {p_vehicle_id:current.vehicle_id,p_snapshot_hash:current.snapshot_hash,p_assignments:assignmentsFor(current,selection,hours),p_idempotency_key:requestKey};
    let accepted=false;
    try {
      const result=await rpc('approve_pdc_new_vehicle_review',approvalRequest);
      if(actor!==window.PDC_AUTH_CONTEXT?.userId) return;
      if(!verifyApproval(result,current,selection,hours)) throw new Error('readback_mismatch');
      accepted=true;selected=null;choices={};hourDrafts={};requestKey='';approvalRequest=null;sourceChanged=false;
      items=items.filter(row=>row.vehicle_id!==current.vehicle_id);total=Math.max(0,total-1);
      notice=`${current.stock_number} approved and added to Vehicle Locations. No workshop booking was created.`;
      // The approval receipt is already verified. Keep the intake queue usable
      // while board projections refresh; a slow refresh must not hold Saving open.
      void Promise.allSettled([refreshEmailVehicleLocations(),loadSharedNavisionVisibleRows()]);
    } catch(err) {error=accepted?'Approval saved. Refresh Vehicle Locations to see the new vehicle.':message(err);}
    finally {saving=false;render();if(accepted)void load({silent:true});}
  }
  const previousRender=renderActiveView;
  renderActiveView=function(...args){if(app.currentView==='newvehicles'){render();return;}return previousRender(...args);};
  const previousView=showView;
  showView=function(view,options){
    const out=previousView(view,options);
    if(app.currentView==='newvehicles'){document.getElementById('page-title').textContent='New Vehicles';render();void load({silent:true});}
    if(['emailreview','ai-auditor'].includes(app.currentView)){document.getElementById('nav-admin-toggle')?.classList.add('active');setAdminNavigationExpanded(true);}
    return out;
  };
  window.addEventListener('pdc-auth-ready',()=>{offset=0;void load();});
  window.addEventListener('pdc-auth-locked',()=>{generation++;items=[];total=0;unidentifiedItems=[];unidentifiedTotal=0;unidentified=false;selected=null;choices={};hourDrafts={};error='';notice='';loading=false;saving=false;approvalRequest=null;requestKey='';render();});
  const timer=setInterval(()=>{if(document.visibilityState==='visible'&&readable())void load({silent:true});},30000);
  window.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
  window.PDC_NEW_VEHICLES_VERSION='2026.09.11.positive-hours';
  window.PDC_NEW_VEHICLES=api;
  render();if(readable())void load();
  if(window.location.hash==='#/newvehicles')showView('newvehicles',{historyMode:'none'});
})();
