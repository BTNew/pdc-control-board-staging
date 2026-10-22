/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r494 (F107): Manage sublets, per vehicle. Craig 22 Oct 18:11: the Vehicle Locations slide-out gets a "Manage sublets"
 * button that opens one screen with every sublet on that vehicle, in two kinds:
 *   - Whole line sublet: the operation line itself is Sublet work (its work category is SUBLET, e.g. seat covers). It sits
 *     in the Sublet box, has the GP PO and the provider, and its own 'sublet done' tick completes it.
 *   - Sublet item on a line: a GP PO on an operation line that stays in its own category (e.g. leaf springs supplied for a
 *     Bus 4x4 suspension line). The line stays in Fitting / Electrical / Bus 4x4; the PO shows under it with its own tick.
 * Whole line is an explicit user choice only: the existing work-category override (set_vehicle_work_category, operators
 * and administrators, versioned and audited). Imports never change it (the override outranks every import rule, F13), and
 * a sublet is never booked into a bay (the RPC refuses a category change while a booking holds the line).
 * Ticks are the r439 per-line tick (set_pdc_sublet_line_tick_439 via pdc-sublet-po.js: controllers, administrators and
 * fitters; imports never clear it). Provider, out / due back / back dates come from the Sublet page bookings; the status
 * text is r491's (Away N days / OVERDUE N days / Back) and Draft email is r492's provider email.
 * No new table, column or SQL: everything shown or changed already exists.
 * Craig 22 Oct 18:41: a whole line sublet with no GP PO says 'PO to raise' (and keeps the box orange, on the board too);
 * a GP PO that an import brings onto a line in another category shows here as a sublet item with 'PO raised for this
 * line' until it is ticked done or the user presses 'Got it'; the purchaser is the supplier (the sublet provider). */
