/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r465 (F78): the fitter Running row gets its own strip on planner tiles and
// overview bars, and overview bar labels show only Key · JC plus the customer.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const fitters = require('./pdc-fitters.js');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');

const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');
const css = read('pdc-running-row.css');
const rule = selector => {
  const start = css.indexOf(`${selector} {`);
  assert.ok(start >= 0, `missing rule ${selector}`);
  return css.slice(start, css.indexOf('}', start));
};
const px = (block, prop) => {
  const match = new RegExp(`(?:^|[;{\\s])${prop}:\\s*(-?[\\d.]+)px`).exec(block);
  assert.ok(match, `${prop} in ${block}`);
  return Number(match[1]);
};
// Synthetic identities only.
const progress = stale => ({ percent: 20, running: 1, stale: stale ? 1 : 0, total_hours: 10, completed_hours: 2,
  current: [{ stale, section: '1', booking_id: 'b1', technician: 'Demo technician', description: 'Section 1 — Demonstration section with a very long description that cannot fit on one line', line_identity: 'source:demo', elapsed_minutes: 300, allowance_minutes: 60 }] });

function renderBars() {
  const snap = fixture.emptySnapshot();
  const bus = snap.board.bays.filter(bay => bay.stage_code === 'BUS_4X4');
  snap.board.bookings.push(
    fixture.booking(1, bus[0], undefined, { status: 'planned', scheduled_start_at: '2026-09-15T01:00:00Z', scheduled_end_at: '2026-09-15T05:00:00Z' }),
    fixture.booking(2, bus[1], undefined, { status: 'started', actual_start_at: '2026-09-15T01:00:00Z', scheduled_start_at: '2026-09-15T01:00:00Z', scheduled_end_at: '2026-09-15T05:00:00Z', fitter_progress: progress(true) }));
  globalThis.window = { PdcFitters: fitters };
  try {
    return overview.render(overview.buildModel(snap), { startDate: '2026-09-15', dayCount: 1, now: new Date('2026-09-15T09:00:00+08:00') });
  } finally { delete globalThis.window; }
}
const bars = html => [...html.matchAll(/<button type="button" class="control-board-timeline-job[\s\S]*?<\/button>/g)].map(m => m[0]);

test('overview bar labels show Key · JC and the customer only, never Stock; the hover title keeps the full identity', () => {
  const list = bars(renderBars());
  assert.equal(list.length, 2);
  for (const bar of list) {
    const label = /<strong>([\s\S]*?)<\/strong>/.exec(bar)[1];
    assert.match(label, /^Key \d+ · JC DEMO-JC-\d+$/);
    assert.doesNotMatch(label, /Stock/);
    const customer = /<span class="control-board-timeline-customer">([\s\S]*?)<\/span>/.exec(bar)[1];
    assert.match(customer, /^Demonstration customer \d+$/);
    const visible = bar.replace(/ (?:title|aria-label)="[^"]*"/g, '');
    assert.doesNotMatch(visible.replace(/<[^>]+>/g, ' '), /Stock/);
    assert.doesNotMatch(visible, /Demonstration Hilux DCC/, 'vehicle description is hover-only');
    assert.match(bar, /title="[^"]*Stock DEMO-\d+/);
  }
  assert.match(list[1], /class="fitter-running is-stale"/);
});

test('admin blocks keep their label', () => {
  assert.match(read('control-board-overview.js'), /item\.kind === 'admin' \? escape\(title\) : `Key \$\{escape\(person\.key\)\} · JC \$\{escape\(person\.job\)\}`/);
});

test('planner tile: identity, Running strip, buttons and progress bar occupy separate vertical bands', () => {
  const fitterCss = read('pdc-fitters.css');
  const plannerCss = read('workshop-planner.css');
  // Existing bands from the bottom: progress bottom 3 / height 10; buttons bottom 16 / height 20.
  assert.match(fitterCss, /\.workshop-plan-chip > \.fitter-progress\.is-compact \{ bottom:3px; right:12px; height:10px;/);
  assert.match(fitterCss, /\.workshop-plan-chip:has\(>\.fitter-progress\) > \.workshop-plan-lifecycle-actions \{ bottom:16px; \}/);
  assert.match(plannerCss, /\.workshop-plan-lifecycle-actions \{[^}]*height: 20px;/);
  const progressBand = [3, 13], actionsBand = [16, 36];
  const running = rule('.workshop-plan-chip > .fitter-running');
  assert.match(running, /position:absolute/);
  assert.match(running, /flex-wrap:nowrap/);
  assert.match(running, /overflow:hidden/);
  const runningBand = [px(running, 'bottom'), px(running, 'bottom') + px(running, 'height')];
  const mainBottom = Number(/height:calc\(100% - (\d+)px\)/.exec(rule('.workshop-plan-chip:has(>.fitter-running) > .workshop-plan-main'))[1]);
  const bands = [progressBand, actionsBand, runningBand, [mainBottom, Infinity]];
  bands.forEach((a, i) => bands.slice(i + 1).forEach(b => assert.ok(a[1] <= b[0] || b[1] <= a[0], `${a} overlaps ${b}`)));
  // The identity lines keep the space they had before the strip (124 - 38 = 142 - 56).
  assert.equal(px(rule('.workshop-plan-chip.planner-identity-chip:has(>.fitter-running)'), 'height') - mainBottom, 124 - 38);
  assert.match(css, /\.workshop-bay-lane:has\(>\.workshop-plan-chip\.planner-identity-chip>\.fitter-running\) \{ min-height:154px; \}/);
  assert.match(rule('.workshop-plan-chip > .fitter-running > *'), /text-overflow:ellipsis/);
});

test('overview Running bar: label row, Running row and progress strip fit the 40px bar without overlap', () => {
  const styles = read('styles.css');
  assert.match(styles, /#workflow \.control-board-timeline-job \{[^}]*height:40px;[^}]*border:1px solid/);
  assert.match(read('pdc-fitters.css'), /\.fitter-progress\.is-compact \{ position:absolute; bottom:2px; left:3px; right:3px; height:5px;/);
  const grid = rule('#workflow .control-board-timeline-job:has(>.fitter-running)');
  assert.match(grid, /display:grid/);
  const rows = /grid-template-rows:(\d+)px (\d+)px/.exec(grid).slice(1).map(Number);
  const contentBottom = px(grid, 'padding-top') + rows[0] + px(grid, 'row-gap') + rows[1];
  const progressTop = 40 - 2 /* borders */ - 2 - 5;
  assert.ok(contentBottom <= progressTop, `${contentBottom} > ${progressTop}`);
  // Planned bars: two 12.5px lines (10px x 1.25) from the top, a 2px gap, above the strip.
  const planned = rule('#workflow .control-board-timeline-job:has(>.fitter-progress)');
  assert.match(planned, /justify-content:flex-start/);
  assert.ok(px(planned, 'padding-top') + 12.5 + 2 + 12.5 <= progressTop);
  assert.match(rule('#workflow .control-board-timeline-job > .fitter-running'), /grid-row:2/);
  assert.match(rule('#workflow .control-board-timeline-job:has(>.fitter-running) > strong'), /grid-row:1/);
  assert.match(rule('#workflow .control-board-timeline-job:has(>.fitter-running) > .control-board-timeline-customer'), /grid-row:1/);
  assert.match(rule('#workflow .control-board-timeline-job > .fitter-running > *'), /text-overflow:ellipsis/);
});

test('the Running row keeps its full hover title and the planner Reset action', () => {
  const html = fitters.progressHtml(progress(true), true, { resettable: true });
  assert.match(html, /<span class="fitter-running is-stale" title="Section 1 — Demonstration section with a very long description that cannot fit on one line · Demo technician · 5h 00m of 1h 00m · check">/);
  assert.match(html, /data-fitter-item-reset="b1"/);
  assert.equal(fitters.progressHtml({ percent: 50, current: [] }, true).includes('fitter-running'), false);
});

test('index.html loads pdc-running-row.css after the fitter CSS, and Pages publishes it', () => {
  const html = read('index.html');
  const at = html.indexOf('<link rel="stylesheet" href="pdc-running-row.css?running-row=2026.10.22.r465">');
  assert.ok(at > html.indexOf('href="pdc-conversion-ticks.css'));
  assert.ok(at > html.indexOf('href="pdc-fitters.css'));
  assert.ok(at > html.indexOf('href="workshop-planner.css'));
  assert.match(html, /control-board-overview\.js\?[^"]*running-row=2026\.10\.22\.r465/);
  assert.ok(html.indexOf('src="pdc-auto-reload.js') < html.indexOf('<link rel="stylesheet"'));
  assert.match(read('scripts/build_pages_runtime.js'), /'pdc-running-row\.css'/);
});

test('the Running row CSS stays scoped to planner tiles and overview bars (Fitters screen unchanged)', () => {
  const selectors = css.replace(/\/\*[\s\S]*?\*\//g, '').match(/[^{}]+(?=\{)/g).flatMap(s => s.split(',')).map(s => s.trim());
  for (const selector of selectors) assert.match(selector, /^(?:\.workshop-plan-chip|\.workshop-bay-(?:row|lane)|#workflow \.control-board-timeline-job)/, selector);
});
