/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { fitterLineCardHtml } = require('./pdc-fitters.js');

const state = (over = {}) => ({ editable: true, disabled: false, note: '', open: false, paused: false, jobSeconds: NaN, pauseControl: '', pauseDisabled: true, ...over });
const line = (over = {}) => ({
  line_identity: 'elec-7pin',
  description: '7pin Small Round Wiring Harness',
  stage_code: 'ELECTRICAL',
  hours: 0.75,
  completed: false,
  external_work: false,
  ...over,
});

test('an other-station item offers Start and keeps Done locked until it is started', () => {
  const html = fitterLineCardHtml(line(), 4, state());
  assert.match(html, /data-fitter-item-start="elec-7pin"/);
  assert.match(html, /> Start</);
  assert.match(html, /Press Start first/);
  assert.match(html, /data-fitter-line="elec-7pin"[^>]*disabled/);
  assert.match(html, /ELECTRICAL · 0.75 h/);
  assert.doesNotMatch(html, /data-fitter-pause|data-fitter-action="resume"/);
});

test('a started other-station item can be ticked Done, and a Done item can be unticked', () => {
  const running = fitterLineCardHtml(line({ item_status: 'running' }), 5, state({ jobSeconds: 600 }));
  assert.match(running, /data-fitter-item-start="elec-7pin"[^>]*checked/);
  assert.match(running, /data-fitter-line="elec-7pin"/);
  assert.doesNotMatch(running, /data-fitter-line="elec-7pin"[^>]*disabled/);
  assert.doesNotMatch(running, /Press Start first/);
  assert.doesNotMatch(running, /data-fitter-pause/);
  const done = fitterLineCardHtml(line({ completed: true, item_status: 'done', item_actual_minutes: 48 }), 6, state());
  assert.match(done, /data-fitter-line="elec-7pin"[^>]*checked/);
  assert.doesNotMatch(done, /data-fitter-line="elec-7pin"[^>]*disabled/);
  assert.match(done, /data-fitter-item-start="elec-7pin"[^>]*disabled/);
  assert.match(done, /Done · actual/);
});

test('a view-only other-station card does not invite a tick', () => {
  const html = fitterLineCardHtml(line(), 7, state({ editable: false, disabled: true }));
  assert.match(html, /disabled/);
  assert.doesNotMatch(html, /Press Start first/);
});

test('the fitting page, and not Department 135, offers other-station ticks', () => {
  const src = fs.readFileSync('pdc-fitters.js', 'utf8');
  assert.match(src, /Other station items/);
  assert.match(src, /station_busy/);
  assert.match(src, /cross_station/);
  assert.match(src, /editable && !l\.external_work && !l\.conversion,true/);
  const karratha = fs.readFileSync('karratha/pdc-fitters.js', 'utf8');
  assert.match(karratha, /All other vehicle items \(\$\{other\.length\}\) · View only/);
  assert.doesNotMatch(karratha, /Other station items/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r532=2026\.10\.26\.r532/);
  const up = fs.readFileSync('supabase/migrations/20261026093000_r532_fitter_other_station_ticks.sql', 'utf8');
  const down = fs.readFileSync('supabase/rollbacks/20261026093000_r532_fitter_other_station_ticks.down.sql', 'utf8');
  assert.match(up, /PREVIEW/);
  assert.match(up, /SQL is not applied/);
  assert.match(up, /clock_version integer; extra jsonb/);
  assert.match(up, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(up, /true,314,'r532'/);
  assert.match(up, /Pin count stays 241/);
  assert.doesNotMatch(up, /<>242/);
  assert.match(down, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(down, /sort_order=314/);
  assert.doesNotMatch(down, /<>242/);
  assert.match(up, /cross_station_ticked/);
  assert.match(down, /cross_station_tick/);
});
