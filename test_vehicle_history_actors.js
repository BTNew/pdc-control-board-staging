'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');
const { createPdcEmailVehicleLocationService, PDC_VEHICLE_HISTORY_RPC } = require('./pdc-email-vehicle-location-service.js');

const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const blockStart = source.indexOf('function compactAuditValue(');
const blockEnd = source.indexOf('\nconst VEHICLE_WORKSHOP_STATION_PRESENTATION', blockStart);
assert.ok(blockStart >= 0 && blockEnd > blockStart, 'Exercise the actual vehicle history implementation');
function functionSource(name) {
  const start = source.indexOf(`function ${name}(`);
  const end = source.indexOf('\n}', start);
  assert.ok(start >= 0 && end > start, `${name} is available in app.js`);
  return source.slice(start, end + 2);
}
const CANONICAL_ID = '11111111-1111-4111-8111-111111111111';
const ACTOR_ID = '22222222-2222-4222-8222-222222222222';
const vehicle = Object.freeze({ id: CANONICAL_ID, canonicalId: CANONICAL_ID, dealerCode: '037047' });

function harness({ detail = {}, localRows = [], canonical = true, status = 'ready', service = null, modalOpen = false } = {}) {
  const historyElement = { outerHTML: '' };
  const context = {
    app: {
      vehicleHistoryCache: new Map(canonical ? [[CANONICAL_ID, { status, detail }]] : []),
      vehicleHistoryRequestGeneration: 0,
      emailVehicleLocationGeneration: 0,
      emailVehicleLocationService: service,
      currentView: 'vehicle-locations',
    },
    window: { PDC_AUTH_CONTEXT: { userId: 'current-viewer', displayName: 'Current Viewer', email: 'viewer@example.test' } },
    vehicleWorkshopDetailCanonicalId: () => canonical ? CANONICAL_ID : '',
    auditTrailForVehicle: () => localRows,
    lifecycleHistoryForVehicle: () => ({}),
    lifecycleDurationLabel: () => 'Unknown',
    vehicleKey: value => value.id || '',
    selectedVehicle: () => vehicle,
    $: selector => selector === '#vehicle-modal' ? { hidden: !modalOpen } : { querySelector: () => historyElement },
    renderVehicleDetailAfterBackgroundRefresh: () => assert.fail('Existing history section should be refreshed directly'),
    renderIncomingDashboardBoard: () => assert.fail('History tests must not refresh another board'),
  };
  vm.createContext(context);
  vm.runInContext([
    functionSource('escapeHtml'), functionSource('parseIsoTimestamp'),
    functionSource('resetEmailVehicleLocations'), source.slice(blockStart, blockEnd),
  ].join('\n'), context);
  return { context, historyElement, render: () => context.renderAuditTrailSection(vehicle) };
}

function actorSpans(html) {
  return [...html.matchAll(/<span class="vehicle-history-actor">([^<]*)<\/span>/g)].map(match => match[1]);
}
function historyItems(html) {
  return [...html.matchAll(/<div class="audit-log-item">([\s\S]*?)<\/div>/g)].map(match => match[1]);
}
function freezeDeep(value) {
  if (value && typeof value === 'object') {
    Object.values(value).forEach(freezeDeep);
    Object.freeze(value);
  }
  return value;
}
function makeService(fetchImpl, token = () => 'synthetic-test-token') {
  return createPdcEmailVehicleLocationService({
    config: { url: 'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey: 'synthetic-test-key' },
    getAccessToken: token, fetchImpl,
  });
}

test('recorded actor projection and legacy event values produce readable labels', () => {
  const { context: c } = harness();
  assert.equal(c.vehicleHistoryActorLabel({ actor: { label: 'Recorded Operator (operator@example.test)', id: ACTOR_ID }, actor_email: 'legacy@example.test' }), 'Recorded Operator (operator@example.test)');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { display_name: 'Recorded Operator', email: 'operator@example.test', kind: 'user' } }), 'Recorded Operator (operator@example.test)');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { display_name: 'operator@example.test', email: 'operator@example.test' } }), 'operator@example.test');
  assert.equal(c.vehicleHistoryActorLabel({ actor_id: ACTOR_ID, actor_email: 'recorded@example.test' }), 'recorded@example.test');
  assert.equal(c.vehicleHistoryActorLabel({ moved_by: 'legacy@example.test' }, 'moved_by'), 'legacy@example.test');
  assert.equal(c.vehicleHistoryActorLabel({ moved_by: 'Legacy Operator' }, 'moved_by'), 'Legacy Operator');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { display_name: 'Recorded Operator' } }), 'Recorded Operator');
});

