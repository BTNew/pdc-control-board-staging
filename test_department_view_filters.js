'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const helperSource = fs.readFileSync(path.join(__dirname, 'pdc-department-filter.js'), 'utf8');
const appSource = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service');
const plain = value => JSON.parse(JSON.stringify(value));

function preference(initial = null, brokenStorage = false) {
  const writes = [], events = [], listeners = new Map();
  const values = new Map(initial == null ? [] : [['pdc_department_view_filter_v1', initial]]);
  const browser = {
    localStorage: {
      getItem: key => { if (brokenStorage) throw new Error('storage denied'); return values.get(key) ?? null; },
      setItem: (key, value) => { if (brokenStorage) throw new Error('storage denied'); writes.push([key, value]); values.set(key, value); },
    },
    CustomEvent: class { constructor(type, options) { this.type = type; this.detail = options.detail; } },
    addEventListener: (name, fn) => listeners.set(name, fn),
    dispatchEvent: event => { events.push(event); return true; },
  };
  const context = vm.createContext({ window: browser, module: { exports: {} } });
  vm.runInContext(helperSource, context);
  return { api: context.module.exports, writes, events, values, browser,
    storage: event => listeners.get('storage')?.(event) };
}
const api = preference().api;
const source = (department, extra = {}) => ({ department, active: true, ...extra });

test('uncapped server membership outranks truncated source lines and misleading vehicle fields', () => {
  const row = Object.freeze({ department_codes: Object.freeze(['139', '138', '138', ' 137 ']), pdcDepartmentCodes: ['139'],
    operations: [source('139')], pdcQcOperationLines: [source('139')], pdcDepartmentCode: '139' });
  assert.deepEqual(plain(api.departmentCodes(row)), ['137', '138', '139']);
  assert.equal(api.matches(row, '138'), true);
  assert.equal(api.matches(row, '139'), true);
});

test('an authoritative empty membership or canonical projection never resurrects historical departments', () => {
  const legacy = { department: '139', pdcEmailOperationLines: [source('139')], operation_lines: [source('139')] };
  for (const row of [
    { ...legacy, department_codes: [] },
    { ...legacy, pdcDepartmentCodes: [] },
    { ...legacy, operations: [] },
    { ...legacy, qc_operation_lines: [] },
    { ...legacy, pdcQcOperationLinesProjectionPresent: true, pdcQcOperationLines: [] },
    { ...legacy, pdcQcOperationLinesProjectionPresent: true },
  ]) {
    assert.deepEqual(plain(api.departmentCodes(row)), []);
    assert.equal(api.matches(row, '139'), false);
    assert.equal(api.matches(row, ''), true);
  }
});

test('only active imported memberships count; completed work retains its department', () => {
  const row = { operations: [
    source('138', { completed: true }), source('139', { active: false }),
    source('139', { deleted_at: '2026-09-19' }), source('139', { is_deleted: true }),
    source(' 138 '), source('bad'), null,
  ] };
  assert.deepEqual(plain(api.departmentCodes(row)), ['138']);
  assert.equal(api.matches(row, '138'), true);
  assert.equal(api.matches(row, '139'), false);
});

test('mixed department vehicles belong to both relevant filtered views without duplication', () => {
  const rows = [
    { id: 'mixed', operations: [source('138'), source('139'), source('138')] },
    { id: 'bus', operations: [source('138')] },
    { id: 'pd', operations: [source('139')] },
    { id: 'unknown', operations: [source('')] },
  ];
  assert.deepEqual(rows.filter(row => api.matches(row, '138')).map(row => row.id), ['mixed', 'bus']);
  assert.deepEqual(rows.filter(row => api.matches(row, '139')).map(row => row.id), ['mixed', 'pd']);
  assert.equal(rows.filter(row => api.matches(row, '')).length, 4);
});

test('Tint, Fitting and Bus 4x4 station names do not invent source departments', () => {
  for (const stage of ['TINT', 'FITTING', 'BUS_4X4', 'FABRICATION']) {
    const row = { operations: [{ stage_code: stage, work_key: stage.toLowerCase(), active: true }], pmbStage: stage };
    assert.deepEqual(plain(api.departmentCodes(row)), []);
    assert.equal(api.matches(row, '138'), false);
    assert.equal(api.matches(row, '139'), false);
    assert.equal(api.matches(row, ''), true);
  }
});

