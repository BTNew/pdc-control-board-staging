/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r575 (F189) preview: one key per active PMB board vehicle. No staging write.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');

const key = require('./pdc-key-number.js');
const up = fs.readFileSync('supabase/migrations/20261028010000_r575_active_key_unique.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261028010000_r575_active_key_unique.down.sql', 'utf8');
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const entry = fs.readFileSync('canonical-entry.js', 'utf8');
const karratha = fs.readFileSync('karratha/app.js', 'utf8');
const SENTENCE = 'Key 214 is already on stock 13047384';

test('the key cell renders the server sentence in blue, not as a red error', () => {
  assert.equal(key.clashMessage(SENTENCE), SENTENCE);
  assert.equal(key.clashMessage('23505'), '');
  assert.equal(key.clashMessage('Another active PMB vehicle already has this key tag.'), '');
  const html = key.keyCellHtml({ vehicleId: '11111111-2222-4333-8444-555555555555', key: '214', canEdit: true, editing: true, message: SENTENCE });
  assert.match(html, /class="pdc-keyno-msg is-clash"/);
  assert.match(html, new RegExp(SENTENCE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  assert.doesNotMatch(html, /is-error/);
  assert.match(key.CSS, /\.pdc-keyno-msg\.is-clash\{color:#1d4ed8\}/);
  assert.doesNotMatch(key.CSS, /#f97316|#ea580c|#c2410c/);
  assert.equal(key.R575, '2026.10.27.r575');
});

test('the card save shows the same blue sentence and passes the server message through', () => {
  assert.match(app, /function boardVehicleWithSameKey\(/);
  assert.match(app, /function keyAlreadyOnStockSentence\(/);
  assert.match(app, /pdcNotify\(sentence, 'info'\)/);
  assert.match(app, /pdcNotify\(clash, 'info'\)/);
  assert.match(app, /saveMessage\.classList\.add\('is-key-clash'\)/);
  assert.match(app, /detailChanges\.key_number !== undefined \? boardVehicleWithSameKey/);
  assert.match(css, /\.save-message\.is-key-clash \{\s*color: #1d4ed8;/);
  assert.match(service, /message: typeof body\?\.message === 'string' \? body\.message : ''/);
  assert.equal(service.match(/message: typeof body\?\.message === 'string' \? body\.message : ''/g).length, 1);
  assert.match(entry, /r575=2026\.10\.27\.r575/);
  assert.doesNotMatch(karratha, /boardVehicleWithSameKey|is-key-clash/);
});

test('the migration refuses active duplicates, names the other stock, and leaves department 135 and sales alone', () => {
  assert.match(up, /r575 \(F189\) \/ sort 346/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.match(up, /vjdtsswhroyguxyfjdkt/);
  assert.match(up, /active board vehicles still share a key\. Fix the data first\./);
  assert.match(up, /Key % is already on stock %/);
  assert.match(up, /USING ERRCODE = 'P0001'/);
  assert.match(up, /WHEN unique_violation THEN/);
  assert.doesNotMatch(up, /RAISE EXCEPTION '23505'|ERRCODE = '23505'/);
  assert.match(up, /59b676f8a7efac59876e0d36a61730a0/);
  assert.match(up, /747aedfaa0ea8f109f7a7d9c6d625327/);
  assert.match(up, /69decdbde44cf15f481ff7ba6e1bcfbd/);
  assert.match(up, /prosrc_md5 = '8e46bf785c2118d58a8cebf2bd1888d1'/);
  assert.match(up, /sort_order = 346/);
  assert.match(up, /pmb_dept_ack_book_574/);
  assert.match(up, /hours_description_fits_573/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION karratha135_pdc/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION public\.pdc_apply_tune_key_number_v1/);
  assert.doesNotMatch(up, /CREATE OR REPLACE FUNCTION pdc_codex_intake_private\.service_whole_archive_569/);
  assert.match(up, /reason IN \('archive', 'leave', 'not_restored'\)/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.equal((up.match(/UPDATE pdc_ops\.expected_function_md5/g) || []).length, 1);
  assert.match(down, /8e46bf785c2118d58a8cebf2bd1888d1/);
  assert.match(down, /eabd64cea227ce91a1f3005569c16439/);
  assert.match(down, /DROP TRIGGER IF EXISTS zzz_pdc_active_key_575/);
  assert.match(down, /A key this release already cleared stays/);
  const fault = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  assert.match(fault, /\| F189 \|/);
  assert.match(fault, /active_key_unique_575/);
  assert.match(fault, /13008249 is key 238/);
  assert.match(fault, /13070395 is key 415/);
});

test('preview files are stable bytes for the report', () => {
  for (const file of [
    'supabase/migrations/20261028010000_r575_active_key_unique.sql',
    'supabase/rollbacks/20261028010000_r575_active_key_unique.down.sql',
    'pdc-key-number.js',
  ]) {
    const digest = crypto.createHash('md5').update(fs.readFileSync(file)).digest('hex');
    assert.equal(digest.length, 32, file);
  }
});
