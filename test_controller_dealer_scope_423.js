/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r423 (F37): controllers (and administrators) without a dealer-scope row can use the dealer-scoped workshop
// actions (Parts received, line hours save, sublet ledger, workshop detail/search) on the board dealer.
// The AI Auditor stays scope-row only: pdc_auditor_actor_scope() is not changed.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = __dirname;
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const V = '20261021005130_r423_controller_dealer_scope';
const migration = read(`supabase/migrations/${V}.sql`);
const rollback = read(`supabase/rollbacks/${V}.down.sql`);

function fnBody(sql, header) {
  const start = sql.indexOf(header);
  assert.notEqual(start, -1, header);
  const open = sql.indexOf('$function$', start);
  const close = sql.indexOf('$function$', open + 10);
  return sql.slice(open + 10, close);
}

test('the controller scope helper is private and only covers approved controllers/administrators without a scope row', () => {
  const body = fnBody(migration, 'CREATE FUNCTION public.pdc_workshop_controller_scope_423()');
  assert.match(body, /'operator'\s*,\s*'administrator'/);
  assert.match(body, /pdc_auditor_user_dealer_scopes/);
  assert.match(body, /banned_until/);
  assert.doesNotMatch(body, /'importer'|'viewer'|'fitter'|'salesperson'/);
  assert.match(migration, /REVOKE ALL ON FUNCTION public\.pdc_workshop_controller_scope_423\(\) FROM PUBLIC, anon, authenticated;/);
});

test('Parts received, hours save, sublet ledger and the workshop read scope accept the controller scope', () => {
  assert.match(fnBody(migration, 'CREATE OR REPLACE FUNCTION public.mark_pdc_parts_received_authenticated_751('),
    /IF v_role<>'administrator' AND public\.pdc_workshop_controller_scope_423\(\) IS NULL THEN/);
  for (const name of ['save_vehicle_workshop_line_hours_batch_768', 'get_pdc_sublet_audit_ledgers']) {
    assert.match(fnBody(migration, `CREATE OR REPLACE FUNCTION public.${name}(`),
      /v_scope:=coalesce\(public\.pdc_workshop_controller_scope_423\(\),public\.pdc_auditor_actor_scope\(\)\);/, name);
  }
  assert.match(fnBody(migration, 'CREATE OR REPLACE FUNCTION pdc_codex_intake_private.workshop_read_actor_scope_20261013()'),
    /pdc_workshop_controller_scope_423\(\)/);
});

test('the AI Auditor is untouched and stays scope-row only', () => {
  assert.doesNotMatch(migration, /FUNCTION public\.pdc_auditor_actor_scope\(/);
  assert.doesNotMatch(migration, /FUNCTION public\.get_pdc_auditor_/);
  assert.doesNotMatch(migration, /INSERT INTO public\.pdc_auditor_user_dealer_scopes/i);
});

test('the migration is guarded, pinned, checked and leaves the clock tick alone', () => {
  assert.match(migration, /NOT BETWEEN 2 AND 45/);
  assert.match(migration, /84af7607bfd0ce9907c89bae8644d5b6/);
  assert.match(migration, /'controllers_use_dealer_scoped_actions','F37'/);
  assert.match(migration, /WHERE release='r423'\)<>5/);
  assert.doesNotMatch(migration, /workshop_clock_tick\(boolean,timestamptz\) *(RETURNS|AS)/i);
  assert.doesNotMatch(migration, /@[a-z0-9-]+\.[a-z]/i);
});

test('the rollback restores the four functions and drops the helper, pins and check', () => {
  assert.match(fnBody(rollback, 'CREATE OR REPLACE FUNCTION public.mark_pdc_parts_received_authenticated_751('),
    /IF v_role<>'administrator' THEN/);
  assert.match(rollback, /DROP FUNCTION public\.pdc_workshop_controller_scope_423\(\);/);
  assert.match(rollback, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r423';/);
  assert.match(rollback, /c16f3b384c19c3e1b120347be72c9af1/);
});
