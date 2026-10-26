/* Fitter workflow. The database is the authority for assignments, lifecycle and progress. */
(function (root) {
  'use strict';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  // r483 (F96): Dept 139 bays show Craig's names and numbers ('Fitting · Bay 06'); other stations keep 'Bay N'.
  // The mechanic's bay list names its station by display name, so map those back to the station code.
  const STAGE_BY_NAME = {Hoist:'HOIST',Fitting:'FITTING',Fab:'FABRICATION',Fabrication:'FABRICATION',Elec:'ELECTRICAL',Electrical:'ELECTRICAL'};
  const bayText = (stageCode, number) => root.PDC_WORKSHOP_DEPARTMENTS?.pmbBayLabel?.(stageCode, number) || `Bay ${number ?? '—'}`;
  const errors = {
    bus_stage_parts_required:'Parts no longer hold up a job. Refresh the page and try again; if it happens again, tell the controller.',
    bus_bay_vehicle_incompatible:'This vehicle is not compatible with this Bus 4×4 bay. Ask the controller to choose a suitable bay.',
    bus_shift_outside_hours:'This booking falls outside the Department 138 shift. Ask the controller to review its times.',
    bus_supplier_verification_required:'Physically check and confirm the supplier work below before completing this bay.',
    conversion_sections_required:'Complete and confirm each conversion section before finishing the parent job.',
    conversion_model_review:'The model or conversion scope needs controller review.',
    conversion_deferred:'Clear or finish deferred work and blockers before confirming this section complete.',
    conversion_checklist_required:'The controller must confirm the applicable manufacturer completion checklist and its scope before Section 12 can be completed.',
    conversion_controller_required:'A controller must confirm the manufacturer checklist.',
    conversion_reopen_section:'Reopen Section 12 before changing its checklist reference.',
    conversion_invalid:'Check the section details and enter non-negative hours.',
    item_start_unavailable:'Supplier and conversion items use their own ticks. Tick Done when the work is finished.',
    item_already_done:'This item is already Done. Untick Done first to start it again.',
    item_not_started:'Press Start on this item first, then tick Done when the work is finished.',
    item_not_running:'That item is no longer running. Refresh the board.',
    booking_not_active:'That job is already complete. Nothing to reset.',
    version_conflict:'This job changed on another screen. Refresh, review the latest items and try again.',
    scope_changed:'The operation list or hours changed. Refresh and review the updated items.',
    assignment_changed:'This job is no longer assigned to this mechanic. Refresh the job list.',
    job_not_running:'Start or resume this job before recording work.',
    items_incomplete:'Complete every item in this bay before finishing the job. Missing hours need controller review.',
    line_unavailable:'That item is no longer available in this bay. Refresh the job.',
    station_busy:'That station already has this job running in its own bay. Finish the items there.',
    mechanic_unavailable:'This mechanic is inactive or unavailable. Select another mechanic.',
    reason_required:'Enter a reason for the stoppage.',
    parts_incomplete_entry:'Parts no longer hold up a job. Refresh the page and try again; if it happens again, tell the controller.',
    vehicle_overlap:'A protected booking for this vehicle prevents this change. Ask the controller to check that work before continuing.',
    bay_overlap:'This bay has another job in progress. Ask the controller to check its bookings.',
    bay_already_started:'This bay already has a running or stopped job. Ask the controller to complete it or release its bay.',
    schedule_changed:'The schedule changed during this action. Refresh, review the latest bookings and try again.',
    schedule_write_order_blocked:'The affected jobs cannot be safely moved. Ask the controller to review the surrounding bookings.',
    no_available_slot:'No suitable working time is available. Ask the controller to review the surrounding bookings.',
    technician_unavailable:'The assigned mechanic is unavailable during this work. Ask the controller to check the assignment.',
    technician_overlap:'This mechanic already has another running or stopped job. Complete or release that work before starting another.',
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
    const bay=Number(blocker.bay_number),where=`${stage}${Number.isInteger(bay)&&bay>0?`, ${bayText(blocker.stage_code,bay)}`:''}`;
    const situation={planned:'has a planned booking',queued:'has a queued booking',started:'has work in progress',stoppage:'has a stopped job'}[blocker.status]||'has another booking';
    const format=value=>Number.isFinite(Date.parse(value))?new Date(value).toLocaleString('en-AU',{timeZone:'Australia/Perth',weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}):'';
    const start=format(blocker.start_at||blocker.scheduled_start_at),end=format(blocker.end_at||blocker.scheduled_end_at);
    const when=start?` (${start}${end?` – ${end}`:''}, Perth time)`:'';
    const help=action==='start'
      ? ['started','stoppage'].includes(blocker.status)?'Ask the controller to resolve that protected work before starting this job.':'This booking could not be moved safely. Ask the controller to check it before starting this job.'
      : 'Ask the controller to check this booking before continuing.';
    return `${action==='start'?'Start blocked':action==='resume'?'Resume blocked':'Change blocked'}: this vehicle ${situation} in ${where}${when}. ${help}`;
  }
  const itemDuration = m => { if (m == null || !Number.isFinite(Number(m))) return '—'; const t = Math.max(0, Math.round(Number(m))); return `${Math.floor(t / 60)}h ${String(t % 60).padStart(2, '0')}m`; };
  // r440: Start and Done ticked seconds apart record a real but tiny actual;
  // say so instead of the misleading "0h 00m".
  const actualDuration = m => Number.isFinite(Number(m)) && Number(m) >= 0 && Number(m) < 0.5 ? 'under 1 min' : itemDuration(m);
  // The % counts Done work only. Running items (Start ticked, not Done) are
  // shown beside it, and any running past twice its allowance or since an
  // earlier day is flagged so a controller can reset it.
  // r493 (F106): options.paused (true or a reason such as 'Stoppage' or
  // 'Outside working time') shows started items as Paused in amber while the
  // job clock is not counting. Display only; the item times are unchanged.
  const pausedText = paused => paused ? (typeof paused === 'string' && paused.trim() ? paused.trim() : 'Paused') : '';
  function runningHtml(progress, options = {}) {
    const current = Array.isArray(progress?.current) ? progress.current : [];
    if (!current.length) return '';
    const paused = pausedText(options.paused);
    const stale = current.filter(c => c.stale === true);
    const now = current.map(c => `${c.description || 'Item'}${c.technician ? ` · ${c.technician}` : ''} · ${itemDuration(c.elapsed_minutes)}${c.allowance_minutes ? ` of ${itemDuration(c.allowance_minutes)}` : ''}${c.stale ? ' · check' : ''}`);
    const reset = options.resettable ? stale.map(c => `<button type="button" class="fitter-item-reset" data-fitter-item-reset="${esc(c.booking_id)}" data-fitter-item-line="${esc(c.line_identity)}" data-fitter-item-section="${esc(c.section ?? '')}" data-fitter-item-name="${esc(c.description || 'Item')}">Reset ${esc(c.description || 'item')}</button>`).join('') : '';
    return `<span class="fitter-running${stale.length ? ' is-stale' : ''}${paused ? ' is-paused' : ''}" title="${esc((paused ? [`Paused · ${paused.replace(/^Paused\s*·\s*/i, '')}`, ...now] : now).join('\n'))}"><b>${paused ? 'Paused' : 'Running'}: ${current.length}</b> <span>Now: ${esc(now[0])}${current.length > 1 ? ` +${current.length - 1}` : ''}</span>${stale.length ? `<em>${stale.length} running too long${options.resettable ? '' : ' · reset from the planner'}</em>` : ''}${reset}</span>`;
  }
  // r440: the running animation covers only the approved hours of the items
  // (or conversion sections) currently started, as a segment straight after
  // the solid Done portion. Nothing started, no animation.
  function runningShare(progress, p) {
    const total = Number(progress?.total_hours) || 0;
    const current = Array.isArray(progress?.current) ? progress.current : [];
    if (!(total > 0) || !current.length) return 0;
    const minutes = current.reduce((sum, c) => sum + Math.max(0, Number(c?.allowance_minutes) || 0), 0);
    return Math.max(0, Math.min(100 - p, Math.round(1000 * minutes / 60 / total) / 10));
  }
  function progressHtml(progress, compact = false, options = {}) {
    const p = Math.max(0, Math.min(100, Number(progress?.percent) || 0));
    const run = runningShare(progress, p), paused = run > 0 && pausedText(options.paused);
    const label = `${p}% work completed${progress ? ` · ${Number(progress.completed_hours) || 0} of ${Number(progress.total_hours) || 0} h` : ''}${Number(progress?.running) > 0 ? ` · ${Number(progress.running)} ${options.paused ? 'paused' : 'running'}` : ''}`;
    return `<span class="fitter-progress${compact ? ' is-compact' : ''}${run > 0 ? ' has-running' : ''}${paused ? ' is-paused' : ''}" role="progressbar" aria-label="Work completed by fitter" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${p}" title="${esc(label)}"><span style="width:${p}%"></span>${run > 0 ? `<i class="fitter-progress-run" aria-hidden="true" style="left:${p}%;width:${run}%"></i>` : ''}${compact ? '' : `<b>${esc(label)}</b>`}</span>${runningHtml(progress, options)}`;
  }
  function formatElapsed(seconds) {
    if (!Number.isFinite(seconds)) return '--:--:--';
    const total=Math.max(0,Math.floor(seconds));
    return `${String(Math.floor(total/3600)).padStart(2,'0')}:${String(Math.floor(total/60)%60).padStart(2,'0')}:${String(total%60).padStart(2,'0')}`;
  }
  function timerModel(detail, options = {}) {
    const timer=detail?.timer, elapsed=Number.isFinite(timer?.elapsed_seconds)?Math.max(0,timer.elapsed_seconds):null;
    const unknownHistory=timer?.history_complete===false&&elapsed===null;
    const timingHint=text=>timer?.history_complete===false?`${text} Approximate: earlier stoppage history is incomplete.`:text;
    const result={tone:'idle',label:'Not started',hint:'Start job to begin recording work.',seconds:0};
    // A newly unverified history supersedes any previously displayed clock.
    // Never turn a missing authoritative total into zero or keep advancing it.
    const frozen=unknownHistory?null:Number.isFinite(options.frozenSeconds)?Math.max(0,options.frozenSeconds):elapsed;
    const pending={start:'Starting job…',resume:'Resuming job…',stop:'Recording stoppage…',complete:'Completing job…',line:'Saving work…',item_start:'Starting item…',item_reset:'Resetting item…'}[options.pendingAction];
    if(pending) return {...result,tone:'pending',label:pending,hint:options.pendingAction==='start'?'Checking the schedule and moving affected unstarted bookings where needed.':'Waiting for the workshop to confirm.',seconds:frozen};
    if(options.unconfirmed) return {...result,tone:'unconfirmed',label:({start:'Start not confirmed',resume:'Resume not confirmed',stop:'Stoppage not confirmed',complete:'Completion not confirmed'}[options.unconfirmedAction]||'Save not confirmed'),hint:'Check / retry the last save before continuing.',seconds:frozen};
    if(options.connected===false) return {...result,tone:'unconfirmed',label:'Last confirmed time',hint:'Reconnect or refresh to check this job.',seconds:frozen};
    if(unknownHistory) return {...result,tone:'unconfirmed',label:'Progress update required',hint:'Timing history is incomplete. Ask the controller to review the recorded work and waiting periods.',seconds:null};
    const queuedWork=detail?.status==='queued'&&detail.actual_start_at&&timer?.basis==='department138_bay_working_hours';
    if(!['started','stoppage','completed'].includes(detail?.status)&&!queuedWork) return result;
    if(!detail.actual_start_at || elapsed===null) return {...result,tone:'pending',label:'Checking job timer',hint:'Waiting for confirmed timing from the workshop.',seconds:null};
    if(queuedWork) return {...result,tone:'paused',label:'Paused · Unallocated',hint:timingHint('Recorded work time is held while this job waits for its next allocation.'),seconds:elapsed};
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
  function startConfirmationMessage(result={}) {
    if(result.already_started) return 'This job is already running on the planner.';
    const count=result.start_priority===true&&Number.isInteger(result.shifted_count)&&result.shifted_count>=0?result.shifted_count:null;
    return 'Job started on the workshop planner.'+(count===null?'':count===0?' No other bookings needed to move.':` ${count} affected booking${count===1?'':'s'} moved later.`);
  }
  function createService(options) {
    let generation = 0, busy = false, retry = null;
    let rosterCache = null, rosterRequest = null;
    let refreshCache = null, refreshRequest = null, readGeneration = 0;
    const now = options.now || Date.now;
    const rosterTtlMs = options.rosterTtlMs ?? 60000;
    const error = (message, code) => Object.assign(Error(message), { code });
    const available = (c, write) => Boolean(c?.actor && c.token && c.config?.projectRef === PROJECT
      && c.config.url?.replace(/\/$/, '') === `https://${PROJECT}.supabase.co`
      && c.config.workshop?.sharedData === true
      && (!write || ['operator','administrator','fitter'].includes(c.role)));
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
          throw error(bookingConflictMessage(result.body,body?.p_action)||errors[code] || (write ? 'The workshop could not save this change. Refresh and ask the controller to check the booking if it continues.' : 'The workshop could not load your jobs. Refresh and ask the controller to check access if it continues.'), code);
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
      invalidateReads();
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
    function invalidateReads() { readGeneration++; refreshCache=null; refreshRequest=null; }
    async function refresh(id, booking = '', { force = false } = {}) {
      // A foreground refresh supersedes any older background read. Never let a
      // response started before a command become the next revision baseline.
      if (force) invalidateReads();
      const owner={...options.context(),generation}, stamp=readGeneration;
      const cached=!force && refreshCache && current(refreshCache.owner,false)
        && refreshCache.id===id && refreshCache.result.selected===booking ? refreshCache : null;
      const known=cached?.revision || null;
      if (refreshRequest && current(refreshRequest.owner,false) && refreshRequest.stamp===stamp
          && refreshRequest.id===id && refreshRequest.booking===booking && refreshRequest.known===known) return refreshRequest.promise;
      const request={owner,stamp,id,booking,known,promise:null};
      request.promise=rpc('get_fitter_refresh',{p_technician_id:id,p_booking_id:booking||null,p_known_revision:known},false,owner).then(result=>{
        if(stamp!==readGeneration || refreshRequest!==request || !current(owner,false)) throw error('The job changed while refreshing. Refresh to check the latest work.','session_changed');
        if(typeof result.revision!=='string' || !result.revision) throw error('The workshop update could not be confirmed. Refresh to retry.','invalid_refresh');
        let snapshot;
        if(result.unchanged===true) {
          if(!cached || result.revision!==known || (result.booking_id||'')!==cached.result.selected
              || (cached.result.detail && (!result.timing?.timer || !result.timing.server_now))) {
            throw error('The workshop update could not be confirmed. Refresh to retry.','invalid_refresh');
          }
          snapshot={...cached.result,detail:cached.result.detail?{...cached.result.detail,...result.timing}:null};
        } else {
          if(!Array.isArray(result.jobs) || !Array.isArray(result.bays)) throw error('The job list could not be confirmed. Refresh to retry.','invalid_refresh');
          const selected=fitterJobFlow(result.jobs,booking).current?.id || '';
          if((result.booking_id||'')!==selected || (selected && result.detail?.booking_id!==selected)) throw error('The job list changed while refreshing. Refresh to retry.','invalid_refresh');
          snapshot={jobs:result.jobs,bays:result.bays,selected,detail:selected?result.detail:null};
        }
        refreshCache={owner,id,revision:result.revision,result:snapshot};
        return snapshot;
      }).finally(()=>{if(refreshRequest===request)refreshRequest=null;});
      refreshRequest=request;
      return request.promise;
    }
    return {
      roster, refresh, invalidateReads,
      jobs:id => rpc('get_fitter_jobs', {p_technician_id:id}, false),
      job:(id, booking) => rpc('get_fitter_job', {p_technician_id:id,p_booking_id:booking}, false),
      command, retry:() => command(null, true),
      resetItem:body => { invalidateReads(); return rpc('reset_fitter_item_timing', body, true); },
      invalidate() { generation++; retry = null; rosterCache = null; rosterRequest = null; invalidateReads(); },
      get busy() { return busy; }, get retryPending() { return Boolean(retry); },
      get retryAction() { return retry?.body.p_action || ''; },
      canWrite:() => available(options.context(), true),
    };
  }
  function fitterJobFlow(jobs, selected = '') {
    // Queue order comes from the planner. A stopped job remains current work;
    // a later planned job must never displace work already in progress.
    const active = jobs.filter(j=>['started','stoppage'].includes(j.status));
    const planned = jobs.filter(j=>['planned','queued'].includes(j.status));
    const current = active.find(j=>j.id===selected) || active[0] || planned[0] || null;
    const waiting = planned.filter(j=>j.id!==current?.id);
    return { current, next:waiting[0] || null, upcoming:waiting.slice(1), otherActive:active.filter(j=>j.id!==current?.id) };
  }
  // Coaster and HiAce main conversions: a dropdown under the job with one
  // simple Start / Done tick per section, like the other bay items.
  function conversionUsesSimpleTick(line) {
    const conversion = line && line.conversion;
    return !!conversion && conversion.needs_review !== true && (conversion.id === 'coaster' || conversion.id === 'hiace_commuter');
  }
  // r500 (F113): every started item / section shows Pause while the job is
  // started (also when it is running too long) and Resume while the job is
  // stopped. Pause opens the job's stoppage panel: the job clock is per bay
  // job, so pausing one item pauses the whole bay job until Resume.
  function itemPauseHtml(state, key, label) {
    const mode = state && state.pauseControl;
    if (mode !== 'pause' && mode !== 'resume') return '';
    const dis = state.pauseDisabled ? ' disabled' : '';
    return mode === 'pause'
      ? `<button type="button" class="fitter-item-pause" data-fitter-pause="${esc(key)}" aria-label="Pause ${esc(label)}"${dis}>Pause</button>`
      : `<button type="button" class="fitter-item-resume" data-fitter-action="resume" aria-label="Resume ${esc(label)}"${dis}>Resume</button>`;
  }
  const conversionDuration = m => m == null ? '—' : `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, '0')}m`;
  function conversionSectionHtml(line, section, state) {
    const id = esc(line.line_identity), sid = esc(section.id), planned = Number(section.planned_minutes) || 0;
    const done = section.status === 'complete', running = section.status === 'in_progress';
    const elapsed = Number(section.elapsed_minutes) || 0, over = running && planned > 0 && elapsed > planned;
    const pct = planned > 0 ? Math.min(100, Math.round(1000 * elapsed / planned) / 10) : 100;
    // Pure CSS fill: start at the server's elapsed share and run the remaining
    // allowance in real time. Paused while the bay job is stopped.
    const remainSeconds = Math.max(1, Math.round((planned - elapsed) * 60));
    const bar = running ? `<div class="conv-bar${over ? ' is-over' : ''}${state.paused ? ' is-paused' : ''}" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(pct)}" aria-label="${esc(section.label)} progress"><span style="--conv-from:${pct}%;--conv-run:${over ? 0 : remainSeconds}s"></span></div>` : '';
    const status = done ? `Done${section.actual_minutes != null ? ` · actual ${conversionDuration(Number(section.actual_minutes))}` : ''}`
      : running ? (state.paused ? 'Paused · ' : '') + (over ? `In progress · over by ${conversionDuration(elapsed - planned)}` : `In progress · ${conversionDuration(elapsed)} of ${conversionDuration(planned)}`) + (section.stale ? ' · running too long, tick Done or ask the controller to reset' : '') : '';
    const dis = state.disabled ? 'disabled' : '';
    const startDis = state.disabled || done ? 'disabled' : '';
    const doneDis = state.disabled || (!running && !done) ? 'disabled' : '';
    const noteKey = `${state.booking}|${line.line_identity}|${section.id}`, draft = state.noteDrafts?.get(noteKey);
    const note = draft ?? section.note ?? '';
    return `<li class="conv-section${done ? ' is-done' : ''}${running ? ' is-running' : ''}${running && state.paused ? ' is-paused' : ''}" data-conv-section="${sid}">
      <div class="conv-section-row"><span class="conv-section-name"><strong>${esc(section.label)} — ${esc(section.description)}</strong><small>${conversionDuration(planned)}${status ? ` · ${esc(status)}` : ''}</small></span>
      <label class="conv-tick"><input type="checkbox" data-conversion-step="start" data-conversion-line="${id}" data-conversion-section="${sid}" ${running || done ? 'checked' : ''} ${startDis}> Start</label>
      <label class="conv-tick"><input type="checkbox" data-conversion-step="done" data-conversion-line="${id}" data-conversion-section="${sid}" ${done ? 'checked' : ''} ${doneDis}> Done</label>${running ? itemPauseHtml(state, line.line_identity, section.label) : ''}</div>
      ${bar}
      ${state.editable || note ? `<details class="fitter-notes conv-note" ${draft != null ? 'open' : ''}><summary>${note ? 'Section note' : 'Add a note'}</summary><textarea aria-label="${esc(section.label)} note" data-conversion-note="${esc(noteKey)}" data-conversion-line="${id}" data-conversion-section="${sid}" rows="2" maxlength="500" ${dis}>${esc(note)}</textarea>${state.editable ? `<button type="button" data-conversion-save-note="${esc(noteKey)}" ${dis}>Save note</button>` : ''}${draft != null ? '<small>Unsaved note</small>' : ''}</details>` : ''}
    </li>`;
  }
  function conversionTicksHtml(line, index, state) {
    const c = line.conversion, sections = c.sections || [];
    const total = c.sections_total ?? sections.length, doneCount = c.sections_done ?? sections.filter(s => s.status === 'complete').length;
    const runningCount = c.sections_running ?? sections.filter(s => s.status === 'in_progress').length;
    const pct = line.completed ? 100 : Math.round(100 * (Number(line.completed_fraction) || 0));
    const open = state.open !== false;
    return `<article class="fitter-line conv-ticks${line.completed ? ' is-done' : ''}" data-conversion-card="${esc(line.line_identity)}"><details class="conv-list" data-conversion-list="${esc(state.booking)}|${esc(line.line_identity)}" ${open ? 'open' : ''}><summary><span><strong>${esc(line.description)}</strong><small>${esc(line.stage_code.replaceAll('_',' '))} · ${line.hours == null ? 'Hours need review' : `${esc(line.hours)} h`} · ${doneCount} of ${total} sections done${runningCount ? ` · ${runningCount} running` : ''}${line.completed ? ' · Work completed' : ''}</small></span><span class="conv-total" aria-hidden="true"><span style="width:${pct}%"></span></span></summary>
      ${line.scope_changed ? '<p class="fitter-warning">This item changed. Review the work before ticking it again.</p>' : ''}
      <ol class="conv-sections">${sections.map(s => conversionSectionHtml(line, s, state)).join('')}</ol></details></article>`;
  }
  // Bay items: Start begins the item's bar against its approved hours (paused
  // with the job clock); Done turns it green with the actual time. Since r440
  // Done needs Start first (server enforced). Supplier items keep the single Done tick.
  function itemTimingModel(line, state = {}) {
    const running = line.item_status === 'running' && !line.completed, done = !!line.completed;
    const planned = Number(line.hours) > 0 ? Number(line.hours) * 60 : 0;
    const fromClock = Number.isFinite(state.jobSeconds) && Number.isFinite(Number(line.item_start_seconds)) ? (state.jobSeconds - Number(line.item_start_seconds)) / 60 : NaN;
    const elapsed = running ? Math.max(0, Number.isFinite(fromClock) ? fromClock : Number(line.item_elapsed_minutes) || 0) : 0;
    // r440: an internal bay item must be started before Done can be ticked.
    const needsStart = !line.external_work && !line.conversion && !done && !running;
    return { running, done, planned, elapsed, needsStart, over: running && planned > 0 && elapsed > planned, actual: done && line.item_status === 'done' && line.item_actual_minutes != null ? Number(line.item_actual_minutes) : null };
  }
  function fitterItemTicksHtml(line, state) {
    if (line.external_work || line.conversion) return '';
    const m = itemTimingModel(line, state), id = esc(line.line_identity);
    const pct = m.planned > 0 ? Math.min(100, Math.round(1000 * m.elapsed / m.planned) / 10) : 0;
    const remainSeconds = Math.max(1, Math.round((m.planned - m.elapsed) * 60));
    const bar = m.running && m.planned > 0 ? `<div class="conv-bar${m.over ? ' is-over' : ''}${state.paused ? ' is-paused' : ''}" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.round(pct)}" aria-label="${esc(line.description)} progress"><span style="--conv-from:${pct}%;--conv-run:${m.over ? 0 : remainSeconds}s"></span></div>` : '';
    const status = m.done ? (m.actual != null ? `Done · actual ${actualDuration(m.actual)}` : '')
      : m.running ? `${state.paused ? 'Paused · ' : ''}${m.over ? `In progress · over by ${itemDuration(m.elapsed - m.planned)}` : m.planned ? `In progress · ${itemDuration(m.elapsed)} of ${itemDuration(m.planned)}` : `In progress · ${itemDuration(m.elapsed)} · no allowance`}${line.item_stale ? ' · running too long, tick Done or ask the controller to reset' : ''}` : '';
    return `<div class="fitter-item-ticks"><label class="conv-tick"><input type="checkbox" data-fitter-item-start="${id}" ${m.running || m.done ? 'checked' : ''} ${state.disabled || m.done ? 'disabled' : ''}> Start</label>${status ? `<small class="fitter-item-status">${esc(status)}</small>` : m.needsStart && state.editable ? '<small class="fitter-item-hint">Press Start first</small>' : ''}${m.running ? itemPauseHtml(state, line.line_identity, line.description) : ''}</div>${bar}`;
  }
  function fitterLineCardHtml(line, index, state) {
    const disabled = state.disabled, note = state.note, editable = state.editable, open = state.open;
    const m = itemTimingModel(line, state), timed = !line.external_work && !line.conversion;
    // r440: Done stays disabled until the item is started (existing Done items stay ticked and can still be unticked).
    const doneLocked = timed && m.needsStart;
    return `<article class="fitter-line${line.completed ? ' is-done' : ''}${m.running ? ' is-running' : ''}${m.running && state.paused ? ' is-paused' : ''}${line.item_stale && m.running ? ' is-stale' : ''}${doneLocked ? ' needs-start' : ''}"><label class="fitter-line-check"${doneLocked && editable ? ' title="Press Start first"' : ''}><input type="checkbox" data-fitter-line="${esc(line.line_identity)}" aria-label="${esc(line.description)} done" ${line.completed ? 'checked' : ''} ${disabled || doneLocked ? 'disabled' : ''}><span><strong>${esc(line.description)}</strong><small>${esc(line.stage_code.replaceAll('_',' '))} · ${line.external_work ? 'Supplier work · internal labour not counted' : line.hours == null ? 'Hours need review' : `${esc(line.hours)} h`}${line.completed ? ' · Work completed' : ''}</small></span></label>
      ${timed ? fitterItemTicksHtml(line, state) : ''}
      ${line.scope_changed ? '<p class="fitter-warning">This item changed. Review the work before ticking it again.</p>' : ''}
      ${line.source_note ? `<p class="fitter-source-note">${esc(line.source_note)}</p>` : ''}
      ${editable || note ? `<details class="fitter-notes" ${open ? 'open' : ''}><summary>${note ? 'Item notes' : 'Add a note'}</summary><label for="fitter-note-${index}">Work notes</label><textarea id="fitter-note-${index}" data-fitter-note="${esc(line.line_identity)}" rows="2" maxlength="2000" ${disabled ? 'disabled' : ''}>${esc(note)}</textarea>${editable ? `<button type="button" data-fitter-save-note="${esc(line.line_identity)}" ${disabled ? 'disabled' : ''}>Save note</button>` : ''}${open ? '<small>Unsaved note</small>' : ''}</details>` : ''}</article>`;
  }
  // The cache token of the pdc-fitters.js tag (index.html text or a script src).
  function fitterScriptToken(text) {
    const m = String(text || '').match(/pdc-fitters\.js\?([^"'\s<>]+)/);
    return m ? m[1].replace(/&amp;/g, '&') : '';
  }
  const api = { createService, fitterScriptToken, progressHtml, runningHtml, timerModel, timerHtml, formatElapsed, startConfirmationMessage, fitterJobFlow, esc, conversionUsesSimpleTick, fitterLineCardHtml, fitterItemTicksHtml, itemTimingModel, conversionTicksHtml, conversionSectionHtml, itemPauseHtml };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  root.PdcFitters = api;
  const doc = root.document;
  const service = createService({
    context:() => ({ actor:root.PDC_AUTH_CONTEXT?.userId, role:root.PDC_AUTH_CONTEXT?.role,
      token:typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '', config:root.PDC_SUPABASE_CONFIG }),
    fetch:(...args) => root.fetch(...args), uuid:() => root.crypto.randomUUID(),
  });
  const busService = () => root.PdcBusWorkflow?.service();
  const busPending = () => Boolean(busService()?.retryPending);
  let supplierDraftKey = '';
  let roster = [], mechanic = '', jobs = [], bays = [], selected = '', detail = null;
  let loading = false, refreshing = false, connected = false, message = '', readErrorMessage = '', loadGeneration = 0, initialized = false, lastSync = 0;
  let stopOpen = false, stopFrom = '', stopReason = '', stopType = 'Parts', saving = false, pendingDraftKey = '', pendingAction = '';
  let detailReceivedAt = 0, timerFreeze = null;
  let pendingConversionNote = '';
  let handover = null, scrollToCurrent = false;
  const clockNow=()=>root.performance?.now?.() ?? Date.now();
  const timingOptions=()=>({connected,receivedAt:detailReceivedAt,now:clockNow(),
    pendingAction:saving||loading?pendingAction:'',unconfirmed:service.retryPending||busPending(),unconfirmedAction:busPending()?'supplier':service.retryAction,
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
  const conversionNotes = new Map(), conversionClosed = new Set();
  // r388: a Fitters bay screen left open keeps running the code it loaded with,
  // so a release (such as the r384 item Start ticks) never reached it. Every few
  // minutes, and when the screen comes back, compare this script's cache token with
  // the live index.html. When they differ, reload as soon as nothing is unsaved
  // (otherwise offer Update now), and come back to the same mechanic and job.
  const UPDATE_CHECK_MS = 5 * 60 * 1000, RESUME_KEY = 'pdc-fitters-resume';
  const loadedToken = fitterScriptToken(doc.currentScript?.src || '');
  let updateReady = false, updateStarted = false, lastUpdateCheck = 0;
  try {
    const saved = JSON.parse(root.sessionStorage?.getItem(RESUME_KEY) || 'null');
    root.sessionStorage?.removeItem(RESUME_KEY);
    if (saved && typeof saved.mechanic === 'string' && Date.now() - Number(saved.at) < 10 * 60 * 1000) {
      mechanic = saved.mechanic; selected = typeof saved.selected === 'string' ? saved.selected : '';
    }
  } catch { /* storage unavailable: start from the mechanic list as before */ }
  const active = () => doc.body?.dataset.currentView === 'fitters';
  const host = () => doc.getElementById('fitters-host');
  const time = value => value ? new Date(value).toLocaleString('en-AU', {timeZone:'Australia/Perth',weekday:'short',day:'numeric',month:'short',hour:'numeric',minute:'2-digit'}) : 'Not scheduled';
  const state = value => ({started:'In progress',stoppage:'Stopped',planned:'Planned',queued:'Queued',completed:'Completed'}[value] || value);
  function jobPreview(job) {
    return `<strong>${esc(job.stock || 'Stock not recorded')}</strong><span>${esc(job.customer || 'Customer not recorded')} · ${esc(job.vehicle || 'Vehicle details pending')}</span><small>${esc(job.stage_name)} · ${esc(bayText(job.stage_code, job.bay_number))} · ${esc(time(job.start_at))}</small>`;
  }
  function nextJobHtml(flow, locked, editable) {
    const unsaved=[...drafts.keys()].some(k=>k.startsWith(selected+':')) || root.PdcConversions?.hasDrafts() || conversionNotes.size>0;
    const ready=detail?.progress?.can_complete && !unsaved && !root.PdcBusWorkflow?.hasDrafts() && !busPending();
    const completeLabel=(saving||loading)&&pendingAction==='complete'?'Completing job…':flow.otherActive.length?'Complete & return to active work':flow.next?'Complete & open next job':'Complete bay job';
    const help=unsaved?'Save your notes before completing this bay.':detail?.status==='stoppage'?'Resume this job before completing the bay.':ready?'All items are done. Complete this bay to continue.':'Tick off every item in this bay before completing the job.';
    return `<footer class="fitter-finish" aria-label="Finish current job and continue"><div class="fitter-finish-action"><div><h3>Finish this bay</h3><p>${esc(help)}</p></div><button type="button" class="fitter-primary" data-fitter-action="complete" ${locked||!editable||!ready?'disabled':''}>${completeLabel}</button></div><div class="fitter-next" aria-label="Next job preview"><span class="fitter-kicker">Next job</span>${flow.next?`${jobPreview(flow.next)}<p>${flow.otherActive.length?'Available after your active jobs are completed.':'Opens automatically after the current job is completed.'} You choose when to start it.</p>`:'<p>No further jobs assigned at the moment.</p>'}</div>${flow.upcoming.length?`<details class="fitter-upcoming"><summary>Later jobs (${flow.upcoming.length})</summary>${flow.upcoming.map(j=>`<div class="fitter-later-job">${jobPreview(j)}</div>`).join('')}</details>`:''}</footer>`;
  }
  // r500: the stoppage (pause) panel; shown under the item whose Pause was pressed, otherwise under the job buttons.
  function stopPanelHtml() {
    const locked = saving || loading || service.retryPending || busPending();
    return `<div class="fitter-stop-panel" role="group" aria-label="Record a workshop stoppage"><p class="fitter-stop-help"><strong>Pause this job</strong> · the job clock stops for every item in this bay until you press Resume.</p><label for="fitter-stop-type">Stoppage type<select id="fitter-stop-type" ${locked?'disabled':''}><option ${stopType==='Parts'?'selected':''}>Parts</option><option ${stopType==='Other'?'selected':''}>Other</option></select></label><label for="fitter-stop-reason">What is holding up the work?<textarea id="fitter-stop-reason" rows="3" maxlength="1900" ${locked?'disabled':''}>${esc(stopReason)}</textarea></label><button type="button" data-fitter-confirm-stop ${locked?'disabled':''}>Record stoppage</button><button type="button" data-fitter-cancel-stop ${locked?'disabled':''}>Cancel</button></div>`;
  }
  function lineCard(line, index, editable, viewOnly=false) {

    if(line.conversion && !conversionUsesSimpleTick(line)) return root.PdcConversions.html(line,{editable:editable&&!saving&&!loading&&!service.retryPending&&!busPending(),controller:['operator','administrator'].includes(root.PDC_AUTH_CONTEXT?.role),booking:selected});
    const draft = drafts.get(`${selected}:${line.line_identity}`), note = draft?.note ?? line.note;
    const disabled = !editable || saving || loading || service.retryPending || busPending();
    const clock=timerModel(detail,timingOptions());
    // r500: Pause on started jobs, Resume on stopped jobs (own bay items only).
    const pauseControl=viewOnly||(!editable&&detail?.status!=='stoppage')?'':detail?.status==='started'?'pause':detail?.status==='stoppage'?'resume':'';
    const pauseDisabled=saving||loading||service.retryPending||busPending()||!connected||!service.canWrite();
    const panel=stopOpen&&stopFrom===line.line_identity?stopPanelHtml():'';
    // r493: a section bar pauses (amber) whenever the job clock is not counting, as bay items already did.
    if(line.conversion) return conversionTicksHtml(line, index, {editable, disabled, booking:selected, paused:detail?.status!=='started'||clock.tone!=='running', noteDrafts:conversionNotes, open:!conversionClosed.has(`${selected}|${line.line_identity}`), pauseControl, pauseDisabled})+panel;
    return fitterLineCardHtml(line, index, {editable, disabled, note, open: !!draft, paused: clock.tone!=='running', jobSeconds: Number.isFinite(clock.seconds)?clock.seconds:NaN, pauseControl, pauseDisabled})+panel;
  }
  // r493: started items show amber Paused while the job clock is held
  // (stoppage, break, closure or end of day, waiting allocation).
  function fitterPausedLabel(d) {
    if(!d || !['started','stoppage','queued'].includes(d.status)) return '';
    const clock=timerModel(d,timingOptions());
    return clock.tone==='paused' ? clock.label : '';
  }
  function render() {
    const target = host(); if (!target || !active()) return;
    const focus = doc.activeElement, focusId = focus?.id, selection = focus?.selectionStart != null ? [focus.selectionStart,focus.selectionEnd] : null;
    const openNotes = new Set([...target.querySelectorAll('.fitter-notes[open] textarea')].map(n=>n.dataset.fitterNote));
    const job = jobs.find(j=>j.id===selected), locked = saving || loading || service.retryPending || busPending();
    const flow = fitterJobFlow(jobs,selected);
    const completedHere = handover?.bookingId===selected;
    const handoverText = !handover?'':!connected||completedHere?`${handover.stock} completed. Refreshing your next assigned job…`:!job?`${handover.stock} completed. No more jobs are assigned at the moment.`:['planned','queued'].includes(job.status)?`${handover.stock} completed. Your next job is ready below. Press Start job when you are ready.`:`${handover.stock} completed. Your other active job is shown below.`;
    const savingLabel=({start:'Starting job…',resume:'Resuming job…',stop:'Recording stoppage…',complete:'Completing job…'}[pendingAction]||'Saving to workshop…');
    const editable = connected && !completedHere && service.canWrite() && detail?.status === 'started';
    const lines = detail?.lines || [], own = lines.filter(l=>l.stage_code===detail.stage_code), other = lines.filter(l=>l.stage_code!==detail.stage_code);
    target.innerHTML = `<div class="fitter-app"><header class="fitter-header"><div><h1>Fitters bay</h1><p>Your work, shared with the workshop planner</p></div><nav aria-label="Fitter navigation"><button type="button" data-fitter-refresh ${locked ? 'disabled' : ''}>Refresh</button><button type="button" data-fitter-signout ${saving ? 'disabled' : ''}>Sign out</button></nav></header>
      <div class="fitter-toolbar"><label for="fitter-mechanic">Mechanic<select id="fitter-mechanic" ${locked ? 'disabled' : ''}><option value="">Select your name</option>${roster.map(t=>`<option value="${esc(t.id)}" ${t.id===mechanic?'selected':''}>${esc(t.name)}</option>`).join('')}</select></label><p class="fitter-sync" role="status">${saving ? savingLabel : loading ? 'Refreshing…' : connected ? `Connected · Updated ${esc(new Date(lastSync).toLocaleTimeString('en-AU',{timeZone:'Australia/Perth',hour:'numeric',minute:'2-digit',second:'2-digit'}))}` : 'Not connected · Changes unavailable'}</p></div>
      ${updateReady ? `<div class="fitter-notice fitter-update" role="status">A new version of the Fitters bay is ready. <button type="button" data-fitter-update>Update now</button></div>` : ''}
      ${message ? `<div class="fitter-notice" role="status">${esc(message)}</div>` : ''}
      ${handoverText ? `<div class="fitter-handover" role="status">${esc(handoverText)}</div>` : ''}
      ${service.retryPending ? '<div class="fitter-warning">The last save is unconfirmed. Retrying checks the same action and cannot apply it twice. <button type="button" data-fitter-retry>Check / retry last save</button></div>' : ''}
      ${busPending() ? '<div class="fitter-warning">The supplier save is unconfirmed. Check the same request before making another change. <button type="button" data-bus-fitter-retry>Check / retry supplier save</button></div>' : ''}
      ${!service.canWrite() && connected ? '<p class="fitter-warning">View only. An operator account is needed to record work.</p>' : ''}
      ${mechanic ? `<p class="fitter-bay-summary">${bays.length ? bays.map(b=>`${esc(b.stage)} · ${esc(bayText(STAGE_BY_NAME[b.stage], b.number))}${b.active?'':' (inactive)'}`).join(' / ') : 'Jobs individually assigned to this mechanic appear below.'}</p>` : ''}
      ${flow.otherActive.length ? `<details class="fitter-active-jobs"><summary>Other active jobs (${flow.otherActive.length})</summary>${flow.otherActive.map(j=>`<button type="button" data-fitter-job="${esc(j.id)}" ${locked?'disabled':''}>${esc(j.stock)} · ${esc(j.stage_name)} / ${esc(bayText(j.stage_code, j.bay_number))} · ${esc(state(j.status))}</button>`).join('')}</details>` : ''}
      <div class="fitter-layout">
      <section class="fitter-work" aria-label="Selected job">${job && detail ? `<div class="fitter-job-heading"><p class="fitter-kicker">${esc(job.stage_name)} · ${esc(bayText(job.stage_code, job.bay_number))} · ${esc(state(detail.status))}</p><h2>${esc(job.stock)} <span>${esc(job.job_card)}</span></h2><p>${esc(job.customer)} · ${esc(job.vehicle)}</p><p class="fitter-time">${esc(time(job.start_at))} – ${esc(time(job.end_at))}</p>${timerHtml(detail,timingOptions())}${progressHtml(detail.progress,false,{paused:fitterPausedLabel(detail)})}<p>${detail.progress.completed_lines} of ${detail.progress.total_lines} items complete · Progress uses approved work hours.</p></div>
      ${detail.status==='stoppage' ? `<div class="fitter-warning"><strong>Job stopped</strong><p>${esc(detail.stoppage_reason)}</p></div>` : ''}
      <div class="fitter-actions">${['planned','queued'].includes(detail.status) ? `<button class="fitter-primary" data-fitter-action="start" ${locked||!connected||!service.canWrite()?'disabled':''}>${(saving||loading)&&pendingAction==='start'?'Starting job…':'Start job'}</button><p>Start this job first. Its other unstarted bookings and affected queues move later where needed.</p>` : detail.status==='stoppage' ? `<button class="fitter-primary" data-fitter-action="resume" ${locked||!connected||!service.canWrite()?'disabled':''}>${(saving||loading)&&pendingAction==='resume'?'Resuming job…':'Resume job'}</button>` : detail.status==='started' ? `<button data-fitter-stop ${locked||!editable?'disabled':''}>Pause · parts / other stoppage</button>` : ''}</div>
      ${stopOpen&&!own.some(l=>l.line_identity===stopFrom) ? stopPanelHtml() : ''}
      ${detail.progress.unknown_hours ? '<p class="fitter-warning">Some items need approved hours. Ask the controller to review these before completing the bay job.</p>' : ''}
      <h3>Items for this bay</h3><div class="fitter-lines">${own.map((l,i)=>lineCard(l,i,editable)).join('') || '<p class="fitter-empty">No approved operation lines for this bay. Ask the controller to review the vehicle.</p>'}</div>
      ${detail.supplier_lines?.length && root.PdcBusWorkflow ? `<section class="fitter-supplier-checks"><h3>Supplier work — physically check the vehicle</h3><p>Check fitted work yourself. A supplier report alone does not complete these lines.</p>${root.PdcBusWorkflow.supplierHtml(detail.supplier_lines,{vehicleId:detail.vehicle_id || job.vehicle_id,editable:editable&&!locked,controller:false,bookingId:selected,technicianId:mechanic})}</section>` : ''}
      ${nextJobHtml(flow,locked,editable)}
      ${other.length ? `<details class="fitter-other${editable ? '' : ' is-view'}" ${editable ? 'open' : ''}><summary>${editable ? `Other station items (${other.length})` : `All other vehicle items (${other.length}) · View only`}</summary>${editable ? '<p class="fitter-other-note">Tick Start, then Done, if this bay is doing that work. When every item for a station is Done, that station is ticked off on the board. Untick to undo.</p>' : ''}${other.map((l,i)=>lineCard(l,own.length+i,editable && !l.external_work && !l.conversion,true)).join('')}</details>` : ''}
      <p class="fitter-help">Complete this bay after ticking off its work. Your next assigned job opens automatically; QC inspection remains a separate step.</p>` : `<div class="fitter-empty">${loading ? 'Loading your job…' : !mechanic ? 'Select your mechanic name to see your current job.' : 'No more jobs assigned. New work will appear here when the controller books it.'}</div>`}</section></div></div>`;
    target.querySelectorAll('.fitter-notes textarea').forEach(n=>{ if(openNotes.has(n.dataset.fitterNote)) n.closest('details').open=true; });
    if (focusId && selection) { const next=doc.getElementById(focusId); next?.focus({preventScroll:true}); next?.setSelectionRange?.(...selection); }
    bind(target);
  }
  function viewKey() { return JSON.stringify([roster, mechanic, jobs, bays, selected, detail, connected, message],(key,value)=>['timer','generated_at','server_now'].includes(key)?undefined:value); }
  async function refresh({ background = false, forceRoster = false } = {}) {
    if (!active() || loading || saving || service.retryPending || busPending() || (background && (doc.hidden || refreshing))) return;
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
        if(rosterResult.refresh_supported===true) {
          const snapshot=await service.refresh(nextMechanic,selected,{force:!background});
          if(generation!==loadGeneration || mechanicBefore!==mechanic || !active())return;
          nextJobs=snapshot.jobs;nextBays=snapshot.bays;nextSelected=snapshot.selected;nextDetail=snapshot.detail;
        } else {
        // Older deployments keep the existing authoritative read path until the
        // roster explicitly advertises the incremental endpoint.
        const list = await service.jobs(nextMechanic);
        if (generation!==loadGeneration || mechanicBefore!==mechanic || !active()) return;
        nextJobs=list.jobs; nextBays=list.bays;
        // Only the freshly assigned queue can supply the next job. The preview
        // may have changed while the fitter was completing the current work.
        nextSelected=fitterJobFlow(nextJobs,selected).current?.id || '';
        nextDetail=nextSelected ? await service.job(nextMechanic,nextSelected) : null;
        if (generation!==loadGeneration || !active()) return;
        }
      }
      // Apply the matching list and operation scope together. An interaction
      // superseding a background read must never receive its late job details.
      if(selected!==nextSelected) { stopOpen=false; stopReason=''; }
      roster=nextRoster; mechanic=nextMechanic; jobs=nextJobs; bays=nextBays;
      selected=nextSelected; detail=nextDetail; detailReceivedAt=clockNow();
      if(!service.retryPending || timerFreeze?.bookingId!==nextSelected) timerFreeze=null;
      connected=true; lastSync=Date.now();
      if(message===readErrorMessage) message='';
      readErrorMessage='';
    } catch(e) { if (generation===loadGeneration) { freezeTimer(); connected=false; message=readErrorMessage=e.message; } }
    finally { if (generation===loadGeneration) {
      loading=false; refreshing=false;
      if (!background || before!==viewKey()) render();
      else {
        const sync=host()?.querySelector('.fitter-sync');
        if(sync && connected) sync.textContent=`Connected · Updated ${new Date(lastSync).toLocaleTimeString('en-AU',{timeZone:'Australia/Perth',hour:'numeric',minute:'2-digit',second:'2-digit'})}`;
        updateTimer();
      }
      if (scrollToCurrent && connected && handover?.bookingId!==selected) {
        scrollToCurrent=false;
        const heading=host()?.querySelector('.fitter-job-heading h2, .fitter-empty');
        heading?.setAttribute?.('tabindex','-1');
        heading?.focus?.({preventScroll:true});
        (host()?.querySelector('.fitter-handover') || heading)?.scrollIntoView?.({block:'start'});
      }
    } }
  }
  async function act(action, lineId, completed, retry=false, conversionChange=null) {
    if (saving || loading || busPending() || (!retry && (!connected || !detail))) return;
    const line=detail?.lines.find(l=>l.line_identity===lineId), key=`${selected}:${lineId}`, draft=drafts.get(key);
    if (draft && draft.scope!==line?.scope_hash && !String(action).startsWith('item_')) { message='This item changed while you were writing. Review it and copy your note before refreshing.'; render(); return; }
    if (action==='stop' && stopReason.trim().length<3) { message='Enter a short reason for the stoppage.'; render(); return; }
    const body={p_technician_id:mechanic,p_booking_id:selected,p_expected_version:detail?.version,
      p_catalog_hash:detail?.catalog_hash,p_action:action,p_line_identity:lineId||null,
      p_completed:completed??null,p_note:conversionChange?JSON.stringify(conversionChange):action==='stop'?`${stopType}: ${stopReason.trim()}`:String(action).startsWith('item_')?null:line?(draft?.note??line.note??''):null};
    if (!retry) pendingDraftKey = lineId && !String(action).startsWith('item_') ? key : '';
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
      if (result.action==='conversion') { root.PdcConversions?.confirmSave(); if(pendingConversionNote) conversionNotes.delete(pendingConversionNote); }
      if (lineId && !String(result.action).startsWith('item_')) drafts.delete(key);
      if (retry && pendingDraftKey) drafts.delete(pendingDraftKey);
      pendingDraftKey = '';
      stopOpen=false; stopReason='';
      if(result.action==='complete') {
        handover={bookingId:result.booking_id||selected,stock:jobs.find(j=>j.id===selected)?.stock||'Bay job'};
        scrollToCurrent=true;
      } else handover=null;
      const cross=result.cross_station;
      const crossText=cross?.ticked?`Saved. ${cross.stage_name||'That station'} is ticked off on the board.`
        :cross?.reopened?`Saved. ${cross.stage_name||'That station'} is open again on the board.`
        :cross?.reason==='hours_need_review'?`Saved. ${cross.stage_name||'That station'} still needs approved hours before it can be ticked off.`
        :'';
      message=result.action==='complete'?'':result.action==='start'?startConfirmationMessage(result):result.action==='resume'?'Job resumed on the workshop planner.':crossText||'Saved to the workshop planner.';
      connected=false;
    } catch(e) { message=e.message; if(e.code!=='busy') connected=false; }
    finally {
      saving=false; if(!service.retryPending) pendingConversionNote='';
      if(service.retryPending) { pendingAction=''; render(); }
      else { await refresh(); pendingAction=''; }
    }
  }
  async function saveSupplier(change, retry=false) {
    const bus=busService();
    if (!bus || saving || loading || service.retryPending || (!retry && (!connected || !detail || bus.retryPending))) return;
    const owner=bus.authorityKey(), booking=selected, stage=detail?.stage_code;
    const isCurrent=()=>owner===bus.authorityKey()&&booking===selected;
    loadGeneration++; refreshing=false; freezeTimer(); saving=true; pendingAction='supplier'; message='';
    if (!retry) supplierDraftKey=change.draftKey || '';
    render();
    try {
      await (retry ? bus.retry() : bus.supplier(change));
      if (!isCurrent()) return;
      root.PdcBusWorkflow.confirmSupplierSave(supplierDraftKey); supplierDraftKey='';
      service.invalidateReads(); connected=false; message='Supplier work verification saved.';
      root.dispatchEvent(new root.CustomEvent('pdc-fitter-workshop-saved',{detail:{bookingId:booking,stageCode:stage,action:'supplier'}}));
    } catch(e) { if(isCurrent()){message=e.message; connected=false;} }
    finally { saving=false; if(isCurrent()){pendingAction=''; if(bus.retryPending) render(); else await refresh();} }
  }
  function bind(target) {
    root.PdcBusWorkflow?.bindSuppliers(target,change=>void saveSupplier(change));
    target.querySelector('[data-bus-fitter-retry]')?.addEventListener('click',()=>void saveSupplier(null,true));
    root.PdcConversions?.bind(target,(lineId,change)=>act('conversion',lineId,null,false,change));
    const on=(selector,event,fn)=>target.querySelectorAll(selector).forEach(n=>n.addEventListener(event,fn));
    on('#fitter-mechanic','change',e=>{ mechanic=e.target.value; selected=''; detail=null; handover=null; scrollToCurrent=false; stopOpen=false; stopReason=''; message=''; void refresh(); });
    on('[data-fitter-refresh]','click',()=>{ message=''; void refresh({forceRoster:true}); });
    on('[data-fitter-job]','click',e=>{ if(saving||loading||service.retryPending) return; selected=e.currentTarget.dataset.fitterJob; detail=null; handover=null; scrollToCurrent=false; stopOpen=false; stopReason=''; message=''; void refresh(); });
    on('[data-fitter-signout]','click',()=>doc.querySelector('#pdc-auth-signout')?.click());
    on('[data-fitter-action]','click',e=>void act(e.currentTarget.dataset.fitterAction));
    on('[data-fitter-line]','change',e=>{ const n=e.currentTarget; const checked=n.checked; n.checked=!checked; void act('line',n.dataset.fitterLine,checked); });
    on('[data-fitter-item-start]','change',e=>{ const n=e.currentTarget, checked=n.checked; n.checked=!checked; void act(checked?'item_start':'item_reset',n.dataset.fitterItemStart); });
    on('[data-fitter-note]','input',e=>{ const id=e.target.dataset.fitterNote, l=detail.lines.find(l=>l.line_identity===id); drafts.set(`${selected}:${id}`,{note:e.target.value,scope:l.scope_hash}); target.querySelector('[data-fitter-action="complete"]')?.setAttribute('disabled',''); });
    on('[data-fitter-save-note]','click',e=>{ const id=e.currentTarget.dataset.fitterSaveNote; void act('line',id,detail.lines.find(l=>l.line_identity===id).completed); });
    on('[data-fitter-stop]','click',()=>{ stopOpen=true; stopFrom=''; render(); doc.getElementById('fitter-stop-reason')?.focus(); });
    // r500: Pause on an item opens the same stoppage panel under that item.
    on('[data-fitter-pause]','click',e=>{ if(saving||loading) return; stopOpen=true; stopFrom=e.currentTarget.dataset.fitterPause||''; render(); const box=doc.getElementById('fitter-stop-reason'); box?.scrollIntoView?.({block:'center'}); box?.focus?.({preventScroll:true}); });
    on('#fitter-stop-type','change',e=>{stopType=e.target.value;});
    on('#fitter-stop-reason','input',e=>{stopReason=e.target.value;});
    on('[data-fitter-confirm-stop]','click',()=>void act('stop'));
    on('[data-fitter-cancel-stop]','click',()=>{stopOpen=false;render();});
    on('[data-fitter-retry]','click',()=>void act(null,null,null,true));
    on('[data-fitter-update]','click',()=>updateNow());
    on('[data-conversion-step]','change',e=>{ const n=e.currentTarget, checked=n.checked; n.checked=!checked;
      // Start ticks begin the section, Done records its actual time; unticking either resets it.
      const step=!checked?'reset':n.dataset.conversionStep==='done'?'done':'start';
      void act('conversion',n.dataset.conversionLine,null,false,{mode:'tick',section:n.dataset.conversionSection,step}); });
    on('[data-conversion-note]','input',e=>{ conversionNotes.set(e.target.dataset.conversionNote,e.target.value); target.querySelector('[data-fitter-action="complete"]')?.setAttribute('disabled',''); });
    on('[data-conversion-save-note]','click',e=>{ const key=e.currentTarget.dataset.conversionSaveNote, box=target.querySelector(`[data-conversion-note="${root.CSS?.escape?root.CSS.escape(key):key}"]`); if(!box) return;
      pendingConversionNote=key; void act('conversion',box.dataset.conversionLine,null,false,{mode:'tick',section:box.dataset.conversionSection,step:'note',note:box.value}); });
    on('[data-conversion-list]','toggle',e=>{ const k=e.currentTarget.dataset.conversionList; if(e.currentTarget.open) conversionClosed.delete(k); else conversionClosed.add(k); });
  }
  api.open = () => { render(); if(!initialized) {initialized=true;void refresh();} };
  api.close = () => { freezeTimer(); loadGeneration++; service.invalidateReads(); loading=false; refreshing=false; initialized=false; connected=false; };
  const reset=()=>{root.PdcBusWorkflow?.reset();supplierDraftKey='';service.invalidate();api.close();roster=[];mechanic='';jobs=[];bays=[];selected='';detail=null;handover=null;scrollToCurrent=false;detailReceivedAt=0;timerFreeze=null;pendingAction='';stopOpen=false;stopReason='';drafts.clear();conversionNotes.clear();conversionClosed.clear();root.PdcConversions?.reset();message='';render();};
  root.addEventListener('pdc-auth-locked',reset);
  root.addEventListener('pdc-auth-ready',()=>{if(active())api.open();});
  root.addEventListener('offline',()=>{freezeTimer();loadGeneration++;loading=false;refreshing=false;connected=false;message='Offline. Saved work is shown; reconnect before changing this job.';render();});
  root.addEventListener('online',()=>{if(active())void refresh();});
  root.addEventListener('focus',()=>{if(active()&&!targetBeingEdited())void refresh({background:true});});
  doc.addEventListener('visibilitychange',()=>{if(!doc.hidden)void checkForUpdate();if(!doc.hidden&&active()&&!targetBeingEdited())void refresh({background:true});});
  setInterval(()=>{if(active()&&!doc.hidden&&!targetBeingEdited())void refresh({background:true});},10000);
  setInterval(updateTimer,1000);
  function unsavedWork() { return saving || loading || drafts.size > 0 || conversionNotes.size > 0 || service.retryPending || busPending() || root.PdcConversions?.hasDrafts() || root.PdcBusWorkflow?.hasDrafts() || targetBeingEdited(); }
  function updateNow() {
    if (unsavedWork()) { message = 'Save your notes and wait for the last save, then tap Update now.'; render(); return; }
    if (updateStarted) return; updateStarted = true;
    try { root.sessionStorage?.setItem(RESUME_KEY, JSON.stringify({ mechanic, selected, at: Date.now() })); } catch { /* reload still updates */ }
    root.location.reload();
  }
  async function checkForUpdate({ force = false } = {}) {
    if (!loadedToken || !active() || doc.hidden || typeof root.fetch !== 'function') return;
    if (updateReady) { if (!unsavedWork()) updateNow(); return; }
    const now = Date.now(); if (!force && now - lastUpdateCheck < UPDATE_CHECK_MS) return; lastUpdateCheck = now;
    try {
      const response = await root.fetch('index.html', { cache: 'no-store', credentials: 'same-origin' });
      if (!response.ok) return;
      const live = fitterScriptToken(await response.text());
      if (!live || live === loadedToken) return;
      updateReady = true;
      if (unsavedWork()) render(); else updateNow();
    } catch { /* offline or blocked: try again next time */ }
  }
  api.checkForUpdate = checkForUpdate;
  setInterval(() => void checkForUpdate(), 60000);
  function targetBeingEdited() { return root.PdcBusWorkflow?.hasDrafts() || root.PdcConversions?.hasDrafts() || conversionNotes.size>0 || (host()?.contains(doc.activeElement) && /INPUT|TEXTAREA|SELECT/.test(doc.activeElement.tagName)); }
  // Controllers reset a forgotten running item from the planner card.
  doc.addEventListener('click',async e=>{
    const n=e.target?.closest?.('[data-fitter-item-reset]'); if(!n) return;
    e.preventDefault(); e.stopPropagation();
    if(!['operator','administrator'].includes(root.PDC_AUTH_CONTEXT?.role)) { root.alert?.('Only a controller can reset a running item.'); return; }
    const reason=root.prompt?.(`Reset "${n.dataset.fitterItemName}" to not started? Enter a short reason (for example: forgot to tick Done).`);
    if(reason==null) return;
    if(reason.trim().length<3) { root.alert?.('Enter a reason of at least 3 characters.'); return; }
    n.disabled=true;
    try {
      const result=await service.resetItem({p_booking_id:n.dataset.fitterItemReset,p_line_identity:n.dataset.fitterItemLine,p_section:n.dataset.fitterItemSection||null,p_reason:reason.trim()});
      root.dispatchEvent(new root.CustomEvent('pdc-fitter-workshop-saved',{detail:{bookingId:result.booking_id,action:'item_reset',revision:result.revision}}));
    } catch(err) { n.disabled=false; root.alert?.(err.message); }
  },true);
  root.addEventListener('beforeunload',e=>{if(saving||drafts.size||conversionNotes.size||root.PdcConversions?.hasDrafts()||root.PdcBusWorkflow?.hasDrafts()||busPending()||service.retryPending){e.preventDefault();e.returnValue='';}});
})(typeof window !== 'undefined' ? window : globalThis);
