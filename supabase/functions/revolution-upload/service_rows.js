/**
 * r728: the website prepares the 'PMG PD Service as a Whole w/Sublet' rows itself (Kajel is switched off).
 * Port of tools/import-rules/revolution_service_whole.py (r479 / r569), revolution_service_wsublet.py (r442 / r444 /
 * r468 / r509), scripts/pmb_work_category_rules.py (routing and Craig's hour defaults, plus the reconstructed
 * craig_work_categories_20260917_tint rules), pmb_workshop_standards.py and pmb_arb_estimates.py.
 *
 * Pure functions. No network, no database, no model. Runs in Deno and in node.
 *
 * Hours: a line Kajel already decided (priorDecisions, keyed by department + normalised description) keeps that
 * decision verbatim. Any other line goes through the ported rules. A line that still needs an ARB review and has no
 * deterministic one (catalogue estimate, workshop standard, Craig default, explicit description time) is NOT sent:
 * it is returned in needsHours. Nothing here invents research.
 *
 * Provenance: raw_row.source_kind stays 'revolution_automated_service_workbook' (the file is that workbook).
 * The delivery channel is raw_row.delivery = 'website_admin_upload_728' with raw_row.upload. No email fields.
 */
import {
  ContractError, norm, unwrapHeader, headerNames, checkServiceHeaders, checkWholeParameters,
  BASE_HEADERS, SUBLET_HEADERS, SERVICE_WHOLE,
} from './parse.js';

export { ContractError };

export const TITLE = SERVICE_WHOLE;
export const SNAPSHOT_SCOPE = 'full_open_ro_snapshot_r479';
export const IDENTITY_RULE = 'r479_exact_board_stock_or_job_card';
export const BOARD_BASIS = 'new_board_vehicle';
export const COLLAPSE_RULE = 'r442_one_row_per_dept_ro_line';
export const CREATE_ADVISOR_RULE = 'r509_import_rows_with_create_advisor';
export const ROUTING_VERSION = 'craig_work_categories_20260917_tint';
export const SOURCE_KIND = 'revolution_automated_service_workbook';
export const DELIVERY = 'website_admin_upload_728';
export const LINE_FIELDS = ['department', 'repair_order_number', 'original_line_number', 'stock_number', 'file_stock', 'file_rego',
  'sub_status', 'identity_status'];
const LIVE_STATES = ['active', 'rft'];
const QC_MIN_LINES = 1000;
const QC_MIN_ROS = 100;

// ---- reading (r479 title / parameters / header unwrap, then the w/Sublet reader) --------------------------------------
function cellAt(row, index) {
  if (!row || index < 0 || index >= row.length) return null;
  const value = row[index];
  return value === undefined ? null : value;
}

const isNumber = (v) => typeof v === 'number' && Number.isFinite(v);

/** Same as revolution_service_wsublet.classify (r442). */
export function classify(raw) {
  const ro = norm(raw['R/O #']);
  const line = raw['Line #'];
  const dept = norm(raw.Dept);
  if (!ro && (line == null || line === '')) return 'footer';
  if (!/^J(138|139)[0-9]+$/.test(ro) || !['138', '139'].includes(dept) || !ro.startsWith(`J${dept}`)) {
    if (!['138', '139'].includes(dept) && ro) return 'excluded_department';
    throw new ContractError(`row: R/O # ${JSON.stringify(ro)} / Dept ${JSON.stringify(raw.Dept)} is not a J138/J139 service line`);
  }
  if (!isNumber(line) || Math.trunc(line) !== line || line <= 0) {
    throw new ContractError(`row: Line # ${JSON.stringify(line)} is not a positive whole number`);
  }
  const hours = raw['Estimated labour hours'];
  if (hours != null && (!isNumber(hours) || hours < 0)) {
    throw new ContractError(`row: Estimated labour hours ${JSON.stringify(hours)} is not a non-negative number`);
  }
  return 'data';
}

function classifyTyped(typeValue, raw, rn) {
  const t = typeof typeValue === 'string' ? typeValue.trim() : typeValue;
  const where = rn != null ? `row ${rn}: ` : 'row: ';
  if (t !== 'D' && t !== 'T1') throw new ContractError(`${where}Type ${JSON.stringify(typeValue)} is not D (data) or T1 (footer); only D and T1 are accepted`);
  const kind = classify(raw);
  if (t === 'T1' && kind !== 'footer') throw new ContractError(`${where}Type T1 (footer) but the row has an R/O # or Line #`);
  if (t === 'D' && kind === 'footer') throw new ContractError(`${where}Type D (data) but the row has no R/O # and no Line #`);
  return kind;
}

/** revolution_service_whole.read_values: rows of the worksheet -> {headers, data, footer, excluded, params, createAdvisor}. */
export function readWhole(grid) {
  const values = grid?.rows || [];
  if (!values.length || norm(values[0]?.[0]) !== TITLE) {
    throw new ContractError(`title: expected ${JSON.stringify(TITLE)}, got ${JSON.stringify(values[0]?.[0] ?? null)}`);
  }
  if (values.length < 4) throw new ContractError('worksheet: no header row');
  const params = norm(values[1]?.[0]);
  checkWholeParameters(params);
  if (!params.includes('Company = "01"') || !params.includes('Division = "1"')) {
    throw new ContractError('parameters: Company 01 / Division 1 required');
  }
  const rawHeaders = (values[3] || []).map(unwrapHeader);
  const names = headerNames(rawHeaders);
  const typed = names.length > 0 && names[0] === 'Type';
  const advised = names.length > 0 && names[names.length - 1] === 'Create Advisor';
  const headers = checkServiceHeaders(rawHeaders);
  const data = [];
  const footer = [];
  const excluded = [];
  const blankAdvisor = [];
  for (let index = 4; index < values.length; index += 1) {
    const rn = index + 1;
    let cells = values[index] || [];
    if (cells.every((x) => x == null || norm(x) === '')) continue;
    let t = null;
    if (typed) { t = cells[0]; cells = cells.slice(1); }
    const advisor = advised && cells.length > headers.length ? cellAt(cells, headers.length) : null;
    const raw = {};
    headers.forEach((h, i) => { raw[h] = i < cells.length ? cellAt(cells, i) : null; });
    // openpyxl gives None for an empty cell; the HTML / OOXML readers can give ''.
    for (const h of headers) if (raw[h] === '') raw[h] = null;
    const kind = typed ? classifyTyped(t, raw, rn) : classify(raw);
    if (advised && kind === 'data' && norm(advisor) === '') { blankAdvisor.push(rn); continue; }
    (kind === 'data' ? data : kind === 'footer' ? footer : excluded).push([rn, raw]);
  }
  if (footer.length > 1) throw new ContractError('more than one footer row');
  return {
    headers, data, footer, excluded, params, typed,
    createAdvisor: {
      rule: CREATE_ADVISOR_RULE,
      column: advised ? 'trailing_create_advisor_dropped_r509' : 'absent',
      blank_data_rows: blankAdvisor.length,
      blank_data_row_numbers: blankAdvisor,
      kept_data_rows: data.length,
      closes_board_cards: false,
    },
  };
}

