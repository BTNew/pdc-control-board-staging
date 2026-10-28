/*
 * r605 (F219): Workshop TV. Craig, 28 Oct 2026.
 * A view-only board for the workshop screen: every station's bays on today and the next working day, coloured like
 * the planner (blue = running, red flashing = running past its end, amber = stoppage, green = done).
 * Light on purpose: one read (get_pdc_workshop_tv_605) a minute, no realtime channel, one innerHTML
 * per refresh, and the "now" line moves through a CSS variable. Paused while the screen is hidden.
 * Controls: the gear hides or shows stations and single bays on this screen (saved in this browser), and
 * Full screen. ?hide=TINT,TYRE in the address hides stations for a kiosk link.
 */
(function (root) {
  'use strict';
  const VERSION = '2026.10.28.r608';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const HIDDEN_KEY = 'pdc.workshop-tv.hidden.v1';
  const REFRESH_MS = 60 * 1000;
  const TICK_MS = 30 * 1000;
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  const esc = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
  const ms = value => { const t = Date.parse(value || ''); return Number.isFinite(t) ? t : null; };
  /** Perth wall-clock parts for a timestamp (Perth has no daylight saving: UTC+8). */
  function perth(t) {
    const d = new Date(t + 8 * 3600 * 1000);
    return { y: d.getUTCFullYear(), mo: d.getUTCMonth(), d: d.getUTCDate(), wd: d.getUTCDay(), h: d.getUTCHours(), mi: d.getUTCMinutes() };
  }
  const hhmm = t => { const p = perth(t); return `${String(p.h).padStart(2, '0')}:${String(p.mi).padStart(2, '0')}`; };
  const dayLabel = t => { const p = perth(t); return `${DAYS[p.wd]} ${p.d} ${MONTHS[p.mo]}`; };

  /** Window position (0-100 %) of a moment; clamped. */
  function pct(t, from, to) { return Math.max(0, Math.min(100, ((t - from) / (to - from)) * 100)); }

  /** State class for a job, using the live clock so red shows between reads. */
  function jobState(job, now) {
    const end = ms(job.end);
    if (job.status === 'completed') return 'done';
    if (job.status === 'stoppage') return job.overrun ? 'over' : 'stop';
    if (job.status === 'started') return job.overrun || (end !== null && now > end) ? 'over' : 'live';
    return 'plan';
  }
  const STATE_LABEL = { live: 'LIVE', over: 'OVER TIME', stop: 'STOPPAGE', done: 'DONE', plan: 'PLANNED' };

  /** One bar, clipped to the day. A running job past its end stretches to now. Null if off the day. */
  function barHtml(job, { from, to, now, edge = true }) {
    const state = jobState(job, now);
    const start = ms(job.start);
    let end = ms(job.end);
    if (start === null || end === null) return '';
    if (state === 'over') end = Math.max(end, now);
    if (end <= from || start >= to) {
      if (edge && (state === 'live' || state === 'over' || state === 'stop')) {
        // Live work booked outside today's window still shows, pinned to the edge it falls past.
        const left = start >= to ? 98 : 0;
        return `<div class="tv-job is-${state} is-edge" style="left:${left}%;width:2%" title="${esc(`${STATE_LABEL[state]} · K${job.key || '-'} · ${job.stock || ''}`)}"></div>`;
      }
      return '';
    }
    const left = pct(start, from, to);
    const width = Math.max(1.2, pct(end, from, to) - left);
    const over = state === 'over' && ms(job.end) !== null ? ` · due ${hhmm(ms(job.end))}` : '';
    const label = [job.key ? `K${job.key}` : '', job.stock || '', job.vehicle || ''].filter(Boolean).join(' · ');
    const tag = state === 'over' ? 'OVER' : state === 'stop' ? 'STOP' : '';
    const title = `${STATE_LABEL[state]} · ${label} · ${hhmm(start)}–${hhmm(ms(job.end))}${job.stoppage ? ` · ${job.stoppage}` : ''}`;
    return `<div class="tv-job is-${state}" style="left:${left.toFixed(2)}%;width:${width.toFixed(2)}%" title="${esc(title)}">${tag ? `<b>${tag}</b>` : ''}<span>${esc(label)}${esc(over)}</span></div>`;
  }

  /** Hour ticks across the window. */
  function hoursHtml(from, to) {
    const out = [];
    const first = Math.ceil(from / 3600000) * 3600000;
    for (let t = first; t < to; t += 3600000) out.push(`<span style="left:${pct(t, from, to).toFixed(2)}%">${perth(t).h}</span>`);
    return out.join('');
  }

  function parseHidden(search, stored) {
    const fromUrl = /[?&]hide=([^&]*)/.exec(search || '');
    const list = fromUrl ? decodeURIComponent(fromUrl[1]).split(',') : (Array.isArray(stored) ? stored : []);
    return new Set(list.map(code => String(code).trim().toUpperCase()).filter(Boolean));
  }

  /** The two day windows from the read (today and the next working day). */
  function windows(data) {
    const list = Array.isArray(data?.days) ? data.days : (data?.from ? [{ date: data.day, from: data.from, to: data.to }] : []);
    return list.map(d => ({ date: d.date, from: ms(d.from), to: ms(d.to) })).filter(w => w.from !== null && w.to !== null && w.to > w.from);
  }
  const bayKey = id => `BAY:${String(id || '').toUpperCase()}`;
  function visibleStations(data, hidden) {
    return (data?.stations || [])
      .filter(s => !hidden.has(String(s.code).toUpperCase()))
      .map(s => ({ ...s, bays: (s.bays || []).filter(b => !hidden.has(bayKey(b.id))) }))
      .filter(s => s.bays.length);
  }

  /** The whole board for one read. */
  function boardHtml(data, { hidden = new Set(), now = Date.now() } = {}) {
    const wins = windows(data);
    if (!wins.length) return '<p class="tv-msg">No workshop day to show.</p>';
    const stations = visibleStations(data, hidden);
    if (!stations.length) return '<p class="tv-msg">Every station is hidden. Use the gear to show some.</p>';
    const head = wins.map((w, i) => `<div class="tv-hours"><em>${i === 0 ? 'Today' : esc(dayLabel(w.from))}</em>${hoursHtml(w.from, w.to)}</div>`).join('');
    return stations.map(s => {
      const bays = s.bays.map(b => {
        const tracks = wins.map((w, i) => {
          const jobs = (b.jobs || []).map(j => barHtml(j, { from: w.from, to: w.to, now, edge: i === 0 })).join('');
          return `<div class="tv-track${i === 0 ? ' is-today' : ''}">${jobs}</div>`;
        }).join('');
        const live = (b.jobs || []).map(j => jobState(j, now));
        const flag = live.includes('over') ? ' has-over' : live.includes('live') ? ' has-live' : '';
        return `<div class="tv-bay${flag}"><div class="tv-bay-name"><strong>${esc(b.name)}</strong>${b.technician ? `<small>${esc(b.technician)}</small>` : ''}</div>${tracks}</div>`;
      }).join('');
      const over = s.bays.flatMap(b => (b.jobs || []).map(j => jobState(j, now))).filter(x => x === 'over').length;
      return `<section class="tv-station" data-station="${esc(s.code)}"><header><h2>${esc(s.name)}${over ? ` <span class="tv-over-count">${over} over time</span>` : ''}</h2>${head}</header>${bays}</section>`;
    }).join('');
  }

  function rowCount(data, hidden) {
    return visibleStations(data, hidden).reduce((sum, s) => sum + s.bays.length + 1.4, 0);
  }

  const api = { VERSION, jobState, barHtml, boardHtml, hoursHtml, parseHidden, pct, perth, hhmm, dayLabel, rowCount, windows, visibleStations, bayKey };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || typeof document === 'undefined') return;

  const $ = id => document.getElementById(id);
  let client = null;
  let data = null;
  let hidden = new Set();
  let lastOk = 0;
  let timer = null;

  function readStored() { try { return JSON.parse(localStorage.getItem(HIDDEN_KEY) || '[]'); } catch (_) { return []; } }
  function writeStored() { try { localStorage.setItem(HIDDEN_KEY, JSON.stringify([...hidden])); } catch (_) { /* this screen only */ } }

  function layout() {
    const rows = rowCount(data, hidden);
    const board = $('tv-board');
    const avail = window.innerHeight - ($('tv-head')?.offsetHeight || 60) - 16;
    const cols = 1; // two day tracks need the full width
    board.classList.toggle('two-col', cols === 2);
    const per = Math.ceil(rows / cols) + (cols === 2 ? 2 : 0);
    const h = Math.max(22, Math.min(64, Math.floor(avail / Math.max(per, 1))));
    document.documentElement.style.setProperty('--row-h', `${h}px`);
  }
  function tickNow() {
    const now = Date.now();
    $('tv-clock').textContent = `${dayLabel(now)} · ${hhmm(now)}`;
    if (!data) return;
    const today = windows(data)[0];
    if (today) {
      document.documentElement.style.setProperty('--now-pct', `${pct(now, today.from, today.to)}%`);
      document.documentElement.classList.toggle('tv-after-hours', now < today.from || now > today.to);
    }
    const stale = lastOk && now - lastOk > 5 * 60 * 1000;
    $('tv-status').textContent = stale ? `Not updated since ${hhmm(lastOk)}` : lastOk ? `Updated ${hhmm(lastOk)}` : '';
    $('tv-status').classList.toggle('is-stale', Boolean(stale));
  }
  function paint() {
    if (!data) return;
    $('tv-board').innerHTML = boardHtml(data, { hidden, now: Date.now() });
    layout();
    tickNow();
  }
  function paintPicker() {
    const list = $('tv-picker-list');
    list.innerHTML = (data?.stations || []).map(s => {
      const off = hidden.has(String(s.code).toUpperCase());
      const bays = (s.bays || []).map(b => `<label class="tv-pick-bay"><input type="checkbox" id="tv-show-${esc(b.id)}" data-code="${esc(bayKey(b.id))}"${hidden.has(bayKey(b.id)) ? '' : ' checked'}${off ? ' disabled' : ''}> ${esc(b.name)}</label>`).join('');
      return `<div class="tv-pick-station"><label><input type="checkbox" id="tv-show-${esc(s.code)}" data-code="${esc(s.code)}"${off ? '' : ' checked'}> <strong>${esc(s.name)}</strong></label>${bays}</div>`;
    }).join('') || '<p>No stations yet.</p>';
  }
  async function load() {
    if (!client || document.visibilityState === 'hidden') return;
    try {
      const { data: json, error } = await client.rpc('get_pdc_workshop_tv_605');
      if (error) throw error;
      if (!json) { showGate('This login cannot see the workshop board. Use an approved board login.'); return; }
      data = json; lastOk = Date.now();
      $('tv-gate').hidden = true;
      paint();
    } catch (_) {
      tickNow(); // keep the last picture; the status line turns stale after 5 minutes
    }
  }
  function showGate(message, signIn = true) {
    $('tv-gate').hidden = false;
    $('tv-gate-msg').textContent = message;
    $('tv-signin').hidden = !signIn;
    if (signIn) setTimeout(() => $('tv-email')?.focus(), 0);
  }
  // r608 (F222): the TV signs in on its own screen. It used to rely on a board sign-in in the same browser,
  // which a fresh TV browser does not have, so it only showed a message.
  async function signIn(event) {
    event.preventDefault();
    const button = $('tv-signin-go');
    button.disabled = true;
    $('tv-signin-error').textContent = '';
    try {
      const { error } = await client.auth.signInWithPassword({ email: $('tv-email').value.trim(), password: $('tv-password').value });
      if (error) throw error;
      $('tv-password').value = '';
      $('tv-gate').hidden = true;
      await load();
      schedule();
    } catch (error) {
      $('tv-signin-error').textContent = /invalid/i.test(error?.message || '') ? 'Email or password is wrong.' : `Could not sign in. ${error?.message || ''}`.trim();
    } finally {
      button.disabled = false;
    }
  }
  function schedule() {
    clearInterval(timer);
    timer = setInterval(load, REFRESH_MS);
  }

  async function start() {
    hidden = parseHidden(location.search, readStored());
    $('tv-gear').addEventListener('click', () => { const p = $('tv-picker'); p.hidden = !p.hidden; if (!p.hidden) paintPicker(); });
    $('tv-picker-close').addEventListener('click', () => { $('tv-picker').hidden = true; });
    $('tv-picker-list').addEventListener('change', event => {
      const code = String(event.target?.dataset?.code || '').toUpperCase();
      if (!code) return;
      if (event.target.checked) hidden.delete(code); else hidden.add(code);
      writeStored(); paintPicker(); paint();
    });
    $('tv-picker-all').addEventListener('click', () => { hidden.clear(); writeStored(); paintPicker(); paint(); });
    $('tv-full').addEventListener('click', () => {
      try { if (document.fullscreenElement) document.exitFullscreen(); else document.documentElement.requestFullscreen(); } catch (_) { /* browser refused */ }
    });
    document.addEventListener('fullscreenchange', () => { $('tv-full').textContent = document.fullscreenElement ? 'Exit full screen' : 'Full screen'; if (data) layout(); });
    window.addEventListener('resize', () => { if (data) layout(); });
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') load(); });
    setInterval(() => { tickNow(); if (data && document.visibilityState === 'visible') paint(); }, TICK_MS);
    tickNow();

    const config = window.PDC_SUPABASE_CONFIG;
    if (!window.supabase?.createClient || config?.projectRef !== PROJECT) { showGate('The board settings did not load. Refresh the page.', false); return; }
    client = window.supabase.createClient(config.url, config.publishableKey, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: false } });
    $('tv-signin').addEventListener('submit', signIn);
    const { data: session } = await client.auth.getSession();
    if (!session?.session) { showGate('Sign in once on this TV. It stays signed in.'); return; }
    client.auth.onAuthStateChange((event, next) => { if (event === 'SIGNED_OUT' || !next) showGate('Signed out. Sign in again.'); });
    await load();
    schedule();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
}(typeof window !== 'undefined' ? window : globalThis));
