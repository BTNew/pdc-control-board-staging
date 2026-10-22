/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r489 (F102): Admin > Fitting statistics. Administrators only (nav, view and the RPC all check).
 * Per work category: Done lines in the period, how many were timed (fitter pressed Start, then Done), whole station jobs
 * completed with their average Start work -> Complete clock time, and per line type (job card description) the completed
 * count and the average / median / fastest / slowest time on the job clock against the average allowance.
 * Data: RPC get_pdc_fitting_statistics_489(p_days) (migration 20261023020000). Read only; no vehicle, stock or customer details. */
(function (root) {
  'use strict';
  const VERSION = '2026.10.23.r489';
  const PERIODS = Object.freeze([7, 30, 90, 365]);
  const DEFAULT_DAYS = 30;
  const CATEGORY_LABELS = Object.freeze({
    FITTING:'Fitting', ELECTRICAL:'Electrical', FABRICATION:'Fabrication', HOIST:'Hoist', TINT:'Tint', TYRE:'Tyres',
    PIT_INSPECTION:'Pit', SUBLET:'Sublet', BUS_4X4:'Bus 4×4', BUS_MECHANICAL:'Bus 4×4 · Mechanical', BUS_ACCESSORIES:'Bus 4×4 · Accessories',
    BUS_ELECTRICAL:'Bus 4×4 · Electrical', BUS_QA:'Bus 4×4 · QA', BUS_PIT:'Bus 4×4 · Pit', BUS_WHOLE_JOB:'Bus 4×4 · Whole job',
    JOB_CARD_NOTES:'Job card notes', UNALLOCATED_MAPPING_REVIEW:'Not yet allocated'
  });
  const CATEGORY_ORDER = Object.freeze(['FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','PIT_INSPECTION',
    'BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_WHOLE_JOB','BUS_4X4','SUBLET','JOB_CARD_NOTES','UNALLOCATED_MAPPING_REVIEW']);
  const SORTS = Object.freeze({completed:'Most completed', avg_minutes:'Longest average time', line_type:'Line type A to Z', over:'Most over allowance'});
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const count = value => { const n = Number(value); return Number.isSafeInteger(n) && n >= 0 ? n : 0; };
  const minutes = value => value === null || value === undefined || value === '' ? null : (Number.isFinite(Number(value)) && Number(value) >= 0 ? Number(value) : null);
  const validDays = value => PERIODS.includes(Number(value)) ? Number(value) : DEFAULT_DAYS;
  function categoryLabel(code) {
    const key = String(code || '');
    return CATEGORY_LABELS[key] || (key ? key.toLowerCase().replace(/_/g,' ').replace(/^./, c => c.toUpperCase()) : 'Other');
  }
  function categoryRank(code) { const i = CATEGORY_ORDER.indexOf(code); return i === -1 ? CATEGORY_ORDER.length : i; }
  function formatMinutes(value) {
    const m = minutes(value);
    if (m === null) return '—';
    if (m > 0 && m < 1) return 'under 1m';
    const total = Math.round(m), h = Math.floor(total / 60), rest = total % 60;
    return h ? h + 'h ' + String(rest).padStart(2,'0') + 'm' : rest + 'm';
  }
  function validTime(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) return null;
    const t = Date.parse(value); return Number.isFinite(t) ? new Date(t).toISOString() : null;
  }
  function formatDate(value, withTime = true) {
    const t = validTime(value);
    if (!t) return 'Not recorded';
    const options = withTime ? {timeZone:'Australia/Perth',day:'numeric',month:'short',year:'numeric',hour:'numeric',minute:'2-digit'} : {timeZone:'Australia/Perth',day:'numeric',month:'short',year:'numeric'};
    return new Intl.DateTimeFormat('en-AU', options).format(new Date(t));
  }
  function normalizeLine(line) {
    const completed = count(line?.completed), timed = Math.min(count(line?.timed), completed);
    return {
      line_type: typeof line?.line_type === 'string' && line.line_type.trim() ? line.line_type.trim() : '',
      completed, timed, untimed: completed - timed,
      avg_minutes: timed ? minutes(line.avg_minutes) : null, median_minutes: timed ? minutes(line.median_minutes) : null,
      min_minutes: timed ? minutes(line.min_minutes) : null, max_minutes: timed ? minutes(line.max_minutes) : null,
      avg_allowance_minutes: minutes(line?.avg_allowance_minutes)
    };
  }
  function normalizeReport(report) {
    if (!report || report.ok !== true || !Array.isArray(report.categories)) {
      const error = new Error(report?.code === 'permission_denied' ? 'Administrators only' : 'Fitting statistics unavailable');
      error.code = report?.code || 'unavailable'; throw error;
    }
    const categories = report.categories.filter(c => c && typeof c.category === 'string' && c.category).map(c => {
      const lines = (Array.isArray(c.lines) ? c.lines : []).filter(Boolean).map(normalizeLine).filter(l => l.completed > 0);
      const completed = lines.reduce((s,l) => s + l.completed, 0), timed = lines.reduce((s,l) => s + l.timed, 0);
      const timedMinutes = lines.reduce((s,l) => s + (l.avg_minutes === null ? 0 : l.avg_minutes * l.timed), 0);
      return {category:c.category, label:categoryLabel(c.category), completed, timed,
        avg_line_minutes: timed ? timedMinutes / timed : null,
        jobs_completed: count(c.jobs_completed), job_avg_elapsed_minutes: count(c.jobs_completed) ? minutes(c.job_avg_elapsed_minutes) : null, lines};
    }).filter(c => c.completed > 0 || c.jobs_completed > 0)
      .sort((a,b) => categoryRank(a.category) - categoryRank(b.category) || a.label.localeCompare(b.label));
    return {days: validDays(report.days), generated_at: validTime(report.generated_at), since: validTime(report.since),
      timing_started_at: validTime(report.timing_started_at), categories,
      totals: {completed: categories.reduce((s,c) => s + c.completed, 0), timed: categories.reduce((s,c) => s + c.timed, 0), jobs: categories.reduce((s,c) => s + c.jobs_completed, 0)}};
  }
  function sortLines(lines, sort) {
    const text = (a,b) => (a.line_type || '~').localeCompare(b.line_type || '~', 'en-AU', {sensitivity:'base'});
    const over = l => l.avg_minutes === null || !l.avg_allowance_minutes ? -Infinity : l.avg_minutes - l.avg_allowance_minutes;
    const by = {
      completed: (a,b) => b.completed - a.completed || text(a,b),
      avg_minutes: (a,b) => (b.avg_minutes ?? -1) - (a.avg_minutes ?? -1) || b.completed - a.completed || text(a,b),
      line_type: text,
      over: (a,b) => over(b) - over(a) || b.completed - a.completed || text(a,b)
    }[SORTS[sort] ? sort : 'completed'];
    return lines.slice().sort(by);
  }
  function versusHtml(line) {
    if (line.avg_minutes === null || !line.avg_allowance_minutes) return '';
    const diff = line.avg_minutes - line.avg_allowance_minutes;
    if (Math.abs(diff) < 1) return '<span class="fitting-stats-vs is-even">on allowance</span>';
    return diff > 0 ? `<span class="fitting-stats-vs is-over">${escape(formatMinutes(diff))} over</span>` : `<span class="fitting-stats-vs is-under">${escape(formatMinutes(-diff))} under</span>`;
  }
  function categoryHtml(cat, sort) {
    const rows = sortLines(cat.lines, sort).map(l => `<tr><th scope="row" data-label="Line type">${l.line_type ? escape(l.line_type) : '<em>Line no longer on the job card</em>'}</th><td data-label="Completed">${l.completed}</td><td data-label="Timed (Start → Done)">${l.timed}${l.untimed ? `<small> · ${l.untimed} without Start</small>` : ''}</td><td data-label="Average time">${escape(formatMinutes(l.avg_minutes))}${versusHtml(l)}</td><td data-label="Median">${escape(formatMinutes(l.median_minutes))}</td><td data-label="Fastest – slowest">${l.timed ? escape(formatMinutes(l.min_minutes)) + ' – ' + escape(formatMinutes(l.max_minutes)) : '—'}</td><td data-label="Allowance (average)">${escape(formatMinutes(l.avg_allowance_minutes))}</td></tr>`).join('');
    const jobs = cat.jobs_completed ? `${cat.jobs_completed} station job${cat.jobs_completed === 1 ? '' : 's'} completed · average ${escape(formatMinutes(cat.job_avg_elapsed_minutes))} start to finish` : 'No station jobs completed';
    return `<section class="fitting-stats-category" data-fitting-stats-category="${escape(cat.category)}"><header><h3>${escape(cat.label)}</h3><p><strong>${cat.completed}</strong> line${cat.completed === 1 ? '' : 's'} completed · <strong>${cat.timed}</strong> timed${cat.avg_line_minutes === null ? '' : ` · average ${escape(formatMinutes(cat.avg_line_minutes))} per timed line`}<br><span>${jobs}</span></p></header>`+
      (rows ? `<div class="fitting-stats-table-wrap"><table class="fitting-stats-table"><thead><tr><th scope="col">Line type</th><th scope="col">Completed</th><th scope="col">Timed (Start → Done)</th><th scope="col">Average time</th><th scope="col">Median</th><th scope="col">Fastest – slowest</th><th scope="col">Allowance (average)</th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p class="fitting-stats-empty">No lines were ticked Done in this category in the period.</p>')+'</section>';
  }
  function reportHtml(report, {category = 'all', sort = 'completed'} = {}) {
    const shown = report.categories.filter(c => category === 'all' || c.category === category);
    const summary = `<div class="fitting-stats-summary"><div><span>Lines completed</span><strong>${report.totals.completed}</strong></div><div><span>Timed (Start → Done)</span><strong>${report.totals.timed}</strong></div><div><span>Station jobs completed</span><strong>${report.totals.jobs}</strong></div><div><span>Categories</span><strong>${report.categories.length}</strong></div></div>`;
    const body = shown.length ? shown.map(c => categoryHtml(c, sort)).join('') : '<p class="fitting-stats-empty">Nothing was completed in this period.</p>';
    const note = `<details class="fitting-stats-about"><summary>How these figures are worked out</summary><p>Completed counts every bay item ticked Done in the period (Perth time), by the line's work category. Times only count items where the fitter pressed Start and then Done: the time is the working time on the job clock between the two, so breaks and closed hours are not counted. Items ticked Done without Start are counted as completed but have no time. Line types group the job card description, ignoring capitals and extra spaces. Station jobs are whole bookings completed in the period; their time is the clock time from Start work to Complete.${report.timing_started_at ? ' Item timing was first recorded ' + escape(formatDate(report.timing_started_at)) + ', so there are no times before then.' : ''}</p></details>`;
    return summary + body + note;
  }
  function createController(options) {
    let owner = '', generation = 0, active = false, locked = false;
    let state = {loading:false,report:null,error:'',days:DEFAULT_DAYS,category:'all',sort:'completed'};
    const context = () => options.context() || {};
    const allowed = ctx => !locked && !!ctx.userId && ctx.role === 'administrator' && !!ctx.token;
    const identity = ctx => [ctx.userId,ctx.role,ctx.url,ctx.key].join('\u0000');
    function emit() { options.render({...state,active,allowed:allowed(context())}); }
    function clear() { generation++; state = {loading:false,report:null,error:'',days:DEFAULT_DAYS,category:'all',sort:'completed'}; }
    function syncAccess() {
      const ctx = context(), nextOwner = allowed(ctx) ? identity(ctx) : '';
      if (nextOwner !== owner || !nextOwner) { owner = nextOwner; clear(); }
      emit();
      return !!nextOwner;
    }
    async function refresh() {
      if (!syncAccess() || !active) return;
      const ctx = {...context()}, requestOwner = identity(ctx), requestId = ++generation, days = state.days;
      state = {...state,loading:true,error:''}; emit();
      const current = () => requestId === generation && active && allowed(context()) && requestOwner === identity(context()) && state.days === days;
      try {
        const response = await options.request(ctx, days);
        if (!current()) return;
        const report = normalizeReport(response);
        if (state.category !== 'all' && !report.categories.some(c => c.category === state.category)) state.category = 'all';
        state = {...state,loading:false,report,error:''};
      } catch (_) {
        if (!current()) return;
        state = {...state,loading:false,error:'Could not load fitting statistics. Please try Refresh.'};
      }
      emit();
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
      setDays(value) { const days = validDays(value); if (days === state.days && state.report) return Promise.resolve(); state = {...state,days,report:null}; return refresh(); },
      setCategory(value) { state = {...state,category:String(value || 'all')}; emit(); },
      setSort(value) { state = {...state,sort:SORTS[value] ? value : 'completed'}; emit(); },
      syncAccess, refresh,
      getState() { return {...state,active,allowed:allowed(context())}; }
    };
  }
  const api = {VERSION,PERIODS,CATEGORY_LABELS,SORTS,categoryLabel,formatMinutes,formatDate,normalizeReport,sortLines,reportHtml,createController};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (!root.document) return;
  const doc = root.document;
  function render(state) {
    const nav = doc.getElementById('nav-fitting-stats');
    if (nav) nav.hidden = !state.allowed;
    const view = doc.getElementById('fitting-stats');
    if (view) view.hidden = !state.allowed;
    const host = doc.getElementById('fitting-stats-content');
    if (!host) return;
    if (!state.allowed || !state.active) { host.replaceChildren(); return; }
    const focused = host.contains(doc.activeElement) ? doc.activeElement?.getAttribute('data-fitting-stats-control') : null;
    const categories = state.report?.categories || [];
    const periodOptions = PERIODS.map(d => `<option value="${d}"${d === state.days ? ' selected' : ''}>${d === 365 ? 'Last 12 months' : 'Last ' + d + ' days'}</option>`).join('');
    const categoryOptions = '<option value="all">All categories</option>' + categories.map(c => `<option value="${escape(c.category)}"${c.category === state.category ? ' selected' : ''}>${escape(c.label)}</option>`).join('');
    const sortOptions = Object.entries(SORTS).map(([k,v]) => `<option value="${k}"${k === state.sort ? ' selected' : ''}>${escape(v)}</option>`).join('');
    const status = state.error ? escape(state.error) + (state.report ? ' Showing the figures loaded before; they may be out of date.' : '')
      : state.loading ? 'Loading fitting statistics…'
      : state.report ? 'Period from ' + escape(formatDate(state.report.since,false)) + ' to now · checked ' + escape(formatDate(state.report.generated_at)) + ' (Perth time)' : '';
    host.innerHTML = `<div class="fitting-stats-header"><div><h2>Fitting statistics</h2><p>How many lines were completed and how long each type of line took, by category.</p></div><div class="fitting-stats-controls"><label>Period <select data-fitting-stats-control="days">${periodOptions}</select></label><label>Category <select data-fitting-stats-control="category"${categories.length ? '' : ' disabled'}>${categoryOptions}</select></label><label>Sort <select data-fitting-stats-control="sort">${sortOptions}</select></label><button type="button" class="small-button" data-fitting-stats-control="refresh"${state.loading ? ' disabled' : ''}>${state.loading ? 'Refreshing…' : 'Refresh'}</button></div></div><p class="fitting-stats-status${state.error ? ' is-error' : ''}" role="status" aria-live="polite">${status}</p><div class="fitting-stats-body" aria-busy="${state.loading}">${state.report ? reportHtml(state.report,{category:state.category,sort:state.sort}) : ''}</div>`;
    host.querySelector('[data-fitting-stats-control="days"]').addEventListener('change', e => controller.setDays(e.target.value));
    host.querySelector('[data-fitting-stats-control="category"]').addEventListener('change', e => controller.setCategory(e.target.value));
    host.querySelector('[data-fitting-stats-control="sort"]').addEventListener('change', e => controller.setSort(e.target.value));
    host.querySelector('[data-fitting-stats-control="refresh"]').addEventListener('click', () => controller.refresh());
    if (focused) host.querySelector(`[data-fitting-stats-control="${focused}"]`)?.focus({preventScroll:true});
  }
  const controller = createController({
    context:() => ({userId:root.PDC_AUTH_CONTEXT?.userId,role:root.PDC_AUTH_CONTEXT?.role,token:root.__pdcCachedAccessToken,url:root.PDC_SUPABASE_CONFIG?.url,key:root.PDC_SUPABASE_CONFIG?.publishableKey}),
    request:async (ctx, days) => {
      if (!ctx.url || !ctx.key) throw new Error('Service unavailable');
      const response = await root.fetch(ctx.url.replace(/\/$/,'') + '/rest/v1/rpc/get_pdc_fitting_statistics_489', {
        method:'POST', headers:{'Content-Type':'application/json',apikey:ctx.key,Authorization:'Bearer ' + ctx.token}, body:JSON.stringify({p_days:days}), cache:'no-store'
      });
      if (!response.ok) throw new Error('Fitting statistics unavailable');
      return response.json();
    }, render
  });
  root.PdcFittingStats = {open:controller.open, close:controller.close, reset:controller.reset, syncAccess:controller.syncAccess, version:VERSION};
  root.addEventListener('pdc-auth-locked', controller.reset);
  root.addEventListener('pdc-auth-ready', () => {
    controller.ready();
    if (doc.getElementById('fitting-stats')?.classList.contains('active')) controller.open();
  });
  controller.syncAccess();
})(typeof window !== 'undefined' ? window : globalThis);