test('missing or unresolved actors remain unknown; only explicit automation evidence is automated', () => {
  const { context: c } = harness();
  assert.equal(c.vehicleHistoryActorLabel({ actor_id: ACTOR_ID }), 'User not identified');
  assert.equal(c.vehicleHistoryActorLabel({ moved_by: ACTOR_ID }, 'moved_by'), 'User not identified');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { id: ACTOR_ID, label: ACTOR_ID, display_name: ACTOR_ID, kind: 'unknown' } }), 'User not identified');
  assert.equal(c.vehicleHistoryActorLabel({}), 'User not recorded');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { kind: 'unknown' } }), 'User not recorded');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { kind: 'automation' } }), 'Automated action');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { label: 'Scheduled import', kind: 'automation' } }), 'Scheduled import');
  assert.equal(c.vehicleHistoryActorLabel({ actor: { kind: 'user' } }), 'User not recorded');
});

test('actor attribution never comes from entity creators, current viewer, supplier, or import sender', () => {
  const event = {
    created_at: '2026-10-03T00:00:00Z', action: 'update', table_name: 'vehicles',
    created_by: 'Entity Creator', updated_by: 'Entity Editor', sender_address: 'sender@example.test',
    before_data: { updated_by: 'Previous Editor' }, after_data: { updated_by: 'Entity Editor' },
    metadata: { user: 'Metadata User', mechanic: 'Assigned Mechanic', provider: 'Service Provider' },
  };
  const { context: c, render } = harness({ detail: { audit_events: [event] } });
  assert.equal(c.vehicleHistoryActorLabel(event), 'User not recorded');
  const attribution = actorSpans(render());
  assert.equal(attribution.length, 1);
  assert.match(attribution[0], /^By: User not recorded · /);
  assert.doesNotMatch(attribution[0], /Creator|Editor|Viewer|sender|Metadata|Mechanic|Provider|System authority/);
});

test('each event has its actor and Perth time before a separate detail span', () => {
  const { render } = harness({
    detail: {
      movements: [{ moved_at: '2026-10-03T00:00:00Z', moved_by: ACTOR_ID, actor: { label: 'Movement Operator' }, from_location: 'YH', to_location: 'PMB', reason: 'Intake confirmed' }],
      audit_events: [{ created_at: '2026-10-02T00:00:00Z', actor: { label: 'Audit Operator' }, action: 'parts_ordered', table_name: 'vehicle_work', before_data: { ordered: false }, after_data: { ordered: true } }],
    },
    localRows: [{ at: '2026-10-01T00:00:00Z', by: 'Local Operator', role: 'admin', action: 'Local note', details: { note: 'Browser note' } }],
  });
  const rows = historyItems(render());
  assert.equal(rows.length, 3);
  assert.match(rows[0], /^<strong>Vehicle moved<\/strong><span class="vehicle-history-actor">By: Movement Operator · [^<]+ \(Perth\)<\/span><span>YH → PMB · Intake confirmed<\/span>$/);
  assert.match(rows[1], /^<strong>parts ordered · vehicle work<\/strong><span class="vehicle-history-actor">By: Audit Operator · [^<]+ \(Perth\)<\/span><span>ordered: false → true<\/span>$/);
  assert.match(rows[2], /^<strong>Local note<\/strong><span class="vehicle-history-actor">By: Browser record: Local Operator \(admin\) · [^<]+ \(Perth\)<\/span><span>note: Browser note<\/span>$/);
});

