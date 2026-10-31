/* Admin > Revolution uploads. r591 dry run; r728 (F338): Apply on for Service as a Whole (Kajel switched off 29 Oct 2026). */
function revolutionUploadParts(file, token) {
  const form = new FormData();
  form.append('file', file, file.name);
  const headers = {};
  if (typeof token === 'string' && /^[\u0000-\u00FF]*$/.test(token)) headers.Authorization = `Bearer ${token}`;
  return { form, headers };
}
if (typeof module !== 'undefined' && module.exports) module.exports = { revolutionUploadParts };

if (typeof window !== 'undefined') (function () {
  const STAGING = 'cdsmnqxtyyoeoznmbidd';
  const PRODUCTION = 'vjdtsswhroyguxyfjdkt';
  const LOG_KEY = 'pdc-revolution-upload-log-r591';
  let wired = false;

  function endpoint() {
    const override = new URLSearchParams(location.search).get('uploadEndpoint');
    if (override) {
      if (override.includes(PRODUCTION)) throw new Error('Production is not a target.');
      return override;
    }
    const config = window.PDC_SUPABASE_CONFIG || {};
    if (config.projectRef && config.projectRef !== STAGING) return '';
    if (!config.url || config.url.includes(PRODUCTION)) return '';
    return `${config.url}/functions/v1/revolution-upload`;
  }

  function readLog() {
    try { return JSON.parse(sessionStorage.getItem(LOG_KEY) || '[]'); }
    catch { return []; }
  }

  function writeLog(entry) {
    const rows = readLog().slice(0, 19);
    rows.unshift(entry);
    sessionStorage.setItem(LOG_KEY, JSON.stringify(rows));
    renderLog(rows);
  }

  function renderLog(rows) {
    const body = document.getElementById('revolution-upload-log');
    if (!body) return;
    body.replaceChildren();
    if (!rows.length) {
      const row = document.createElement('tr');
      const cell = document.createElement('td');
      cell.colSpan = 5;
      cell.textContent = 'No file has been dry-run in this browser yet.';
      row.append(cell);
      body.append(row);
      return;
    }
    for (const entry of rows) {
      const row = document.createElement('tr');
      for (const value of [entry.when, entry.uploader, entry.md5, entry.kind, entry.result]) {
        const cell = document.createElement('td');
        cell.textContent = value || '';
        row.append(cell);
      }
      body.append(row);
    }
  }

  function setStatus(text) {
    const node = document.getElementById('revolution-upload-status');
    if (node) node.textContent = text;
  }

  // r762 (F368, Craig 31 Oct 05:27): "give me a preview when i load it". List the stock numbers behind every count.
  function changeLine762(entry) {
    const bits = [];
    if (entry.stock) bits.push(entry.stock);
    if (entry.rego && entry.rego !== entry.stock) bits.push(`rego ${entry.rego}`);
    if (entry.ro) bits.push(entry.ro);
    if (entry.key_number) bits.push(`key ${entry.key_number}`);
    if (Number.isInteger(entry.lines)) bits.push(`${entry.lines} line${entry.lines === 1 ? '' : 's'}`);
    return bits.join(' · ');
  }

  function renderChanges762(host, payload) {
    const changes = payload.changes;
    if (!changes || typeof changes !== 'object') return;
    const sections = [
      ['archived', 'Leaving the board', 'Not on the Revolution list any more. Completed, or tagged "not on Revolution list" if the car is still on Navision.', true],
      ['new', 'Coming onto the board', 'Not on the board yet.', true],
      ['updated', 'Changed', 'Already imported; at least one line changed since the last import.', true],
      ['held_before', 'Held last time, retrying', 'Not applied by the last import (staff-locked hours, review or identity holds). Tried again; usually held again.', false],
      ['awaiting_approval', 'Imported, waiting on New Vehicles', 'Already imported and unchanged; approve them on the New Vehicles page.', false],
      ['unchanged', 'Unchanged', 'Line-for-line what the last import applied. The server skips these.', false],
      ['sales_left_alone', 'Sales boards left alone', '', false],
    ];
    const wrap = document.createElement('div');
    wrap.className = 'ru-changes';
    for (const [keyName, label, note, open] of sections) {
      const rows = Array.isArray(changes[keyName]) ? changes[keyName] : [];
      if (!rows.length) continue;
      const details = document.createElement('details');
      details.className = `ru-change ru-change-${keyName}`;
      if (open) details.open = true;
      const summary = document.createElement('summary');
      summary.textContent = `${label} (${rows.length})`;
      details.append(summary);
      if (note) {
        const p = document.createElement('p');
        p.className = 'ru-note';
        p.textContent = note;
        details.append(p);
      }
      const list = document.createElement('ul');
      list.className = 'ru-change-list';
      for (const entry of rows) {
        const item = document.createElement('li');
        item.textContent = changeLine762(entry);
        list.append(item);
      }
      details.append(list);
      wrap.append(details);
    }
    const holds = Array.isArray(payload.holds) ? payload.holds : [];
    if (holds.length) {
      const details = document.createElement('details');
      details.className = 'ru-change ru-change-holds';
      details.open = true;
      const summary = document.createElement('summary');
      summary.textContent = `Held lines (${holds.length})`;
      details.append(summary);
      const list = document.createElement('ul');
      list.className = 'ru-change-list';
      for (const hold of holds) {
        const item = document.createElement('li');
        item.textContent = [hold.stock, hold.ro, hold.line ? `line ${hold.line}` : '', hold.reason].filter(Boolean).join(' · ');
        list.append(item);
      }
      details.append(list);
      wrap.append(details);
    }
    if (wrap.childElementCount) host.append(wrap);
  }

  function renderResult(payload) {
    const host = document.getElementById('revolution-upload-result');
    if (!host) return;
    host.replaceChildren();
    const title = document.createElement('h2');
    title.textContent = payload.title || payload.kind || 'Dry run';
    host.append(title);
    const counts = payload.counts || {};
    const grid = document.createElement('div');
    grid.className = 'ru-counts';
    const cards = [
      ['New', counts.new || 0],
      [payload.delta && payload.delta.ok ? 'Changed' : 'Updated', counts.updated || 0],
    ];
    if (Number.isInteger(counts.unchanged)) cards.push(['Unchanged', counts.unchanged]);
    cards.push(
      ['Archived', counts.archived || 0],
      ['Skipped', counts.skipped || 0],
      ['Errors', counts.errors || 0],
    );
    for (const [label, value] of cards) {
      const card = document.createElement('div');
      card.className = 'ru-count';
      const name = document.createElement('span');
      name.textContent = label;
      const strong = document.createElement('strong');
      strong.textContent = String(value);
      card.append(name, strong);
      grid.append(card);
    }
    host.append(grid);
    const notes = document.createElement('p');
    notes.className = 'ru-note';
    const extra = [
      payload.held_open_job_card ? `${payload.held_open_job_card} kept because a job card is open` : '',
      payload.sales_boards_left_alone ? `${payload.sales_boards_left_alone} sales-board vehicles left alone` : '',
      payload.closed_vehicles ? `${payload.closed_vehicles} vehicles have every line at status 80` : '',
      payload.delta && payload.delta.ok === false ? 'Could not compare with the last import; counts are against the board only.' : '',
      payload.needs_admin_confirm ? 'More than 15 cars would leave the board. Apply would stop for an administrator confirm.' : '',
      payload.duplicate_file ? 'This file is already in the ledger.' : '',
      payload.quiet_hours ? 'Quiet hours. Apply is refused around 07:00, 12:30 and 18:00 AWST.' : '',
    ].filter(Boolean);
    notes.textContent = [payload.summary, ...extra].filter(Boolean).join(' ') || 'No extra holds.';
    host.append(notes);
    if (payload.errors?.length) {
      const list = document.createElement('ul');
      list.className = 'ru-errors';
      for (const error of payload.errors) {
        const item = document.createElement('li');
        item.textContent = error.message || error.code;
        list.append(item);
      }
      host.append(list);
    }
    renderChanges762(host, payload);
    const plan = document.createElement('p');
    plan.className = 'ru-note';
    plan.textContent = payload.apply_enabled
      ? 'Apply sends this file to the import queue. Every part is previewed on the server, then applied.'
      : 'Apply is on for Service as a Whole first. This report still waits.';
    host.append(plan);
    const holdCounts = payload.hold_counts || {};
    const holdNames = Object.keys(holdCounts);
    const holdTitle = document.createElement('h2');
    holdTitle.textContent = 'Hold list';
    host.append(holdTitle);
    if (!holdNames.length) {
      const none = document.createElement('p');
      none.className = 'ru-note';
      none.textContent = 'No lines are held.';
      host.append(none);
    } else {
      const list = document.createElement('ul');
      list.className = 'ru-errors';
      for (const reason of holdNames) {
        const item = document.createElement('li');
        item.textContent = `${reason}: ${holdCounts[reason]}`;
        list.append(item);
      }
      host.append(list);
    }
  }

  async function postFile(file, action) {
    const url = new URL(endpoint());
    url.searchParams.set('action', action);
    const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : null;
    const { form, headers } = revolutionUploadParts(file, token);
    const response = await fetch(url, { method: 'POST', body: form, headers });
    const payload = await response.json();
    if (!response.ok && !payload.md5 && !payload.error) throw new Error('The server did not return a dry run.');
    return payload;
  }

  function remember(file, payload) {
    const counts = payload.counts || {};
    writeLog({
      when: new Date().toLocaleString('en-AU', { timeZone: 'Australia/Perth', hour12: false }),
      uploader: payload.uploader || 'Preview staff',
      md5: payload.md5 || '',
      kind: payload.kind || '',
      result: payload.error && !payload.md5
        ? payload.error
        : payload.summary || `new ${counts.new || 0}, updated ${counts.updated || 0}, archived ${counts.archived || 0}, skipped ${counts.skipped || 0}, holds ${counts.holds || 0}, errors ${counts.errors || 0}`,
    });
  }

  // r728: progress of an applied upload, read with the signed-in administrator's token.
  let pollTimer = null;
  async function status(uploadId) {
    const config = window.PDC_SUPABASE_CONFIG || {};
    const token = typeof getPdcSupabaseAccessToken === 'function' ? getPdcSupabaseAccessToken() : '';
    const response = await fetch(`${config.url}/rest/v1/rpc/revolution_upload_status_728`, {
      method: 'POST',
      headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_upload: uploadId }),
    });
    return response.json();
  }
  function follow(uploadId) {
    clearTimeout(pollTimer);
    const tick = async () => {
      try {
        const s = await status(uploadId);
        if (s?.ok !== true) { setStatus('Sent. Progress could not be read; check again in a minute.'); return; }
        const parts = s.n_parts ? ` Part ${Math.min(s.parts_applied || s.parts_previewed || 0, s.n_parts)} of ${s.n_parts}.` : '';
        if (s.status === 'done') { setStatus(`Imported.${s.holds ? ` ${s.holds} lines held for review.` : ''} The board is up to date with this file.`); return; }
        if (s.status === 'failed') { setStatus(`The import stopped: ${s.error || 'unknown error'}. Nothing after that part was written.`); return; }
        if (s.status === 'held') { setStatus(`Stopped for an administrator: ${s.note || 'sanity gate'}.`); return; }
        setStatus(`${s.status === 'queued' ? 'Waiting to start' : 'Importing'}…${parts} You can leave this page.`);
      } catch (_) { /* try again */ }
      pollTimer = setTimeout(tick, 5000);
    };
    void tick();
  }
  function renderNeedsHours(list) {
    const host = document.getElementById('revolution-upload-result');
    if (!host || !list?.length) return;
    const title = document.createElement('h2');
    title.textContent = `Needs hours (${list.length}) · not sent`;
    const note = document.createElement('p');
    note.className = 'ru-note';
    note.textContent = 'These lines have no hours and no earlier ARB check, so they were held. Add the hours on the board, then upload the next file.';
    const ul = document.createElement('ul');
    ul.className = 'ru-errors';
    for (const item of list.slice(0, 200)) {
      const li = document.createElement('li');
      li.textContent = `${item.stock_number || item.stock || ''} · ${item.repair_order_number || item.ro || ''} line ${item.original_line_number || item.line || ''} · ${item.proposed_station || item.station || ''} · ${item.operation_description || item.description || ''}`;
      ul.append(li);
    }
    host.append(title, note, ul);
  }

  function open() {
    renderLog(readLog());
    if (wired) return;
    wired = true;
    const input = document.getElementById('revolution-upload-file');
    const dry = document.getElementById('revolution-upload-dry');
    const apply = document.getElementById('revolution-upload-apply');
    if (apply) apply.disabled = true;
    input?.addEventListener('change', () => { if (apply) apply.disabled = true; });
    apply?.addEventListener('click', async () => {
      const file = input?.files?.[0];
      if (!file) return;
      apply.disabled = true;
      setStatus('Preparing the rows and sending them to the import queue…');
      try {
        const payload = await postFile(file, 'apply');
        remember(file, { ...payload, kind: 'apply', summary: payload.ok ? `sent ${payload.rows_sent || 0}, held ${payload.rows_held || 0}, needs hours ${(payload.needs_hours || []).length}` : payload.error });
        if (payload.ok !== true) { setStatus(payload.error || 'Apply was refused.'); return; }
        renderNeedsHours(payload.needs_hours);
        setStatus(payload.message);
        if (payload.status !== 'held') follow(payload.upload_id);
      } catch (error) {
        setStatus(error instanceof Error ? error.message : 'Apply failed.');
      }
    });
    dry?.addEventListener('click', async () => {
      const file = input?.files?.[0];
      if (!file) { setStatus('Choose a Revolution report first.'); return; }
      setStatus('Reading the report on the server…');
      try {
        const payload = await postFile(file, 'dry-run');
        if (payload.error && !payload.md5) {
          setStatus(payload.error);
          remember(file, payload);
          return;
        }
        renderResult(payload);
        setStatus(payload.message || 'Dry run ready. Nothing was written.');
        if (apply) apply.disabled = !(payload.apply_enabled === true && payload.ok !== false && !payload.duplicate_file);
        remember(file, payload);
      } catch (error) {
        setStatus(error instanceof Error ? error.message : 'The dry run failed.');
      }
    });
  }

  window.PdcRevolutionUpload = { open, reset() { wired = false; } };
})();
