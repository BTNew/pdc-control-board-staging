/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r686 (F296, Craig 29 Oct 2026): a done job on the Workshop TV ends at its completion time.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const tv = require('./workshop-tv.js');

const from = Date.parse('2026-10-28T23:00:00Z'); // 07:00 Perth
const to = Date.parse('2026-10-29T09:00:00Z');   // 17:00 Perth
const tomorrow = { from: Date.parse('2026-10-29T23:00:00Z'), to: Date.parse('2026-10-30T09:00:00Z') };
const now = Date.parse('2026-10-28T22:44:00Z');
const job = { status: 'completed', start: '2026-10-28T22:25:00Z', end: '2026-10-30T05:43:00Z', actual_start: '2026-10-28T22:25:00Z', actual_end: '2026-10-28T23:31:00Z', key: '456', stock: '13017852' };

test('r686: done bar stops at actual_end, not the planned end', () => {
  const html = tv.barHtml(job, { from, to, now });
  const width = Number(/width:([\d.]+)%/.exec(html)[1]);
  assert.ok(width < 6, `width ${width}`); // 07:00-07:31 of a 10 h day = 5.17 %
  assert.match(html, /07:31/);
  assert.equal(tv.barHtml(job, { ...tomorrow, now }), ''); // gone from tomorrow
});

test('r686: done without actual_end keeps the planned bar; other states unchanged', () => {
  const html = tv.barHtml({ ...job, actual_end: null }, { from, to, now });
  assert.match(html, /width:100\.00%/);
  assert.match(tv.barHtml({ ...job, status: 'planned' }, { from, to, now }), /width:100\.00%/);
});

test('r686: SQL returns actual_end, html cache-busts', () => {
  const sql = fs.readFileSync('supabase/migrations/20261029010000_r686_tv_done_ends.sql', 'utf8');
  assert.match(sql, /'actual_end', j\.actual_end_at/);
  assert.match(fs.readFileSync('supabase/rollbacks/20261029010000_r686_tv_done_ends.down.sql', 'utf8'), /845f391f2915c53dfceb68fc8e7f992b/);
  assert.match(fs.readFileSync('workshop-tv.html', 'utf8'), /r686=2026\.10\.29\.r686/);
});
