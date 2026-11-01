/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r797 (F407, Craig 1 Nov 2026): drawer line layout. Move to drop-down has a fixed width; any PO chip puts chip + Move to on row 2.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r797: fixed-width Move to, PO chip rows, group header row, cache tags', () => {
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
  const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(css, /\.vso-move select \{ width: 8\.5rem !important;/);
  assert.match(css, /li\.vso-move-row2 > \.vso-move \{ grid-column: 2 \/ -1; grid-row: 2; justify-self: end; \}/);
  assert.match(css, /li\.pdc-sublet-group \{ display: flex !important;/);
  assert.match(js, /li\.querySelector\('\.pdc-sublet-po-inline, \.pdc-sublet-po-nopo, \.pdc-sublet-po-ref'\)\) li\.classList\.add\('vso-move-row2'\)/);
  assert.match(js, /r797=2026\.11\.01\.r797`/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?[^']*&r797=2026\.11\.01\.r797'/);
});
