// r728: the website prepares the Service as a Whole rows Kajel used to send (service_rows.js). Synthetic data only.
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');
const path = require('node:path');

const modulePath = path.join(__dirname, 'supabase/functions/revolution-upload/service_rows.js');
const load = () => import('./supabase/functions/revolution-upload/service_rows.js');
const parser = () => import('./supabase/functions/revolution-upload/parse.js');

const TITLE = 'PMG PD Service as a Whole w/Sublet';
const PARAMS = 'Extracted on 29/10/2026 13:30   Parameters: Company = "01" and Division = "1" and ( Dept = "138" or Dept = "139" ) and ( Status >= "20" and Status < "90" )';
const BASE = ['Dept', 'Stock #', 'Rego #', 'Owner Name', 'Parts Location', 'Key Tag Number', 'R/O #', 'Sub Status', 'Line #', 'Operation Desc', 'Estimated labour hours', 'Modified Date', 'Range #'];
const HEADERS = [...BASE, 'PO #', 'Description of sublet'];
const SHA = 'ab'.repeat(32);
const UPLOAD = { uploader_email: 'admin@example.test', upload_id: 'upl-728-1', uploaded_at: '2026-10-29T05:30:00+00:00', filename: 'PMG PD Service as a Whole w-Sublet - Job 1.xls', sha256: SHA };

function line(o = {}) {
  const r = { dept: 139, stock: 'SYN0001', rego: 'SYNR001', owner: 'Synthetic Owner', loc: null, key: 0, ro: 'J139900001', status: '20', line: 1,
    desc: 'Synthetic operation', hours: 1, modified: '2026-10-28 00:00:00', range: 'TOYHIA', po: null, sublet: null, advisor: 'OB', ...o };
  return [r.dept, r.stock, r.rego, r.owner, r.loc, r.key, r.ro, r.status, r.line, r.desc, r.hours, r.modified, r.range, r.po, r.sublet, r.advisor];
}

function grid(dataRows, { headers = [...HEADERS, 'Create Advisor'], params = PARAMS, title = TITLE, wrap = true, typed = false } = {}) {
  const head = (typed ? ['Type', ...headers] : headers).map((h) => (wrap ? `="${h}"` : h));
  const data = dataRows.map((r) => (typed ? ['D', ...r] : r));
  return { sheetName: 'Results', rows: [[title], [params], [], head, ...data] };
}

const veh = (i, stock, extra = {}) => ({ id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, stock, jc: null, ls: 'active', deleted: false, visible: true, ...extra });
const BOARD = {
  vehicles: [veh(1, 'SYN0001'), veh(2, 'SYN0002', { jc: 'J139900002' }), veh(3, 'SYNR003'), veh(4, 'SYN0004', { ls: 'completed' }), veh(9, 'SYN0009')],
  jobs: [{ vehicle_id: veh(9).id, ro: 'J139900009', closed: false }],
};

async function build(rows, extra = {}) {
  const { buildServiceRows } = await load();
  return buildServiceRows({ grid: extra.grid || grid(rows, extra.gridOptions), board: extra.board || BOARD, upload: extra.upload || UPLOAD, ...extra.options });
}