const wsText = (v) => norm(v).replace(/\s+/g, ' ');
const sameValue = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** revolution_service_wsublet.collapse: one line per Dept + R/O # + Line #, first row kept, hours never summed. */
export function collapse(rows) {
  const groups = new Map();
  const order = [];
  for (const [rn, raw] of rows) {
    const key = `${norm(raw.Dept)}|${norm(raw['R/O #']).toUpperCase()}|${Math.trunc(raw['Line #'])}`;
    if (!groups.has(key)) { groups.set(key, []); order.push(key); }
    groups.get(key).push([rn, raw]);
  }
  const lines = [];
  const conflicts = [];
  let repeated = 0;
  for (const key of order) {
    const g = groups.get(key);
    const first = g[0][1];
    const base = {};
    for (const k of BASE_HEADERS) if (k in first) base[k] = first[k];
    const differing = {};
    for (const k of BASE_HEADERS) {
      const vals = [];
      for (const [, r] of g) {
        let v = r[k];
        if (typeof v === 'string') v = wsText(v);
        if (!vals.some((x) => sameValue(x, v))) vals.push(v === undefined ? null : v);
      }
      if (vals.length > 1) differing[k] = vals;
    }
    const pos = [];
    const cols = [];
    const descs = new Map();
    for (const [rn, r] of g) {
      const po = norm(r['PO #']).replace(/\s+/g, '').toUpperCase();
      const entry = {};
      for (const k of SUBLET_HEADERS) if (k in r) entry[k] = r[k];
      entry.source_row_number = rn;
      cols.push(entry);
      if (po && !pos.includes(po)) pos.push(po);
      const d = norm(r['Description of sublet']);
      if (po && d) {
        if (!descs.has(po)) descs.set(po, []);
        if (!descs.get(po).includes(d)) descs.get(po).push(d);
      }
    }
    if (g.length > 1) repeated += 1;
    const c = { rule: COLLAPSE_RULE, source_rows: g.length, hours_summed: false, conflict: Object.keys(differing).length > 0 };
    const [dept, ro, line] = key.split('|');
    if (c.conflict) {
      c.kept = 'first_row_in_source_order';
      c.differing_values = differing;
      conflicts.push({ dept, ro, line: Number(line), fields: Object.keys(differing).sort() });
    }
    lines.push({
      key: [dept, ro, Number(line)], raw: base, source_row_numbers: g.map(([rn]) => rn), sublet_pos: pos,
      sublet_po_descriptions: Object.fromEntries([...descs].map(([po, v]) => [po, v.join('^').slice(0, 4000)])),
      sublet_columns: cols, collapse: c,
    });
  }
  const round2 = (n) => Math.round(n * 100) / 100;
  const summary = {
    source_rows: rows.length, lines: lines.length, lines_with_repeats: repeated, rows_collapsed: rows.length - lines.length, conflicts,
    distinct_pos: new Set(lines.flatMap((l) => l.sublet_pos)).size,
    hours_first_row_per_line: round2(lines.reduce((s, l) => s + Number(l.raw['Estimated labour hours'] || 0), 0)),
    hours_naive_all_rows: round2(rows.reduce((s, [, r]) => s + Number(r['Estimated labour hours'] || 0), 0)),
  };
  return { lines, summary };
}

// ---- board identity (r479 / r569) ----------------------------------------------------------------------------------
const key = (v) => norm(v).toUpperCase();

export function boardIndex(board) {
  const byStock = new Map(); const byJc = new Map(); const byJob = new Map(); const vehicles = new Map();
  const push = (map, k, v) => { if (!map.has(k)) map.set(k, []); map.get(k).push(v); };
  for (const v of board?.vehicles || []) {
    vehicles.set(String(v.id), v);
    if (key(v.stock)) push(byStock, key(v.stock), v);
    if (key(v.jc)) push(byJc, key(v.jc), v);
  }
  for (const j of board?.jobs || []) {
    const v = vehicles.get(String(j.vehicle_id));
    if (v !== undefined && key(j.ro)) {
      const list = byJob.get(key(j.ro)) || [];
      if (!list.includes(v)) list.push(v);
      byJob.set(key(j.ro), list);
    }
  }
  const holds = new Set((board?.holds || []).map(key).filter(Boolean));
  const restores = new Set((board?.restores || []).map(key).filter(Boolean));
  return { stock: byStock, jc: byJc, job: byJob, vehicles, holds, restores };
}

const live = (v) => !v.deleted && LIVE_STATES.includes(v.ls);
function unique(cands) {
  const out = [];
  for (const v of cands) if (out.every((x) => String(x.id) !== String(v.id))) out.push(v);
  return out;
}
function closed(extra = {}) {
  return { board_action: null, send: false, board_basis: null, board_stock: null, rego_fallback: false, skip_reasons: [], ...extra };
}

