'use strict';
// r891 (F441): owner snapshot page. One read-only call (get_pdc_owner_snapshot_891), refreshed every 2 minutes.
// The database decides who may see it (pdc_owner_private.viewers: Craig and Dave).
(function () {
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const REFRESH_MS = 120000;
  const STALE_MS = 10 * 60000;
  const STATION_COLOURS = { Fitting: '--blue', Hoist: '--violet', Electrical: '--amber', Tyre: '--slate', Tint: '--teal', Fab: '--orange', Bus4x4: '--pink', Other: '--sky' };
  const AGE_COLOURS = ['--green', '--green', '--amber', '--red', '--red'];
  const $ = (id) => document.getElementById(id);
  let client = null;
  let timer = null;
  let lastOk = 0;

  const fmt = (v) => {
    if (v == null || v === '') return '-';
    const n = Number(v);
    if (!Number.isFinite(n)) return String(v);
    return Number.isInteger(n) ? n.toLocaleString('en-AU') : n.toLocaleString('en-AU', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
  };
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const perthTime = (iso) => new Date(iso).toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });

  function renderHeadline(h) {
    document.querySelectorAll('[data-h]').forEach((node) => { node.textContent = fmt(h?.[node.dataset.h]); });
  }

  function renderStations(stations, bays) {
    const wrap = $('own-stations');
    wrap.replaceChildren(...(stations || []).map((s) => {
      const tile = el('div', 'tile stn');
      tile.style.setProperty('--c', `var(${STATION_COLOURS[s.station] || '--sky'})`);
      const top = el('div', 'stn-top');
      top.append(el('span', 'stn-name', s.station), el('span', 'num', fmt(s.booked)));
      const sub = el('span', 'sub', `${fmt(s.running)} running · ${fmt(s.bays_with_work)} of ${fmt(s.bays)} bays with work`);
      const list = el('div', 'bays');
      const rows = (bays || []).filter((b) => b.station === s.station);
      const max = Math.max(1, ...rows.map((b) => b.booked));
      rows.forEach((b) => {
        const row = el('div', 'bay');
        const name = el('span', 'bay-name');
        name.append(el('i', 'dot' + (b.stopped > 0 ? ' stop' : b.running > 0 ? ' run' : '')), el('span', null, String(b.bay).replace(' - Bus4x4 Bay ', ' ')));
        name.title = b.bay;
        const track = el('div', 'track');
        const fill = el('div', 'fill');
        fill.style.width = `${(b.booked / max) * 100}%`;
        track.append(fill);
        row.append(name, track, el('span', 'cnt', fmt(b.booked)));
        list.append(row);
      });
      tile.append(top, sub, list);
      return tile;
    }));
  }

  function renderAge(age) {
    const rows = age || [];
    const max = Math.max(1, ...rows.map((r) => r.cars));
    $('own-age').replaceChildren(...rows.map((r, i) => {
      const row = el('div', 'age-row');
      const bar = el('div', 'age-bar');
      bar.style.width = `${(r.cars / max) * 100}%`;
      bar.style.background = `var(${AGE_COLOURS[i] || '--red'})`;
      row.append(el('span', null, r.bucket), bar, el('span', 'cnt', fmt(r.cars)));
      return row;
    }));
  }

  function renderOldest(oldest) {
    $('own-oldest').replaceChildren(...(oldest || []).map((r) => {
      const tr = el('tr');
      const days = el('td', 'days ' + (r.days >= 60 ? 'hot' : r.days >= 30 ? 'warm' : ''), fmt(r.days));
      const model = el('td', 'model', r.model);
      model.title = r.model || '';
      tr.append(el('td', 'key', r.key_number), model, days,
        el('td', r.booked ? 'good' : 'warm', r.booked ? 'Yes' : 'No'),
        el('td', r.waiting_parts ? 'hot' : '', r.waiting_parts ? 'Yes' : 'No'));
      return tr;
    }));
  }

  function markStale() {
    const asof = $('own-asof');
    asof.classList.toggle('is-stale', lastOk > 0 && Date.now() - lastOk > STALE_MS);
  }

  async function load() {
    if (!client) return;
    const { data, error } = await client.rpc('get_pdc_owner_snapshot_891');
    if (error) {
      if (error.code === '42501' || /owner logins only/i.test(error.message || '')) {
        showGate('This login cannot open the owner snapshot. Ask Craig for access.', true);
        return;
      }
      $('own-asof').textContent = `Could not refresh: ${error.message || 'connection problem'}`;
      $('own-asof').classList.add('is-stale');
      return;
    }
    lastOk = Date.now();
    $('own-gate').hidden = true;
    $('own-main').hidden = false;
    renderHeadline(data?.headline);
    renderStations(data?.stations, data?.bays);
    renderAge(data?.age);
    renderOldest(data?.oldest);
    $('own-asof').textContent = `Live · ${perthTime(data?.as_of || new Date().toISOString())} Perth`;
    markStale();
  }

  function schedule() {
    clearInterval(timer);
    timer = setInterval(() => { load(); markStale(); }, REFRESH_MS);
  }

  function showGate(message, signedIn) {
    clearInterval(timer);
    $('own-main').hidden = true;
    $('own-gate').hidden = false;
    $('own-gate-msg').textContent = message || '';
    $('own-signin').hidden = !!signedIn;
  }

  async function start() {
    const config = window.PDC_SUPABASE_CONFIG;
    if (!window.supabase?.createClient || config?.projectRef !== PROJECT) { showGate('The board settings did not load. Refresh the page.', false); return; }
    client = window.supabase.createClient(config.url, config.publishableKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } });
    const { data: session } = await client.auth.getSession();
    client.auth.onAuthStateChange((event, next) => { if (event === 'SIGNED_OUT' || !next) showGate('Signed out. Sign in again.', false); });
    if (!session?.session) { showGate('', false); return; }
    await load();
    schedule();
  }

  $('own-signin').addEventListener('submit', async (event) => {
    event.preventDefault();
    $('own-signin-error').textContent = '';
    const { error } = await client.auth.signInWithPassword({ email: $('own-email').value.trim(), password: $('own-password').value });
    if (error) { $('own-signin-error').textContent = error.message || 'Sign-in failed.'; return; }
    $('own-password').value = '';
    await load();
    schedule();
  });
  $('own-refresh').addEventListener('click', () => load());
  $('own-signout').addEventListener('click', async () => { if (client) await client.auth.signOut(); showGate('Signed out.', false); });
  document.addEventListener('visibilitychange', () => { if (!document.hidden && client) load(); });

  start();
})();
