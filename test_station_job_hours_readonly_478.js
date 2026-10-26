'use strict';
// r478 (F91): Craig, 22 Oct: the estimated hours in a planner station's vehicle job popup (e.g. 'Fitting vehicle job')
// must not be changeable by hand. The hours show read-only (sum of the authenticated lines), there is no input or
// spinner, and nothing in the popup writes hours. The old 'Save estimated time / allocation' button on the shared
// board only ever sent set_workshop_stage_estimated_minutes_407 (a manual 'Planner stage time adjustment'), so it
// is gone there; the local fallback keeps its line work-area save, which no longer reads any typed hours.
// r539 (F153): that popup is no longer drawn. Double-click opens the Vehicle Locations side panel.
// This file still guards the old hours path: the opener writes nothing, and the leftover line renderer has no hours input.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const src = fs.readFileSync(process.env.PDC_R478_PLANNER || 'workshop-planner.js', 'utf8');
const grab = name => { const i = src.indexOf(`function ${name}(`); assert.ok(i >= 0, name); let depth = 0; const j = src.indexOf('{', src.indexOf(')', i)); for (let k = j; k < src.length; k++) { if (src[k] === '{') depth++; else if (src[k] === '}') { depth--; if (!depth) return src.slice(i, k + 1); } } };

function openPanel(key = '13047270') {
  const calls = { opened: [], notes: [] };
  const ctx = {
    window: { PDC_VEHICLE_SLIDEOUT: { open: (id, bucket) => calls.opened.push({ id, bucket }) } },
    document: { querySelector: () => null, body: { classList: { remove() {} } } },
    vehicleLocationsScreenRows: () => [{ stock: '13047270', id: 'veh-1' }],
    vehicleKey: row => row.stock,
    incomingBucketForVehicle: () => 'pmb',
    workshopNotify: message => calls.notes.push(message),
  };
  vm.createContext(ctx);
  vm.runInContext([grab('workshopLocationsVehicle'), grab('openWorkshopVehicleJob')].join('\n'), ctx);
  const opened = ctx.openWorkshopVehicleJob(key, 'FITTING', 'plan-1');
  return { calls, opened };
}

for (const stage of ['FITTING', 'ELECTRICAL', 'BUS_4X4']) {
  test(`r478: ${stage} no longer draws a hours popup or writes a stage estimate`, () => {
    const body = grab('openWorkshopVehicleJob');
    assert.equal(stage.length > 0, true);
    assert.doesNotMatch(body, /data-workshop-estimate-readonly|type="submit"|className = 'modal-overlay/);
    assert.doesNotMatch(body, /name="estimated_hours"|name="line_hours_/);
    const h = openPanel();
    assert.equal(h.opened, true);
    assert.deepEqual(h.calls.opened, [{ id: '13047270', bucket: 'pmb' }]);
    assert.equal(h.calls.notes.length, 0);
  });
}

test('r478: no path in the opener reads typed hours or dispatches the manual stage estimate', () => {
  const body = grab('openWorkshopVehicleJob');
  assert.doesNotMatch(body, /estimated_hours/);
  assert.doesNotMatch(body, /line_hours_/);
  assert.doesNotMatch(body, /setStageEstimatedMinutes/);
  assert.doesNotMatch(body, /workshopManualDurationAllocation/);
  assert.doesNotMatch(grab('workshopJobLineRowsHtml'), /<input\b/);
  assert.doesNotMatch(src, /workshop_clock_tick/);
  assert.doesNotMatch(body, /modal-close/);
  const css = fs.readFileSync('workshop-planner.css', 'utf8');
  assert.match(css, /\.workshop-current-stage-time \.workshop-estimate-readonly output/);
});