test('legacy local history stays explicitly browser-recorded and missing local operator is truthful', () => {
  const { render } = harness({ canonical: false, localRows: [
    { at: '2026-10-02T00:00:00Z', user: 'Legacy User', role: 'sales', action: 'Legacy update' },
    { at: '2026-10-01T00:00:00Z', action: 'Unattributed update' },
  ] });
  const html = render();
  assert.match(html, /only browser-recorded history is available/);
  assert.match(actorSpans(html)[0], /^By: Browser record: Legacy User \(sales\) · /);
  assert.match(actorSpans(html)[1], /^By: Browser record: Unknown operator · /);
  assert.doesNotMatch(html, /System authority|By: Current Viewer/);
});

test('server and browser actor labels, action and details are escaped before HTML rendering', () => {
  const injection = '<img src=x onerror="alert(1)"> & \'quoted\'';
  const { render } = harness({
    detail: {
      movements: [{ moved_at: '2026-10-03T00:00:00Z', actor: { label: injection }, from_location: injection, to_location: 'PMB' }],
      audit_events: [{ created_at: '2026-10-02T00:00:00Z', actor_email: injection, action: injection, metadata: { note: injection } }],
    },
    localRows: [{ at: '2026-10-01T00:00:00Z', by: injection, role: injection, action: injection, details: { note: injection } }],
  });
  const html = render();
  assert.equal(historyItems(html).length, 3);
  assert.doesNotMatch(html, /<img|<script|onerror="/);
  assert.match(html, /&lt;img src=x onerror=&quot;alert\(1\)&quot;&gt; &amp; &#39;quoted&#39;/);
  assert.equal(actorSpans(html).length, 3);
  actorSpans(html).forEach(value => assert.match(value, /&lt;img/));
});

test('history timestamps use Perth even on a UTC device and invalid timestamps remain unknown', () => {
  const originalTimezone = process.env.TZ;
  process.env.TZ = 'UTC';
  try {
    const { render } = harness({ detail: { audit_events: [
      { created_at: '2026-10-02T23:30:00.000Z', actor_email: 'operator@example.test' },
      { created_at: 'invalid', actor_email: 'unknown-time@example.test' },
    ] } });
    const attribution = actorSpans(render());
    const expected = new Date('2026-10-02T23:30:00.000Z').toLocaleString('en-AU', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Australia/Perth' });
    assert.ok(attribution.includes(`By: operator@example.test · ${expected} (Perth)`));
    assert.match(expected, /3\/10\/26, 7:30 am/);
    assert.ok(attribution.includes('By: unknown-time@example.test · Unknown time (Perth)'));
  } finally {
    if (originalTimezone === undefined) delete process.env.TZ;
    else process.env.TZ = originalTimezone;
  }
});

test('newest history remains first with the existing 150-row limit and no input mutation', () => {
  const detail = freezeDeep({ audit_events: Array.from({ length: 151 }, (_, index) => ({
    created_at: new Date(Date.UTC(2026, 0, 1, 0, index)).toISOString(),
    actor: { label: `Operator ${index}` }, action: `event_${index}`,
    before_data: { status: 'old' }, after_data: { status: 'new' },
  })) });
  const before = JSON.stringify(detail);
  const html = harness({ detail }).render();
  const rows = historyItems(html);
  assert.equal(rows.length, 150);
  assert.match(rows[0], /^<strong>event 150 · vehicle<\/strong>/);
  assert.match(rows[149], /^<strong>event 1 · vehicle<\/strong>/);
  assert.doesNotMatch(html, /<strong>event 0 · vehicle<\/strong>/);
  assert.equal(JSON.stringify(detail), before);
});

test('history service uses the authenticated scoped RPC and preserves per-event projections', async () => {
  const calls = [];
  const detail = freezeDeep({
    movements: [{ moved_by: ACTOR_ID, actor: { id: ACTOR_ID, email: 'operator@example.test', display_name: 'Operator', label: 'Operator (operator@example.test)', kind: 'user', source: 'recorded_user_id' } }],
    audit_events: [{ actor_id: ACTOR_ID, actor_email: 'historical@example.test', actor: { label: 'Historical Operator', kind: 'user', source: 'recorded_email' } }],
  });
  const service = makeService(async (url, options) => {
    calls.push({ url, options });
    return { ok: true, status: 200, json: async () => ({ ok: true, data: detail }) };
  });
  const response = await service.vehicleHistory(CANONICAL_ID, 'ignored-client-scope');
  assert.equal(response.ok, true);
  assert.strictEqual(response.data, detail);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `https://cdsmnqxtyyoeoznmbidd.supabase.co/rest/v1/rpc/${PDC_VEHICLE_HISTORY_RPC}`);
  assert.equal(calls[0].options.method, 'POST');
  assert.equal(calls[0].options.headers.Authorization, 'Bearer synthetic-test-token');
  assert.deepEqual(JSON.parse(calls[0].options.body), { p_vehicle_id: CANONICAL_ID });
});

test('unauthenticated history service does not request any data', async () => {
  const service = makeService(() => assert.fail('No request is permitted without authentication'), () => null);
  assert.deepEqual(await service.vehicleHistory(CANONICAL_ID), { ok: false, code: 'not_authenticated', data: null });
});

test('ready history reuses its cache, and successful loading refreshes the open detail only', async () => {
  let calls = 0;
  const detail = { audit_events: [{ created_at: '2026-10-03T00:00:00Z', actor: { label: 'Recorded Operator' } }] };
  const { context: c, historyElement } = harness({ service: { vehicleHistory: async (id, dealer) => {
    calls += 1;
    assert.equal(id, CANONICAL_ID);
    assert.equal(dealer, '037047');
    return { ok: true, data: detail };
  } }, modalOpen: true });
  c.app.vehicleHistoryCache.clear();
  await c.loadVehicleHistoryForDetail(vehicle);
  assert.equal(c.app.vehicleHistoryCache.get(CANONICAL_ID).status, 'ready');
  assert.strictEqual(c.app.vehicleHistoryCache.get(CANONICAL_ID).detail, detail);
  assert.match(historyElement.outerHTML, /By: Recorded Operator/);
  await c.loadVehicleHistoryForDetail(vehicle);
  assert.equal(calls, 1);
});

test('failed or denied history responses never cache or render their payload', async () => {
  const { context: c, render } = harness({ service: { vehicleHistory: async () => ({
    ok: false, code: 'dealer_scope_denied', data: { audit_events: [{ actor: { label: 'Denied Payload Actor' } }] },
  }) } });
  c.app.vehicleHistoryCache.clear();
  await c.loadVehicleHistoryForDetail(vehicle);
  const state = c.app.vehicleHistoryCache.get(CANONICAL_ID);
  assert.equal(state.status, 'error');
  assert.equal(state.message, 'dealer_scope_denied');
  assert.equal(state.detail, undefined);
  const html = render();
  assert.match(html, /Authoritative history unavailable: dealer_scope_denied/);
  assert.doesNotMatch(html, /Denied Payload Actor/);
});

test('auth reset clears history and a late previous-session response cannot restore it', async () => {
  let release;
  const pendingResponse = new Promise(resolve => { release = resolve; });
  const { context: c, historyElement } = harness({ service: { vehicleHistory: () => pendingResponse }, modalOpen: true });
  c.app.vehicleHistoryCache.clear();
  const loading = c.loadVehicleHistoryForDetail(vehicle);
  assert.equal(c.app.vehicleHistoryCache.get(CANONICAL_ID).status, 'loading');
  c.resetEmailVehicleLocations();
  assert.equal(c.app.vehicleHistoryCache.size, 0);
  assert.equal(c.app.emailVehicleLocationService, null);
  release({ ok: true, data: { audit_events: [{ actor: { label: 'Previous Session Actor' } }] } });
  await loading;
  assert.equal(c.app.vehicleHistoryCache.size, 0);
  assert.equal(historyElement.outerHTML, '');
});
