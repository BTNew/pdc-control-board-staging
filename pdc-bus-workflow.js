/* Department 138 workshop flow. Forecasts and supplier updates never create bookings. */
(function (root) {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const STAGES = [['yard','Yard / key allocated'],['early_sublet','Early supplier work'],['waiting_parts','Waiting for stage parts'],['mechanical','Mechanical build'],['buffer','Buffer / wheel alignment'],['electrical','Electrical'],['qa','QA / rectification'],['pit','Pit inspection'],['rustproof','Late rustproofing'],['wash','Wash'],['rft','Ready for QC / RFT check'],['delivery','Delivery / transport']];
  const SUPPLIER = [['required','Required'],['ordered','Ordered'],['vendor_completed','Vendor completed'],['technician_verified','Technician verified']];
  const LABELS = Object.fromEntries([...STAGES, ...SUPPLIER]);
  const BAY_LABELS={BUS_4X4:'Bus 4×4',TINT:'Tint',ELECTRICAL:'Electrical',FITTING:'Fitting',FABRICATION:'Fabrication',HOIST:'Hoist',TYRE:'Tyres'};
  const BOOKING_LABELS={queued:'Queued',planned:'Planned',started:'In progress',stoppage:'Stopped',completed:'Completed'};
  const ERRORS = {
    stale_workflow:'This plan changed on another screen. Refresh and review the saved plan before trying again.',
    version_conflict:'This item changed on another screen. Refresh before trying again.',
    scope_changed:'The operation changed. Refresh and check the latest description before confirming it.',
    stale_supplier_line:'The supplier item changed. Refresh and check it before continuing.',
    stage_parts_not_ready:'Confirm that the parts needed to start and progress this stage are available before allocating a production bay.',
    bus_stage_parts_required:'Confirm that the parts needed for this stage are available before allocating a production bay.',
    bus_bay_vehicle_incompatible:'Bay 3 has a height restriction and cannot take a Coaster. Select a suitable bay.',
    bus_shift_outside_hours:'This booking is outside the Bus 4×4 working hours. Check the bay calendar and use an available shift.',
    bus_supplier_verification_required:'The supplier work is still outstanding. The assigned technician must physically check and confirm it before completion.',
    not_department138:'This workflow is available for current Department 138 jobs only.',
    active_department138_required:'This workflow is available for current Department 138 jobs only.',
    permission_denied:'Your account cannot make this change.',
    assignment_changed:'This vehicle is no longer assigned to the selected technician. Refresh the job.',
    supplier_verification_required:'The assigned technician must physically check the supplier work before confirming it.',
    physical_verification_requires_assigned_started_job:'Start the vehicle’s assigned job before confirming the physical supplier check.',
    supplier_scope_changed:'This supplier item changed. Refresh and check its current description before confirming it.',
    stale_supplier:'This supplier item changed on another screen. Refresh and review the latest status.',
    supplier_evidence_required:'Add the supplier, order reference or completion evidence for this progress update.',
    readiness_evidence_required:'Record which parts were checked before confirming that the stage is ready.',
    evidence_required:'Add the confirmation or evidence for this change.',
    request_reused:'This save could not be verified. Refresh and review the plan.',
    invalid_patch:'Check the entered dates, statuses and confirmation notes.',
    invalid_request:'Check the selected vehicle, current version and supplied details.',
    invalid_stage:'Select a current and next stage from the available options.',
    invalid_milestone_status:'Select a valid QA, pit, rustproofing, wash or release-check status.',
    invalid_date:'Check the entered date and time.',
    invalid_forecasts:'Check the completion and delivery forecasts.',
    invalid_note:'Shorten the note and try again.',
  };
  const error = (code, message) => Object.assign(new Error(message || ERRORS[code] || 'The change could not be saved. Refresh and review the current job.'), {code});
  const version = value => Number.isInteger(value) && value >= 0;
  const validDate = value => typeof value === 'string' && value.trim() !== '' && Number.isFinite(Date.parse(value));
  const formatDate = value => validDate(value) ? new Date(value).toLocaleString('en-AU', {timeZone:'Australia/Perth',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}) : 'Not confirmed';
  const localDate = value => validDate(value) ? new Date(Date.parse(value) + 8 * 3600000).toISOString().slice(0,16) : '';
  function fromLocalDate(value) {
    if (!value) return null;
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw error('invalid_patch');
    const result = new Date(value + ':00+08:00').toISOString();
    if (localDate(result) !== value) throw error('invalid_patch');
    return result;
  }
  function addWeekdays(value, days, closures = []) {
    if (!validDate(value) || !Number.isInteger(days) || Math.abs(days) > 366) return null;
    const closed = new Set((Array.isArray(closures) ? closures : []).map(c => typeof c === 'string' ? c : c?.date).filter(c => /^\d{4}-\d{2}-\d{2}$/.test(c || '')));
    const d = new Date(Date.parse(value) + 8 * 3600000);
    const direction = days < 0 ? -1 : 1;
    let remaining = Math.abs(days), guard = 0;
    while (remaining > 0 && guard++ < 3660) {
      d.setUTCDate(d.getUTCDate() + direction);
      if (d.getUTCDay() !== 0 && d.getUTCDay() !== 6 && !closed.has(d.toISOString().slice(0,10))) remaining--;
    }
    if (remaining) return null;
    return new Date(d.getTime() - 8 * 3600000).toISOString();
  }
  function planningHints(plan, now = Date.now()) {
    const f = plan?.forecasts || {}, hints = [];
    const calendar = plan?.planning_calendar || {}, closures = calendar.closures || [];
    const two = addWeekdays(f.mechanical_complete, 2, closures), three = addWeekdays(f.mechanical_complete, 3, closures);
    if (two) hints.push({tone:'info',code:'buffer',text:`Allow approximately 2–3 working days after mechanical: ${formatDate(two)} to ${formatDate(three)}. Check wheel alignment, outstanding work, supplier dates and the workshop calendar.`});
    else hints.push({tone:'review',code:'mechanical_forecast',text:'Record the mechanical completion forecast to plan the buffer and electrical queue.'});
    hints.push({tone:'info',code:'qa_allowance',text:'Allow approximately 3 hours for QA per vehicle, plus any rectification. This is a planning allowance; review it against actual work and enter the vehicle-ready forecast after QA.'});
    const forecastDates = [f.mechanical_complete, f.electrical_complete, f.vehicle_ready, f.delivery, two, three].filter(validDate).map(d => localDate(d).slice(0,10));
    if (calendar.verified !== true || (calendar.verified_through && forecastDates.some(d => d > calendar.verified_through))) hints.push({tone:'review',code:'calendar_review',text:'Check the workshop calendar before promising these dates. Public holidays and workshop closures must have no production hours; dates outside the confirmed calendar need review.'});
    if (validDate(f.vehicle_ready) && !['requested','booked','passed','not_required'].includes(plan?.pit_status)) {
      const requestFrom = addWeekdays(f.vehicle_ready, -3, closures), requestBy = addWeekdays(f.vehicle_ready, -2, closures);
      const late = now > Date.parse(requestBy), due = now >= Date.parse(requestFrom);
      hints.push({tone:late ? 'risk' : due ? 'review' : 'info',code:'pit_notice',request_from:requestFrom,request_by:requestBy,text:Date.parse(f.vehicle_ready) < now ? 'Vehicle-ready forecast has passed. Confirm readiness and the pit inspection plan.' : late ? 'Pit request needs attention: fewer than 2 working days remain before the vehicle-ready forecast. Contact Ron and confirm availability.' : due ? 'Pit request due: contact Ron now, allowing 2–3 working days before the forecast completion of electrical and QA.' : `Plan the pit request between ${formatDate(requestFrom)} and ${formatDate(requestBy)} — 2–3 working days before the vehicle-ready forecast.`});
    } else if (!validDate(f.vehicle_ready) && !['passed','not_required'].includes(plan?.pit_status)) hints.push({tone:'review',code:'ready_forecast',text:'Vehicle-ready forecast required. Allow QA and rectification before arranging the pit inspection.'});
    if (validDate(f.delivery) && validDate(f.vehicle_ready) && Date.parse(f.vehicle_ready) > Date.parse(f.delivery)) hints.push({tone:'risk',code:'delivery_risk',text:'The vehicle-ready forecast is later than delivery. Review the downstream plan.'});
    if (plan?.downstream_review_required === true) hints.push({tone:'review',code:'downstream_review',text:'A forecast changed. Review electrical, QA, pit, rustproofing, wash and delivery arrangements; bookings have not moved automatically.'});
    return hints;
  }

  function createService(options) {
    let generation = 0, busy = false, pending = null;
    const context = options.context, makeId = options.uuid || (() => root.crypto.randomUUID());
    const available = (c, role = 'read') => Boolean(c?.actor && c.token && c.config?.projectRef === PROJECT
      && c.config.url?.replace(/\/$/,'') === `https://${PROJECT}.supabase.co` && c.config.workshop?.sharedData === true
      && (role === 'read' || (role === 'planner' ? ['operator','administrator'] : ['operator','administrator','fitter']).includes(c.role)));
    const capture = () => ({...context(),generation});
    function current(owner, role) { const c = context(); return owner.generation === generation && owner.actor === c?.actor && owner.token === c?.token && owner.role === c?.role && owner.config === c?.config && available(c,role); }
    async function rpc(name, params, owner, role) {
      if (!current(owner,role)) throw error('session_changed','Your sign-in changed. Refresh before continuing.');
      const abort = new AbortController(); let timer;
      try {
        const result = await Promise.race([
          (async () => {
            if (options.request) return options.request(name,params,owner,abort.signal);
            const response = await options.fetch(`${owner.config.url.replace(/\/$/,'')}/rest/v1/rpc/${name}`, {method:'POST',signal:abort.signal,headers:{apikey:owner.config.publishableKey,Authorization:`Bearer ${owner.token}`,'Content-Type':'application/json'},body:JSON.stringify(params)});
            return {ok:response.ok,status:response.status,body:await response.json()};
          })(),
          new Promise((_,reject) => { timer = setTimeout(() => { abort.abort(); reject(error('unconfirmed','The result is unconfirmed. Check or retry the same save before continuing.')); },options.timeoutMs || 25000); }),
        ]);
        if (!current(owner,role)) throw error('session_changed','Your sign-in changed. Refresh before continuing.');
        if (!result?.ok || result.body?.ok !== true) {
          if (result?.status >= 500 || result?.status === 408) throw error('unconfirmed','The result is unconfirmed. Check or retry the same save before continuing.');
          let code=result?.body?.error || result?.body?.code;
          for(const value of [result?.body?.message,result?.body?.details]){
            if(typeof value!=='string')continue;
            if(Object.hasOwn(ERRORS,value.trim()))code=value.trim();
            const found=value.match(/"error"\s*:\s*"([a-z_]+)"/);if(found&&Object.hasOwn(ERRORS,found[1]))code=found[1];
          }
          throw error(code || ([401,403].includes(result?.status)?'permission_denied':'request_failed'));
        }
        return result.body;
      } catch (e) {
        if (!current(owner,role)) throw error('session_changed','Your sign-in changed. Refresh before continuing.');
        if (e.code) throw e;
        throw error('unconfirmed','The connection was interrupted. Check or retry the same save before continuing.');
      } finally { clearTimeout(timer); }
    }
    async function command(name, params, role, retry = false) {
      if (busy) throw error('busy','A change is already being saved.');
      if (pending && !retry) throw error('unconfirmed','Check or retry the previous save before making another change.');
      const request = retry ? pending : {name,params:{...JSON.parse(JSON.stringify(params)),p_request_id:makeId()},role,owner:capture()};
      if (!request) throw error('no_retry','There is no save to retry.');
      if (!current(request.owner,request.role)) { pending = null; throw error('session_changed','Your sign-in changed. Refresh before continuing.'); }
      busy = true;
      try { const result = await rpc(request.name,request.params,request.owner,request.role); pending = null; return result; }
      catch (e) { pending = e.code === 'unconfirmed' && current(request.owner,request.role) ? request : null; throw e; }
      finally { busy = false; }
    }
    return {
      async read(vehicleId) {
        if (!UUID.test(String(vehicleId))) throw error('invalid_identity');
        const result = await rpc('get_pdc_bus_workflow',{p_vehicle_id:vehicleId},capture(),'read');
        if (result.vehicle_id !== vehicleId || !version(result.version) || !Array.isArray(result.supplier_lines)) throw error('invalid_response','The workflow could not be verified. Refresh to try again.');
        return result;
      },
      save(vehicleId,expectedVersion,patch) {
        if (!UUID.test(String(vehicleId)) || !version(expectedVersion) || !patch || Array.isArray(patch) || typeof patch !== 'object') return Promise.reject(error('invalid_patch'));
        return command('save_pdc_bus_workflow',{p_vehicle_id:vehicleId,p_expected_version:expectedVersion,p_patch:patch},'planner');
      },
      supplier(change) {
        const expectedVersion=change?.expectedVersion??change?.version;
        if (!UUID.test(String(change?.vehicleId)) || !version(expectedVersion) || !change.lineIdentity || !change.scopeHash || !SUPPLIER.some(([s])=>s===change.status)) return Promise.reject(error('invalid_identity'));
        if (change.status === 'technician_verified' && (!UUID.test(String(change.bookingId)) || !UUID.test(String(change.technicianId)))) return Promise.reject(error('supplier_verification_required'));
        if(change.status!=='required'&&!String(change.note||'').trim())return Promise.reject(error('supplier_evidence_required',change.status==='technician_verified'?'Add a brief note describing what you physically checked.':undefined));
        return command('set_pdc_bus_supplier_status',{p_vehicle_id:change.vehicleId,p_line_identity:change.lineIdentity,p_scope_hash:change.scopeHash,p_expected_version:expectedVersion,p_status:change.status,p_note:String(change.note||'').trim(),p_booking_id:change.bookingId||null,p_technician_id:change.technicianId||null},change.status==='technician_verified'?'supplier':'planner');
      },
      retry:() => command(null,null,null,true),
      invalidate() { generation++; pending=null; },
      authorityKey:() => { const c=context(); return `${generation}|${c?.actor||''}|${c?.role||''}|${c?.token||''}`; },
      canRead:() => available(context()), canPlan:() => available(context(),'planner'), canVerify:() => available(context(),'supplier'),
      get busy() {return busy;}, get retryPending() {return Boolean(pending);}, get pendingVehicleId() {return pending?.params.p_vehicle_id||'';},
    };
  }

  const supplierDrafts = new Map();
  const supplierKey = (vehicle,line,booking='') => `${vehicle}|${line.line_identity}|${line.scope_hash}|${booking}`;
  function supplierHtml(lines, options = {}) {
    if (!Array.isArray(lines) || !lines.length) return '';
    const editable = options.editable === true, controller = options.controller === true;
    const canVerify = editable && UUID.test(String(options.bookingId)) && UUID.test(String(options.technicianId));
    return `<section class="bus-supplier-list"><h3>Supplier work · physical checks</h3><p>Supplier work stays visible and uses no internal labour allowance. Vendor completion must be checked on the vehicle by the assigned technician.</p>${lines.map(line => {
      const key = supplierKey(options.vehicleId,line,options.bookingId), saved = supplierDrafts.get(key), status = line.status || 'required';
      const staleDraft=Boolean(saved&&saved.version!==line.version),disabled = editable&&!staleDraft ? '' : 'disabled';
      return `<article class="bus-supplier ${status==='technician_verified'?'is-verified':''}"><header><strong>${esc(line.description)}</strong><span class="bus-status">${esc(LABELS[status]||'Needs review')}</span></header><p>${line.supplier_phase==='late'?'Late stage · after pits, before wash / delivery':'Early supplier work · organise in the yard'} · ${esc(line.stage_code==='TINT'?'Tint':'Bus 4×4')} · Internal labour: 0 h${line.source_hours!=null?` (source: ${esc(line.source_hours)} h retained)`:''}</p>${line.note?`<p>${esc(line.note)}</p>`:''}
      ${staleDraft?'<p class="bus-warning">This supplier item changed while you were editing it. Review the latest status and discard the old draft before continuing.</p>':''}<form data-bus-supplier-form="${esc(key)}" data-bus-supplier-line="${esc(line.line_identity)}" data-bus-supplier-hash="${esc(line.scope_hash)}" data-bus-supplier-version="${esc(line.version)}" data-bus-supplier-vehicle="${esc(options.vehicleId)}" data-bus-supplier-booking="${esc(options.bookingId||'')}" data-bus-supplier-technician="${esc(options.technicianId||'')}">
      ${controller&&status!=='technician_verified'?`<label>Supplier progress<select name="status" ${disabled}>${SUPPLIER.filter(([s])=>s!=='technician_verified').map(([s,label])=>`<option value="${s}" ${(saved?.status||status)===s?'selected':''}>${label}</option>`).join('')}</select></label><label>Supplier / order / completion evidence<textarea name="note" maxlength="1000" rows="2" ${disabled}>${esc(saved?.note||'')}</textarea></label><button type="submit" ${disabled}>Save supplier progress</button>`:''}
      ${canVerify&&status!=='technician_verified'?`${controller?'':`<label>What did you physically check?<textarea name="note" maxlength="1000" rows="2" required ${disabled}>${esc(saved?.note||'')}</textarea></label>`}<label class="bus-checkbox"><input type="checkbox" name="physical_check" ${saved?.physical_check?'checked':''} ${disabled}> I physically checked this work on this vehicle and confirm it is complete.</label><button type="button" data-bus-supplier-verify ${disabled}>Confirm physical check</button>`:''}
      ${saved?'<button type="button" data-bus-supplier-discard>Discard unsaved supplier changes</button>':''}
      ${status==='technician_verified'?'<p class="bus-verified-note">✓ Physically verified. Any rework must be raised separately with the controller.</p>':!controller&&!canVerify?'<p>Start the assigned job to record the physical check. Leave unfinished work outstanding.</p>':''}
      </form></article>`;
    }).join('')}</section>`;
  }
  function bindSuppliers(host, save) {
    host?.querySelectorAll?.('[data-bus-supplier-form]').forEach(form => {
      if (form.dataset.busBound) return;
      form.dataset.busBound = 'true';
      const key=form.dataset.busSupplierForm;
      form.addEventListener('input',()=>{const data={version:Number(form.dataset.busSupplierVersion)};for(const field of form.elements)if(field.name)data[field.name]=field.type==='checkbox'?field.checked:field.value;supplierDrafts.set(key,data);});
      const submit = verified => {
        if (!form.reportValidity()) return;
        const values=new FormData(form);
        if (verified && !values.has('physical_check')) { const checkbox=form.elements.namedItem('physical_check');checkbox?.setCustomValidity('Confirm the physical check first.');checkbox?.reportValidity();return; }
        const change={vehicleId:form.dataset.busSupplierVehicle,lineIdentity:form.dataset.busSupplierLine,scopeHash:form.dataset.busSupplierHash,version:Number(form.dataset.busSupplierVersion),status:verified?'technician_verified':values.get('status'),note:String(values.get('note')||''),bookingId:form.dataset.busSupplierBooking||null,technicianId:form.dataset.busSupplierTechnician||null,draftKey:key};
        void save(change);
      };
      form.elements.namedItem('physical_check')?.addEventListener('change',event=>event.target.setCustomValidity(''));
      form.addEventListener('submit',event=>{event.preventDefault();submit(false);});
      form.querySelector('[data-bus-supplier-verify]')?.addEventListener('click',()=>submit(true));
      form.querySelector('[data-bus-supplier-discard]')?.addEventListener('click',()=>{supplierDrafts.delete(key);form.querySelectorAll('textarea').forEach(field=>{field.value='';});form.querySelectorAll('input[type="checkbox"]').forEach(field=>{field.checked=false;});const note=host.ownerDocument?.createElement('p');if(note){note.className='bus-message';note.textContent='Draft discarded. Refresh this vehicle to review its current supplier status.';form.append(note);}form.querySelectorAll('button').forEach(button=>button.disabled=true);});
    });
  }

  const select = (name,label,value,choices,disabled='') => `<label>${esc(label)}<select name="${esc(name)}" ${disabled}>${choices.map(([v,t])=>`<option value="${esc(v)}" ${String(value??'')===v?'selected':''}>${esc(t)}</option>`).join('')}</select></label>`;
  const date = (name,label,value,disabled='') => `<label>${esc(label)}<input type="datetime-local" name="${esc(name)}" value="${esc(localDate(value))}" ${disabled}></label>`;
  const textarea = (name,label,value,disabled='') => `<label>${esc(label)}<textarea name="${esc(name)}" maxlength="1000" rows="2" ${disabled}>${esc(value||'')}</textarea></label>`;
  function formPayload(form) {
    const data=new FormData(form),out={forecasts:{},parts_readiness:{}};
    for(const field of ['current_stage','next_stage','waiting_reason','qa_status','pit_status','rustproof_status','wash_status','rft_status','notes']) out[field]=String(data.get(field)||'').trim();
    for(const field of ['mechanical_complete','electrical_complete','vehicle_ready','delivery']) out.forecasts[field]=fromLocalDate(data.get('forecast_'+field));
    for(const field of ['pit_requested_at','pit_booked_at','pit_passed_at'])out[field]=fromLocalDate(data.get(field));
    if(data.has('downstream_review_acknowledged'))out.downstream_review_acknowledged=true;
    for(const stage of ['mechanical','electrical','accessory']){const raw=data.get('parts_'+stage),note=String(data.get('parts_'+stage+'_note')||'').trim();if(raw==='ready'&&!note)throw error('evidence_required','Add a parts confirmation note for each ready stage.');out.parts_readiness[stage]={ready:raw==='ready'?true:raw==='outstanding'?false:null,note};}
    return out;
  }
  function panelHtml(plan,{identity='',editable=false,busy=false,message='',dirty=false,stale=false,retry=false}={}) {
    const disabled=!editable||busy||stale||retry?'disabled':'', f=plan.forecasts||{}, readiness=plan.parts_readiness||{}, bookings=plan.bookings||[];
    const active=bookings.filter(b=>['started','stoppage'].includes(b.status));
    const current=active.length?active:bookings.filter(b=>b.status==='planned'||b.status==='queued');
    const statusChoices=[['required','Required'],['in_progress','In progress'],['completed','Completed']];
    const hints=planningHints(plan);
    return `<section class="bus-workflow" aria-label="Bus 4x4 workshop flow"><header class="bus-workflow-header"><div><p class="bus-eyebrow">Department 138</p><h3>Workshop flow · ${esc(identity||plan.stock_number||'Selected vehicle')}</h3><p>Plan ahead around parts, supplier work and the next available bay.</p></div><button type="button" data-bus-refresh ${busy?'disabled':''}>Refresh saved plan</button></header>
    <div class="bus-flow-path">${STAGES.map(([s,label])=>`<span class="${plan.current_stage===s?'is-current':''}">${esc(label)}</span>`).join('')}</div>
    ${message?`<p class="bus-message" role="status">${esc(message)}</p>`:''}${dirty?'<p class="bus-unsaved">Unsaved changes remain on this screen.</p>':''}${retry?'<p class="bus-warning">Save outcome unconfirmed. Check the same request before continuing.</p><button type="button" data-bus-retry>Check / retry last save</button>':''}
    <div class="bus-current">${current.length?current.map(b=>`<span><strong>${esc(b.stage_name||BAY_LABELS[b.stage_code]||'Workshop')} · ${b.bay_number!=null?'Bay '+esc(b.bay_number):'Unallocated'}</strong> ${esc(b.technician_name||b.assignee_name||'Technician not confirmed')} · ${esc(BOOKING_LABELS[b.status]||'Status needs review')}</span>`).join(''):'<span>No current or planned bay allocation recorded.</span>'}</div>
    <ul class="bus-hints">${hints.map(h=>`<li class="is-${h.tone}">${esc(h.text)}</li>`).join('')}${(plan.warnings||[]).map(w=>`<li class="is-review">${esc(typeof w==='string'?w:w.message||w.code||'Review required')}</li>`).join('')}</ul>
    <form data-bus-plan-form><div class="bus-fields">${select('current_stage','Current stage',plan.current_stage||'', [['','Not recorded'],...STAGES],disabled)}${select('next_stage','Next planned stage',plan.next_stage||'', [['','Not confirmed'],...STAGES],disabled)}${textarea('waiting_reason','Waiting reason / outstanding dependency',plan.waiting_reason,disabled)}</div>
    <details open class="bus-section"><summary>Stage parts readiness — required before production allocation</summary><p>Confirm the parts needed to start and reasonably progress the specific stage. An imported green parts flag does not make this confirmation.</p><div class="bus-fields">${['mechanical','electrical','accessory'].map(stage=>{const p=readiness[stage]||{};return `<div>${select('parts_'+stage,stage[0].toUpperCase()+stage.slice(1)+' parts',p.ready===true?'ready':p.ready===false?'outstanding':'unknown',[['unknown','Needs checking'],['outstanding','Parts outstanding'],['ready','Confirmed available for this stage']],disabled)}${textarea('parts_'+stage+'_note','What was checked / parts still needed',p.note,disabled)}${p.confirmed_at?`<small>Last confirmed ${esc(formatDate(p.confirmed_at))}</small>`:''}</div>`;}).join('')}</div></details>
    <details class="bus-section" open><summary>Forecasts and downstream planning</summary><div class="bus-fields">${date('forecast_mechanical_complete','Mechanical completion forecast (Perth)',f.mechanical_complete,disabled)}${date('forecast_electrical_complete','Electrical completion forecast (Perth)',f.electrical_complete,disabled)}${date('forecast_vehicle_ready','Vehicle ready for pit — after QA (Perth)',f.vehicle_ready,disabled)}${date('forecast_delivery','Confirmed delivery / transport (Perth)',f.delivery,disabled)}</div><p class="bus-help">Allow approximately 3 hours for QA, plus any rectification. The mechanical buffer and pit notice use 2–3 working days, skipping weekends and recorded public holidays/closures. Forecast changes require a downstream review and do not move bookings.</p>${plan.downstream_review_required===true?`<label class="bus-checkbox"><input type="checkbox" name="downstream_review_acknowledged" ${disabled}> I reviewed the downstream electrical, QA, pit, rustproofing, wash and delivery arrangements against the saved forecasts.</label><p class="bus-help">Save changed forecasts first, then confirm the downstream review. Existing bookings remain unchanged.</p>`:''}</details>
    <details class="bus-section"><summary>QA, pit inspection and final delivery</summary><div class="bus-fields">${select('qa_status','QA / rectification',plan.qa_status||'required',statusChoices,disabled)}${select('pit_status','Pit inspection',plan.pit_status||'required',[['not_required','Not required'],['required','Required'],['requested','Requested — awaiting booking'],['booked','Booking confirmed'],['passed','Passed — result confirmed']],disabled)}${date('pit_requested_at','Pit request sent (Perth)',plan.pit_requested_at,disabled)}${date('pit_booked_at','Confirmed pit appointment (Perth)',plan.pit_booked_at,disabled)}${date('pit_passed_at','Pit passed (Perth)',plan.pit_passed_at,disabled)}${select('rustproof_status','Late rustproofing',plan.rustproof_status||'not_required',[['not_required','Not required'],...SUPPLIER.filter(([s])=>s!=='technician_verified')],disabled)}${select('wash_status','Wash',plan.wash_status||'not_required',[['not_required','Not required'],['required','Required'],['requested','Requested'],['completed','Completed']],disabled)}${select('rft_status','Ready for release checks',plan.rft_status||'not_ready',[['not_ready','Not ready'],['ready_for_qc_check','Ready for existing QC / RFT checks']],disabled)}</div><p class="bus-help">Only record confirmed requests, bookings and results. Pit passed → rustproofing → wash → QC / RFT → delivery. This plan does not certify release or bypass the conversion and QC checklists.</p></details>
    ${textarea('notes','Controller planning notes / reason for changed forecasts',plan.notes,disabled)}<div class="bus-save"><button type="submit" ${disabled}>${busy?'Saving…':'Save workshop flow'}</button><small>Dates and supplier statuses are records of confirmed arrangements. Saving sends no email and creates no booking.</small></div></form>
    ${supplierHtml(plan.supplier_lines,{vehicleId:plan.vehicle_id,editable:editable&&!busy&&!stale&&!retry,controller:true})}</section>`;
  }

  function createPanel(options) {
    const service=options.service;let host=options.host,vehicleId='',identity='',plan=null,loading=false,saving=false,message='',draft=null,stale=false,sequence=0,owner=service.authorityKey(),retryKind='',retryDraftKey='';
    const ownerCurrent=()=>owner===service.authorityKey();
    function clear() { sequence++;plan=null;vehicleId='';identity='';draft=null;stale=false;message='';loading=false;saving=false;retryKind='';retryDraftKey=''; }
    function render() {
      if(!host)return;
      if(!ownerCurrent()){clear();owner=service.authorityKey();}
      if(!vehicleId){host.innerHTML='<section class="bus-workflow bus-empty"><h3>Bus 4×4 workshop flow</h3><p>Select a vehicle or planned job to confirm stage parts readiness, supplier work and the next steps.</p></section>';return;}
      if(!plan){host.innerHTML=`<section class="bus-workflow"><h3>Bus 4×4 workshop flow · ${esc(identity)}</h3><p role="status">${esc(message||(loading?'Loading the saved workflow…':'The workflow is unavailable.'))}</p>${!loading?'<button data-bus-refresh type="button">Try again</button>':''}</section>`;host.querySelector('[data-bus-refresh]')?.addEventListener('click',()=>refresh());return;}
      host.innerHTML=panelHtml(plan,{identity,editable:service.canPlan(),busy:saving||loading,message,dirty:Boolean(draft),stale,retry:service.retryPending});
      const form=host.querySelector('[data-bus-plan-form]');
      if(draft)for(const[name,value]of Object.entries(draft)){const field=form.elements.namedItem(name);if(field){if(field.type==='checkbox')field.checked=value;else field.value=value;}}
      form.addEventListener('input',()=>{draft={};for(const field of form.elements)if(field.name)draft[field.name]=field.type==='checkbox'?field.checked:field.value;const save=host.querySelector('.bus-save small');if(save)save.textContent='Unsaved changes. Save workshop flow when ready.';});
      form.addEventListener('submit',event=>{event.preventDefault();if(!form.reportValidity()||stale||saving||loading)return;let patch;try{patch=formPayload(form);}catch(e){message=e.message;render();return;}void mutate(()=>service.save(vehicleId,plan.version,patch),'plan');});
      host.querySelector('[data-bus-refresh]')?.addEventListener('click',()=>{if(draft&&!root.confirm('Discard your unsaved workflow changes and reload the saved plan?'))return;draft=null;stale=false;void refresh();});
      host.querySelector('[data-bus-retry]')?.addEventListener('click',()=>mutate(()=>service.retry(),retryKind||'retry',retryDraftKey));
      bindSuppliers(host,change=>mutate(()=>service.supplier(change),'supplier',change.draftKey));
    }
    async function refresh() {
      if(!vehicleId||saving)return;
      const target=vehicleId,ticket=++sequence;loading=true;render();
      try{const saved=await service.read(target);if(ticket!==sequence||target!==vehicleId||!ownerCurrent())return;if(draft&&plan&&saved.version!==plan.version){stale=true;message='The saved plan has changed. Your unsaved edits are retained; reload the saved plan before continuing.';}plan=saved;}
      catch(e){if(ticket!==sequence||!ownerCurrent())return;message=e.message;stale=true;}
      finally{if(ticket===sequence){loading=false;render();}}
    }
    async function mutate(action,kind,key) {
      if(saving||loading||!ownerCurrent())return;
      const target=vehicleId,ticket=sequence;saving=true;message='';render();
      try{await action();if(ticket!==sequence||target!==vehicleId||!ownerCurrent())return;if(kind==='plan')draft=null;if(key)supplierDrafts.delete(key);retryKind='';retryDraftKey='';message='Saved. Checking the current workshop record…';stale=false;saving=false;await refresh();if(target!==vehicleId||!ownerCurrent())return;if(!stale)message='Workshop update saved and checked.';options.onSaved?.();}
      catch(e){if(ticket!==sequence||!ownerCurrent())return;message=e.message;if(e.code==='unconfirmed'){retryKind=kind;retryDraftKey=key||'';}if(['stale_workflow','version_conflict','scope_changed','stale_supplier_line','stale_supplier','supplier_scope_changed'].includes(e.code))stale=true;}
      finally{if(ticket===sequence||target===vehicleId){saving=false;render();}}
    }
    return {
      async choose(id,label='') {
        if(!ownerCurrent()){clear();owner=service.authorityKey();}
        if(id===vehicleId){identity=label||identity;render();return true;}
        if((draft||service.retryPending||saving)&&vehicleId){message='Save or discard the current workflow changes before opening another vehicle.';render();return false;}
        sequence++;vehicleId=UUID.test(String(id))?id:'';identity=label;plan=null;draft=null;stale=false;message='';render();if(vehicleId)await refresh();return true;
      },
      setHost(value){host=value;render();},refresh,
      invalidate(){service.invalidate();clear();supplierDrafts.clear();owner=service.authorityKey();render();},
      hasDrafts:()=>Boolean(draft),get vehicleId(){return vehicleId;},
    };
  }
  let defaultService=null,plannerPanel=null;
  function service() {
    if(!defaultService)defaultService=createService({context:()=>({actor:root.PDC_AUTH_CONTEXT?.userId,role:root.PDC_AUTH_CONTEXT?.role,token:typeof getPdcSupabaseAccessToken==='function'?getPdcSupabaseAccessToken():'',config:root.PDC_SUPABASE_CONFIG}),fetch:(...args)=>root.fetch(...args),uuid:()=>root.crypto.randomUUID()});
    return defaultService;
  }
  function mountPlanner({host,vehicleId,identity='',stageCode}={}) {
    if(!host)return;
    if(stageCode!=='BUS_4X4'){host.innerHTML='';return;}
    if(!plannerPanel)plannerPanel=createPanel({host,service:service()});else plannerPanel.setHost(host);
    void plannerPanel.choose(vehicleId,typeof identity==='string'?identity:identity?.stock||identity?.stock_number||'');
  }
  const api={createService,service,createPanel,mountPlanner,panelHtml,formPayload,supplierHtml,bindSuppliers,planningHints,addWeekdays,fromLocalDate,localDate,formatDate,
    confirmSupplierSave:key=>supplierDrafts.delete(key),hasDrafts:()=>supplierDrafts.size>0||Boolean(plannerPanel?.hasDrafts()),
    reset(){defaultService?.invalidate();plannerPanel?.invalidate();supplierDrafts.clear();},esc,STAGES,SUPPLIER};
  if(typeof module!=='undefined'&&module.exports){module.exports=api;return;}
  root.PdcBusWorkflow=api;
  root.addEventListener('beforeunload',event=>{if(api.hasDrafts()||defaultService?.busy||defaultService?.retryPending){event.preventDefault();event.returnValue='';}});
})(typeof window==='undefined'?globalThis:window);