/** revolution_service_whole.resolve_ro */
export function resolveRo(ro, fileStock, fileRego, idx) {
  const st = key(fileStock); const rg = key(fileRego); const r = key(ro);
  const out = { rule: IDENTITY_RULE, file_stock: norm(fileStock) || null, file_rego: norm(fileRego) || null };
  const tried = st
    ? [['stock_column', idx.stock.get(st) || []]]
    : [['rego_column_exact_board_stock', rg ? (idx.stock.get(rg) || []) : []],
       ['job_card_exact', idx.jc.get(r) || []],
       ['job_card_service_job', idx.job.get(r) || []]];
  const all = tried.flatMap(([, c]) => c);
  const liveOnes = unique(all.filter(live));
  if (liveOnes.length === 1) {
    const v = liveOnes[0];
    const basis = tried.find(([, c]) => c.some((x) => String(x.id) === String(v.id)))[0];
    return Object.assign(out, { status: 'linked', basis, stock: norm(v.stock), vehicle_id: String(v.id) },
      closed({ board_action: 'existing_row', send: true }));
  }
  if (liveOnes.length > 1) {
    return Object.assign(out, { status: 'ambiguous', basis: null, stock: null, vehicle_id: null,
      candidates: liveOnes.map((v) => norm(v.stock)).sort() }, closed());
  }
  const other = unique(all);
  if (other.length) {
    const states = [...new Set(other.map((v) => (v.deleted ? 'deleted' : String(v.ls))))].sort();
    return Object.assign(out, { status: 'vehicle_not_live', basis: null, stock: null, vehicle_id: null, board_states: states }, closed());
  }
  const identStock = st ? norm(fileStock) : (rg ? norm(fileRego) : null);
  const regoFallback = Boolean(identStock) && !st;
  const skip = [];
  if (identStock && idx.holds.has(key(identStock))) skip.push('owner_hold');
  if (identStock && idx.restores.has(key(identStock))) skip.push('pending_restore');
  Object.assign(out, { status: 'no_board_vehicle', basis: null, stock: null, vehicle_id: null,
    reason: st ? 'stock_not_on_board' : (rg ? 'rego_not_a_board_stock_and_no_job_card' : 'no_stock_no_rego_no_job_card') });
  if (!identStock) return Object.assign(out, closed());
  if (skip.includes('owner_hold')) return Object.assign(out, closed({ board_action: 'skip_owner_hold', board_stock: identStock, rego_fallback: regoFallback, skip_reasons: skip }));
  if (skip.includes('pending_restore')) return Object.assign(out, closed({ board_action: 'skip_pending_restore', board_stock: identStock, rego_fallback: regoFallback, skip_reasons: skip }));
  return Object.assign(out, closed({ board_action: 'create_board', send: true, board_basis: BOARD_BASIS, board_stock: identStock, rego_fallback: regoFallback }));
}

export const subStatus = (raw) => norm(raw['Sub Status']) || null;
const roKey = (raw) => `${norm(raw.Dept)}|${norm(raw['R/O #']).toUpperCase()}`;

/** revolution_service_whole.resolve_lines: Map 'dept|R/O' -> identity. */
export function resolveLines(lines, idx) {
  const seen = new Map(); const out = new Map(); const groups = new Map();
  for (const L of lines) {
    const raw = L.raw; const k = roKey(raw);
    if (!seen.has(k)) seen.set(k, new Set());
    seen.get(k).add(`${key(raw['Stock #'])}\u0000${key(raw['Rego #'])}`);
    if (!out.has(k)) out.set(k, resolveRo(k.split('|')[1], raw['Stock #'], raw['Rego #'], idx));
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(subStatus(raw));
  }
  for (const [k, ids] of seen) {
    if (ids.size > 1) out.set(k, { ...out.get(k), status: 'ambiguous', basis: null, stock: null, vehicle_id: null,
      reason: 'stock_or_rego_differs_between_lines', ...closed() });
  }
  for (const [k, subs] of groups) {
    const ident = out.get(k);
    if (ident.status !== 'no_board_vehicle' || !subs.length || !subs.every((s) => s === '99')) continue;
    const reasons = [...(ident.skip_reasons || [])];
    if (!reasons.includes('status_99')) reasons.push('status_99');
    if (ident.board_stock) out.set(k, { ...ident, board_action: 'skip_status_99', send: false, board_basis: null, skip_reasons: reasons });
    else out.set(k, { ...ident, send: false, board_basis: null, skip_reasons: reasons });
  }
  return out;
}

export function previewLineAllowed(raw, ident) {
  if (!ident || !ident.send) return false;
  if (ident.board_basis === BOARD_BASIS && subStatus(raw) === '99') return false;
  return true;
}

export function identityR479(ident) {
  if (!ident || !ident.send) return null;
  if (ident.status === 'linked' && ident.basis) return { rule: IDENTITY_RULE, basis: ident.basis };
  if (ident.board_basis === BOARD_BASIS) {
    const body = { rule: IDENTITY_RULE, basis: BOARD_BASIS };
    if (ident.rego_fallback) body.rego_fallback = true;
    return body;
  }
  return null;
}

export function previewStockNumber(ident, raw) {
  if (ident && ident.board_basis === BOARD_BASIS) return ident.board_stock;
  if (ident && ident.stock) return ident.stock;
  return norm(raw['Stock #']) || null;
}

/** revolution_service_whole.file_qc_guard */
export function fileQcGuard(lineCount, roCount, complete, previousLines, filename, scope) {
  void filename;
  const lines = lineCount || 0; const ros = roCount || 0;
  if (!complete) return { ok: false, reason: 'partial_file' };
  if (lines < 1 || ros < 1) return { ok: false, reason: 'empty_file' };
  if (scope !== SNAPSHOT_SCOPE) return { ok: false, reason: 'not_full_snapshot' };
  if (lines < QC_MIN_LINES || ros < QC_MIN_ROS) return { ok: false, reason: 'below_minimum_size' };
  if (previousLines == null) return { ok: false, reason: 'no_previous_complete_snapshot' };
  if (lines * 2 < previousLines) return { ok: false, reason: 'partial_vs_previous' };
  return { ok: true, reason: 'complete_file' };
}

