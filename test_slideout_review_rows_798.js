/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r798 (F408, Craig 1 Nov 2026): Review control on its own row, Review box full width, stale row-2 class cleared, hover text.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
test('r798: review row, full width, stale class cleared, hover title, cache tags', () => {
  const css = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8');
  const js = fs.readFileSync('pdc-vehicle-slideout.js', 'utf8');
  assert.match(css, /li > div\[data-review-control\] \{ grid-column: 1 \/ -1 !important; grid-row: 3;/);
  assert.match(css, /\.pdc-op-below > \.authenticated-operation-station \{ flex: 1 1 100%; width: 100%;/);
  assert.match(js, /li\.classList\.remove\('vso-has-move', 'vso-move-row2'\)/);
  assert.match(js, /if \(desc && !desc\.title\) desc\.title = desc\.textContent\.trim\(\)/);
  assert.match(js, /r798=2026\.11\.01\.r798`/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /pdc-vehicle-slideout\.js\?[^']*&r798=2026\.11\.01\.r798'/);
});
