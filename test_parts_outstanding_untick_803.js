'use strict';
// r803 (F418, Craig 1 Nov 17:48): untick Parts complete over a green import = parts outstanding, red.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

function loadApi() { return require('./pdc-parts-stoppage.js'); }

test('r803: off over a green import is red; off over a non-green import shows the import; email stays', () => {
  const api = loadApi();
  assert.ok(api && typeof api.boardCompleteFlags === 'function', 'api exposed');
  const green = { colour: 'green', label: 'All active jobs parts-ready', parts_complete: true, feed: 'separate_parts_status', jobs: [{ colour: 'green' }] };
  const red = api.boardCompleteFlags(green, false, 'craig@x', '2026-11-01T10:00:00Z');
  assert.equal(red.colour, 'red');
  assert.equal(red.parts_complete, false);
  assert.equal(red.override_source, 'board_parts_outstanding');
  assert.equal(red.jobs[0].colour, 'red');
  assert.equal(red.import_status.colour, 'green');
  const orange = { colour: 'orange', label: 'Parts on order — outstanding', parts_complete: false };
  assert.equal(api.boardCompleteFlags(orange, false, 'x', 'y').colour, 'orange');
  const back = api.boardCompleteFlags(red, true, 'craig@x', '2026-11-01T10:05:00Z');
  assert.equal(back.colour, 'green');
  assert.equal(back.import_status.colour, 'green', 'ticking again goes back over the original import, not the red mark');
  const st = api.partsFlagsState(red);
  assert.equal(st.done, false); assert.equal(st.red, true);
  const html = api.completeTickHtml({ vehicleId: '610a64eb-bb72-43e2-973b-6efde0027603', partsDone: false, partsRed: true, partsWho: 'craig@x' });
  assert.ok(html.includes('is-outstanding') && !/checked/.test(html));
});

test('r803: server, label colour, cache tags and fault log', () => {
  const sql = fs.readFileSync('supabase/migrations/20261101180000_r803_parts_outstanding_untick.sql', 'utf8');
  assert.match(sql, /CREATE TABLE public\.pdc_parts_board_outstanding_803/);
  assert.match(sql, /'board_parts_outstanding'/);
  assert.match(sql, /'parts_outstanding_untick_803', 'F418'/);
  assert.match(fs.readFileSync('pdc-parts-confirmation.js', 'utf8'), /Parts outstanding — marked on the board'\) return 'parts-status-stoppage'/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-parts-stoppage\.js\?[^']*&r803=2026\.11\.01\.r803/);
  assert.match(entry, /pdc-parts-confirmation\.js\?[^']*&r803=2026\.11\.01\.r803/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F418 \|/m);
});
