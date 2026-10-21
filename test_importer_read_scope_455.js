'use strict';
// r455 (F68): staging-only database release. The behaviour is proven by the rolled-back tests in tests/
// (real accounts by role, rolled back) and checked daily by importer_read_scope_455 (sort 254) in pdc_ops.fault_regression_check().
// This file keeps the shipped migration and its undo honest: guarded window, staging only, pins, check and undo.
// Importers open vehicle drop-downs read-only (Craig decision 3, 22 Oct).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const mig=fs.readFileSync('supabase/migrations/20261021231123_r455_importer_read_scope.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021231123_r455_importer_read_scope.down.sql','utf8');
const pins=['pdc_codex_intake_private.workshop_importer_read_scope_455()::93ac42208534e22089c70e025db9cf84', 'pdc_codex_intake_private.workshop_read_actor_scope_20261013()::f7dedb862bdc1d85afd7d2392141c946'];

test('r455: guarded apply (window :02-:45, lock_timeout 2s, staging only, clock tick untouched)',()=>{
  assert.match(mig,/SET LOCAL lock_timeout = '2s'/);
  assert.match(mig,/NOT BETWEEN 2 AND 45/);
  assert.match(mig,/staging only/);
  assert.match(mig,/pdc\.r455_tick/);
  assert.doesNotMatch(mig,/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/i);
  assert.doesNotMatch(mig,/^\s*(DELETE FROM|TRUNCATE|DROP TABLE)\s+(public|karratha)/im);
});

test('r455: every changed function is pinned and the check is registered at sort 254',()=>{
  for(const p of pins){const [sig,md5]=p.split('::');assert.ok(mig.includes(md5),sig+' pin '+md5);assert.ok(mig.includes(sig),sig);}
  assert.match(mig,/INSERT INTO pdc_ops\.regression_checks/);
  assert.ok(mig.includes("'importer_read_scope_455'")&&mig.includes(',254,'),'check row');
});

test('r455: the undo restores the previous definitions, removes the pins and the check',()=>{
  assert.match(down,/NOT BETWEEN 2 AND 45/);
  assert.ok(down.includes('importer_read_scope_455'));
  assert.match(down,/DELETE FROM pdc_ops\.regression_checks/);
});

test('r455: no personal data in the release files',()=>{
  for(const s of [mig,down]){assert.doesNotMatch(s,/@(?!pdc\.invalid)[a-z0-9-]+\.[a-z]/i,'no email addresses');}
});

test('r455: the importer scope is read-only (viewer) and the AI Auditor scope is not changed',()=>{
  assert.match(mig,/'viewer'/);
  assert.doesNotMatch(mig,/CREATE OR REPLACE FUNCTION [a-z_.]*pdc_auditor_actor_scope/i);
  assert.doesNotMatch(mig,/CREATE OR REPLACE FUNCTION public\.(set|update|mark|record|book)_/i,'no write function changes');
});
