/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r768: Navision Uploads on the Sales sites. Broome Toyota uploads the Broome file (Broome Upload: 037047 + 001234 + 002345);
// Karratha Toyota uploads the Pilbara file (Pilbara Upload: 014450 + 001234 + 002345). The server picks the upload from the
// signed-in account's own branch (sales_navision_upload_768); this page only shows which one. Rows are built by the exact
// PMB Navision Uploads parser (navision-profile-parser.js) and checked by the same backend guards.
(function (root) {
  'use strict';
  const e = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const PROFILES = Object.freeze({
    '37047': { profile: 'broome', label: 'Broome Upload', dealers: 'Broome Toyota 037047 + Toyota head office 001234 and 002345', other: 'Pilbara', otherSite: 'Karratha Sales' },
    '14450': { profile: 'pilbara', label: 'Pilbara Upload', dealers: 'Pilbara Toyota 014450 + Toyota head office 001234 and 002345', other: 'Broome', otherSite: 'Broome Sales' },
  });
  const SAFETY = {
    suspicious_partial_snapshot: 'This file leaves out a lot of the vehicles already loaded. It may be a part export.',
    suspicious_complete_replacement: 'This file would replace every vehicle already loaded.',
    suspicious_cross_dealer_overlap: 'This file seems to hold vehicles that belong to another dealer.',
    cross_dealer_identity_overlap: 'This file has vehicles already loaded under the other dealer.',
    source_name_dealer_scope_mismatch: 'The file name names a different dealer.',
    unproven_empty_dealer_scope: 'This dealer has no Navision data loaded yet. An administrator must do the first upload.',
    suspicious_empty_scope: 'The file could not be checked safely.',
    suspicious_tiny_snapshot: 'This file is too small to be the full daily Navision export.',
  };
  const CODES = {
    stale_revision: 'Another upload finished first. Preview again.',
    source_changed: 'The file changed after the preview. Preview again.',
    preview_changed: 'The data changed after the preview. Preview again.',
    blocking_reconciliation: 'The file needs a check by an administrator before it can be loaded.',
    branch_upload_not_available: 'Navision uploads are not set up for this branch.',
    unauthorized: 'Your account cannot upload Navision files.',
    upload_failed: 'The upload did not finish. Nothing changed. Try again.',
  };
  const RETRY = new Set(['55P03', '40P01', '40001']);

  function create(host) {
    const doc = () => host.document;
    const $ = id => doc()?.getElementById(id);
    const state = { options: null, text: '', fileName: '', parsed: null, preview: null, busy: false, last: null, principal: null, note: '', noteKind: '', done: null };
    const principal = () => host.PDC_AUTH_CONTEXT?.userId || null;
    const context = () => state.options?.getContext?.() || null;
    const active = () => state.options?.getView?.() === 'navision';
    const info = () => PROFILES[String(context()?.dealer_code || '')] || null;
    const parser = () => host.PDC_NAVISION_PROFILE_PARSER;

    function clear() {
      Object.assign(state, { text: '', fileName: '', parsed: null, preview: null, busy: false, last: null, note: '', noteKind: '', done: null, principal: principal() });
      const box = $('sales-navision');
      if (box) box.innerHTML = '';
    }
    function say(text, kind = '') { state.note = text; state.noteKind = kind; paint(); }
    function when(value) {
      const d = value ? new Date(value) : null;
      return d && Number.isFinite(d.getTime()) ? d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', dateStyle: 'medium', timeStyle: 'short' }) : 'Not recorded';
    }
    function previewData() { return state.preview?.result?.data || null; }

    function shell() {
      const p = info();
      return '<section class="panel nvu-panel"><div class="panel-header"><div><h2>Navision Uploads · ' + e(p.label) + '</h2>' +
        '<p>' + e(p.dealers) + '. Upload the daily Navision export here. It updates every board straight away.</p></div></div>' +
        '<p class="tracking-note" id="sales-navision-last"></p>' +
        '<div class="nvu-inputs"><label class="small-button nvu-file"><span>Choose file (.xlsx, .csv, .txt)</span>' +
        '<input id="sales-navision-file" type="file" accept=".xlsx,.csv,.tsv,.txt,text/plain,text/csv" hidden></label>' +
        '<label class="nvu-paste"><span>Or paste the Navision rows (with the heading row)</span><textarea id="sales-navision-paste" rows="5" spellcheck="false"></textarea></label></div>' +
        '<div class="panel-actions"><button class="small-button" id="sales-navision-preview" type="button">Preview</button>' +
        '<button class="primary" id="sales-navision-apply" type="button" disabled>Upload to the boards</button>' +
        '<button class="small-button" id="sales-navision-clear" type="button">Clear</button></div>' +
        '<div id="sales-navision-status" role="status" aria-live="polite"></div><div id="sales-navision-result"></div></section>';
    }

    function paint() {
      if (!active()) return;
      const box = $('sales-navision');
      if (!box) return;
      if (state.principal !== principal()) clear();
      const p = info();
      if (!principal() || !p) { box.innerHTML = '<div class="empty-state">Navision uploads are not available for this account.</div>'; return; }
      if (!$('sales-navision-file')) { box.innerHTML = shell(); bind(); loadLast(); }
      const data = previewData();
      const ready = !!(data && data.blocking === false && state.preview?.result?.ok);
      $('sales-navision-preview').disabled = state.busy || !state.text.trim();
      $('sales-navision-apply').disabled = state.busy || !ready;
      $('sales-navision-clear').disabled = state.busy;
      $('sales-navision-file').disabled = state.busy;
      $('sales-navision-paste').disabled = state.busy;
      $('sales-navision-last').textContent = state.last ? 'Last ' + p.label + ': ' + when(state.last.applied_at) : '';
      $('sales-navision-status').innerHTML = state.note ? '<p class="nvu-note ' + (state.noteKind || '') + '"' + (state.noteKind === 'error' ? ' role="alert"' : '') + '>' + e(state.note) + '</p>' : '';
      $('sales-navision-result').innerHTML = resultHtml();
    }

    function resultHtml() {
      const data = state.done || previewData();
      if (!data) return '';
      const c = data.counts || {};
      const stats = [['Rows in file', state.parsed?.vehicles?.length ?? data.source_row_count], ['New', c.new], ['Changed', c.changed], ['Unchanged', c.unchanged], ['Left Navision', c.missing]];
      return '<div class="nvu-stats">' + stats.map(([k, v]) => '<div><span>' + e(k) + '</span><strong>' + Number(v || 0) + '</strong></div>').join('') + '</div>';
    }

    async function loadLast() {
      const user = principal();
      try {
        const { data, error } = await host.PDC_SUPABASE.rpc('sales_navision_last_upload_768');
        if (!error && user === principal()) { state.last = data; paint(); }
      } catch { /* header line only */ }
    }

    function setText(text, name) {
      state.text = String(text || ''); state.fileName = name || ''; state.parsed = null; state.preview = null; state.done = null;
      const paste = $('sales-navision-paste'); if (paste && paste.value !== state.text) paste.value = state.text;
    }

    async function onFile(event) {
      const file = event.target.files?.[0];
      event.target.value = '';
      if (!file || state.busy) return;
      const P = parser();
      try {
        state.busy = true; say('Reading ' + file.name + '…');
        let text;
        if (P.isXlsxFile(file)) text = (await P.readXlsxVehicleSpreadsheet(file)).text;
        else if (/\.xls$/i.test(file.name)) throw new Error('Old .xls files cannot be read. Save it as .xlsx or .csv and try again.');
        else text = await P.readTextFile(file);
        setText(text, file.name);
        state.busy = false; say(file.name + ' loaded. Click Preview.');
      } catch (error) {
        state.busy = false; setText('', ''); say(error.message || 'This file could not be read.', 'error');
      }
    }

    function parse() {
      const p = info(), P = parser();
      const parsed = P.parseNavisionInput(state.text, { pmbOnly: false, uploadProfile: p.profile });
      if (!parsed.vehicles.length) throw new Error(parsed.warnings?.[0] || 'No vehicle rows found. Include the Navision heading row.');
      const check = P.assessNavisionUploadProfile(parsed.vehicles, p.profile);
      if (check.detectedProfile && check.detectedProfile !== p.profile) throw new Error('This is the ' + p.other + ' file. Upload it on ' + p.otherSite + '. Nothing changed.');
      if (check.blockedMessage) throw new Error(check.blockedMessage);
      const pre = P.navisionClientPreflight(parsed.vehicles, p.profile);
      if (pre.blocking) {
        const first = pre.issues[0];
        throw new Error(pre.issue_count + ' row(s) need fixing, e.g. row ' + first.row_index + (first.stock_number ? ' (' + first.stock_number + ')' : '') + ': ' + String(first.reason).replace(/_/g, ' ') + '. Nothing changed.');
      }
      return parsed;
    }

    async function preview() {
      if (state.busy || !state.text.trim()) return;
      const user = principal(), text = state.text;
      state.busy = true; state.preview = null; state.done = null; say('Checking the file…');
      try {
        const parsed = parse();
        const { data, error } = await host.PDC_SUPABASE.rpc('sales_navision_upload_768', { p_apply: false, p_rows: parsed.vehicles, p_source_name: state.fileName || 'Pasted text' });
        if (user !== principal() || text !== state.text) return;
        if (error) throw new Error(error.message || 'The preview did not finish.');
        if (data?.profile !== info().profile) throw new Error('Your account is set up for a different branch. Refresh the page.');
        state.parsed = parsed; state.preview = data;
        const res = data.result || {};
        if (!res.ok) throw new Error(CODES[res.code] || 'The preview did not finish (' + (res.code || 'unknown') + '). Nothing changed.');
        const d = res.data || {};
        if (d.blocking) {
          const reason = d.safety?.reason || (d.dealer_groups || []).find(g => g.blocking)?.safety?.reason;
          const rows = Number(d.counts?.invalid || 0) + Number(d.counts?.conflict || 0);
          say((rows ? rows + ' row(s) need fixing. ' : (SAFETY[reason] || 'The file needs a check.') + ' ') + 'Ask an administrator to load it on PMB Navision Uploads. Nothing changed.', 'error');
        } else {
          say('Preview ready. Check the numbers, then click Upload to the boards.', 'success');
        }
      } catch (error) {
        if (user === principal()) { state.preview = null; say(error.message || 'The preview did not finish. Nothing changed.', 'error'); }
      } finally {
        if (user === principal()) { state.busy = false; paint(); }
      }
    }

    async function apply() {
      const d = previewData();
      if (state.busy || !d || d.blocking !== false) return;
      const c = d.counts || {};
      if (!host.confirm?.('Upload this ' + info().label + ' to the boards?\n\nNew ' + Number(c.new || 0) + ', changed ' + Number(c.changed || 0) + ', left Navision ' + Number(c.missing || 0) + '.\n\nDelivered - At Dealer moves PMB vehicles to Completed.')) return;
      const user = principal(), rows = state.parsed.vehicles;
      state.busy = true; say('Uploading…');
      let data = null, error = null;
      try {
        for (let attempt = 0; attempt < 3; attempt += 1) {
          ({ data, error } = await host.PDC_SUPABASE.rpc('sales_navision_upload_768', {
            p_apply: true, p_rows: rows, p_source_name: state.fileName || 'Pasted text',
            p_idempotency_key: 'sales-upload:' + info().profile + ':' + d.source_hash,
            p_source_hash: d.source_hash, p_preview_hash: d.preview_hash, p_expected_revision: d.base_revision,
          }));
          const state_ = String(data?.result?.data?.sqlstate || '').toUpperCase();
          if (error || data?.result?.ok || !RETRY.has(state_) || attempt === 2) break;
          await new Promise(r => setTimeout(r, (attempt + 1) * 1000));
        }
        if (user !== principal()) return;
        if (error) throw new Error(error.message || 'The upload did not finish.');
        const res = data?.result || {};
        if (!res.ok) throw new Error(CODES[res.code] || 'The upload did not finish (' + (res.code || 'unknown') + '). Nothing changed.');
        state.done = d; state.preview = null; state.text = ''; state.fileName = '';
        const paste = $('sales-navision-paste'); if (paste) paste.value = '';
        say(info().label + ' loaded. The boards are up to date.', 'success');
        loadLast();
        $('sales-refresh')?.click?.();
      } catch (err) {
        if (user === principal()) say(err.message || 'The upload did not finish.', 'error');
      } finally {
        if (user === principal()) { state.busy = false; paint(); }
      }
    }

    function bind() {
      $('sales-navision-file').addEventListener('change', onFile);
      $('sales-navision-paste').addEventListener('input', ev => { setText(ev.target.value, ''); state.note = ''; paint(); });
      $('sales-navision-preview').addEventListener('click', preview);
      $('sales-navision-apply').addEventListener('click', apply);
      $('sales-navision-clear').addEventListener('click', () => { setText('', ''); state.note = ''; paint(); });
    }

    function init(options) {
      state.options = options; state.principal = principal();
      host.addEventListener?.('pdc-auth-locked', clear); host.addEventListener?.('pdc-auth-failed', clear);
      return api;
    }
    const api = { init, clear, render: paint, PROFILES };
    return api;
  }
  if (typeof module === 'object' && module.exports) module.exports = { create, PROFILES, SAFETY, CODES };
  if (root && root.document) root.SALES_NAVISION_UPLOAD = create(root);
})(typeof window === 'object' ? window : null);
