/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const fitters = require('./pdc-fitters.js');

const POLY = 'source:354acf7c-04bc-4c0d-8a6c-e825af5fde4e';
const targets = [
  { stage_code: 'FITTING', label: 'Fitting', bays: [{ id: 'bay-fit', number: 6, label: 'Bay 06' }] },
  { stage_code: 'ELECTRICAL', label: 'Electrical', bays: [{ id: 'bay-elec', number: 3, label: 'Bay 03' }] },
];
const state = { editable: true, disabled: false, note: '', open: false, handoffTargets: targets, stageCode: 'FITTING' };
function line(extra = {}) {
  return { line_identity: POLY, description: 'POLY WATER TANK WITH 12V PUMP - SIZE TBC', stage_code: 'FITTING', hours: null, completed: false, ...extra };
}

test('a fitting line can be sent to Electrical or one of its bays', () => {
  const before = fitters.fitterLineCardHtml(line(), 0, { editable: true, disabled: false, note: '', open: false });
  assert.doesNotMatch(before, /data-fitter-handoff|Send this line|is-sent/);
  const html = fitters.fitterLineCardHtml(line(), 0, state);
  assert.match(html, /data-fitter-handoff="source:354acf7c-04bc-4c0d-8a6c-e825af5fde4e"/);
  assert.match(html, /Send to Electrical/);
  assert.match(html, /value="ELECTRICAL\|bay-elec"/);
  assert.match(html, /Electrical · Bay 03/);
  assert.match(html, /Keep in this bay/);
  assert.doesNotMatch(html, /#[fF][fF][aA]|orange|#f97316|#ea580c/);
});

test('a sent line stays blue and outstanding and does not block the bay', () => {
  const html = fitters.fitterLineCardHtml(line({
    handoff: { sent_away: true, to_stage_code: 'ELECTRICAL', to_bay_name: 'Bay 03', from_stage_code: 'FITTING' },
  }), 1, state);
  assert.match(html, /class="fitter-line is-sent/);
  assert.match(html, /Sent to Electrical · Bay 03/);
  assert.match(html, /Still outstanding there/);
  assert.match(html, /data-fitter-handoff-undo="source:354acf7c-04bc-4c0d-8a6c-e825af5fde4e"/);
  assert.match(html, /data-fitter-line="[^"]+"[^>]*disabled/);
  assert.doesNotMatch(html, /data-fitter-handoff="/);
  assert.doesNotMatch(html, /data-fitter-item-start/);
});

test('a line sent here from Fitting can still be ticked Done', () => {
  const html = fitters.fitterLineCardHtml(line({
    handoff: { received_here: true, from_stage_code: 'FITTING', to_stage_code: 'ELECTRICAL' },
  }), 2, { ...state, stageCode: 'ELECTRICAL' });
  assert.match(html, /is-received/);
  assert.match(html, /Sent here from Fitting/);
  assert.match(html, /Still outstanding until this line is Done/);
  assert.match(html, /data-fitter-item-start=/);
  assert.doesNotMatch(html, /Sent to Electrical/);
});

test('the controller sees an unbooked handed-off line and can book or undo it', () => {
  const html = fitters.controllerHandoffListHtml([{
    vehicle_id: 'f5622c52-212b-4330-9398-3a86c99ad38d',
    stock_number: '13073300',
    key_number: '307',
    line_identity: POLY,
    description: 'POLY WATER TANK WITH 12V PUMP - SIZE TBC',
    from_stage_code: 'FITTING',
    to_stage_code: 'ELECTRICAL',
    actor_email: 'fitter@example.com',
    actor_role: 'fitter',
    handed_at: '2026-10-27T02:15:00.000Z',
    booked: false,
  }]);
  assert.match(html, /Unbooked · Electrical/);
  assert.match(html, /POLY WATER TANK WITH 12V PUMP - SIZE TBC/);
  assert.match(html, /Sent from Fitting to Electrical/);
  assert.match(html, /Still outstanding/);
  assert.match(html, /Stock 13073300/);
  assert.match(html, /Key 307/);
  assert.match(html, /data-line-handoff-book="ELECTRICAL"/);
  assert.match(html, /Book into a Electrical bay/);
  assert.match(html, /data-line-handoff-undo="source:354acf7c-04bc-4c0d-8a6c-e825af5fde4e"/);
  assert.match(html, /Vehicle Locations/);
  assert.match(html, /New to PMB/);
  assert.doesNotMatch(html, /orange|#f97316|#ea580c/);
});

test('the release files claim r583 / F197 / sort 355 and leave department 135 frozen', () => {
  const up = fs.readFileSync('supabase/migrations/20261028033000_r583_line_handoff.sql', 'utf8');
  const down = fs.readFileSync('supabase/rollbacks/20261028033000_r583_line_handoff.down.sql', 'utf8');
  assert.match(up, /line_handoff_583/);
  assert.match(up, /'F197'/);
  assert.match(up, /355, 'r583'/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(up, /pdc_line_handoff_583/);
  assert.match(up, /line_handoff_work_key_583/);
  assert.doesNotMatch(up, /UPDATE public\.vehicles SET/);
  assert.match(down, /DROP TABLE IF EXISTS public\.pdc_line_handoff_583/);
  assert.match(down, /74d1a88dc9b440782904c02682c25ebc/);
  assert.match(down, /88d2eed58518a9eb98ef4210610a4dd1/);
  assert.doesNotMatch(fs.readFileSync('karratha/pdc-fitters.js', 'utf8'), /data-fitter-handoff|PdcLineHandoff/);
  assert.doesNotMatch(fs.readFileSync('karratha/pdc-fitters.css', 'utf8'), /line-handoff-controller/);
  const css = fs.readFileSync('pdc-fitters.css', 'utf8');
  assert.match(css, /\.fitter-line\.is-sent[\s\S]*#eff6ff/);
  assert.match(css, /#1d4ed8/);
  assert.match(css, /#2563eb/);
  assert.match(fs.readFileSync('pdc-vehicle-slideout.js', 'utf8'), /PdcLineHandoff\?\.mount/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /r583=2026\.10\.27\.r583/);
});