/** revolution_service_whole.snapshot_payload (header without the email-only gmail_message_id). */
export function snapshotPayload(sha256, snapshotAt, lines, identities) {
  if (!/^[0-9a-f]{64}$/.test(sha256 || '')) throw new ContractError('snapshot: sha256 must be 64 lower-case hex');
  const rows = lines.map((L) => {
    const raw = L.raw; const k = roKey(raw); const ident = identities.get(k);
    const [dept, ro] = k.split('|');
    return [dept, ro, Math.trunc(raw['Line #']), ident.stock ?? null, ident.file_stock ?? null, ident.file_rego ?? null, subStatus(raw), ident.status];
  });
  return {
    header: { snapshot_sha256: sha256, report_title: TITLE, snapshot_scope: SNAPSHOT_SCOPE, source_snapshot_at: snapshotAt,
      line_count: rows.length, ro_count: new Set(rows.map((r) => `${r[0]}|${r[1]}`)).size },
    lines: rows,
  };
}

// ---- routing and hours (pmb_work_category_rules) --------------------------------------------------------------------
const upper = (d) => String(d || '').toUpperCase().replace(/\s+/g, ' ').trim();

/**
 * category(): the repo rules (craig_work_categories_20260912) in their order, with the 20260917_tint rules inserted
 * (RECONSTRUCTED: the 20260917_tint Python is not in the repo; rule names come from Kajel's rows, patterns are ours).
 */
export function category(description) {
  const s = upper(description);
  const has = (re) => re.test(s);
  const roof = has(/ROOF[ -]?RACK|RHINO[ -]?RACK/);
  const whip = has(/WHIP[ -]?FLAGS?/);
  if (has(/\b(?:FILL\s+(?:WITH\s+)?FUEL|FULL\s+TANK\s+(?:OF\s+)?FUEL|REFUEL(?:LING|ING)?|PIT\s*(?:AND|&)\s*WEIGH)\b/) || has(/BATTERY\s*100\s*%/)) {
    return ['FITTING', 'preparation_fitting'];
  }
  // reconstructed 20260917_tint
  if (has(/LONG[ -]?RANGE\b.*\bTANK/)) return ['HOIST', 'accessory_long_range_tank_20260914'];
  if (has(/\bTINT(?:ING|S)?\b/) && !has(/BONNET[ -]*PROTECT|WEATHER[ -]*(?:SHIELD|SHEILD)/)) return ['TINT', 'accessory_window_tint_20260914'];
  if (has(/BONNET[ -]*PROTECT|WEATHER[ -]*(?:SHIELD|SHEILD)/)) return ['FITTING', 'bonnet_protectors_weather_shields_fitting'];
  // repo
  if (has(/MINE[ -]?BARS?/) || (whip && (roof || has(/LIGHT|LED|ILLUMINAT/)))) return ['ELECTRICAL', 'mine_bar_or_lit_roof_whip'];
  // reconstructed 20260917_tint
  if (has(/SPOT[ -]?LIGHTS?|DRIVING[ -]?LIGHTS?|LIGHT[ -]?BARS?\b|HEAD[ -]?(?:LAMPS?|LIGHTS?)\b.*\bAUTO|\bAUTO[ -]?ON\b.*\bHEAD[ -]?(?:LAMPS?|LIGHTS?)\b/)) {
    return ['ELECTRICAL', 'headlights_on_kits_and_spotlights_electrical'];
  }
  // repo
  if (has(/SUBCORE?\b.*(?:SIGN|LOGO|RIBBON)/)) return ['SUBLET', 'subcore_signs'];
  if (has(/\bPTE\b.*TRAY/)) return ['SUBLET', 'pte_tray'];
  if (has(/HEAVY[ -]?DUTY.*RUBBER.*(?:FLOOR[ -]?)?MATS?/) || has(/\b(?:PROTECTED|PROTECTA)\b.*MATS?/) || has(/VINYL[ -]?FLOOR/)) return ['SUBLET', 'floor_coverings'];
  if ((has(/\b(?:HI[ -]?DRIVE|HIGH[ -]?DRIVE|BOSTON|MTE)\b.*(?:CANOP|BULL|MOTOR[ -]?BOD|BODIES|BODY)/) || has(/\bCANOP(?:Y|IES)\b|BODY[ -]?BUILDER/))
    && !has(/SOCKET|OUTLET|ANDERSON|COMPRESSOR|BEACON|DECAL|FRIDGE[ -]?SLIDE|AIR[ -]?VENT|SECURITY[ -]?GRILL|ROOF[ -]?RACK|RHINO[ -]?RACK|CABINET|LIGHT/)) {
    return ['SUBLET', 'canopy_body_builder'];
  }
  if (has(/RYCO.*CATCH[ -]?CAN.*KIT/)) return ['FITTING', 'ryco_catch_can_kit'];
  // reconstructed 20260917_tint: an additional spare is a tyre job (before the repo additional-rim fabrication rule)
  if (has(/\b(?:2ND|SECOND|EXTRA|ADDITIONAL)\s+SPARE\b/) && !has(/HOLDER|MOUNT|CARRIER/)) return ['TYRE', 'additional_spares_tyre'];
  // repo
  if (has(/ADDITIONAL.*(?:GENUINE|ALLOY).*RIM/)) return ['FABRICATION', 'additional_genuine_alloy_rim'];
  if (has(/SPARE[ -]?(?:TYRE|WHEEL).*(?:HOLDER|MOUNT).*PMB.*CAB[ -]?RACK/)) return ['FABRICATION', 'pmb_cab_rack_tyre_holder'];
  if (has(/CERTIFIED.*MESH.*CAB[ -]?RACK.*BARRIER/) || has(/ADDITIONAL.*ALLOY.*RIMS?/)
    || (has(/\b(?:800\s*MM\s*)?TOOL[ -]?BOX(?:ES)?\b/) && !has(/CENTRAL[ -]?LOCK|SOCKET|OUTLET|WIRING|LIGHT/))
    || has(/TIE[ -]?DOWN.*(?:POINT|ANCHOR).*FLOOR/) || has(/SPARE[ -]?WHEEL.*(?:MOUNT|HOLDER).*\b(?:TRAY|TOOL[ -]?BOX)/)) {
    return ['FABRICATION', 'fabricated_accessory'];
  }
  // reconstructed 20260917_tint
  if (has(/TRIANGLES?\b.*\bHOLDERS?\b|TRIANGLE[ -]?HOLDER/)) return ['FABRICATION', 'mounted_triangle_holder_fabrication'];
  if (has(/WHEEL[ -]?CHOCKS?/)) return ['FITTING', 'wheel_chocks_fitting'];
  if (has(/SEAT[ -]?COVERS?/)) return ['FITTING', 'accessory_seat_covers_fitting_20260914'];
  if (has(/\bGVM\b|SUSPENSION|\bAIR[ -]?BAGS?\b|LIFT[ -]?KIT|\bOME\b|LEAF[ -]?SPRINGS?|COIL[ -]?SPRINGS?|SHOCK[ -]?ABSORBERS?/)) {
    return ['HOIST', 'suspension_department_139_hoist'];
  }
  if (has(/\bTYRES?\b|\bTIRES?\b/) && !has(/HOLDER|MOUNT|CARRIER|COVER|PRESSURE|TPMS/)) return ['TYRE', 'accessory_tyres_20260914'];
  // repo
  if (has(/BUSHRANGER.*COVERT.*WINCH/) || roof || has(/FIRST[ -]?AID.*KIT/) || has(/ANTI[ -]?THEFT.*(?:NUMBER|NO[ .-]?)[ -]?PLATE.*SCREW/) || has(/\bEV[ -]?TAGS?\b/)) {
    return ['FITTING', 'specific_minor_or_roof_fitment'];
  }
  if (has(/\bPMB[ -]*0*02\b|\bPMB[ -]+ITEMS?\b|^PMB(?:[A-Z]?\d+)?\b/)) return ['FABRICATION', 'pmb_product'];
  // reconstructed 20260917_tint
  if (has(/ANDERSON|DUAL[ -]?BATTER|BRAKE[ -]?CONTROLLER|REVERSE[ -]?CAMERA|\bUHF\b|INVERTER|\bUSB\b|BEACON|REDARC/)) return ['ELECTRICAL', 'accessory_electrical_20260914'];
  if (has(/\bARB\b/)) return ['FITTING', 'arb_general_fitment_20260914'];
  return [null, null];
}

