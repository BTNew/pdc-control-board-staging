/* © 2026 Specialise Pty Ltd. r564 (F178): Fitters bay key badge beside stock. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { fitterJobKeyNumber, fitterKeyBadgeHtml } = require('./pdc-fitters.js');

test('fitterJobKeyNumber reads key_number and trims', () => {
  assert.equal(fitterJobKeyNumber({ key_number: ' 364 ' }), '364');
  assert.equal(fitterJobKeyNumber({ keyNumber: '420' }), '420');
  assert.equal(fitterJobKeyNumber({ stock: '13042994' }), '');
});

test('fitterKeyBadgeHtml uses blue styling class and escapes values', () => {
  assert.match(fitterKeyBadgeHtml({ key_number: '364' }), /class="fitter-key-badge"[^>]*>Key 364</);
  assert.doesNotMatch(fitterKeyBadgeHtml({ key_number: '364' }), /is-missing/);
  assert.match(fitterKeyBadgeHtml({}), /class="fitter-key-badge is-missing"[^>]*>No key</);
  assert.match(fitterKeyBadgeHtml({ key_number: '<script>' }), /Key &lt;script&gt;/);
  assert.doesNotMatch(fitterKeyBadgeHtml({ key_number: '364' }), /orange|#92400e|#fef3c7/i);
});

test('r564: index.html cache-busts pdc-fitters.js with r564', () => {
  const index = fs.readFileSync('index.html', 'utf8');
  assert.match(index, /pdc-fitters\.js\?[^"]*r564=2026\.10\.27\.r564/);
});

test('r564: migration adds key_number to get_fitter_jobs', () => {
  const sql = fs.readFileSync('supabase/migrations/20261027121500_r564_fitter_job_key_number.sql', 'utf8');
  assert.match(sql, /'key_number',v\.key_number/);
  assert.match(sql, /r564 \(F178\)/);
});