test('explicit legacy department fields are used only when no line or server authority exists', () => {
  assert.deepEqual(plain(api.departmentCodes({ pdcDepartmentCode: '138', departmentCode: '139' })), ['138', '139']);
  assert.deepEqual(plain(api.departmentCodes({ department: 138 })), ['138']);
  assert.deepEqual(plain(api.departmentCodes({ department: 'Bus 4x4' })), []);
  assert.deepEqual(plain(api.departmentCodes({ department: '139', pdcEmailOperationLines: [source('138')] })), ['138']);
  assert.deepEqual(plain(api.departmentCodes({ department: '139', pdcQcOperationLinesProjectionPresent: true,
    pdcQcOperationLines: [source('138')], pdcEmailOperationLines: [source('139')] })), ['138']);
});

test('preference loads, persists changes once and sends one shared-view event', () => {
  const f = preference('138');
  assert.equal(f.api.getSelection(), '138');
  assert.equal(f.api.setSelection(' 139 '), '139');
  assert.equal(f.api.getSelection(), '139');
  assert.deepEqual(f.writes, [['pdc_department_view_filter_v1', '139']]);
  assert.deepEqual(f.events.map(event => [event.type, event.detail.department]), [['pdc-department-filter-changed', '139']]);
  f.api.setSelection('139');
  assert.equal(f.events.length, 1);
  assert.equal(f.writes.length, 1);
  f.api.setSelection('');
  assert.equal(f.events[1].detail.department, '');
});

test('blocked browser storage does not prevent an in-memory filter or its change event', () => {
  const f = preference(null, true);
  assert.equal(f.api.getSelection(), '');
  assert.doesNotThrow(() => f.api.setSelection('138'));
  assert.equal(f.api.getSelection(), '138');
  assert.equal(f.events.length, 1);
  assert.equal(f.events[0].detail.department, '138');
});

test('cross-tab storage updates synchronize these views without storage write loops', () => {
  const f = preference('139');
  f.storage({ key: 'unrelated_setting', newValue: '138' });
  assert.equal(f.api.getSelection(), '139');
  f.storage({ key: 'pdc_department_view_filter_v1', newValue: '138' });
  assert.equal(f.api.getSelection(), '138');
  assert.equal(f.events.length, 1);
  assert.equal(f.writes.length, 0);
  f.storage({ key: 'pdc_department_view_filter_v1', newValue: '138' });
  assert.equal(f.events.length, 1);
  f.storage({ key: null, newValue: null });
  assert.equal(f.api.getSelection(), '');
  assert.equal(f.events.length, 2);
  assert.equal(f.writes.length, 0);
});

test('unknown persisted values select All rather than applying an unsupported hidden scope', () => {
  const f = preference('137');
  assert.equal(f.api.getSelection(), '');
  assert.equal(f.api.normalize('garbage'), '');
  assert.equal(f.api.normalize('138'), '138');
  assert.equal(f.api.normalize(139), '139');
  assert.equal(f.api.matches({ department_codes: ['137'] }, '137'), true);
});

function serverVehicle(extra = {}) {
  return { id: '10000000-0000-4000-8000-000000000001', stock_number: 'QA-DEPARTMENT', version: 1,
    current_location: 'PMB', visible_on_board: true, ...extra };
}
function operation(index, department = '139') {
  const id = '20000000-0000-4000-8000-' + String(index + 1).padStart(12, '0');
  return { operation_line_id: id, source_line_id: id, line_identity: 'source:' + id, department,
    operation_no: 'OP' + (index + 1), work_key: 'fitting', stage_code: 'FITTING',
    source_kind: 'authenticated', description: 'Synthetic work ' + index, active: true };
}

test('mapper preserves full server departments when matching work lies beyond both display caps', () => {
  const operations = Array.from({ length: 251 }, (_, index) => operation(index, index === 250 ? '138' : '139'));
  const mapped = mapServerVehicle(serverVehicle({ operation_lines: operations, qc_operation_lines: operations,
    department_codes: ['138', '139'], has_unknown_department: false }));
  assert.equal(mapped.pdcEmailOperationLines.length, 50);
  assert.equal(mapped.pdcQcOperationLines.length, 250);
  assert.equal(mapped.pdcQcOperationLines.some(line => line.department === '138'), false);
  assert.deepEqual(mapped.pdcDepartmentCodes, ['138', '139']);
  assert.equal(api.matches(mapped, '138'), true);
  assert.equal(api.matches(mapped, '139'), true);
});