function hoursValue(value) {
  if (value == null || value === '') return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) throw new ContractError('Invalid hours');
  return n;
}

/** Times written in the description ('1.5 HRS', '30 MINS'), as a set of hours. */
export function descriptionTimes(description) {
  const out = new Set();
  const re = /\b(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?)\b/gi;
  let m;
  while ((m = re.exec(String(description || '')))) out.add(Number(m[1]) / (m[2].toLowerCase().startsWith('min') ? 60 : 1));
  return out;
}

/** propose() with the department 138 owner rule (all Dept 138 work is Bus 4x4, tint excepted). */
export function propose(description, sourceHours = null, fallbackStation = 'REVIEW', department = null) {
  const [matched, rule] = category(description);
  const dept138 = String(department) === '138';
  let station; let routingRule; let routingProvenance;
  if (dept138) {
    const tint = matched === 'TINT';
    station = tint ? 'TINT' : 'BUS_4X4';
    routingRule = tint ? 'department_138_tint_exception' : 'department_138_exclusive_bus4x4';
    routingProvenance = 'explicit_owner_rule';
  } else {
    const suspensionElsewhere = rule === 'suspension_department_139_hoist' && String(department) !== '139';
    station = (!suspensionElsewhere && matched) || fallbackStation;
    routingRule = suspensionElsewhere ? null : rule;
    routingProvenance = suspensionElsewhere || !matched ? 'existing_default' : 'explicit_owner_rule';
  }
  const original = hoursValue(sourceHours);
  let effective = original;
  let provenance = 'source_estimate';
  let needsReview = false;
  let defaultHours = null; let defaultProvenance = null;
  const d = upper(description);
  if (station === 'ELECTRICAL') { defaultHours = 1.5; defaultProvenance = 'craig_electrical_default_1_5_hours'; }
  else if (station === 'FITTING' && /RYCO.*CATCH[ -]?CAN.*KIT/.test(d)) { defaultHours = 1.5; defaultProvenance = 'craig_ryco_catch_can_default_1_5_hours'; }
  else if (station === 'FABRICATION') {
    if (/ADDITIONAL.*(?:GENUINE|ALLOY).*RIM/.test(d)) { defaultHours = 0.5; defaultProvenance = 'craig_additional_rim_default_0_5_hours'; }
    else if (/TIE[ -]?DOWN.*POINT.*FLOOR/.test(d)) {
      const q = / X\s*(\d+)\b/.exec(d);
      defaultHours = Number(q ? q[1] : 1); defaultProvenance = 'craig_floor_tie_down_1_hour_each';
    } else if (/PMB.*STEEL.*TRAY|PMB.*TRAY.*STEEL/.test(d)) { defaultHours = 2; defaultProvenance = 'craig_steel_tray_default_2_hours'; }
    else if (/MESH.*CAB[ -]?RACK.*BARRIER/.test(d)) { defaultHours = 0.5; defaultProvenance = 'craig_mesh_cab_rack_default_0_5_hours'; }
    else if (/SPARE[ -]?(?:TYRE|WHEEL).*(?:HOLDER|MOUNT).*PMB.*CAB[ -]?RACK/.test(d)) { defaultHours = 0.5; defaultProvenance = 'craig_tyre_holder_default_0_5_hours'; }
  }
  // reconstructed 20260917_tint defaults
  else if (station === 'TINT') { defaultHours = 1; defaultProvenance = 'craig_tint_default_1_hour'; }
  else if (station === 'HOIST' && routingRule === 'suspension_department_139_hoist') { defaultHours = 5; defaultProvenance = 'craig_suspension_department_139_default_5_hours'; }
  else if (station === 'TYRE' && rule === 'accessory_tyres_20260914') { defaultHours = 1; defaultProvenance = 'craig_tyres_default_1_hour'; }
  if (rule === 'additional_spares_tyre' && (station === 'TYRE' || station === 'BUS_4X4')) {
    defaultHours = 0.17; defaultProvenance = 'craig_additional_spare_ten_minutes';
  }
  if (defaultHours != null && (original == null || original === 0)) {
    const times = descriptionTimes(description);
    if (times.size > 1) { effective = null; provenance = 'conflicting_description_times'; needsReview = true; }
    else if (times.size === 1) { effective = [...times][0]; provenance = 'explicit_description_time'; }
    else { effective = defaultHours; provenance = defaultProvenance; }
  }
  return {
    proposed_station: station,
    source_estimated_hours: sourceHours,
    effective_estimated_hours: effective,
    hours_provenance: provenance,
    routing_rule: routingRule,
    routing_rule_version: ROUTING_VERSION,
    routing_provenance: routingProvenance,
    needs_hours_review: needsReview || (station !== 'SUBLET' && (effective == null || effective <= 0)),
  };
}

