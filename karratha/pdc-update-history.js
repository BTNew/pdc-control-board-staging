(function (root) {
  'use strict';
  const FEEDS = Object.freeze([
    { key:'broome_navision', label:'Broome Navision Update' },
    { key:'pilbara_navision', label:'Pilbara Navision Update' },
    { key:'other_navision', label:'Other codes Navision Update' },
    { key:'service_codes', label:'Service Codes update' },
    { key:'parts_info', label:'Parts info update' }
  ]);
  const LABELS = Object.fromEntries(FEEDS.map(feed => [feed.key, feed.label]));
  const knownFeed = key => Object.prototype.hasOwnProperty.call(LABELS,key);
  const escape = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  function validTime(value) {
    // Require an explicit timezone so dates cannot change with the viewer's device setting.
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) return null;
    const time = Date.parse(value);
    return Number.isFinite(time) ? new Date(time).toISOString() : null;
  }
  function formatDate(value) {
    const time = validTime(value);
    return time ? new Intl.DateTimeFormat('en-AU', {timeZone:'Australia/Perth',day:'numeric',month:'short',year:'numeric',hour:'numeric',minute:'2-digit'}).format(new Date(time)) : 'Not recorded';
  }
  function safeCount(value) {
    return ['number','string'].includes(typeof value) && String(value).trim() !== '' && Number.isSafeInteger(Number(value)) && Number(value) >= 0 ? Number(value) : null;
  }
  function status(value) {
    const name = String(value || '').toLowerCase();
    if (['completed','complete','success','succeeded','applied','processed'].includes(name)) return {label:'Completed',tone:'success',completed:true};
    if (name === 'completed_with_warnings') return {label:'Completed · review items',tone:'pending',completed:true};
    if (name === 'preview') return {label:'Preview only',tone:'neutral'};
    if (name === 'rolled_back') return {label:'Rolled back',tone:'failure'};
    if (name === 'not_recorded') return {label:'Not recorded',tone:'neutral'};
    if (['failed','error','rejected'].includes(name)) return {label:'Failed',tone:'failure'};
    if (['pending','queued','processing','running','in_progress'].includes(name)) return {label:'In progress',tone:'pending'};
    if (['partial','partially_completed'].includes(name)) return {label:'Partially completed',tone:'pending'};
    if (['skipped','ignored','duplicate'].includes(name)) return {label:'Skipped',tone:'neutral'};
    return {label:'Status unavailable',tone:'neutral'};
  }
  function normalizeReport(report) {
    if (!report || report.ok !== true || !Array.isArray(report.feeds)) throw new Error('Update history unavailable');
    const byKey = new Map(report.feeds.filter(feed => feed && knownFeed(feed.key)).map(feed => [feed.key,feed]));
    return {
      generated_at:validTime(report.generated_at),
      feeds:FEEDS.map(feed => {
        const row = byKey.get(feed.key) || {};
        const latestSuccess = validTime(row.last_success_at), latestAttempt = validTime(row.last_attempt_at);
        const successStatus = status(row.last_success_status || (latestSuccess === latestAttempt && status(row.last_status).completed ? row.last_status : 'completed'));
        return {...feed,last_success_at:latestSuccess,last_attempt_at:latestAttempt,last_status:status(row.last_status),last_success_status:successStatus.completed ? successStatus : status('completed'),record_count:safeCount(row.record_count),detail:typeof row.detail === 'string' ? row.detail : ''};
      }),
      history:(Array.isArray(report.history) ? report.history : []).filter(row => row && knownFeed(row.feed_key)).map(row => ({
        label:LABELS[row.feed_key],completed_at:validTime(row.completed_at),status:status(row.status),record_count:safeCount(row.record_count),detail:typeof row.detail === 'string' ? row.detail : ''
      })).sort((a,b) => (Date.parse(b.completed_at) || 0) - (Date.parse(a.completed_at) || 0)).slice(0,20)
    };
  }
  function timeHtml(value) { return value ? `<time datetime="${escape(value)}">${escape(formatDate(value))}</time>` : 'No completed update recorded'; }
  function reportHtml(report) {
    const cards = report.feeds.map(feed => {
      const newerAttempt = feed.last_attempt_at && (!feed.last_success_at || Date.parse(feed.last_attempt_at) > Date.parse(feed.last_success_at));
      const incomplete = newerAttempt && !feed.last_status.completed;
      const badge = feed.last_success_at ? `<span class="update-history-badge is-${feed.last_success_status.tone}">${escape(feed.last_success_status.label)}</span>` : '<span class="update-history-badge is-neutral">Not recorded</span>';
      return `<article class="update-history-feed"><div class="update-history-feed-heading"><h3>${escape(feed.label)}</h3>${badge}</div><p class="update-history-caption">Latest completed update</p><p class="update-history-date">${timeHtml(feed.last_success_at)}</p>${feed.last_success_at && feed.record_count !== null ? `<p class="update-history-count">${feed.record_count.toLocaleString('en-AU')} source rows</p>` : ''}${incomplete ? `<p class="update-history-attempt"><strong>${escape(feed.last_status.label)}</strong> · ${escape(formatDate(feed.last_attempt_at))}<span>This attempt has not replaced the latest completed update.</span></p>` : ''}${feed.detail ? `<p class="update-history-detail">${escape(feed.detail)}</p>` : ''}</article>`;
    }).join('');
    const rows = report.history.map(row => `<tr><td data-label="Update">${escape(row.label)}</td><td data-label="Completed">${row.completed_at ? timeHtml(row.completed_at) : 'Not recorded'}</td><td data-label="Status"><span class="update-history-badge is-${row.status.tone}">${escape(row.status.label)}</span></td><td data-label="Source rows">${row.record_count === null ? '—' : row.record_count.toLocaleString('en-AU')}</td><td data-label="Details">${escape(row.detail) || '—'}</td></tr>`).join('');
    return `<div class="update-history-feeds">${cards}</div><section class="update-history-recent"><h3>Recent update history</h3><p class="update-history-caption">Most recent recorded updates · Perth time</p>${rows ? `<div class="update-history-table-wrap"><table class="update-history-table"><thead><tr><th scope="col">Update</th><th scope="col">Completed</th><th scope="col">Status</th><th scope="col">Source rows</th><th scope="col">Details</th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p class="update-history-empty">No update history has been recorded yet.</p>'}</section>`;
  }
  function createController(options) {
    let owner = '', generation = 0, active = false, locked = false;
    let state = {loading:false,report:null,error:''};
    const context = () => options.context() || {};
    const allowed = ctx => !locked && !!ctx.userId && ctx.role === 'administrator' && !!ctx.token;
    const identity = ctx => [ctx.userId,ctx.role,ctx.token,ctx.url,ctx.key].join('\u0000');
    function emit() { options.render({...state,active,allowed:allowed(context())}); }
    function clear() { generation++; state = {loading:false,report:null,error:''}; }
    function syncAccess() {
      const ctx = context(), nextOwner = allowed(ctx) ? identity(ctx) : '';
      if (nextOwner !== owner || !nextOwner) { owner = nextOwner; clear(); }
      emit();
      return !!nextOwner;
    }
    async function refresh() {
      if (!syncAccess() || !active || state.loading) return;
      const ctx = {...context()}, requestOwner = identity(ctx), requestId = ++generation;
      state = {...state,loading:true,error:''}; emit();
      const current = () => requestId === generation && active && allowed(context()) && requestOwner === identity(context());
      try {
        const response = await options.request(ctx);
        if (!current()) { if (requestId === generation) syncAccess(); return; }
        state = {loading:false,report:normalizeReport(response),error:''};
      } catch (_) {
        if (!current()) { if (requestId === generation) syncAccess(); return; }
        state = {...state,loading:false,error:'Could not load update history. Please try Refresh.'};
      }
      if (current()) emit();
    }
    return {
      open() {
        const alreadyActive = active; active = true;
        if (!syncAccess() || (alreadyActive && state.report)) return Promise.resolve();
        return refresh();
      },
      close() { active = false; clear(); emit(); },
      reset() { locked = true; owner = ''; active = false; clear(); emit(); },
      ready() { locked = false; syncAccess(); },
      syncAccess, refresh,
      getState() { return {...state,active,allowed:allowed(context())}; }
    };
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {FEEDS,validTime,formatDate,safeCount,status,normalizeReport,reportHtml,createController};
  if (!root.document) return;
  const doc = root.document;
  function render(state) {
    const nav = doc.getElementById('nav-update-history');
    if (nav) nav.hidden = !state.allowed;
    const view = doc.getElementById('update-history');
    if (view) view.hidden = !state.allowed;
    const host = doc.getElementById('update-history-content');
    if (!host) return;
    if (!state.allowed || !state.active) { host.replaceChildren(); return; }
    const restoreFocus = host.contains(doc.activeElement) && doc.activeElement?.hasAttribute('data-update-history-refresh');
    host.innerHTML = `<div class="update-history-header"><div><h2>Update history</h2><p>Latest completed imports for each data feed. All dates and times are Perth time.</p></div><button type="button" class="small-button" data-update-history-refresh ${state.loading ? 'disabled' : ''}>${state.loading ? 'Refreshing…' : 'Refresh'}</button></div><p class="update-history-status${state.error ? ' is-error' : ''}" role="status" aria-live="polite">${state.error ? escape(state.error) + (state.report ? ' Showing the previously loaded history; it may be out of date.' : '') : state.loading ? 'Loading update history…' : state.report?.generated_at ? 'Checked '+escape(formatDate(state.report.generated_at)) : ''}</p><div aria-busy="${state.loading}">${state.report ? reportHtml(state.report) : state.loading ? '<p class="update-history-empty">Checking the latest updates…</p>' : ''}</div>`;
    const refresh = host.querySelector('[data-update-history-refresh]');
    refresh?.addEventListener('click', () => controller.refresh());
    if (restoreFocus && !state.loading) refresh?.focus({preventScroll:true});
  }
  const controller = createController({
    context:() => ({userId:root.PDC_AUTH_CONTEXT?.userId,role:root.PDC_AUTH_CONTEXT?.role,token:root.__pdcCachedAccessToken,url:root.PDC_SUPABASE_CONFIG?.url,key:root.PDC_SUPABASE_CONFIG?.publishableKey}),
    request:async ctx => {
      if (!ctx.url || !ctx.key) throw new Error('Service unavailable');
      const response = await root.fetch(ctx.url.replace(/\/$/,'')+'/rest/v1/rpc/get_pdc_update_history',{
        method:'POST',headers:{'Content-Type':'application/json',apikey:ctx.key,Authorization:'Bearer '+ctx.token},body:'{}',cache:'no-store'
      });
      if (!response.ok) throw new Error('Update history unavailable');
      return response.json();
    }, render
  });
  root.PdcUpdateHistory = {open:controller.open,close:controller.close,reset:controller.reset,syncAccess:controller.syncAccess};
  root.addEventListener('pdc-auth-locked',controller.reset);
  root.addEventListener('pdc-auth-ready',() => {
    controller.ready();
    if (doc.getElementById('update-history')?.classList.contains('active')) controller.open();
  });
  controller.syncAccess();
})(typeof window !== 'undefined' ? window : globalThis);
