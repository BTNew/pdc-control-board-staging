'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const cleanup = require('./pdc-workshop-tile-cleanup.js');

test('single-click planner selection hides the duplicate top detail panel', () => {
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, false), true);
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, undefined), true);
});

test('explicit focused-booking mode retains detailed booking controls', () => {
  assert.equal(cleanup.shouldHideSelectionPanel({ id: 'booking-1' }, true), false);
  assert.equal(cleanup.shouldHideSelectionPanel(null, false), false);
});

test('canonical bootstrap loads the tile cleanup asset', () => {
  const source = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(source, /pdc-workshop-tile-cleanup\.js\?v=2026\.09\.10\.01/);
});

test('planner tiles retain their own lifecycle and drag controls', () => {
  const planner = fs.readFileSync('workshop-planner.js', 'utf8');
  assert.match(planner, /data-workshop-start-plan=/);
  assert.match(planner, /data-workshop-stop-plan=/);
  assert.match(planner, /data-workshop-complete-plan=/);
  assert.match(planner, /data-workshop-resize-plan=/);
  assert.match(planner, /draggable="true"/);
});
