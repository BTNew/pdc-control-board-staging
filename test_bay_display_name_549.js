/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r549 (F163): a bay's on-screen name is workshop_bays.display_name.
// The station name plus the padded bay number is only the fallback.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const layout = require('./pdc-workshop-departments.js');
const overview = require('./control-board-overview.js');
const fixture = require('./qa/control-board-fixtures.js');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261026240000_r549_bay_display_name.sql', 'utf8');

function slice(source, name) {
  const start = source.indexOf(`function ${name}`);
  const end = source.indexOf('\nfunction ', start + 1);
  return source.slice(start, end);
}

test('r549: planner and vehicle labels prefer display_name', () => {
  const ctx = {
    window: { PDC_WORKSHOP_DEPARTMENTS: layout },
    workshopDepartmentLayout: () => layout,
    workshopPad: value => String(value).padStart(2, '0'),
    normalizePmbStage: value => String(value || '').toUpperCase(),
    workshopSharedBayRef: (stage, bay) => (stage === 'HOIST' && Number(bay) === 3 ? { display_name: 'Bay 8', code: 'HOIST-BAY-03', bay_number: 3 } : null),
  };
  vm.runInNewContext(`${slice(planner, 'workshopBayChoiceLabel')}\n${slice(planner, 'workshopBayText')}\nthis.choice = workshopBayChoiceLabel; this.text = workshopBayText;`, ctx);
  assert.equal(ctx.choice('HOIST', 3), 'Bay 8');
  assert.equal(ctx.text('HOIST', 3), 'Bay 8');
  assert.equal(ctx.choice('HOIST', 1), 'Express / Pits Hoist · Bay 01');
  assert.equal(ctx.text('BUS_4X4', 4, true), 'Bay 04');
  const appCtx = {
    window: {
      PDC_WORKSHOP_DEPARTMENTS: layout,
      __workshopReferenceDataService: { getCachedWorkshopBays: () => ({ rows: [{ code: 'HOIST-BAY-03', display_name: 'Bay 8' }] }) },
    },
    normalizePmbStage: value => String(value || '').toUpperCase(),
  };
  vm.runInNewContext(`${slice(app, 'pdcBayText')}\nthis.fn = pdcBayText;`, appCtx);
  assert.equal(appCtx.fn('HOIST', 3, true), 'Bay 8');
  assert.equal(appCtx.fn('FITTING', 1), 'Fitting · Bay 06');
});

test('r549: control board header uses display_name and falls back when it is blank', () => {
  const named = fixture.emptySnapshot();
  const hoist = named.board.bays.find(bay => bay.stage_code === 'HOIST' && bay.bay_number === 2);
  hoist.display_name = 'Bay 8';
  assert.match(overview.render(overview.buildModel(named)), /<strong>Bay 8<\/strong>/);
  const blank = fixture.emptySnapshot();
  blank.board.bays.forEach(bay => { bay.display_name = ''; });
  assert.match(overview.render(overview.buildModel(blank)), /<strong>Express · Bay 02<\/strong>/);
});

test('r549: the rename control is on the bay header and the SQL only writes display_name', () => {
  assert.match(planner, /data-workshop-bay-rename-stage/);
  assert.match(planner, /setWorkshopBayDisplayName/);
  assert.match(sql, /set_workshop_bay_display_name\(p_bay_id pg_catalog\.uuid, p_expected_version pg_catalog\.int4, p_display_name pg_catalog\.text\)/);
  assert.match(sql, /require_pdc_role\('operator'::public\.pdc_role\)/);
  assert.match(sql, /SET search_path TO pg_catalog, public/);
  assert.match(sql, /bay_display_name_visual_only/);
  assert.doesNotMatch(sql, /::regprocedure/);
  assert.match(sql, /sort_order, added_in\) VALUES\n \('bay_display_name_visual_only', 'F163'/);
  assert.equal((sql.match(/sort_order=325/g) || []).length > 0, true);
});
