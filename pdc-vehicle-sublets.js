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
 * line' until it is ticked done or the user presses 'Got it'; the purchaser is the supplier (the sublet provider).
 * r494b (Craig 22 Oct 18:55): no 'PO raised for this line' / 'Got it' (the GP PO number shows it); 'PO to raise' sits in
 * the GP PO column as a chip the same size as a GP PO number; one text size in the tables.
 * r501 (F114, Craig 23 Oct 07:55): 'when it's got PO to raise can we have the due outs and due back dates on this screen
 * ... all the sublet bookings need to be done from the side menu'. Each whole line sublet row here now has Supplier, Due out
 * and Due back inputs with Save / Clear (operators and administrators, the roles the booking RPCs allow), also while the
 * line says 'PO to raise'. Save goes through the same booking service the Sublet page used (createSubletBooking ->
 * create_pdc_sublet_operation_booking for the line; updateSubletBooking / updateSubletBookingProvider for an active
 * booking), then one snapshot refresh, so the booking is on the Sublet calendar straight away. Clear cancels the line's
 * active booking with the existing cancel_pdc_sublet_booking RPC (history kept; the line goes back to Sublet To Book).
 * Due back must be on or after Due out. The Sublet page no longer creates bookings (pdc-sublet-intake.js). No new SQL.
 * r502 (F115, Craig 23 Oct 08:34): Manage sublets Save showed 'Not saved. Refresh and try again.' because failText hid every
 * create/update code that was not in SAVE_ERRORS (not_authenticated, session_changed, sublet_create_unavailable, vehicle_not_found,
 * and PostgREST/PG codes). Toast now maps those and always shows the raw code. Identity is normalised to source:/manual: + lowercase;
 * notes truncated to 2000. Revolution '^' line-breaks in GP PO wording are cleaned to ' · ' (same as the Sublet box). Sublet items
 * get 'Whole line sublet' (promote; reverse of Move). Wording truncated with hover overlay so the table stays neat. Pit inspection /
 * pit and weigh|way / weighbridge|waybridge wording is sorted first in 'Make a whole operation line a sublet' (import may still own
 * the category; booking still needs stage SUBLET). No SQL applied. */
