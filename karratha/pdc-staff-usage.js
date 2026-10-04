(function (root) {
  'use strict';
  const PAGES = new Set(['dashboard','qc','workflow','planner-bus-4x4','planner-tint','planner-hoist','planner-fitting','planner-fab','planner-elec','planner-tyre','parts','sublet','user-management','lists','import','backup','deleted','collected','completed','backend','newvehicles','emailreview','ai-auditor','other']);
  const cleanPage = page => PAGES.has(page) ? page : 'other';
  class UsageQueue {
    constructor(uuid) { this.uuid = uuid; this.reset(); }
    reset() { this.user = ''; this.page = ''; this.queue = []; this.current = null; }
    identify(user) { if (user !== this.user) { this.reset(); this.user = user; } }
    visit(page) {
      if (!this.user) return;
      page = cleanPage(page);
      if (page === this.page) return;
      this.seal(); this.page = page;
      this.current = { p_batch_id: this.uuid(), p_page: page, p_clicks: 0, p_visit: true };
    }
    click() {
      if (!this.user || !this.page) return;
      if (!this.current) this.current = { p_batch_id: this.uuid(), p_page: this.page, p_clicks: 0, p_visit: false };
      if (this.current.p_clicks < 200) this.current.p_clicks++;
    }
    seal() {
      if (this.current) {
        if (this.queue.length < 100) this.queue.push(this.current);
        this.current = null;
      }
    }
    next() { this.seal(); return this.queue[0]; }
    acknowledge(id) { if (this.queue[0]?.p_batch_id === id) this.queue.shift(); }
  }
  const SORT_KEYS = new Set(['name','last_sign_in_at','last_active_at','sign_ins','active_days','page_visits','clicks']);
  const DATE_KEYS = new Set(['last_sign_in_at','last_active_at']);
  const timestamp = value => typeof value === 'string' && value.trim() ? Date.parse(value) : NaN;
  const count = value => Number.isFinite(Number(value)) ? Number(value) : 0;
  const compareText = (a,b) => String(a ?? '').localeCompare(String(b ?? ''),'en-AU',{sensitivity:'base'}) || String(a ?? '').localeCompare(String(b ?? ''),'en-AU');
  const compareStaff = (a,b) => compareText(a.name,b.name) || compareText(a.email,b.email) || compareText(a.user_id,b.user_id);
  function sortUsageUsers(users, key = 'last_active_at', direction = 'desc') {
    key = SORT_KEYS.has(key) ? key : 'last_active_at';
    const multiplier = direction === 'asc' ? 1 : -1;
    return (Array.isArray(users) ? users : []).slice().sort((a,b) => {
      let comparison;
      if (DATE_KEYS.has(key)) {
        const left = timestamp(a[key]), right = timestamp(b[key]);
        if (!Number.isFinite(left) || !Number.isFinite(right)) {
          if (Number.isFinite(left)) return -1;
          if (Number.isFinite(right)) return 1;
          return compareStaff(a,b);
        }
        comparison = left - right;
      } else comparison = key === 'name' ? compareText(a.name,b.name) : count(a[key]) - count(b[key]);
      return comparison * multiplier || compareStaff(a,b);
    });
  }
  function usagePresence(user, report, nowMs) {
    if (!user || !report || report.error || report.stale || typeof user.active_now !== 'boolean' || !Number.isFinite(nowMs)) return 'unknown';
    const generated = timestamp(report.generated_at);
    if (!Number.isFinite(generated) || nowMs - generated > 60000 || generated - nowMs > 5000) return 'unknown';
    if (!user.active_now) return 'inactive';
    const activeAt = timestamp(user.presence_last_active_at), windowSeconds = Number(report.active_window_seconds);
    if (!Number.isFinite(activeAt) || !Number.isFinite(windowSeconds) || windowSeconds <= 0 || activeAt - nowMs > 5000) return 'unknown';
    return nowMs - activeAt <= windowSeconds * 1000 ? 'active' : 'inactive';
  }
  function filterUsageUsers(users, {query = '', activity = 'all'} = {}, report, nowMs) {
    const term = String(query).trim().toLocaleLowerCase('en-AU');
    return (Array.isArray(users) ? users : []).filter(user => {
      if (term && ![user.name,user.email].some(value => String(value ?? '').toLocaleLowerCase('en-AU').includes(term))) return false;
      if (activity === 'active') return usagePresence(user,report,nowMs) === 'active';
      const used = ['sign_ins','active_days','page_visits','clicks'].some(key => count(user[key]) > 0);
      return activity === 'used' ? used : activity === 'unused' ? !used : true;
    });
  }
  if (typeof module !== 'undefined') module.exports = { UsageQueue, cleanPage, sortUsageUsers, filterUsageUsers, usagePresence };
  if (!root.document) return;
  const doc = root.document;
  const queue = new UsageQueue(() => root.crypto.randomUUID());
  let generation = 0, sending = false, reportGeneration = 0, loadedFor = '', days = 30;
  let authOwner = '', authRole = '', authLocked = false;
  let cachedReport = null, reportError = false, reportFetching = false, reportReceivedAt = 0, wasReportVisible = false;
  let sortKey = 'last_active_at', sortDirection = 'desc', query = '', activity = 'all';
  const expandedUsers = new Set();
  const monotonicNow = () => root.performance?.now ? root.performance.now() : Date.now();
  const context = () => root.PDC_AUTH_CONTEXT;
  const page = () => {
    const view = doc.querySelector('.view.active')?.id;
    return cleanPage(PAGES.has(view) ? view : doc.querySelector('.nav-item.active[data-view]')?.dataset.view || 'dashboard');
  };
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function signedRequest(name, body) {
    const ctx = context(), token = root.__pdcCachedAccessToken, config = root.PDC_SUPABASE_CONFIG;
    if (!ctx?.userId || !token || config?.url?.replace(/\/$/,'') !== 'https://cdsmnqxtyyoeoznmbidd.supabase.co') return Promise.reject(new Error('Sign in required'));
    // Capture the current token synchronously: queued clicks cannot inherit another user's later session.
    return root.fetch(config.url.replace(/\/$/,'') + '/rest/v1/rpc/' + name, {
      method:'POST', headers:{'Content-Type':'application/json',apikey:config.publishableKey,Authorization:'Bearer '+token},
      body:JSON.stringify(body), keepalive:true
    }).then(async response => { if (!response.ok) throw new Error('Usage request failed'); return response.json(); });
  }
  async function flush() {
    if (sending || !context()?.userId || queue.user !== context().userId) return;
    const batch = queue.next(); if (!batch) return;
    const owner = generation; sending = true;
    try {
      const result = await signedRequest('record_pdc_usage_20260914', batch);
      if (owner === generation && result?.ok) queue.acknowledge(batch.p_batch_id);
    } catch (_) { /* Retry the same batch ID without doubling successful writes. */ }
    finally { if (owner === generation) sending = false; }
  }
  const reportVisible = () => !authLocked && !!context()?.userId && context()?.role === 'administrator' && page() === 'user-management' && doc.visibilityState !== 'hidden';
  function onRoute() {
    if (authLocked) return;
    if (authOwner !== (context()?.userId || '') || authRole !== (context()?.role || '')) { ready(); return; }
    if (!context()?.userId) return;
    queue.visit(page());
    if (!reportVisible()) { wasReportVisible = false; return; }
    const enteringReport = !wasReportVisible; wasReportVisible = true;
    if (cachedReport) renderReport();
    if (!reportFetching && (loadedFor !== context().userId || (enteringReport && (!cachedReport || monotonicNow() - reportReceivedAt >= 30000)))) loadReport();
  }
  function lock() {
    generation++; reportGeneration++; sending = false; loadedFor = ''; queue.reset();
    cachedReport = null; reportError = false; reportFetching = false; reportReceivedAt = 0; wasReportVisible = false;
    authOwner = ''; authRole = ''; days = 30; sortKey = 'last_active_at'; sortDirection = 'desc'; query = ''; activity = 'all'; expandedUsers.clear();
    const panel = doc.getElementById('staff-usage-panel');
    if (panel) {
      panel.hidden = true; panel.querySelector('[data-usage-content]').replaceChildren();
      panel.querySelector('[data-usage-note]').textContent = '';
      panel.querySelector('[data-usage-results]').textContent = '';
      panel.querySelector('[data-usage-status]').textContent = '';
      panel.querySelector('[data-usage-counts]').textContent = '';
      panel.querySelector('.staff-usage-about').open = false;
      panel.querySelector('[data-usage-days]').value = '30';
      panel.querySelector('[data-usage-search]').value = '';
      panel.querySelector('[data-usage-activity]').value = 'all';
      syncSortControls(panel);
    }
  }
  function ready() {
    const user = context()?.userId || '', role = context()?.role || '';
    if (authOwner !== user || authRole !== role) lock();
    authLocked = false; authOwner = user; authRole = role;
    queue.identify(user);
    const panel = ensurePanel(); if (panel) panel.hidden = context()?.role !== 'administrator';
    onRoute(); flush();
  }
  function formatDate(value) {
    if (!value) return 'Never recorded';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? 'Unknown' : date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'});
  }
  const labels = {'dashboard':'Vehicle Locations','workflow':'Control Board','qc':'QC Sign-off','newvehicles':'New Vehicles','user-management':'User Management','planner-bus-4x4':'Bus 4×4','planner-tint':'Tint','planner-hoist':'Hoist','planner-fitting':'Fitting','planner-fab':'Fabrication','planner-elec':'Electrical','planner-tyre':'Tyres'};
  function ensurePanel() {
    let panel = doc.getElementById('staff-usage-panel');
    if (panel) return panel;
    const parent = doc.querySelector('#user-management .pdc-lists-layout'); if (!parent) return null;
    panel = doc.createElement('section'); panel.id = 'staff-usage-panel'; panel.className = 'panel pdc-list-panel'; panel.hidden = true;
    panel.innerHTML = '<div class="panel-header"><div><h2>Board usage</h2><p>Sign-ins, page visits and clicks by staff member.</p></div><div class="staff-usage-controls"><label>Period <select data-usage-days><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option></select></label><button type="button" class="small-button" data-usage-refresh>Refresh usage</button></div></div>'+
      '<div class="staff-usage-toolbar"><label class="staff-usage-search">Find staff<input type="search" data-usage-search placeholder="Search name or email" autocomplete="off"></label><label>Activity<select data-usage-activity><option value="all">All staff</option><option value="active">Active now</option><option value="used">Used in selected period</option><option value="unused">No activity in period</option></select></label><label>Sort by<select data-usage-sort><option value="last_active_at">Last activity</option><option value="last_sign_in_at">Last sign-in</option><option value="sign_ins">Sign-ins</option><option value="active_days">Active days</option><option value="page_visits">Page visits</option><option value="clicks">Clicks</option><option value="name">Name / email</option></select></label><button type="button" class="small-button staff-usage-direction" data-usage-direction>Newest first ↓</button></div>'+
      '<p class="staff-usage-results" data-usage-results></p><p class="staff-usage-note" data-usage-note></p><div class="staff-usage-sr-only" data-usage-status role="status" aria-live="polite" aria-atomic="true"></div><div data-usage-content></div><details class="staff-usage-about"><summary>About counts</summary><p data-usage-counts></p></details>';
    parent.append(panel);
    panel.querySelector('[data-usage-days]').addEventListener('change', e => { days = Number(e.target.value); cachedReport = null; reportError = false; loadReport({announce:true}); });
    panel.querySelector('[data-usage-refresh]').addEventListener('click', () => loadReport({announce:true}));
    panel.querySelector('[data-usage-search]').addEventListener('input', e => { query = e.target.value; renderReport({announce:true}); });
    panel.querySelector('[data-usage-activity]').addEventListener('change', e => { activity = e.target.value; renderReport({announce:true}); });
    panel.querySelector('[data-usage-sort]').addEventListener('change', e => { sortKey = e.target.value; sortDirection = sortKey === 'name' ? 'asc' : 'desc'; renderReport({announce:true}); });
    panel.querySelector('[data-usage-direction]').addEventListener('click', () => { sortDirection = sortDirection === 'desc' ? 'asc' : 'desc'; renderReport({announce:true}); });
    panel.addEventListener('click', e => {
      const button = e.target.closest?.('[data-usage-sort-key]');
      if (!button) return;
      if (sortKey === button.dataset.usageSortKey) sortDirection = sortDirection === 'desc' ? 'asc' : 'desc';
      else { sortKey = button.dataset.usageSortKey; sortDirection = sortKey === 'name' ? 'asc' : 'desc'; }
      renderReport({announce:true});
    });
    panel.addEventListener('toggle', e => {
      if (e.target.tagName !== 'DETAILS') return;
      const key = e.target.closest('[data-usage-person]')?.dataset.usagePerson;
      if (key && e.target.isConnected) { if (e.target.open) expandedUsers.add(key); else expandedUsers.delete(key); }
    },true);
    return panel;
  }
  const columns = [['name','Name / email'],['last_sign_in_at','Last sign-in'],['last_active_at','Last activity'],['sign_ins','Sign-ins'],['active_days','Active days'],['page_visits','Page visits'],['clicks','Clicks']];
  function syncSortControls(panel) {
    panel.querySelector('[data-usage-sort]').value = sortKey;
    const descending = sortDirection === 'desc';
    panel.querySelector('[data-usage-direction]').textContent = (sortKey === 'name' ? descending ? 'Z to A' : 'A to Z' : DATE_KEYS.has(sortKey) ? descending ? 'Newest first' : 'Oldest first' : descending ? 'Highest first' : 'Lowest first') + (descending ? ' ↓' : ' ↑');
    panel.querySelectorAll('[data-usage-sort-key]').forEach(button => {
      const selected = button.dataset.usageSortKey === sortKey;
      button.closest('th').setAttribute('aria-sort',selected ? descending ? 'descending' : 'ascending' : 'none');
      button.querySelector('[data-usage-sort-arrow]').textContent = selected ? descending ? '↓' : '↑' : '↕';
    });
  }
  function reportNow() {
    const generated = timestamp(cachedReport?.generated_at);
    return Number.isFinite(generated) ? generated + Math.max(0,monotonicNow() - reportReceivedAt) : NaN;
  }
  function renderReport({announce = false} = {}) {
    if (!reportVisible()) return;
    const panel = ensurePanel(); if (!panel) return;
    panel.hidden = false; syncSortControls(panel);
    if (!cachedReport) return;
    const data = reportError ? {...cachedReport,error:true} : cachedReport, nowMs = reportNow();
    const users = Array.isArray(data.users) ? data.users : [];
    const visibleUsers = sortUsageUsers(filterUsageUsers(users,{query,activity},data,nowMs),sortKey,sortDirection);
    const content = panel.querySelector('[data-usage-content]');
    if (!content.querySelector('table')) content.innerHTML = '<div class="admin-reference-table-wrap"><table class="admin-reference-table staff-usage-table"><thead><tr>'+columns.map(([key,label]) => '<th scope="col" aria-sort="none"><button type="button" class="staff-usage-sort-heading" data-usage-sort-key="'+key+'">'+label+' <span data-usage-sort-arrow aria-hidden="true">↕</span></button></th>').join('')+'<th scope="col">Status</th><th scope="col">Pages used</th></tr></thead><tbody></tbody></table></div>';
    const wrap = content.querySelector('.admin-reference-table-wrap'), scrollLeft = wrap.scrollLeft;
    const focusedSummary = doc.activeElement?.tagName === 'SUMMARY' ? doc.activeElement.closest('[data-usage-person]')?.dataset.usagePerson : null;
    content.querySelectorAll('[data-usage-person]').forEach(row => {
      if (row.querySelector('details')?.open) expandedUsers.add(row.dataset.usagePerson);
      else expandedUsers.delete(row.dataset.usagePerson);
    });
    content.querySelector('tbody').innerHTML = visibleUsers.map(u => {
      const key = String(u.user_id || u.email || u.name || ''), presence = usagePresence(u,data,nowMs);
      const status = presence === 'active' ? 'Active now' : presence === 'inactive' ? 'Inactive' : 'Status unavailable';
      const tooltip = presence === 'active' ? 'Activity within the last 2 minutes in a signed-in session' : presence === 'inactive' ? 'No recent activity in a signed-in session' : 'Current activity could not be confirmed. Refresh usage to try again.';
      return '<tr data-usage-person="'+escape(key)+'"><td>'+escape(u.name)+'<br><small>'+escape(u.email)+'</small></td><td>'+escape(formatDate(u.last_sign_in_at))+'</td><td>'+escape(formatDate(u.last_active_at))+'</td><td>'+escape(count(u.sign_ins))+'</td><td>'+escape(count(u.active_days))+'</td><td>'+escape(count(u.page_visits))+'</td><td>'+escape(count(u.clicks))+'</td><td><span class="staff-usage-presence staff-usage-presence--'+presence+'" title="'+escape(tooltip)+'"><span class="staff-usage-dot" aria-hidden="true"></span>'+status+'</span></td><td><details'+(expandedUsers.has(key) ? ' open' : '')+'><summary>View pages</summary>'+((Array.isArray(u.pages) ? u.pages : []).map(p=>'<div>'+escape(labels[p.page]||p.page)+': '+escape(p.visits)+' visits, '+escape(p.clicks)+' clicks</div>').join('')||'No activity recorded')+'</details></td></tr>';
    }).join('') || '<tr><td colspan="9" class="staff-usage-empty">No staff match these filters.</td></tr>';
    syncSortControls(panel);
    if (focusedSummary) Array.from(content.querySelectorAll('[data-usage-person]')).find(row => row.dataset.usagePerson === focusedSummary)?.querySelector('summary')?.focus({preventScroll:true});
    wrap.scrollLeft = scrollLeft;
    const result = visibleUsers.length+' of '+users.length+' staff shown';
    panel.querySelector('[data-usage-results]').textContent = result;
    const stale = reportError || data.error || data.stale || !Number.isFinite(nowMs) || nowMs - timestamp(data.generated_at) > 60000;
    panel.querySelector('[data-usage-note]').classList.toggle('staff-usage-note--stale',stale);
    panel.querySelector('[data-usage-note]').textContent = stale ? 'Usage may be out of date. Showing the last loaded counts; current status is unavailable. Use Refresh usage to try again.' : 'Green means activity within the last 2 minutes in a signed-in session. Status refreshes every 30 seconds while this page is open. Counts cover the selected period; dates are Perth time.';
    panel.querySelector('[data-usage-counts]').textContent = 'Tracking started '+formatDate(data.tracking_started_at)+'. Sign-ins count distinct sign-in sessions observed since tracking began; refreshing a page does not add a sign-in. Last sign-in and last activity show the latest recorded dates and can fall outside the selected period. Active days count Perth calendar days with recorded usage. Clicks and visits are usage indicators, not a measure of completed work.';
    if (announce) panel.querySelector('[data-usage-status]').textContent = result+'.';
  }
  async function loadReport({announce = false} = {}) {
    if (!authLocked && (authOwner !== (context()?.userId || '') || authRole !== (context()?.role || ''))) { ready(); return; }
    if (!reportVisible()) return;
    const panel = ensurePanel(); if (!panel) return;
    const request = ++reportGeneration, owner = context().userId, requestedDays = days;
    loadedFor = owner; panel.hidden = false; reportFetching = true;
    const content = panel.querySelector('[data-usage-content]');
    if (!cachedReport) { content.textContent = 'Loading usage…'; panel.querySelector('[data-usage-results]').textContent = ''; panel.querySelector('[data-usage-note]').textContent = ''; }
    try {
      const data = await signedRequest('get_pdc_usage_report_20260914', {p_days:requestedDays});
      if (request !== reportGeneration || context()?.userId !== owner || context()?.role !== 'administrator' || days !== requestedDays || authLocked) return;
      if (!data || !Array.isArray(data.users)) throw new Error('Invalid usage report');
      cachedReport = data; reportError = false; reportReceivedAt = monotonicNow();
      renderReport({announce});
    } catch (_) {
      if (request === reportGeneration && context()?.userId === owner && context()?.role === 'administrator' && !authLocked) {
        reportError = true;
        if (cachedReport) renderReport({announce});
        else if (reportVisible()) { content.textContent = 'Could not load usage. Please try Refresh usage.'; if (announce) panel.querySelector('[data-usage-status]').textContent = 'Could not load usage.'; }
      }
    } finally {
      if (request === reportGeneration) reportFetching = false;
    }
  }
  doc.addEventListener('click', event => {
    if (!event.isTrusted || !event.target?.closest?.('#app-shell') || !context()?.userId) return;
    queue.click(); root.setTimeout(onRoute,0);
  }, true);
  root.addEventListener('pdc-auth-ready', ready);
  root.addEventListener('pdc-auth-locked', () => { lock(); authLocked = true; });
  root.addEventListener('hashchange', onRoute);
  root.addEventListener('popstate', onRoute);
  doc.addEventListener('visibilitychange', () => { if (doc.visibilityState === 'hidden') { wasReportVisible = false; flush(); } else onRoute(); });
  root.addEventListener('pagehide', flush);
  const observer = new root.MutationObserver(onRoute);
  doc.querySelectorAll('.view').forEach(view => observer.observe(view,{attributes:true,attributeFilter:['class']}));
  root.setInterval(flush,15000);
  root.setInterval(() => {
    if (authOwner !== (context()?.userId || '') || authRole !== (context()?.role || '')) { if (!authLocked) ready(); return; }
    if (!reportVisible()) return;
    renderReport();
    if (!reportFetching) loadReport();
  },30000);
  ready();
})(typeof window !== 'undefined' ? window : globalThis);

