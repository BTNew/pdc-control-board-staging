'use strict';
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const rowStart = appSource.indexOf('function incomingVehicleDetailRow');
const rowEnd = appSource.indexOf('\nfunction ', rowStart + 20);
assert.ok(rowStart >= 0 && rowEnd > rowStart, 'Vehicle Locations row renderer exists');
const rowSource = appSource.slice(rowStart, rowEnd);
const rftHelperStart = appSource.indexOf('function vehicleRftTransportBooked');
const rftHelperEnd = appSource.indexOf('\nfunction rftTransportEmailStatusLabel', rftHelperStart);
assert.ok(rftHelperStart >= 0 && rftHelperEnd > rftHelperStart, 'RFT row control helpers exist');
const rftHelperSource = appSource.slice(rftHelperStart, rftHelperEnd);

const vehicle = {
  __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  __emailVehicleVersion: 7,
  __emailVehicleServerAuthoritative: true,
  __emailVehicleReadOnly: true,
  source: 'Imported by email',
  stock: '13000769',
  pdcLocation: 'RFT',
  lifecycleState: 'rft',
  rftConfirmed: true,
  rftConfirmedAt: '2026-08-28T03:00:00Z',
  toyotaStatus: 'RFT',
  client: 'Ahrens Group Pty Ltd',
  vehicle: 'Hilux DCC',
  rftTransportOutbox: {
    intercepted: false,
    delivery_enabled: false,
  },
};

const context = {
  app: { selectedRows: new Set(), rftTransportActionInFlight: new Set(), emailVehicleLocationService: { setRftConfirmation736: () => {}, bookRftTransport734: () => {}, bookRftTransport739: () => {}, collectRftTransport734: () => {} } },
  window: {
    PDC_AUTH_CONTEXT: { role: 'operator' },
    PDC_SUPABASE_CONFIG: {
      environment: 'staging',
      projectRef: 'cdsmnqxtyyoeoznmbidd',
      vehicleLifecycle: { durableRftLifecycle: true },
    },
  },
  vehicle,
  vehicleKey: value => value.__emailVehicleId || value.stock,
  escapeHtml: value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char])),
  sharedNavisionLocationAuthorityReady: () => true,
  vehicleLifecycleSharedModeActive: () => true,
  vehicleLifecycleAdministratorActive: () => false,
  durableRftLifecycleEnabled: () => true,
  rftTransportEmailStatusLabel: () => '',
  statusCategory: () => 'rft',
  navisionStatusText: () => 'RFT',
  locationAgeLabel: () => '28/07/2026',
  displayStockNumber: value => value.stock,
  displayVehicle: value => value.vehicle,
  consultantName: () => 'Craig',
  vehicleKeyNumber: () => '',
  pmbAgeLabel: () => '1 day',
  vehicleWorkshopBookingProjection: () => ({ bookingRequired: false, label: '' }),
  incomingWorkChecklistHtml: () => '<span class="work-check">work</span>',
  incomingBucketLabel: () => 'RFT',
  inferredPmbStage: () => '',
  incomingGridStatusLabel: () => 'BLOCKED',
  pmbBaySubletProvider: () => '',
  subletProviderOptionsHtml: () => '',
  sharedVehicleLocationMutationUnavailable: () => false,
  vehicleReadyForQualityControl: () => false,
  vehicleCanEnterPit: () => false,
  pdcRequiredJobs: () => [],
  vehicleIdentityStackHtml: () => '<span class="identity">13000769</span>',
  partsRiskBadge: () => '',
  vehicleDepartmentBadge: () => '',
  partsEtaRisk: () => false,
  onSiteDaysClass: () => 'normal',
  pdcGridJobLabel: () => 'Parts',
  authenticatedEmailOperationLinesHtml: () => '',
};
vm.createContext(context);
vm.runInContext(`${rftHelperSource}\n${rowSource}\nthis.renderIncomingRftRow = incomingVehicleDetailRow;`, context);

