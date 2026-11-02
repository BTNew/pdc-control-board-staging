/* Fitter logins. r816 (F455). Administrator only: Setup > Mechanic list > Fitter PINs (Craig 2 Nov 08:07).
   Each fitter signs in on the tablet with initials and a PIN. Reads and writes stay on staging. */
(function (root) {
  'use strict';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  const MESSAGES = {
    administrator_required:'Only an administrator can manage fitter logins.',
    technician_not_found:'That mechanic is not active any more.',
    username_format:'The username is the Tune mechanic ID: 2 to 6 numbers (for example 2686).',
    username_taken:'Another fitter already has that mechanic ID.',
    pin_format:'The first PIN is the fitter number (2 to 6 numbers), or a 4 to 6 number PIN.',
    pin_too_simple:'Pick a harder PIN: not all the same number and not a run like 1234.',
    login_not_found:'This fitter has no login yet.',
    no_fitter_logins:'Add at least one fitter login before switching sign-in on.',
    idle_minutes_range:'Idle sign-out is 2 to 60 minutes.',
  };

  // Initials from the name, the same as the server (pdc_fitter_initials_816): first letter of each word, up to 4.
  function initials(name) {
    return String(name || '').toUpperCase().replace(/[^A-Z ]/g, ' ').split(/\s+/).filter(Boolean).map(w => w[0]).join('').slice(0, 4);
  }
  // Craig 2 Nov 07:30: the fitter taps their name; the first PIN is their fitter number (changed at first sign-in).
  function defaultTempPassword(name, id) {
    return /^[0-9]{2,6}$/.test(String(id || '')) ? String(id) : '';
  }
  // A random temporary PIN that passes the PIN rule.
  function randomPin(rand = Math.random) {
    for (;;) {
      const pin = String(Math.floor(rand() * 9000) + 1000);
      if (!/^(.)\1+$/.test(pin) && !'0123456789'.includes(pin) && !'9876543210'.includes(pin)) return pin;
    }
  }
  function statusText(t, now = Date.now()) {
    if (!t.username) return 'No login';
    if (t.active === false) return 'Disabled';
    if (t.locked_until && Date.parse(t.locked_until) > now) return 'Locked (wrong PINs)';
    if (t.must_change) return 'Temporary PIN · not signed in yet';
    return 'Active';
  }
  function panelHtml(state) {
    if (state.error) return `<section class="fitter-logins"><h3>Fitter PINs</h3><p class="fitter-logins-error">${esc(state.error)}</p></section>`;
    if (!state.payload) return `<section class="fitter-logins"><h3>Fitter PINs</h3><p>Loading…</p></section>`;
    const p = state.payload, techs = p.technicians || [];
    const withLogin = techs.filter(t => t.username && t.active !== false).length;
    const rows = techs.map(t => {
      const draft = state.drafts[t.technician_id] || {};
      const id = draft.username ?? t.username ?? (/^[0-9]{2,6}$/.test(String(t.code || '')) ? t.code : '');
      const temp = draft.pin ?? (t.username ? '' : defaultTempPassword(t.name, id));
      return `<tr data-fitter-login-row="${esc(t.technician_id)}">
        <td><strong>${esc(t.name)}</strong>${t.timed_jobs_14d ? `<small class="fitter-logins-used">${esc(t.timed_jobs_14d)} timed items, 14 days</small>` : ''}</td>
        <td><input aria-label="Tune mechanic ID for ${esc(t.name)}" data-fitter-login-initials value="${esc(id)}" inputmode="numeric" maxlength="6" size="6" autocomplete="off" placeholder="ID"></td>
        <td><input aria-label="Temporary password for ${esc(t.name)}" data-fitter-login-pin value="${esc(temp)}" maxlength="10" size="9" autocomplete="off" placeholder="${t.username ? 'reset to' : 'fitter no.'}"><button type="button" data-fitter-login-random title="Fitter number">Default</button></td>
        <td>${esc(statusText(t))}${t.last_sign_in ? `<small>Last in ${esc(new Date(t.last_sign_in).toLocaleString('en-AU', { timeZone:'Australia/Perth', day:'numeric', month:'short', hour:'numeric', minute:'2-digit' }))}</small>` : ''}</td>
        <td class="fitter-logins-actions"><button type="button" data-fitter-login-save ${state.busy ? 'disabled' : ''}>${t.username ? 'Reset PIN' : 'Create PIN'}</button>
          ${t.username ? `<button type="button" data-fitter-login-active="${t.active === false ? '1' : '0'}" ${state.busy ? 'disabled' : ''}>${t.active === false ? 'Enable' : 'Disable'}</button>` : ''}
          ${state.rowMessage[t.technician_id] ? `<small role="status">${esc(state.rowMessage[t.technician_id])}</small>` : ''}</td></tr>`;
    }).join('');
    return `<section class="fitter-logins" aria-label="Fitter logins"><h3>Fitter PINs</h3>
      <p>Each fitter taps their name on the tablet. Their first PIN is their fitter number. Anyone could work that out, so at first sign-in the fitter must pick their own 4 to 6 number PIN.</p>
      <p><button type="button" data-fitter-login-bulk ${state.busy ? 'disabled' : ''}>Create PINs for every mechanic with a Tune ID</button> ${techs.filter(t => !t.username && !/^[0-9]{2,6}$/.test(String(t.code || ''))).length ? `<small>${techs.filter(t => !t.username && !/^[0-9]{2,6}$/.test(String(t.code || ''))).length} without a Tune ID: type their ID in the row.</small>` : ''}</p>
      <div class="fitter-logins-switch"><label><input type="checkbox" data-fitter-login-required ${p.required ? 'checked' : ''} ${state.busy ? 'disabled' : ''}> Fitter PIN required on the Fitters bay</label>
        <label>Sign out after <input type="number" min="2" max="60" data-fitter-login-idle value="${esc(p.idle_minutes || 10)}"> idle minutes</label>
        <span>${withLogin} of ${techs.length} mechanics have a login.${p.required ? ' PIN is ON: fitters without a login cannot record work.' : ' PIN is OFF: fitters keep working as now (pick their name, no PIN).'}</span></div>
      ${state.message ? `<p class="fitter-logins-msg" role="status">${esc(state.message)}</p>` : ''}
      <div class="fitter-logins-table"><table><thead><tr><th>Mechanic</th><th>Tune ID</th><th>First PIN</th><th>Status</th><th></th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
  }

  const api = { initials, defaultTempPassword, randomPin, statusText, panelHtml, MESSAGES };
  if (typeof module !== 'undefined' && module.exports) { module.exports = api; return; }
  root.PdcFitterLogins = api;

  const doc = root.document;
  const state = { payload:null, error:'', message:'', busy:false, drafts:{}, rowMessage:{}, loading:false };
  const host = () => doc.getElementById('fitter-logins-content');
  const isAdmin = () => root.PDC_AUTH_CONTEXT?.role === 'administrator';
  const shown = () => doc.body?.dataset.currentView === 'lists';

  async function rpc(name, body) {
    const config = root.PDC_SUPABASE_CONFIG;
    const token = typeof root.getPdcSupabaseAccessToken === 'function' ? root.getPdcSupabaseAccessToken() : '';
    if (!root.PDC_AUTH_CONTEXT?.userId || !token || config?.projectRef !== 'cdsmnqxtyyoeoznmbidd') throw Error('Sign in on staging to manage fitter logins.');
    const response = await root.fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
      method:'POST', headers:{ apikey:config.publishableKey, Authorization:`Bearer ${token}`, 'Content-Type':'application/json' }, body:JSON.stringify(body || {}),
    });
    const data = await response.json().catch(() => ({}));
    if (response.status === 404) throw Error('Fitter logins are not on this database yet. This preview has not been applied.');
    if (!response.ok) throw Error('The change could not be saved. Refresh and try again.');
    if (data?.ok === false) throw Error(MESSAGES[data.error] || 'The change was refused.');
    return data;
  }
  function render() { const h = host(); if (!h) return; if (!isAdmin()) { h.innerHTML = ''; return; } h.innerHTML = panelHtml(state); bind(h); }
  async function load() {
    if (state.loading || !isAdmin()) { render(); return; }
    state.loading = true;
    try { state.payload = await rpc('admin_list_fitter_logins_816'); state.error = ''; }
    catch (e) { state.error = e.message; }
    finally { state.loading = false; render(); }
  }
  function rowInputs(row) {
    return { id:row.dataset.fitterLoginRow, initials:row.querySelector('[data-fitter-login-initials]')?.value || '', pin:row.querySelector('[data-fitter-login-pin]')?.value || '' };
  }
  function keepDrafts(h) {
    h.querySelectorAll('[data-fitter-login-row]').forEach(row => { const v = rowInputs(row); state.drafts[v.id] = { username:v.initials, pin:v.pin }; });
  }
  async function act(fn, done) {
    state.busy = true; render();
    try { await fn(); await load(); if (done) done(); }
    catch (e) { state.message = e.message; }
    finally { state.busy = false; render(); }
  }
  function bind(h) {
    h.querySelectorAll('[data-fitter-login-random]').forEach(b => b.addEventListener('click', () => {
      const row = b.closest('[data-fitter-login-row]'), t = (state.payload?.technicians || []).find(x => x.technician_id === row.dataset.fitterLoginRow);
      row.querySelector('[data-fitter-login-pin]').value = defaultTempPassword(t?.name, row.querySelector('[data-fitter-login-initials]')?.value); keepDrafts(h);
    }));
    h.querySelectorAll('input[data-fitter-login-initials],input[data-fitter-login-pin]').forEach(i => i.addEventListener('input', () => keepDrafts(h)));
    h.querySelectorAll('[data-fitter-login-save]').forEach(b => b.addEventListener('click', () => {
      const v = rowInputs(b.closest('[data-fitter-login-row]'));
      state.message = ''; state.rowMessage = {};
      void act(() => rpc('admin_set_fitter_login_816', { p_technician_id:v.id, p_username:v.initials, p_temp_pin:v.pin }), () => {
        delete state.drafts[v.id];
        state.rowMessage[v.id] = `Saved. Mechanic ${v.initials} signs in with ${v.pin.toUpperCase()}, then picks their own PIN.`;
      });
    }));
    h.querySelector('[data-fitter-login-bulk]')?.addEventListener('click', () => {
      state.message = ''; state.rowMessage = {};
      let result = null;
      void act(async () => { result = await rpc('admin_create_fitter_logins_from_tune_816'); }, () => {
        const skipped = (result?.skipped || []).length;
        state.message = `${result?.created || 0} logins created (first PIN: their fitter number).${skipped ? ` ${skipped} skipped: add their Tune ID in the row.` : ''}`;
      });
    });
    h.querySelectorAll('[data-fitter-login-active]').forEach(b => b.addEventListener('click', () => {
      const id = b.closest('[data-fitter-login-row]').dataset.fitterLoginRow;
      void act(() => rpc('admin_set_fitter_login_active_816', { p_technician_id:id, p_active:b.dataset.fitterLoginActive === '1' }));
    }));
    h.querySelector('[data-fitter-login-required]')?.addEventListener('change', e => {
      const on = e.target.checked, idle = Number(h.querySelector('[data-fitter-login-idle]')?.value) || null;
      if (on && !root.confirm?.('Switch fitter sign-in ON? Every fitter will need their initials and PIN to record work on the Fitters bay.')) { e.target.checked = false; return; }
      void act(() => rpc('admin_set_fitter_login_required_816', { p_required:on, p_idle_minutes:idle }), () => { state.message = on ? 'Fitter sign-in is ON.' : 'Fitter sign-in is OFF.'; });
    });
    h.querySelector('[data-fitter-login-idle]')?.addEventListener('change', e => {
      void act(() => rpc('admin_set_fitter_login_required_816', { p_required:state.payload?.required === true, p_idle_minutes:Number(e.target.value) || null }), () => { state.message = 'Idle sign-out saved.'; });
    });
  }
  let wasShown = false;
  function check() {
    const now = shown();
    if (now && !wasShown) { state.message = ''; state.rowMessage = {}; void load(); }
    if (!now && wasShown) { state.drafts = {}; state.rowMessage = {}; const h = host(); if (h) h.innerHTML = ''; }
    wasShown = now;
  }
  if (doc?.body) new root.MutationObserver(check).observe(doc.body, { attributes:true, attributeFilter:['data-current-view'] });
  root.addEventListener('pdc-auth-ready', check);
  root.addEventListener('pdc-auth-locked', () => { state.payload = null; state.drafts = {}; wasShown = false; const h = host(); if (h) h.innerHTML = ''; });
})(typeof window !== 'undefined' ? window : globalThis);
