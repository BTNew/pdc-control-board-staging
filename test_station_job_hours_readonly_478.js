'use strict';
// r478 (F91): Craig, 22 Oct: the estimated hours in a planner station's vehicle job popup (e.g. 'Fitting vehicle job')
// must not be changeable by hand. The hours show read-only (sum of the authenticated lines), there is no input or
// spinner, and nothing in the popup writes hours. The old 'Save estimated time / allocation' button on the shared
// board only ever sent set_workshop_stage_estimated_minutes_407 (a manual 'Planner stage time adjustment'), so it
// is gone there; the local fallback keeps its line work-area save, which no longer reads any typed hours.
// Runs the real openWorkshopVehicleJob / workshopJobLineRowsHtml from workshop-planner.js against a stub DOM.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm');
const src = fs.readFileSync(process.env.PDC_R478_PLANNER || 'workshop-planner.js', 'utf8');
const grab = name => { const i = src.indexOf(`function ${name}(`); assert.ok(i >= 0, name); let depth = 0; const j = src.indexOf('{', src.indexOf(')', i)); for (let k = j; k < src.length; k++) { if (src[k] === '{') depth++; else if (src[k] === '}') { depth--; if (!depth) return src.slice(i, k + 1); } } };

function harness({ shared, stage = 'FITTING' }) {
  const calls = { dispatch: [], saves: [], audits: [], plans: [], notes: [] };
  const listeners = {};
  let html = '';
  const form = { dataset: { workshopJobStage: stage, workshopJobKey: 'veh-1' }, addEventListener: (t, f) => { listeners[t] = f; } };
  const el = () => ({ addEventListener() {}, focus() {}, dataset: {} });
  const overlay = {
    className: '', dataset: {}, setAttribute() {}, addEventListener() {}, remove() {},
    set innerHTML(v) { html = v; }, get innerHTML() { return html; },
    querySelectorAll: () => [],
    querySelector: sel => sel === '[data-workshop-job-form]' ? form
      : sel === 'input' ? (/<input\b/.test(html) ? el() : null)
      : sel === 'select' ? (/<select\b/.test(html) ? el() : null)
      : /data-workshop-job-close|data-workshop-job-full-vehicle/.test(sel) ? el()
      : /estimated_hours|estimated-hours-total/.test(sel) ? (/name="estimated_hours"/.test(html) || /estimated-hours-total/.test(sel) ? { addEventListener() {}, value: '9', textContent: '' } : null)
      : null,
  };
  const lines = [
    { id: 'L1', text: 'Tow bar', stage: 'FITTING', hours: 1.5 },
    { id: 'L2', text: 'Fire extinguisher', stage: 'FITTING', hours: 0.5 },
  ];
  const vehicle = { id: 'veh-1', version: 3, workshopAdditionalHoursByStage: { FITTING: 0.25 }, workshopEstimatedHoursByStage: {}, workshopJobLineAssignments: {} };
  const plan = { id: 'plan-1', vehicleKey: 'veh-1', stage, status: 'planned', hours: 2, operationEstimateHours: 2, sharedBookingId: 'b-1', sharedVersion: 1 };
  const ctx = {
    console, Math, Number, String, Object, Array, Map, Set, JSON, FormData: class { constructor() { this.m = new Map(Object.entries(harness.formValues || {})); } get(k) { return this.m.has(k) ? this.m.get(k) : null; } },
    window: {}, document: { querySelector: () => null, createElement: () => overlay, body: { appendChild() {}, classList: { add() {}, remove() {} } } },
    WORKSHOP_STAGE_SEQUENCE: ['FITTING', 'ELECTRICAL', 'BUS_4X4'], WORKSHOP_PLAN_STORAGE_KEY: 'plans',
    normalizePmbStage: v => String(v || '').trim().toUpperCase(), inferredPmbStage: () => stage, workshopState: () => ({ stage }),
    workshopVehicle: () => vehicle, workshopPartsSummary: () => ({ status: 'ok', text: 'Not ordered' }), pdcRequirementDefinitions: () => [],
    pdcJobRequired: () => true, pdcJobComplete: () => false, pmbStageJobDef: () => null, workshopSelectedBusGroup: () => null,
    workshopLoadPlans: () => [plan], vehicleKey: v => v.id, workshopDepartmentLayout: () => ({ categoryLabel: c => c }), pmbStageLabel: s => s === 'FITTING' ? 'Fitting' : s,
    workshopStageJobLines: () => lines, workshopExactDurationHours: h => Number(h), workshopCalculatedStageHours: () => 2,
    workshopDefaultBookingHours: () => 1, workshopSharedModeActive: () => shared, escapeHtml: v => String(v ?? ''),
    workshopVehicleIdentitySummaryHtml: () => '<span>JC TEST</span>', vehicleCustomerName: () => 'Test', teamNotesText: () => '',
    cleanNavisionText: v => String(v || ''), vehicleJobcardNumber: () => 'TEST-JC', workshopResolvedJobLines: () => lines,
    workshopImportedJobLines: () => lines, workshopJobStageOptionsHtml: s => `<option selected>${s}</option>`,
    openVehicleModal() {}, workshopRequireOperatorProfile: () => true, workshopNotify: m => calls.notes.push(m),
    workshopDispatchSharedAction: async (name, payload) => { calls.dispatch.push({ name, payload }); return { ok: true }; },
    workshopStageEstimateSharedPayload: (v, p, s, m) => ({ totalMinutes: m }),
    workshopJobLineAssignments: v => ({ ...v.workshopJobLineAssignments }), workshopAdditionalHoursMap: v => ({ ...v.workshopAdditionalHoursByStage }),
    workshopEstimatedHoursMap: v => ({ ...v.workshopEstimatedHoursByStage }), workshopClampLineHours: h => Number(h), workshopClampDurationHours: h => Number(h),
    workshopManualDurationAllocation: (r, i) => ({ total: Number(r), additional: Math.max(0, Number(r) - Number(i)) }),
    workshopHasConflict: () => false, workshopEntryHasAssigneeConflict: () => false,
    saveVehicleEdits: (k, edits) => calls.saves.push(edits), recordVehicleAudit: (v, a, d) => calls.audits.push(d),
    workshopSavePlans: rows => calls.plans.push(rows), workshopCascadePlans: rows => ({ rows }), nowIsoString: () => 'now', renderWorkshopPlanner() {},
  };
  ctx.window = ctx;
  vm.createContext(ctx);
  vm.runInContext([grab('workshopDurationInputValue'), grab('workshopJobLineRowsHtml'), grab('workshopRequiredJobsForStageHtml'), grab('openWorkshopVehicleJob')].join('\n'), ctx);
  ctx.openWorkshopVehicleJob('veh-1', stage, 'plan-1');
  const submit = async values => { harness.formValues = values; await listeners.submit?.({ preventDefault() {}, currentTarget: form }); };
  return { html: () => html, calls, submit };
}

