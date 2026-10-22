/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r484 (F97, Craig approved in chat 22 Oct 2026 14:18 AWST): accept Revolution's Pilbara parts report addressed To
// pdc@pmgwa.com.au with Craig on CC. One recipient case added to the shared sign-in check; nothing else loosened.
// Database behaviour is proven by tests/r484_local_harness/run.sh (throwaway local PostgreSQL) and daily on staging by
// parts_auth_pdc_mailbox_484 (sort 284). Synthetic ids only; no stock numbers, R/Os or real message ids in Git.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), cp = require('node:child_process'), crypto = require('node:crypto');
const MIG = 'supabase/migrations/20261022063000_r484_parts_auth_pdc_mailbox.sql';
const DOWN = 'supabase/rollbacks/20261022063000_r484_parts_auth_pdc_mailbox.down.sql';
const H = 'tests/r484_local_harness/';
const mig = fs.readFileSync(MIG, 'utf8'), down = fs.readFileSync(DOWN, 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const SIG = 'pdc_codex_intake_private.revolution_parts_authenticated_20261006(jsonb,text)';
const OLD_DEF = 'bd378910e0328a5c6bcab980195d73d4', OLD_SRC = '67d03f901dc6ba475691a9661fff8826';
const NEW_DEF = 'abbb00e85839a85c47df7de16c9895bd', NEW_SRC = '6c1a612f6ed82dfcbf5788c17d2e5d87';
const between = (s, a, b) => { const i = s.indexOf(a); assert.ok(i >= 0, a); const j = s.indexOf(b, i + a.length); assert.ok(j > i, b); return s.slice(i + a.length, j); };
const crlfBody = def => between(def, 'AS $function$', '$function$').replace(/\n/g, '\r\n');
const newBody = () => between(mig, 'AS $function$', '$function$');
const oldLive = fs.readFileSync(H + 'old_function_live.sql', 'utf8');

test('files are LF only (CRLF did not survive the MCP transport for r479)', () => {
  for (const f of [MIG, DOWN, H + 'old_function_live.sql', H + 'parts_caller_live.sql', H + 'cases.sql', H + 'stubs.sql', H + 'run.sh']) assert.doesNotMatch(fs.readFileSync(f, 'utf8'), /\r/, f);
});

test('the harness copy of the live function is the live version (functiondef and prosrc md5)', () => {
  assert.equal(md5(crlfBody(oldLive)), OLD_SRC);
  const def = oldLive.replace(between(oldLive, 'AS $function$', '$function$'), () => crlfBody(oldLive));
  assert.equal(md5(def), OLD_DEF);
});

test('new body = old body (LF) + exactly one recipient case, nothing else changed', () => {
  const oldLf = between(oldLive, 'AS $function$', '$function$'), nb = newBody();
  assert.equal(md5(nb), NEW_SRC);
  assert.equal(md5(oldLive.replace(oldLf, () => nb)), NEW_DEF, 'functiondef md5 the apply checks');
  const o = oldLf.split('\n'), n = nb.split('\n');
  assert.equal(n.length, o.length + 2);
  const i = o.findIndex((l, k) => l !== n[k]);
  assert.equal(n[i] + ')', o[i], 'the old To/CC group only loses its closing bracket to the new case');
  assert.match(n[i + 1], /^\s+-- r484 \(F97\)/);
  assert.equal(n[i + 2], "   OR (p_auth->>'to_address'='pdc@pmgwa.com.au' AND p_auth->'cc_addresses' @> '[\"craig.watson@broometoyota.com.au\"]'::jsonb))");
  assert.deepEqual(n.slice(i + 3), o.slice(i + 1), 'every later check identical');
  assert.deepEqual(n.slice(0, i), o.slice(0, i), 'every earlier check identical');
  for (const keep of ["p_auth->>'from_address'='noreply@revolutionsoftware.com.au'", "p_auth->>'mailbox'='pmbcontroller@gmail.com'", 'spf=pass', 'dmarc=pass', "p_auth->>'verified_by'='gmail_receiving_provider'"]) assert.ok(nb.includes(keep), keep);
});

test('migration: header unchanged, guards (staging, window :02-:45, lock 2s, old md5s, not applied), pin + check, final check', () => {
  assert.ok(mig.includes(oldLive.slice(0, oldLive.indexOf('AS $function$'))), 'same signature / language / volatility / search_path; no SECURITY DEFINER');
  assert.doesNotMatch(mig.slice(mig.indexOf('CREATE OR REPLACE'), mig.indexOf('$function$')), /SECURITY DEFINER|GRANT|REVOKE|ALTER FUNCTION/);
  assert.match(mig, /^SET LOCAL lock_timeout = '2s';$/m);
  assert.match(mig, /NOT BETWEEN 2 AND 45/);
  assert.match(mig, /project_ref='cdsmnqxtyyoeoznmbidd'/); assert.doesNotMatch(mig + down, /vjdtsswhroyguxyfjdkt/);
  assert.ok(mig.includes(`IS DISTINCT FROM '${OLD_DEF}'`) && mig.includes(`IS DISTINCT FROM '${OLD_SRC}'`));
  assert.ok(mig.includes(`('${SIG}','${NEW_SRC}','r484',`), 'schema-qualified pin to the new prosrc md5');
  assert.ok(mig.includes(`IS DISTINCT FROM '${NEW_DEF}'`), 'final functiondef check');
  assert.match(mig, /position\(chr\(13\) IN prosrc\)/);
  assert.match(mig, /current_setting\('pdc\.r484_pins'\)::int\+1/);
  assert.match(mig, /\('parts_auth_pdc_mailbox_484','F97',/); assert.match(mig, /,true,284,'r484'\);/);
  assert.equal((mig.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1, 'only this function');
});

test('undo: rebuilds the exact old CRLF body from an LF literal and removes the pin and check', () => {
  const lit = between(down, '$old$', '$old$');
  assert.equal(md5(lit.slice(1).replace(/\n/g, '\r\n')), OLD_SRC);
  assert.ok(down.includes(`IS DISTINCT FROM '${NEW_SRC}'`), 'refuses to undo over unknown changes');
  assert.ok(down.includes(`IS DISTINCT FROM '${OLD_DEF}'`), 'checks the restored functiondef');
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r484'/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='parts_auth_pdc_mailbox_484'/);
  assert.match(down, /NOT BETWEEN 2 AND 45/); assert.match(down, /^SET LOCAL lock_timeout = '2s';$/m);
});

test('no real ids in Git: synthetic message ids and sha only', () => {
  for (const f of [MIG, DOWN, H + 'cases.sql', H + 'run.sh', 'test_parts_auth_pdc_mailbox_484.js']) {
    const s = fs.readFileSync(f, 'utf8');
    assert.doesNotMatch(s, new RegExp(['1a1622e0' + 'ab01660c', 'e2c1d13a' + '4af38dee'].join('|')), f);
    assert.doesNotMatch(s, /\b1\d{7}\b|J13[89]\d{6}/, f);
  }
});

function localPg() { try { cp.execSync("sudo -n -u postgres psql -Atc 'select 1'", { stdio: 'pipe', timeout: 5000 }); return true; } catch { return false; } }
test('local PostgreSQL harness: apply as is, 26 check cases, 15 gate cases x 3 phases, CRLF copy refused, undo exact',
  { skip: !localPg() && 'no local PostgreSQL on this machine (run tests/r484_local_harness/run.sh where there is one)' }, () => {
  const out = cp.execSync('bash tests/r484_local_harness/run.sh', { encoding: 'utf8', timeout: 240000, stdio: ['ignore', 'pipe', 'pipe'] });
  assert.match(out, /check parts_auth_pdc_mailbox_484: true .*cases right 26\/26/);
  assert.match(out, /crlf copy: refused and rolled back/);
  assert.doesNotMatch(out, /FAIL/);
  assert.match(out, /r484 local harness: PASS/);
});
