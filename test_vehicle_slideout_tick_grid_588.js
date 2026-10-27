/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. */
'use strict';
// r588 (F202): Vehicle Locations side panel — hours, GP/PO chip and completion tick must not overlap (Craig 28 Oct 2026).
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const subletPo = require('./pdc-sublet-po.js');

const CSS = fs.readFileSync('pdc-vehicle-slideout.css', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const slideout = require('./pdc-vehicle-slideout.js');
const faults = fs.readFileSync('docs/REPORTED_FAULTS.md', 'utf8');

test('r588 uses a five-column grid with PO chips in column 4 and the tick in column 5', () => {
  assert.equal(slideout.VERSION, '2026.10.28.r588');
  assert.match(CSS, /grid-template-columns:[^;]*minmax\(7rem, auto\)/);
  assert.match(CSS, /li > \.pdc-sublet-po-ref[\s\S]*grid-column: 4 !important/);
  assert.match(CSS, /li > \.vso-tick \{ grid-column: 5/);
  assert.doesNotMatch(CSS, /li > \.vso-tick \{ grid-column: 4/);
});

test('sublet rows keep PO chips and the panel tick on separate grid tracks', () => {
  const html = subletPo.decorateOperations(
    `<section class="authenticated-operation-station" data-operation-station="SUBLET" data-operation-category="sublet">`
    + `<header><strong>Sublet</strong></header><ol>`
    + `<li data-operation-source-id="a1b2c3d4-e5f6-7890-abcd-ef1234567890">`
    + `<strong>PD line 15</strong><span>SUB - MMT 2 ROW CANVAS SEAT COVERS</span><em>0.00 h</em></li>`
    + `</ol></section>`,
    {
      vehicleId: '00000000-0000-4000-8000-000000000001',
      known: true,
      payload: {
        ok: true,
        can_tick: true,
        vehicle_id: '00000000-0000-4000-8000-000000000001',
        lines: [{
          line_identity: 'source:a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          line_key: 'source:a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          operation_no: 'PD015-1',
          po_numbers: ['GP1 63458'],
          po_details: [{ po_number: 'GP1 63458', description: 'Seat covers' }],
          ticked: false,
          version: 1,
        }],
      },
    },
  );
  assert.match(html, /pdc-sublet-po-inline/);
  assert.match(html, /pdc-sublet-po-chip/);
  const injected = /\.authenticated-email-operations li>\.pdc-sublet-po-inline[\s\S]*?grid-column:2\/-1/.test(
    fs.readFileSync('pdc-sublet-po.js', 'utf8'),
  );
  assert.equal(injected, true, 'board CSS still spans 2/-1; the panel must override it');
  assert.match(CSS, /li > \.pdc-sublet-po-inline \{ grid-column: 4 !important/);
});

test('REPORTED_FAULTS documents stock 13092999 and the layout fix', () => {
  assert.match(faults, /13092999/);
  assert.match(faults, /r588 \(F202\)/);
  assert.match(faults, /PO chip/);
  assert.match(faults, /cdsmnqxtyyoeoznmbidd/);
  assert.match(faults, /9be0883b1a555f48f3c1ba9fa111c891/);
});
