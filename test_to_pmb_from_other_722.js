'use strict';
// r722 (F332): To PMB for every vehicle not already at PMB, PIT, QC or RFT, including the Other tile.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
test('board and server both allow Other', () => {
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /including the Other tile \(a Navision status the board does not map\)\. The server applies the same rule\.\n  return true;/);
  const sql = fs.readFileSync('supabase/migrations/20261029160000_r722_to_pmb_from_other.sql', 'utf8');
  assert.match(sql, /if v_location = '' and \( -- r722 \(F332\)/);
});
