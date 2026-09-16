'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const appSource = fs.readFileSync('./app.js', 'utf8');
const mobileSource = fs.readFileSync('./pdc-qc-mobile.js', 'utf8');
const fitterSource = fs.readFileSync('./pdc-fitters.js', 'utf8');
const index = fs.readFileSync('./index.html', 'utf8');
const qcCss = fs.readFileSync('./pdc-qc-mobile.css', 'utf8');
const fitterCss = fs.readFileSync('./pdc-fitters.css', 'utf8');

function routingFixture({ role = 'operator', phone = true, hash = '#/qc' } = {}) {
  const classes = new Set(), calls = [];
  let isPhone = phone, qcRenders = 0;
  const context = {
    app: { currentView: 'dashboard' },
    window: { PDC_AUTH_CONTEXT: { role }, location: { hash } },
    mobile: () => isPhone,
    document: { documentElement: { classList: {
      toggle: (name, enabled) => enabled ? classes.add(name) : classes.delete(name),
      remove: name => classes.delete(name),
    } } },
    renderQualityControlPage: () => { qcRenders++; },
    recordNavigation: (view, options) => { calls.push({ view, options }); return 'core-result'; },
  };
  vm.createContext(context);
  // Compose the real core role redirect with the real mobile adapter. Testing
  // these independently missed a fitter route hidden by QC-only presentation.
  const coreStart = appSource.indexOf('function showView(view, options)');
  const coreEnd = appSource.indexOf('  // Hidden navigation', coreStart);
  assert.ok(coreStart >= 0 && coreEnd > coreStart);
  vm.runInContext(appSource.slice(coreStart, coreEnd)
    + 'app.currentView = requestedView; return recordNavigation(requestedView, options); }'
    + '\nconst desktopShowView = showView;', context);
  const adapterStart = mobileSource.indexOf('  showView = function (view, options)');
  const adapterEnd = mobileSource.indexOf('  media.addEventListener', adapterStart);
  assert.ok(adapterStart >= 0 && adapterEnd > adapterStart);
  vm.runInContext(mobileSource.slice(adapterStart, adapterEnd), context);
  return {
    context, calls, classes,
    setPhone: value => { isPhone = value; },
    qcRenders: () => qcRenders,
    visibleScreens: () => ['fitters', 'qc'].filter(view =>
      view === context.app.currentView
      && (!classes.has('pdc-qc-phone') || view === 'qc')
      && (context.window.PDC_AUTH_CONTEXT.role !== 'fitter' || view === 'fitters')),
  };
}

test('operator mobile navigation shows one dedicated QC or fitter screen', () => {
  const f = routingFixture();
  for (const route of ['qc', 'fitters', 'qc']) {
    const options = { historyMode: 'replace' };
    assert.equal(f.context.showView(route, options), 'core-result');
    assert.equal(f.context.app.currentView, route);
    assert.equal(f.classes.has('pdc-qc-phone'), route === 'qc');
    assert.deepEqual(f.visibleScreens(), [route]);
    assert.equal(f.calls.at(-1).options, options);
  }
});