(function (root) {
  'use strict';
  const VERSION = '2026.10.23.r502';
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  /** One identity for a line across job cards, GP PO lines and Sublet bookings ("source:<uuid>" = "<uuid>"). */
  const sid = value => String(value ?? '').trim().toLowerCase().replace(/^(source|manual|operation):/, '');
  /** Booking RPC identity: source:|manual: + lowercase uuid (CHECK + create_pdc_sublet_operation_booking). */
  function normalizeOperationIdentity(value) {
    const raw = String(value || '').trim().toLowerCase();
    if (/^(source|manual):[0-9a-f-]{36}$/.test(raw)) return raw;
    const bare = raw.replace(/^(source|manual|operation):/, '');
    if (/^[0-9a-f-]{36}$/.test(bare)) return `source:${bare}`;
    return raw;
  }
  /** Revolution GP PO descriptions use '^' as a line break; show ' · ' like the Sublet box (pdc-sublet-po cleanDescription). */
  function cleanDescription(text) {
    return String(text ?? '').split('^').map(part => part.replace(/\s+/g, ' ').trim()).filter(Boolean).join(' · ');
  }
  /** Craig standing rule: pit inspection / pit and weigh|way / weighbridge|waybridge are always sublets (import may own the category). */
  function isAlwaysSubletWording(text) {
    const t = String(text || '').toLowerCase().replace(/\s+/g, ' ');
    return /pit\s*inspection/.test(t)
      || /pit\s*(?:and|&)\s*weigh/.test(t)
      || /pit\s*(?:and|&)\s*way\b/.test(t)
      || /weigh\s*bridge/.test(t)
      || /way\s*bridge/.test(t);
  }
  /** Short label + full text on hover (title + overlay) so Manage sublets stays neat. */
  function clipHtml(text, max = 64) {
    const clean = cleanDescription(text);
    if (!clean) return '—';
    const short = clean.length > max ? `${clean.slice(0, Math.max(1, max - 1))}…` : clean;
    return `<span class="pvs-clip" title="${esc(clean)}"><span class="pvs-clip-text">${esc(short)}</span><span class="pvs-clip-full" role="tooltip">${esc(clean)}</span></span>`;
  }
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
    const byPo = new Map(details.filter(d => d && d.po_number).map(d => [String(d.po_number), cleanDescription(d.description)]));
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
    const bookingsFor = id => rows.filter(row => id && sid(row.__subletOperationIdentity) === id && row.__subletBookingStatus !== 'cancelled');
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
    const loose = rows.filter(row => row.__subletBookingStatus !== 'cancelled' && (!sid(row.__subletOperationIdentity) || !seen.has(sid(row.__subletOperationIdentity))));
    const others = lines.filter(line => {
      const id = sid(line.line_identity || line.workshopLineKey || line.operation_line_id);
      return id && !isWholeLine(line) && line.completed !== true && !['JOB_CARD_NOTES', 'UNALLOCATED_MAPPING_REVIEW'].includes(String(line.work_category || '').toUpperCase());
    }).map(line => entry(sid(line.line_identity || line.workshopLineKey || line.operation_line_id), line, poById.get(sid(line.line_identity))))
      .sort((a, b) => {
        const aw = isAlwaysSubletWording(a.description) || a.pos.some(p => isAlwaysSubletWording(p.description)) ? 0 : 1;
        const bw = isAlwaysSubletWording(b.description) || b.pos.some(p => isAlwaysSubletWording(p.description)) ? 0 : 1;
        return aw - bw || sort(a, b);
      });
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
    if (!row.tickable) return '<span class="pvs-muted" title="The done tick appears once the GP PO import attaches the PO">—</span>'; // r494b: 'PO to raise' is in the GP PO column
    const po = row.po, ticked = po.ticked === true;
    const title = !canTick ? `Sublet done: ${ticked ? 'yes' : 'not yet'}. Read only: controllers, administrators and fitters tick sublet done`
      : ticked ? 'Sublet done. Untick if the sublet is not done' : 'Tick when the supplier has finished this';
    // Same markup as the r439/r444 Sublet box tick, so pdc-sublet-po.js saves it with set_pdc_sublet_line_tick_439.
    return `<span class="pdc-sublet-po-inline pvs-tick is-${ticked ? 'done' : 'ordered'}" data-pdc-sublet-vehicle="${esc(vehicleId)}" data-line-key="${esc(po.line_key || '')}" data-version="${esc(Number(po.version) || 0)}">`
      + `<input type="checkbox" class="pdc-sublet-po-tick" title="${esc(title)}" aria-label="${esc(`${lineLabel(row.operationNo)} sublet done`)}"${ticked ? ' checked' : ''}${!canTick || po.tickable === false ? ' disabled' : ''}>`
      + `<span>${ticked ? 'Done' : 'Not done'}</span></span>`;
  }
  function bookingCells(bookings, canEmail, emptyText = 'No supplier booked yet') {
    if (!bookings.length) return `<td class="pvs-muted" colspan="5">${esc(emptyText)}</td><td></td>`;
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
    // r494b: a whole line sublet with no GP PO shows 'PO to raise' here, the same chip size as a GP PO number.
    if (!row.pos.length) return `<span class="pvs-nopo" title="No GP purchase order on this whole line sublet yet: raise the PO. The done tick appears once the GP PO import attaches it.">PO to raise</span>`;
    return row.pos.map(p => `<span class="pvs-po" title="${esc(p.description || 'GP purchase order')}">${esc(p.po)}</span>${p.description ? `<small class="pvs-po-desc">${clipHtml(p.description, 56)}</small>` : ''}`).join('');
  }
  function moveBackHtml(row, choices) {
    const options = choices.filter(code => code !== 'SUBLET').map(code => `<option value="${esc(code)}">${esc(categoryLabel(code))}</option>`).join('');
    return `<label class="pvs-move"><select data-pvs-move-to aria-label="Move ${esc(lineLabel(row.operationNo))} back to"><option value="">Not a whole line sublet…</option>${options}</select></label>`
      + `<button type="button" class="small-button" data-pvs-move="${esc(row.id)}" data-category-version="${esc(row.categoryVersion)}">Move</button>`;
  }
  // r501 (F114): Due out / Due back / Supplier on whole line sublet rows (Manage sublets is the only place bookings are made).
  const plainDate = value => { const m = String(value || '').match(/^(\d{4}-\d{2}-\d{2})/); return m ? m[1] : ''; };
  /** The line's bookable state: its active booking, else its pending 'Sublet To Book' row from the Sublet list, else a returned one. */
  function lineBooking(row) {
    const list = row?.bookings || [];
    const active = list.find(b => b.__subletBookingId && (b.__subletBookingStatus || 'active') === 'active') || null;
    const pending = active ? null : list.find(b => !b.__subletBookingId && b.__subletOperationIdentity) || null;
    const returned = list.find(b => b.__subletBookingId && b.__subletBookingStatus === 'returned') || null;
    return { active, pending, returned };
  }
  /** '' when the dates can be saved, else the message to show. Dates are yyyy-mm-dd (input type=date). */
  function datesError(out, back) {
    const o = plainDate(out), b = plainDate(back);
    if (!o || !b) return 'Enter both Due out and Due back.';
    if (b < o) return 'Due back must be on or after Due out.';
    return '';
  }
  /** What Save does for a line: { error } or { kind: 'create' | 'update', steps }. */
  function planSave(row, { providerId = '', out = '', back = '' } = {}) {
    const { active, pending } = lineBooking(row);
    if (!active && !pending) return { error: 'This line is not on the Sublet list yet. Refresh the board, then try again.' };
    const error = datesError(out, back);
    if (error) return { error };
    const o = plainDate(out), b = plainDate(back);
    if (!active) {
      if (!providerId) return { error: 'Choose the supplier first.' };
      const identity = normalizeOperationIdentity(pending.__subletOperationIdentity);
      if (!/^(source|manual):[0-9a-f-]{36}$/.test(identity)) return { error: 'This line is no longer an open Sublet line. Refresh the board.' };
      return { kind: 'create', identity, providerId, out: o, back: b, notes: String(pending.pmbSubletNotes || '').slice(0, 2000), steps: ['create'] };
    }
    const steps = [];
    if (providerId && providerId !== String(active.__subletProviderId || '')) steps.push('provider');
    if (o !== plainDate(active.pmbSubletBookingDate) || b !== plainDate(active.pmbSubletExpectedReturnDate)) steps.push('dates');
    if (!steps.length) return { error: 'Nothing changed.' , unchanged: true };
    return { kind: 'update', bookingId: active.__subletBookingId, version: Number(active.__subletBookingVersion) || 0, providerId, out: o, back: b, steps };
  }
  const SAVE_ERRORS = {
    invalid_input: 'Enter a supplier, Due out and Due back (Due back on or after Due out).',
    sublet_operation_not_available: 'This line is no longer an open Sublet line. Refresh the board.',
    vehicle_review_not_approved: 'Approve the vehicle intake review first, then book the sublet.',
    sublet_operation_already_booked: 'This line already has a booking. Refreshed: check it and try again.',
    provider_not_found: 'That supplier is not active. Choose another supplier.',
    vehicle_not_found: 'That vehicle is not on the board. Refresh, then try again.',
    vehicle_version_conflict: 'The vehicle changed. Refreshed: try again.',
    version_conflict: 'Someone else changed this booking. Refreshed: try again.',
    sublet_booking_overlap: 'Those dates overlap another booking for this line.',
    booking_not_active: 'This booking is no longer active. Refreshed.',
    invalid_cancel_state: 'This booking cannot be cleared now (it may be back already).',
    unauthorized: 'Only operators and administrators book sublets.',
    not_authenticated: 'Sign in again, then retry.',
    session_changed: 'Your sign-in changed while saving. Sign in again, then retry.',
    sublet_create_unavailable: 'Not saved: connection issue. Check the network, refresh, then try again.',
    sublet_update_unavailable: 'Not saved: connection issue. Check the network, refresh, then try again.',
    wrong_environment: 'Not saved: this page is not connected to the PDC database.',
  };
  /** Prefer a mapped phrase; always keep the raw code so a new failure is diagnosable (F115). */
  const failText = result => {
    const code = String(result?.code || '').trim();
    const mapped = SAVE_ERRORS[code];
    if (mapped) return mapped;
    if (code) return `Not saved (${code}). Refresh and try again.`;
    return String(result?.message || '').trim() || 'Not saved. Refresh and try again.';
  };
  const nextVersion = (result, version) => { const v = Number(result?.data?.booking?.version ?? result?.data?.version); return Number.isFinite(v) && v > version ? v : version + 1; };
  /** Run a planSave() plan. deps: { service, vehicle: { id, version }, providerEmail, idempotencyKey }. One call per step, no retries. */
  async function performSave(plan, deps) {
    const svc = deps.service;
    if (!svc) return { ok: false, message: 'Sign in again, then retry.' };
    if (plan.kind === 'create') {
      const r = await svc.createSubletBooking(deps.vehicle.id, deps.vehicle.version, plan.providerId, plan.out, plan.back, deps.providerEmail || '', plan.notes || '', plan.identity);
      return r?.ok ? { ok: true, created: true } : { ok: false, code: r?.code, message: failText(r) };
    }
    let version = plan.version;
    for (const step of plan.steps) {
      const r = step === 'provider'
        ? await svc.updateSubletBookingProvider(plan.bookingId, version, plan.providerId, deps.providerEmail || '', deps.idempotencyKey || '')
        : await svc.updateSubletBooking(plan.bookingId, version, plan.out, plan.back, null);
      if (!r?.ok) return { ok: false, code: r?.code, message: failText(r), partial: step !== plan.steps[0] };
      version = nextVersion(r, version);
    }
    return { ok: true };
  }
  /** Clear dates on a line = cancel its active booking (existing cancel_pdc_sublet_booking; history kept). */
  async function performClear(active, deps) {
    if (!active?.__subletBookingId) return { ok: true, nothing: true };
    const r = await deps.cancel(active.__subletBookingId, Number(active.__subletBookingVersion) || 0, 'Dates cleared in Manage sublets');
    return r?.ok ? { ok: true } : { ok: false, code: r?.code, message: failText(r) };
  }
  function editorCells(row, p) {
    const { active, pending, returned } = lineBooking(row);
    if (!active && !pending) {
      if (returned) return bookingCells([returned], p.canEmail);
      return '<td class="pvs-muted" colspan="5">Not on the Sublet list yet: refresh the board, then set the dates here.</td><td></td>';
    }
    const b = active || pending;
    const draft = p.drafts?.[row.id] || {};
    const providerId = draft.providerId ?? String(active?.__subletProviderId || '');
    const out = draft.out ?? plainDate(b.pmbSubletBookingDate);
    const back = draft.back ?? plainDate(b.pmbSubletExpectedReturnDate);
    const providers = (p.providers || []).slice();
    if (active?.__subletProviderId && !providers.some(x => String(x.id) === String(active.__subletProviderId))) providers.unshift({ id: active.__subletProviderId, name: active.pmbSubletProvider || 'Current supplier' });
    const label = lineLabel(row.operationNo);
    const options = `<option value="">${providers.length ? 'Choose supplier…' : 'No suppliers loaded'}</option>`
      + providers.map(x => `<option value="${esc(x.id)}"${String(x.id) === providerId ? ' selected' : ''}>${esc(x.name || x.id)}</option>`).join('');
    const status = statusText(b);
    const busy = p.busy === row.id;
    const msg = p.messages?.[row.id];
    const key = b.__subletBookingId || b.__subletOperationKey || '';
    const email = p.canEmail && active && b.pmbSubletProvider && key ? `<button type="button" class="small-button pvs-email" data-pvs-email="${esc(key)}" title="Draft the supplier email (opens your mail app; nothing is sent)">Draft email</button>` : '';
    return `<td><select class="pvs-in" data-pvs-f="providerId" data-pvs-row="${esc(row.id)}" aria-label="${esc(label)} supplier"${busy ? ' disabled' : ''}>${options}</select></td>`
      + `<td><input type="date" class="pvs-in" data-pvs-f="out" data-pvs-row="${esc(row.id)}" value="${esc(out)}" aria-label="${esc(label)} due out"${busy ? ' disabled' : ''}></td>`
      + `<td><input type="date" class="pvs-in" data-pvs-f="back" data-pvs-row="${esc(row.id)}" value="${esc(back)}"${out ? ` min="${esc(out)}"` : ''} aria-label="${esc(label)} due back"${busy ? ' disabled' : ''}></td>`
      + `<td>${dateText(b.pmbSubletActualReturnDate)}</td><td><span class="pvs-status ${statusTone(status)}">${esc(status)}</span></td>`
      + `<td><div class="pvs-save-actions"><button type="button" class="small-button pvs-save" data-pvs-save="${esc(row.id)}"${busy ? ' disabled' : ''} title="Save the supplier and dates; the booking shows on the Sublet calendar">${busy ? 'Saving…' : 'Save'}</button>`
      + `<button type="button" class="small-button pvs-clear" data-pvs-clear="${esc(row.id)}"${busy ? ' disabled' : ''} title="${active ? 'Clear the dates: cancels this booking (history kept) and the line goes back to Sublet To Book' : 'Clear the dates you typed'}">Clear</button>${email}</div>`
      + (msg ? `<small class="pvs-msg ${msg.ok ? 'is-ok' : 'is-err'}" role="status">${esc(msg.text)}</small>` : '') + '</td>';
  }
  const HEAD = '<thead><tr><th>Line</th><th>Sublet work</th><th>GP PO</th><th>Done</th><th>Supplier</th><th>Due out</th><th>Due back</th><th>Back</th><th>Status</th><th></th></tr></thead>';
  /** The screen's HTML. perms: { canTick, canMove, canEmail, choices, canBook, providers, drafts, messages, busy }. */
  function screenHtml(model, { vehicleId = '', title = '', subtitle = '', perms = {}, loading = false, note = '' } = {}) {
    const p = { canTick: false, canMove: false, canEmail: false, canBook: false, providers: [], drafts: null, messages: null, busy: '', choices: [], seen: null, ...perms };
    // r494b (F107): no 'PO raised for this line' note here any more (perms.seen is ignored); the GP PO number shows it.
    const pill = model.state === 'none' ? '<span class="pvs-pill is-none">No sublets</span>'
      : model.state === 'done' ? `<span class="pvs-pill is-done">✓ All ${model.total} done</span>`
        : `<span class="pvs-pill is-open">! ${model.open} open · ${model.done}/${model.total} done</span>`;
    const wholeRows = model.whole.map(row => `<tr data-pvs-line="${esc(row.id)}"><td><b>${esc(lineLabel(row.operationNo))}</b></td>`
      + `<td>${clipHtml(row.description || '—', 72)}${p.canMove && !row.completed ? `<div class="pvs-line-actions">${moveBackHtml(row, p.choices)}</div>` : ''}</td>`
      + `<td>${poCell(row)}</td><td>${tickHtml(row, vehicleId, p.canTick)}</td>${p.canBook && !row.completed ? editorCells(row, p)
        : bookingCells(row.bookings, p.canEmail, p.canBook ? 'No supplier booked yet' : 'No supplier booked yet: operators and administrators book it here')}</tr>`).join('');
    const itemRows = model.items.map(row => {
      const itemDesc = row.pos.map(x => cleanDescription(x.description)).filter(Boolean).join('; ');
      const promote = p.canMove && !row.completed
        ? `<button type="button" class="small-button pvs-promote" data-pvs-whole="${esc(row.id)}" data-category-version="${esc(row.categoryVersion)}" title="Make this whole operation line a sublet (moves to Whole line sublets)">Whole line sublet</button>`
        : '';
      return `<tr class="pvs-op" data-pvs-line="${esc(row.id)}"><td><b>${esc(lineLabel(row.operationNo))}</b></td>`
        + `<td colspan="9"><span class="pvs-cat">${esc(categoryLabel(row.category))}</span> ${clipHtml(row.description || '—', 72)} <small class="pvs-muted">· the line stays in ${esc(categoryLabel(row.category))}</small>${promote ? ` ${promote}` : ''}</td></tr>`
        + `<tr class="pvs-item"><td class="pvs-indent">↳ Sublet</td><td>${itemDesc ? clipHtml(itemDesc, 72) : '<span class="pvs-muted">No sublet description in the upload yet</span>'}</td>`
        + `<td>${row.pos.map(x => `<span class="pvs-po" title="${esc(cleanDescription(x.description) || 'GP purchase order')}">${esc(x.po)}</span>`).join('')}</td><td>${tickHtml(row, vehicleId, p.canTick)}</td>${bookingCells(row.bookings, p.canEmail)}</tr>`;
    }).join('');
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
      + `<footer class="pvs-foot"><span class="pvs-muted">${p.canTick ? 'Ticks save straight away.' : 'Read only: controllers, administrators and fitters tick sublet done.'}${p.canMove ? '' : ' Operators and administrators change whole line sublets.'}${p.canBook ? ' Due out and Due back save to the Sublet calendar.' : ''}</span><button type="button" class="small-button" data-pvs-open-sublet>Open Sublet page</button></footer></div>`;
  }
  const api = { VERSION, sid, normalizeOperationIdentity, cleanDescription, isAlwaysSubletWording, clipHtml, isWholeLine, poList, buildModel, screenHtml, categoryLabel, lineLabel, dateText, statusTone, lineBooking, datesError, planSave, performSave, performClear, SAVE_ERRORS, failText };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (!root || !root.document || root.PDC_VEHICLE_SUBLETS) return;
  root.PDC_VEHICLE_SUBLETS = api;
  const doc = root.document;
  const state = { key: '', vehicleId: '', note: '', model: null, drafts: {}, messages: {}, busy: '', providersAsked: false, drawTimer: 0 };
  const role = () => String(root.PDC_AUTH_CONTEXT?.role || '').trim().toLowerCase();
  const vehicleByKey = key => {
    try { const rows = typeof root.vehicleLocationsScreenRows === 'function' ? root.vehicleLocationsScreenRows() : []; const hit = rows.find(row => root.vehicleKey(row) === key); if (hit) return hit; } catch (_) { /* fallback */ }
    try { return typeof root.selectedVehicle === 'function' ? root.selectedVehicle(key) : null; } catch (_) { return null; }
  };
  const canonicalId = vehicle => { try { return root.vehicleWorkshopDetailCanonicalId(vehicle) || ''; } catch (_) { return ''; } };
  const detailFor = id => { try { return root.app?.vehicleWorkshopDetailCache?.get(id)?.detail || (typeof app !== 'undefined' ? app.vehicleWorkshopDetailCache.get(id)?.detail : null) || null; } catch (_) { return null; } };
  const bookingsFor = key => { try { return typeof root.subletRows === 'function' ? root.subletRows().filter(row => row.__subletVehicleKey === key) : []; } catch (_) { return []; } };
  const notify = (message, tone) => { try { root.pdcNotify(message, tone); } catch (_) { /* no toast */ } };
  // r501 (F114): the booking service the Sublet page uses (app is a top-level const in app.js; window.app is the same object).
  const appObj = () => root.app || (typeof app !== 'undefined' ? app : null);
  const bookingService = () => appObj()?.emailVehicleLocationService || null;
  const providerList = () => { try { return (typeof root.loadSubletProviderRecords === 'function' ? root.loadSubletProviderRecords() : []).filter(x => x && x.id && x.active !== false); } catch (_) { return []; } };
  const canBook = vehicle => ['operator', 'administrator'].includes(role()) && vehicle?.__emailVehicleServerAuthoritative === true && Boolean(vehicle.__emailVehicleId) && Boolean(bookingService()?.createSubletBooking);
  // One redraw per burst (a save refresh, the provider list arriving) - never one per RPC answer.
  function scheduleDraw() { if (state.drawTimer) return; state.drawTimer = root.setTimeout(() => { state.drawTimer = 0; draw(); }, 30); }
  function ensureShell() {
    let shell = doc.getElementById('pvs-shell');
    if (shell) return shell;
    shell = doc.createElement('div');
    shell.id = 'pvs-shell';
    shell.innerHTML = '<div class="pvs-scrim" data-pvs-close></div><section class="pvs-dialog" role="dialog" aria-modal="true" aria-label="Manage sublets"></section>';
    doc.body.appendChild(shell);
    shell.addEventListener('click', onClick);
    shell.addEventListener('input', onInput);
    shell.addEventListener('change', onInput);
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
    const perms = { canTick: payload?.can_tick === true, canMove, canEmail: true, choices, seen: root.PDC_SUBLET_PO?.seen?.() || null,
      canBook: canBook(vehicle), providers: providerList(), drafts: state.drafts, messages: state.messages, busy: state.busy };
    state.model = model;
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
  // r501 (F114): Save / Clear for a whole line sublet's Supplier, Due out and Due back.
  function readInputs(rowId) {
    const shell = doc.getElementById('pvs-shell');
    const draft = { ...(state.drafts[rowId] || {}) };
    shell?.querySelectorAll?.('[data-pvs-row]')?.forEach?.(input => { if (input.dataset.pvsRow === rowId) draft[input.dataset.pvsF] = String(input.value || ''); });
    return draft;
  }
  function onInput(event) {
    const input = event.target?.closest?.('[data-pvs-row]');
    if (!input) return;
    const rowId = input.dataset.pvsRow;
    state.drafts[rowId] = { ...(state.drafts[rowId] || {}), [input.dataset.pvsF]: String(input.value || '') };
    delete state.messages[rowId];
    if (input.dataset.pvsF === 'out') {
      const back = input.closest('tr')?.querySelector?.('[data-pvs-f="back"]');
      if (back) back.min = input.value || '';
    }
    const error = state.drafts[rowId].out && state.drafts[rowId].back ? datesError(state.drafts[rowId].out, state.drafts[rowId].back) : '';
    input.closest('tr')?.querySelector?.('[data-pvs-f="back"]')?.setCustomValidity?.(error);
  }
  async function afterBookingChange() {
    let refreshed = true;
    try { refreshed = typeof root.refreshEmailVehicleLocations === 'function' ? await root.refreshEmailVehicleLocations() : true; } catch (_) { refreshed = false; }
    try { if (appObj()?.currentView === 'sublet' && typeof root.renderSubletHome === 'function') root.renderSubletHome(); } catch (_) { /* next render */ }
    scheduleDraw();
    return refreshed !== false;
  }
  async function cancelBooking(bookingId, expectedVersion, reason) {
    const svc = bookingService();
    if (typeof svc?.cancelSubletBooking === 'function') return svc.cancelSubletBooking(bookingId, expectedVersion, reason);
    const config = root.PDC_SUPABASE_CONFIG || {};
    const token = typeof root.getPdcSupabaseAccessToken === 'function' ? root.getPdcSupabaseAccessToken() : null;
    if (!token || !config.url || !config.publishableKey) return { ok: false, message: 'Sign in again, then retry.' };
    // Existing RPC (supabase/staging_only/171): cancels the booking, keeps its history, frees the line to be booked again.
    const response = await root.fetch(`${String(config.url).replace(/\/$/, '')}/rest/v1/rpc/cancel_pdc_sublet_booking`, {
      method: 'POST', headers: { apikey: config.publishableKey, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_booking_id: bookingId, p_expected_version: expectedVersion, p_reason: reason }) });
    const body = await response.json().catch(() => ({}));
    const result = Array.isArray(body) ? body[0] : body;
    return response.ok && result?.ok === true ? { ok: true, data: result } : { ok: false, code: result?.code || result?.error || '', message: result?.message || '' };
  }
  async function saveLine(rowId) {
    if (state.busy) return;
    const row = state.model?.whole.find(r => r.id === rowId);
    const vehicle = vehicleByKey(state.key);
    if (!row || !vehicle || !canBook(vehicle)) { notify('Only operators and administrators book sublets.'); return; }
    const draft = readInputs(rowId);
    const plan = planSave(row, draft);
    if (plan.error) { state.messages[rowId] = { ok: false, text: plan.error }; draw(); if (!plan.unchanged) notify(plan.error); return; }
    const provider = providerList().find(x => String(x.id) === String(plan.providerId)) || null;
    state.busy = rowId; state.messages[rowId] = null; draw();
    let result;
    try {
      result = await performSave(plan, { service: bookingService(), vehicle: { id: vehicle.__emailVehicleId, version: Number(vehicle.__emailVehicleVersion) || 0 },
        providerEmail: String(provider?.email || '').trim(), idempotencyKey: root.crypto?.randomUUID?.() || '' });
    } catch (_) { result = { ok: false, message: 'Not saved: check your connection, then try again.' }; }
    state.busy = '';
    if (result.ok) {
      delete state.drafts[rowId];
      const text = `Saved: Due out ${dateText(plan.out)} · Due back ${dateText(plan.back)}. On the Sublet calendar.`;
      state.messages[rowId] = { ok: true, text };
      notify(text, 'info');
    } else {
      state.messages[rowId] = { ok: false, text: result.message };
      notify(result.message);
    }
    if (!(await afterBookingChange()) && result.ok) notify('Saved, but the list could not be refreshed. Refresh the board before another change.');
  }
  async function clearLine(rowId) {
    if (state.busy) return;
    const row = state.model?.whole.find(r => r.id === rowId);
    if (!row) return;
    const { active } = lineBooking(row);
    if (!active) { delete state.drafts[rowId]; delete state.messages[rowId]; draw(); return; }
    if (typeof root.confirm === 'function' && !root.confirm(`Clear Due out and Due back for ${lineLabel(row.operationNo)}? This cancels the booking with ${active.pmbSubletProvider || 'the supplier'} (history is kept) and the line goes back to Sublet To Book.`)) return;
    state.busy = rowId; draw();
    let result;
    try { result = await performClear(active, { cancel: cancelBooking }); } catch (_) { result = { ok: false, message: 'Not cleared: check your connection, then try again.' }; }
    state.busy = '';
    delete state.drafts[rowId];
    state.messages[rowId] = result.ok ? { ok: true, text: 'Dates cleared: back to Sublet To Book.' } : { ok: false, text: result.message };
    notify(result.ok ? 'Dates cleared: the line is back to Sublet To Book.' : result.message, result.ok ? 'info' : undefined);
    await afterBookingChange();
  }
  function onClick(event) {
    const t = event.target;
    if (t.closest('[data-pvs-close]')) { close(); return; }
    const save = t.closest('[data-pvs-save]');
    if (save) { saveLine(save.dataset.pvsSave); return; }
    const clear = t.closest('[data-pvs-clear]');
    if (clear) { clearLine(clear.dataset.pvsClear); return; }
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
    if (state.key !== key) { state.drafts = {}; state.messages = {}; }
    state.key = key; state.note = '';
    // r501: the supplier list is cached by the Sublet page; ask once only if it is empty (one redraw when it lands).
    const svc = (() => { try { return typeof root.initWorkshopReferenceDataServiceIfAvailable === 'function' ? root.initWorkshopReferenceDataServiceIfAvailable() : root.__workshopReferenceDataService; } catch (_) { return null; } })();
    if (!state.providersAsked && !providerList().length && typeof svc?.listSubletProviders === 'function') {
      state.providersAsked = true;
      Promise.resolve(svc.listSubletProviders()).then(() => { if (state.key) scheduleDraw(); }, () => {});
    }
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
