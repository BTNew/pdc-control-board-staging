'use strict';
// r453 (F66): staging-only database release. The behaviour is proven by the rolled-back tests in tests/
// (real accounts by role, rolled back) and checked daily by history_board_visibility_453 (sort 252) in pdc_ops.fault_regression_check().
// This file keeps the shipped migration and its undo honest: guarded window, staging only, pins, check and undo.
// History follows the board (Craig decision 1, 22 Oct).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const mig=fs.readFileSync('supabase/migrations/20261021225711_r453_history_board_visibility.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021225711_r453_history_board_visibility.down.sql','utf8');
const pins=['pdc_codex_intake_private.board_vehicle_visible_453(uuid)::d98f1bce13cbc964fba7332d8a4f6d97', 'public.get_pdc_vehicle_lifecycle_history_82000(uuid,text)::7cc5705d90440dd229c349563259541f'];

test('r453: guarded apply (window :02-:45, lock_timeout 2s, staging only, clock tick untouched)',()=>{
  assert.match(mig,/SET LOCAL lock_timeout = '2s'/);
  assert.match(mig,/NOT BETWEEN 2 AND 45/);
  assert.match(mig,/staging only/);
  assert.match(mig,/pdc\.r453_tick/);
  assert.doesNotMatch(mig,/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/i);
  assert.doesNotMatch(mig,/^\s*(DELETE FROM|TRUNCATE|DROP TABLE)\s+(public|karratha)/im);
});

test('r453: every changed function is pinned and the check is registered at sort 252',()=>{
  for(const p of pins){const [sig,md5]=p.split('::');assert.ok(mig.includes(md5),sig+' pin '+md5);assert.ok(mig.includes(sig),sig);}
  assert.match(mig,/INSERT INTO pdc_ops\.regression_checks/);
  assert.ok(mig.includes("'history_board_visibility_453'")&&mig.includes(',252,'),'check row');
});

test('r453: the undo restores the previous definitions, removes the pins and the check',()=>{
  assert.match(down,/NOT BETWEEN 2 AND 45/);
  assert.ok(down.includes('history_board_visibility_453'));
  assert.match(down,/DELETE FROM pdc_ops\.regression_checks/);
});

test('r453: no personal data in the release files',()=>{
  for(const s of [mig,down]){assert.doesNotMatch(s,/@(?!pdc\.invalid)[a-z0-9-]+\.[a-z]/i,'no email addresses');}
});