test('mapper distinguishes authoritative empty department membership from absent metadata', () => {
  const historical = [operation(0, '139')];
  const empty = mapServerVehicle(serverVehicle({ department_codes: [], operation_lines: historical, qc_operation_lines: historical }));
  assert.ok(Object.prototype.hasOwnProperty.call(empty, 'pdcDepartmentCodes'));
  assert.deepEqual(empty.pdcDepartmentCodes, []);
  assert.equal(api.matches(empty, '139'), false);
  const legacy = mapServerVehicle(serverVehicle({ operation_lines: historical }));
  assert.equal(Object.prototype.hasOwnProperty.call(legacy, 'pdcDepartmentCodes'), false);
  assert.equal(api.matches(legacy, '139'), true);
});

function appFunction(name) {
  const start = appSource.search(new RegExp('^(?:async )?function ' + name + '\\(', 'm'));
  assert.ok(start >= 0, name + ' is present');
  const rest = appSource.slice(start);
  const next = rest.slice(1).search(/^(?:async )?function /m);
  return next < 0 ? rest : rest.slice(0, next + 1);
}

function locationsFixture(initial = '138') {
  const pref = preference(initial);
  const rows = [
    { id: 'bus', stock: 'BUS-1', pdcDepartmentCodes: ['138'], bucket: 'pmb', status: 'PMB', rep: 'Alice', work: ['tint'] },
    { id: 'pd', stock: 'PD-1', pdcDepartmentCodes: ['139'], bucket: 'pmb', status: 'PMB', rep: 'Bob', work: ['fitting'] },
    { id: 'mixed', stock: 'MIX-1', pdcDepartmentCodes: ['138', '139'], bucket: 'pmb', status: 'PMB', rep: 'Alice', work: ['fitting'] },
    { id: 'unknown', stock: 'UNK-1', pdcDepartmentCodes: [], bucket: 'yardhold', status: 'YH', rep: 'Bob', work: [] },
  ];
  const controls = new Map(['incoming-search', 'incoming-status-filter', 'incoming-bucket-filter',
    'incoming-rep-filter', 'incoming-department-filter', 'incoming-filter-summary']
    .map(id => ['#' + id, { value: '', textContent: '' }]));
  const host = { innerHTML: '' };
  controls.set('#incoming-main-board', host);
  const workChecks = [{ value: 'tint', checked: false }, { value: 'fitting', checked: false }];
  const priority = rows.map(vehicle => ({ vehicle, label: vehicle.id + ' STOPPAGE' }));
  let renderCalls = 0;
  const c = {
    window: { PDC_DEPARTMENT_FILTER: pref.api, requestAnimationFrame: () => {} },
    app: { currentView: 'dashboard', selectedRows: new Set(['bus', 'pd', 'mixed', 'unknown']),
      singleSearchFocus: { incoming: 'old' }, data: rows, vehicleLocationsRefreshState: 'idle', incomingDashboardSort: {} },
    $: selector => controls.get(selector) || null,
    $$: selector => selector === 'input[name="incoming-work-filter"]' ? workChecks : [],
    vehicleKey: row => row.id,
    vehicleLocationBoardRows: () => rows,
    vehicleCollectedFromRft: () => false, vehicleInCollectedState: () => false,
    incomingBucketForVehicle: row => row.bucket,
    incomingSearchText: row => row.stock.toLowerCase(),
    navisionStatusText: row => row.status, pdcLocationLabel: value => value,
    vehiclePdcLocation: row => row.status, consultantName: row => row.rep,
    incomingWorkFilterMatches: (row, key) => row.work.includes(key),
    workflowPriorityRows: () => priority,
    renderIncomingDashboardBoard: () => { renderCalls++; },
    captureIncomingBoardDisclosureState: () => ({}),
    ensureDashboardWorkshopProjectionReady: () => false,
    sharedNavisionLocationAuthorityReady: () => true,
    updateIncomingDashboardFilterOptions: () => {},
    updateIncomingMoreFiltersState: () => {},
    VEHICLE_LOCATION_BUCKET_DEFS: [{ key: 'pmb', label: 'PMB', hint: 'Synthetic PMB', open: true },
      { key: 'yardhold', label: 'Yard Hold', hint: 'Synthetic YH', open: true }],
    incomingBucketLabel: value => value,
    fixFirstRowsHtml: rows => rows.map(row => '<i data-priority="' + row.vehicle.id + '"></i>').join(''),
    sharedNavisionLocationsStatusHtml: () => '', workStatusLegendHtml: () => '',
    incomingCompareVehicles: (a, b) => a.id.localeCompare(b.id),
    incomingVehicleDetailRow: row => '<article data-vehicle="' + row.id + '"></article>',
    productionGridHeaderHtml: () => '', vehicleLocationsRftHeaderHtml: () => '',
    escapeHtml: value => String(value),
    bindIncomingSubletLinks: () => {}, bindVehicleLabelButtons: () => {},
    bindAuthenticatedOperationSummaries: () => {}, bindFixFirstRows: () => {},
    bindRftCollectedInputs: () => {}, bindIncomingCardSelection: () => {},
    revealSingleVehicleSearchResult: () => {}, updateInlineSelectionBars: () => {},
    restoreIncomingBoardDisclosureState: () => {}, updateCollapseToggleButtons: () => {},
    ensureOperationalRefreshControls: () => {}, showView: view => { c.app.currentView = view; },
  };
  vm.createContext(c);
  for (const name of ['incomingDepartmentFilterValue', 'syncIncomingDepartmentFilter', 'pruneIncomingDepartmentSelection',
    'incomingDepartmentPriorityRows', 'incomingWorkFilterValues', 'incomingDashboardFilterValues',
    'incomingVehicleMatchesFilters', 'vehicleLocationsScreenRows', 'clearIncomingDashboardFilters',
    'focusVehiclesAfterWorkImport', 'renderIncomingDashboardBoardContent']) vm.runInContext(appFunction(name), c);
  return { c, pref, rows, priority, host, controls, workChecks, get renderCalls() { return renderCalls; } };
}

