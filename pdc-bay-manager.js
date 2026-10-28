/* Bay Manager. r570 (F184). Reads and writes stay on staging. */
(() => {
  'use strict';
  const DAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
  const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  const DAY_LABEL = { monday: 'Monday', tuesday: 'Tuesday', wednesday: 'Wednesday', thursday: 'Thursday', friday: 'Friday', saturday: 'Saturday', sunday: 'Sunday' };
  const state = { loaded: false, loading: false, payload: null, error: '', openBay: '', renameBay: '', bayErrors: {}, warnings: {} };

  function host() { return document.getElementById('bay-manager-content'); }
  function role() { return window.PDC_AUTH_CONTEXT?.role || ''; }
  function canWrite(payload) {
    return payload?.can_write === true || role() === 'operator' || role() === 'administrator';
  }
  function canHide() { return role() === 'administrator'; }

  async function rpc(name, body) {
    const config = window.PDC_SUPABASE_CONFIG;
    const actor = window.PDC_AUTH_CONTEXT?.userId;
    const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '';
    if (!actor || !token || config?.projectRef !== 'cdsmnqxtyyoeoznmbidd') throw Error('Sign in on staging to read bay hours.');
    const response = await fetch(`${config.url.replace(/\/$/, '')}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body || {}),
    });
    const data = await response.json().catch(() => ({}));
    if (response.status === 404) {
      const missing = new Error('Bay hours are not on this database yet. This preview has not been applied.');
      missing.code = 'missing';
      throw missing;
    }
    if (!response.ok) throw Error(data?.message || data?.error || 'The bay hours could not be read.');
    if (data?.ok === false) throw Error(data.error === 'not_authorized' ? 'You can view this page once your role includes the workshop.' : (data.error || 'The change was refused.'));
    return data;
  }

  function applyPlanner(payload) {
    const map = {};
    for (const station of payload?.stations || []) {
      for (const bay of station.bays || []) {
        if (bay.override) map[`${bay.stage}:${bay.bay_number}`] = bay.override;
      }
    }
    if (typeof workshopSetBayHours570 === 'function') workshopSetBayHours570(map);
  }

  async function load(force) {
    if (String(window.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase() === 'fitter') return; // r616 (F231): Fitters bay only
    if (state.loading) return state.payload;
    if (state.loaded && !force) return state.payload;
    state.loading = true;
    try {
      const data = await rpc('list_workshop_bay_hours_570', {});
      state.payload = data;
      state.error = '';
      state.loaded = true;
      applyPlanner(data);
      return data;
    } catch (error) {
      state.error = error.message;
      state.loaded = error.code === 'missing';
      if (error.code === 'missing' && typeof workshopSetBayHours570 === 'function') workshopSetBayHours570(null);
      return null;
    } finally {
      state.loading = false;
    }
  }

  function hoursFor(bay) {
    return bay.override || bay.station_default;
  }
  function summary(bay) {
    const hours = hoursFor(bay);
    const monday = hours?.monday;
    if (!monday) return 'Hours unavailable';
    if (bay.override) return `Saved week · Mon ${monday.off ? 'off' : `${monday.start}–${monday.finish}`}`;
    return bay.source === 'bus_shift' ? `Bus shift · Mon ${monday.off ? 'off' : `${monday.start}–${monday.finish}`}` : `Workshop calendar · Mon ${monday.off ? 'off' : `${monday.start}–${monday.finish}`}`;
  }
  // r640 (F255): no breaks. Craig does not want breaks in any job; saved weeks always carry none.
  function readWeek(form) {
    const hours = {};
    for (const day of DAYS) {
      const off = form.querySelector(`[data-off="${day}"]`)?.checked === true;
      const start = form.querySelector(`[data-start="${day}"]`)?.value || '06:00';
      const finish = form.querySelector(`[data-finish="${day}"]`)?.value || '16:30';
      hours[day] = { off, start, finish, breaks: [] };
    }
    return hours;
  }
  function weekTable(bay, writable) {
    const hours = hoursFor(bay);
    const rows = DAYS.map(day => {
      const spec = hours?.[day] || { off: true, start: '06:00', finish: '16:30' };
      return `<tr>
        <th scope="row">${DAY_LABEL[day].slice(0, 3)}</th>
        <td><label class="bay-manager-off"><input data-off="${day}" type="checkbox" ${spec.off ? 'checked' : ''} ${writable ? '' : 'disabled'} aria-label="${DAY_LABEL[day]} day off"> Off</label></td>
        <td><input data-start="${day}" type="time" value="${esc(spec.start || '06:00')}" ${writable ? '' : 'disabled'} aria-label="${DAY_LABEL[day]} start"></td>
        <td><input data-finish="${day}" type="time" value="${esc(spec.finish || '16:30')}" ${writable ? '' : 'disabled'} aria-label="${DAY_LABEL[day]} finish"></td>
      </tr>`;
    }).join('');
    return `<table class="bay-manager-week"><thead><tr><th>Day</th><th></th><th>Start</th><th>Finish</th></tr></thead><tbody>${rows}</tbody></table>`;
  }
  const BAY_ERRORS = {
    bay_in_use: 'This bay has open bookings. Move or finish them, then hide it.',
    version_conflict: 'Someone else just changed this bay. Try again.',
    display_name_length: 'Names are 1 to 40 characters.',
  };
  function bayError(bayId, error) {
    state.bayErrors[bayId] = BAY_ERRORS[error?.message] || error?.message || 'That change was refused.';
    render();
  }
  function warningHtml(bayId) {
    const warning = state.warnings[bayId];
    if (!warning) return '';
    const items = (warning.outside || []).map(row => `<li>${esc(row.stock_number || 'Stock')} · key ${esc(row.key_number || '—')} · ${esc(row.bay)} · ${esc(row.status)}</li>`).join('');
    const more = warning.outside_truncated ? ' More bookings were not listed.' : '';
    return `<p class="bay-manager-warning"><strong>Hours saved. Existing bookings were not moved.</strong>${items ? ` These bookings now sit outside the hours:${more}<ul>${items}</ul>` : ' None of the open bookings on the changed bays sit outside the hours.'}</p>`;
  }

  function render() {
    const root = host();
    if (!root) return;
    root.replaceChildren();
    const wrap = document.createElement('div');
    wrap.className = 'bay-manager';
    const title = document.createElement('h2');
    title.textContent = 'Bay Manager';
    const lead = document.createElement('p');
    lead.className = 'bay-manager-lead';
    lead.textContent = 'Tap the pencil to rename a bay. Edit hours sets its working week (no breaks). Saving does not move bookings.';
    wrap.append(title, lead);
    if (state.loading && !state.payload) {
      const waiting = document.createElement('p');
      waiting.textContent = 'Loading bays…';
      wrap.append(waiting);
      root.append(wrap);
      return;
    }
    if (state.error) {
      const problem = document.createElement('p');
      problem.className = 'bay-manager-warning';
      problem.textContent = state.error;
      wrap.append(problem);
    }
    const payload = state.payload;
    const writable = canWrite(payload);
    if (payload && !writable) {
      const note = document.createElement('p');
      note.className = 'bay-manager-note';
      note.textContent = 'You can read these hours. A workshop controller or an administrator can change them.';
      wrap.append(note);
    }
    for (const station of payload?.stations || []) {
      const section = document.createElement('section');
      section.className = 'bay-manager-station';
      const header = document.createElement('header');
      header.textContent = station.label;
      section.append(header);
      for (const bay of station.bays || []) {
        // r640 (F255): one slim row per bay: name with a pencil, code, state, hours, then Edit hours and Hide on the right.
        const article = document.createElement('article');
        article.className = `bay-manager-bay${bay.is_active ? '' : ' is-hidden-bay'}`;
        const row = document.createElement('div');
        row.className = 'bay-manager-row';
        const renaming = state.renameBay === bay.id;
        const open = state.openBay === bay.id;
        row.innerHTML = `${renaming
            ? `<form class="bay-manager-rename"><input type="text" name="display" maxlength="40" value="${esc(bay.display_name || '')}" aria-label="Name for ${esc(bay.code)}"><button type="submit" class="bay-manager-primary">Save name</button><button type="button" data-rename-cancel>Cancel</button></form>`
            : `<strong class="bay-manager-name">${esc(bay.display_name)}</strong>${writable ? `<button type="button" class="bay-manager-pencil" data-rename title="Change name" aria-label="Change name of ${esc(bay.display_name)}">&#9998;</button>` : ''}`}<span class="bay-manager-code">${esc(bay.code)}</span><span class="bay-manager-state ${bay.is_active ? 'is-active' : 'is-hidden'}">${bay.is_active ? 'Active' : 'Hidden'}</span><span class="bay-manager-source">${esc(summary(bay))}</span><span class="bay-manager-row-actions"><button type="button" data-hours>${open ? 'Close hours' : 'Edit hours'}</button>${canHide() ? `<button type="button" data-active>${bay.is_active ? 'Hide bay' : 'Show bay'}</button>` : ''}</span>`;
        article.append(row);
        row.querySelector('[data-rename]')?.addEventListener('click', () => { state.renameBay = bay.id; delete state.bayErrors[bay.id]; render(); host()?.querySelector('.bay-manager-rename input')?.focus(); });
        row.querySelector('[data-rename-cancel]')?.addEventListener('click', () => { state.renameBay = ''; render(); });
        row.querySelector('.bay-manager-rename')?.addEventListener('submit', async event => {
          event.preventDefault();
          if (!writable) return;
          try {
            await rpc('set_workshop_bay_display_name', { p_bay_id: bay.id, p_expected_version: bay.bay_version, p_display_name: new FormData(event.currentTarget).get('display') });
            state.renameBay = ''; delete state.bayErrors[bay.id];
            await refresh();
          } catch (error) { bayError(bay.id, error); }
        });
        row.querySelector('[data-active]')?.addEventListener('click', async () => {
          if (!canHide()) return;
          try {
            await rpc('set_workshop_bay_active', { p_bay_id: bay.id, p_expected_version: bay.bay_version, p_active: !bay.is_active });
            delete state.bayErrors[bay.id];
            await refresh();
          } catch (error) { bayError(bay.id, error); }
        });
        row.querySelector('[data-hours]')?.addEventListener('click', () => { state.openBay = open ? '' : bay.id; render(); });
        if (state.bayErrors[bay.id]) {
          const problem = document.createElement('p');
          problem.className = 'bay-manager-warning bay-manager-bay-error';
          problem.textContent = state.bayErrors[bay.id];
          article.append(problem);
        }
        if (open) {
          const form = document.createElement('form');
          form.className = 'bay-manager-hours';
          form.innerHTML = `${weekTable(bay, writable)}<div class="bay-manager-actions"><button class="bay-manager-primary" type="submit" ${writable ? '' : 'disabled'}>Save hours</button><button type="button" data-copy="1" ${writable ? '' : 'disabled'}>Copy to all bays in station</button><button type="button" data-reset="1" ${writable ? '' : 'disabled'}>Reset to station default</button></div>`;
          form.addEventListener('submit', event => { event.preventDefault(); void save(bay, 'save', readWeek(form)); });
          form.querySelector('[data-copy]')?.addEventListener('click', () => { void save(bay, 'copy', readWeek(form)); });
          form.querySelector('[data-reset]')?.addEventListener('click', () => { void save(bay, 'reset', null); });
          article.append(form);
        }
        if (state.warnings[bay.id]) {
          const warning = document.createElement('div');
          warning.innerHTML = warningHtml(bay.id);
          article.append(warning);
        }
        section.append(article);
      }
      wrap.append(section);
    }
    root.append(wrap);
  }

  async function save(bay, mode, hours) {
    try {
      const result = await rpc('set_workshop_bay_hours_570', {
        p_bay_id: bay.id,
        p_expected_version: bay.hours_version,
        p_hours: hours,
        p_mode: mode,
      });
      state.warnings[bay.id] = result;
      state.error = '';
      await refresh();
    } catch (error) {
      bayError(bay.id, error);
    }
  }
  async function refresh() {
    await load(true);
    render();
    if (typeof renderWorkshopPlanner === 'function' && document.body?.dataset?.currentView?.startsWith('planner-')) renderWorkshopPlanner();
  }

  let painted = false;
  async function ensure() {
    if (!window.PDC_AUTH_CONTEXT?.userId || state.loading) return;
    if (!state.loaded) await load(false);
    if (state.payload) applyPlanner(state.payload);
    const onPlanner = document.body?.dataset?.currentView?.startsWith('planner-');
    if (!painted && state.payload && onPlanner && typeof renderWorkshopPlanner === 'function') {
      painted = true;
      renderWorkshopPlanner();
    }
    if (document.getElementById('bay-manager')?.classList.contains('active')) render();
  }

  window.PdcBayManager = {
    open() { void load(true).then(render); },
    close() {},
    reset() { state.loaded = false; state.payload = null; state.error = ''; state.warnings = {}; painted = false; host()?.replaceChildren(); if (typeof workshopSetBayHours570 === 'function') workshopSetBayHours570(null); },
    ensure,
    syncAccess() {},
  };
  window.addEventListener('pdc-auth-ready', () => { painted = false; state.loaded = false; void ensure(); });
  window.addEventListener('pdc-auth-locked', () => window.PdcBayManager.reset());
})();
