'use strict';
// r643 (F258): the MMT login opens Sublet · MMT only (browser side); the database hook refuses the rest.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('browser: MMT login refuses other RPCs locally, lands on Sublet · MMT, hides the rest', () => {
  const auth = fs.readFileSync('pdc-auth.js', 'utf8');
  assert.match(auth, /MMT_LOGINS = Object\.freeze\(new Set\(\['mmt@neatseat\.com\.au'\]\)\)/);
  assert.match(auth, /isMmtSession\(\) && !MMT_RPC_ALLOWLIST\.has/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /if \(mmtOnly\) \{[\s\S]{0,200}showView\('mmt-sublet'/);
  const css = fs.readFileSync('pdc-mmt-sublet.css', 'utf8');
  assert.match(css, /body\.mmt-only \.nav > :not\(\[data-view="mmt-sublet"\]\)/);
  assert.match(css, /body\.mmt-only \.view:not\(#mmt-sublet\)/);
});

test('database: pre-request hook keeps the fitter branch and adds the MMT branch', () => {
  const sql = fs.readFileSync('supabase/migrations/20261028235500_r643_mmt_only_login.sql', 'utf8');
  assert.match(sql, /This account can access Fitters bay only/);
  assert.match(sql, /pdc_mmt_private\.providers/);
  assert.match(sql, /rpc\/get_pdc_mmt_sublet_board_642','rpc\/set_pdc_mmt_sublet_tick_642'/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028235500_r643_mmt_only_login.down.sql'));
});

test('phones: Sublet · MMT is not forced to QC (like Fitters bay); shared QC phone file untouched', () => {
  const entry = fs.readFileSync('canonical-entry.js', 'utf8');
  assert.match(entry, /\['#\/fitters', '#\/mmt-sublet'\]\.includes\(location\.hash\)/);
  const page = fs.readFileSync('pdc-mmt-sublet.js', 'utf8');
  assert.match(page, /view === 'qc' && phone\?\.matches && \(wantMmt \|\| mmtLogin\) \? 'mmt-sublet' : view/);
  assert.equal(fs.readFileSync('pdc-qc-mobile.js', 'utf8'), fs.readFileSync('karratha/pdc-qc-mobile.js', 'utf8'));
});