// ---- reviewed workshop standards and the ARB checkpoint (pmb_workshop_standards / pmb_arb_estimates) ----------------
export const GUIDE_VERSION = 'DRT20260901.1';
export const GUIDE_SHA256 = '4e1a8c9cd5f317d1a9b28fbf0c9448f1b33a33651e4dff8507e9947a157c46c6';
export const CATALOGUES = {
  [GUIDE_VERSION]: GUIDE_SHA256,
  'RT20260901.1': '6ceaecee5b8a8e4fb23127de0941b06ca710b09a3b76dfb4f1e6f2c39af78163',
};
const UNABLE_REASONS = new Set(['missing_vehicle_context', 'ambiguous_kit', 'incompatible_scope', 'unsupported_product', 'no_published_labour', 'conditional_or_bundled']);
const CONTEXT_SOURCES = new Set(['unique_current_exact_stock_navision', 'explicit_source_vehicle_context']);
const normalize = (v) => String(v ?? '').replace(/\s+/g, ' ').trim().toUpperCase();
export const descriptionKey = (department, description) => `${norm(department)}|${normalize(description)}`;

/** pmb_workshop_standards.reviewed_standard. registry: {version, rules:[...]} (none is installed in the repo). */
export function reviewedStandard(row, registry) {
  if (norm(row.department) !== '138') return null;
  if (row.staff_hours != null || row.manual_assignment_locked === true) return null;
  const proof = String(row.hours_provenance || '');
  if (proof.startsWith('craig_') || ['staff_estimate', 'explicit_description_time', 'manual_operator', 'conflicting_description_times'].includes(proof)) return null;
  const source = row.source_estimated_hours;
  if (source != null && source !== '') {
    const n = Number(source);
    if (!Number.isFinite(n) || n !== 0) return null;
  }
  if (descriptionTimes(row.operation_description).size) return null;
  const ctx = row.vehicle_context || row.raw_row?.vehicle_context || {};
  if (!CONTEXT_SOURCES.has(ctx.source)) return null;
  const model = normalize(ctx.vehicle || ctx.model);
  if (!model || !registry) return null;
  const matched = (registry.rules || []).filter((r) => r.department === '138' && normalize(r.model) === model
    && normalize(r.description) === normalize(row.operation_description) && r.stage === row.proposed_station);
  if (matched.length !== 1) return null;
  const rule = matched[0];
  if (!rule.evidence || !rule.id) return null;
  const hours = Number(rule.hours);
  if (!(hours >= 0.1 && hours <= 999) || Math.abs(hours * 100 - Math.round(hours * 100)) > 1e-9) return null;
  return { standard_id: rule.id, registry_version: registry.version, model: rule.model, description: rule.description, department: '138',
    stage: rule.stage, hours, source: rule.source, evidence: rule.evidence };
}

export function needsLookup(r) {
  const source = r.source_estimated_hours;
  if (source != null && source !== '' && Number(source) > 0) return false;
  if (r.proposed_station === 'SUBLET' || r.staff_hours != null) return false;
  const proof = r.hours_provenance || '';
  if (proof.startsWith('craig_') && Number(r.effective_estimated_hours || 0) > 0) return false;
  if (proof === 'explicit_description_time') return false;
  return true;
}

/**
 * pmb_arb_estimates.catalogue_estimate. arbGuide is the installed guide index {guide_version, guide_sha256, pages}.
 * Without it there is no deterministic evidence, so null. The returned review never carries guide page text.
 */
export function catalogueEstimate(r, arbGuide) {
  if (!needsLookup(r)) return null;
  const ctx = r.vehicle_context || r.raw_row?.vehicle_context || {};
  if (!CONTEXT_SOURCES.has(ctx.source)) return null;
  const vehicle = String(ctx.vehicle || ctx.model || '');
  const month = String(ctx.production_month || '');
  if (!/hilux/i.test(vehicle) || !/^(?:12\/25|0[1-9]\/26|1[0-2]\/26|202512|2026(?:0[1-9]|1[0-2]))$/.test(month)) return null;
  const d = String(r.operation_description || '').trim().toUpperCase();
  if (!/^SAFARI[ -]+SNORKEL(?:[ -]+(?:V[ -]?SPEC|ARMAX|SS223HF|SS223HP))?(?:\s*\*[^*]*\*)?\s*$/.test(d)) return null;
  if (!arbGuide) return null;
  if (arbGuide.guide_version !== GUIDE_VERSION || arbGuide.guide_sha256 !== GUIDE_SHA256) throw new ContractError('Wrong ARB guide index');
  const page = (arbGuide.pages || []).find((x) => x.page === 56)?.text || '';
  if (!['SS223HF', 'SS223HP', '320.00', '400.00'].every((x) => page.includes(x))) throw new ContractError('ARB evidence changed; re-review page56');
  let h; let lo; let hi; let cost; let kit;
  if (/V[ -]?SPEC|SS223HF/.test(d)) { h = lo = hi = 2; cost = 320; kit = 'SS223HF'; }
  else if (/ARMAX|SS223HP/.test(d)) { h = lo = hi = 2.5; cost = 400; kit = 'SS223HP'; }
  else { h = 2.25; lo = 2; hi = 2.5; cost = 320; kit = 'SS223HF / SS223HP'; }
  return {
    checked: true, status: 'estimated', guide_version: GUIDE_VERSION, guide_sha256: GUIDE_SHA256, pages: [5, 56], searched_terms: [d, 'HiLux MY26'],
    estimated_hours: h, fitting_charge: cost, labour_rate: 160, comparable_min_hours: lo, comparable_max_hours: hi, vehicle_context: ctx,
    match_basis: `HiLux MY26 production ${month}: ${kit}; published fitting 320/160=2h or400/160=2.5h; chosen ${h}h is within15% of the relevant candidates.`,
    reviewed_candidates: [{ part: 'SS223HF', hours: 2 }, { part: 'SS223HP', hours: 2.5 }],
    caveat: 'AI estimate; confirm ordered kit. Excludes relocating non-original accessories.',
  };
}