test('the module runs in Deno and node: no node-only imports', () => {
  const source = readFileSync(modulePath, 'utf8');
  assert.equal(/from 'node:|require\(/.test(source), false);
  assert.match(source, /from '\.\/parse\.js'/);
});

test('title and parameters: only a full open-R/O snapshot is read', async () => {
  const { buildServiceRows, ContractError } = await load();
  const rows = [line()];
  assert.throws(() => buildServiceRows({ grid: grid(rows, { title: 'PMG PD Service Complete w/Sublet' }), board: BOARD, upload: UPLOAD }), ContractError);
  for (const params of [PARAMS.replace('Dept = "138" or ', ''), PARAMS.replace('< "90"', '< "80"'), PARAMS.replace('Division = "1"', 'Division = "2"'), 'Company = "01" Division = "1"']) {
    assert.throws(() => buildServiceRows({ grid: grid(rows, { params }), board: BOARD, upload: UPLOAD }), /parameters/);
  }
  assert.throws(() => buildServiceRows({ grid: grid(rows), board: BOARD, upload: { ...UPLOAD, upload_id: '' } }), /upload_id/);
  assert.throws(() => buildServiceRows({ grid: grid(rows), board: BOARD, upload: { ...UPLOAD, sha256: 'abc' } }), /sha256/);
  assert.throws(() => buildServiceRows({ grid: grid(rows), parsed: { kind: 'cw_parts' }, board: BOARD, upload: UPLOAD }), /service_whole/);
});

test('header unwrap: ="..." headers, plain headers and a leading Type column give the same rows', async () => {
  const rows = [line({ hours: 2 }), line({ line: 2, hours: 3 })];
  const a = await build(rows);
  const b = await build(rows, { gridOptions: { wrap: false } });
  const c = await build(rows, { gridOptions: { typed: true } });
  assert.deepEqual(a.rows, b.rows);
  assert.deepEqual(a.rows, c.rows);
  assert.equal(a.rows.length, 2);
  assert.equal('Type' in a.rows[0].raw_row, false);
  assert.equal('Create Advisor' in a.rows[0].raw_row, false);
  const { readWhole } = await load();
  assert.throws(() => readWhole(grid(rows, { headers: [...BASE, 'Create Advisor', 'PO #'] })), /headers/);
  assert.throws(() => readWhole(grid([line({ line: 1.5 })])), /Line #/);
  assert.throws(() => readWhole(grid([line({ ro: 'J138900001' })])), /J138\/J139/);
});

test('collapse: one row per Dept + R/O + Line #, hours never summed, every PO kept with its description', async () => {
  const rows = [
    line({ po: 'GP13990001', sublet: 'Canopy fit', hours: 2 }),
    line({ po: 'gp1399 0002', sublet: 'Tray', hours: 2 }),
    line({ po: 'GP13990001', sublet: 'Canopy fit second note', hours: 2 }),
    line({ line: 2, desc: 'Other', hours: 1.5 }),
  ];
  const out = await build(rows);
  assert.equal(out.rows.length, 2);
  const [first] = out.rows;
  assert.equal(first.source_estimated_hours, 2);
  assert.equal(first.effective_estimated_hours, 2);
  assert.deepEqual(first.raw_row.collapse, { rule: 'r442_one_row_per_dept_ro_line', source_rows: 3, hours_summed: false, conflict: false });
  assert.deepEqual(first.raw_row.sublet_pos, ['GP13990001', 'GP13990002']);
  assert.deepEqual(first.raw_row.sublet_po_descriptions, { GP13990001: 'Canopy fit^Canopy fit second note', GP13990002: 'Tray' });
  assert.deepEqual(first.raw_row.source_row_numbers, [5, 6, 7]);
  assert.equal(first.raw_row.source_row_number, 5);
  assert.deepEqual(first.raw_row.sublet_columns[1], { 'PO #': 'gp1399 0002', 'Description of sublet': 'Tray', source_row_number: 6 });
  assert.equal(first.raw_row.line_collapse, 'r442_one_row_per_dept_ro_line');
  assert.equal(out.summary.hours_first_row_per_line, 3.5);
  assert.equal(out.summary.hours_naive_all_rows, 7.5);
  const conflict = await build([line({ hours: 2, po: 'GP1' }), line({ hours: 3, po: 'GP2' })]);
  assert.equal(conflict.rows[0].source_estimated_hours, 2);
  assert.equal(conflict.rows[0].raw_row.collapse.conflict, true);
  assert.equal(conflict.rows[0].raw_row.collapse.kept, 'first_row_in_source_order');
  assert.deepEqual(conflict.rows[0].raw_row.collapse.differing_values, { 'Estimated labour hours': [2, 3] });
});

test('Create Advisor: a data row with a blank advisor is not imported and closes nothing', async () => {
  const out = await build([line(), line({ line: 2, advisor: '' }), line({ line: 3, advisor: null }), line({ line: 4, advisor: 'GR' })]);
  assert.deepEqual(out.rows.map((r) => r.original_line_number), [1, 4]);
  assert.deepEqual(out.summary.create_advisor, { rule: 'r509_import_rows_with_create_advisor', column: 'trailing_create_advisor_dropped_r509',
    blank_data_rows: 2, blank_data_row_numbers: [6, 7], kept_data_rows: 2, closes_board_cards: false });
  const noColumn = await build([line(), line({ line: 2 })].map((r) => r.slice(0, -1)), { gridOptions: { headers: HEADERS } });
  assert.equal(noColumn.rows.length, 2);
  assert.equal(noColumn.summary.create_advisor.column, 'absent');
});

test('identity bases: stock column, rego, job card, service job, new board vehicle; Sub Status 99 is not created', async () => {
  const board = { ...BOARD, holds: ['SYN0070'], restores: ['SYN0071'] };
  const out = await build([
    line({ ro: 'J139900001', stock: 'SYN0001' }),
    line({ ro: 'J139900003', stock: null, rego: 'SYNR003' }),
    line({ ro: 'J139900002', stock: null, rego: 'NOTONBOARD' }),
    line({ ro: 'J139900009', stock: null, rego: null }),
    line({ ro: 'J139900050', stock: 'SYN0050' }),
    line({ ro: 'J139900051', stock: null, rego: 'SYNREGO51' }),
    line({ ro: 'J139900052', stock: 'SYN0052', status: '99' }),
    line({ ro: 'J139900053', stock: 'SYN0053', status: '99' }),
    line({ ro: 'J139900053', stock: 'SYN0053', status: '22', line: 2 }),
    line({ ro: 'J139900054', stock: 'SYN0054', status: '80' }),
    line({ ro: 'J139900004', stock: 'SYN0004' }),
    line({ ro: 'J139900060', stock: 'SYN0060' }),
    line({ ro: 'J139900060', stock: 'SYN0061', line: 2 }),
    line({ ro: 'J139900070', stock: 'SYN0070' }),
    line({ ro: 'J139900071', stock: null, rego: 'SYN0071' }),
    line({ ro: 'J139900072', stock: null, rego: null }),
    line({ ro: 'J139900001', stock: 'SYN0001', line: 2, status: '99' }),
  ], { board });
  const sent = Object.fromEntries(out.rows.map((r) => [`${r.repair_order_number}|${r.original_line_number}`, r]));
  const basis = (k) => sent[k].raw_row.identity_r479;
  assert.deepEqual(basis('J139900001|1'), { rule: 'r479_exact_board_stock_or_job_card', basis: 'stock_column', file_rego: 'SYNR001', file_stock: 'SYN0001' });
  assert.equal(sent['J139900001|1'].raw_row.stock_identity_provenance, 'Stock # column (exact board stock)');
  assert.equal(basis('J139900003|1').basis, 'rego_column_exact_board_stock');
  assert.equal(sent['J139900003|1'].stock_number, 'SYNR003');
  assert.equal(basis('J139900002|1').basis, 'job_card_exact');
  assert.equal(sent['J139900002|1'].stock_number, 'SYN0002');
  assert.equal(basis('J139900009|1').basis, 'job_card_service_job');
  assert.equal(sent['J139900009|1'].stock_number, 'SYN0009');
  assert.equal(basis('J139900050|1').basis, 'new_board_vehicle');
  assert.equal(basis('J139900050|1').rego_fallback, undefined);
  assert.equal(sent['J139900050|1'].stock_number, 'SYN0050');
  assert.equal(basis('J139900051|1').rego_fallback, true);
  assert.equal(sent['J139900051|1'].stock_number, 'SYNREGO51');
  assert.equal(sent['J139900052|1'], undefined);
  assert.equal(sent['J139900053|1'], undefined);
  assert.equal(basis('J139900053|2').basis, 'new_board_vehicle');
  assert.equal(basis('J139900054|1').basis, 'new_board_vehicle');
  assert.equal(basis('J139900001|2').basis, 'stock_column');
  const holds = Object.fromEntries(out.holds.map((h) => [`${h.ro}|${h.line}`, h.reason]));
  assert.deepEqual(holds, {
    'J139900052|1': 'skip_status_99', 'J139900053|1': 'skip_status_99_line', 'J139900004|1': 'vehicle_not_live',
    'J139900060|1': 'ambiguous', 'J139900060|2': 'ambiguous', 'J139900070|1': 'skip_owner_hold', 'J139900071|1': 'skip_pending_restore',
    'J139900072|1': 'no_board_vehicle',
  });
  assert.equal(out.summary.new_board_vehicles, 4);
  const create = out.snapshot.lines.find((l) => l[1] === 'J139900050');
  assert.deepEqual(create, ['139', 'J139900050', 1, null, 'SYN0050', 'SYNR001', '20', 'no_board_vehicle']);
  assert.equal(out.snapshot.header.snapshot_sha256, SHA);
  assert.equal(out.snapshot.header.line_count, 17);
});

test('the identity rules match the Python r479 fixtures', async () => {
  const { resolveRo, boardIndex } = await load();
  const v = (i, stock, jc = null, ls = 'active', deleted = false) => ({ id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, stock, jc, ls, deleted });
  const idx = boardIndex({
    vehicles: [v(1, 'SYN0001'), v(2, 'SYN0002', 'J139900002'), v(3, 'SYN-RG03'), v(4, 'SYN0004', null, 'completed'), v(5, 'SYN0005'), v(6, 'SYN0005B'),
      v(7, 'SYN0007', null, 'rft'), v(8, 'SYN0008', null, 'active', true), v(9, 'SYN0009'), v(10, 'SYN0010')],
    jobs: [{ vehicle_id: v(9).id, ro: 'J139900009' }, { vehicle_id: v(1).id, ro: 'J139900001' }],
  });
  assert.equal(resolveRo('J139900001', ' syn0001 ', null, idx).status, 'linked');
  assert.equal(resolveRo('J139900001', 'SYN000', null, idx).reason, 'stock_not_on_board');
  assert.equal(resolveRo('J139900002', 'SYN9999', 'SYN0001', idx).status, 'no_board_vehicle');
  assert.equal(resolveRo('J139900003', null, 'SYN-RG03', idx).basis, 'rego_column_exact_board_stock');
  assert.equal(resolveRo('J139900002', '', 'NOTONBOARD', idx).basis, 'job_card_exact');
  assert.equal(resolveRo('J139900009', '', null, idx).basis, 'job_card_service_job');
  assert.equal(resolveRo('J139900077', '', 'NOTONBOARD', idx).reason, 'rego_not_a_board_stock_and_no_job_card');
  assert.equal(resolveRo('J139900078', '', '', idx).reason, 'no_stock_no_rego_no_job_card');
  assert.equal(resolveRo('J139900078', '', '', idx).send, false);
  assert.deepEqual(resolveRo('J139900008', 'SYN0008', null, idx).board_states, ['deleted']);
  assert.equal(resolveRo('J139900007', 'SYN0007', null, idx).status, 'linked');
  assert.equal(resolveRo('J139900002', '', 'SYN0005', idx).status, 'ambiguous');
});

test('routing and every Craig hour default (139), with the tint and spare exceptions on 138', async () => {
  const { propose } = await load();
  const p = (d, dept = '139', h = 0) => propose(d, h, 'REVIEW', dept);
  const cases = [
    ['MINE BAR', 'ELECTRICAL', 1.5, 'craig_electrical_default_1_5_hours'],
    ['7\' STEDI EVO SPOTLIGHTS', 'ELECTRICAL', 1.5, 'craig_electrical_default_1_5_hours'],
    ['HEADLAMPS AUTO ON', 'ELECTRICAL', 1.5, 'craig_electrical_default_1_5_hours'],
    ['RYCO CATCH CAN KIT', 'FITTING', 1.5, 'craig_ryco_catch_can_default_1_5_hours'],
    ['ADDITIONAL GENUINE ALLOY RIM', 'FABRICATION', 0.5, 'craig_additional_rim_default_0_5_hours'],
    ['TIE DOWN POINTS IN FLOOR X 4', 'FABRICATION', 4, 'craig_floor_tie_down_1_hour_each'],
    ['PMB STEEL TRAY', 'FABRICATION', 2, 'craig_steel_tray_default_2_hours'],
    ['CERTIFIED MESH CAB RACK BARRIER', 'FABRICATION', 0.5, 'craig_mesh_cab_rack_default_0_5_hours'],
    ['SPARE WHEEL HOLDER ON PMB CAB RACK', 'FABRICATION', 0.5, 'craig_tyre_holder_default_0_5_hours'],
    ['DARKEST LEGAL WINDOW TINT', 'TINT', 1, 'craig_tint_default_1_hour'],
    ['ADDITIONAL SPARE RIM - BROOME TO SUPPLY', 'TYRE', 0.17, 'craig_additional_spare_ten_minutes'],
    ['2ND SPARE ALLOY RIM', 'TYRE', 0.17, 'craig_additional_spare_ten_minutes'],
    ['4 X TYRES', 'TYRE', 1, 'craig_tyres_default_1_hour'],
    ['5 X BFG KO3 A/T TYRES', 'TYRE', 1, 'craig_tyres_default_1_hour'],
    ['GVM UPGRADE', 'HOIST', 5, 'craig_suspension_department_139_default_5_hours'],
    ['AIR BAG RAISED REAR SUSPENSION', 'HOIST', 5, 'craig_suspension_department_139_default_5_hours'],
    ['OME 3550KG GVM', 'HOIST', 5, 'craig_suspension_department_139_default_5_hours'],
  ];
  for (const [d, station, hours, prov] of cases) {
    const x = p(d);
    assert.equal(x.proposed_station, station, d);
    assert.equal(x.effective_estimated_hours, hours, d);
    assert.equal(x.hours_provenance, prov, d);
    assert.equal(x.needs_hours_review, false, d);
    assert.equal(x.routing_provenance, 'explicit_owner_rule', d);
    assert.equal(x.routing_rule_version, 'craig_work_categories_20260917_tint', d);
  }
  for (const [d, station, rule] of [['ARB LONG RANGE FUEL TANK', 'HOIST', 'accessory_long_range_tank_20260914'], ['WHEEL CHOCKS', 'FITTING', 'wheel_chocks_fitting'],
    ['WEATHER SHIELDS', 'FITTING', 'bonnet_protectors_weather_shields_fitting'], ['BONNET PROTECTOR', 'FITTING', 'bonnet_protectors_weather_shields_fitting'],
    ['SAFETY TRIANGLES AND HOLDER', 'FABRICATION', 'mounted_triangle_holder_fabrication'], ['BLACK DUCK CANVAS SEAT COVERS', 'FITTING', 'accessory_seat_covers_fitting_20260914'],
    ['COMPLEMENTARY FULL TANK OF FUEL', 'FITTING', 'preparation_fitting'], ['HI DRIVE CANOPY', 'SUBLET', 'canopy_body_builder']]) {
    const x = p(d);
    assert.equal(x.proposed_station, station, d);
    assert.equal(x.routing_rule, rule, d);
  }
  assert.equal(p('HI DRIVE CANOPY').needs_hours_review, false);
  const plain = p('Synthetic operation');
  assert.deepEqual([plain.proposed_station, plain.routing_rule, plain.routing_provenance, plain.needs_hours_review], ['REVIEW', null, 'existing_default', true]);
  // Explicit description time wins; two different times are a review.
  assert.deepEqual([p('MINE BAR 2 HRS').effective_estimated_hours, p('MINE BAR 2 HRS').hours_provenance], [2, 'explicit_description_time']);
  assert.deepEqual([p('MINE BAR 30 MINS').effective_estimated_hours, p('MINE BAR 30 MINS').hours_provenance], [0.5, 'explicit_description_time']);
  const conflicting = p('MINE BAR 1 HR OR 90 MINS');
  assert.deepEqual([conflicting.effective_estimated_hours, conflicting.hours_provenance, conflicting.needs_hours_review], [null, 'conflicting_description_times', true]);
  // Source hours are kept; a default only fills a zero or blank.
  assert.deepEqual([p('MINE BAR', '139', 3).effective_estimated_hours, p('MINE BAR', '139', 3).hours_provenance], [3, 'source_estimate']);
  assert.equal(p('DARKEST LEGAL WINDOW TINT', '139', null).effective_estimated_hours, 1);
  // Department 138: Bus 4x4 only, tint excepted; the additional spare keeps its 10 minutes.
  const tint138 = p('DARKEST LEGAL WINDOW TINT', '138');
  assert.deepEqual([tint138.proposed_station, tint138.routing_rule, tint138.effective_estimated_hours, tint138.hours_provenance], ['TINT', 'department_138_tint_exception', 1, 'craig_tint_default_1_hour']);
  const spare138 = p('2ND SPARE ALLOY RIM', '138');
  assert.deepEqual([spare138.proposed_station, spare138.routing_rule, spare138.effective_estimated_hours], ['BUS_4X4', 'department_138_exclusive_bus4x4', 0.17]);
  for (const d of ['MINE BAR', 'SUPPLY ONLY MMT SYNTHETIC', 'GVM UPGRADE', '4 X TYRES']) {
    const x = p(d, '138');
    assert.deepEqual([x.proposed_station, x.routing_rule, x.routing_provenance], ['BUS_4X4', 'department_138_exclusive_bus4x4', 'explicit_owner_rule'], d);
  }
  assert.equal(p('BONNET PROTECTOR TINTED').proposed_station, 'FITTING');
});

test('a fallback line that still needs ARB research is held in needsHours, not sent', async () => {
  const out = await build([
    line({ dept: 138, ro: 'J138000420', stock: 'SYN0001', desc: 'SUPPLY ONLY MMT SYNTHETIC', hours: 0 }),
    line({ dept: 138, ro: 'J138000420', stock: 'SYN0001', line: 2, desc: 'DARKEST LEGAL WINDOW TINT', hours: 0 }),
    line({ dept: 138, ro: 'J138000420', stock: 'SYN0001', line: 3, desc: 'BULL BAR', hours: 4 }),
    line({ ro: 'J139900001', line: 4, desc: 'HI DRIVE CANOPY', hours: 0 }),
    line({ ro: 'J139900001', line: 5, desc: 'COMPLEMENTARY FULL TANK OF FUEL', hours: 0 }),
  ]);
  assert.deepEqual(out.rows.map((r) => [r.repair_order_number, r.original_line_number, r.proposed_station, r.effective_estimated_hours, r.hours_provenance]), [
    ['J138000420', 2, 'TINT', 1, 'craig_tint_default_1_hour'],
    ['J138000420', 3, 'BUS_4X4', 4, 'source_estimate'],
    ['J139900001', 4, 'SUBLET', 0, 'source_estimate'],
  ]);
  assert.deepEqual(out.needsHours, [
    { department: '138', stock: 'SYN0001', ro: 'J138000420', line: 1, description: 'SUPPLY ONLY MMT SYNTHETIC', station: 'BUS_4X4', routing_rule: 'department_138_exclusive_bus4x4', reason: 'arb_review_required' },
    { department: '139', stock: 'SYN0001', ro: 'J139900001', line: 5, description: 'COMPLEMENTARY FULL TANK OF FUEL', station: 'FITTING', routing_rule: 'preparation_fitting', reason: 'arb_review_required' },
  ]);
  assert.equal(out.summary.needs_hours, 2);
  assert.equal(out.rows.some((r) => 'arb_review' in r), false);
});

const UNABLE = {
  checked: true, status: 'unable', guide_version: 'DRT20260901.1', guide_sha256: '4e1a8c9cd5f317d1a9b28fbf0c9448f1b33a33651e4dff8507e9947a157c46c6',
  searched_terms: ['MMT'], match_basis: 'Supply only part; no fitting labour in the guide', reason: 'Supply-only item with no published fitting labour',
  unable_reason_code: 'no_published_labour', reviewed_candidates: [], vehicle_context: { source: 'unique_current_exact_stock_navision', model: 'HiLux' },
};

test('priorDecisions: a line Kajel already decided reuses that decision verbatim', async () => {
  const { descriptionKey } = await load();
  const decision = { proposed_station: 'BUS_4X4', routing_rule: 'department_138_exclusive_bus4x4', routing_provenance: 'explicit_owner_rule',
    routing_rule_version: 'craig_work_categories_20260917_tint', hours_provenance: 'estimate_unable', effective_estimated_hours: 0, needs_hours_review: true, arb_review: UNABLE };
  const tyres = { proposed_station: 'TYRE', routing_rule: 'accessory_tyres_20260914', routing_provenance: 'explicit_owner_rule',
    routing_rule_version: 'craig_work_categories_20260917_tint', hours_provenance: 'craig_tyres_default_1_hour', effective_estimated_hours: 1, needs_hours_review: false };
  const priorDecisions = { [descriptionKey('138', 'supply  only MMT synthetic ')]: decision, [descriptionKey('139', '4 X TYRES')]: tyres };
  assert.equal(descriptionKey(138, ' supply only   mmt '), '138|SUPPLY ONLY MMT');
  const out = await build([
    line({ dept: 138, ro: 'J138000420', stock: 'SYN0001', desc: 'SUPPLY ONLY MMT SYNTHETIC', hours: 0, po: 'GP13801580', sublet: 'MMT synthetic sublet' }),
    line({ ro: 'J139900001', line: 2, desc: '4 X TYRES', hours: 0 }),
    line({ ro: 'J139900001', line: 3, desc: '4 X TYRES', hours: 2.5 }),
    line({ ro: 'J139900001', line: 4, desc: 'SUPPLY ONLY MMT SYNTHETIC', hours: 0 }),
  ], { options: { priorDecisions } });
  const [mmt, t0, t25] = out.rows;
  assert.equal(out.rows.length, 3);
  assert.deepEqual(mmt.arb_review, UNABLE);
  assert.deepEqual(mmt.raw_row.arb_review, UNABLE);
  assert.deepEqual([mmt.proposed_station, mmt.routing_rule, mmt.routing_provenance, mmt.routing_rule_version, mmt.hours_provenance, mmt.effective_estimated_hours, mmt.needs_hours_review],
    ['BUS_4X4', 'department_138_exclusive_bus4x4', 'explicit_owner_rule', 'craig_work_categories_20260917_tint', 'estimate_unable', 0, true]);
  assert.deepEqual([t0.proposed_station, t0.effective_estimated_hours, t0.hours_provenance, 'arb_review' in t0], ['TYRE', 1, 'craig_tyres_default_1_hour', false]);
  assert.deepEqual([t25.proposed_station, t25.routing_rule, t25.effective_estimated_hours, t25.hours_provenance, t25.needs_hours_review], ['TYRE', 'accessory_tyres_20260914', 2.5, 'source_estimate', false]);
  // The key includes the department: the 139 line with the same text is not Kajel's 138 decision.
  assert.deepEqual(out.needsHours.map((h) => [h.ro, h.line]), [['J139900001', 4]]);
  assert.equal(out.summary.prior_decisions_used, 3);
  // A prior review that does not pass the ARB contract is not sent.
  const broken = await build([line({ dept: 138, ro: 'J138000420', desc: 'SUPPLY ONLY MMT SYNTHETIC', hours: 0 })],
    { options: { priorDecisions: { [descriptionKey('138', 'SUPPLY ONLY MMT SYNTHETIC')]: { ...decision, arb_review: { ...UNABLE, unable_reason_code: 'nope' } } } } });
  assert.equal(broken.rows.length, 0);
  assert.equal(broken.needsHours[0].reason, 'prior_review_not_valid');
});

test('row shape: Kajel fields, website delivery and upload, no email fields', async () => {
  const { EMAIL_FIELDS, descriptionKey } = await load();
  const decision = { proposed_station: 'BUS_4X4', routing_rule: 'department_138_exclusive_bus4x4', routing_provenance: 'explicit_owner_rule',
    routing_rule_version: 'craig_work_categories_20260917_tint', hours_provenance: 'estimate_unable', effective_estimated_hours: 0, needs_hours_review: true, arb_review: UNABLE };
  const out = await build([line({ dept: 138, ro: 'J138000420', stock: 10903647, rego: '1SYN452', desc: 'SUPPLY ONLY MMT SYNTHETIC', hours: 0, po: 'GP13801580', sublet: 'Synthetic sublet' })],
    { board: { vehicles: [veh(1, '10903647')], jobs: [] }, options: { priorDecisions: { [descriptionKey('138', 'SUPPLY ONLY MMT SYNTHETIC')]: decision } } });
  const [row] = out.rows;
  assert.deepEqual(Object.keys(row), ['department', 'stock_number', 'repair_order_number', 'original_line_number', 'operation_description', 'operation_code',
    'source_estimated_hours', 'effective_estimated_hours', 'hours_provenance', 'needs_hours_review', 'proposed_station', 'routing_rule', 'routing_provenance',
    'routing_rule_version', 'arb_review', 'workbook_sha256', 'vehicle_context', 'raw_row']);
  assert.deepEqual([row.department, row.stock_number, row.repair_order_number, row.original_line_number, row.operation_code, row.workbook_sha256],
    ['138', '10903647', 'J138000420', 1, null, SHA]);
  const raw = row.raw_row;
  assert.equal(raw.Dept, 138);
  assert.equal(raw['Stock #'], 10903647);
  assert.deepEqual([raw.Company, raw.Division], ['01', '1']);
  assert.equal(raw.source_kind, 'revolution_automated_service_workbook');
  assert.equal(raw.delivery, 'website_admin_upload_728');
  assert.deepEqual(raw.upload, { uploader_email: 'admin@example.test', upload_id: 'upl-728-1', uploaded_at: '2026-10-29T05:30:00+00:00' });
  assert.equal(raw.email_subject, 'PMG PD Service as a Whole w/Sublet');
  assert.equal(raw.source_filename, UPLOAD.filename);
  assert.equal(raw.snapshot_sha256, SHA);
  assert.equal(raw.snapshot_scope, 'full_open_ro_snapshot_r479');
  assert.equal(raw.source_report_parameters, PARAMS);
  assert.equal(raw.source_snapshot_at, UPLOAD.uploaded_at);
  assert.equal(raw.classifier_version, 'craig_work_categories_20260917_tint');
  assert.equal(raw.source_sheet, 'Results');
  assert.equal(raw.scope_provenance, 'Original worksheet extraction parameters');
  assert.equal(raw.rolling_changed_records, false);
  assert.deepEqual(raw.identity_r479, { rule: 'r479_exact_board_stock_or_job_card', basis: 'stock_column', file_rego: '1SYN452', file_stock: '10903647' });
  for (const field of EMAIL_FIELDS) {
    assert.equal(field in raw, false, field);
    assert.equal(field in row, false, field);
  }
  assert.equal(JSON.stringify(out).includes('gmail'), false);
  assert.equal(JSON.stringify(out).includes('website_admin_upload_728'), true);
});

test('ARB checkpoint: catalogue estimate, Unable contract and tolerance (pmb_arb_estimates tests)', async () => {
  const { catalogueEstimate, validate, GUIDE_VERSION, GUIDE_SHA256 } = await load();
  const guide = { guide_version: GUIDE_VERSION, guide_sha256: GUIDE_SHA256, pages: [{ page: 56, text: 'SS223HF 320.00 SS223HP 400.00' }] };
  const row = (o = {}) => ({ operation_description: 'Safari Snorkel', source_estimated_hours: 0, effective_estimated_hours: 0, proposed_station: 'FITTING', hours_provenance: 'source_explicit',
    vehicle_context: { source: 'unique_current_exact_stock_navision', vehicle: 'HiLux WorkMate', production_month: '06/26' }, ...o });
  assert.equal(catalogueEstimate(row(), guide).estimated_hours, 2.25);
  assert.equal(catalogueEstimate(row({ operation_description: 'Safari Snorkel V-Spec' }), guide).estimated_hours, 2);
  assert.equal(catalogueEstimate(row({ operation_description: 'Safari Snorkel ARMAX' }), guide).estimated_hours, 2.5);
  assert.equal(JSON.stringify(catalogueEstimate(row(), guide)).includes('320.00 SS223HP'), false);
  assert.equal(catalogueEstimate(row(), null), null);
  for (const ctx of [{}, { source: 'email_received_date', vehicle: 'HiLux', production_month: '06/26' }, { source: 'unique_current_exact_stock_navision', vehicle: 'HiLux', production_month: '06/24' }]) {
    assert.equal(catalogueEstimate(row({ vehicle_context: ctx }), guide), null);
  }
  assert.equal(catalogueEstimate(row({ operation_description: 'Snorkel and winch kit' }), guide), null);
  const est = catalogueEstimate(row(), guide);
  assert.equal(validate(row({ arb_review: est, effective_estimated_hours: 2.25, hours_provenance: 'ai_estimated' })), true);
  assert.equal(validate(row({ arb_review: est, effective_estimated_hours: 4, hours_provenance: 'ai_estimated' })), false);
  const generic = { status: 'unable', checked: true, guide_version: GUIDE_VERSION, guide_sha256: GUIDE_SHA256, searched_terms: ['custom'], match_basis: 'Searched the guide for this description', reason: 'No comparable catalogue fitting allowance' };
  assert.equal(validate(row({ operation_description: 'Custom kit', arb_review: generic })), false);
  const interpreted = { ...generic, match_basis: 'Custom fabrication has no matching manufactured kit', reason: 'One-off tray fabrication drawing and scope required', unable_reason_code: 'unsupported_product', reviewed_candidates: [], vehicle_context: { source: 'source_report', model: 'Unknown' } };
  assert.equal(validate(row({ operation_description: 'Custom kit', arb_review: interpreted })), true);
  for (const patch of [{ source_estimated_hours: 3 }, { staff_hours: 0 }, { proposed_station: 'SUBLET' }, { hours_provenance: 'craig_special', effective_estimated_hours: 4 }, { hours_provenance: 'explicit_description_time', effective_estimated_hours: 1 }]) {
    assert.equal(validate(row(patch)), true);
  }
  assert.equal(validate(row()), false);
  // Through buildServiceRows: a Navision-context HiLux snorkel is estimated from the installed guide, not held.
  const { buildServiceRows } = await load();
  const out = buildServiceRows({ grid: grid([line({ desc: 'SAFARI SNORKEL', hours: 0 })]), board: BOARD, upload: UPLOAD, arbGuide: guide,
    vehicleContexts: { SYN0001: { source: 'unique_current_exact_stock_navision', vehicle: 'HiLux SR5', production_month: '03/26' } } });
  assert.equal(out.needsHours.length, 0);
  assert.deepEqual([out.rows[0].effective_estimated_hours, out.rows[0].hours_provenance, out.rows[0].arb_review.status], [2.25, 'ai_estimated', 'estimated']);
});

test('reviewed workshop standard fills a Dept 138 zero-hour line from the registry', async () => {
  const registry = { version: 'syn-1', rules: [{ id: 'std-1', department: '138', model: 'HILUX SR5', description: 'SYNTHETIC BUS WORK', stage: 'BUS_4X4', hours: 3, source: 'craig', evidence: 'synthetic' }] };
  const out = await build([line({ dept: 138, ro: 'J138000001', desc: 'Synthetic bus work', hours: 0 })], {
    options: { standards: registry, vehicleContexts: { SYN0001: { source: 'unique_current_exact_stock_navision', vehicle: 'HiLux SR5' } } } });
  assert.equal(out.needsHours.length, 0);
  assert.deepEqual([out.rows[0].effective_estimated_hours, out.rows[0].hours_provenance, out.rows[0].workshop_standard.standard_id, out.rows[0].raw_row.workshop_standard.standard_id],
    [3, 'craig_workshop_manager_standard', 'std-1', 'std-1']);
});

test('file QC guard is the same gate apply uses', async () => {
  const { fileQcGuard, SNAPSHOT_SCOPE } = await load();
  assert.deepEqual(fileQcGuard(6751, 465, true, 6731, 'a.xlsx', SNAPSHOT_SCOPE), { ok: true, reason: 'complete_file' });
  assert.equal(fileQcGuard(0, 0, true, 6731, 'a.xlsx', SNAPSHOT_SCOPE).reason, 'empty_file');
  assert.equal(fileQcGuard(6751, 465, false, 6731, 'a.xlsx', SNAPSHOT_SCOPE).reason, 'partial_file');
  assert.equal(fileQcGuard(500, 50, true, 6731, 'a.xlsx', SNAPSHOT_SCOPE).reason, 'below_minimum_size');
  assert.equal(fileQcGuard(2000, 200, true, 6731, 'a.xlsx', SNAPSHOT_SCOPE).reason, 'partial_vs_previous');
  assert.equal(fileQcGuard(6751, 465, true, null, 'a.xlsx', SNAPSHOT_SCOPE).reason, 'no_previous_complete_snapshot');
  assert.equal(fileQcGuard(6751, 465, true, 6731, 'a.xlsx', 'other').reason, 'not_full_snapshot');
  const small = await build([line()]);
  assert.deepEqual(small.qc, { ok: false, reason: 'below_minimum_size' });
});

test('end to end from an uploaded HTML workbook through parse.js', async () => {
  const { parseRevolutionUpload, readSheet } = await parser();
  const { buildServiceRows } = await load();
  const rows = [[TITLE], [PARAMS], [], [...HEADERS, 'Create Advisor'].map((h) => `="${h}"`),
    line({ po: 'GP13990001', sublet: 'Sublet A' }), line({ po: 'GP13990002', sublet: 'Sublet B' }), line({ line: 2, desc: 'DARKEST LEGAL WINDOW TINT', hours: 0 }),
    line({ dept: 140, ro: 'J140000001' })];
  const html = `<table>${rows.map((r) => `<tr>${r.map((c) => `<td>${c == null ? '' : String(c).replace(/&/g, '&amp;').replace(/</g, '&lt;')}</td>`).join('')}</tr>`).join('')}</table>`;
  const bytes = new TextEncoder().encode(html);
  const parsed = await parseRevolutionUpload(bytes, UPLOAD.filename);
  const gridRead = await readSheet(bytes);
  const out = buildServiceRows({ grid: gridRead, parsed, board: BOARD, upload: { ...UPLOAD, sha256: parsed.sha256 } });
  assert.equal(out.rows.length, 2);
  assert.deepEqual(out.rows[0].raw_row.sublet_pos, ['GP13990001', 'GP13990002']);
  assert.equal(out.rows[1].proposed_station, 'TINT');
  assert.equal(out.summary.excluded_department_rows, 1);
  assert.equal(out.rows[0].workbook_sha256, parsed.sha256);
});

test('r728 wiring: server RPCs, edge Apply, page Apply (no faked email)', () => {
  const fs = require('fs');
  const sql = fs.readFileSync('supabase/migrations/20261029200000_r728_website_service_upload.sql', 'utf8');
  assert.match(sql, /CREATE TABLE pdc_import_620\.web_uploads_728/);
  assert.match(sql, /IF v_role <> 'administrator' OR v_uid IS NULL OR v_email = '' THEN RETURN/);
  assert.match(sql, /pdc_import_620\.web_upload_row_ok_728\(x\) IS NOT TRUE AND \(x->'raw_row'->>'from_address' IS DISTINCT FROM 'noreply@revolutionsoftware\.com\.au'/);
  assert.match(sql, /REVOKE ALL ON FUNCTION public\.revolution_prior_decisions_728\(\) FROM authenticated;/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.match(sql, /'filename', btrim\(p_filename\),\n    'provenance', jsonb_build_object\('source_kind', 'website_admin_upload_728'/, 'the envelope carries no message id');
  const edge = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');
  assert.match(edge, /if \(action === 'apply'\) return await applyService\(/);
  assert.match(edge, /if \(parsed\.kind !== 'service_whole'\) return refuse\(/);
  assert.match(edge, /rpcAs\(projectUrl, auth, 'revolution_upload_begin_728'/);
  const page = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(page, /apply\.disabled = !\(payload\.apply_enabled === true/);
  assert.match(page, /revolution_upload_status_728/);
});
