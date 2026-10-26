/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { summaryHtml } = require('./pdc-planner-capacity.js');

const reason = 'Waiting for Chelsea Rees # 2 on Key 411 (Fitting - PMB Bay 10) until Wed 07:01';
const held = {
  key_number: '248', stock_number: '13047270', stage_code: 'FITTING', bay_number: 1,
  bay_display_name: 'Fitting - PMB Bay 06',
  start_at: '2026-10-27T23:01:00Z', end_at: '2026-10-28T22:47:00Z',
  hold_reason: reason,
};

test('a close-gaps row uses the workshop bay name and the hold reason', () => {
  const html = summaryHtml({
    can_apply: true,
    changes: [{
      key_number: '411', stock_number: '12710966', stage_code: 'FITTING', bay_number: 5,
      bay_display_name: 'Fitting - PMB Bay 10',
      old_start_at: '2026-10-26T23:40:00Z', old_end_at: '2026-10-27T23:01:00Z',
      new_start_at: '2026-10-26T23:40:00Z', new_end_at: '2026-10-27T23:01:00Z',
      hold_reason: 'Waiting for the workshop to open at Tue 07:00',
    }],
    holds: [held],
    unchanged_count: 1,
  });
  assert.match(html, /Fitting - PMB Bay 10/);
  assert.match(html, /Fitting - PMB Bay 06/);
  assert.match(html, /Key 248 · Stock 13047270/);
  assert.match(html, /Waiting for Chelsea Rees # 2 on Key 411 \(Fitting - PMB Bay 10\) until Wed 07:01/);
  assert.match(html, /Waiting for the workshop to open at Tue 07:00/);
  assert.match(html, /Staying in place/);
  assert.doesNotMatch(html, /· Bay \d/);
});

test('a row without a display name still says Bay N, and reasons are escaped', () => {
  const html = summaryHtml({
    can_apply: true,
    changes: [{ stock_number: 'S&1', stage_code: 'HOIST', bay_number: 2, bay_display_name: '',
      old_start_at: '2026-10-26T00:00:00Z', old_end_at: '2026-10-26T02:00:00Z',
      new_start_at: '2026-10-26T01:00:00Z', new_end_at: '2026-10-26T03:00:00Z',
      hold_reason: 'Waiting for <script> until Tue 11:21' }],
    unchanged_count: 0,
  });
  assert.match(html, /Hoist · Bay 2|HOIST · Bay 2/);
  assert.match(html, /S&amp;1/);
  assert.match(html, /Waiting for &lt;script&gt; until Tue 11:21/);
  assert.doesNotMatch(html, /<script>/);
});

test('the plan migration keeps the times and adds the regression check', () => {
  const up = fs.readFileSync(path.join(__dirname, 'supabase/migrations/20261026133000_r538_close_gaps_bay_reason.sql'), 'utf8');
  const down = fs.readFileSync(path.join(__dirname, 'supabase/rollbacks/20261026133000_r538_close_gaps_bay_reason.down.sql'), 'utf8');
  assert.match(up, /close_gaps_preview_bay_label_and_tech_reason/);
  assert.match(up, /sort_order, added_in\) VALUES/);
  assert.match(up, /true, 317, 'r538'/);
  assert.match(up, /pin count is not 241/);
  assert.match(up, /pin count changed/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(up, /final_start=proposed_start,final_end=proposed_end/);
  assert.match(up, /proposed_start IS DISTINCT FROM item\.original_start/);
  assert.match(up, /search_path','pg_catalog'/);
  assert.match(up, /::pg_catalog\.regprocedure/);
  assert.match(down, /f76a8333a700a66158bf60ab7ca536d8/);
  assert.match(down, /note='Close gaps'/);
  const karratha = fs.readFileSync(path.join(__dirname, 'karratha/pdc-planner-capacity.js'), 'utf8');
  assert.doesNotMatch(karratha, /hold_reason|bay_display_name|r538/);
  const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
  assert.match(html, /pdc-planner-capacity\.js\?[^"]*&amp;r538=2026\.10\.26\.r538/);
  assert.doesNotMatch(fs.readFileSync(path.join(__dirname, 'karratha/index.html'), 'utf8'), /r538=/);
});
