/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r518 (F132): the Navision JITA number completes Parts Jita. The JITA ETA paste does not.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const upPath = 'supabase/migrations/20261023220000_r518_navision_jita_station_tick.sql';
const downPath = 'supabase/rollbacks/20261023220000_r518_navision_jita_station_tick.down.sql';
const up = fs.readFileSync(upPath, 'utf8');
const down = fs.readFileSync(downPath, 'utf8');
const between = (text, tag) => {
  const parts = text.split('$' + tag + '$');
  assert.equal(parts.length, 3, tag);
  return parts[1];
};

test('the tick function reads the Navision number and not the JITA ETA or the email parts date', () => {
  const tick = between(up, 'r518tick');
  const trg = between(up, 'r518trg');
  assert.match(tick, /validated-navision-import-v1/);
  assert.match(tick, /jitQty/);
  assert.match(tick, /work_key = 'PARTS'/);
  assert.doesNotMatch(tick, /pdc_jita_eta|worst_eta|set_parts_eta/);
  assert.doesNotMatch(trg, /pdc_jita_eta|worst_eta|set_parts_eta/);
  assert.match(up, /navision_jita_station_tick_518/);
  assert.match(up, /304, 'r518'/);
  assert.match(up, /'F132'/);
  assert.match(up, /Craig approved go-live/);
  assert.doesNotMatch(up, /PREVIEW/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.doesNotMatch(up, /\r/);
  assert.doesNotMatch(down, /\r/);
});

test('undo drops the trigger before it restores rows and does not touch the email parts writer body', () => {
  const dropAt = down.indexOf('DROP TRIGGER tick_parts_jita_from_navision_518');
  const workAt = down.indexOf('UPDATE public.vehicle_work_items');
  assert.ok(dropAt > 0 && workAt > dropAt);
  assert.match(down, /pdc_772/);
  assert.doesNotMatch(down, /CREATE OR REPLACE FUNCTION public\.set_parts_eta/);
  assert.doesNotMatch(down, /DROP TABLE public\.pdc_jita_eta/);
});

test('r524 paints the full green tick only when the import is missing or green', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  const sales = fs.readFileSync('sales/pmb-stations.js', 'utf8');
  const body = app.slice(app.indexOf('function incomingWorkChecklistHtml'), app.indexOf('function workStatusLegendHtml'));
  const importedAt = body.indexOf('importedPartsStatus(vehicle)');
  const completeAt = body.indexOf('Parts Jita complete. Navision JITA number');
  assert.ok(importedAt > 0 && completeAt > importedAt, 'imported status is read before the full green tick');
  assert.match(body, /jitaNumber && !isActivePartsStoppage\(vehicle\) && \(!imported \|\| imported\.colour === 'green'\)/);
  const salesBody = sales.slice(sales.indexOf("if (def.key === 'parts')"));
  assert.match(salesBody, /jita && !partsStoppage\(v\) && \(!imp \|\| imp\.colour === 'green'\)/);
  assert.ok(salesBody.indexOf('const imp = imported') < salesBody.indexOf('Parts Jita complete. Navision JITA number'));
  assert.match(fs.readFileSync('index.html', 'utf8'), /app\.js\?[^"]*r518=2026\.10\.23\.r518/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r524=2026\.10\.24\.r524/);
  assert.match(fs.readFileSync('sales/index.html', 'utf8'), /pmb-stations\.js\?v=2026\.10\.23\.r499b&amp;r518=2026\.10\.23\.r518&amp;r524=2026\.10\.24\.r524/);
});