test('fitter-only redirects remain visible when QC was requested', () => {
  // These are the production selectors that together previously hid both views.
  assert.match(qcCss, /html\.pdc-qc-phone \.main > \.view:not\(#qc\)/);
  assert.match(fitterCss, /body\.fitter-only \.view:not\(#fitters\)/);
  const f = routingFixture({ role: 'fitter' });
  for (const requested of ['qc', 'dashboard', 'fitters']) {
    f.context.showView(requested);
    assert.equal(f.context.app.currentView, 'fitters');
    assert.equal(f.classes.has('pdc-qc-phone'), false);
    assert.deepEqual(f.visibleScreens(), ['fitters']);
  }
});

test('auth or viewport updates use the resolved route instead of a stale QC hash', () => {
  const f = routingFixture({ role: 'fitter', hash: '#/qc' });
  f.classes.add('pdc-qc-phone');
  f.context.updateMode();
  assert.equal(f.context.app.currentView, 'fitters');
  assert.deepEqual(f.visibleScreens(), ['fitters']);
  assert.equal(f.classes.has('pdc-qc-phone'), false);
  assert.equal(f.calls.at(-1).options.historyMode, 'replace');
});

test('leaving phone size clears QC-only presentation without changing the selected screen', () => {
  const f = routingFixture();
  f.context.showView('qc');
  f.setPhone(false);
  f.context.updateMode();
  assert.equal(f.context.app.currentView, 'qc');
  assert.equal(f.classes.has('pdc-qc-phone'), false);
  assert.equal(f.qcRenders(), 1);
  f.context.showView('fitters');
  f.context.updateMode();
  assert.equal(f.context.app.currentView, 'fitters');
  assert.equal(f.qcRenders(), 1);
});

test('phone mode still preserves authentication fragments', () => {
  const f = routingFixture({ hash: '#type=recovery' });
  f.context.updateMode();
  assert.equal(f.calls.at(-1).options.historyMode, 'none');
});

test('QC and fitters retain separate sidebar entries and hosts without cross-workflow header buttons', () => {
  assert.match(index, /data-view="qc"[^>]*>QC Sign-off<\/button>/);
  assert.match(index, /data-view="fitters"[^>]*>Fitters bay<\/button>/);
  assert.match(index, /<section id="fitters" class="view"><div id="fitters-host">/);
  assert.match(index, /<section id="qc" class="view">/);
  assert.doesNotMatch(fitterSource, /data-fitter-qc/);
  assert.doesNotMatch(mobileSource, /data-qc-open-fitters/);
  assert.match(fitterSource, /data-fitter-action="complete"/);
  assert.match(mobileSource, /data-qc-signoff=/);
});

function qcActivityFixture(options = {}) {
  const f = routingFixture(options), handlers = new Map();
  let reads = 0, renders = 0;
  let reader = async () => true;
  Object.assign(f.context, {
    qcSelectedVehicleKey: 'retained-qc-vehicle', qcPageNotice: '',
    renderPhone: () => { renders++; }, renderDesktop: () => { renders++; },
    refreshEmailVehicleLocations: () => { reads++; return reader(); },
  });
  f.context.window.addEventListener = (name, callback) => handlers.set(name, callback);
  const active = mobileSource.match(/^  const qcActive = .*;$/m)?.[0];
  assert.ok(active);
  const refreshStart = mobileSource.indexOf('  async function refresh()');
  const refreshEnd = mobileSource.indexOf('  function vehicleCard(', refreshStart);
  const renderStart = mobileSource.indexOf('  renderQualityControlPage = function ()');
  const renderEnd = mobileSource.indexOf('  showView = function', renderStart);
  const historyStart = mobileSource.indexOf("  window.addEventListener('popstate'");
  const historyEnd = mobileSource.indexOf("  window.addEventListener('beforeunload'", historyStart);
  const connectivityStart = mobileSource.indexOf("  window.addEventListener('online'");
  const connectivityEnd = mobileSource.indexOf('  window.PDC_QC_MOBILE_VERSION', connectivityStart);
  assert.ok(refreshStart >= 0 && refreshEnd > refreshStart && renderEnd > renderStart
    && historyEnd > historyStart && connectivityEnd > connectivityStart);
  vm.runInContext('let refreshBusy = false;\n' + active + '\n'
    + mobileSource.slice(refreshStart, refreshEnd)
    + mobileSource.slice(renderStart, renderEnd)
    + mobileSource.slice(historyStart, historyEnd)
    + mobileSource.slice(connectivityStart, connectivityEnd), f.context);
  return {
    ...f, emit: (name, event = {}) => handlers.get(name)?.(event),
    reads: () => reads, renders: () => renders, setReader: fn => { reader = fn; },
  };
}

test('Fitters connectivity and history events neither fetch nor render hidden QC or reset its selection', async () => {
  for (const role of ['operator', 'fitter']) {
    const f = qcActivityFixture({ role });
    f.context.showView('fitters');
    f.emit('online'); f.emit('offline');
    f.emit('popstate', { state: { pdcView: 'fitters' } });
    await f.context.refresh();
    f.context.renderQualityControlPage();
    assert.equal(f.reads(), 0, role);
    assert.equal(f.renders(), 0, role);
    assert.equal(f.context.qcSelectedVehicleKey, 'retained-qc-vehicle');
    assert.deepEqual(f.visibleScreens(), ['fitters']);
  }
});

test('QC connectivity and history remain active only on its selected screen', async () => {
  const f = qcActivityFixture();
  f.context.showView('qc');
  f.emit('online');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.reads(), 1);
  const priorRenders = f.renders();
  f.emit('offline');
  f.emit('popstate', { state: { pdcView: 'qc', qcMobileVehicle: 'qc-detail' } });
  assert.equal(f.renders(), priorRenders + 2);
  assert.equal(f.context.qcSelectedVehicleKey, 'qc-detail');
  f.context.showView('fitters');
  f.emit('online'); f.emit('offline'); f.emit('popstate', { state: { pdcView: 'fitters' } });
  assert.equal(f.reads(), 1);
  assert.equal(f.renders(), priorRenders + 2);
  assert.equal(f.context.qcSelectedVehicleKey, 'qc-detail');
  f.context.showView('qc');
  f.emit('popstate', { state: { pdcView: 'qc' } });
  assert.equal(f.context.qcSelectedVehicleKey, '');
  await f.context.refresh();
  assert.equal(f.reads(), 2);
});

test('a QC refresh finishing after navigating to Fitters cannot render hidden QC', async () => {
  const f = qcActivityFixture();
  let resolveRead;
  f.setReader(() => new Promise(resolve => { resolveRead = resolve; }));
  f.context.showView('qc');
  const refreshing = f.context.refresh();
  assert.equal(f.reads(), 1);
  assert.equal(f.renders(), 1);
  f.context.showView('fitters');
  resolveRead(true);
  await refreshing;
  assert.equal(f.renders(), 1);
  assert.deepEqual(f.visibleScreens(), ['fitters']);
  f.context.showView('qc');
  f.setReader(async () => true);
  await f.context.refresh();
  assert.equal(f.reads(), 2, 'a completed previous refresh must release its busy flag');
  assert.equal(f.renders(), 3);
});

test('fitter role transitions cannot fetch QC before the route redirect runs', async () => {
  const f = qcActivityFixture();
  f.context.showView('qc');
  f.context.window.PDC_AUTH_CONTEXT.role = 'fitter';
  f.emit('online'); f.emit('offline');
  f.emit('popstate', { state: { qcMobileVehicle: 'other-qc-vehicle' } });
  await f.context.refresh();
  f.context.renderQualityControlPage();
  assert.equal(f.reads(), 0);
  assert.equal(f.renders(), 0);
  assert.equal(f.context.qcSelectedVehicleKey, 'retained-qc-vehicle');
});