test('Vehicle Locations department filter composes with existing search, status, rep, bucket and work criteria', () => {
  const f = locationsFixture();
  const filters = { department: '138', search: '', status: '', rep: '', bucket: '', work: [] };
  assert.deepEqual(f.rows.filter(row => f.c.incomingVehicleMatchesFilters(row, filters)).map(row => row.id), ['bus', 'mixed']);
  assert.equal(f.c.incomingVehicleMatchesFilters(f.rows[0], { ...filters, search: 'bus-1', status: 'PMB', rep: 'Alice', bucket: 'pmb', work: ['tint'] }), true);
  for (const change of [{ search: 'missing' }, { status: 'YH' }, { rep: 'Bob' }, { bucket: 'yardhold' }, { work: ['fitting'] }]) {
    assert.equal(f.c.incomingVehicleMatchesFilters(f.rows[0], { ...filters, ...change }), false);
  }
  assert.equal(f.c.incomingVehicleMatchesFilters(f.rows[1], { ...filters, department: '139', work: ['fitting'] }), true);
});

test('shared source rows remain available to Parts and other screens while Locations hides a department', () => {
  const f = locationsFixture();
  assert.deepEqual(f.c.vehicleLocationsScreenRows().map(row => row.id), ['bus', 'pd', 'mixed', 'unknown']);
  assert.equal(f.c.incomingDashboardFilterValues().department, '138');
  assert.equal(f.c.incomingVehicleMatchesFilters(f.rows[1]), false);
  f.c.app.currentView = 'workflow';
  assert.equal(f.c.vehicleLocationBoardRows().length, 4);
  assert.equal(f.c.vehicleLocationsScreenRows().length, 4);
});

test('department events clear dashboard selections and synchronize the dropdown without changing another screen', () => {
  const f = locationsFixture('139');
  f.c.syncIncomingDepartmentFilter();
  assert.equal(f.controls.get('#incoming-department-filter').value, '139');
  assert.equal(f.c.app.selectedRows.size, 0);
  assert.equal(f.c.app.singleSearchFocus.incoming, '');
  assert.equal(f.renderCalls, 1);
  f.c.app.currentView = 'workflow';
  f.c.app.selectedRows.add('pd');
  f.c.app.singleSearchFocus.incoming = 'retain';
  f.pref.api.setSelection('138');
  f.c.syncIncomingDepartmentFilter();
  assert.equal(f.controls.get('#incoming-department-filter').value, '138');
  assert.deepEqual([...f.c.app.selectedRows], ['pd']);
  assert.equal(f.c.app.singleSearchFocus.incoming, 'retain');
  assert.equal(f.renderCalls, 1);
});

