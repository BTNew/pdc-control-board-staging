/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { componentHtml } = require('./pdc-bus-component-split.js');
const { scanSql } = require('./scripts/lint_migration_safeupdate_dml.js');

const up = fs.readFileSync('supabase/migrations/20261027180000_r565_bus_component_split.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261027180000_r565_bus_component_split.down.sql', 'utf8');
const between = (src, tag) => {
  const start = src.indexOf(tag);
  const end = src.indexOf(tag, start + tag.length);
  return src.slice(start + tag.length, end);
};

const board = {
  ok: true,
  booking_id: 'elec-bay',
  items: [
    {
      kind: 'section', category: 'BUS_MECHANICAL', category_label: 'Mechanical', home_busy: false,
      line_identity: 'conv-1', section_id: '2', section_label: 'Section 2',
      section_description: 'Rear lift', status: 'in_progress', started_bay: 'Bay 01',
    },
    {
      kind: 'line', category: 'BUS_ACCESSORIES', category_label: 'Accessories', home_busy: false,
      line_identity: 'stripe-1', description: 'Reflective Stripes - Yellow', hours: 0.01,
      completed: false, item_status: 'idle',
    },
    {
      kind: 'line', category: 'BUS_ELECTRICAL', category_label: 'Electrical', home_busy: true,
      line_identity: 'mine-1', description: 'Mine bar', hours: 4, completed: false, item_status: 'running', started_bay: 'Bay 04',
    },
  ],
};

test('a section started in another bay can be finished here, and a busy component cannot', () => {
  const html = componentHtml(board, { editable: true, bookingId: 'elec-bay' });
  assert.match(html, /Other Bus 4x4 components/);
  assert.match(html, /This does not close the job card/);
  assert.match(html, /Mechanical/);
  assert.match(html, /Section 2 — Rear lift/);
  assert.match(html, /Started in Bay 01/);
  const section = html.split('<li').find(part => part.includes('Section 2'));
  assert.match(section, /data-bus-split-step="done"/);
  assert.doesNotMatch(section, /data-bus-split-step="done"[^>]*disabled/);
  const idle = html.split('<li').find(part => part.includes('Reflective Stripes'));
  assert.match(idle, /0\.01 h/);
  assert.match(idle, /data-bus-split-step="done"[^>]*disabled/);
  assert.doesNotMatch(idle, /data-bus-split-step="start"[^>]*disabled/);
  const busy = html.split('<li').find(part => part.includes('Mine bar'));
  assert.match(busy, /That bay still has this component/);
  assert.match(busy, /data-bus-split-step="start"[^>]*disabled/);
  assert.match(busy, /data-bus-split-step="done"[^>]*disabled/);
});

test('an empty board and a view-only card do not invite a tick', () => {
  assert.equal(componentHtml({ items: [] }), '');
  assert.equal(componentHtml(null), '');
  const html = componentHtml(board, { editable: false });
  assert.match(html, /data-bus-split-step="start"[^>]*disabled/);
  const done = componentHtml({ items: [{ kind: 'section', category: 'BUS_QA', category_label: 'QA', section_id: '12', section_label: 'Section 12', section_description: 'Sign-off', status: 'complete', finished_bay: 'Bay 02', line_identity: 'conv-1' }] }, { editable: true });
  assert.match(done, /Finished in Bay 02/);
  assert.match(done, /data-bus-split-step="done"[^>]*checked/);
  assert.match(done, /data-bus-split-step="start"[^>]*disabled/);
});

test('the migration keeps the old pins and does not close a vehicle or a booking', () => {
  assert.match(up, /Go-live/);
  assert.doesNotMatch(up, /SQL is not applied/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt/);
  assert.match(up, /NOT BETWEEN 2 AND 45/);
  assert.match(up, /set_config\('search_path','pg_catalog',true\)/);
  assert.match(up, /set_config\('request\.jwt\.claims','',true\)/);
  assert.match(up, /626ca8b23a2e5f02e2ca8f96a4533d6f/);
  assert.match(up, /39b8f50d21d7932e671c31a5d539001d/);
  assert.match(up, /b1b23383b96acd867c246cf6e57572dc/);
  assert.match(up, /7031ac921d64cf2db16d52f3e8e02140/);
  assert.match(up, /3ea8b27f10bfc908c410760ed22f4fed/);
  assert.match(up, /true, 339, 'r568'/);
  assert.match(up, /bus_component_split_568/);
  assert.match(up, /'F182'/);
  assert.match(up, /Pin count stays 241/);
  assert.doesNotMatch(up, /<>242/);
  const setBody = between(up, '$set565$');
  const boardBody = between(up, '$board565$');
  for (const body of [setBody, boardBody]) {
    assert.equal(body.includes('UPDATE public.vehicles'), false);
    assert.equal(body.includes('DELETE FROM'), false);
    assert.equal(body.includes('cancel_workshop_booking'), false);
    assert.equal(body.includes('complete_workshop_work'), false);
    assert.equal(body.includes('pg_catalog.coalesce'), false);
    assert.match(body, /coalesce/);
    assert.match(body, /deleted_at IS NULL/);
  }
  assert.match(setBody, /component_busy/);
  assert.match(setBody, /BUS_MECHANICAL/);
  assert.match(down, /7031ac921d64cf2db16d52f3e8e02140/);
  assert.match(down, /sort_order=339/);
  assert.doesNotMatch(down, /DELETE FROM public\.vehicles/);
  assert.equal(scanSql(up).length, 0);
  assert.equal(scanSql(down).length, 0);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F182 \|/);
});

test('the fitter page loads the split before the bay card, and Department 135 does not', () => {
  const index = fs.readFileSync('index.html', 'utf8');
  const splitAt = index.indexOf('pdc-bus-component-split.js?r568=2026.10.27.r568');
  const fittersAt = index.indexOf('pdc-fitters.js?');
  assert.ok(splitAt > 0 && splitAt < fittersAt);
  assert.match(index, /r564=2026\.10\.27\.r564&amp;r568=2026\.10\.27\.r568/);
  const runtime = fs.readFileSync('scripts/build_pages_runtime.js', 'utf8');
  assert.match(runtime, /'pdc-bus-component-split\.js', 'pdc-fitters\.css', 'pdc-fitters\.js'/);
  const fitters = fs.readFileSync('pdc-fitters.js', 'utf8');
  assert.match(fitters, /data-bus-booking/);
  assert.match(fitters, /detail\.stage_code==='BUS_4X4'/);
  assert.doesNotMatch(fs.readFileSync('karratha/pdc-fitters.js', 'utf8'), /data-bus-booking|pdc-bus-component-split/);
  assert.doesNotMatch(fs.readFileSync('karratha/index.html', 'utf8'), /pdc-bus-component-split/);
});
