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
      stage_code: choices[line.line_identity] ?? (validStation(line.stage_code) ? line.stage_code : line.department === '138' ? 'BUS_4X4' : ''),
      ...(hours && ((choices[line.line_identity] ?? line.stage_code) !== 'SUBLET') ? {estimated_hours:positiveHours(hoursFor(line,hours))?Number(hoursFor(line,hours)):null} : {})}));
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
  function reviewOrder(row, choices = {}, drafts = {}) {
    const stages=new Map(assignmentsFor(row,choices).map(x=>[x.line_identity,x.stage_code]));
    const priority=line=>stages.get(line.line_identity)!=='SUBLET'&&!positiveHours(hoursFor(line,drafts))?0:1;
    return [...(row?.operations||[])].sort((a,b)=>priority(a)-priority(b));
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
  function updateProblems(row, draft={}) {
    const stage=draft.stage ?? row.current_work?.stage_code ?? row.proposed?.proposed_station;
    const hours=draft.hours ?? row.effective_hours;
    const issues=[];
    if(!validStation(stage)) issues.push('Choose a workshop station.');
    if(stage!=='SUBLET'&&!positiveHours(hours)) issues.push('Enter positive workshop hours.');
    if(row.current_work?.completed) issues.push('This operation is completed. Review rework before changing it.');
    if(row.status!=='pending'||!row.already_on_board) issues.push('Refresh this vehicle before approving.');
    return issues;
  }
  function operationUpdateHtml(row,draft={},canApprove=true,busy=false) {
    const stage=draft.stage ?? row.current_work?.stage_code ?? row.proposed?.proposed_station;
    const hours=draft.hours ?? row.effective_hours;
    const issues=updateProblems(row,draft);
    return `<article class="nv-update-card" data-operation-change="${esc(row.change_id)}"><header><h3>${esc(row.stock_number)} · ${row.change_kind==='added'?'Added operation':'Changed operation'}</h3><span>Already on board · ${esc(row.current_location)}</span></header>
    <p>${esc(row.customer_name)} · Job ${esc(row.job_number)} · Line ${esc(row.line_number)}${row.company?' · '+esc(row.company):''}${row.division?' / '+esc(row.division):''}</p>
    <div class="nv-update-compare"><section><h4>Previously accepted Tune line</h4><p>${row.change_kind==='added'?'New line — not on this vehicle yet':esc(row.before?.operation_description)}</p><small>${row.change_kind==='added'?'':esc(row.before?.source_estimated_hours??'Not supplied')+' source hours'}</small></section>
    <section><h4>Latest Tune line</h4><p>${esc(row.proposed?.operation_description)}</p><small>${esc(row.proposed?.source_estimated_hours??'Not supplied')} source hours</small></section></div>
    ${row.current_work?`<p>Current workshop plan: ${esc(row.current_work.stage_code)} · ${esc(row.current_work.estimated_hours)} hours${row.current_work.completed?' · Completed':''}</p>`:''}
    <p><small>Imported ${esc(new Date(row.received_at).toLocaleString('en-AU',{timeZone:'Australia/Perth'}))} (Perth)</small></p>
    <div class="nv-update-controls"><label>Workshop <select data-update-stage ${busy||!canApprove?'disabled':''}><option value="">Choose station</option>${STATIONS.map(([code,label])=>`<option value="${code}" ${code===stage?'selected':''}>${esc(label)}</option>`).join('')}</select></label>
    <label>Approved hours <input data-update-hours type="number" min="0.01" max="999.99" step="0.01" value="${esc(hours??'')}" ${busy||!canApprove||stage==='SUBLET'?'disabled':''}></label>
    <button type="button" class="primary" data-approve-update ${issues.length||!canApprove||busy?'disabled':''}>${busy?'Saving…':'Approve operation change'}</button></div>
    <p class="nv-update-issues">${issues.map(esc).join(' ')}</p><small>Existing bookings, completed work and vehicle location are kept. Review affected booking times after approval.</small></article>`;
  }

  const api={reviewOrder,updateProblems,operationUpdateHtml,STATIONS,reviewChoices,assignmentsFor,problems,stationGroups,verifyApproval,positiveHours,hoursFor,esc};
  if(typeof module!=='undefined' && module.exports) module.exports=api;
  if(typeof window==='undefined' || window.PDC_SUPABASE_CONFIG?.projectRef!==PROJECT
      || typeof showView!=='function' || window.PDC_NEW_VEHICLES_VERSION) return;

  let items=[],total=0,offset=0,selected=null,choices={},loading=false,saving=false,error='',notice='',sourceChanged=false;
  let updateItems=[],updateTotal=0,updateOffset=0,updateError='',updateDrafts={},updateRequests={};
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
    if(/completed|protected|rework/.test(code)) return 'This work or vehicle is protected by completion history. Review rework before applying this change.';
    if(/long_description/.test(code)) return 'Review this long description in vehicle details before applying the update.';
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
      if(!unidentified) {
        try {
          const changes=await rpc('list_pdc_tune_operation_changes',{p_offset:updateOffset,p_limit:50});
          if(stamp!==generation) return;
          updateItems=changes.data.items;updateTotal=changes.data.total;updateError='';
        } catch(err) {updateError='Updated operation lines could not be loaded. Refresh to retry.';}
      }
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
    const sublet=assigned==='SUBLET';
    const value=hoursFor(line,hourDrafts),missing=!sublet&&!positiveHours(value);
    const standard=line.hours_provenance==='craig_standard_pre_delivery_1_hour';
    const disabled=!writable()||saving||sourceChanged;
    const provenance=line.hours_provenance==='craig_electrical_default_1_5_hours'?'Electrical default · 1.5 hours':line.hours_provenance==='explicit_description_time'?'Estimate stated in description':line.hours_provenance==='conflicting_description_times'?'Conflicting times — enter an estimate':'';
    const hint=sublet?'Hours not required':missing?'Hours required before approval':standard?'Pre-delivery · 1 hour standard':Object.hasOwn(hourDrafts,line.line_identity)?'Your estimate':provenance||'Hours confirmed';
    return `<article class="nv-operation nv-operation-row ${missing?'nv-hours-missing':''}" draggable="${!disabled}" data-nv-line="${esc(line.line_identity)}">
      <small class="nv-line-meta" title="Drag to a station · ${line.department?`Dept ${esc(line.department)} · `:''}${line.original_line_number!=null?'Line '+esc(line.original_line_number):esc(line.operation_no)}${line.job_card_number?' · '+esc(line.job_card_number):''}"><span aria-hidden="true">⠿</span><span class="nv-source-line">${esc(line.original_line_number??line.operation_no??'—')}</span></small>
      <strong>${esc(line.description)}</strong>
      <div class="nv-operation-controls">
      ${sublet?'':`<label class="nv-hours-label">Hours<input type="number" min="0.01" max="999.99" step="0.01" inputmode="decimal" aria-label="Hours for ${esc(line.description)}" aria-invalid="${missing}" data-nv-hours="${esc(line.line_identity)}" value="${esc(value??'')}" placeholder="—" ${standard?'readonly':''} ${disabled?'disabled':''}></label>`}
      <small class="nv-hours-hint">${esc(hint)}</small>
      <label class="nv-station-choice">Station<select data-nv-stage="${esc(line.line_identity)}" aria-label="Station for ${esc(line.description)}" ${disabled?'disabled':''}><option value="">Needs Review</option>${STATIONS.map(([code,label])=>`<option value="${code}" ${code===assigned?'selected':''}>${esc(label)}</option>`).join('')}</select></label></div></article>`;
  }
  function stationSection(group) {
    const theme=group.code&&typeof vehicleWorkshopStationPresentation==='function'?vehicleWorkshopStationPresentation(group.code):null;
    const style=theme?` style="--station-colour:${esc(theme.colour)};--station-tint:${esc(theme.tint)}"`:'';
    return `<section class="nv-station nv-bucket ${group.code?'':'needs-review'}" data-nv-drop="${group.code}"${style}><header><h3>${esc(group.label)}</h3><small>${group.lines.length} items · ${group.code==='SUBLET'?'Hours not required':group.hours==null?'Hours need review':`${group.hours.toFixed(2)} h`}</small></header><p class="nv-drop-hint">Drop here</p></section>`;
  }
  async function approveUpdate(id) {
    const row=updateItems.find(x=>x.change_id===id),draft=updateDrafts[id]||{},actor=window.PDC_AUTH_CONTEXT?.userId;
    if(saving||!writable()||!row||updateProblems(row,draft).length) return;
    const stage=draft.stage ?? row.current_work?.stage_code ?? row.proposed.proposed_station;
    const hours=stage==='SUBLET'?null:Number(draft.hours??row.effective_hours);
    const identity=JSON.stringify([row.snapshot_hash,stage,hours]);
    if(updateRequests[id]?.identity!==identity) updateRequests[id]={identity,key:crypto.randomUUID()};
    const request={p_change_id:id,p_snapshot_hash:row.snapshot_hash,p_stage_code:stage,p_estimated_hours:hours,p_idempotency_key:updateRequests[id].key};
    saving=true;error='';render();
    try {
      const result=await rpc('approve_pdc_tune_operation_change',request);
      if(actor!==window.PDC_AUTH_CONTEXT?.userId) return;
      const data=result.data;
      if(data?.change_id!==id||data?.vehicle_id!==row.vehicle_id||data?.bookings_changed!==false||data?.location_changed!==false
        ||data?.operation?.description!==row.proposed.operation_description||data?.operation?.stage_code!==stage
        ||(stage!=='SUBLET'&&Number(data?.operation?.estimated_hours)!==hours)||data?.operation?.completed!==false) throw new Error('readback_mismatch');
      updateItems=updateItems.filter(x=>x.change_id!==id);updateTotal=Math.max(0,updateTotal-1);delete updateDrafts[id];delete updateRequests[id];
      notice=`${row.stock_number}: operation change approved. Existing bookings and location were kept; review affected booking times.`;
      void Promise.allSettled([refreshEmailVehicleLocations(),loadSharedNavisionVisibleRows()]);
    } catch(err) {error=message(err);}
    finally {saving=false;render();void load({silent:true});}
  }
  function bindUpdates() {
    page.querySelectorAll('[data-operation-change]').forEach(card=>{
      const id=card.dataset.operationChange;
      card.querySelector('[data-update-stage]').addEventListener('change',event=>{updateDrafts[id]={...updateDrafts[id],stage:event.target.value};delete updateRequests[id];render();});
      card.querySelector('[data-update-hours]').addEventListener('input',event=>{
        updateDrafts[id]={...updateDrafts[id],hours:event.target.value};delete updateRequests[id];
        const issues=updateProblems(updateItems.find(x=>x.change_id===id),updateDrafts[id]);
        card.querySelector('[data-approve-update]').disabled=saving||!writable()||issues.length>0;
        card.querySelector('.nv-update-issues').textContent=issues.join(' ');
      });
      card.querySelector('[data-approve-update]').addEventListener('click',()=>void approveUpdate(id));
    });
    page.querySelectorAll('[data-update-page]').forEach(button=>button.addEventListener('click',()=>{updateOffset=Math.max(0,updateOffset+Number(button.dataset.updatePage)*50);void load();}));
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
      <p class="nv-help">Read each description, then drag the row into a station bucket or choose its station below. Items needing hours appear first. Sublet does not require hours. Your choices and hours are saved when you approve.</p>
      <div class="nv-routing-buckets" aria-label="Drag operations into station buckets">${groups.map(group=>stationSection(group)).join('')}</div>
      <div class="nv-operation-list" aria-label="Operation descriptions and estimates">${reviewOrder(selected,choices,hourDrafts).map(operation).join('')}</div>
      <footer class="nv-approval"><div>${issues.length?issues.map(issue=>`<p>${esc(issue)}</p>`).join(''):'<p>All operations have a station and required workshop hours.</p>'}<small>Approval adds this vehicle to its current location on the board. Nothing is booked or marked fitted.</small></div>
      ${approvalButton()}</footer>`:
      `<div class="nv-list">${items.map(card).join('') || `<div class="nv-empty"><h3>${loading?'Loading Job Cards…':error?'Queue unavailable':'No new vehicles waiting'}</h3><p>New report vehicles appear here after import processing. Existing board vehicles are not reset or pulled back into this queue.</p></div>`}</div>
      <div class="nv-pagination"><button data-nv-page="-1" ${offset===0||loading?'disabled':''}>Previous</button><span>${total?`${offset+1}–${Math.min(offset+items.length,total)} of ${total}`:'0 awaiting review'}</span><button data-nv-page="1" ${offset+items.length>=total||loading?'disabled':''}>Next</button></div>`}`;
    if(!selected) {
      page.insertAdjacentHTML('beforeend',`<section class="nv-operation-updates" aria-label="Updated operation lines"><h2>Updated operation lines</h2><p>${updateTotal} changes awaiting approval for vehicles already on the board.</p>${updateError?`<p role="alert">${esc(updateError)}</p>`:''}${updateItems.map(row=>operationUpdateHtml(row,updateDrafts[row.change_id]||{},writable(),saving)).join('')||'<p>No updated operation lines waiting.</p>'}<div class="nv-pagination"><button data-update-page="-1" ${updateOffset===0||loading||saving?'disabled':''}>Previous changes</button><span>${updateTotal} changes</span><button data-update-page="1" ${updateOffset+updateItems.length>=updateTotal||loading||saving?'disabled':''}>Next changes</button></div></section>`);
      bindUpdates();
    }
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
    page.querySelectorAll('[data-nv-stage]').forEach(select=>{
      select.addEventListener('change',()=>{if(saving||!writable()||sourceChanged)return;choices[select.dataset.nvStage]=select.value;requestKey='';approvalRequest=null;render();});
      select.addEventListener('dragstart',event=>event.stopPropagation());
    });
    page.querySelectorAll('[data-nv-line]').forEach(tile=>tile.addEventListener('dragstart',event=>{if(saving||!writable()||sourceChanged){event.preventDefault();return;}event.dataTransfer.setData('text/plain',tile.dataset.nvLine);event.dataTransfer.effectAllowed='move';}));
    page.querySelectorAll('[data-nv-drop]').forEach(group=>{
      group.addEventListener('dragover',event=>{if(!saving&&writable()&&!sourceChanged){event.preventDefault();group.classList.add('nv-drop-active');}});
      group.addEventListener('dragleave',event=>{if(!group.contains(event.relatedTarget))group.classList.remove('nv-drop-active');});
      group.addEventListener('drop',event=>{event.preventDefault();group.classList.remove('nv-drop-active');if(saving||!writable()||sourceChanged)return;const id=event.dataTransfer.getData('text/plain');if(!selected.operations.some(line=>line.line_identity===id))return;choices[id]=group.dataset.nvDrop;requestKey='';approvalRequest=null;render();});
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
  window.addEventListener('pdc-auth-locked',()=>{generation++;items=[];total=0;updateItems=[];updateTotal=0;updateOffset=0;updateDrafts={};updateRequests={};updateError='';unidentifiedItems=[];unidentifiedTotal=0;unidentified=false;selected=null;choices={};hourDrafts={};error='';notice='';loading=false;saving=false;approvalRequest=null;requestKey='';render();});
  const timer=setInterval(()=>{if(document.visibilityState==='visible'&&readable())void load({silent:true});},30000);
  window.addEventListener('pagehide',()=>clearInterval(timer),{once:true});
  window.PDC_NEW_VEHICLES_VERSION='2026.09.12.compact-review';
  window.PDC_NEW_VEHICLES=api;
  render();if(readable())void load();
  if(window.location.hash==='#/newvehicles')showView('newvehicles',{historyMode:'none'});
})();
