/* Admin > Revolution uploads. r591. The file is parsed on the server. Apply stays off. */
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
      ['Updated', counts.updated || 0],
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
      payload.needs_admin_confirm ? 'More than 15 new vehicles or archives. Apply would stop for an administrator confirm.' : '',
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
    const plan = document.createElement('p');
    plan.className = 'ru-note';
    plan.textContent = `After go-live this file would call ${(payload.would_call || []).join(', ') || 'nothing'}. Apply is off in this preview.`;
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

  function open() {
    renderLog(readLog());
    if (wired) return;
    wired = true;
    const input = document.getElementById('revolution-upload-file');
    const dry = document.getElementById('revolution-upload-dry');
    const apply = document.getElementById('revolution-upload-apply');
    if (apply) apply.disabled = true;
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
        remember(file, payload);
      } catch (error) {
        setStatus(error instanceof Error ? error.message : 'The dry run failed.');
      }
    });
  }

  window.PdcRevolutionUpload = { open, reset() { wired = false; } };
})();
