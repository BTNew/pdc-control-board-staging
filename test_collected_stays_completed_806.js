'use strict';
// r806 (F422, Craig 1 Nov 19:38): a Collected car stays completed until Navision delivers or drops it.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r806: service import skips collected / delivered cars; check and fault log', () => {
  const sql = fs.readFileSync('supabase/migrations/20261101194500_r806_collected_stays_completed.sql', 'utf8');
  assert.match(sql, /pdc_rft_transport_lifecycle_receipts_734 t WHERE t\.vehicle_id = v\.id AND t\.action IN \('collected', 'delivered'\)/);
  assert.match(sql, /'collected_stays_completed_806', 'F422'/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F422 \|/m);
});