/** pmb_arb_estimates.validate (the same contract the database checks with arb_hours_review_valid). */
export function validate(r) {
  if (!needsLookup(r)) return true;
  const a = r.arb_review || {};
  const truthy = (v) => (Array.isArray(v) ? v.length > 0 : Boolean(v));
  if (!(a.checked === true && Object.hasOwn(CATALOGUES, String(a.guide_version)) && a.guide_sha256 === CATALOGUES[a.guide_version]
    && String(a.match_basis || '').trim().length >= 15 && truthy(a.searched_terms))) return false;
  if (a.status === 'unable') {
    return String(a.reason || '').trim().length > 15 && !r.effective_estimated_hours && UNABLE_REASONS.has(a.unable_reason_code)
      && Array.isArray(a.reviewed_candidates) && a.vehicle_context !== null && typeof a.vehicle_context === 'object'
      && !Array.isArray(a.vehicle_context) && Boolean(a.vehicle_context.source);
  }
  if (a.status !== 'estimated' || r.hours_provenance !== 'ai_estimated' || !truthy(a.pages)) return false;
  const h = Number(r.effective_estimated_hours); const cost = Number(a.fitting_charge); const rate = Number(a.labour_rate);
  const candidates = [cost / rate, Number(a.comparable_min_hours), Number(a.comparable_max_hours)];
  if (![h, cost, rate, ...candidates].every(Number.isFinite)) return false;
  return rate === 160 && h > 0 && h <= 999.99 && Math.abs(h * 100 - Math.round(h * 100)) < 1e-9
    && candidates.every((c) => c > 0 && Math.abs(h - c) / c <= 0.15 + 1e-12);
}

// ---- rows ----------------------------------------------------------------------------------------------------------
const EMAIL_FIELDS = ['from_address', 'mailbox', 'gmail_message_id', 'outlook_message_id', 'internet_message_id', 'verified_by',
  'approval_evidence', 'source_snapshot_timezone', 'sender', 'email_received_at'];
export { EMAIL_FIELDS };

const STOCK_PROVENANCE = {
  stock_column: 'Stock # column (exact board stock)',
  rego_column_exact_board_stock: 'Rego # column (exact board stock)',
  job_card_exact: 'Job card number (exact board job card)',
  job_card_service_job: 'R/O # (exact service job on the board)',
};

function stockProvenance(ident) {
  if (ident.status === 'linked') return STOCK_PROVENANCE[ident.basis];
  return ident.rego_fallback ? 'Rego # column (new board vehicle, Stock # blank)' : 'Stock # column (new board vehicle)';
}

function holdOf(L, ident, reason) {
  const raw = L.raw;
  return {
    reason,
    department: norm(raw.Dept),
    stock: norm(raw['Stock #']) || null,
    rego: norm(raw['Rego #']) || null,
    ro: norm(raw['R/O #']).toUpperCase(),
    line: Math.trunc(raw['Line #']),
    description: norm(raw['Operation Desc']),
    identity_status: ident?.status ?? null,
    detail: ident?.reason || (ident?.skip_reasons?.length ? ident.skip_reasons.join(',') : null),
  };
}

function holdReason(raw, ident) {
  if (!ident) return 'no_identity';
  if (!ident.send) return (ident.board_action && ident.board_action.startsWith('skip_')) ? ident.board_action : ident.status;
  if (ident.board_basis === BOARD_BASIS && subStatus(raw) === '99') return 'skip_status_99_line';
  return 'not_sent';
}

function checkUpload(upload, parsed) {
  const u = upload || {};
  for (const field of ['uploader_email', 'upload_id', 'uploaded_at']) {
    if (!norm(u[field])) throw new ContractError(`upload: ${field} is required`);
  }
  const sha = String(u.sha256 || parsed?.sha256 || '').toLowerCase();
  if (!/^[0-9a-f]{64}$/.test(sha)) throw new ContractError('upload: sha256 must be 64 hex');
  if (parsed?.sha256 && String(parsed.sha256).toLowerCase() !== sha) throw new ContractError('upload: sha256 differs from the parsed file');
  return { sha, filename: norm(u.filename || parsed?.filename), upload: { uploader_email: u.uploader_email, upload_id: u.upload_id, uploaded_at: u.uploaded_at } };
}

/**
 * buildServiceRows({ grid, parsed, board, upload, priorDecisions, ... }) -> { rows, holds, needsHours, qc, summary, snapshot }
 *   grid            readSheet() result of the uploaded file
 *   parsed          parseRevolutionUpload() result (kind must be service_whole); optional
 *   board           pdc_revolution_board_602 payload {vehicles, jobs} (optional holds, restores: stock lists)
 *   upload          {uploader_email, upload_id, uploaded_at, filename, sha256}
 *   priorDecisions  {'dept|NORMALISED DESCRIPTION': {proposed_station, routing_rule, routing_provenance, routing_rule_version,
 *                    hours_provenance, effective_estimated_hours, needs_hours_review, arb_review}} (Kajel's earlier rows)
 *   vehicleContexts {stock: vehicle_context} from an exact current Navision match (optional)
 *   standards       reviewed workshop standards registry (optional), arbGuide: installed ARB guide index (optional)
 *   previousLines   line count of the previous complete snapshot (file QC guard)
 */
