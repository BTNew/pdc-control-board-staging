/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r504 (F117): Status 80 ticks parts+sublet and clears all planner bays; Pit phrases are ALWAYS Sublet.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');

const ID = '20261023080000_r504_status80_qc_stations_and_pit_sublet';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');

const OLD = {
  apply: 'eea5bb523c2538742db52508665191d3',
  life: '94230674500701543bcaf93e58158a54',
  req: '3a860c8866b61a5f848418bd2c6ac14a',
  pit: '2379b7ad49c2c472e09118cedc1bd8ce',
  ensure: 'd164e32cdde78185f2dbdf2612459d9e',
  suggest: 'f751daa751d482d53339ea470c6dcb6c',
};
const NEW = {
  apply: '5162460f98589c34aa976b5ed36fdbd2',
  life: '26cc76fc310dd1cfa65b6a5fca2b0efb',
  req: 'f8e14899a5a9017c466bb5cde92f07c6',
  pit: '7e10e4f66633cf5129c5b2c21aa905e0',
  ensure: '794492676469d3f4404fbc4e1bb2e08c',
  suggest: 'ee799302c1bdd37bcfba15837859e200',
};

test('migration: staging only, exact base md5s, never names production', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  for (const md5 of Object.values(OLD)) assert.ok(up.includes(`'${md5}'`), `base md5 ${md5}`);
  for (const md5 of Object.values(NEW)) {
    assert.ok(up.includes(md5), `new md5 ${md5} in up`);
    assert.ok(down.includes(md5), `new md5 ${md5} in down`);
  }
});

test('migration: Status 80 completes parts+sublet and all active bookings', () => {
  const apply = up.match(/CREATE OR REPLACE FUNCTION pdc_codex_intake_private\.apply_service_pmb_complete[\s\S]*?END \$fn\$;/);
  assert.ok(apply, 'apply function present');
  assert.match(apply[0], /lower\(work_key\) IN\('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet'\)/);
  assert.match(apply[0], /UPDATE public\.workshop_bookings wb SET status='completed'/);
  assert.ok(!apply[0].includes('workshop_stages'), 'no stage filter on Status 80 booking complete');
  assert.match(apply[0], /'started','stoppage'/);
  assert.match(up, /'status80_completes_parts_sublet_and_all_bays'/);
  assert.match(up, /'F117'/);
});

test('migration: lifecycle and require_planner allow any stage for tune_pmb receipts', () => {
  const life = up.match(/CREATE OR REPLACE FUNCTION public\.workshop_enforce_booking_lifecycle\(\)[\s\S]*?\$function\$;/);
  const req = up.match(/CREATE OR REPLACE FUNCTION public\.workshop_require_planner_booking_mutation\(\)[\s\S]*?\$function\$;/);
  assert.ok(life && req);
  assert.ok(!/s\.code\s+in\s*\(/i.test(life[0].split('r504')[1] || life[0]), 'lifecycle Status-80 path has no stage allowlist');
  assert.match(life[0], /tune_pmb_complete_receipts/);
  assert.match(req[0], /tune_pmb_complete_receipts/);
});

test('migration: Pit wording expanded; suggest ALWAYS Sublet before department gate; ensure remaps to SUBLET', () => {
  assert.match(up, /\(WEIGH\|WAY\)BRIDGE/);
  assert.match(up, /pit and way/i);
  const sug = up.match(/CREATE OR REPLACE FUNCTION pdc_work_categories_private\.suggest\(line jsonb\)[\s\S]*?END \$fn\$;/);
  assert.ok(sug);
  const pitIdx = sug[0].indexOf('ALWAYS Sublet');
  const deptIdx = sug[0].indexOf("department' IS DISTINCT FROM '138'");
  assert.ok(pitIdx > 0 && deptIdx > pitIdx, 'pit SUBLET check precedes department gate');
  assert.match(sug[0], /RETURN 'SUBLET'/);
  assert.match(up, /WHEN public\.pdc_line_is_pit_401\(p_vehicle_id,l\) THEN 'SUBLET'/);
});

test('undo restores tip md5s and removes r504 pins/check', () => {
  for (const md5 of Object.values(OLD)) assert.ok(down.includes(md5), `old md5 ${md5}`);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='status80_completes_parts_sublet_and_all_bays'/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r504'/);
  assert.match(down, /added_in='r405'/);
});

test('FAULT_LOG has F117', () => {
  assert.match(log, /\| F117 \|/);
  assert.match(log, /r504/);
  assert.match(log, /status80_completes_parts_sublet_and_all_bays/);
  assert.match(log, /PO TO RAISE|backfill|SQL only/i);
});

test('require_planner rebuilt from live tip (allowed_schedule kept; no stage allowlist on Status 80)', () => {
  const req = up.match(/CREATE OR REPLACE FUNCTION public\.workshop_require_planner_booking_mutation\(\)[\s\S]*?\$function\$;/);
  assert.ok(req);
  assert.match(req[0], /allowed_schedule/);
  assert.match(req[0], /allowed_booking_cancel/);
  assert.match(req[0], /tune_pmb_complete_receipts/);
  // Status-80 path must not join workshop_stages / stage allowlist
  const afterComment = req[0].split('r504')[1] || '';
  assert.ok(!/s\.code\s+in\s*\(/i.test(afterComment), 'Status-80 path has no stage allowlist');
  assert.match(down, /3a860c8866b61a5f848418bd2c6ac14a/);
});

test('backfill: restamp receipt txid; UNIQUE-safe; complete stations (+ bookings when receipt)', () => {
  assert.match(up, /DO \$bf\$/);
  assert.match(up, /transaction_id\s*=\s*txid_current\(\)/);
  assert.match(up, /r504 backfill/);
  assert.match(up, /tune_pmb_complete_receipts/);
  assert.match(up, /current_location[^\n]*QC|upper\([^)]*current_location[^)]*\)='QC'/);
  assert.ok(up.includes("'parts','sublet'") || up.includes("'parts'"));
  assert.match(down, /Does NOT reverse the one-shot QC backfill/i);
});

test('Craig answers encoded: Sublet even with PO; force mid-job; backfill; SQL only', () => {
  assert.match(up, /PO TO RAISE/);
  assert.match(up, /started','stoppage'/);
  assert.match(up, /backfill/i);
  assert.match(up, /Does not change app\.js or pdc-qc-rework\.js/);
});

test('no locked frontend files touched', () => {
  assert.match(up, /Does not change app\.js or pdc-qc-rework\.js/);
  // Backfill DO may UPDATE work_items/bookings; apply/lifecycle bodies may too — strip function + $bf$ bodies.
  let top = up.replace(/\$function\$[\s\S]*?\$function\$/g, '')
    .replace(/\$fn\$[\s\S]*?\$fn\$/g, '')
    .replace(/\$bf\$[\s\S]*?\$bf\$/g, '')
    .replace(/\$c\w+\$[\s\S]*?\$c\w+\$/g, '')
    .replace(/\$g\$[\s\S]*?\$g\$/g, '')
    .replace(/\$p\$[\s\S]*?\$p\$/g, '');
  assert.doesNotMatch(top, /^\s*(UPDATE|DELETE FROM|INSERT INTO)\s+public\.(vehicles|vehicle_work_items|workshop_bookings)\b/im, 'no unexpected data DML outside function/backfill bodies');
});
