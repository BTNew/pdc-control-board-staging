'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const appSource = fs.readFileSync(__dirname + '/app.js', 'utf8');
const plannerSource = fs.readFileSync(__dirname + '/workshop-planner.js', 'utf8');
const indexSource = fs.readFileSync(__dirname + '/index.html', 'utf8');

function extract(source, name) {
  const start = source.indexOf('function ' + name + '(');
  assert.ok(start >= 0, name + ' must exist in the installed source');
  const tail = source.slice(start);
  const next = /\n(?:async )?function \w+\(/.exec(tail);
  return next ? tail.slice(0, next.index) : tail;
}

function fixture(rawVehicle) {
  let matches = [];
  const context = {
    window: {},
    workshopSharedModeActive: () => false,
    workshopCurrentSearchLookup: () => null,
    workshopSearchMatches: () => matches,
    workshopState: () => ({ searchKey: '' }),
    vehicleKeyNumber: v => v.keyNumber,
    displayStockNumber: v => v.stock,
    vehicleCustomerName: v => v.client,
    displayVehicle: v => v.vehicle,
    workshopOutstandingDisabledReasonLabel: () => 'Hours required',
    workshopBookingSearchMeta: () => ({ station: 'Electrical', bay: 'Bay 8', date: 'Future', time: '07:00–08:00', status: 'Planned' }),
  };
  vm.createContext(context);
  // Use the real app identity/escaping helpers before the dynamic planner helpers,
  // matching the installed dependency order rather than stubbing the broken label.
  for (const name of ['cleanNavisionText', 'vehicleJobcardNumber', 'escapeHtml']) {
    vm.runInContext(extract(appSource, name), context);
  }
  for (const name of ['workshopSnapshotVehicleToPlannerRow', 'workshopSearchJobCards', 'workshopSearchResultsHtml']) {
    vm.runInContext(extract(plannerSource, name), context);
  }
  const vehicle = context.workshopSnapshotVehicleToPlannerRow(rawVehicle, [], 'BUS_4X4');
  return {
    context,
    vehicle,
    render(patch = {}) {
      matches = [{ vehicle, vehicleIdentity: 'shared:synthetic-vehicle', bookings: [], candidateAvailable: true, ...patch }];
      return context.workshopSearchResultsHtml('JC-LINK-B', []);
    },
  };
}

test('linked-only snapshot job cards remain visible in every selectable or disabled search row', () => {
  const f = fixture({
    id: 'synthetic-vehicle', stock_number: 'TEST-STOCK', key_number: 'TEST-KEY',
    job_card_number: null, job_card_numbers: ['JC-LINK-A', 'JC-LINK-B'],
    customer_name: 'Synthetic customer', vehicle_description: 'Synthetic vehicle',
  });
  assert.equal(f.context.vehicleJobcardNumber(f.vehicle), '', 'reproduce the missing singular primary');
  for (const patch of [
    {},
    { returnedBookings: [{ id: 'returned', hours: 2 }] },
    { bookings: [{ id: 'booked' }] },
    { candidateAvailable: false, candidateDisabledReason: 'hours' },
    { archived: true },
  ]) {
    const html = f.render(patch);
    assert.match(html, /JC JC-LINK-A, JC-LINK-B/);
    assert.doesNotMatch(html, /JC —/);
  }
  assert.match(f.render(), /data-workshop-search-unbooked-identity="shared:synthetic-vehicle"/);
  assert.match(f.render({ returnedBookings: [{ id: 'returned', hours: 2 }] }), /data-workshop-select-returned-plan="returned"/);
  assert.match(f.render({ bookings: [{ id: 'booked' }] }), /data-workshop-search-booking-id="booked"/);
});

test('search labels preserve primary cards, deduplicate linked cards and escape display text', () => {
  const f = fixture({ job_card_number: 'JC-PRIMARY', job_card_numbers: ['JC-PRIMARY', ' JC-LINK-B ', '<script>fixture</script>'] });
  const html = f.render();
  assert.match(html, /JC JC-PRIMARY, JC-LINK-B, &lt;script&gt;fixture&lt;\/script&gt;/);
  assert.equal((html.match(/JC-PRIMARY/g) || []).length, 1);
  assert.doesNotMatch(html, /<script>/);
  assert.match(fixture({ job_card_number: null, job_card_numbers: [] }).render(), /JC —/);
});

test('both dynamic planner loads and their app loader refresh the linked-card label asset', () => {
  const marker = 'search-jobcards=2026.10.26.01';
  const plannerLoads = appSource.split('\n').filter(line => line.includes('loadExternalScript(`workshop-planner.js?'));
  assert.equal(plannerLoads.length, 2);
  assert.ok(plannerLoads.every(line => line.includes(marker)));
  const appTag = indexSource.match(/<script\b[^>]*src="app\.js\?[^"]*"[^>]*>/);
  assert.ok(appTag && appTag[0].includes(marker));
});
