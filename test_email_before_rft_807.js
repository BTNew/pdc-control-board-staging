'use strict';
// r807 (F423, Craig 1 Nov 19:47): Email salesperson before Mark RFT'd; Mark collected only on the RFT page.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { controls } = require('./pdc-rft-actions.js');
const base = { __emailVehicleServerAuthoritative: true, __emailVehicleId: 'v1', __emailVehicleVersion: 3, pdcQcComplete: true,
  pdcQcCompleteAt: '2026-11-01T11:00:00Z', rftTransferredAt: '2026-11-01T11:00:01Z', pdcLocation: 'RFT' };
const opts = { key: 'k', allowed: true, authority: true, inFlight: false, collectionEnabled: true };
const btn = (html, k) => html.match(new RegExp('<button[^>]+data-' + k + '[^>]*>'))?.[0];
test('r807: WPC order and RFT page collect', () => {
  const wpc = controls(base, opts);
  assert.doesNotMatch(btn(wpc, 'rft-transport-booked-key'), /disabled/);
  assert.match(btn(wpc, 'pmb-rft-release-key'), /disabled/);
  assert.equal(btn(wpc, 'rft-collected-key'), undefined);
  const emailed = controls({ ...base, rftTransportDraft: { draft_id: 'd' } }, opts);
  assert.doesNotMatch(btn(emailed, 'pmb-rft-release-key'), /disabled/);
  assert.equal(btn(emailed, 'rft-collected-key'), undefined);
  const rft = controls({ ...base, rftTransportDraft: { draft_id: 'd' }, rftConfirmedAt: '2026-11-01T11:05:00Z' }, opts);
  assert.doesNotMatch(btn(rft, 'rft-collected-key'), /disabled/);
  const sql = fs.readFileSync('supabase/migrations/20261101200000_r807_email_before_rft.sql', 'utf8');
  assert.match(sql, /email_salesperson_required/);
  assert.match(sql, /'email_before_rft_807', 'F423'/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-rft-actions\.js\?[^']*&r807=2026\.11\.01\.r807/);
});