let rendered = context.renderIncomingRftRow(vehicle, 'rft', {});
assert.match(rendered, /incoming-rft-row/, 'Stock-shaped authoritative RFT row uses Vehicle Locations renderer');
assert.match(rendered, /13000769/, 'Stock-shaped row identity remains visible');
assert.match(rendered, /data-rft-transport-booked-key="11111111-1111-4111-8111-111111111111"/, 'RFT email successor control is visible in the Vehicle Locations row');
assert.match(rendered, /data-rft-collected-key="11111111-1111-4111-8111-111111111111"/, 'Collected control is visible in the Vehicle Locations row');
const summary = rendered.match(/<summary[\s\S]*?<\/summary>/)?.[0] || '';
const summaryLabels = [...summary.matchAll(/<span>(RFT’d|Email Sales Person|Collected)<\/span>/g)].map(match => match[1]);
assert.deepStrictEqual(summaryLabels, ['RFT’d', 'Email Sales Person', 'Collected'], 'Vehicle Locations RFT row exposes exactly the three final labels');
assert.match(summary, /rft-confirmation-control is-checked/);
assert.match(summary, /data-rft-confirmation-key="11111111-1111-4111-8111-111111111111"/);
assert.doesNotMatch(rendered, /RFT Booked|incoming-work-check|pdc-station-|pdc-mini-|rft-completion|\bAge\b|\bETA\b|\bStatus\b/, 'RFT Vehicle Locations rows have no per-work icons or ordinary age/ETA/status clutter');
assert.match(rendered, /Collected/, 'Collected accessible label is visible');
assert.match(rendered, /Book RFT|Mandatory email.*photo|collection/i, 'Collected disabled state exposes a clear reason');

