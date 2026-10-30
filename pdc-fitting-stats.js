/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
/* r489 (F102): Admin > Fitting statistics. Administrators only (nav, view and the RPC all check).
 * r850 (F400): broken down by vehicle model (HiLux, Prado, LandCruiser 300, 70 Series ...) and filterable by fitter.
 *   Each model opens to its categories; each category lists item types (Bull bar, Tow bar, Seat covers ...) and each
 *   item type opens to the exact job card lines behind it, with completed count and the time on the job clock vs allowance.
 * r880 (F420): each job card line has a Times list (date, fitter, stock / key, time vs allowance) where an administrator can Remove a
 *   bad time (e.g. a bull bar Started and Done a minute apart) from the averages, or Restore it. The job itself is never changed.
 * Data: RPC get_pdc_fitting_statistics_850(p_days, p_technician_id) (migrations 20261030120000, 20261030130000). If that RPC is not there yet
 *   the page falls back to the r489 RPC (no model / fitter split) so nothing breaks. Read only; no stock or customer details. */
(function (root) {
  'use strict';
  const VERSION = '2026.10.30.r880';
  const PERIODS = Object.freeze([0, 7, 30, 90, 365]);
  const DEFAULT_DAYS = 0;
  const LEGACY_PERIODS = Object.freeze([7, 30, 90, 365]);
  const CATEGORY_LABELS = Object.freeze({
    FITTING:'Fitting', ELECTRICAL:'Electrical', FABRICATION:'Fabrication', HOIST:'Hoist', TINT:'Tint', TYRE:'Tyres',
    PIT_INSPECTION:'Pit', SUBLET:'Sublet', BUS_4X4:'Bus 4×4', BUS_MECHANICAL:'Bus 4×4 · Mechanical', BUS_ACCESSORIES:'Bus 4×4 · Accessories',
    BUS_ELECTRICAL:'Bus 4×4 · Electrical', BUS_QA:'Bus 4×4 · QA', BUS_PIT:'Bus 4×4 · Pit', BUS_WHOLE_JOB:'Bus 4×4 · Whole job',
    JOB_CARD_NOTES:'Job card notes', UNALLOCATED_MAPPING_REVIEW:'Not yet allocated'
  });
  const CATEGORY_ORDER = Object.freeze(['FITTING','ELECTRICAL','FABRICATION','HOIST','TINT','TYRE','PIT_INSPECTION',
    'BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_WHOLE_JOB','BUS_4X4','SUBLET','JOB_CARD_NOTES','UNALLOCATED_MAPPING_REVIEW']);
  const MODEL_LABELS = Object.freeze({
    HILUX:'HiLux', PRADO:'Prado', LC300:'LandCruiser 300', LC70:'70 Series', LANDCRUISER:'LandCruiser', COASTER:'Coaster', HIACE:'HiAce',
    DMAX:'Isuzu D-Max', FORTUNER:'Fortuner', TUNDRA:'Tundra', BZ4X:'bZ4X', RAV4:'RAV4', KLUGER:'Kluger', CAMRY:'Camry', COROLLA:'Corolla',
    YARIS:'Yaris', GRANVIA:'Granvia', OTHER:'Other models', UNKNOWN:'Model not recorded', ALL:'All models'
  });
  const MODEL_ORDER = Object.freeze(['ALL','HILUX','PRADO','LC300','LC70','LANDCRUISER','COASTER','HIACE','DMAX','FORTUNER','TUNDRA','BZ4X','RAV4','KLUGER','CAMRY','COROLLA','YARIS','GRANVIA','OTHER','UNKNOWN']);
  // Item types: the first match wins, so the specific ones come first (a "Tow Bar [For ... Tray Body]" is a tow bar, not a tray).
  const ITEM_TYPES = Object.freeze([
    ['Pre-delivery', /pre-?\s?delivery|\bpdi\b/i],
    ['Seat covers', /seat\s?covers?/i],
    ['Safety triangle', /tr(?:ia|ai)ngle/i],
    ['Wheel chocks', /chock/i],
    ['Wheel nut indicators', /nut\s+indica/i],
    ['Fire extinguisher', /extin/i],
    ['First aid kit', /first\s?aid/i],
    ['Technician step', /technician\s+step/i],
    ['Recovery points', /recovery/i],
    ['Side steps / rails', /side\s+(?:steps?|protection|rails?)|rock\s+sliders?/i],
    ['Logos / signage', /\blogos?\b|signage|signcraft|decals?|stickers?/i],
    ['IVMS', /\bivms\b/i],
    ['Auto headlamps', /auto\s+on|headlamps?\s+on\b|auto\s+headlamps?/i],
    ['Beacons / buzzers / mine bars', /beacon|buzzer|whip|mine\s?bar|clearance\s+poles?/i],
    ['Reverse camera / sensors', /reverse\s+(?:camera|parking|sensor)|parking\s+sensor/i],
    ['Rear bar / H bar', /\bh\s?bar\b|rear\s+bar/i],
    ['Lights', /light\s?bar|driving\s+lights?|spot\s?l|\bspots\b|solis|work\s?(?:lamps?|lights?)|led\s+bar|tail\s?lamps?|reverse\s+(?:lights?|lamps?)|plate\s+lamp|strip\s+lighting|hid\s+lights/i],
    ['Bull bar', /bull\s?bar|summit\s+bar|nudge\s?bar|smartbar|spartanbar/i],
    ['Battery / isolator / power', /battery|isolator|dc-?dc|redarc|inverter|anderson|12v\s+plug/i],
    ['Tow bar', /tow\s?bar|towing\s+kit|tow\s+hitch|\b7\s?pin\b/i],
    ['Cab rack', /cab\s+rack|ladder\s+rack/i],
    ['Cargo barrier', /cargo\s+barrier|\bbarrier\b/i],
    ['Snorkel', /snorkel/i],
    ['Winch', /winch/i],
    ['Roof rack', /roof\s+(?:rack|bars?|platform)/i],
    ['Awning', /awning/i],
    ['Towing mirrors', /clear\s?view|towing\s+mirrors?/i],
    ['Canopy / tray / tub', /canopy|ute\s+tub|\btub\b|tray\s+body|\btray\b|mesh\s+guard/i],
    ['Dash mat', /dash\s?mat/i],
    ['Floor / cargo mats', /\bmats?\b|cargo\s+liner/i],
    ['Cargo nets / storage', /\bnets?\b|drawer|storage/i],
    ['UHF / radio / comms', /\buhf\b|\bgme\b|radio|antenna|aerial|tetra|cel-?fi/i],
    ['Suspension / GVM', /\bgvm\b|suspension|\blift\b|coils?\b|shocks?\b/i],
    ['Diff breathers', /breather/i],
    ['Headlight covers', /head\s?(?:lamp|light)\s+(?:covers?|protectors?)/i],
    ['Weathershields / protectors', /weather\s?shield|bonnet\s+protector/i],
    ['Window tint', /\btint/i],
    ['Long range fuel tank', /long\s+range|fuel\s+tank/i],
    ['Tyres / wheels', /\btyres?\b|\brims?\b|alloy\s+wheels?/i],
    ['Bus 4×4 conversion', /bus\s?4\s?x\s?4/i],
    ['Fuel', /\bfuel\b/i],
    ['Pit and weigh', /pit\s+and\s+weigh|\bpit\b/i]
  ]);
  const SORTS = Object.freeze({completed:'Most completed', avg_minutes:'Longest average time', line_type:'A to Z', over:'Most over allowance'});
  const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const count = value => { const n = Number(value); return Number.isSafeInteger(n) && n >= 0 ? n : 0; };
  const minutes = value => value === null || value === undefined || value === '' ? null : (Number.isFinite(Number(value)) && Number(value) >= 0 ? Number(value) : null);
  const validDays = value => value !== null && value !== '' && PERIODS.includes(Number(value)) ? Number(value) : DEFAULT_DAYS;
  const validTechnician = value => typeof value === 'string' && UUID.test(value) ? value.toLowerCase() : '';
  const periodLabel = d => d === 0 ? 'All time' : d === 365 ? 'Last 12 months' : 'Last ' + d + ' days';
  function categoryLabel(code) {
    const key = String(code || '');
    return CATEGORY_LABELS[key] || (key ? key.toLowerCase().replace(/_/g,' ').replace(/^./, c => c.toUpperCase()) : 'Other');
  }
  function categoryRank(code) { const i = CATEGORY_ORDER.indexOf(code); return i === -1 ? CATEGORY_ORDER.length : i; }
  function modelLabel(code) { const key = String(code || ''); return MODEL_LABELS[key] || (key ? key.charAt(0) + key.slice(1).toLowerCase() : MODEL_LABELS.UNKNOWN); }
  function modelRank(code) { const i = MODEL_ORDER.indexOf(code); return i === -1 ? MODEL_ORDER.indexOf('OTHER') - 0.5 : i; }
  function formatMinutes(value) {
    const m = minutes(value);
    if (m === null) return '—';
    if (m > 0 && m < 1) return 'under 1m';
    const total = Math.round(m), h = Math.floor(total / 60), rest = total % 60;
    return h ? h + 'h ' + String(rest).padStart(2,'0') + 'm' : rest + 'm';
  }
  function validTime(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i.test(value)) return null;
    const t = Date.parse(value); return Number.isFinite(t) ? new Date(t).toISOString() : null;
  }
  function formatDate(value, withTime = true) {
    const t = validTime(value);
    if (!t) return 'Not recorded';
    const options = withTime ? {timeZone:'Australia/Perth',day:'numeric',month:'short',year:'numeric',hour:'numeric',minute:'2-digit'} : {timeZone:'Australia/Perth',day:'numeric',month:'short',year:'numeric'};
    return new Intl.DateTimeFormat('en-AU', options).format(new Date(t));
  }
  // Job card text without the ordering notes: "STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY" -> "STEEL BULL BAR - PREMIUM",
  // "PRE-DELIVERY (COMMERCIAL) -- 05H2A" -> "PRE-DELIVERY (COMMERCIAL)", "*SUS 16C6A*" notes dropped.
  function cleanLineType(text) {
    return String(text || '').replace(/\*[^*]*\*/g, ' ').replace(/[-–\s]*\bbroome\s+to\s+supply\b/ig, ' ')
      .replace(/[-–\s]*\b\d{2}[A-Z]\d[A-Z]\b.*$/i, ' ').replace(/\s+/g, ' ').replace(/[\s\-–]+$/, '').trim();
  }
  function itemType(lineType) {
    const text = String(lineType || '');
    if (!text.trim()) return 'Line no longer on the job card';
    for (const [label, pattern] of ITEM_TYPES) if (pattern.test(text)) return label;
    let clean = (cleanLineType(text) || text.trim()).toLowerCase();
    if (clean.length > 48) clean = clean.slice(0, 48).replace(/\s+\S*$/, '') + '…';
    return clean.charAt(0).toUpperCase() + clean.slice(1);
  }
  function normalizeLine(line) {
    const completed = count(line?.completed), timed = Math.min(count(line?.timed), completed);
    return {
      line_type: typeof line?.line_type === 'string' && line.line_type.trim() ? line.line_type.trim() : '',
      completed, timed, untimed: Math.max(0, completed - timed - count(line?.excluded)),
      avg_minutes: timed ? minutes(line.avg_minutes) : null, median_minutes: timed ? minutes(line.median_minutes) : null,
      min_minutes: timed ? minutes(line.min_minutes) : null, max_minutes: timed ? minutes(line.max_minutes) : null,
      avg_allowance_minutes: minutes(line?.avg_allowance_minutes),
      type_key: typeof line?.type_key === 'string' ? line.type_key : '', excluded: count(line?.excluded)
    };
  }
  // Lines -> item types. Average = weighted by timed lines; allowance = weighted by completed lines that had one; no median across types.
  function groupItems(lines) {
    const map = new Map();
    for (const l of lines) {
      const label = itemType(l.line_type);
      const g = map.get(label) || {item:label, lines:[], completed:0, timed:0, untimed:0, excluded:0, _t:0, _a:0, _an:0, min_minutes:null, max_minutes:null};
      g.lines.push(l); g.completed += l.completed; g.timed += l.timed; g.untimed += l.untimed; g.excluded += l.excluded;
      if (l.avg_minutes !== null && l.timed) g._t += l.avg_minutes * l.timed;
      if (l.avg_allowance_minutes) { g._a += l.avg_allowance_minutes * l.completed; g._an += l.completed; }
      if (l.min_minutes !== null) g.min_minutes = g.min_minutes === null ? l.min_minutes : Math.min(g.min_minutes, l.min_minutes);
      if (l.max_minutes !== null) g.max_minutes = g.max_minutes === null ? l.max_minutes : Math.max(g.max_minutes, l.max_minutes);
      map.set(label, g);
    }
    return [...map.values()].map(({_t,_a,_an,...g}) => ({...g, line_type:g.item, avg_minutes: g.timed ? _t / g.timed : null, avg_allowance_minutes: _an ? _a / _an : null}));
  }
  function normalizeCategory(c) {
    const lines = (Array.isArray(c.lines) ? c.lines : []).filter(Boolean).map(normalizeLine).filter(l => l.completed > 0);
    const completed = lines.reduce((s,l) => s + l.completed, 0), timed = lines.reduce((s,l) => s + l.timed, 0);
    const timedMinutes = lines.reduce((s,l) => s + (l.avg_minutes === null ? 0 : l.avg_minutes * l.timed), 0);
    return {category:c.category, label:categoryLabel(c.category), completed, timed,
      avg_line_minutes: timed ? timedMinutes / timed : null,
      jobs_completed: count(c.jobs_completed), job_avg_elapsed_minutes: count(c.jobs_completed) ? minutes(c.job_avg_elapsed_minutes) : null,
      lines, items: groupItems(lines)};
  }
  function normalizeCategories(list) {
    return (Array.isArray(list) ? list : []).filter(c => c && typeof c.category === 'string' && c.category).map(normalizeCategory)
      .filter(c => c.completed > 0 || c.jobs_completed > 0)
      .sort((a,b) => categoryRank(a.category) - categoryRank(b.category) || a.label.localeCompare(b.label));
  }
  function totalsOf(categories) {
    return {completed: categories.reduce((s,c) => s + c.completed, 0), timed: categories.reduce((s,c) => s + c.timed, 0), jobs: categories.reduce((s,c) => s + c.jobs_completed, 0)};
  }
  function normalizeReport(report) {
    const legacy = !!report && report.ok === true && Array.isArray(report.categories) && !Array.isArray(report.models);
    if (!report || report.ok !== true || (!legacy && !Array.isArray(report.models))) {
      const error = new Error(report?.code === 'permission_denied' ? 'Administrators only' : 'Fitting statistics unavailable');
      error.code = report?.code || 'unavailable'; throw error;
    }
    const rawModels = legacy ? [{model:'ALL', categories:report.categories}] : report.models;
    const models = rawModels.filter(m => m && typeof m.model === 'string' && m.model).map(m => {
      const categories = normalizeCategories(m.categories);
      return {model:m.model, label:modelLabel(m.model), categories, totals:totalsOf(categories)};
    }).filter(m => m.categories.length)
      .sort((a,b) => modelRank(a.model) - modelRank(b.model) || a.label.localeCompare(b.label));
    const technicians = legacy ? [] : (Array.isArray(report.technicians) ? report.technicians : [])
      .filter(t => t && validTechnician(t.id) && typeof t.name === 'string' && t.name.trim())
      .map(t => ({id:validTechnician(t.id), name:t.name.trim(), completed:count(t.completed)}))
      .sort((a,b) => a.name.localeCompare(b.name, 'en-AU', {sensitivity:'base'}));
    const technician = !legacy && report.technician && validTechnician(report.technician.id) ? {id:validTechnician(report.technician.id), name:String(report.technician.name || '').trim()} : null;
    const allCategories = models.flatMap(m => m.categories);
    const categoryCodes = [...new Set(allCategories.map(c => c.category))].sort((a,b) => categoryRank(a) - categoryRank(b) || categoryLabel(a).localeCompare(categoryLabel(b)));
    return {legacy, days: legacy ? (LEGACY_PERIODS.includes(Number(report.days)) ? Number(report.days) : 30) : validDays(report.days),
      generated_at: validTime(report.generated_at), since: validTime(report.since), timing_started_at: validTime(report.timing_started_at),
      technician, technicians, models, categoryCodes, totals: totalsOf(allCategories)};
  }
  function sortLines(lines, sort) {
    const text = (a,b) => (a.line_type || '~').localeCompare(b.line_type || '~', 'en-AU', {sensitivity:'base'});
    const over = l => l.avg_minutes === null || !l.avg_allowance_minutes ? -Infinity : l.avg_minutes - l.avg_allowance_minutes;
    const by = {
      completed: (a,b) => b.completed - a.completed || text(a,b),
      avg_minutes: (a,b) => (b.avg_minutes ?? -1) - (a.avg_minutes ?? -1) || b.completed - a.completed || text(a,b),
      line_type: text,
      over: (a,b) => over(b) - over(a) || b.completed - a.completed || text(a,b)
    }[SORTS[sort] ? sort : 'completed'];
    return lines.slice().sort(by);
  }
  function versusHtml(line) {
    if (line.avg_minutes === null || !line.avg_allowance_minutes) return '';
    const diff = line.avg_minutes - line.avg_allowance_minutes;
    if (Math.abs(diff) < 1) return '<span class="fitting-stats-vs is-even">on allowance</span>';
    return diff > 0 ? `<span class="fitting-stats-vs is-over">${escape(formatMinutes(diff))} over</span>` : `<span class="fitting-stats-vs is-under">${escape(formatMinutes(-diff))} under</span>`;
  }
  const entriesKey = (model, category, typeKey) => [model, category, typeKey].join('|');
  function entriesHtml(view) {
    if (!view) return '';
    if (view.loading && !view.rows) return '<p class="fitting-stats-entries-note">Loading times…</p>';
    const error = view.error ? `<p class="fitting-stats-entries-note is-error">${escape(view.error)}</p>` : '';
    if (!view.rows?.length) return error + '<p class="fitting-stats-entries-note">No timed jobs for this line in the period.</p>';
    const rows = view.rows.map(e => {
      const suspect = !e.excluded && e.minutes !== null && (e.minutes < 5 || (e.allowance_minutes && e.minutes < e.allowance_minutes * 0.25));
      const busy = view.busy === e.id;
      const car = [e.stock_number, e.key_number ? 'Key ' + e.key_number : ''].filter(Boolean).join(' · ') || '—';
      return `<tr class="${e.excluded ? 'is-removed' : suspect ? 'is-suspect' : ''}"><td data-label="Done">${escape(formatDate(e.done_at))}</td><td data-label="Fitter">${escape(e.fitter || '—')}</td><td data-label="Car">${escape(car)}</td><td data-label="Time">${escape(formatMinutes(e.minutes))}${e.excluded ? ' <span class="fitting-stats-vs is-even">removed</span>' : suspect ? ' <span class="fitting-stats-vs is-over">check</span>' : ''}</td><td data-label="Allowance">${escape(formatMinutes(e.allowance_minutes))}</td><td><button type="button" class="small-button fitting-stats-exclude${e.excluded ? '' : ' is-remove'}" data-fitting-stats-exclude="${escape(e.id)}" data-excluded="${e.excluded ? 'false' : 'true'}"${busy || view.busy ? ' disabled' : ''}>${busy ? 'Saving…' : e.excluded ? 'Restore' : 'Remove'}</button></td></tr>`;
    }).join('');
    return error + `<table class="fitting-stats-entries"><thead><tr><th scope="col">Done</th><th scope="col">Fitter</th><th scope="col">Car</th><th scope="col">Time</th><th scope="col">Allowance</th><th scope="col"><span class="visually-hidden">Remove or restore</span></th></tr></thead><tbody>${rows}</tbody></table><p class="fitting-stats-entries-note">Remove takes that job's time out of the averages only; it still counts as done and nothing on the job changes.</p>`;
  }
  function linesTableHtml(lines, sort, model = '', category = '', entries = {}) {
    const rows = sortLines(lines, sort).map(l => {
      const key = l.type_key && model ? entriesKey(model, category, l.type_key) : '';
      const canTime = key && (l.timed + l.excluded) > 0;
      const open = canTime && entries[key];
      const button = canTime ? `<button type="button" class="small-button fitting-stats-times" data-fitting-stats-times="${escape(key)}" aria-expanded="${open ? 'true' : 'false'}">${open ? 'Hide times' : 'Times'}</button>` : '';
      return `<tr><th scope="row" data-label="Job card line">${l.line_type ? escape(l.line_type) : '<em>Line no longer on the job card</em>'}</th><td data-label="Completed">${l.completed}</td><td data-label="Timed (Start → Done)">${l.timed}${l.untimed ? `<small> · ${l.untimed} without Start</small>` : ''}${l.excluded ? `<small> · ${l.excluded} removed</small>` : ''}</td><td data-label="Average time">${escape(formatMinutes(l.avg_minutes))}${versusHtml(l)}</td><td data-label="Median">${escape(formatMinutes(l.median_minutes))}</td><td data-label="Fastest – slowest">${l.timed ? escape(formatMinutes(l.min_minutes)) + ' – ' + escape(formatMinutes(l.max_minutes)) : '—'}</td><td data-label="Allowance (average)">${escape(formatMinutes(l.avg_allowance_minutes))}</td><td class="fitting-stats-times-cell">${button}</td></tr>` +
        (open ? `<tr class="fitting-stats-entries-row"><td colspan="8">${entriesHtml(open)}</td></tr>` : '');
    }).join('');
    return `<div class="fitting-stats-table-wrap"><table class="fitting-stats-table"><thead><tr><th scope="col">Job card line</th><th scope="col">Completed</th><th scope="col">Timed (Start → Done)</th><th scope="col">Average time</th><th scope="col">Median</th><th scope="col">Fastest – slowest</th><th scope="col">Allowance (average)</th><th scope="col"><span class="visually-hidden">Times</span></th></tr></thead><tbody>${rows}</tbody></table></div>`;
  }
  function itemHtml(item, sort, model = '', category = '', entries = {}) {
    const range = item.timed ? ` · ${escape(formatMinutes(item.min_minutes))} – ${escape(formatMinutes(item.max_minutes))}` : '';
    return `<details class="fitting-stats-item" data-fitting-stats-item="${escape(item.item)}" data-fitting-stats-open="${escape('i|' + model + '|' + category + '|' + item.item)}"><summary><span class="fitting-stats-item-name">${escape(item.item)}</span><span class="fitting-stats-item-figures"><strong>${item.completed}</strong> done · ${item.timed} timed${item.timed ? ` · average ${escape(formatMinutes(item.avg_minutes))}${range}` : ''}${item.avg_allowance_minutes ? ` · allowance ${escape(formatMinutes(item.avg_allowance_minutes))}` : ''}${versusHtml(item)}${item.excluded ? ` <small>· ${item.excluded} removed</small>` : ''}</span></summary>${linesTableHtml(item.lines, sort, model, category, entries)}</details>`;
  }
  function categoryHtml(cat, sort, model = '', entries = {}) {
    const jobs = cat.jobs_completed ? `${cat.jobs_completed} station job${cat.jobs_completed === 1 ? '' : 's'} completed · average ${escape(formatMinutes(cat.job_avg_elapsed_minutes))} start to finish` : 'No station jobs completed';
    const items = sortLines(cat.items, sort).map(i => itemHtml(i, sort, model, cat.category, entries)).join('');
    return `<section class="fitting-stats-category" data-fitting-stats-category="${escape(cat.category)}"><header><h4>${escape(cat.label)}</h4><p><strong>${cat.completed}</strong> line${cat.completed === 1 ? '' : 's'} completed · <strong>${cat.timed}</strong> timed${cat.avg_line_minutes === null ? '' : ` · average ${escape(formatMinutes(cat.avg_line_minutes))} per timed line`}<br><span>${jobs}</span></p></header>`+
      (items ? `<div class="fitting-stats-items">${items}</div>` : '<p class="fitting-stats-empty">No lines were ticked Done in this category in the period.</p>')+'</section>';
  }
  function modelHtml(model, {category, sort, open, entries = {}}) {
    const cats = model.categories.filter(c => category === 'all' || c.category === category);
    if (!cats.length) return '';
    const t = totalsOf(cats);
    return `<details class="fitting-stats-model" data-fitting-stats-model="${escape(model.model)}" data-fitting-stats-open="${escape('m|' + model.model)}"${open ? ' open' : ''}><summary><h3>${escape(model.label)}</h3><span><strong>${t.completed}</strong> line${t.completed === 1 ? '' : 's'} completed · ${t.timed} timed · ${t.jobs} station job${t.jobs === 1 ? '' : 's'}</span></summary>${cats.map(c => categoryHtml(c, sort, report_legacy(model) ? '' : model.model, entries)).join('')}</details>`;
  }
  const report_legacy = model => model.model === 'ALL';
  function reportHtml(report, {category = 'all', sort = 'completed', model = 'all', entries = {}} = {}) {
    const models = report.models.filter(m => model === 'all' || m.model === model);
    const shownCats = models.flatMap(m => m.categories.filter(c => category === 'all' || c.category === category));
    const t = totalsOf(shownCats);
    const shownModels = models.filter(m => m.categories.some(c => category === 'all' || c.category === category));
    const summary = `<div class="fitting-stats-summary"><div><span>Lines completed</span><strong>${t.completed}</strong></div><div><span>Timed (Start → Done)</span><strong>${t.timed}</strong></div><div><span>Station jobs completed</span><strong>${t.jobs}</strong></div><div><span>Models</span><strong>${report.legacy ? '—' : shownModels.length}</strong></div></div>`;
    const open = shownModels.length === 1;
    const body = shownModels.length ? shownModels.map(m => modelHtml(m, {category, sort, open, entries})).join('') : '<p class="fitting-stats-empty">Nothing was completed in this period' + (report.technician ? ' by ' + escape(report.technician.name) : '') + '.</p>';
    const legacy = report.legacy ? '<p class="fitting-stats-empty fitting-stats-legacy">The model and fitter breakdown needs the database update; showing all models together until it is applied.</p>' : '';
    const note = `<details class="fitting-stats-about"><summary>How these figures are worked out</summary><p>Completed counts every bay item ticked Done in the period (Perth time), by the vehicle's model and the line's work category. With a fitter chosen, only the items ticked Done for that fitter count, and station jobs only where that fitter ticked a line. Model is the vehicle model (HiLux, Prado, LandCruiser 300, 70 Series ...). Item types group similar job card lines (every bull bar line is under Bull bar); open an item type to see the exact lines. Times only count items where the fitter pressed Start and then Done: the time is the working time on the job clock between the two, so breaks and closed hours are not counted. Items ticked Done without Start are counted as completed but have no time. Item type averages are weighted by the timed lines. Times opens every timed job behind a line; Remove takes a bad time (for example Start and Done pressed a minute apart) out of every average without changing the job, and Restore puts it back. Times under 5 minutes or under a quarter of the allowance are marked check. Station jobs are whole bookings completed in the period; their time is the clock time from Start work to Complete.${report.timing_started_at ? ' Item timing was first recorded ' + escape(formatDate(report.timing_started_at)) + ', so there are no times before then.' : ''}</p></details>`;
    return summary + legacy + body + note;
  }
  function normalizeEntries(response) {
    if (!response || response.ok !== true || !Array.isArray(response.entries)) {
      const error = new Error(response?.code === 'permission_denied' ? 'Administrators only' : 'Times unavailable'); error.code = response?.code || 'unavailable'; throw error;
    }
    return response.entries.filter(e => e && UUID.test(String(e.booking_id || '')) && typeof e.line_identity === 'string' && e.line_identity).map(e => ({
      id: String(e.booking_id).toLowerCase() + '|' + e.line_identity, booking_id: String(e.booking_id).toLowerCase(), line_identity: e.line_identity,
      done_at: validTime(e.done_at), fitter: typeof e.fitter === 'string' ? e.fitter.trim() : '',
      stock_number: e.stock_number == null ? '' : String(e.stock_number).trim(), key_number: e.key_number == null ? '' : String(e.key_number).trim(),
      minutes: minutes(e.minutes), allowance_minutes: minutes(e.allowance_minutes), excluded: e.excluded === true
    }));
  }
  function createController(options) {
    let owner = '', generation = 0, active = false, locked = false;
    const blank = () => ({loading:false,report:null,error:'',days:DEFAULT_DAYS,technician:'',model:'all',category:'all',sort:'completed',entries:{}});
    let state = blank();
    const context = () => options.context() || {};
    const allowed = ctx => !locked && !!ctx.userId && ctx.role === 'administrator' && !!ctx.token;
    const identity = ctx => [ctx.userId,ctx.role,ctx.url,ctx.key].join('\u0000');
    function emit() { options.render({...state,active,allowed:allowed(context())}); }
    function clear() { generation++; state = blank(); }
    function syncAccess() {
      const ctx = context(), nextOwner = allowed(ctx) ? identity(ctx) : '';
      if (nextOwner !== owner || !nextOwner) { owner = nextOwner; clear(); }
      emit();
      return !!nextOwner;
    }
    async function loadEntries(key, keep = false) {
      const [model, category, ...rest] = String(key).split('|'), typeKey = rest.join('|');
      const ctx = {...context()}, days = state.days, technician = state.technician, requestOwner = identity(ctx);
      const previous = state.entries[key];
      state = {...state,entries:{...state.entries,[key]:{rows: keep ? previous?.rows || null : null, loading:true, busy:'', error:''}}}; emit();
      const current = () => active && allowed(context()) && requestOwner === identity(context()) && state.days === days && state.technician === technician && state.entries[key];
      try {
        const rows = normalizeEntries(await options.entries(ctx, days, technician || null, model, category, typeKey));
        if (!current()) return;
        state = {...state,entries:{...state.entries,[key]:{rows,loading:false,busy:'',error:''}}};
      } catch (err) {
        if (!current()) return;
        const message = err?.code === 'not_deployed' ? 'Times need the database update.' : 'Could not load times. Please try again.';
        state = {...state,entries:{...state.entries,[key]:{rows:previous?.rows || null,loading:false,busy:'',error:message}}};
      }
      emit();
    }
    async function refresh() {
      if (!syncAccess() || !active) return;
      const ctx = {...context()}, requestOwner = identity(ctx), requestId = ++generation, days = state.days, technician = state.technician;
      state = {...state,loading:true,error:''}; emit();
      const current = () => requestId === generation && active && allowed(context()) && requestOwner === identity(context()) && state.days === days && state.technician === technician;
      try {
        const response = await options.request(ctx, days, technician || null);
        if (!current()) return;
        const report = normalizeReport(response);
        if (state.model !== 'all' && !report.models.some(m => m.model === state.model)) state.model = 'all';
        if (state.category !== 'all' && !report.categoryCodes.includes(state.category)) state.category = 'all';
        state = {...state,loading:false,report,error:''};
      } catch (_) {
        if (!current()) return;
        state = {...state,loading:false,error:'Could not load fitting statistics. Please try Refresh.'};
      }
      emit();
    }
    return {
      open() {
        const alreadyActive = active; active = true;
        if (!syncAccess() || (alreadyActive && state.report)) return Promise.resolve();
        return refresh();
      },
      close() { active = false; clear(); emit(); },
      reset() { locked = true; owner = ''; active = false; clear(); emit(); },
      ready() { locked = false; syncAccess(); },
      setDays(value) { const days = validDays(value); if (days === state.days && state.report) return Promise.resolve(); state = {...state,days,report:null,entries:{}}; return refresh(); },
      setTechnician(value) { const technician = validTechnician(value); if (technician === state.technician && state.report) return Promise.resolve(); state = {...state,technician,report:null,entries:{}}; return refresh(); },
      // r880: open / close the Times list behind one job card line (key = model|category|type_key).
      async toggleEntries(key) {
        const parts = String(key || '').split('|'); if (parts.length < 3 || !state.report || state.report.legacy) return;
        if (state.entries[key]) { const entries = {...state.entries}; delete entries[key]; state = {...state,entries}; emit(); return; }
        return loadEntries(key);
      },
      // r880: remove (excluded true) or restore one job's time, then reload that list and the figures.
      async setExcluded(key, entryId, excluded) {
        const view = state.entries[key]; const entry = view?.rows?.find(e => e.id === entryId);
        if (!entry || view.busy || !allowed(context())) return;
        state = {...state,entries:{...state.entries,[key]:{...view,busy:entryId,error:''}}}; emit();
        let error = '';
        try {
          const result = await options.exclude({...context()}, entry.booking_id, entry.line_identity, !!excluded);
          if (!result || result.ok !== true) error = result?.code === 'permission_denied' ? 'Administrators only.' : 'Could not save. Please try again.';
        } catch (_) { error = 'Could not save. Please try again.'; }
        if (!state.entries[key]) return;
        if (error) { state = {...state,entries:{...state.entries,[key]:{...state.entries[key],busy:'',error}}}; emit(); return; }
        await loadEntries(key, true);
        return refresh();
      },
      setModel(value) { state = {...state,model:String(value || 'all')}; emit(); },
      setCategory(value) { state = {...state,category:String(value || 'all')}; emit(); },
      setSort(value) { state = {...state,sort:SORTS[value] ? value : 'completed'}; emit(); },
      syncAccess, refresh,
      getState() { return {...state,active,allowed:allowed(context())}; }
    };
  }
  const api = {VERSION,PERIODS,DEFAULT_DAYS,CATEGORY_LABELS,MODEL_LABELS,SORTS,categoryLabel,modelLabel,formatMinutes,formatDate,cleanLineType,itemType,groupItems,normalizeReport,normalizeEntries,entriesKey,sortLines,reportHtml,createController};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  if (!root.document) return;
  const doc = root.document;
  function render(state) {
    const nav = doc.getElementById('nav-fitting-stats');
    if (nav) nav.hidden = !state.allowed;
    const view = doc.getElementById('fitting-stats');
    if (view) view.hidden = !state.allowed;
    const host = doc.getElementById('fitting-stats-content');
    if (!host) return;
    if (!state.allowed || !state.active) { host.replaceChildren(); return; }
    const focused = host.contains(doc.activeElement) ? doc.activeElement?.getAttribute('data-fitting-stats-control') : null;
    // r880: a re-render (Times, Remove, Refresh) keeps every model / item drop-down as the user left it.
    const openState = new Map([...host.querySelectorAll('details[data-fitting-stats-open]')].map(d => [d.getAttribute('data-fitting-stats-open'), d.open]));
    const scrollY = root.scrollY;
    const report = state.report, legacy = !!report?.legacy;
    const periodOptions = PERIODS.filter(d => !legacy || d !== 0).map(d => `<option value="${d}"${d === (legacy && state.days === 0 ? 365 : state.days) ? ' selected' : ''}>${periodLabel(d)}</option>`).join('');
    const techs = report?.technicians || [];
    const techOptions = '<option value="">All fitters</option>' + techs.map(t => `<option value="${escape(t.id)}"${t.id === state.technician ? ' selected' : ''}>${escape(t.name)}${t.completed ? ' (' + t.completed + ')' : ''}</option>`).join('');
    const models = report?.models || [];
    const modelOptions = '<option value="all">All models</option>' + (legacy ? '' : models.map(m => `<option value="${escape(m.model)}"${m.model === state.model ? ' selected' : ''}>${escape(m.label)} (${m.totals.completed})</option>`).join(''));
    const categoryOptions = '<option value="all">All categories</option>' + (report?.categoryCodes || []).map(c => `<option value="${escape(c)}"${c === state.category ? ' selected' : ''}>${escape(categoryLabel(c))}</option>`).join('');
    const sortOptions = Object.entries(SORTS).map(([k,v]) => `<option value="${k}"${k === state.sort ? ' selected' : ''}>${escape(v)}</option>`).join('');
    const who = report?.technician?.name ? ' · ' + escape(report.technician.name) : '';
    const status = state.error ? escape(state.error) + (report ? ' Showing the figures loaded before; they may be out of date.' : '')
      : state.loading ? 'Loading fitting statistics…'
      : report ? (report.since ? 'Period from ' + escape(formatDate(report.since,false)) + ' to now' : 'All time') + who + ' · checked ' + escape(formatDate(report.generated_at)) + ' (Perth time)' : '';
    host.innerHTML = `<div class="fitting-stats-header"><div><h2>Fitting statistics</h2><p>What was fitted and how long it took, by model, fitter and item.</p></div><div class="fitting-stats-controls"><label>Period <select data-fitting-stats-control="days">${periodOptions}</select></label><label>Fitter <select data-fitting-stats-control="technician"${techs.length ? '' : ' disabled'}>${techOptions}</select></label><label>Model <select data-fitting-stats-control="model"${models.length && !legacy ? '' : ' disabled'}>${modelOptions}</select></label><label>Category <select data-fitting-stats-control="category"${report?.categoryCodes?.length ? '' : ' disabled'}>${categoryOptions}</select></label><label>Sort <select data-fitting-stats-control="sort">${sortOptions}</select></label><button type="button" class="small-button" data-fitting-stats-control="refresh"${state.loading ? ' disabled' : ''}>${state.loading ? 'Refreshing…' : 'Refresh'}</button></div></div><p class="fitting-stats-status${state.error ? ' is-error' : ''}" role="status" aria-live="polite">${status}</p><div class="fitting-stats-body" aria-busy="${state.loading}">${report ? reportHtml(report,{category:state.category,sort:state.sort,model:state.model,entries:state.entries}) : ''}</div>`;
    host.querySelectorAll('details[data-fitting-stats-open]').forEach(d => { const k = d.getAttribute('data-fitting-stats-open'); if (openState.has(k)) d.open = openState.get(k); });
    if (openState.size && typeof root.scrollTo === 'function' && root.scrollY !== scrollY) root.scrollTo(0, scrollY);
    if (!host.__fittingStatsClicks) {
      host.__fittingStatsClicks = true;
      host.addEventListener('click', event => {
        const times = event.target.closest?.('[data-fitting-stats-times]');
        if (times && host.contains(times)) { event.preventDefault(); controller.toggleEntries(times.getAttribute('data-fitting-stats-times')); return; }
        const ex = event.target.closest?.('[data-fitting-stats-exclude]');
        if (ex && host.contains(ex) && !ex.disabled) {
          event.preventDefault();
          const key = ex.closest('.fitting-stats-entries-row')?.previousElementSibling?.querySelector('[data-fitting-stats-times]')?.getAttribute('data-fitting-stats-times');
          if (key) controller.setExcluded(key, ex.getAttribute('data-fitting-stats-exclude'), ex.getAttribute('data-excluded') === 'true');
        }
      });
    }
    host.querySelector('[data-fitting-stats-control="days"]').addEventListener('change', e => controller.setDays(e.target.value));
    host.querySelector('[data-fitting-stats-control="technician"]').addEventListener('change', e => controller.setTechnician(e.target.value));
    host.querySelector('[data-fitting-stats-control="model"]').addEventListener('change', e => controller.setModel(e.target.value));
    host.querySelector('[data-fitting-stats-control="category"]').addEventListener('change', e => controller.setCategory(e.target.value));
    host.querySelector('[data-fitting-stats-control="sort"]').addEventListener('change', e => controller.setSort(e.target.value));
    host.querySelector('[data-fitting-stats-control="refresh"]').addEventListener('click', () => controller.refresh());
    if (focused) host.querySelector(`[data-fitting-stats-control="${focused}"]`)?.focus({preventScroll:true});
  }
  async function post(ctx, rpc, body) {
    return root.fetch(ctx.url.replace(/\/$/,'') + '/rest/v1/rpc/' + rpc, {
      method:'POST', headers:{'Content-Type':'application/json',apikey:ctx.key,Authorization:'Bearer ' + ctx.token}, body:JSON.stringify(body), cache:'no-store'
    });
  }
  const controller = createController({
    context:() => ({userId:root.PDC_AUTH_CONTEXT?.userId,role:root.PDC_AUTH_CONTEXT?.role,token:root.__pdcCachedAccessToken,url:root.PDC_SUPABASE_CONFIG?.url,key:root.PDC_SUPABASE_CONFIG?.publishableKey}),
    request:async (ctx, days, technician) => {
      if (!ctx.url || !ctx.key) throw new Error('Service unavailable');
      const response = await post(ctx, 'get_pdc_fitting_statistics_850', {p_days:days, p_technician_id:technician});
      if (response.status === 404 && !technician) {
        // r850 database update not applied yet: the r489 report (no model / fitter split) keeps the page working.
        const legacy = await post(ctx, 'get_pdc_fitting_statistics_489', {p_days: LEGACY_PERIODS.includes(days) ? days : 365});
        if (!legacy.ok) throw new Error('Fitting statistics unavailable');
        return legacy.json();
      }
      if (!response.ok) throw new Error('Fitting statistics unavailable');
      return response.json();
    },
    entries:async (ctx, days, technician, model, category, typeKey) => {
      if (!ctx.url || !ctx.key) throw new Error('Service unavailable');
      const response = await post(ctx, 'get_pdc_fitting_line_entries_880', {p_days:days, p_technician_id:technician, p_model:model, p_category:category, p_type_key:typeKey});
      if (response.status === 404) { const e = new Error('not deployed'); e.code = 'not_deployed'; throw e; }
      if (!response.ok) throw new Error('Times unavailable');
      return response.json();
    },
    exclude:async (ctx, bookingId, lineIdentity, excluded) => {
      if (!ctx.url || !ctx.key || !ctx.token) throw new Error('Service unavailable');
      const response = await post(ctx, 'set_pdc_fitting_time_excluded_880', {p_booking_id:bookingId, p_line_identity:lineIdentity, p_excluded:excluded});
      if (!response.ok) throw new Error('Could not save');
      return response.json();
    }, render
  });
  root.PdcFittingStats = {open:controller.open, close:controller.close, reset:controller.reset, syncAccess:controller.syncAccess, version:VERSION};
  root.addEventListener('pdc-auth-locked', controller.reset);
  root.addEventListener('pdc-auth-ready', () => {
    controller.ready();
    if (doc.getElementById('fitting-stats')?.classList.contains('active')) controller.open();
  });
  controller.syncAccess();
})(typeof window !== 'undefined' ? window : globalThis);
