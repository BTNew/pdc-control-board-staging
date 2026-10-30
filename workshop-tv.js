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
  const VERSION = '2026.10.30.r744';
  // r706 (F316, Craig 29 Oct): Tint and Tyres sit side by side at the bottom with each job's full key and Start / Stop.
  // They have one line and no iPad. Every other station stays view-only.
  // r744 (F349, Craig 30 Oct): the bottom is split in two, Tyres then Tint, one list per station with the whole day.
  const ACTION_STATIONS = ['TYRE', 'TINT'];
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
    let start = ms(job.start);
    let end = ms(job.end);
    // r686 (F296, Craig 29 Oct): a done job shows only from its actual start to when it was completed.
    const doneAt = state === 'done' ? ms(job.actual_end) : null;
    if (doneAt !== null) { end = doneAt; start = Math.min(ms(job.actual_start) ?? start ?? doneAt, doneAt); }
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
    const title = `${STATE_LABEL[state]} · ${label} · ${hhmm(start)}–${hhmm(doneAt ?? ms(job.end))}${job.stoppage ? ` · ${job.stoppage}` : ''}`;
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
  const isAction = s => ACTION_STATIONS.includes(String(s?.code || '').toUpperCase());
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
    const timeline = stations.filter(s => !isAction(s));
    const action = ACTION_STATIONS.map(code => stations.find(s => String(s.code).toUpperCase() === code)).filter(Boolean);
    // r744 (F349): two halves (Tyres, Tint), each listing the station's day across its visible bays.
    const actionHtml = action.length ? `<div class="tv-actions">${action.map(s => actionStationHtml(s, data, wins, now)).join('')}</div>` : '';
    return timeline.map(s => {
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
    }).join('') + actionHtml;
  }

  /**
   * r744 (F349, Craig 30 Oct): the day's jobs for one station, all its visible bays together.
   * Running and stopped jobs first, then today's waiting jobs by start time, then today's done jobs.
   * Two tinters and two tyre fitters work at once, so every waiting job has its own Start.
   * When nothing is left to start today, the next working day's jobs show so the fitters can pull work forward.
   */
  function stationDayJobs(station, wins, now) {
    const today = wins[0];
    const next = wins[1];
    const rows = [];
    for (const bay of station.bays || []) for (const j of bay.jobs || []) rows.push({ ...j, bay_id: bay.id, bay_name: bay.name });
    const rank = j => { const st = jobState(j, now); return st === 'live' || st === 'over' || st === 'stop' ? 0 : st === 'done' ? 2 : 1; };
    const startsBefore = (j, t) => { const st = ms(j.start); return st !== null && t && st < t; };
    const doneToday = j => { const end = ms(j.actual_end); return end !== null && today && end >= today.from && end < today.to; };
    let list = rows.filter(j => {
      const r = rank(j);
      if (r === 0) return true;
      if (r === 2) return doneToday(j);
      return startsBefore(j, today?.to);
    });
    if (!list.some(j => rank(j) === 1) && next) {
      list = list.concat(rows.filter(j => rank(j) === 1 && !startsBefore(j, today?.to) && startsBefore(j, next.to)).map(j => ({ ...j, later: true })));
    }
    return list.sort((a, b) => rank(a) - rank(b) || (ms(a.start) ?? 0) - (ms(b.start) ?? 0));
  }
  /** Kept for callers of r706-r741: the first three of a single bay's day. */
  function actionJobs(bay, wins, now) {
    return stationDayJobs({ bays: [bay] }, wins, now).filter(j => jobState(j, now) !== 'done').slice(0, 3);
  }
  /**
   * r744 (F349, Craig 30 Oct 08:52): "have them in this section, have the next 8 jobs in the boxes shown below".
   * Each half: the running jobs across the top (Complete), then the next 8 waiting jobs as boxes (Start on each),
   * today first and then the next working day. Done jobs are only counted in the header.
   */
  const NEXT_BOXES = 8;
  function stationBoard(station, wins, now) {
    const rows = [];
    for (const bay of station.bays || []) for (const j of bay.jobs || []) rows.push({ ...j, bay_id: bay.id, bay_name: bay.name });
    const today = wins[0];
    const byStart = (a, b) => (ms(a.start) ?? 0) - (ms(b.start) ?? 0);
    const running = rows.filter(j => ['live', 'over', 'stop'].includes(jobState(j, now))).sort(byStart);
    const next = rows.filter(j => jobState(j, now) === 'plan' && ms(j.start) !== null).sort(byStart).slice(0, NEXT_BOXES)
      .map(j => (today && ms(j.start) >= today.to ? { ...j, later: true } : j));
    const done = rows.filter(j => { const end = ms(j.actual_end); return jobState(j, now) === 'done' && end !== null && today && end >= today.from && end < today.to; }).length;
    return { running, next, done };
  }
  function actionStationHtml(s, data, wins, now) {
    const canAct = data?.can_act === true;
    const { running, next, done } = stationBoard(s, wins, now);
    const multiBay = (s.bays || []).length > 1;
    const button = (j, kind) => {
      if (!canAct || !j.id || !Number.isInteger(Number(j.booking_version))) return '';
      const key = esc(j.key || '');
      return kind === 'start'
        ? `<button type="button" class="tv-act tv-act-start" data-tv-act="start" data-id="${esc(j.id)}" data-v="${esc(j.booking_version)}" data-work="${esc(s.work_key || '')}" aria-label="Start key ${key}">Start</button>`
        : `<button type="button" class="tv-act tv-act-stop" data-tv-act="stop" data-id="${esc(j.id)}" data-v="${esc(j.booking_version)}" data-work="${esc(s.work_key || '')}" aria-label="Complete key ${key}">Complete</button>`;
    };
    const keyText = j => (j.key ? `Key ${esc(j.key)}` : 'No key');
    const info = j => esc([j.vehicle || '', multiBay ? j.bay_name : ''].filter(Boolean).join(' · '));
    const when = j => { const st = ms(j.start); return st === null ? '' : `${dayLabel(st) === dayLabel(now) ? '' : `${dayLabel(st)} `}${hhmm(st)}`; };
    const runHtml = running.map(j => {
      const state = jobState(j, now);
      const since = ms(j.actual_start ?? j.start);
      const tag = state === 'over' ? 'OVER TIME' : state === 'stop' ? 'STOPPAGE' : `Since ${since !== null ? hhmm(since) : '-'}`;
      return `<li class="tv-aj tv-run is-${state}"><strong class="tv-aj-key">${keyText(j)}</strong><span class="tv-aj-info">${info(j)}</span><span class="tv-aj-when">${esc(tag)}</span>${button(j, 'stop')}</li>`;
    }).join('') || '<li class="tv-aj is-empty">Nothing running</li>';
    const boxes = next.map(j => `<li class="tv-box is-plan${j.later ? ' is-later' : ''}"><strong class="tv-aj-key">${keyText(j)}</strong><span class="tv-aj-info">${info(j)}</span><span class="tv-aj-when">${esc(when(j))}</span>${button(j, 'start')}</li>`).join('')
      || '<li class="tv-box is-empty">No jobs booked</li>';
    const counts = `<small>${running.length} running · ${done} done today</small>`;
    return `<section class="tv-astation tv-zone" data-station="${esc(s.code)}" data-bay="${esc(s.code)}"><h2>${esc(s.name)} ${counts}</h2><ul class="tv-running">${runHtml}</ul><p class="tv-next-head">Next ${NEXT_BOXES}</p><ul class="tv-next">${boxes}</ul></section>`;
  }

  function rowCount(data, hidden) {
    return visibleStations(data, hidden).filter(s => !isAction(s)).reduce((sum, s) => sum + s.bays.length + 1.4, 0);
  }

  const api = { VERSION, ACTION_STATIONS, actionJobs, stationDayJobs, stationBoard, actionStationHtml, jobState, barHtml, boardHtml, hoursHtml, parseHidden, pct, perth, hhmm, dayLabel, rowCount, windows, visibleStations, bayKey };
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
    const actions = board.querySelector('.tv-actions');
    const avail = window.innerHeight - ($('tv-head')?.offsetHeight || 60) - 16 - (actions ? actions.offsetHeight + 8 : 0);
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
    if (typeof paintNotes === 'function') paintNotes();
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
  // r706: Start / Stop for Tint and Tyres. Stop finishes the booking (complete), the same as Complete on the planner.
  let acting = false;
  // r711 (F321, Craig 29 Oct): the answer shows in big type on the bay itself for 20 seconds, and the board reloads
  // straight away. A refused Start (e.g. an admin block in the bay) used to show only in the small status line.
  const notes = new Map();
  const TV_ERRORS = {
    admin_block_conflict: 'an admin block is booked in this bay before this job would finish. Move or delete the block on the planner, then press Start again.',
    version_conflict: 'the board changed. Press it again.',
    lock_busy: 'the board was busy. Press it again.',
    booking_version_conflict: 'the board changed. Press it again.',
    not_authorized: 'this TV login cannot start or complete jobs. Sign in with a controller login.',
    bay_already_started: 'another job is already running in this bay. The board allows one running job per bay.',
  };
  function tvReason(error, result) {
    const code = String(result?.error || result?.code || '').trim();
    if (TV_ERRORS[code]) return TV_ERRORS[code];
    if (/operator or administrator/i.test(error?.message || '')) return TV_ERRORS.not_authorized;
    if (/lock timeout|deadlock/i.test(error?.message || '')) return TV_ERRORS.lock_busy;
    return String(result?.message || error?.message || code || 'refresh and try again').slice(0, 140);
  }
  function paintNotes() {
    const now = Date.now();
    for (const [bay, n] of notes) {
      if (n.until < now) { notes.delete(bay); continue; }
      const zone = document.querySelector(`.tv-zone[data-bay="${CSS.escape(bay)}"]`);
      if (!zone || zone.querySelector('.tv-znote')) continue;
      const div = document.createElement('div');
      div.className = `tv-znote ${n.ok ? 'is-ok' : 'is-bad'}`;
      div.textContent = n.text;
      zone.insertBefore(div, zone.querySelector('ul'));
    }
  }
  async function act(button) {
    if (acting || !client) return;
    const id = button.dataset.id, version = Number(button.dataset.v), kind = button.dataset.tvAct;
    if (!id || !Number.isInteger(version)) return;
    acting = true;
    const bay = button.closest('[data-bay]')?.dataset.bay || '';
    const keyText = button.closest('.tv-aj')?.querySelector('.tv-aj-key')?.textContent || 'This job';
    button.disabled = true;
    button.textContent = kind === 'start' ? 'Starting…' : 'Completing…';
    let note = '';
    try {
      // r741 (Craig 30 Oct): the button reads Complete. A lock timeout or deadlock means the board was busy
      // (someone moving cars at the same moment); nothing was saved, so try once more before showing an error.
      const call = () => kind === 'start'
        ? client.rpc('start_workshop_work', { p_booking_id: id, p_expected_version: version, p_actual_start_at: null, p_metadata: { source: 'workshop_tv_706' } })
        : client.rpc('complete_workshop_work', { p_booking_id: id, p_expected_version: version, p_work_key: button.dataset.work || null, p_actual_end_at: null, p_metadata: { source: 'workshop_tv_706' } });
      let { data: result, error } = await call();
      if (error && /lock timeout|deadlock/i.test(error.message || '')) {
        await new Promise(r => setTimeout(r, 1500));
        ({ data: result, error } = await call());
      }
      if (error || result?.ok !== true) { note = `${keyText} NOT ${kind === 'start' ? 'started' : 'completed'}: ${tvReason(error, result)}`; if (bay) notes.set(bay, { text: note, ok: false, until: Date.now() + 20000 }); }
      else { note = `${keyText} ${kind === 'start' ? 'started' : 'done'}`; if (bay) notes.set(bay, { text: note, ok: true, until: Date.now() + 8000 }); }
    } catch (e) {
      note = 'Not saved. Check the connection and try again.';
      if (bay) notes.set(bay, { text: note, ok: false, until: Date.now() + 20000 });
    } finally {
      acting = false;
      $('tv-status').textContent = note;
      paintNotes();
      await load(); // refresh straight away
      paintNotes();
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
    $('tv-board').addEventListener('click', event => { const b = event.target.closest?.('[data-tv-act]'); if (b) act(b); });
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