context.app.emailVehicleLocationService = {
  setRftConfirmation736: () => {},
  bookRftTransport734: () => {},
  bookRftTransport739: () => {},
  collectRftTransport734: () => {},
};
rendered = context.renderIncomingRftRow(vehicle, 'rft', {});
const bookedButton = rendered.match(/<button[^>]*data-rft-transport-booked-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '';
const collectedButton = rendered.match(/<button[^>]*data-rft-collected-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '';
assert.doesNotMatch(bookedButton, /\sdisabled(?:=|\s|>)/, 'Unbooked authoritative RFT row enables RFT Booked');
assert.match(collectedButton, /\sdisabled(?:=|\s|>)/, 'Collected stays disabled before booking');

vehicle.rftTransportBookedAt = '2026-08-28T04:00:00Z';
vehicle.rftTransportOutbox = {
  intercepted: true,
  delivery_enabled: false,
  sent_at: null,
  delivered_at: null,
  evidence: { photo_receipt_id: 'photo-734', mime_sha256: 'hash-734' },
};
rendered = context.renderIncomingRftRow(vehicle, 'rft', {});
vm.runInContext('this.debugEvidence = vehicleRftEmailEvidenceReady(vehicle); this.debugCollection = vehicleRftCollectionEnabled(vehicle);', context);
assert.strictEqual(context.debugEvidence, true, 'Mandatory email and QC photo evidence projects as ready');
assert.strictEqual(context.debugCollection, true, 'Collection projection enables from durable evidence');
const bookedAfter = rendered.match(/<button[^>]*data-rft-transport-booked-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '';
const collectedAfter = rendered.match(/<button[^>]*data-rft-collected-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '';
assert.match(bookedAfter, /aria-pressed="true"[\s\S]*\sdisabled(?:=|\s|>)/, 'Booked state is checked and disabled');
assert.doesNotMatch(collectedAfter, /\sdisabled(?:=|\s|>)/, 'Collected enables after booking and mandatory evidence read-back');
const irreversibleConfirmation = rendered.match(/<input[^>]*data-rft-confirmation-key="[^"]+"[^>]*>/)?.[0] || '';
assert.match(irreversibleConfirmation, /\sdisabled(?:=|\s|>)/, 'RFT’d cannot be unticked after Email Sales Person evidence');
assert.match(rendered, /Email Sales Person evidence exists; RFT’d cannot be unticked/);

const uncheckedVehicle = { ...vehicle, rftConfirmed: false, rftConfirmedAt: '', rftTransportBookedAt: '', rftTransportOutbox: { intercepted: false, delivery_enabled: false } };
rendered = context.renderIncomingRftRow(uncheckedVehicle, 'rft', {});
const uncheckedConfirmation = rendered.match(/<input[^>]*data-rft-confirmation-key="[^"]+"[^>]*>/)?.[0] || '';
const uncheckedEmail = rendered.match(/<button[^>]*data-rft-transport-booked-key="[^"]+[\s\S]*?<\/button>/)?.[0] || '';
assert.doesNotMatch(uncheckedConfirmation, /\sdisabled(?:=|\s|>)/, 'Authorised operator can tick RFT’d on an already-RFT vehicle');
assert.match(uncheckedEmail, /\sdisabled(?:=|\s|>)/, 'Email Sales Person is disabled until RFT’d is ticked');
assert.match(uncheckedEmail, /tick RFT’d first/);

context.window.PDC_AUTH_CONTEXT.role = 'viewer';
rendered = context.renderIncomingRftRow(vehicle, 'rft', {});
const unauthorisedSummary = rendered.match(/<summary[\s\S]*?<\/summary>/)?.[0] || '';
assert.match(unauthorisedSummary, /RFT’d/);
assert.match(unauthorisedSummary, /Email Sales Person/);
assert.match(unauthorisedSummary, /Collected/);
assert.match(unauthorisedSummary.match(/data-rft-transport-booked-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '', /\sdisabled(?:=|\s|>)/, 'Unauthorised email successor remains disabled');
assert.match(unauthorisedSummary.match(/data-rft-collected-key="[^"]+"[\s\S]*?<\/button>/)?.[0] || '', /\sdisabled(?:=|\s|>)/, 'Unauthorised collection remains disabled');
context.window.PDC_AUTH_CONTEXT.role = 'operator';

const actionStart = appSource.indexOf('async function markRftTransportBooked');
const actionEnd = appSource.indexOf('\nfunction collectedVehicleRows', actionStart);
assert.ok(actionStart >= 0 && actionEnd > actionStart, 'RFT action handlers exist');
const transportActionsStart = appSource.indexOf('function beginRftTransportAction');
const actionSource = appSource.slice(transportActionsStart, actionEnd);
assert.match(actionSource, /service\.bookRftTransport739/);
assert.match(actionSource, /service\.collectRftTransport734/);
assert.match(actionSource, /service\.setRftConfirmation736/);
assert.match(actionSource, /data-rft-transport-booked-key|Email Sales Person/);
assert.match(actionSource, /await refreshEmailVehicleLocations\(\)/);
assert.match(actionSource, /rftTransportActionIsCurrent/, 'RFT callbacks reject stale results');
assert.doesNotMatch(actionSource, /saveVehicleEdits|localStorage\.setItem/, 'RFT controls never use browser-local fallback');

const actionVehicle = {
  __emailVehicleId: '11111111-1111-4111-8111-111111111111',
  __emailVehicleVersion: 7,
  __emailVehicleServerAuthoritative: true,
  rftConfirmed: true,
  rftTransportBookedAt: '',
};
let pendingBooking;
let bookingCalls = [];
let collectionCalls = [];
let confirmationCalls = [];
let refreshCalls = 0;
let renderCalls = 0;
const actionContext = {
  app: {
    emailVehicleLocationService: {
      setRftConfirmation736: async (id, version, confirmed, key) => {
        confirmationCalls.push([id, version, confirmed, key]);
        actionVehicle.rftConfirmed = confirmed;
        return { ok: true, code: confirmed ? 'rft_confirmed' : 'rft_unconfirmed', data: { receipt_id: 'receipt-736', vehicle_id: id, vehicle_version_after: version + 1, rft_confirmed: confirmed } };
      },
      bookRftTransport739: (id, version, key) => {
        bookingCalls.push([id, version, key]);
        return new Promise(resolve => { pendingBooking = resolve; });
      },
      collectRftTransport734: async (id, version, key) => {
        collectionCalls.push([id, version, key]);
        return { ok: true, code: 'rft_collected', data: { vehicle_id: id } };
      },
    },
    rftTransportActionGeneration: 0,
    rftTransportActionInFlight: new Set(),
  },
  window: {
    PDC_AUTH_CONTEXT: { role: 'operator' },
    confirm: () => true,
    alert: () => {},
    __workshopDataService: {},
  },
  selectedVehicle: () => actionVehicle,
  vehicleRftLifecycleRoleAllowed: () => true,
  rftTransportActionAuthorityReady: () => true,
  rftConfirmationIrreversibleReason: () => '',
  vehicleRftConfirmationActive: value => value.rftConfirmed === true,
  vehicleRftTransportBooked: value => Boolean(value.rftTransportBookedAt),
  vehicleRftEmailEvidenceReady: () => true,
  vehicleRftCollectionEnabled: () => true,
  durableRftLifecycleEnabled: () => true,
  vehicleIdentityTitle: () => '13000769',
  displayStockNumber: value => value.stock || '13000769',
  salespersonAssignmentIdempotencyKey: () => 'idempotency-734',
  refreshEmailVehicleLocations: async () => { refreshCalls += 1; return true; },
  renderAll: () => { renderCalls += 1; },
};
vm.createContext(actionContext);
vm.runInContext(`${actionSource}\nthis.book = markRftTransportBooked; this.collect = markRftVehicleCollected; this.confirm = markRftConfirmation;`, actionContext);
const staleBooking = actionContext.book('11111111-1111-4111-8111-111111111111', true);
setImmediate(() => {
  actionContext.app.rftTransportActionGeneration += 1;
  pendingBooking({ ok: true, code: 'rft_transport_booked', data: { vehicle_id: actionVehicle.__emailVehicleId } });
});
staleBooking.then(async result => {
  assert.strictEqual(result, false, 'Stale booking callback is ignored');
  assert.deepStrictEqual(bookingCalls, [['11111111-1111-4111-8111-111111111111', 7, 'idempotency-734']], 'Booked handler dispatches exact successor RPC arguments');
  assert.strictEqual(refreshCalls, 0, 'Stale booking does not refresh or render over newer state');
  actionVehicle.rftTransportBookedAt = '2026-08-28T04:00:00Z';
  const collected = await actionContext.collect('11111111-1111-4111-8111-111111111111', true);
  assert.strictEqual(collected, true, 'Collected handler completes with authoritative read-back');
  assert.deepStrictEqual(collectionCalls, [['11111111-1111-4111-8111-111111111111', 7, 'idempotency-734']], 'Collected handler dispatches exact successor RPC arguments');
  assert.strictEqual(refreshCalls, 1, 'Successful collection refreshes authoritative state');
  assert.ok(renderCalls > 0, 'Handlers remain wired to the normal render path');
  actionVehicle.rftConfirmed = false;
  actionVehicle.__emailVehicleVersion = 8;
  const confirmed = await actionContext.confirm('11111111-1111-4111-8111-111111111111', true);
  assert.strictEqual(confirmed, true, 'Unchecked RFT’d handler records authoritative confirmation');
  assert.deepStrictEqual(confirmationCalls[0], ['11111111-1111-4111-8111-111111111111', 8, true, 'idempotency-734'], 'RFT’d tick dispatches exact successor vehicle/version/value/idempotency');
  actionVehicle.__emailVehicleVersion = 9;
  const unconfirmed = await actionContext.confirm('11111111-1111-4111-8111-111111111111', false);
  assert.strictEqual(unconfirmed, true, 'Checked RFT’d handler permits the guarded accidental-confirmation reversal');
  assert.deepStrictEqual(confirmationCalls[1], ['11111111-1111-4111-8111-111111111111', 9, false, 'idempotency-734'], 'RFT’d untick dispatches exact successor vehicle/version/value/idempotency');
  assert.strictEqual(refreshCalls, 3, 'Both RFT’d mutations refresh authoritative state');
}).catch(error => { console.error(error); process.exitCode = 1; });

assert.match(css, /rft-transport-controls/);
assert.match(css, /@media[\s\S]*rft-transport-controls/);
console.log('Vehicle Locations RFT transport controls regression: PASS');
