/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r445 (F58, change request from Craig, 21 Oct 2026): attach the sublet purchase order PDF to a GP PO.
   Pilot: only vehicles in the server's pilot list show the controls, and only to controllers and administrators.
   Craig's workflow: whoever raises the job card attaches the sublet PO straight away, before the w/Sublet upload brings the
   PO onto the board. So staff enter the GP PO number (GP + 8 digits), optionally tick the operation lines it covers, and
   pick the PDF. The document is stored against the vehicle and PO number:
   - the vehicle's Sublet box gets a "Sublet PO documents" block: each PO with its state ("Pending: not on the w/Sublet
     upload yet" or "On PD line N"), file name, size, who uploaded it and when (AWST), View and Replace;
   - once the w/Sublet import attaches that PO to lines, the board's sublet rows for that PO get a "PDF" button (the server
     joins on vehicle + PO number at read time; no importer change).
   Upload path (same as the screen's QC photos): the PDF goes straight to the private pdc-sublet-po-staging bucket under
   sublet-po/<user>/<vehicle>/<uuid>.pdf with the user's own session (x-upsert false), then
   record_pdc_sublet_po_document_445 checks and records it. View opens a 60-second signed URL. Replace uploads a new file
   and keeps the old one as history. Nothing is ever emailed or sent from here.
   Loads after pdc-sublet-po.js and before pdc-operation-panels.js (which then places the Sublet box full width). */
(() => {
  'use strict';
  const VERSION = '2026.10.21.r445';
  const PROJECT = 'cdsmnqxtyyoeoznmbidd';
  const BUCKET = 'pdc-sublet-po-staging';
  const MAX_BYTES = 10 * 1024 * 1024;
  const PO_RE = /^GP[0-9]{8}$/;
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const idKey = value => String(value ?? '').trim().toLowerCase();
  /** GP PO as typed -> 'GP12345678' or '' when it is not one. */
  function normalisePo(value) {
    const po = String(value ?? '').replace(/\s+/g, '').toUpperCase();
    return PO_RE.test(po) ? po : '';
  }
  /** Size for people: 51 KB, 2.4 MB. */
  function sizeLabel(bytes) {
    const n = Number(bytes) || 0;
    if (n < 1024) return `${n} B`;
    if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
    return `${(n / 1024 / 1024).toFixed(1)} MB`;
  }
  const when = value => {
    const d = new Date(value || '');
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString('en-AU', { timeZone: 'Australia/Perth', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit', hour12: false }) + ' AWST';
  };
  /**
   * Check a chosen file before upload. Returns '' when fine, else the reason shown to the user.
   * head: the first bytes of the file (Uint8Array) when known; a PDF starts with "%PDF-".
   */
  function fileProblem(file, head) {
    if (!file) return 'Choose the purchase order PDF.';
    const name = String(file.name || '');
    const type = String(file.type || '').toLowerCase();
    if (!/\.pdf$/i.test(name) || (type && type !== 'application/pdf')) return 'Only PDF files can be attached.';
    const size = Number(file.size) || 0;
    if (size < 1) return 'That file is empty.';
    if (size > MAX_BYTES) return `That PDF is ${sizeLabel(size)}; the limit is 10 MB.`;
    if (head && head.length >= 5 && String.fromCharCode(...head.slice(0, 5)) !== '%PDF-') return 'That file is not a real PDF.';
    return '';
  }
  /** Storage object path for a new upload: sublet-po/<user id>/<vehicle id>/<uuid>.pdf */
  function uploadPath(userId, vehicleId, fileId) {
    const u = idKey(userId), v = idKey(vehicleId), f = idKey(fileId);
    if (![u, v, f].every(x => UUID.test(x))) return '';
    return `sublet-po/${u}/${v}/${f}.pdf`;
  }
  const GRID_OPEN = '<div class="authenticated-operation-station-grid">';
  const SECTION = /(<section class="authenticated-operation-station" data-operation-station="([^"]*)"[^>]*>)([\s\S]*?)(<\/section>)/g;
  function docRowHtml(doc, canAttach) {
    const pending = doc.state !== 'linked';
    const lines = (Array.isArray(doc.board_lines) ? doc.board_lines : []).map(l => l.label || l.line_key).filter(Boolean);
    const covers = (Array.isArray(doc.covered_labels) ? doc.covered_labels : []).filter(Boolean);
    const history = Array.isArray(doc.history) ? doc.history.length : 0;
    const state = pending
      ? `<span class="pdc-po-doc-state is-pending" title="Stored against this vehicle and ${esc(doc.po_number)}. It shows on the sublet rows when the w/Sublet upload brings this PO.">Pending: PO not on the w/Sublet upload yet</span>`
      : `<span class="pdc-po-doc-state is-linked">On ${esc(lines.join(', '))}</span>`;
    const meta = [esc(doc.original_filename), esc(sizeLabel(doc.byte_length)), `uploaded by ${esc(doc.uploaded_by_email || 'unknown')} ${esc(when(doc.uploaded_at))}`]
      .concat(covers.length ? [`covers ${esc(covers.join(', '))}`] : [])
      .concat(history ? [`${history} earlier version${history === 1 ? '' : 's'} kept`] : []).join(' · ');
    return `<div class="pdc-po-doc ${pending ? 'is-pending' : 'is-linked'}" data-pdc-po-doc="${esc(doc.doc_id)}">`
      + `<span class="pdc-po-doc-po">${esc(doc.po_number)}</span>${state}`
      + `<span class="pdc-po-doc-meta">${meta}</span>`
      + `<span class="pdc-po-doc-actions"><button type="button" class="pdc-po-doc-view" data-pdc-po-view="${esc(doc.doc_id)}">View PO</button>`
      + (canAttach ? `<button type="button" class="pdc-po-doc-replace" data-pdc-po-replace="${esc(doc.doc_id)}">Replace</button>` : '') + '</span></div>';
  }
  /** The "Sublet PO documents" block for one vehicle (no <li>, so the Sublet box's "N sublets" count is unchanged). */
  function docsBlockHtml(payload, vehicleId) {
    const docs = Array.isArray(payload?.documents) ? payload.documents : [];
    const canAttach = payload?.can_attach === true;
    if (!docs.length && !canAttach) return '';
    return `<div class="pdc-sublet-po-docs" data-pdc-po-docs="${esc(vehicleId)}">`
      + `<div class="pdc-po-docs-head"><strong>Sublet PO documents</strong><small>Pilot · controllers and administrators</small>`
      + (canAttach ? `<button type="button" class="pdc-po-attach" data-pdc-po-attach="${esc(vehicleId)}">Attach PO (PDF)</button>` : '') + '</div>'
      + (docs.length ? docs.map(d => docRowHtml(d, canAttach)).join('') : '<p class="pdc-po-docs-empty">No sublet PO attached yet. Attach the GP purchase order when you raise the job card.</p>')
      + '</div>';
  }
  /** Add a "PDF" button after each board PO chip that has a stored document (sublet rows in the Sublet box). */
  function chipButtons(sectionHtml, docs) {
    const byPo = new Map(docs.map(d => [String(d.po_number), d]));
    return sectionHtml.replace(/<span class="pdc-sublet-po-chip">(GP[0-9]{8})<\/span>(?!<button class="pdc-po-chip-pdf")/g, (all, po) => {
      const d = byPo.get(po);
      return d ? `${all}<button class="pdc-po-chip-pdf" type="button" data-pdc-po-view="${esc(d.doc_id)}" title="View the sublet PO ${esc(po)} (${esc(d.original_filename)})">PDF</button>` : all;
    });
  }
  /**
   * Decorate one operations summary (HTML string) for a pilot vehicle. state: { vehicleId, payload } where payload is the
   * get_pdc_sublet_po_documents_445 result. Adds the documents block to the Sublet box (creating a Sublet box when the vehicle
   * has none yet) and a PDF button on the Sublet box's PO chips. Idempotent; never touches lines, ticks or categories.
   */
  function decorate(html, state = {}) {
    if (typeof html !== 'string' || !html.includes(GRID_OPEN) || html.includes('data-pdc-po-docs=')) return html;
    const payload = state.payload && state.payload.ok === true ? state.payload : null;
    if (!payload) return html;
    const vid = idKey(state.vehicleId || payload.vehicle_id);
    const block = docsBlockHtml(payload, vid);
    if (!block) return html;
    const docs = Array.isArray(payload.documents) ? payload.documents : [];
    let found = false;
    const out = html.replace(SECTION, (all, open, station, inner, close) => {
      if (station.toUpperCase() !== 'SUBLET' || found) return all;
      found = true;
      return open + chipButtons(inner, docs) + block + close;
    });
    if (found) return out;
    const section = '<section class="authenticated-operation-station" data-operation-station="SUBLET" data-operation-category="sublet" style="--station-colour:#8c671d;--station-tint:#fbf5e5" data-pdc-po-docs-only>'
      + `<header><strong>Sublet</strong><small>Sublet PO documents</small></header>${block}`
      // One hidden marker per pending PO so the panel header counts it ("1 sublet") instead of "0 sublets".
      + docs.filter(d => d.state !== 'linked').map(d => `<li hidden data-pdc-po-pending="${esc(d.po_number)}"></li>`).join('') + '</section>';
    const start = html.indexOf(GRID_OPEN);
    const last = html.lastIndexOf('</section>');
    if (last < start) return html;
    return html.slice(0, last + 10) + section + html.slice(last + 10);
  }
  const CSS = [
    '.pdc-sublet-po-docs{margin:.4rem .55rem .55rem;padding:.45rem .55rem;border:1px dashed #cbd5e1;border-radius:8px;background:#f8fafc;font-size:12px}',
    '.pdc-po-docs-head{display:flex;align-items:center;gap:.5rem;flex-wrap:wrap;margin-bottom:.3rem}.pdc-po-docs-head strong{color:#1f2937;font-size:12px}',
    '.pdc-po-docs-head small{color:#64748b;font-size:10.5px}.pdc-po-docs-head .pdc-po-attach{margin-left:auto}',
    '.pdc-po-doc{display:grid;grid-template-columns:max-content minmax(0,1fr) max-content;column-gap:.5rem;row-gap:.15rem;align-items:center;padding:.3rem 0;border-top:1px solid #e2e8f0}',
    '.pdc-po-doc-po{font-weight:750;color:#9a3412;background:#fff7ed;border:1px solid #fdba74;border-radius:4px;padding:0 5px;line-height:17px}',
    '.pdc-po-doc.is-linked .pdc-po-doc-po{color:#166534;background:#f0fdf4;border-color:#86efac}',
    '.pdc-po-doc-state{font-weight:650;font-size:11.5px}.pdc-po-doc-state.is-pending{color:#b45309}.pdc-po-doc-state.is-linked{color:#166534}',
    '.pdc-po-doc-meta{grid-column:2/3;color:#475569;font-size:11px;overflow-wrap:anywhere}',
    '.pdc-po-doc-actions{grid-column:3;grid-row:1/3;display:flex;gap:.3rem}',
    '.pdc-sublet-po-docs button,.pdc-po-chip-pdf{font:inherit;font-size:11px;font-weight:650;padding:2px 8px;border-radius:5px;border:1px solid #94a3b8;background:#fff;color:#1e293b;cursor:pointer}',
    '.pdc-sublet-po-docs .pdc-po-attach{background:#1d4ed8;border-color:#1d4ed8;color:#fff}',
    '.pdc-po-chip-pdf{margin-left:3px;padding:0 5px;line-height:15px;font-size:10px}',
    '.pdc-po-docs-empty{margin:.2rem 0;color:#64748b;font-size:11.5px}',
    '.pdc-po-dialog{border:0;border-radius:10px;padding:0;max-width:min(520px,94vw);box-shadow:0 20px 50px rgba(15,23,42,.35)}.pdc-po-dialog::backdrop{background:rgba(15,23,42,.45)}',
    '.pdc-po-dialog form{display:flex;flex-direction:column;gap:.6rem;padding:1rem 1.1rem;font-size:13px}.pdc-po-dialog h3{margin:0;font-size:15px}',
    '.pdc-po-dialog label{display:flex;flex-direction:column;gap:.2rem;font-weight:650}.pdc-po-dialog input[type=text]{font:inherit;padding:.35rem .45rem;border:1px solid #94a3b8;border-radius:6px;text-transform:uppercase}',
    '.pdc-po-dialog fieldset{border:1px solid #e2e8f0;border-radius:6px;padding:.4rem .55rem}.pdc-po-dialog fieldset label{flex-direction:row;align-items:center;font-weight:500;gap:.4rem}',
    '.pdc-po-dialog .pdc-po-msg{min-height:1.1em;color:#b91c1c;font-size:12px}.pdc-po-dialog .pdc-po-msg.is-ok{color:#166534}',
    '.pdc-po-dialog .pdc-po-buttons{display:flex;justify-content:flex-end;gap:.5rem}.pdc-po-dialog button{font:inherit;padding:.35rem .8rem;border-radius:6px;border:1px solid #94a3b8;background:#fff;cursor:pointer}',
    '.pdc-po-dialog button[type=submit]{background:#1d4ed8;border-color:#1d4ed8;color:#fff}.pdc-po-dialog small{color:#64748b;font-weight:500}',
  ].join('');
  const api = { VERSION, BUCKET, MAX_BYTES, normalisePo, sizeLabel, fileProblem, uploadPath, docsBlockHtml, decorate, CSS };
  if (typeof module !== 'undefined') module.exports = api;
  if (typeof window === 'undefined' || window.PDC_SUPABASE_CONFIG?.projectRef !== PROJECT || window.PDC_SUBLET_PO_ATTACH_VERSION) return;
  window.PDC_SUBLET_PO_ATTACH_VERSION = VERSION;
  const base = () => (window.PDC_SUPABASE_CONFIG?.url || '').replace(/\/$/, '');
  const token = () => window.__pdcCachedAccessToken;
  const headers = extra => ({ apikey: window.PDC_SUPABASE_CONFIG.publishableKey, Authorization: 'Bearer ' + token(), ...extra });
  function jwtSubject() {
    try { return idKey(JSON.parse(atob(String(token()).split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub); } catch (_) { return ''; }
  }
  async function rpc(name, body) {
    if (!token() || base() !== `https://${PROJECT}.supabase.co`) throw new Error('Not signed in');
    const response = await fetch(`${base()}/rest/v1/rpc/${name}`, { method: 'POST', headers: headers({ 'Content-Type': 'application/json' }), body: JSON.stringify(body || {}) });
    const text = await response.text();
    if (!response.ok) { let m = text; try { m = JSON.parse(text).message || text; } catch (_) { /* raw */ } throw new Error(String(m || response.status)); }
    return JSON.parse(text || 'null');
  }
  let pilot = new Set(), canAttach = false, pilotLoaded = false;
  const cache = new Map(), inflight = new Set();
  function vehicleIds(vehicle) {
    const ids = [vehicle?.__emailVehicleId, vehicle?.id, vehicle?.permanentVehicleId];
    try { if (typeof vehicleWorkshopDetailCanonicalId === 'function') ids.unshift(vehicleWorkshopDetailCanonicalId(vehicle)); } catch (_) { /* optional */ }
    return ids.map(idKey).filter(id => UUID.test(id));
  }
  const refreshSummaries = () => {
    try {
      if (typeof refreshAuthenticatedOperationSummaryRow !== 'function') return;
      document.querySelectorAll('[data-incoming-row][open]').forEach(row => { try { refreshAuthenticatedOperationSummaryRow(row); } catch (_) { /* next render */ } });
    } catch (_) { /* next render */ }
  };
  async function loadPilot() {
    if (!token()) return;
    try {
      const data = await rpc('get_pdc_sublet_po_attach_pilot_445', {});
      const next = new Set((Array.isArray(data?.vehicle_ids) ? data.vehicle_ids : []).map(idKey));
      const changed = next.size !== pilot.size || [...next].some(id => !pilot.has(id)) || canAttach !== (data?.can_attach === true);
      pilot = next; canAttach = data?.can_attach === true; pilotLoaded = true;
      if (changed) refreshSummaries();
    } catch (_) { /* keep the last list; the next poll retries */ }
  }
  async function fetchDocs(vid) {
    if (!vid || inflight.has(vid)) return;
    inflight.add(vid);
    try { cache.set(vid, await rpc('get_pdc_sublet_po_documents_445', { p_vehicle_id: vid })); refreshSummaries(); }
    catch (_) { /* keep what is shown */ }
    finally { inflight.delete(vid); }
  }
  if (typeof authenticatedEmailOperationLinesHtml === 'function') {
    const prior = authenticatedEmailOperationLinesHtml;
    authenticatedEmailOperationLinesHtml = function (vehicle = {}, ...args) {
      const html = prior.call(this, vehicle, ...args);
      if (!html || !pilot.size) return html;
      const vid = vehicleIds(vehicle).find(id => pilot.has(id));
      if (!vid) return html;
      if (!cache.has(vid)) { fetchDocs(vid); return html; }
      return decorate(html, { vehicleId: vid, payload: cache.get(vid) });
    };
  }
  const notify = (message, tone) => { try { if (typeof pdcNotify === 'function') pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  function findDoc(docId) {
    for (const [vid, payload] of cache) {
      for (const d of Array.isArray(payload?.documents) ? payload.documents : []) {
        if (d.doc_id === docId) return { vid, doc: d, payload };
        for (const h of Array.isArray(d.history) ? d.history : []) if (h.doc_id === docId) return { vid, doc: { ...h, po_number: d.po_number }, payload };
      }
    }
    return null;
  }
  async function view(docId) {
    const hit = findDoc(docId);
    if (!hit) return;
    const win = window.open('about:blank', '_blank');
    try {
      const path = hit.doc.storage_path.split('/').map(encodeURIComponent).join('/');
      const response = await fetch(`${base()}/storage/v1/object/sign/${BUCKET}/${path}`, { method: 'POST', headers: headers({ 'Content-Type': 'application/json' }), body: JSON.stringify({ expiresIn: 60 }) });
      const body = await response.json().catch(() => null);
      const signed = body?.signedURL || body?.signedUrl;
      if (!response.ok || !signed) throw new Error(body?.message || 'not allowed');
      const url = /^https?:/.test(signed) ? signed : `${base()}/storage/v1${signed.startsWith('/') ? '' : '/'}${signed}`;
      if (win) win.location.href = url; else window.location.assign(url);
    } catch (error) { if (win) win.close(); notify(`Could not open the PO: ${error.message}`, 'error'); }
  }
  async function sha256Hex(buffer) {
    const digest = await crypto.subtle.digest('SHA-256', buffer);
    return Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
  }
  /** Upload the PDF with the user's session, then record it. replaceDoc: the current document being replaced (or null). */
  async function attach(vid, po, file, lineKeys, replaceDoc) {
    const bytes = await file.arrayBuffer();
    const problem = fileProblem(file, new Uint8Array(bytes.slice(0, 5)));
    if (problem) throw new Error(problem);
    const uid = jwtSubject();
    const path = uploadPath(uid, vid, crypto.randomUUID());
    if (!path) throw new Error('Sign in again and retry.');
    const sha = await sha256Hex(bytes);
    const up = await fetch(`${base()}/storage/v1/object/${BUCKET}/${path}`, { method: 'POST', headers: headers({ 'Content-Type': 'application/pdf', 'x-upsert': 'false' }), body: new Blob([bytes], { type: 'application/pdf' }) });
    if (!up.ok) { const b = await up.json().catch(() => null); throw new Error(/size/i.test(b?.message || '') ? 'The PDF is over 10 MB.' : /mime|type/i.test(b?.message || '') ? 'Only PDF files can be attached.' : `Upload refused (${b?.message || up.status}).`); }
    const result = await rpc('record_pdc_sublet_po_document_445', { p_vehicle_id: vid, p_po_number: po, p_storage_path: path, p_byte_length: bytes.byteLength,
      p_sha256: sha, p_original_filename: file.name, p_covered_line_keys: lineKeys, p_replaces_doc_id: replaceDoc ? replaceDoc.doc_id : null, p_idempotency_key: crypto.randomUUID() });
    if (!result || result.ok !== true) {
      const code = result?.code || 'unknown';
      throw new Error({ po_already_attached: 'That PO already has a PDF here; use Replace on it.', replace_conflict: 'Someone else changed this PO; reopen and retry.',
        po_number_invalid: 'The PO must be GP followed by 8 digits.', sublet_po_attach_not_in_pilot: 'This vehicle is not in the pilot.',
        not_authorized: 'Only controllers and administrators can attach sublet POs.', covered_line_not_on_vehicle: 'One of the ticked lines is no longer on this vehicle.' }[code] || `Not saved (${code}).`);
    }
    return result;
  }
  function openDialog(vid, replaceDoc) {
    const payload = cache.get(vid);
    if (!payload || payload.can_attach !== true) return;
    const lines = Array.isArray(payload.lines) ? payload.lines : [];
    const dialog = document.createElement('dialog');
    dialog.className = 'pdc-po-dialog';
    const checked = new Set(replaceDoc?.covered_line_keys || []);
    dialog.innerHTML = `<form method="dialog"><h3>${replaceDoc ? `Replace the PDF for ${esc(replaceDoc.po_number)}` : 'Attach the sublet purchase order'}</h3>`
      + `<label>GP PO number<input type="text" name="po" maxlength="12" autocomplete="off" placeholder="GP12345678" value="${esc(replaceDoc?.po_number || '')}"${replaceDoc ? ' readonly' : ''} required></label>`
      + (lines.length ? `<fieldset><legend>Covers these lines <small>(optional)</small></legend>${lines.map(l => `<label><input type="checkbox" name="line" value="${esc(l.line_key)}"${checked.has(l.line_key) ? ' checked' : ''}> ${esc(l.label)} · ${esc(l.description)}</label>`).join('')}</fieldset>` : '')
      + `<label>Purchase order PDF <small>PDF only, up to 10 MB</small><input type="file" name="file" accept="application/pdf,.pdf" required></label>`
      + (replaceDoc ? '<small>The current PDF is kept as history.</small>' : '<small>It shows as pending until the w/Sublet upload brings this PO, then on its sublet lines.</small>')
      + '<div class="pdc-po-msg" role="status"></div><div class="pdc-po-buttons"><button type="button" value="cancel">Cancel</button><button type="submit">Upload</button></div></form>';
    document.body.appendChild(dialog);
    const form = dialog.querySelector('form'), msg = dialog.querySelector('.pdc-po-msg'), submit = dialog.querySelector('button[type=submit]');
    const close = () => { try { dialog.close(); } catch (_) { /* closed */ } dialog.remove(); };
    dialog.querySelector('button[value=cancel]').addEventListener('click', close);
    dialog.addEventListener('cancel', close);
    form.addEventListener('submit', async event => {
      event.preventDefault();
      const po = normalisePo(form.po.value);
      const file = form.file.files && form.file.files[0];
      msg.className = 'pdc-po-msg';
      if (!po) { msg.textContent = 'The PO must be GP followed by 8 digits, e.g. GP12345678.'; return; }
      const problem = fileProblem(file);
      if (problem) { msg.textContent = problem; return; }
      submit.disabled = true; msg.textContent = 'Uploading…'; msg.className = 'pdc-po-msg is-ok';
      try {
        const keys = [...form.querySelectorAll('input[name=line]:checked')].map(i => i.value);
        await attach(vid, po, file, keys, replaceDoc);
        notify(replaceDoc ? `PDF replaced for ${po}` : `Sublet PO ${po} attached`, 'success');
        close();
        cache.delete(vid); fetchDocs(vid);
      } catch (error) { msg.className = 'pdc-po-msg'; msg.textContent = error.message; submit.disabled = false; }
    });
    if (typeof dialog.showModal === 'function') dialog.showModal(); else dialog.setAttribute('open', '');
  }
  // These controls sit inside a line or row that may open an editor: keep their clicks to themselves.
  for (const type of ['mousedown', 'pointerdown', 'touchstart', 'dblclick']) {
    document.addEventListener(type, event => { if (event.target?.closest?.('.pdc-sublet-po-docs,.pdc-po-chip-pdf')) event.stopPropagation(); }, true);
  }
  document.addEventListener('click', event => {
    const el = event.target?.closest?.('[data-pdc-po-view],[data-pdc-po-replace],[data-pdc-po-attach]');
    if (!el) return;
    event.preventDefault(); event.stopPropagation();
    if (el.dataset.pdcPoView) view(el.dataset.pdcPoView);
    else if (el.dataset.pdcPoReplace) { const hit = findDoc(el.dataset.pdcPoReplace); if (hit) openDialog(hit.vid, hit.doc); }
    else if (el.dataset.pdcPoAttach) openDialog(idKey(el.dataset.pdcPoAttach), null);
  }, true);
  const style = document.createElement('style');
  style.textContent = CSS;
  document.head.appendChild(style);
  // r490: skip the 4 s retry once the pilot list has loaded, and do not poll while the tab is hidden;
  // coming back to the tab refreshes the pilot list and any open PO documents straight away.
  const refreshAll = () => { loadPilot(); for (const vid of cache.keys()) fetchDocs(vid); };
  loadPilot();
  setTimeout(() => { if (!pilotLoaded) loadPilot(); }, 4000);
  setInterval(() => { if (document.visibilityState !== 'hidden') refreshAll(); }, 2 * 60 * 1000);
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') refreshAll(); });
})();
