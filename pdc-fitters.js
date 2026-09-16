/* Fitter workflow. The database is the authority for assignments, lifecycle and progress. */
(function (root) {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const errors = {
    version_conflict:'This job changed on another screen. Refresh, review the latest items and try again.',
    scope_changed:'The operation list or hours changed. Refresh and review the updated items.',
    assignment_changed:'This job is no longer assigned to this mechanic. Refresh the job list.',
    job_not_running:'Start or resume this job before recording work.',
    items_incomplete:'Complete every item in this bay before finishing the job. Missing hours need controller review.',
    line_unavailable:'That item is no longer available in this bay. Refresh the job.',
    mechanic_unavailable:'This mechanic is inactive or unavailable. Select another mechanic.',
    reason_required:'Enter a reason for the stoppage.',
    vehicle_overlap:'This vehicle is working in another bay. Ask the controller to check its bookings.',
    bay_overlap:'This bay has another job in progress. Ask the controller to check its bookings.',
    not_startable:'This booking cannot be started in its current state. Refresh the job.',
    request_reused:'This action could not be verified. Refresh before making another change.',
  };
  function progressHtml(progress, compact = false) {
    const p = Math.max(0, Math.min(100, Number(progress?.percent) || 0));
    const label = `${p}% work completed${progress ? ` · ${Number(progress.completed_hours) || 0} of ${Number(progress.total_hours) || 0} h` : ''}`;
    return `<span class="fitter-progress${compact ? ' is-compact' : ''}" role="progressbar" aria-label="Work completed by fitter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${p}" title="${esc(label)}"><span style="width:${p}%"></span>${compact ? '' : `<b>${esc(label)}</b>`}</span>`;
  }
  function createService(options) {
    let generation = 0, busy = false, retry = null;
    const error = (message, code) => Object.assign(Error(message), { code });
    const available = (c, write) => Boolean(c?.actor && c.token && c.config?.projectRef === PROJECT
      && c.config.url?.replace(/\/$/, '') === `https://${PROJECT}.supabase.co`
      && c.config.workshop?.sharedData === true
      && (!write || ['operator','administrator'].includes(c.role)));
    function current(owner, write) {
      const c = options.context();
      return owner.generation === generation && owner.actor === c.actor && owner.token === c.token
        && owner.config === c.config && available(c, write);
    }
    async function rpc(name, body, write, owner) {
      owner = owner || { ...options.context(), generation };
      if (!current(owner, write)) throw error('Sign in with an approved staff account to continue.', 'session_changed');
      const abort = new AbortController();
      let timer;
      try {
        const result = await Promise.race([
          options.fetch(`${owner.config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
            method:'POST', signal:abort.signal,
            headers:{ apikey:owner.config.publishableKey, Authorization:`Bearer ${owner.token}`, 'Content-Type':'application/json' },
            body:JSON.stringify(body),
          }).then(async response => ({ ok:response.ok, body:await response.json() })),
          new Promise((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(error('Connection lost. Refresh to check the job, or retry the same action.', 'unconfirmed')); }, options.timeoutMs || 25000); }),
        ]);
        if (!current(owner, write)) throw error('Your sign-in changed. Refresh before continuing.', 'session_changed');
        if (!result.ok || result.body?.ok !== true) {
          const code = result.body?.error || result.body?.code || 'rejected';
          throw error(errors[code] || 'The workshop could not save this change. Refresh and ask the controller to check the booking if it continues.', code);
        }
        return result.body;
      } catch (e) {
        if (e.code) throw e;
        throw error('Connection lost. The result is unconfirmed; refresh or retry the same action.', 'unconfirmed');
      } finally { clearTimeout(timer); }
    }
    async function command(body, isRetry = false) {
      if (busy) throw error('A change is already being saved.', 'busy');
      if (retry && !isRetry) throw error('Check or retry the previous action first.', 'unconfirmed');
      const request = isRetry ? retry : { body:{ ...body, p_request_id:options.uuid() }, owner:{ ...options.context(), generation } };
      if (!request) throw error('There is no action to retry.', 'no_retry');
      busy = true;
      try {
        const result = await rpc('fitter_job_command', request.body, true, request.owner);
        retry = null;
        return result;
      } catch (e) {
        retry = e.code === 'unconfirmed' && current(request.owner, true) ? request : null;
        throw e;
      } finally { busy = false; }
    }
    return {
      roster:() => rpc('get_fitter_roster', {}, false),
      jobs:id => rpc('get_fitter_jobs', {p_technician_id:id}, false),
      job:(id, booking) => rpc('get_fitter_job', {p_technician_id:id,p_booking_id:booking}, false),
      command, retry:() => command(null, true),
      invalidate() { generation++; retry = null; },
      get busy() { return busy; }, get retryPending() { return Boolean(retry); },
      canWrite:() => available(options.context(), true),
    };
  }
  const api = { createService, progressHtml, esc };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  root.PdcFitters = api;
  const doc = root.document;
  const service = createService({
    context:() => ({ actor:root.PDC_AUTH_CONTEXT?.userId, role:root.PDC_AUTH_CONTEXT?.role,
      token:typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '', config:root.PDC_SUPABASE_CONFIG }),
    fetch:(...args) => root.fetch(...args), uuid:() => root.crypto.randomUUID(),
  });
  let roster = [], mechanic = '', jobs = [], bays = [], selected = '', detail = null;
  let loading = false, connected = false, message = '', loadGeneration = 0, initialized = false, lastSync = 0;
  let stopOpen = false, stopReason = '', stopType = 'Parts', saving = false, pendingDraftKey = '';
  const drafts = new Map();
  const active = () => doc.body?.dataset.currentView === 'fitters';
  const host = () => doc.getElementById('fitters-host');
  const time = value => value ? new Date(value).toLocaleString('en-AU', {timeZone:'Australia/Perth',weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}) : 'Not scheduled';
  const state = value => ({started:'In progress',stoppage:'Stopped',planned:'Planned',queued:'Queued',completed:'Completed'}[value] || value);
  function jobCard(job, index) {
    const heading = job.status === 'started' ? 'On now' : job.status === 'stoppage' ? 'Stoppage' : index === 0 ? 'Next to start' : index === 1 ? 'Next job' : index === 2 ? 'Following job' : 'Later';
    return `<button type="button" class="fitter-job${selected === job.id ? ' is-selected' : ''}" data-fitter-job="${esc(job.id)}" ${saving || loading || service.retryPending ? 'disabled' : ''}><span class="fitter-kicker">${heading} · ${esc(job.stage_name)} / Bay ${esc(job.bay_number ?? '—')}</span><strong>${esc(job.stock || 'Stock not recorded')}</strong><span>${esc(job.customer || 'Customer not recorded')}</span><span>${esc(job.vehicle || 'Vehicle details pending')}</span><small>${esc(time(job.start_at))}</small>${progressHtml(job.progress, true)}</button>`;
  }
  function lineCard(line, index, editable) {
    const draft = drafts.get(`${selected}:${line.line_identity}`), note = draft?.note ?? line.note;
    const disabled = !editable || saving || loading || service.retryPending;
    return `<article class="fitter-line${line.completed ? ' is-done' : ''}"><label class="fitter-line-check"><input type="checkbox" data-fitter-line="${esc(line.line_identity)}" ${line.completed ? 'checked' : ''} ${disabled ? 'disabled' : ''}><span><strong>${esc(line.description)}</strong><small>${esc(line.stage_code.replaceAll('_',' '))} · ${line.hours == null ? 'Hours need review' : `${esc(line.hours)} h`}${line.completed ? ' · Work completed' : ''}</small></span></label>
      ${line.scope_changed ? '<p class="fitter-warning">This item changed. Review the work before ticking it again.</p>' : ''}
      ${line.source_note ? `<p class="fitter-source-note">${esc(line.source_note)}</p>` : ''}
      ${editable || note ? `<details class="fitter-notes" ${draft ? 'open' : ''}><summary>${note ? 'Item notes' : 'Add a note'}</summary><label for="fitter-note-${index}">Work notes</label><textarea id="fitter-note-${index}" data-fitter-note="${esc(line.line_identity)}" rows="2" maxlength="2000" ${disabled ? 'disabled' : ''}>${esc(note)}</textarea>${editable ? `<button type="button" data-fitter-save-note="${esc(line.line_identity)}" ${disabled ? 'disabled' : ''}>Save note</button>` : ''}${draft ? '<small>Unsaved note</small>' : ''}</details>` : ''}</article>`;
  }
  function render() {
    const target = host(); if (!target || !active()) return;
    const focus = doc.activeElement, focusId = focus?.id, selection = focus?.selectionStart != null ? [focus.selectionStart,focus.selectionEnd] : null;
    const openNotes = new Set([...target.querySelectorAll('.fitter-notes[open] textarea')].map(n=>n.dataset.fitterNote));
    const job = jobs.find(j=>j.id===selected), locked = saving || loading || service.retryPending;
    const editable = connected && service.canWrite() && detail?.status === 'started';
    const lines = detail?.lines || [], own = lines.filter(l=>l.stage_code===detail.stage_code), other = lines.filter(l=>l.stage_code!==detail.stage_code);
    target.innerHTML = `<div class="fitter-app"><header class="fitter-header"><div><h1>Fitters bay</h1><p>Your work, shared with the workshop planner</p></div><nav aria-label="Fitter navigation"><button type="button" data-fitter-qc>QC</button><button type="button" data-fitter-refresh ${locked ? 'disabled' : ''}>Refresh</button><button type="button" data-fitter-signout ${saving ? 'disabled' : ''}>Sign out</button></nav></header>
      <div class="fitter-toolbar"><label for="fitter-mechanic">Mechanic<select id="fitter-mechanic" ${locked ? 'disabled' : ''}><option value="">Select your name</option>${roster.map(t=>`<option value="${esc(t.id)}" ${t.id===mechanic?'selected':''}>${esc(t.name)}</option>`).join('')}</select></label><p class="fitter-sync" role="status">${saving ? 'Saving to workshop…' : loading ? 'Refreshing…' : connected ? `Connected · Updated ${esc(new Date(lastSync).toLocaleTimeString('en-AU',{timeZone:'Australia/Perth',hour:'numeric',minute:'2-digit',second:'2-digit'}))}` : 'Not connected · Changes unavailable'}</p></div>
      ${message ? `<div class="fitter-notice" role="status">${esc(message)}</div>` : ''}
      ${service.retryPending ? '<div class="fitter-warning">The last save is unconfirmed. Retrying checks the same action and cannot apply it twice. <button type="button" data-fitter-retry>Check / retry last save</button></div>' : ''}
      ${!service.canWrite() && connected ? '<p class="fitter-warning">View only. An operator account is needed to record work.</p>' : ''}
      ${mechanic ? `<p class="fitter-bay-summary">${bays.length ? bays.map(b=>`${esc(b.stage)} · Bay ${esc(b.number ?? '—')}${b.active?'':' (inactive)'}`).join(' / ') : 'Jobs individually assigned to this mechanic appear below.'}</p>` : ''}
      <div class="fitter-layout"><aside class="fitter-queue" aria-label="Current and upcoming jobs">${jobs.map(jobCard).join('') || `<div class="fitter-empty">${loading ? 'Loading jobs…' : mechanic ? 'No active jobs assigned. Ask the controller to assign your name to a bay or booking.' : 'Select your mechanic name to see your bays and jobs.'}</div>`}</aside>
      <section class="fitter-work" aria-label="Selected job">${job && detail ? `<div class="fitter-job-heading"><p class="fitter-kicker">${esc(job.stage_name)} · Bay ${esc(job.bay_number ?? '—')} · ${esc(state(detail.status))}</p><h2>${esc(job.stock)} <span>${esc(job.job_card)}</span></h2><p>${esc(job.customer)} · ${esc(job.vehicle)}</p><p class="fitter-time">${esc(time(job.start_at))} – ${esc(time(job.end_at))}</p>${progressHtml(detail.progress)}<p>${detail.progress.completed_lines} of ${detail.progress.total_lines} items complete · Progress uses approved work hours.</p></div>
      ${detail.status==='stoppage' ? `<div class="fitter-warning"><strong>Job stopped</strong><p>${esc(detail.stoppage_reason)}</p></div>` : ''}
      <div class="fitter-actions">${['planned','queued'].includes(detail.status) ? `<button class="fitter-primary" data-fitter-action="start" ${locked||!connected||!service.canWrite()?'disabled':''}>Start job</button><p>Start this booking on the workshop planner.</p>` : detail.status==='stoppage' ? `<button class="fitter-primary" data-fitter-action="resume" ${locked||!connected||!service.canWrite()?'disabled':''}>Resume job</button>` : detail.status==='started' ? `<button data-fitter-stop ${locked||!editable?'disabled':''}>Parts / other stoppage</button><button class="fitter-primary" data-fitter-action="complete" ${locked||!editable||!detail.progress.can_complete||[...drafts.keys()].some(k=>k.startsWith(selected+':'))?'disabled':''}>Complete bay job</button>` : ''}</div>
      ${stopOpen ? `<div class="fitter-stop-panel"><label for="fitter-stop-type">Stoppage type<select id="fitter-stop-type"><option ${stopType==='Parts'?'selected':''}>Parts</option><option ${stopType==='Other'?'selected':''}>Other</option></select></label><label for="fitter-stop-reason">What is holding up the work?<textarea id="fitter-stop-reason" rows="3" maxlength="1900">${esc(stopReason)}</textarea></label><button data-fitter-confirm-stop ${locked?'disabled':''}>Record stoppage</button><button data-fitter-cancel-stop ${locked?'disabled':''}>Cancel</button></div>` : ''}
      ${detail.progress.unknown_hours ? '<p class="fitter-warning">Some items need approved hours. Ask the controller to review these before completing the bay job.</p>' : ''}
      <h3>Items for this bay</h3><div class="fitter-lines">${own.map((l,i)=>lineCard(l,i,editable)).join('') || '<p class="fitter-empty">No approved operation lines for this bay. Ask the controller to review the vehicle.</p>'}</div>
      ${other.length ? `<details class="fitter-other"><summary>All other vehicle items (${other.length}) · View only</summary>${other.map((l,i)=>lineCard(l,own.length+i,false)).join('')}</details>` : ''}
      <p class="fitter-help">Tick items as the work is completed. Complete bay job finishes this workshop booking; QC inspection remains a separate step.</p>` : `<div class="fitter-empty">${loading && selected ? 'Loading operation lines…' : 'Your selected job will appear here.'}</div>`}</section></div></div>`;
    target.querySelectorAll('.fitter-notes textarea').forEach(n=>{ if(openNotes.has(n.dataset.fitterNote)) n.closest('details').open=true; });
    if (focusId && selection) { const next=doc.getElementById(focusId); next?.focus({preventScroll:true}); next?.setSelectionRange?.(...selection); }
    bind(target);
  }
  async function refresh() {
    if (!active() || loading || saving) return;
    const generation = ++loadGeneration, selectedBefore = selected, mechanicBefore = mechanic;
    loading = true; render();
    try {
      const rosterResult = await service.roster();
      if (generation!==loadGeneration || !active()) return;
      roster = rosterResult.technicians;
      if (mechanic && !roster.some(t=>t.id===mechanic)) mechanic='';
      if (mechanic) {
        const list = await service.jobs(mechanic);
        if (generation!==loadGeneration || mechanicBefore!==mechanic || !active()) return;
        jobs=list.jobs; bays=list.bays;
        if (!jobs.some(j=>j.id===selected)) { selected=jobs[0]?.id || ''; detail=null; }
        const result=selected ? await service.job(mechanic,selected) : null;
        if (generation!==loadGeneration || !active()) return;
        detail=result;
      } else { jobs=[]; bays=[]; selected=''; detail=null; }
      connected=true; lastSync=Date.now();
    } catch(e) { if (generation===loadGeneration) { connected=false; message=e.message; } }
    finally { if (generation===loadGeneration) { loading=false; render(); } }
  }
  async function act(action, lineId, completed, retry=false) {
    if (saving || loading || (!retry && (!connected || !detail))) return;
    const line=detail?.lines.find(l=>l.line_identity===lineId), key=`${selected}:${lineId}`, draft=drafts.get(key);
    if (draft && draft.scope!==line?.scope_hash) { message='This item changed while you were writing. Review it and copy your note before refreshing.'; render(); return; }
    if (action==='stop' && stopReason.trim().length<3) { message='Enter a short reason for the stoppage.'; render(); return; }
    const body={p_technician_id:mechanic,p_booking_id:selected,p_expected_version:detail?.version,
      p_catalog_hash:detail?.catalog_hash,p_action:action,p_line_identity:lineId||null,
      p_completed:completed??null,p_note:action==='stop'?`${stopType}: ${stopReason.trim()}`:line?(draft?.note??line.note??''):null};
    if (!retry) pendingDraftKey = lineId ? key : '';
    saving=true; message=''; render();
    try {
      const result=retry?await service.retry():await service.command(body);
      if (lineId) drafts.delete(key);
      if (retry && pendingDraftKey) drafts.delete(pendingDraftKey);
      pendingDraftKey = '';
      stopOpen=false; stopReason='';
      message=result.action==='complete'?'Bay job completed. Your next job is shown below.':result.already_started?'This job is already running on the planner.':'Saved to the workshop planner.';
      connected=false;
    } catch(e) { message=e.message; if(e.code!=='busy') connected=false; }
    finally { saving=false; await refresh(); render(); }
  }
  function bind(target) {
    const on=(selector,event,fn)=>target.querySelectorAll(selector).forEach(n=>n.addEventListener(event,fn));
    on('#fitter-mechanic','change',e=>{ mechanic=e.target.value; selected=''; detail=null; stopOpen=false; message=''; void refresh(); });
    on('[data-fitter-refresh]','click',()=>{ message=''; void refresh(); });
    on('[data-fitter-job]','click',e=>{ selected=e.currentTarget.dataset.fitterJob; detail=null; stopOpen=false; message=''; void refresh(); });
    on('[data-fitter-qc]','click',()=>{ if(typeof showView==='function') showView('qc'); });
    on('[data-fitter-signout]','click',()=>doc.querySelector('#pdc-auth-signout')?.click());
    on('[data-fitter-action]','click',e=>void act(e.currentTarget.dataset.fitterAction));
    on('[data-fitter-line]','change',e=>{ const n=e.currentTarget; const checked=n.checked; n.checked=!checked; void act('line',n.dataset.fitterLine,checked); });
    on('[data-fitter-note]','input',e=>{ const id=e.target.dataset.fitterNote, l=detail.lines.find(l=>l.line_identity===id); drafts.set(`${selected}:${id}`,{note:e.target.value,scope:l.scope_hash}); target.querySelector('[data-fitter-action="complete"]')?.setAttribute('disabled',''); });
    on('[data-fitter-save-note]','click',e=>{ const id=e.currentTarget.dataset.fitterSaveNote; void act('line',id,detail.lines.find(l=>l.line_identity===id).completed); });
    on('[data-fitter-stop]','click',()=>{ stopOpen=true; render(); doc.getElementById('fitter-stop-reason')?.focus(); });
    on('#fitter-stop-type','change',e=>{stopType=e.target.value;});
    on('#fitter-stop-reason','input',e=>{stopReason=e.target.value;});
    on('[data-fitter-confirm-stop]','click',()=>void act('stop'));
    on('[data-fitter-cancel-stop]','click',()=>{stopOpen=false;render();});
    on('[data-fitter-retry]','click',()=>void act(null,null,null,true));
  }
  api.open = () => { render(); if(!initialized) {initialized=true;void refresh();} };
  api.close = () => { loadGeneration++; loading=false; initialized=false; connected=false; };
  const reset=()=>{service.invalidate();api.close();roster=[];mechanic='';jobs=[];bays=[];selected='';detail=null;drafts.clear();message='';render();};
  root.addEventListener('pdc-auth-locked',reset);
  root.addEventListener('pdc-auth-ready',()=>{if(active())api.open();});
  root.addEventListener('offline',()=>{connected=false;message='Offline. Saved work is shown; reconnect before changing this job.';render();});
  root.addEventListener('online',()=>{if(active())void refresh();});
  root.addEventListener('focus',()=>{if(active())void refresh();});
  doc.addEventListener('visibilitychange',()=>{if(!doc.hidden&&active())void refresh();});
  setInterval(()=>{if(active()&&!doc.hidden&&!targetBeingEdited())void refresh();},10000);
  function targetBeingEdited() { return host()?.contains(doc.activeElement) && /TEXTAREA|SELECT/.test(doc.activeElement.tagName); }
  root.addEventListener('beforeunload',e=>{if(saving||drafts.size||service.retryPending){e.preventDefault();e.returnValue='';}});
})(typeof window !== 'undefined' ? window : globalThis);