test('hidden department selections are pruned only for the dashboard', () => {
  const f = locationsFixture();
  f.c.pruneIncomingDepartmentSelection([f.rows[0], f.rows[2]]);
  assert.deepEqual([...f.c.app.selectedRows], ['bus', 'mixed']);
  f.c.app.currentView = 'workshop';
  f.c.app.selectedRows.add('pd');
  f.c.pruneIncomingDepartmentSelection([]);
  assert.deepEqual([...f.c.app.selectedRows], ['bus', 'mixed', 'pd']);
});

test('Fix First is filtered locally without changing Control Board priority data', () => {
  const f = locationsFixture();
  const filtered = f.c.incomingDepartmentPriorityRows();
  assert.deepEqual(filtered.map(row => row.vehicle.id), ['bus', 'mixed']);
  assert.equal(f.c.workflowPriorityRows().length, 4);
  assert.deepEqual(f.priority.map(row => row.vehicle.id), ['bus', 'pd', 'mixed', 'unknown']);
});

test('rendered rows, bucket totals, Fix First and selection all agree on the chosen department', () => {
  const f = locationsFixture();
  f.c.renderIncomingDashboardBoardContent();
  assert.match(f.controls.get('#incoming-filter-summary').textContent, /^2 of 4 vehicles shown.*Department 138/);
  assert.match(f.host.innerHTML, /data-vehicle="bus"/);
  assert.match(f.host.innerHTML, /data-vehicle="mixed"/);
  assert.doesNotMatch(f.host.innerHTML, /data-(?:vehicle|priority)="(?:pd|unknown)"/);
  assert.match(f.host.innerHTML, /2 active/);
  assert.deepEqual([...f.c.app.selectedRows], ['bus', 'mixed']);
  f.pref.api.setSelection('139');
  f.c.renderIncomingDashboardBoardContent();
  assert.match(f.controls.get('#incoming-filter-summary').textContent, /^2 of 4 vehicles shown.*Department 139/);
  assert.match(f.host.innerHTML, /data-vehicle="pd"/);
  assert.match(f.host.innerHTML, /data-vehicle="mixed"/);
  assert.doesNotMatch(f.host.innerHTML, /data-(?:vehicle|priority)="(?:bus|unknown)"/);
});

test('Clear filters restores All departments while approval focus preserves the chosen department', () => {
  const f = locationsFixture();
  for (const [key, control] of f.controls) if (key !== '#incoming-main-board') control.value = 'old-filter';
  f.workChecks[0].checked = true;
  f.c.clearIncomingDashboardFilters();
  assert.equal(f.pref.api.getSelection(), '');
  for (const id of ['incoming-search', 'incoming-status-filter', 'incoming-bucket-filter', 'incoming-rep-filter']) {
    assert.equal(f.controls.get('#' + id).value, '');
  }
  assert.equal(f.workChecks.some(control => control.checked), false);
  f.pref.api.setSelection('138');
  f.c.focusVehiclesAfterWorkImport(['newly-approved']);
  assert.equal(f.pref.api.getSelection(), '138');
  assert.equal(f.c.app.currentView, 'dashboard');
});

test('shared department preference is wired to Locations without entering Control Board or station code', () => {
  assert.match(appSource, /addEventListener\('pdc-department-filter-changed',\s*syncIncomingDepartmentFilter\)/);
  assert.doesNotMatch(appFunction('renderWorkflowBoard'), /PDC_DEPARTMENT_FILTER|incomingDepartmentFilterValue|incomingVehicleMatchesFilters/);
  assert.doesNotMatch(appFunction('workflowPriorityRows'), /PDC_DEPARTMENT_FILTER|incomingDepartmentFilterValue|incomingVehicleMatchesFilters/);
  assert.doesNotMatch(appFunction('vehicleLocationBoardRows'), /PDC_DEPARTMENT_FILTER|incomingDepartmentFilterValue|incomingVehicleMatchesFilters/);
  const stationSource = fs.readFileSync(path.join(__dirname, 'workshop-planner.js'), 'utf8');
  assert.doesNotMatch(stationSource, /PDC_DEPARTMENT_FILTER|incomingDepartmentFilterValue/);
});
