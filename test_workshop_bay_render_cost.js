'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('workshop-planner.js', 'utf8');
function extract(text, name) {
  const start = text.indexOf(`function ${name}(`);
  assert(start >= 0, name);
  return text.slice(start, text.indexOf('\nfunction ', start + 10));
}
function fixture(text = source) {
  const counts = { segment: 0, calendar: 0, blocks: 0, time: 0 };
  const blocks = [
    { id: 'maintenance', stage: 'FITTING', bay: 2, visible: true },
    { id: 'elsewhere', stage: 'TYRE', bay: 1, visible: true },
  ];
  const ctx = {
    WORKSHOP_PLANNER_CONFIG: { dayLengthMinutes: 630 },
    workshopStageBayCount: () => 13,
    workshopEntrySegmentForDate: (entry) => { counts.segment++; return entry.visible ? { start: entry.minute || 0, end: (entry.minute || 0) + 60, continuesNext: !!entry.continuesNext } : null; },
    workshopLoadAdminBlocks: () => { counts.blocks++; return blocks; },
    workshopAdminBlockSegment: block => block.visible,
    workshopAdminBlockHtml: block => `<aside>${block.id}</aside>`,
    workshopUnavailableTimeHtml: () => { counts.calendar++; return '<i>Lunch break</i>'; },
    workshopDropPreviewHtml: () => '<i hidden>Drop preview</i>',
    workshopBayMechanic: () => 'Fixture mechanic',
    workshopPad: value => String(value).padStart(2, '0'),
    workshopAssigneeOptions: () => '<option>Fixture mechanic</option>',
    escapeHtml: value => String(value ?? ''),
    workshopVehicle: key => key === 'missing' ? null : { stock: key, vehicle: 'Hilux' },
    workshopLoadPlans: () => [],
    isPdcBlocked: () => false,
    workshopEntryIsOvertime: () => false,
    workshopEntryHasAssigneeConflict: () => false,
    workshopState: () => ({ selectedPlanId: 'live' }),
    workshopPartsSummary: () => ({ label: 'Issued', status: 'issued' }),
    workshopEtaRiskForEntry: () => null,
    workshopEtaRiskLabel: () => '',
    cleanNavisionText: value => value,
    workshopPlanLifecycleActionsHtml: entry => `<button>${entry.status}</button>`,
    workshopEntryTimeLabel: () => { counts.time++; return '6:00 am–7:00 am'; },
    vehicleJobcardNumber: () => 'J123',
    displayStockNumber: vehicle => vehicle.stock,
    vehicleCustomerName: () => 'Customer',
    workshopDurationInputValue: value => value,
    workshopStageJobLines: () => [],
    window: {},
  };
  vm.createContext(ctx);
  vm.runInContext(extract(text, 'workshopPlanChipHtml') + '\n' + extract(text, 'workshopBayRowsHtml'), ctx);
  return { ctx, counts, blocks };
}
function rows() {
  return [
    { id: 'later', vehicleKey: 'later', stage: 'FITTING', bay: '2', status: 'planned', startAt: '2026-09-17T03:00:00Z', hours: 1, visible: true },
    { id: 'live', vehicleKey: 'live', stage: 'FITTING', bay: 2, status: 'started', startAt: '2026-09-16T22:00:00Z', hours: 8, visible: true, continuesNext: true },
    { id: 'completed', vehicleKey: 'completed', stage: 'FITTING', bay: 1, status: 'completed', visible: true },
    { id: 'offday', vehicleKey: 'offday', stage: 'FITTING', bay: 1, status: 'planned', visible: false },
    { id: 'other-stage', vehicleKey: 'other-stage', stage: 'TYRE', bay: 1, status: 'planned', visible: true },
    { id: 'invalid-bay', vehicleKey: 'invalid-bay', stage: 'FITTING', bay: 14, status: 'planned', visible: true },
  ];
}
test('bay render preserves order, continued live work, controls and admin blocks', () => {
  const { ctx } = fixture();
  const html = ctx.workshopBayRowsHtml('FITTING', '2026-09-17', rows());
  assert.equal((html.match(/class="workshop-bay-row"/g) || []).length, 13);
  assert.equal((html.match(/data-workshop-plan-id=/g) || []).length, 2);
  assert(html.indexOf('data-workshop-plan-id="live"') < html.indexOf('data-workshop-plan-id="later"'));
  assert(html.includes('is-started') && html.includes('continues-next') && html.includes('is-selected'));
  assert(html.includes('<small class="workshop-plan-time">6:00 am–7:00 am · 8 h</small>'));
  assert(html.includes('<aside>maintenance</aside>'));
  for (const id of ['completed', 'offday', 'other-stage', 'invalid-bay', 'elsewhere']) assert(!html.includes(`="${id}"`) && !html.includes(`<aside>${id}</aside>`));
  assert(html.includes('data-workshop-bay-mechanic-number="13"'));
});
test('crowded planner calculates each visible segment once and shared calendar once per render', () => {
  const { ctx, counts } = fixture();
  const bookings = Array.from({ length: 260 }, (_, i) => ({ id: `p${i}`, vehicleKey: `v${i}`, stage: 'FITTING', bay: i % 13 + 1, status: 'planned', hours: 1, visible: true, startAt: String(i).padStart(4, '0') }));
  const html = ctx.workshopBayRowsHtml('FITTING', '2026-09-17', bookings);
  assert.equal((html.match(/data-workshop-plan-id=/g) || []).length, 260);
  assert.deepEqual(counts, { segment: 260, calendar: 1, blocks: 1, time: 260 });
});
test('subsequent render recomputes changed bookings, calendar and admin blocks', () => {
  const { ctx, counts, blocks } = fixture();
  const bookings = rows();
  ctx.workshopBayRowsHtml('FITTING', '2026-09-17', bookings);
  bookings[0].visible = false;
  blocks[0].visible = false;
  const html = ctx.workshopBayRowsHtml('FITTING', '2026-09-18', bookings);
  assert(!html.includes('data-workshop-plan-id="later"'));
  assert(!html.includes('<aside>maintenance</aside>'));
  assert.equal(counts.calendar, 2);
  assert.equal(counts.blocks, 2);
});
test('standalone chip rendering still resolves its own date segment', () => {
  const { ctx, counts } = fixture();
  assert(ctx.workshopPlanChipHtml(rows()[0], '2026-09-17', []).includes('data-workshop-plan-id="later"'));
  assert.equal(counts.segment, 1);
  assert.equal(ctx.workshopPlanChipHtml({ ...rows()[0], visible: false }, '2026-09-18', []), '');
});

module.exports = { fixture, rows };
