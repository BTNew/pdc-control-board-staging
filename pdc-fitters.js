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
    parts_incomplete_entry:'Parts are not marked ready. Ask the controller to confirm the parts or record an authorised override before starting this job.',
    vehicle_overlap:'This vehicle has another booking that prevents this change. Ask the controller to review its booking order.',
    bay_overlap:'This bay has another job in progress. Ask the controller to check its bookings.',
    bay_already_started:'This bay already has a running or stopped job. Ask the controller to complete it or release its bay.',
    schedule_changed:'The schedule changed during this action. Refresh, review the latest bookings and try again.',
    schedule_write_order_blocked:'The affected jobs cannot be safely moved. Ask the controller to review the surrounding bookings.',
    no_available_slot:'No suitable working time is available. Ask the controller to review the surrounding bookings.',
    technician_unavailable:'The assigned mechanic is unavailable during this work. Ask the controller to check the assignment.',
    fixed_booking_conflict:'Live work or an admin block is reserving this bay. Refresh and ask the controller to review the booking.',
    admin_block_conflict:'An admin block is reserving this bay. Ask the controller to review the booking.',
    calendar_unavailable:'This booking needs its workshop hours checked. Refresh and ask the controller to review it.',
    calendar_duration_mismatch:'This booking needs its work duration checked after a workshop-hours change. Ask the controller to review it.',
    not_startable:'This booking cannot be started in its current state. Refresh the job.',
    request_reused:'This action could not be verified. Refresh before making another change.',
  };
  function serverErrorCode(body) {
    for (const code of [body?.error,body?.code]) if (Object.hasOwn(errors,code)) return code;
    // PostgreSQL constraint errors may wrap the useful code in a JSON message.
    // Only show our known explanations, never raw database details.
    for (const value of [body?.message,body?.details,body?.hint]) {
      if (typeof value!=='string') continue;
      try {
        const start=value.indexOf('{'),end=value.lastIndexOf('}');
        const parsed=JSON.parse(start>=0 ? value.slice(start,end+1) : value);
        if (Object.hasOwn(errors,parsed?.error)) return parsed.error;
      } catch (_) { /* Non-JSON server messages use the generic explanation. */ }
    }
    return body?.error || body?.code || 'rejected';
  }
  function bookingConflictMessage(body, action) {
    if(serverErrorCode(body)!=='vehicle_overlap') return null;
    const blocker=body?.blocker;
    if(!blocker || typeof blocker!=='object') return null;
    const stages={BUS_4X4:'Bus 4×4',TINT:'Tint',HOIST:'Hoist',FITTING:'Fitting',FABRICATION:'Fabrication',ELECTRICAL:'Electrical',TYRE:'Tyre'};
    const stage=stages[blocker.stage_code]||String(blocker.stage_name||'another workshop').trim().slice(0,80);
    const bay=Number(blocker.bay_number),where=`${stage}${Number.isInteger(bay)&&bay>0?`, Bay ${bay}`:''}`;
    const situation={planned:'has a planned booking',queued:'has a queued booking',started:'has work in progress',stoppage:'has a stopped job'}[blocker.status]||'has another booking';
    const format=value=>Number.isFinite(Date.parse(value))?new Date(value).toLocaleString('en-AU',{timeZone:'Australia/Perth',weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}):'';
    const start=format(blocker.start_at||blocker.scheduled_start_at),end=format(blocker.end_at||blocker.scheduled_end_at);
    const when=start?` (${start}${end?` – ${end}`:''}, Perth time)`:'';
    return `${action==='start'?'Start blocked':action==='resume'?'Resume blocked':'Change blocked'}: this vehicle ${situation} in ${where}${when}. Ask the controller to review the vehicle’s booking order.`;
  }
  function progressHtml(progress, compact = false) {
    const p = Math.max(0, Math.min(100, Number(progress?.percent) || 0));
    const label = `${p}% work completed${progress ? ` · ${Number(progress.completed_hours) || 0} of ${Number(progress.total_hours) || 0} h` : ''}`;
    return `<span class="fitter-progress${compact ? ' is-compact' : ''}" role="progressbar" aria-label="Work completed by fitter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${p}" title="${esc(label)}"><span style="width:${p}%"></span>${compact ? '' : `<b>${esc(label)}</b>`}</span>`;
  }
  function formatElapsed(seconds) {
    if (!Number.isFinite(seconds)) return '--:--:--';
    const total=Math.max(0,Math.floor(seconds));
    return `${String(Math.floor(total/3600)).padStart(2,'0')}:${String(Math.floor(total/60)%60).padStart(2,'0')}:${String(total%60).padStart(2,'0')}`;
  }
  function timerModel(detail, options = {}) {
    const timer=detail?.timer, elapsed=Number.isFinite(timer?.elapsed_seconds)?Math.max(0,timer.elapsed_seconds):null;
    const timingHint=text=>timer?.history_complete===false?`${text} Approximate: earlier stoppage history is incomplete.`:text;
    const result={tone:'idle',label:'Not started',hint:'Start job to begin recording work.',seconds:0};
    const frozen=Number.isFinite(options.frozenSeconds)?Math.max(0,options.frozenSeconds):elapsed;
    const pending={start:'Starting job…',resume:'Resuming job…',stop:'Recording stoppage…',complete:'Completing job…',line:'Saving work…'}[options.pendingAction];
    if(pending) return {...result,tone:'pending',label:pending,hint:'Waiting for the workshop to confirm.',seconds:frozen};
    if(options.unconfirmed) return {...result,tone:'unconfirmed',label:({start:'Start not confirmed',resume:'Resume not confirmed',stop:'Stoppage not confirmed',complete:'Completion not confirmed'}[options.unconfirmedAction]||'Save not confirmed'),hint:'Check / retry the last save before continuing.',seconds:frozen};
    if(options.connected===false) return {...result,tone:'unconfirmed',label:'Last confirmed time',hint:'Reconnect or refresh to check this job.',seconds:frozen};
    if(!['started','stoppage','completed'].includes(detail?.status)) return result;
    if(!detail.actual_start_at || elapsed===null) return {...result,tone:'pending',label:'Checking job timer',hint:'Waiting for confirmed timing from the workshop.',seconds:null};
    if(detail.status==='stoppage') return {...result,tone:'paused',label:'Paused · Stoppage',hint:timingHint('Work time is paused until you resume.'),seconds:elapsed};
    if(detail.status==='completed') return {...result,label:'Job completed',hint:timingHint('Recorded work time.'),seconds:elapsed};
    if(timer.running!==true) return {...result,tone:'paused',label:'Outside working time',hint:timingHint('The timer pauses for breaks and workshop closure.'),seconds:elapsed};
    const age=Math.max(0,(options.now ?? 0)-(options.receivedAt ?? 0));
    const boundary=Date.parse(timer.next_change_at)-Date.parse(timer.as_of);
    const advance=Math.min(age,30000,Number.isFinite(boundary)?Math.max(0,boundary):30000);
    if(age>=30000) return {...result,tone:'unconfirmed',label:'Awaiting timer update',hint:'Showing the last confirmed running interval.',seconds:elapsed+advance/1000};
    if(Number.isFinite(boundary)&&age>=boundary) return {...result,tone:'paused',label:'Working interval ended',hint:'The next workshop update will confirm the timer.',seconds:elapsed+advance/1000};
    return {...result,tone:'running',label:'Running',hint:timingHint('Active work time · Breaks and stoppages excluded.'),seconds:elapsed+advance/1000};
  }
  function timerHtml(detail, options) {
    const timer=timerModel(detail,options);
    return `<div class="fitter-timer is-${timer.tone}" data-fitter-timer role="group" aria-label="Job work timer"><span class="fitter-timer-dot" aria-hidden="true"></span><div><strong data-fitter-timer-label>${esc(timer.label)}</strong><small data-fitter-timer-hint>${esc(timer.hint)}</small></div><output data-fitter-clock aria-label="Elapsed work time">${formatElapsed(timer.seconds)}</output></div>`;
  }
  function createService(options) {
    let generation = 0, busy = false, retry = null;
    let rosterCache = null, rosterRequest = null;
    const now = options.now || Date.now;
    const rosterTtlMs = options.rosterTtlMs ?? 60000;
    const error = (message, code) => Object.assign(Error(message), { code });
    const available = (c, write) => Boolean(c?.actor && c.token && c.config?.projectRef === PROJECT
      && c.config.url?.replace(/\/$/, '') === `https://${PROJECT}.supabase.co`
      && c.config.workshop?.sharedData === true
      && (!write || ['operator','administrator'].includes(c.role)));
    function current(owner, write) {
      const c = options.context();
      return owner.generation === generation && owner.actor === c.actor && owner.token === c.token
        && owner.role === c.role && owner.config === c.config && available(c, write);
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
          const code = serverErrorCode(result.body);
          throw error(bookingConflictMessage(result.body,body?.p_action)||errors[code] || 'The workshop could not save this change. Refresh and ask the controller to check the booking if it continues.', code);
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
    async function roster({ force = false } = {}) {
      // Reference names change infrequently. Never reuse this cache across a
      // sign-in, role, token or configuration change, including in-flight reads.
      if (!force && rosterCache && current(rosterCache.owner, false)
          && now() - rosterCache.at < rosterTtlMs) return rosterCache.result;
      if (rosterRequest && current(rosterRequest.owner, false)) return rosterRequest.promise;
      const owner = { ...options.context(), generation };
      const request = { owner, promise: null };
      request.promise = rpc('get_fitter_roster', {}, false, owner).then(result => {
        if (current(owner, false)) rosterCache = { owner, result, at: now() };
        return result;
      }).finally(() => { if (rosterRequest === request) rosterRequest = null; });
      rosterRequest = request;
      return request.promise;
    }
    return {
      roster,
      jobs:id => rpc('get_fitter_jobs', {p_technician_id:id}, false),
      job:(id, booking) => rpc('get_fitter_job', {p_technician_id:id,p_booking_id:booking}, false),
      command, retry:() => command(null, true),
      invalidate() { generation++; retry = null; rosterCache = null; rosterRequest = null; },
      get busy() { return busy; }, get retryPending() { return Boolean(retry); },
      get retryAction() { return retry?.body.p_action || ''; },
      canWrite:() => available(options.context(), true),
    };
  }
  const api = { createService, progressHtml, timerModel, timerHtml, formatElapsed, esc };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  root.PdcFitters = api;
  const doc = root.document;
  const service = createService({
    context:() => ({ actor:root.PDC_AUTH_CONTEXT?.userId, role:root.PDC_AUTH_CONTEXT?.role,
      token:typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '', config:root.PDC_SUPABASE_CONFIG }),
    fetch:(...args) => root.fetch(...args), uuid:() => root.crypto.randomUUID(),
  });
  let roster = [], mechanic = '', jobs = [], bays = [], selected = '', detail = null;
  let loading = false, refreshing = false, connected = false, message = '', loadGeneration = 0, initialized = false, lastSync = 0;
  let stopOpen = false, stopReason = '', stopType = 'Parts', saving = false, pendingDraftKey = '', pendingAction = '';
  let detailReceivedAt = 0, timerFreeze = null;
  const clockNow=()=>root.performance?.now?.() ?? Date.now();
  const timingOptions=()=>({connected,receivedAt:detailReceivedAt,now:clockNow(),
    pendingAction:saving||loading?pendingAction:'',unconfirmed:service.retryPending,unconfirmedAction:service.retryAction,
    frozenSeconds:timerFreeze?.bookingId===detail?.booking_id?timerFreeze?.seconds:null});
  function freezeTimer() {
    // Keep the visible confirmed interval when a save or connection becomes
    // uncertain; dropping back to its last poll would make the clock rewind.
    timerFreeze=detail?{bookingId:detail.booking_id,seconds:timerModel(detail,timingOptions()).seconds}:null;
  }
  function updateTimer() {
    if(!active()||doc.hidden) return;
    const box=host()?.querySelector('[data-fitter-timer]'); if(!box) return;
    const timer=timerModel(detail,timingOptions());
    box.className=`fitter-timer is-${timer.tone}`;
    const clock=box.querySelector('[data-fitter-clock]'),label=box.querySelector('[data-fitter-timer-label]'),hint=box.querySelector('[data-fitter-timer-hint]');
    if(clock) clock.textContent=formatElapsed(timer.seconds);
    if(label) label.textContent=timer.label;
    if(hint) hint.textContent=timer.hint;
  }
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
    const savingLabel=({start:'Starting job…',resume:'Resuming job…',stop:'Recording stoppage…',complete:'Completing job…'}[pendingAction]||'Saving to workshop…');
    const editable = connected && service.canWrite() && detail?.status === 'started';
    const lines = detail?.lines || [], own = lines.filter(l=>l.stage_code===detail.stage_code), other = lines.filter(l=>l.stage_code!==detail.stage_code);
    target.innerHTML = `<div class="fitter-app"><header class="fitter-header"><div><h1>Fitters bay</h1><p>Your work, shared with the workshop planner</p></div><nav aria-label="Fitter navigation"><button type="button" data-fitter-qc>QC</button><button type="button" data-fitter-refresh ${locked ? 'disabled' : ''}>Refresh</button><button type="button" data-fitter-signout ${saving ? 'disabled' : ''}>Sign out</button></nav></header>
      <div class="fitter-toolbar"><label for="fitter-mechanic">Mechanic<select id="fitter-mechanic" ${locked ? 'disabled' : ''}><option value="">Select your name</option>${roster.map(t=>`<option value="${esc(t.id)}" ${t.id===mechanic?'selected':''}>${esc(t.name)}</option>`).join('')}</select></label><p class="fitter-sync" role="status">${saving ? savingLabel : loading ? 'Refreshing…' : connected ? `Connected · Updated ${esc(new Date(lastSync).toLocaleTimeString('en-AU',{timeZone:'Australia/Perth',hour:'numeric',minute:'2-digit',second:'2-digit'}))}` : 'Not connected · Changes unavailable'}</p></div>
      ${message ? `<div class="fitter-notice" role="status">${esc(message)}</div>` : ''}
      ${service.retryPending ? '<div class="fitter-warning">The last save is unconfirmed. Retrying checks the same action and cannot apply it twice. <button type="button" data-fitter-retry>Check / retry last save</button></div>' : ''}
      ${!service.canWrite() && connected ? '<p class="fitter-warning">View only. An operator account is needed to record work.</p>' : ''}
      ${mechanic ? `<p class="fitter-bay-summary">${bays.length ? bays.map(b=>`${esc(b.stage)} · Bay ${esc(b.number ?? '—')}${b.active?'':' (inactive)'}`).join(' / ') : 'Jobs individually assigned to this mechanic appear below.'}</p>` : ''}
      <div class="fitter-layout"><aside class="fitter-queue" aria-label="Current and upcoming jobs">${jobs.map(jobCard).join('') || `<div class="fitter-empty">${loading ? 'Loading jobs…' : mechanic ? 'No active jobs assigned. Ask the controller to assign your name to a bay or booking.' : 'Select your mechanic name to see your bays and jobs.'}</div>`}</aside>
      <section class="fitter-work" aria-label="Selected job">${job && detail ? `<div class="fitter-job-heading"><p class="fitter-kicker">${esc(job.stage_name)} · Bay ${esc(job.bay_number ?? '—')} · ${esc(state(detail.status))}</p><h2>${esc(job.stock)} <span>${esc(job.job_card)}</span></h2><p>${esc(job.customer)} · ${esc(job.vehicle)}</p><p class="fitter-time">${esc(time(job.start_at))} – ${esc(time(job.end_at))}</p>${timerHtml(detail,timingOptions())}${progressHtml(detail.progress)}<p>${detail.progress.completed_lines} of ${detail.progress.total_lines} items complete · Progress uses approved work hours.</p></div>
      ${detail.status==='stoppage' ? `<div class="fitter-warning"><strong>Job stopped</strong><p>${esc(detail.stoppage_reason)}</p></div>` : ''}
      <div class="fitter-actions">${['planned','queued'].includes(detail.status) ? `<button class="fitter-primary" data-fitter-action="start" ${locked||!connected||!service.canWrite()?'disabled':''}>${(saving||loading)&&pendingAction==='start'?'Starting job…':'Start job'}</button><p>Start this booking on the workshop planner.</p>` : detail.status==='stoppage' ? `<button class="fitter-primary" data-fitter-action="resume" ${locked||!connected||!service.canWrite()?'disabled':''}>${(saving||loading)&&pendingAction==='resume'?'Resuming job…':'Resume job'}</button>` : detail.status==='started' ? `<button data-fitter-stop ${locked||!editable?'disabled':''}>Parts / other stoppage</button><button class="fitter-primary" data-fitter-action="complete" ${locked||!editable||!detail.progress.can_complete||[...drafts.keys()].some(k=>k.startsWith(selected+':'))?'disabled':''}>Complete bay job</button>` : ''}</div>
      ${stopOpen ? `<div class="fitter-stop-panel" role="group" aria-label="Record a workshop stoppage"><label for="fitter-stop-type">Stoppage type<select id="fitter-stop-type" ${locked?'disabled':''}><option ${stopType==='Parts'?'selected':''}>Parts</option><option ${stopType==='Other'?'selected':''}>Other</option></select></label><label for="fitter-stop-reason">What is holding up the work?<textarea id="fitter-stop-reason" rows="3" maxlength="1900" ${locked?'disabled':''}>${esc(stopReason)}</textarea></label><button type="button" data-fitter-confirm-stop ${locked?'disabled':''}>Record stoppage</button><button type="button" data-fitter-cancel-stop ${locked?'disabled':''}>Cancel</button></div>` : ''}
      ${detail.progress.unknown_hours ? '<p class="fitter-warning">Some items need approved hours. Ask the controller to review these before completing the bay job.</p>' : ''}
      <h3>Items for this bay</h3><div class="fitter-lines">${own.map((l,i)=>lineCard(l,i,editable)).join('') || '<p class="fitter-empty">No approved operation lines for this bay. Ask the controller to review the vehicle.</p>'}</div>
      ${other.length ? `<details class="fitter-other"><summary>All other vehicle items (${other.length}) · View only</summary>${other.map((l,i)=>lineCard(l,own.length+i,false)).join('')}</details>` : ''}
      <p class="fitter-help">Tick items as the work is completed. Complete bay job finishes this workshop booking; QC inspection remains a separate step.</p>` : `<div class="fitter-empty">${loading && selected ? 'Loading operation lines…' : 'Your selected job will appear here.'}</div>`}</section></div></div>`;
    target.querySelectorAll('.fitter-notes textarea').forEach(n=>{ if(openNotes.has(n.dataset.fitterNote)) n.closest('details').open=true; });
    if (focusId && selection) { const next=doc.getElementById(focusId); next?.focus({preventScroll:true}); next?.setSelectionRange?.(...selection); }
    bind(target);
  }
  function viewKey() { return JSON.stringify([roster, mechanic, jobs, bays, selected, detail, connected, message],(key,value)=>['timer','generated_at','server_now'].includes(key)?undefined:value); }
  async function refresh({ background = false, forceRoster = false } = {}) {
    if (!active() || loading || saving || (background && refreshing)) return;
    const generation = ++loadGeneration, mechanicBefore = mechanic, before = viewKey();
    refreshing = true; loading = !background;
    if (!background) render();
    try {
      const rosterResult = await service.roster({ force: forceRoster });
      if (generation!==loadGeneration || !active()) return;
      const nextRoster = rosterResult.technicians;
      const nextMechanic = nextRoster.some(t=>t.id===mechanicBefore) ? mechanicBefore : '';
      let nextJobs = [], nextBays = [], nextSelected = '', nextDetail = null;
      if (nextMechanic) {
        const list = await service.jobs(nextMechanic);
        if (generation!==loadGeneration || mechanicBefore!==mechanic || !active()) return;
        nextJobs=list.jobs; nextBays=list.bays;
        nextSelected=nextJobs.some(j=>j.id===selected) ? selected : nextJobs[0]?.id || '';
        nextDetail=nextSelected ? await service.job(nextMechanic,nextSelected) : null;
        if (generation!==loadGeneration || !active()) return;
      }
      // Apply the matching list and operation scope together. An interaction
      // superseding a background read must never receive its late job details.
      if(selected!==nextSelected) { stopOpen=false; stopReason=''; }
      roster=nextRoster; mechanic=nextMechanic; jobs=nextJobs; bays=nextBays;
      selected=nextSelected; detail=nextDetail; detailReceivedAt=clockNow();
      if(!service.retryPending || timerFreeze?.bookingId!==nextSelected) timerFreeze=null;
      connected=true; lastSync=Date.now();
    } catch(e) { if (generation===loadGeneration) { freezeTimer(); connected=false; message=e.message; } }
    finally { if (generation===loadGeneration) {
      loading=false; refreshing=false;
      if (!background || before!==viewKey()) render();
      else {
        const sync=host()?.querySelector('.fitter-sync');
        if(sync && connected) sync.textContent=`Connected · Updated ${new Date(lastSync).toLocaleTimeString('en-AU',{timeZone:'Australia/Perth',hour:'numeric',minute:'2-digit',second:'2-digit'})}`;
        updateTimer();
      }
    } }
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
    // Do not make a fitter's tap disappear merely because polling is running.
    // The command still carries the displayed version and scope to the server.
    loadGeneration++; refreshing=false;
    freezeTimer();
    pendingAction=retry?service.retryAction:action;
    saving=true; message=''; render();
    try {
      const result=retry?await service.retry():await service.command(body);
      if(typeof root.CustomEvent==='function'&&typeof root.dispatchEvent==='function') {
        root.dispatchEvent(new root.CustomEvent('pdc-fitter-workshop-saved',{detail:{
          bookingId:result.booking_id||detail?.booking_id,stageCode:detail?.stage_code,
          action:result.action,revision:result.revision,
        }}));
      }
      if (lineId) drafts.delete(key);
      if (retry && pendingDraftKey) drafts.delete(pendingDraftKey);
      pendingDraftKey = '';
      stopOpen=false; stopReason='';
      message=result.action==='complete'?'Bay job completed. Your next job is shown below.':result.already_started?'This job is already running on the planner.':result.action==='start'?'Job started on the workshop planner.':result.action==='resume'?'Job resumed on the workshop planner.':'Saved to the workshop planner.';
      connected=false;
    } catch(e) { message=e.message; if(e.code!=='busy') connected=false; }
    finally { saving=false; await refresh(); pendingAction=''; }
  }
  function bind(target) {
    const on=(selector,event,fn)=>target.querySelectorAll(selector).forEach(n=>n.addEventListener(event,fn));
    on('#fitter-mechanic','change',e=>{ mechanic=e.target.value; selected=''; detail=null; stopOpen=false; stopReason=''; message=''; void refresh(); });
    on('[data-fitter-refresh]','click',()=>{ message=''; void refresh({forceRoster:true}); });
    on('[data-fitter-job]','click',e=>{ selected=e.currentTarget.dataset.fitterJob; detail=null; stopOpen=false; stopReason=''; message=''; void refresh(); });
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
  api.close = () => { freezeTimer(); loadGeneration++; loading=false; refreshing=false; initialized=false; connected=false; };
  const reset=()=>{service.invalidate();api.close();roster=[];mechanic='';jobs=[];bays=[];selected='';detail=null;detailReceivedAt=0;timerFreeze=null;pendingAction='';stopOpen=false;stopReason='';drafts.clear();message='';render();};
  root.addEventListener('pdc-auth-locked',reset);
  root.addEventListener('pdc-auth-ready',()=>{if(active())api.open();});
  root.addEventListener('offline',()=>{freezeTimer();loadGeneration++;loading=false;refreshing=false;connected=false;message='Offline. Saved work is shown; reconnect before changing this job.';render();});
  root.addEventListener('online',()=>{if(active())void refresh();});
  root.addEventListener('focus',()=>{if(active()&&!targetBeingEdited())void refresh({background:true});});
  doc.addEventListener('visibilitychange',()=>{if(!doc.hidden&&active()&&!targetBeingEdited())void refresh({background:true});});
  setInterval(()=>{if(active()&&!doc.hidden&&!targetBeingEdited())void refresh({background:true});},10000);
  setInterval(updateTimer,1000);
  function targetBeingEdited() { return host()?.contains(doc.activeElement) && /TEXTAREA|SELECT/.test(doc.activeElement.tagName); }
  root.addEventListener('beforeunload',e=>{if(saving||drafts.size||service.retryPending){e.preventDefault();e.returnValue='';}});
})(typeof window !== 'undefined' ? window : globalThis);
