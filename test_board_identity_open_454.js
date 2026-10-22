/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r454 (F67): staging-only database release. The behaviour is proven by the rolled-back tests in tests/
// (real accounts by role, rolled back) and checked daily by board_identity_open_454 (sort 253) in pdc_ops.fault_regression_check().
// This file keeps the shipped migration and its undo honest: guarded window, staging only, pins, check and undo.
// The 9 board vehicles whose identity was unavailable open (Craig decision 2, 22 Oct).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const mig=fs.readFileSync('supabase/migrations/20261021230343_r454_board_identity_open.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021230343_r454_board_identity_open.down.sql','utf8');
const pins=['pdc_codex_intake_private.board_identity_dealer_454(uuid)::a1c3a6a592ac1e7e7c20df3b498748c9', 'pdc_codex_intake_private.workshop_board_identity_read_allowed_454(jsonb,uuid,text)::88eb91cdfef653bad2013342c375af4b', 'pdc_codex_intake_private.workshop_read_vehicle_allowed_20261013(jsonb,uuid,text)::cba3a1268c1363043c4df2b9d65b69e7', 'public.get_vehicle_workshop_detail_scoped(uuid,text)::c0ba734f2f4945e902a6c474cb589089', 'public.get_workshop_booking_search_scoped(jsonb)::f348c91e50b70c2dd14d8651f97d52a2', 'public.get_pdc_email_vehicle_location_snapshot()::e7f77fad301b8a87ef548472a8f790a6'];

test('r454: guarded apply (window :02-:45, lock_timeout 2s, staging only, clock tick untouched)',()=>{
  assert.match(mig,/SET LOCAL lock_timeout = '2s'/);
  assert.match(mig,/NOT BETWEEN 2 AND 45/);
  assert.match(mig,/staging only/);
  assert.match(mig,/pdc\.r454_tick/);
  assert.doesNotMatch(mig,/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/i);
  assert.doesNotMatch(mig,/^\s*(DELETE FROM|TRUNCATE|DROP TABLE)\s+(public|karratha)/im);
});

test('r454: every changed function is pinned and the check is registered at sort 253',()=>{
  for(const p of pins){const [sig,md5]=p.split('::');assert.ok(mig.includes(md5),sig+' pin '+md5);assert.ok(mig.includes(sig),sig);}
  assert.match(mig,/INSERT INTO pdc_ops\.regression_checks/);
  assert.ok(mig.includes("'board_identity_open_454'")&&mig.includes(',253,'),'check row');
});

test('r454: the undo restores the previous definitions, removes the pins and the check',()=>{
  assert.match(down,/NOT BETWEEN 2 AND 45/);
  assert.ok(down.includes('board_identity_open_454'));
  assert.match(down,/DELETE FROM pdc_ops\.regression_checks/);
});

test('r454: no personal data in the release files',()=>{
  for(const s of [mig,down]){assert.doesNotMatch(s,/@(?!pdc\.invalid)[a-z0-9-]+\.[a-z]/i,'no email addresses');}
});

test('r454: the board row identity dealer fills a missing dealer only, and only for this board',()=>{
  const {mapServerVehicle}=require('./pdc-email-vehicle-location-service.js');
  const base={id:'00000000-0000-4000-8000-000000000001',permanent_vehicle_id:'00000000-0000-4000-8000-000000000001',stock_number:'TEST-1'};
  assert.equal(mapServerVehicle({...base,identity_dealer_code:'14450'}).dealerCode,'14450');
  assert.equal(mapServerVehicle({...base,identity_dealer_code:'37047'}).dealerCode,'37047');
  assert.equal(mapServerVehicle({...base,identity_dealer_code:'99999'}).dealerCode,undefined,'unknown dealers never fill');
  assert.equal(mapServerVehicle({...base,identity_dealer_code:' '}).dealerCode,undefined);
  assert.equal(mapServerVehicle(base).dealerCode,undefined,'rows without the field are unchanged');
});

test('r454: the undo restores the three CRLF definitions byte for byte (base64), and index.html cache-busts the service',()=>{
  assert.equal((down.match(/convert_from\(decode\('/g)||[]).length,3);
  assert.match(fs.readFileSync('index.html','utf8'),/pdc-email-vehicle-location-service\.js\?[^"]*identity-dealer=2026\.10\.22\.r454[^"]*" defer>/);
});