for (const stage of ['FITTING', 'ELECTRICAL', 'BUS_4X4']) {
  test(`r478: ${stage} popup on the shared board shows the hours read-only, with no input and no save`, async () => {
    const h = harness({ shared: true, stage });
    const html = h.html();
    assert.match(html, /data-workshop-estimate-readonly/);
    assert.match(html, /<output data-workshop-estimated-hours-value[^>]*>2<\/output>/);
    assert.doesNotMatch(html, /<input\b/, 'no input of any kind in the popup');
    assert.doesNotMatch(html, /name="estimated_hours"|name="line_hours_/);
    assert.doesNotMatch(html, /type="submit"/);
    assert.doesNotMatch(html, /Save estimated time/);
    assert.match(html, /Open full vehicle/);
    assert.match(html, /data-workshop-job-close/);
    await h.submit({ estimated_hours: '9' }); // a forced/programmatic submit still writes nothing
    assert.equal(h.calls.dispatch.length, 0);
    assert.equal(h.calls.saves.length, 0);
    assert.equal(h.calls.plans.length, 0);
  });
}

test('r478: local fallback keeps the line work-area save; typed hours are ignored and no stage addition is changed', async () => {
  const h = harness({ shared: false });
  const html = h.html();
  assert.doesNotMatch(html, /<input\b/);
  assert.match(html, /<select name="line_stage_L1"/);
  assert.match(html, /data-workshop-line-hours-readonly>1.5</);
  assert.match(html, /type="submit" data-workshop-job-save-allocation>Save line work areas</);
  await h.submit({ estimated_hours: '40', line_stage_L1: 'ELECTRICAL', line_stage_L2: 'FITTING', line_hours_L1: '99', line_hours_L2: '99' });
  assert.equal(h.calls.dispatch.length, 0);
  assert.equal(h.calls.saves.length, 1);
  const edits = h.calls.saves[0];
  assert.deepEqual(JSON.parse(JSON.stringify(edits.workshopJobLineAssignments)), { L1: { stage: 'ELECTRICAL', hours: 1.5 }, L2: { stage: 'FITTING', hours: 0.5 } });
  assert.deepEqual(JSON.parse(JSON.stringify(edits.workshopAdditionalHoursByStage)), { FITTING: 0.25 }, 'existing addition kept, nothing new');
  assert.equal(edits.workshopEstimatedHoursByStage.FITTING, 0.75);
  assert.equal(edits.workshopEstimatedHoursByStage.ELECTRICAL, 1.5);
});

test('r478: no path in the popup source reads typed hours or dispatches the manual stage estimate', () => {
  const body = grab('openWorkshopVehicleJob');
  assert.doesNotMatch(body, /estimated_hours/);
  assert.doesNotMatch(body, /line_hours_/);
  assert.doesNotMatch(body, /setStageEstimatedMinutes/);
  assert.doesNotMatch(body, /workshopManualDurationAllocation/);
  assert.doesNotMatch(grab('workshopJobLineRowsHtml'), /<input\b/);
  assert.doesNotMatch(src, /workshop_clock_tick/);
  assert.match(body, /\.modal-close\[data-workshop-job-close\]'\)\?\.focus\(\{ preventScroll: true \}\)/);
  const css = fs.readFileSync('workshop-planner.css', 'utf8');
  assert.match(css, /\.workshop-current-stage-time \.workshop-estimate-readonly output/);
});