(function (root) {
  'use strict';
  const VERSION = '2026.10.23.r494';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  /** One identity for a line across job cards, GP PO lines and Sublet bookings ("source:<uuid>" = "<uuid>"). */
  const sid = value => String(value ?? '').trim().toLowerCase().replace(/^(source|manual|operation):/, '');
  const CATEGORY_LABELS = Object.freeze({
    FITTING:'Fitting', ELECTRICAL:'Electrical', FABRICATION:'Fabrication', HOIST:'Hoist', TINT:'Tint', TYRE:'Tyres',
    PIT_INSPECTION:'Pit', SUBLET:'Sublet', BUS_4X4:'Bus 4×4', BUS_MECHANICAL:'Bus 4×4 · Mechanical', BUS_ACCESSORIES:'Bus 4×4 · Accessories',
    BUS_ELECTRICAL:'Bus 4×4 · Electrical', BUS_QA:'Bus 4×4 · QA', BUS_PIT:'Bus 4×4 · Pit', PDI:'PDI', PDS:'PDS', PRE_DELIVERY:'Pre-delivery'
  });
  function categoryLabel(code) {
    const key = String(code || '').toUpperCase();
    if (CATEGORY_LABELS[key]) return CATEGORY_LABELS[key];
    try { const named = root.PDC_WORKSHOP_DEPARTMENTS?.categoryLabel?.(key); if (named && named !== key) return named; } catch (_) { /* fallback */ }
    return CATEGORY_LABELS[key] || (key ? key.toLowerCase().replace(/_/g, ' ').replace(/^./, c => c.toUpperCase()) : 'Other');
  }
  function lineLabel(operationNo) {
    const text = String(operationNo ?? '').trim();
    if (!text) return 'Line';
    const n = text.match(/([0-9]+)\s*$/);
    return n ? `Op ${Number(n[1])}` : text;
  }
  const lineOrder = line => { const m = String(line?.operation_no ?? '').match(/([0-9]+)\s*$/); return m ? Number(m[1]) : 1e9; };
  function isWholeLine(line) {
    return String(line?.work_category || line?.category || line?.stage_code || '').toUpperCase() === 'SUBLET';
  }
  function poList(line) {
    const details = Array.isArray(line?.po_details) ? line.po_details : [];
    const byPo = new Map(details.filter(d => d && d.po_number).map(d => [String(d.po_number), String(d.description || '').replace(/\s+/g, ' ').trim()]));
    const pos = Array.isArray(line?.po_numbers) ? line.po_numbers.map(String) : [];
    for (const po of byPo.keys()) if (!pos.includes(po)) pos.push(po);
    return pos.map(po => ({ po, description: byPo.get(po) || '' }));
  }
  /**
   * The per-vehicle model. jobLines: the vehicle's operation lines (Workshop detail job_card_lines, any shape with
   * line_identity / operation_no / description / work_category). poLines: get_pdc_sublet_lines_439 lines (GP PO lines).
   * bookings: the Sublet page rows of this vehicle (subletRows()). Returns whole-line sublets, sublet items grouped by their
   * operation line, vehicle-level bookings that name no line, and the open / done count for the box colour.
   */
  function buildModel({ jobLines = [], poLines = [], bookings = [] } = {}) {
    const lines = (Array.isArray(jobLines) ? jobLines : []).filter(line => line && line.active !== false);
    const byId = new Map(lines.map(line => [sid(line.line_identity || line.workshopLineKey || line.operation_line_id), line]));
    const pos = (Array.isArray(poLines) ? poLines : []).filter(Boolean);
    const poById = new Map(pos.map(line => [sid(line.line_identity), line]));
    const rows = Array.isArray(bookings) ? bookings.filter(Boolean) : [];
    const bookingsFor = id => rows.filter(row => id && sid(row.__subletOperationIdentity) === id);
    const whole = [], items = [];
    const seen = new Set();
    const entry = (id, line, po) => {
      const list = poList(po);
      const tickable = Boolean(po) && po.has_po !== false && list.length > 0;
      return { id, line: line || null, po: po || null, pos: list, tickable, done: tickable && po.ticked === true,
        operationNo: line?.operation_no ?? po?.operation_no ?? '', description: String(line?.description || po?.description || '').trim(),
        category: String(line?.work_category || po?.category || '').toUpperCase(), completed: line?.completed === true,
        categoryVersion: Number(line?.category_version || 0), department: String(line?.department ?? po?.department ?? ''),
        bookings: bookingsFor(id) };
    };
    for (const line of lines) {
      const id = sid(line.line_identity || line.workshopLineKey || line.operation_line_id);
      if (!id || !isWholeLine(line)) continue;
      seen.add(id); whole.push(entry(id, line, poById.get(id)));
    }
    for (const po of pos) {
      const id = sid(po.line_identity);
      if (!id || seen.has(id)) continue;
      const line = byId.get(id);
      seen.add(id);
      if (line ? isWholeLine(line) : isWholeLine(po)) whole.push(entry(id, line, po));
      else items.push(entry(id, line, po));
    }
    const sort = (a, b) => lineOrder({ operation_no: a.operationNo }) - lineOrder({ operation_no: b.operationNo }) || a.description.localeCompare(b.description);
    whole.sort(sort); items.sort(sort);
    const loose = rows.filter(row => !sid(row.__subletOperationIdentity) || !seen.has(sid(row.__subletOperationIdentity)));
    const others = lines.filter(line => {
      const id = sid(line.line_identity || line.workshopLineKey || line.operation_line_id);
      return id && !isWholeLine(line) && line.completed !== true && !['JOB_CARD_NOTES', 'UNALLOCATED_MAPPING_REVIEW'].includes(String(line.work_category || '').toUpperCase());
    }).map(line => entry(sid(line.line_identity || line.workshopLineKey || line.operation_line_id), line, poById.get(sid(line.line_identity))))
      .sort(sort);
    const all = [...whole, ...items];
    const done = all.filter(row => row.done).length;
    const state = all.length === 0 ? 'none' : done === all.length ? 'done' : 'open';
    return { whole, items, loose, others, total: all.length, done, open: all.length - done, state,
      noPoWhole: whole.filter(row => !row.tickable).length };
  }
  const dateText = value => {
    const m = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})/);
    return m ? `${m[3]}/${m[2]}/${m[1].slice(2)}` : '—';
  };
  function statusText(row) {
    try { if (typeof root.subletStatusText === 'function') return root.subletStatusText(row); } catch (_) { /* fallback */ }
    if (row?.__subletBookingStatus === 'returned') return 'Returned';
    return row?.__subletBookingId ? 'Sublet Booked' : 'Sublet To Book';
  }
  const statusTone = text => /^OVERDUE/.test(text) ? 'is-overdue' : /^Away/.test(text) ? 'is-away' : /^(Back|Returned)/.test(text) ? 'is-back' : /Booked/.test(text) ? 'is-booked' : 'is-tobook';
  function tickHtml(row, vehicleId, canTick) {
    if (!row.tickable) return `<span class="pvs-nopo" title="No GP purchase order on this whole line sublet yet: raise the PO. The done tick appears once the GP PO import attaches it.">PO to raise</span>`;
    const po = row.po, ticked = po.ticked === true;
    const title = !canTick ? `Sublet done: ${ticked ? 'yes' : 'not yet'}. Read only: controllers, administrators and fitters tick sublet done`
      : ticked ? 'Sublet done. Untick if the sublet is not done' : 'Tick when the supplier has finished this';
    // Same markup as the r439/r444 Sublet box tick, so pdc-sublet-po.js saves it with set_pdc_sublet_line_tick_439.
    return `<span class="pdc-sublet-po-inline pvs-tick is-${ticked ? 'done' : 'ordered'}" data-pdc-sublet-vehicle="${esc(vehicleId)}" data-line-key="${esc(po.line_key || '')}" data-version="${esc(Number(po.version) || 0)}">`
      + `<input type="checkbox" class="pdc-sublet-po-tick" title="${esc(title)}" aria-label="${esc(`${lineLabel(row.operationNo)} sublet done`)}"${ticked ? ' checked' : ''}${!canTick || po.tickable === false ? ' disabled' : ''}>`
      + `<span>${ticked ? 'Done' : 'Not done'}</span></span>`;
  }
  function bookingCells(bookings, canEmail) {
    if (!bookings.length) return `<td class="pvs-muted" colspan="5">No supplier booked yet — book it on the Sublet page</td><td></td>`;
    return bookings.map((b, i) => {
      const status = statusText(b);
      const key = b.__subletBookingId || b.__subletOperationKey || '';
      const email = canEmail && b.pmbSubletProvider && key ? `<button type="button" class="small-button pvs-email" data-pvs-email="${esc(key)}" title="Draft the supplier email (opens your mail app; nothing is sent)">Draft email</button>` : '';
      const cells = `<td>${esc(b.pmbSubletProvider || '—')}</td><td>${dateText(b.pmbSubletBookingDate)}</td><td>${dateText(b.pmbSubletExpectedReturnDate)}</td><td>${dateText(b.pmbSubletActualReturnDate)}</td>`
        + `<td><span class="pvs-status ${statusTone(status)}">${esc(status)}</span></td><td>${email}</td>`;
      return i === 0 ? cells : `</tr><tr class="pvs-more"><td colspan="3"></td>${cells}`;
    }).join('');
  }
  function poCell(row) {
    if (!row.pos.length) return '<span class="pvs-muted">—</span>';
    return row.pos.map(p => `<span class="pvs-po" title="${esc(p.description || 'GP purchase order')}">${esc(p.po)}</span>${p.description ? `<small>${esc(p.description)}</small>` : ''}`).join('');
  }
  function moveBackHtml(row, choices) {
    const options = choices.filter(code => code !== 'SUBLET').map(code => `<option value="${esc(code)}">${esc(categoryLabel(code))}</option>`).join('');
    return `<label class="pvs-move"><select data-pvs-move-to aria-label="Move ${esc(lineLabel(row.operationNo))} back to"><option value="">Not a whole line sublet…</option>${options}</select></label>`
      + `<button type="button" class="small-button" data-pvs-move="${esc(row.id)}" data-category-version="${esc(row.categoryVersion)}">Move</button>`;
  }
  const HEAD = '<thead><tr><th>Line</th><th>Sublet work</th><th>GP PO</th><th>Done</th><th>Supplier</th><th>Out</th><th>Due back</th><th>Back</th><th>Status</th><th></th></tr></thead>';
  /** The screen's HTML. perms: { canTick, canMove, canEmail, choices }. */
  function screenHtml(model, { vehicleId = '', title = '', subtitle = '', perms = {}, loading = false, note = '' } = {}) {
    const p = { canTick: false, canMove: false, canEmail: false, choices: [], seen: null, ...perms };
    const keys = row => row.pos.map(x => [String(vehicleId).toLowerCase(), String(row.po?.line_key || ''), x.po].join('|'));
    const newPo = row => Boolean(p.seen && typeof p.seen.has === 'function' && row.po && !row.done && keys(row).some(k => !p.seen.has(k)));
    const newPoNote = row => `<div class="pvs-new-po"><b title="An import attached a GP PO to this line. It stays highlighted until the sublet is ticked done or you press Got it.">PO raised for this line</b>`
      + `<button type="button" class="small-button" data-pdc-sublet-ack="${esc(keys(row).join(' '))}" title="Hide this note (for you, in this browser)">Got it</button></div>`;
    const pill = model.state === 'none' ? '<span class="pvs-pill is-none">No sublets</span>'
      : model.state === 'done' ? `<span class="pvs-pill is-done">✓ All ${model.total} done</span>`
        : `<span class="pvs-pill is-open">! ${model.open} open · ${model.done}/${model.total} done</span>`;
    const wholeRows = model.whole.map(row => `<tr data-pvs-line="${esc(row.id)}"><td><b>${esc(lineLabel(row.operationNo))}</b></td>`
      + `<td>${esc(row.description || '—')}${p.canMove && !row.completed ? `<div class="pvs-line-actions">${moveBackHtml(row, p.choices)}</div>` : ''}</td>`
      + `<td>${poCell(row)}</td><td>${tickHtml(row, vehicleId, p.canTick)}</td>${bookingCells(row.bookings, p.canEmail)}</tr>`).join('');
    const itemRows = model.items.map(row => `<tr class="pvs-op" data-pvs-line="${esc(row.id)}"><td><b>${esc(lineLabel(row.operationNo))}</b></td>`
      + `<td colspan="9"><span class="pvs-cat">${esc(categoryLabel(row.category))}</span> ${esc(row.description || '—')} <small class="pvs-muted">· the line stays in ${esc(categoryLabel(row.category))}</small></td></tr>`
      + `<tr class="pvs-item${newPo(row) ? ' is-new-po' : ''}"><td class="pvs-indent">↳ Sublet</td><td>${row.pos.map(x => esc(x.description)).filter(Boolean).join('; ') || '<span class="pvs-muted">No sublet description in the upload yet</span>'}${newPo(row) ? newPoNote(row) : ''}</td>`
      + `<td>${row.pos.map(x => `<span class="pvs-po">${esc(x.po)}</span>`).join('')}</td><td>${tickHtml(row, vehicleId, p.canTick)}</td>${bookingCells(row.bookings, p.canEmail)}</tr>`).join('');
    const loose = model.loose.length ? `<section class="pvs-section"><h4>Vehicle sublet bookings <small>not tied to one operation line</small></h4><table class="pvs-table"><thead><tr><th>Supplier</th><th>Out</th><th>Due back</th><th>Back</th><th>Status</th><th></th></tr></thead><tbody>${model.loose.map(b => `<tr>${bookingCells([b], p.canEmail)}</tr>`).join('')}</tbody></table></section>` : '';
    const others = p.canMove && model.others.length ? `<details class="pvs-section pvs-others"><summary>Make a whole operation line a sublet <small>(${model.others.length} other line${model.others.length === 1 ? '' : 's'})</small></summary>`
      + `<p class="pvs-muted">Use this when the whole line is done by a sublet provider (e.g. seat covers). Leave it in its category when only a part is sublet (e.g. leaf springs supplied for a suspension line). Imports never change this choice.</p>`
      + `<table class="pvs-table"><tbody>${model.others.map(row => `<tr data-pvs-line="${esc(row.id)}"><td><b>${esc(lineLabel(row.operationNo))}</b></td><td><span class="pvs-cat">${esc(categoryLabel(row.category))}</span> ${esc(row.description || '—')}${row.pos.length ? ` <span class="pvs-po">${esc(row.pos.map(x => x.po).join(', '))}</span>` : ''}</td>`
        + `<td><button type="button" class="small-button" data-pvs-whole="${esc(row.id)}" data-category-version="${esc(row.categoryVersion)}">Whole line sublet</button></td></tr>`).join('')}</tbody></table></details>` : '';
    const empty = !model.whole.length && !model.items.length ? `<p class="pvs-empty">${loading ? 'Loading sublets…' : 'No sublets on this vehicle yet.'}</p>` : '';
    const noPo = model.noPoWhole ? `<p class="pvs-note">PO to raise: ${model.noPoWhole} whole line sublet${model.noPoWhole === 1 ? ' has' : 's have'} no GP PO yet, so the Sublet box stays orange until the PO is raised, imported and ticked.</p>` : '';
    return `<header class="pvs-head"><div><h3>Manage sublets</h3><p>${esc(title)}${subtitle ? ` · ${esc(subtitle)}` : ''}</p></div>${pill}<button type="button" class="pvs-close" data-pvs-close aria-label="Close">✕</button></header>`
      + `<div class="pvs-body">${note ? `<p class="pvs-note">${esc(note)}</p>` : ''}${empty}`
      + (model.whole.length ? `<section class="pvs-section"><h4>Whole line sublets <small>the line is Sublet work · its tick completes it</small></h4><table class="pvs-table">${HEAD}<tbody>${wholeRows}</tbody></table>${noPo}</section>` : '')
      + (model.items.length ? `<section class="pvs-section"><h4>Sublet items on operation lines <small>the line stays in its category · the sublet has its own tick</small></h4><table class="pvs-table">${HEAD}<tbody>${itemRows}</tbody></table></section>` : '')
      + loose + others
      + `<footer class="pvs-foot"><span class="pvs-muted">${p.canTick ? 'Ticks save straight away.' : 'Read only: controllers, administrators and fitters tick sublet done.'}${p.canMove ? '' : ' Operators and administrators change whole line sublets.'}</span><button type="button" class="small-button" data-pvs-open-sublet>Open Sublet page</button></footer></div>`;
  }
  const api = { VERSION, sid, isWholeLine, poList, buildModel, screenHtml, categoryLabel, lineLabel, dateText, statusTone };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (!root || !root.document || root.PDC_VEHICLE_SUBLETS) return;
  root.PDC_VEHICLE_SUBLETS = api;
  const doc = root.document;
  const state = { key: '', vehicleId: '', note: '' };
  const role = () => String(root.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
  const vehicleByKey = key => {
    try { const rows = typeof root.vehicleLocationsScreenRows === 'function' ? root.vehicleLocationsScreenRows() : []; const hit = rows.find(row => root.vehicleKey(row) === key); if (hit) return hit; } catch (_) { /* fallback */ }
    try { return typeof root.selectedVehicle === 'function' ? root.selectedVehicle(key) : null; } catch (_) { return null; }
  };
  const canonicalId = vehicle => { try { return root.vehicleWorkshopDetailCanonicalId(vehicle) || ''; } catch (_) { return ''; } };
  const detailFor = id => { try { return root.app?.vehicleWorkshopDetailCache?.get(id)?.detail || (typeof app !== 'undefined' ? app.vehicleWorkshopDetailCache.get(id)?.detail : null) || null; } catch (_) { return null; } };
  const bookingsFor = key => { try { return typeof root.subletRows === 'function' ? root.subletRows().filter(row => row.__subletVehicleKey === key) : []; } catch (_) { return []; } };
  const notify = (message, tone) => { try { root.pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  function ensureShell() {
    let shell = doc.getElementById('pvs-shell');
    if (shell) return shell;
    shell = doc.createElement('div');
    shell.id = 'pvs-shell';
    shell.innerHTML = '<div class="pvs-scrim" data-pvs-close></div><section class="pvs-dialog" role="dialog" aria-modal="true" aria-label="Manage sublets"></section>';
    doc.body.appendChild(shell);
    shell.addEventListener('click', onClick);
    return shell;
  }
  function draw() {
    const shell = doc.getElementById('pvs-shell');
    if (!shell || !state.key) return;
    const vehicle = vehicleByKey(state.key);
    if (!vehicle) { close(); return; }
    const id = state.vehicleId = canonicalId(vehicle).toLowerCase();
    const detail = detailFor(id);
    const payload = root.PDC_SUBLET_PO?.lines?.(id) || null;
    const jobLines = detail?.job_card_lines || detail?.operation_lines || [];
    const model = buildModel({ jobLines, poLines: payload?.lines || [], bookings: bookingsFor(state.key) });
    const department = model.others[0]?.department || model.whole[0]?.department || '';
    const choices = (() => { try { return root.PDC_WORKSHOP_DEPARTMENTS.categoryChoices(department === '138' ? '138' : '139'); } catch (_) { return []; } })();
    const canMove = ['operator', 'administrator'].includes(role()) && Boolean(detail);
    const perms = { canTick: payload?.can_tick === true, canMove, canEmail: true, choices, seen: root.PDC_SUBLET_PO?.seen?.() || null };
    const title = [root.displayStockNumber?.(vehicle), root.displayVehicle?.(vehicle)].filter(Boolean).join(' · ');
    const dialog = shell.querySelector('.pvs-dialog');
    const scroll = dialog.querySelector('.pvs-body')?.scrollTop || 0;
    const open = dialog.querySelector('.pvs-others')?.open;
    dialog.innerHTML = screenHtml(model, { vehicleId: id, title, perms, loading: !payload || !detail, note: state.note });
    if (open) dialog.querySelector('.pvs-others')?.setAttribute('open', '');
    const body = dialog.querySelector('.pvs-body'); if (body) body.scrollTop = scroll;
  }
  async function load(force) {
    const vehicle = vehicleByKey(state.key);
    if (!vehicle) return;
    const id = canonicalId(vehicle);
    const jobs = [];
    if (typeof root.loadVehicleWorkshopDetail === 'function') jobs.push(root.loadVehicleWorkshopDetail(vehicle, { force }).catch(() => null));
    if (root.PDC_SUBLET_PO?.fetch && id) jobs.push(root.PDC_SUBLET_PO.fetch(id).catch(() => null));
    draw();
    await Promise.all(jobs);
    draw();
  }
  async function setCategory(button, category) {
    const vehicle = vehicleByKey(state.key);
    const id = canonicalId(vehicle);
    const detail = detailFor(id);
    const config = root.PDC_SUPABASE_CONFIG || {};
    const token = typeof root.getPdcSupabaseAccessToken === 'function' ? root.getPdcSupabaseAccessToken() : null;
    if (!detail || !token || !config.url || !config.publishableKey) { notify('Sign in again, then retry.'); return; }
    const words = category === 'SUBLET' ? 'Make this whole operation line a sublet? It moves to the Sublet box (never a bay) and imports keep it there.'
      : `Move this line back to ${categoryLabel(category)}? It stops being a whole line sublet; any GP PO stays on the line as a sublet item.`;
    if (typeof root.confirm === 'function' && !root.confirm(words)) return;
    button.disabled = true;
    try {
      const response = await root.fetch(`${String(config.url).replace(/\/$/, '')}/rest/v1/rpc/set_vehicle_work_category`, {
        method: 'POST', headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ p_vehicle_id: id, p_vehicle_expected_version: detail.vehicle_version, p_line_identity: lineIdentityFor(detail, button.dataset.pvsWhole || button.dataset.pvsMove),
          p_category: category, p_category_expected_version: Number(button.dataset.categoryVersion || 0) }) });
      const result = await response.json().catch(() => ({}));
      if (!response.ok || result?.ok !== true) throw new Error(result?.message || ({ category_booking_exists: 'This line has a booking. Split or cancel the unstarted booking first; a sublet is never booked into a bay.', category_version_conflict: 'Someone else changed this line; reloaded.', vehicle_version_conflict: 'The vehicle changed; reloaded.' })[result?.error] || result?.error || 'Not saved. Refresh and try again.');
      notify(category === 'SUBLET' ? 'Whole line is now a sublet' : `Moved back to ${categoryLabel(category)}`, 'success');
    } catch (error) { notify(error.message || 'Not saved.'); }
    finally { button.disabled = false; await load(true); try { root.refreshAllViews?.(); } catch (_) { /* next render */ } }
  }
  function lineIdentityFor(detail, id) {
    const lines = detail?.job_card_lines || detail?.operation_lines || [];
    const hit = lines.find(line => sid(line.line_identity || line.workshopLineKey || line.operation_line_id) === id);
    return hit?.line_identity || `source:${id}`;
  }
  function onClick(event) {
    const t = event.target;
    if (t.closest('[data-pvs-close]')) { close(); return; }
    const email = t.closest('[data-pvs-email]');
    if (email) { try { root.draftSubletProviderEmail(email.dataset.pvsEmail); } catch (_) { notify('The email could not be drafted.'); } return; }
    const whole = t.closest('[data-pvs-whole]');
    if (whole) { setCategory(whole, 'SUBLET'); return; }
    const move = t.closest('[data-pvs-move]');
    if (move) {
      const to = move.parentElement?.querySelector('[data-pvs-move-to]')?.value || '';
      if (!to) { notify('Choose the category the line goes back to.'); return; }
      setCategory(move, to); return;
    }
    if (t.closest('[data-pvs-open-sublet]')) {
      const vehicle = vehicleByKey(state.key); close();
      try { root.openSubletForStock(vehicle?.stock || root.displayStockNumber?.(vehicle) || ''); } catch (_) { /* nav unavailable */ }
    }
  }
  function open(key) {
    state.key = key; state.note = '';
    const shell = ensureShell();
    shell.classList.add('is-open');
    doc.body.classList.add('pvs-open');
    load(false);
    shell.querySelector('.pvs-close')?.focus?.({ preventScroll: true });
  }
  function close() {
    state.key = '';
    doc.getElementById('pvs-shell')?.classList.remove('is-open');
    doc.body.classList.remove('pvs-open');
  }
  api.open = open; api.close = close;
  doc.addEventListener('keydown', event => { if (event.key === 'Escape' && state.key) { event.stopPropagation(); close(); } }, true);
  // A tick saved by pdc-sublet-po.js reloads that vehicle's GP PO lines; redraw the open screen with them.
  root.addEventListener?.('pdc-sublet-lines', event => { if (state.key && (!event.detail?.vehicleId || event.detail.vehicleId === state.vehicleId)) draw(); });
  // The slide-out (r485) rebuilds its panel on every refresh: add the button to its open row each time.
  function addButton(panel) {
    const row = panel?.querySelector?.('.vso-open-row');
    if (!row || row.querySelector('[data-pvs-manage]')) return;
    const key = panel.querySelector('details.vso-card')?.dataset.incomingRow || '';
    if (!key) return;
    const button = doc.createElement('button');
    button.type = 'button'; button.className = 'vso-open-vehicle pvs-manage'; button.dataset.pvsManage = key;
    button.textContent = 'Manage sublets'; button.title = 'Every sublet on this vehicle: whole line sublets and sublet items, POs, suppliers, dates and done ticks';
    button.addEventListener('click', event => { event.stopPropagation(); open(key); });
    row.appendChild(button);
  }
  function watch() {
    const shell = doc.getElementById('vso-shell');
    const panel = shell?.querySelector('.vso-panel');
    if (!panel || panel.__pvsWatched) return Boolean(panel);
    panel.__pvsWatched = true;
    addButton(panel);
    if (typeof root.MutationObserver === 'function') new root.MutationObserver(() => addButton(panel)).observe(panel, { childList: true });
    return true;
  }
  if (!watch() && typeof root.MutationObserver === 'function') {
    const bodyWatch = new root.MutationObserver(() => { if (watch()) bodyWatch.disconnect(); });
    bodyWatch.observe(doc.body, { childList: true });
  }
}(typeof window !== 'undefined' ? window : globalThis));
