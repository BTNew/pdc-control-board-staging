/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r499b (F112, Craig 23 Oct): the PMB station icons (Parts / JITA, Tint, Bus 4x4, Hoist, Fitting, Fab, Elec, Tyre, Sublet) in the
   Sales PMB STATUS column, read only. Same rules, markup and colours as the Control Board strip (app.js incomingWorkChecklistHtml,
   with Sublet recoloured as pdc-sublet-po.js decorateStrip does); test_sales_pmb_stations_499.js renders both and compares them.
   r499b: a station whose workshop booking status is started also gets is-started (the planner's class). The Sales stylesheet
   runs the planner's workshop-started-blue-pulse on that class. Completed and STOPPAGE stations do not flash.
   Performance: ONE batched read per Sales refresh (get_broome_sales_pmb_stations, every linked vehicle in a single call), the
   strip HTML is built once per answer and cached by vehicle id, and render() only reads the cache. Nothing runs per vehicle
   while the table draws: no call, no fetch and no extra table redraw. If the read is missing or fails, no icons show (the
   existing PMB text stays) and the failure is logged once. Unlinked vehicles keep their text and get no icons. */
(function (root) {
  'use strict';
  const guardApi = root.VehicleRequirementsGuard || (typeof module === 'object' && module.exports ? require('../vehicle-requirements-guard.js') : null);
  const eligibility = root.PDC_WORKSHOP_ELIGIBILITY || (typeof module === 'object' && module.exports ? require('../workshop-eligibility.js') : null);
  const RPC = 'get_broome_sales_pmb_stations';
  const MAX_IDS = 1000;
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
  const esc = value => String(value ?? '').replace(/[&<>'"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[c]));
  const clean = value => String(value ?? '').replace(/[\r\n]+/g, ' ').replace(/\s+/g, ' ').trim();
  // The board's PDC_JOB_DEFS (label, requireKey, completeKey) in its row order (pdcJobDefsPartsFirst).
  const DEFS = Object.freeze([
    ['parts', 'PARTS', 'Parts'], ['tint', 'TINT', 'Tint'], ['bus4x4', 'BUS 4X4', 'Bus 4x4'], ['hoist', 'HOIST', 'Hoist'], ['fitting', 'FITTING', 'Fitting'],
    ['fabrication', 'FAB', 'Fab'], ['electrical', 'ELEC', 'Elec'], ['tyre', 'TYRE', 'Tyre'], ['sublet', 'SUBLET', 'Sublet'],
  ].map(([key, label, grid]) => {
    const suffix = key.charAt(0).toUpperCase() + key.slice(1);
    return Object.freeze({ key, label, grid, requireKey: 'pdcRequires' + suffix, completeKey: 'pdcComplete' + suffix });
  }));
  const ALL_FIELDS = DEFS.map(d => [d.requireKey, d.completeKey]).concat([['pdcRequiresPitInspection', 'pdcCompletePitInspection']]);
  const FIELD_BY_KEY = Object.freeze(Object.fromEntries(DEFS.map(d => [d.key, [d.requireKey, d.completeKey]]).concat([['pitinspection', ['pdcRequiresPitInspection', 'pdcCompletePitInspection']]])));
  // The board's pmbStageForPdcJob (PRODUCTION_FLOW_DEFS: no stage for Parts or Sublet) and PMB_STAGE_TO_JOB_KEY.
  const STAGE_FOR_JOB = Object.freeze({ bus4x4: 'BUS_4X4', tint: 'TINT', hoist: 'HOIST', fitting: 'FITTING', fabrication: 'FABRICATION', electrical: 'ELECTRICAL', tyre: 'TYRE' });
  const JOB_FOR_STAGE = Object.freeze({ BUS_4X4: 'bus4x4', TINT: 'tint', HOIST: 'hoist', FITTING: 'fitting', FABRICATION: 'fabrication', ELECTRICAL: 'electrical', TYRE: 'tyre', PIT_INSPECTION: 'pitInspection', SUBLET: 'sublet' });
  const BUS_STAGES = ['BUS_MECHANICAL', 'BUS_ACCESSORIES', 'BUS_ELECTRICAL', 'BUS_QA', 'BUS_PIT', 'BUS_4X4'];
  const JITA_AUTHORITY = 'validated-navision-import-v1';

  function canonicalWorkKey(value) { // pdc-email-vehicle-location-service.js canonicalWorkKey
    const key = String(value || '').trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    if (['pit', 'pitinspection', 'inspectionpit', 'pitinspect'].includes(key)) return 'pitinspection';
    if (['bus4x4', 'bus4wd', '4x4bus'].includes(key)) return 'bus4x4';
    if (['tyres', 'tire', 'tires'].includes(key)) return 'tyre';
    if (['part', 'partsrequired'].includes(key)) return 'parts';
    return key;
  }
  function normalizeStage(value) { // the board's normalizePmbStage for a staff-set PMB stage
    const canonical = eligibility?.canonicalWorkshopStage?.(value);
    if (canonical) return canonical;
    const c = String(value || '').trim().toUpperCase();
    if (!c) return '';
    if (/\bBUS[ _-]*4X4\b|\b4X4[ _-]*BUS\b|\b(?:DEPT|DEPARTMENT)[ _-]*138\b/.test(c)) return 'BUS_4X4';
    if (c.includes('TINT')) return 'TINT';
    if ((c.includes('EXPRESS') && c.includes('HOIST')) || c.includes('PITS HOIST') || c.includes('PIT HOIST')) return 'HOIST';
    if (c.includes('EXPRESS') && (c.includes('FITOUT') || c.includes('FIT OUT') || c.includes('FITTING') || c.includes('FITMENT'))) return 'FITTING';
    if (c.includes('HOIST') || c.includes('SUSPENSION') || c.includes('LIFT')) return 'HOIST';
    if (/FITTING|FITMENT|FITOUT|FIT OUT|BUILD|PDI|PRE DELIVERY|PRE-DELIVERY/.test(c)) return 'FITTING';
    if (/FAB|TRAY|BODY/.test(c)) return 'FABRICATION';
    if (/ELECTRICAL|AUTO ELEC|AUTO-ELEC|12V|UHF/.test(c)) return 'ELECTRICAL';
    if (/TYRE|TIRE|WHEEL/.test(c)) return 'TYRE';
    if (/PIT|INSPECTION/.test(c)) return 'PIT_INSPECTION';
    if (/SUBLET|SUB-LET|SUB LET|OUTSOURCE|EXTERNAL/.test(c)) return 'SUBLET';
    return '';
  }

  /** One server entry -> the board's vehicle fields (the same mapping as mapServerVehicle for these facts). */
  function toBoardVehicle(entry = {}) {
    const v = { id: String(entry.vehicle_id || ''), pmbStage: String(entry.pmb_stage || '').trim() };
    for (const [r, c] of ALL_FIELDS) { v[r] = false; v[c] = false; }
    const work = entry.work && typeof entry.work === 'object' ? entry.work : {};
    for (const [key, item] of Object.entries(work)) {
      const f = FIELD_BY_KEY[canonicalWorkKey(key)]; if (!f) continue;
      v[f[0]] = item?.required === true; v[f[1]] = item?.completed === true;
    }
    for (const code of Array.isArray(entry.qc_open_stage_codes) ? entry.qc_open_stage_codes : []) {
      const stage = String(code || '').toUpperCase();
      const f = FIELD_BY_KEY[BUS_STAGES.includes(stage) ? 'bus4x4' : canonicalWorkKey(stage)];
      if (f && stage !== 'JOB_CARD_NOTES') v[f[0]] = true;
    }
    const parts = entry.parts && typeof entry.parts === 'object' ? entry.parts : {};
    v.stock = entry.has_stock === true ? 'LINKED' : '';
    v.parts_update = {};
    if (typeof parts.parts_required === 'boolean') { v.pdcRequiresParts = parts.parts_required; v.parts_update = { parts_required: parts.parts_required }; }
    v.pdcCompleteParts = typeof parts.parts_received === 'boolean' ? parts.parts_received : work.parts?.completed === true;
    v.pdcPartsOrdered = parts.parts_ordered === true;
    v.pdcPartsStoppage = parts.parts_stoppage === true;
    v.pdcPartsStoppageReason = String(parts.parts_stoppage_reason || '');
    v.pdcBlocked = entry.pmb_stoppage === true;
    v.pdcBlockReason = v.pdcBlocked ? String(entry.pmb_stoppage_reason || '') : '';
    v.pdcPartsFlags = entry.parts_flags && typeof entry.parts_flags === 'object' ? entry.parts_flags : null;
    const jita = clean(entry.jita_number);
    if (jita) Object.assign(v, { navisionJitaIdentityVerified: true, navisionJitaNumberColumnPresent: true, navisionJitaNumberAuthority: JITA_AUTHORITY, navisionJitaNumber: jita, jitQty: jita });
    const active = Math.max(0, Math.floor(Number(entry.sublet_active_bookings) || 0)), returned = Math.max(0, Math.floor(Number(entry.sublet_returned_bookings) || 0));
    v.pdcSubletBookings = [...Array(active)].map((_, i) => ({ bookingId: 'a' + i, status: 'active', outDate: '' }))
      .concat([...Array(returned)].map((_, i) => ({ bookingId: 'r' + i, status: 'returned', outDate: '' })));
    if (active + returned) { v.pdcRequiresSublet = true; v.pdcCompleteSublet = active === 0; }
    v.salesWorkshopBookings = (Array.isArray(entry.bookings) ? entry.bookings : []).filter(b => b && !['completed', 'deleted', 'cancelled'].includes(String(b.status || '').toLowerCase()))
      .map(b => ({ stage: String(b.stage_code || ''), stage_code: String(b.stage_code || ''), status: String(b.status || ''), stoppageReason: String(b.stoppage_reason || '') }));
    return v;
  }

  // ---- The board's helpers for these facts (app.js; same names so the parity test reads cleanly) ----
  const required = (v, d) => {
    if (d.key === 'parts') {
      if (typeof v.parts_update?.parts_required === 'boolean') return v.parts_update.parts_required;
      return Boolean(clean(v.stock));
    }
    return v[d.requireKey] === true;
  };
  const complete = (v, d) => v[d.completeKey] === true;
  const partsComplete = v => complete(v, DEFS[0]) || v.pdcCompleteParts === true;
  const partsStoppage = v => !partsComplete(v) && (v.pdcPartsStoppage === true || Boolean(clean(v.pdcPartsStoppageReason))) && required(v, DEFS[0]);
  const blocked = v => v.pdcBlocked === true || Boolean(clean(v.pdcBlockReason));
  const blockReason = v => clean(v.pdcBlockReason) || 'Blocked';
  const jitaNumber = v => {
    if (v.navisionJitaNumberAuthority !== JITA_AUTHORITY || v.navisionJitaIdentityVerified !== true || v.navisionJitaNumberColumnPresent !== true) return '';
    const value = String(v.jitQty || v.navisionJitaNumber || '').trim();
    return /\d/.test(value) && !/^0+(?:\.0+)?$/.test(value) ? value : '';
  };
  const imported = v => { const p = v.pdcPartsFlags; return p && ['orange', 'red', 'green', 'grey', 'review'].includes(p.colour) ? p : null; };
  const importedTitle = v => {
    const p = imported(v); if (!p) return '';
    const when = p.last_successful_import_at ? new Date(p.last_successful_import_at).toLocaleString('en-AU', { timeZone: 'Australia/Perth' }) : 'Not recorded';
    return `${p.label}. Last successful import: ${when} (Perth). ${p.meaning || ''}`;
  };
  const completionTitle = (v, d) => [`${d.label} required`, complete(v, d) ? 'signed off' : 'not signed off yet'].join(' - ');
  const activeSubletBooking = v => (v.pdcSubletBookings || []).filter(b => b.status === 'active' && b.bookingId).length === 1;

  /** The Control Board strip for one vehicle (incomingWorkChecklistHtml without planner navigation or booking warning). */
  function stripHtml(v = {}) {
    const currentStage = normalizeStage(v.pmbStage);
    const bookings = Array.isArray(v.salesWorkshopBookings) ? v.salesWorkshopBookings : [];
    const stopped = new Map(bookings.filter(b => String(b.status).toLowerCase() === 'stoppage').map(b => [normalizeStage(b.stage), b]));
    return `<div class="incoming-work-checks pdc-station-strip" data-workshop-booking-required="false" aria-label="Required work stations">${DEFS.map(def => {
      const req = required(v, def), done = complete(v, def), stage = STAGE_FOR_JOB[def.key] || '';
      const stoppedBooking = stage ? stopped.get(stage) : null;
      const stageJobKey = JOB_FOR_STAGE[currentStage] || '';
      const isBlocked = def.key === 'parts' ? partsStoppage(v) : Boolean(stoppedBooking || (blocked(v) && stageJobKey === def.key));
      const ordered = def.key === 'parts' && req && !done && !isBlocked && v.pdcPartsOrdered === true;
      const subletBooked = def.key === 'sublet' && activeSubletBooking(v) && !done && !isBlocked;
      const vehicleStageStoppage = blocked(v) && stageJobKey === def.key;
      const projected = guardApi.projectWorkState({
        workKey: def.key, required: req, completed: done, bookings,
        partsOrdered: def.key === 'parts' && v.pdcPartsOrdered === true,
        partsStoppage: def.key === 'parts' && partsStoppage(v),
        stoppage: Boolean(isBlocked || vehicleStageStoppage),
        stoppageReason: stoppedBooking?.stoppageReason || (isBlocked ? blockReason(v) : '') || (vehicleStageStoppage ? blockReason(v) : ''),
        subletBookings: v.pdcSubletBookings || [],
      });
      const booked = projected.state === 'booked';
      // Same stage map as the board. Started is a booking status the board folds into "booked"; Sales keeps that
      // markup and adds is-started so the icon can use the planner's blue pulse. Not on a completed or STOPPAGE box.
      const startedHere = Boolean(stage) && !done && projected.state !== 'stoppage' && projected.state !== 'completed'
        && bookings.some(b => String(b.status || '').toLowerCase() === 'started' && normalizeStage(b.stage || b.stage_code) === stage);
      const classes = ['incoming-work-check', `pdc-station-${def.key}`];
      if (!req && !done) classes.push('is-not-required');
      if (req) classes.push('is-required');
      if (ordered || subletBooked) classes.push('is-ordered');
      if (booked) classes.push('is-booked');
      if (startedHere) classes.push('is-started');
      if (done) classes.push('is-complete');
      if (projected.state === 'stoppage') classes.push('is-blocked');
      if (stage && currentStage === stage) classes.push('is-current-stage');
      const state = projected.state === 'completed' ? 'complete' : projected.state === 'stoppage' ? 'STOPPAGE' : ordered ? 'ordered' : startedHere ? 'started' : projected.state;
      const marker = projected.marker;
      const title = stoppedBooking
        ? `${def.grid} STOPPAGE${stoppedBooking.stoppageReason ? `: ${stoppedBooking.stoppageReason}` : ''}`
        : ordered ? `${def.grid} ordered` : booked ? `${def.grid} ${startedHere ? 'started' : 'booked'}` : req || done ? completionTitle(v, def) : `${def.grid} not required`;
      if (def.key === 'parts') {
        const imp = imported(v), jita = jitaNumber(v);
        const jitaStatus = jita ? `JITA pre-order ${jita}` : 'No verified Navision JITA pre-order number';
        // r524 (F138): same rule as app.js. A verified JITA number paints the whole station green
        // only when there is no imported parts status, or that status is green. Orange, red,
        // review and grey keep their colour, with the JITA tick in the corner. JITA ETA is not read.
        if (jita && !partsStoppage(v) && (!imp || imp.colour === 'green')) {
          return `<span class="incoming-work-check pdc-station-parts parts-jita-split is-complete has-jita" role="img" title="${esc(`Parts Jita complete. Navision JITA number ${jita}.`)}" aria-label="${esc(`Parts Jita complete; ${jitaStatus}`)}"><span class="incoming-work-box parts-jita-parts-marker" aria-hidden="true">✓</span><span class="parts-jita-marker" aria-hidden="true">✓</span><span class="incoming-work-label">Parts / JITA</span></span>`;
        }
        if (imp) {
          const glyph = { green: '✓', orange: '!', red: '●', grey: '—', review: '?' }[imp.colour];
          return `<span class="incoming-work-check parts-jita-split imported-parts-${esc(imp.colour)} ${jita ? 'has-jita' : 'no-jita'}" role="img" title="${esc(importedTitle(v) + ' ' + jitaStatus)}" aria-label="${esc(imp.label + '; ' + jitaStatus)}"><span class="incoming-work-box parts-jita-parts-marker" aria-hidden="true">${glyph}</span><span class="parts-jita-marker" aria-hidden="true">${jita ? '✓' : '●'}</span><span class="incoming-work-label">Parts / JITA</span></span>`;
        }
        return `<span class="${classes.join(' ')} parts-jita-split ${jita ? 'has-jita' : 'no-jita'}" role="img" title="${esc(`Top left: ${title}. Bottom right: ${jitaStatus}`)}" aria-label="${esc(`Parts ${state}; ${jitaStatus}`)}">
        <span class="incoming-work-box parts-jita-parts-marker" aria-hidden="true">${marker}</span>
        <span class="parts-jita-marker" aria-hidden="true">${jita ? '✓' : '●'}</span>
        <span class="incoming-work-label">Parts / JITA</span>
      </span>`;
      }
      return `<span class="${classes.join(' ')}" title="${esc(title)}" aria-label="${esc(`${def.grid} ${state}`)}">
      <span class="incoming-work-box" aria-hidden="true">${marker}</span>
      <span class="incoming-work-label">${esc(def.grid)}</span>
    </span>`;
    }).join('')}</div>`;
  }

  // ---- pdc-sublet-po.js boxState + decorateStrip (same output; that file is not loaded on Sales) ----
  function boxState(entry, toRaise = 0) {
    const raise = Number(toRaise) > 0 ? Math.floor(Number(toRaise)) : 0;
    if ((!entry || !(Number(entry.total) > 0)) && !raise) return null;
    if (raise) {
      const poTotal = entry && Number(entry.total) > 0 ? Number(entry.total) : 0, poTicked = poTotal ? Number(entry.ticked) || 0 : 0;
      const title = `Sublet: PO to raise: ${raise} whole line sublet${raise === 1 ? ' has' : 's have'} no GP PO yet`
        + (poTotal ? `; ${poTicked} of ${poTotal} GP PO line${poTotal === 1 ? '' : 's'} ticked sublet done` : '');
      return { cls: 'is-ordered', marker: '!', count: 'PO to raise', title, raise };
    }
    const total = Number(entry.total) || 0, ticked = Number(entry.ticked) || 0, withPo = Number(entry.with_po) || 0;
    const count = `${ticked}/${total}`;
    if (entry.state === 'done') return { cls: 'is-complete', marker: '✓', count, title: `Sublet: all ${total} GP PO line${total === 1 ? '' : 's'} ticked sublet done` };
    if (entry.state === 'ordered') return { cls: 'is-ordered', marker: '!', count, title: `Sublet: ${withPo} line${withPo === 1 ? '' : 's'} with a GP PO, ${ticked} of ${total} ticked sublet done` };
    return null;
  }
  const BOX = /<(span|button)([^>]*\bclass="incoming-work-check pdc-station-sublet\b[^"]*")([^>]*)>((?:\s*<span\b[^>]*>[^<]*<\/span>)*\s*)<\/\1>/;
  function decorateStrip(html, entry, toRaise = 0) {
    const s = boxState(entry, toRaise);
    if (!s || typeof html !== 'string' || !BOX.test(html)) return html;
    return html.replace(BOX, (all, tag, classAttr, rest, inner) => {
      if (classAttr.includes('pdc-sublet-po-box')) return all;
      const classes = classAttr.match(/class="([^"]*)"/)[1].split(/\s+/);
      const isComplete = classes.includes('is-complete');
      let next = classes.concat('pdc-sublet-po-box');
      if (s.cls && !isComplete) {
        next = next.filter(c => !['is-required', 'is-ordered', 'is-booked', 'is-complete', 'is-not-required'].includes(c));
        if (s.cls === 'is-ordered') next.push('is-required');
        next.push(s.cls);
      }
      let body = inner;
      const marker = s.raise ? '<b class="pdc-sublet-po-raise">PO to raise</b>' : s.marker;
      if (s.raise && !isComplete) next.push('is-po-to-raise');
      if (marker && !isComplete) body = body.replace(/(<span class="incoming-work-box"[^>]*>)[\s\S]*?(<\/span>)/, `$1${marker}$2`);
      body = body.replace(/(<span class="incoming-work-label">[\s\S]*?)(<\/span>)/, `$1 <small class="pdc-sublet-po-count">${esc(s.count)}</small>$2`);
      const attrs = (classAttr.replace(/class="[^"]*"/, `class="${next.join(' ')}"`) + rest)
        .replace(/title="[^"]*"/, `title="${esc(s.title)}"`).replace(/aria-label="([^"]*)"/, (_, a) => `aria-label="${a}; ${esc(s.title)}"`);
      return `<${tag}${attrs}>${body}</${tag}>`;
    });
  }

  /** Read-only Sales markup for one server entry: the board strip (Sublet PO decorated), wrapped so it is compact and inert. */
  function entryHtml(entry) {
    if (!entry || !guardApi?.projectWorkState) return '';
    const strip = decorateStrip(stripHtml(toBoardVehicle(entry)), entry.sublet_po || null, Number(entry.sublet_without_po) || 0);
    return '<div class="sales-pmb-stations" role="group" aria-label="PMB stations (read only)">' + strip + '</div>';
  }
  /** Index a server answer: vehicle id -> strip HTML. Built once per answer. */
  function indexAnswer(data) {
    const map = new Map();
    if (!data || data.ok !== true || !Array.isArray(data.vehicles)) return map;
    for (const entry of data.vehicles) {
      const id = String(entry?.vehicle_id || '').toLowerCase();
      if (UUID.test(id)) map.set(id, entryHtml(entry));
    }
    return map;
  }

  function create(host) {
    let cache = new Map(), logged = false, request = 0;
    return {
      /** ONE batched read for every linked vehicle on the page. Never throws; on failure the icons are hidden. */
      async refresh(vehicleIds) {
        const ids = [...new Set((vehicleIds || []).map(id => String(id || '').toLowerCase()).filter(id => UUID.test(id)))].slice(0, MAX_IDS);
        const mine = ++request;
        if (!ids.length || !host.PDC_SUPABASE?.rpc) { cache = new Map(); return 0; }
        try {
          const { data, error } = await host.PDC_SUPABASE.rpc(RPC, { p_vehicle_ids: ids });
          if (mine !== request) return cache.size;
          if (error || !data || data.ok !== true) throw error || new Error('PMB station read failed');
          cache = indexAnswer(data);
        } catch (error) {
          if (mine !== request) return cache.size;
          cache = new Map();
          if (!logged) { logged = true; host.console?.warn?.('Sales PMB station icons unavailable:', error?.message || error); }
        }
        return cache.size;
      },
      /** Cached strip for a Sales row ('' when unlinked or not loaded). No work happens here. */
      html(row) { return row?.canonical_vehicle_id ? cache.get(String(row.canonical_vehicle_id).toLowerCase()) || '' : ''; },
      clear() { cache = new Map(); request++; },
      size: () => cache.size,
    };
  }

  const api = { RPC, MAX_IDS, DEFS, toBoardVehicle, stripHtml, decorateStrip, boxState, entryHtml, indexAnswer, create };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root.document) root.BROOME_SALES_PMB_STATIONS = Object.assign(create(root), { api });
})(typeof window !== 'undefined' ? window : globalThis);
