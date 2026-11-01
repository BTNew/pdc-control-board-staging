'use strict';
// r816 (F455): fitter initials + PIN sign-in. Built for preview; applied only when Craig has the names.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const F = require('./pdc-fitters.js');
const L = require('./pdc-fitter-logins.js');
const sql = fs.readFileSync('supabase/migrations/20261102063000_r816_fitter_logins.sql', 'utf8');
const fitters = fs.readFileSync('pdc-fitters.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

test('PIN rule matches the server: 4 to 6 digits, not all one digit, not a run', () => {
  for (const bad of ['1234', '0000', '4321', '987654', '111111', '123456']) assert.equal(F.fitterPinProblem(bad), 'pin_too_simple', bad);
  for (const bad of ['123', '12a4', '1234567', '', null]) assert.equal(F.fitterPinProblem(bad), 'pin_format', String(bad));
  for (const good of ['2580', '7391', '135790', '9021']) assert.equal(F.fitterPinProblem(good), '', good);
  assert.match(sql, /strpos\('0123456789', d\) > 0 OR strpos\('9876543210', d\) > 0/);
});

test('random temporary PINs always pass the rule', () => {
  let x = 0; const rand = () => { x = (x * 9301 + 49297) % 233280; return x / 233280; };
  for (let i = 0; i < 500; i++) assert.equal(F.fitterPinProblem(L.randomPin(rand)), '');
});

test('Craig 06:33: username is the Tune mechanic ID, first password is initials then mechanic ID', () => {
  assert.equal(L.initials('Mudassar Rasheed'), 'MR');
  assert.equal(L.initials('Chelsea Rees # 2'), 'CR');
  assert.equal(L.defaultTempPassword('Mudassar Rasheed', '2686'), '2686', 'Craig 07:30: first PIN is the fitter number');
  assert.equal(L.defaultTempPassword('Mudassar Rasheed', ''), '', 'no Tune ID, no default');
  assert.match(sql, /username text NOT NULL UNIQUE CHECK \(username ~ '\^\[0-9\]\{2,6\}\$'\)/);
  assert.match(sql, /extensions\.crypt\(t\.code, extensions\.gen_salt\('bf', 8\)\), true/, 'bulk logins start with the fitter number and must change');
  assert.equal(F.fitterPinProblem('MR2686'), 'pin_format', 'initials+ID is never accepted as the fitter\'s own PIN');
});

test('sign-in screen: names, then a masked password box and PIN pad', () => {
  const pick = F.fitterLoginGateHtml({ mode:'pick', fitters:[{ username:'2686', name:'Mudassar Rasheed' }], pin:'', newPin:null });
  assert.match(pick, /data-fitter-login-user="2686"/);
  assert.match(pick, /Mudassar Rasheed/);
  const pin = F.fitterLoginGateHtml({ mode:'pin', username:'2686', name:'Mudassar', pin:'MR2686', newPin:null });
  assert.match(pin, /<input type="password"[^>]*data-fitter-pin-input/);
  assert.match(pin, /Your PIN is your fitter number/);
  assert.match(pin, /data-fitter-pin-ok(?![^>]*disabled)/);
  const short = F.fitterLoginGateHtml({ mode:'pin', username:'2686', pin:'25', newPin:null });
  assert.match(short, /data-fitter-pin-ok[^>]*disabled/);
  const change = F.fitterLoginGateHtml({ mode:'change', username:'MR', name:'Mudassar', pin:'', newPin:null });
  assert.match(change, /pick your own PIN/);
  assert.match(F.fitterLoginGateHtml({ mode:'pick', fitters:[], pin:'' }), /No fitter logins yet/);
});

test('every Fitters bay request carries the signed-in fitter session header', async () => {
  let seen;
  const ctx = { actor:'u', role:'fitter', token:'t', config:{ projectRef:'cdsmnqxtyyoeoznmbidd', url:'https://cdsmnqxtyyoeoznmbidd.supabase.co', publishableKey:'k', workshop:{ sharedData:true } } };
  const s = F.createService({
    context:() => ctx,
    fetch:async (url, opts) => { seen = opts.headers; return { ok:true, json:async () => ({ ok:true, technicians:[] }) }; },
    uuid:() => 'id', fitterToken:() => 'tok123',
  });
  await s.login('fitter_login_state_816');
  assert.equal(seen['x-pdc-fitter-session'], 'tok123');
  const s2 = F.createService({
    context:() => ctx,
    fetch:async (url, opts) => { seen = opts.headers; return { ok:true, json:async () => ({ ok:true }) }; }, uuid:() => 'id', fitterToken:() => '',
  });
  await s2.login('fitter_login_state_816');
  assert.equal('x-pdc-fitter-session' in seen, false);
});

test('server: guards only bite once required is switched on, and the four writes are guarded', () => {
  assert.match(sql, /required boolean NOT NULL DEFAULT false/);
  assert.match(sql, /IF NOT coalesce\(\(SELECT required FROM pdc_ops\.fitter_login_settings_816 WHERE singleton\), false\) THEN RETURN NULL/);
  for (const fn of ['fitter_job_command', 'handoff_operation_line_583', 'undo_line_handoff_583', 'set_line_later_627']) assert.match(sql, new RegExp(`public\\.${fn}\\(`));
  assert.match(sql, /'rpc\/fitter_sign_in_816'/);
  assert.match(sql, /extensions\.crypt\(upper\(btrim\(p_temp_pin\)\), extensions\.gen_salt\('bf', 8\)\)/);
  assert.match(sql, /encode\(extensions\.digest\(v_token, 'sha256'\), 'hex'\)/, 'only a hash of the session token is stored');
  assert.match(sql, /failed_count \+ 1 >= 5/);
  assert.doesNotMatch(sql.replace(/--[^\n]*/g, ''), /\bdob\b|date_of_birth|birth/i, 'no date of birth is stored or used');
});

test('page: with sign-in required the mechanic is the signed-in fitter, not the name list', () => {
  assert.match(fitters, /const wanted = loginRequired\(\) \? \(signedIn\(\) \? fitterSession\.fitter\.technician_id : ''\) : mechanicBefore;/);
  assert.match(fitters, /if \(loginRequired\(\) && !signedIn\(\)\) \{/);
  assert.match(fitters, /Signed out after \$\{loginState\.idle\|\|10\} minutes without use\./);
  assert.match(html, /<script src="pdc-fitter-logins\.js\?r816=2026\.11\.02\.r816" defer><\/script>/);
  assert.match(html, /<div id="fitter-logins-content" class="panel"><\/div>/);
});

test('admin panel: Tune ID usernames, initials+ID first passwords, one-button create', () => {
  const out = L.panelHtml({ payload:{ required:false, idle_minutes:10, technicians:[
    { technician_id:'a', name:'Mudassar Rasheed', username:'2686', active:true, must_change:true },
    { technician_id:'b', name:'Jo Tan', code:'2401', username:null },
    { technician_id:'c', name:'No Code', code:null, username:null } ] }, drafts:{}, rowMessage:{}, busy:false });
  assert.match(out, /Temporary PIN · not signed in yet/);
  assert.match(out, /No login/);
  assert.match(out, /value="2401"/);
  assert.equal((out.match(/value="2401"/g) || []).length, 2, 'ID and first PIN both prefilled');
  assert.match(out, /must pick their own 4 to 6 number PIN/);
  assert.match(out, /data-fitter-login-bulk/);
  assert.match(out, /1 without a Tune ID/);
  assert.match(out, /Sign-in is OFF/);
});