export function buildServiceRows({ grid, parsed, board, upload, priorDecisions, vehicleContexts, standards, arbGuide, previousLines } = {}) {
  if (parsed && parsed.kind && parsed.kind !== 'service_whole') throw new ContractError(`report: expected service_whole, got ${parsed.kind}`);
  const { sha, filename, upload: uploadMeta } = checkUpload(upload, parsed);
  const sheet = readWhole(grid);
  const { lines, summary: collapseSummary } = collapse(sheet.data);
  const idx = boardIndex(board || { vehicles: [], jobs: [] });
  const identities = resolveLines(lines, idx);
  const snapshotAt = uploadMeta.uploaded_at;
  const snapshot = snapshotPayload(sha, snapshotAt, lines, identities);
  const prior = priorDecisions instanceof Map ? Object.fromEntries(priorDecisions) : (priorDecisions || {});
  const contexts = vehicleContexts instanceof Map ? Object.fromEntries(vehicleContexts) : (vehicleContexts || {});
  const rows = []; const holds = []; const needsHours = [];
  let priorUsed = 0; let fallbackUsed = 0; let newVehicles = new Set();
  for (const L of lines) {
    const raw = L.raw;
    const ident = identities.get(roKey(raw));
    if (!previewLineAllowed(raw, ident)) { holds.push(holdOf(L, ident, holdReason(raw, ident))); continue; }
    const department = norm(raw.Dept);
    const stock = previewStockNumber(ident, raw);
    const description = norm(raw['Operation Desc']);
    const sourceHours = raw['Estimated labour hours'] ?? null;
    const vehicleContext = contexts[stock] || {};
    const identity = { ...identityR479(ident), file_rego: ident.file_rego, file_stock: ident.file_stock };
    const rawRow = {
      ...raw,
      Company: '01',
      Division: '1',
      collapse: L.collapse,
      sublet_pos: L.sublet_pos,
      sublet_columns: L.sublet_columns,
      sublet_po_descriptions: L.sublet_po_descriptions,
      source_row_number: L.source_row_numbers[0],
      source_row_numbers: L.source_row_numbers,
      source_sheet: grid.sheetName || 'Results',
      line_collapse: COLLAPSE_RULE,
      snapshot_scope: SNAPSHOT_SCOPE,
      identity_r479: identity,
      email_subject: TITLE,
      source_kind: SOURCE_KIND,
      delivery: DELIVERY,
      upload: uploadMeta,
      source_filename: filename,
      snapshot_sha256: sha,
      parent_attachment_sha256: sha,
      source_report_parameters: sheet.params,
      source_snapshot_at: snapshotAt,
      classifier_version: ROUTING_VERSION,
      vehicle_context: vehicleContext,
      stock_identity_provenance: stockProvenance(ident),
      scope_provenance: 'Original worksheet extraction parameters',
      rolling_changed_records: false,
    };
    let row = {
      department, stock_number: stock, repair_order_number: norm(raw['R/O #']).toUpperCase(), original_line_number: Math.trunc(raw['Line #']),
      operation_description: description, operation_code: null, source_estimated_hours: sourceHours,
    };
    const decision = prior[descriptionKey(department, description)];
    if (decision) {
      priorUsed += 1;
      const routing = {
        proposed_station: decision.proposed_station, routing_rule: decision.routing_rule ?? null,
        routing_provenance: decision.routing_provenance ?? null, routing_rule_version: decision.routing_rule_version ?? null,
      };
      if (isNumber(sourceHours) && sourceHours > 0) {
        row = { ...row, effective_estimated_hours: sourceHours, hours_provenance: 'source_estimate', needs_hours_review: false, ...routing };
      } else {
        row = { ...row, effective_estimated_hours: decision.effective_estimated_hours ?? null, hours_provenance: decision.hours_provenance,
          needs_hours_review: decision.needs_hours_review, ...routing };
        if (decision.arb_review) row.arb_review = decision.arb_review;
      }
    } else {
      fallbackUsed += 1;
      const p = propose(description, sourceHours, 'REVIEW', department);
      row = { ...row, effective_estimated_hours: p.effective_estimated_hours, hours_provenance: p.hours_provenance, needs_hours_review: p.needs_hours_review,
        proposed_station: p.proposed_station, routing_rule: p.routing_rule, routing_provenance: p.routing_provenance, routing_rule_version: p.routing_rule_version };
    }
    row.workbook_sha256 = sha;
    row.vehicle_context = vehicleContext;
    row.raw_row = rawRow;
    if (!decision) {
      const standard = reviewedStandard(row, standards);
      if (standard) {
        Object.assign(row, { effective_estimated_hours: standard.hours, hours_provenance: 'craig_workshop_manager_standard', needs_hours_review: false, workshop_standard: standard });
        row.raw_row = { ...row.raw_row, workshop_standard: standard };
      }
      const matched = catalogueEstimate(row, arbGuide);
      if (matched) {
        row.arb_review = matched;
        Object.assign(row, { effective_estimated_hours: matched.estimated_hours, hours_provenance: 'ai_estimated', needs_hours_review: false });
      }
    }
    if (!validate(row)) {
      needsHours.push({ department, stock, ro: row.repair_order_number, line: row.original_line_number, description,
        station: row.proposed_station, routing_rule: row.routing_rule, reason: decision ? 'prior_review_not_valid' : 'arb_review_required' });
      continue;
    }
    if (row.arb_review) row.raw_row = { ...row.raw_row, arb_review: row.arb_review };
    if (identity.basis === BOARD_BASIS) newVehicles.add(stock);
    // Key order: the shape Kajel sent (raw_row last).
    const { raw_row: rr, ...head } = row;
    rows.push({ ...head, raw_row: rr });
  }
  const roCount = new Set(lines.map((L) => roKey(L.raw))).size;
  const qc = fileQcGuard(lines.length, roCount, true, previousLines ?? null, filename, SNAPSHOT_SCOPE);
  const holdCounts = {};
  for (const h of holds) holdCounts[h.reason] = (holdCounts[h.reason] || 0) + 1;
  const summary = {
    ...collapseSummary,
    ro_count: roCount,
    excluded_department_rows: sheet.excluded.length,
    footer_rows: sheet.footer.length,
    create_advisor: sheet.createAdvisor,
    rows_sent: rows.length,
    holds: holds.length,
    hold_counts: holdCounts,
    needs_hours: needsHours.length,
    new_board_vehicles: newVehicles.size,
    prior_decisions_used: priorUsed,
    fallback_rules_used: fallbackUsed,
    routing_rule_version: ROUTING_VERSION,
    delivery: DELIVERY,
  };
  return { rows, holds, needsHours, qc, summary, snapshot };
}
