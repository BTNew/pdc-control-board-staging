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
  if (typeof module !== 'undefined') module.exports = { UsageQueue, cleanPage };
  if (!root.document) return;
  const doc = root.document;
  const queue = new UsageQueue(() => root.crypto.randomUUID());
  let generation = 0, sending = false, reportGeneration = 0, loadedFor = '', days = 30;
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
  function onRoute() {
    if (!context()?.userId) return;
    queue.visit(page());
    if (page() === 'user-management' && context().role === 'administrator' && loadedFor !== context().userId) loadReport();
  }
  function lock() {
    generation++; reportGeneration++; sending = false; loadedFor = ''; queue.reset();
    const panel = doc.getElementById('staff-usage-panel');
    if (panel) { panel.hidden = true; panel.querySelector('[data-usage-content]').replaceChildren(); }
  }
  function ready() {
    const user = context()?.userId || '';
    if (queue.user !== user) lock();
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
    panel.innerHTML = '<div class="panel-header"><div><h2>Board usage</h2><p>Sign-ins, page visits and clicks by staff member.</p></div><div class="staff-usage-controls"><label>Period <select data-usage-days><option value="7">Last 7 days</option><option value="30" selected>Last 30 days</option><option value="90">Last 90 days</option></select></label><button type="button" class="small-button" data-usage-refresh>Refresh usage</button></div></div><p class="muted-label" data-usage-note></p><div data-usage-content></div>';
    parent.append(panel);
    panel.querySelector('[data-usage-days]').addEventListener('change', e => { days = Number(e.target.value); loadReport(); });
    panel.querySelector('[data-usage-refresh]').addEventListener('click', loadReport);
    return panel;
  }
  async function loadReport() {
    if (context()?.role !== 'administrator') return;
    const panel = ensurePanel(); if (!panel) return;
    const request = ++reportGeneration, owner = context().userId;
    loadedFor = owner; panel.hidden = false;
    const content = panel.querySelector('[data-usage-content]');
    content.textContent = 'Loading usage…';
    try {
      const data = await signedRequest('get_pdc_usage_report_20260914', {p_days:days});
      if (request !== reportGeneration || context()?.userId !== owner || context()?.role !== 'administrator') return;
      panel.querySelector('[data-usage-note]').textContent = 'Tracking started '+formatDate(data.tracking_started_at)+'. Sign-ins count distinct sign-in sessions observed since tracking began; refreshing a page does not add a sign-in. Times are Perth time. Clicks and visits are usage indicators, not a measure of completed work.';
      const users = data.users || [];
      content.innerHTML = '<div class="admin-reference-table-wrap"><table class="admin-reference-table staff-usage-table"><thead><tr><th>Name / email</th><th>Last sign-in</th><th>Last activity</th><th>Sign-ins</th><th>Active days</th><th>Page visits</th><th>Clicks</th><th>Pages used</th></tr></thead><tbody>'+users.map(u => '<tr><td>'+escape(u.name)+'<br><small>'+escape(u.email)+'</small></td><td>'+escape(formatDate(u.last_sign_in_at))+'</td><td>'+escape(formatDate(u.last_active_at))+'</td><td>'+escape(u.sign_ins)+'</td><td>'+escape(u.active_days)+'</td><td>'+escape(u.page_visits)+'</td><td>'+escape(u.clicks)+'</td><td><details><summary>View pages</summary>'+((u.pages||[]).map(p=>'<div>'+escape(labels[p.page]||p.page)+': '+escape(p.visits)+' visits, '+escape(p.clicks)+' clicks</div>').join('')||'No activity recorded')+'</details></td></tr>').join('')+'</tbody></table></div>';
    } catch (_) {
      if (request === reportGeneration && context()?.userId === owner) { content.textContent = 'Could not load usage. Please try Refresh usage.'; loadedFor = ''; }
    }
  }
  doc.addEventListener('click', event => {
    if (!event.isTrusted || !event.target?.closest?.('#app-shell') || !context()?.userId) return;
    queue.click(); root.setTimeout(onRoute,0);
  }, true);
  root.addEventListener('pdc-auth-ready', ready);
  root.addEventListener('pdc-auth-locked', lock);
  root.addEventListener('hashchange', onRoute);
  root.addEventListener('popstate', onRoute);
  doc.addEventListener('visibilitychange', () => { if (doc.visibilityState === 'hidden') flush(); else onRoute(); });
  root.addEventListener('pagehide', flush);
  const observer = new root.MutationObserver(onRoute);
  doc.querySelectorAll('.view').forEach(view => observer.observe(view,{attributes:true,attributeFilter:['class']}));
  root.setInterval(flush,15000);
  ready();
})(typeof window !== 'undefined' ? window : globalThis);
