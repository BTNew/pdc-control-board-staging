'use strict';
// r804 (F419, Craig 1 Nov 18:33): a parts ETA in the future unticks Parts complete and makes the box red.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const api = require('./pdc-parts-stoppage.js');

test('r804: future-ETA flags read red and unticked, with the ETA in the hover', () => {
  const flags = { colour: 'red', label: 'Parts outstanding — ETA 30/11/26', parts_complete: false, override_source: 'parts_eta_future', eta_date: '2026-11-30' };
  const st = api.partsFlagsState(flags);
  assert.equal(st.done, false); assert.equal(st.red, true); assert.equal(st.eta, '2026-11-30');
  const html = api.completeTickHtml({ vehicleId: '610a64eb-bb72-43e2-973b-6efde0027603', partsDone: false, partsRed: true, partsEta: st.eta });
  assert.ok(html.includes('is-outstanding') && !/checked/.test(html) && html.includes('30/11/26'));
});

test('r804: server rule, label colour, cache tags, fault log', () => {
  const sql = fs.readFileSync('supabase/migrations/20261101190000_r804_future_eta_parts_red.sql', 'utf8');
  assert.match(sql, /'parts_eta_future'/);
  assert.match(sql, /v_eta > v_today/);
  assert.match(sql, /b\.set_at > v_eta_at/);
  assert.match(sql, /CREATE TRIGGER pdc_parts_eta_revision_804 AFTER INSERT OR UPDATE OR DELETE ON public\.pdc_parts_stoppage_564/);
  assert.match(sql, /'future_eta_parts_red_804', 'F419'/);
  assert.match(fs.readFileSync('pdc-parts-confirmation.js', 'utf8'), /startsWith\('import:Parts outstanding — ETA '\)\) return 'parts-status-stoppage'/);
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /pdc-parts-stoppage\.js\?[^']*&r804=2026\.11\.01\.r804/);
  assert.match(entry, /pdc-parts-confirmation\.js\?[^']*&r804=2026\.11\.01\.r804/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F419 \|/m);
});
