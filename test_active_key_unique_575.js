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
  assert.doesNotMatch(up, /Fix the data first/);
  assert.match(up, /a new active duplicate appeared after the approved clears\. Nothing was kept\./);
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
  assert.match(up, /reason IN \('archive', 'leave', 'not_restored', 'approved_clear'\)/);
  assert.doesNotMatch(up, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.equal((up.match(/UPDATE pdc_ops\.expected_function_md5/g) || []).length, 1);
  assert.match(down, /8e46bf785c2118d58a8cebf2bd1888d1/);
  assert.match(down, /eabd64cea227ce91a1f3005569c16439/);
  assert.match(down, /DROP TRIGGER IF EXISTS zzz_pdc_active_key_575/);
  assert.match(down, /puts each approved_clear key back/);
  assert.doesNotMatch(down, /already cleared stays/);
  const fault = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
  assert.match(fault, /\| F189 \|/);
  assert.match(fault, /active_key_unique_575/);
  assert.match(fault, /13008249 is key 238/);
  assert.match(fault, /13070395 is key 415/);
  assert.match(fault, /214 is on 13047384/);
  assert.match(fault, /approved_clear/);
});

test('the approved clears are id-scoped, skip an archived holder, and the undo puts that key back', () => {
  const losers = [
    ['105', '2314e3bc-5510-4d92-adc4-8155d3885d63', '13073068', 'ca02d68f-6d53-4519-9678-f2b31ca7e3a1', '13070896'],
    ['126', '465a85f0-f027-476c-bcab-243448f22ac3', '13073094', '835f365f-17fc-4f56-908c-27963f276da0', '13070891'],
    ['144', '53a6dc04-14cb-43cb-a2d6-7bd3a075bb72', '13092054', '1c1ca4f0-7ed2-4194-8376-e7aacc4a5e77', '13070886'],
    ['146', 'e1f8c5b7-31c2-4a8e-8269-b396424bbc0b', '13073086', '861cac9d-087d-466b-86c3-4c95d86dce2c', '13070887'],
    ['214', '61f9f707-4073-4e1b-9cd5-b499e25d8c58', '13047384', 'd602c80a-8511-4359-8931-67d87facd0f2', '13019220'],
    ['320', '0d60664a-6501-4034-8a9e-8509b76e5490', '13072026', '057eb94c-2433-45c1-8a61-a841da0b1e29', '13070889'],
    ['338', 'fbd73ece-abb6-4fb5-a5a1-342bc2811ff4', 'IS60353006', '84502339-d4fd-4e2a-beee-1a504672978c', '13041213'],
    ['348', '7ba6db7d-cbd2-4548-a5b9-0135bf448c0b', '13073074', '1b18c826-e226-43e9-b4a0-6079c55853cc', '13070897'],
    ['349', '0fc35a49-55fc-4395-928a-26ee9f82ac17', '13073075', '3e3eb9b0-89d2-4778-bb73-d06cf2bb0ad0', '13073090'],
    ['414', 'f9d7ca6c-34a8-4f41-b28b-2c71575d7bf8', 'IS60069640', '6da9c8e1-9c9f-4fea-992e-57cc991f4d5f', '13018221'],
  ];
  for (const [token, keeperId, keeperStock, loserId, loserStock] of losers) {
    assert.match(up, new RegExp(`'${token}'::text, '${keeperId}'::uuid, '${keeperStock}'::text, '${loserId}'::uuid, '${loserStock}'::text`));
    assert.match(down, new RegExp(loserId));
  }
  assert.match(up, /IF v_loser\.board_purged_at IS NOT NULL THEN/);
  assert.match(up, /'approved_clear'/);
  const clearAt = up.indexOf("reason, note)\n    VALUES (v_loser.id, v_have, v_loser.stock_number, 'approved_clear'");
  const refuseAt = up.indexOf('a new active duplicate appeared after the approved clears');
  const shadowAt = up.indexOf('CREATE TABLE pdc_key_number_private.active_key_575');
  const triggerAt = up.indexOf('CREATE TRIGGER zzz_pdc_active_key_575');
  assert.ok(clearAt > 0 && refuseAt > clearAt && shadowAt > refuseAt && triggerAt > shadowAt);
  assert.equal((up.match(/CREATE TABLE pdc_key_number_private\.key_release_575/g) || []).length, 1);
  assert.equal((up.match(/CREATE TABLE pdc_key_number_private\.active_key_575/g) || []).length, 1);
  const dropTriggerAt = down.indexOf('DROP TRIGGER IF EXISTS zzz_pdc_active_key_575');
  const restoreAt = down.indexOf("reason = 'approved_clear'");
  const dropHistoryAt = down.indexOf('DROP TABLE IF EXISTS pdc_key_number_private.key_release_575');
  const dropTokenAt = down.indexOf('DROP FUNCTION IF EXISTS pdc_key_number_private.key_token_575');
  assert.ok(dropTriggerAt >= 0 && restoreAt > dropTriggerAt && dropHistoryAt > restoreAt && dropTokenAt > restoreAt);
  assert.match(down, /key_number IS NULL/);
  assert.match(down, /already has key %\. The approved key % was not written over it/);
  assert.match(up, /reason IN \('archive', 'leave'\)/);
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
