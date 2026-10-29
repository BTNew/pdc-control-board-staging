'use strict';
// r711 (F321): Sublet · PSC (Perth Sign Craft), a copy of Sublet · MMT. Pure helpers and wiring only; no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const psc = require('./pdc-psc-sublet.js');

const lines = [
  { vehicle_id: 'a', line_key: 'jc:J1:1', po_number: 'GP1', key_number: '247', stock_number: '13018567', customer: 'Acme', vehicle: 'HiLux', description: 'New Vehicle Complete Signage', built: false, complete: false, built_version: 0, complete_version: 0, days_at_pmg: 3 },
  { vehicle_id: 'b', line_key: 'jc:J2:7', po_number: 'GP2', key_number: '348', stock_number: '13073070', customer: 'Beta', vehicle: 'LC79', description: 'Avis Signage & Stripping', built: true, complete: true, built_version: 1, complete_version: 1 },
];

test('PSC page: same stages, search, ticks and invoice step as MMT, with PSC wording', () => {
  assert.equal(psc.VERSION, '2026.10.29.r711');
  assert.deepEqual(psc.counts(lines), { todo: 1, built: 0, complete: 1, all: 2 });
  assert.deepEqual(psc.filterLines(lines, 'all', 'K348').map(l => l.vehicle_id), ['b']);
  assert.match(psc.tickHtml(lines[0], 'built', true), /title="Signage made"/);
  assert.match(psc.invoiceHtml(lines[1], true), /PSC has invoiced/);
  assert.match(psc.panelHtml({ can_tick: true, lines: [] }, { filter: 'todo' }), /No PSC sublets at PMB/);
});

test('PSC wiring: tab, view, app hooks, phone exemption, /psc link and login lock', () => {
  const html = fs.readFileSync('index.html', 'utf8');
  assert.match(html, /data-view="psc-sublet"[^>]*>Sublet · PSC</);
  assert.match(html, /<section id="psc-sublet" class="view">[\s\S]*id="psc-sublet-content"/);
  assert.match(html, /pdc-psc-sublet\.js\?r711=2026\.10\.29\.r711/);
  const app = fs.readFileSync('app.js', 'utf8');
  assert.match(app, /case 'psc-sublet':[\s\S]{0,80}PdcPscSublet\?\.open\(\)/);
  assert.match(app, /if \(pscOnly\) \{[\s\S]{0,200}showView\('psc-sublet'/);
  assert.match(fs.readFileSync('pdc-auth.js', 'utf8'), /isPscSession\(\) && !PSC_RPC_ALLOWLIST\.has/);
  assert.match(fs.readFileSync('canonical-entry.js', 'utf8'), /'#\/psc-sublet'\]\.includes\(location\.hash\)/);
  assert.match(fs.readFileSync('pdc-psc-sublet.js', 'utf8'), /view === 'qc' && phone\?\.matches && \(wantPsc \|\| pscLogin\) \? 'psc-sublet' : view/);
  assert.match(fs.readFileSync('psc/index.html', 'utf8'), /\.\.\/#\/psc-sublet/);
  assert.match(fs.readFileSync('pdc-mmt-sublet.css', 'utf8'), /body\.psc-only \.view:not\(#psc-sublet\)/);
});

test('PSC database: own line rule, never MMT seat-cover lines, own login branch, undo exists', () => {
  const sql = fs.readFileSync('supabase/migrations/20261029040000_r711_psc_sublet.sql', 'utf8');
  assert.match(sql, /CREATE FUNCTION pdc_mmt_private\.psc_line_711/);
  assert.match(sql, /!~\* '\\m\(mmt\|malaga\)'/);
  assert.match(sql, /v_provider='PSC' AND \(path NOT IN \('rpc\/get_pdc_psc_sublet_board_711'/);
  assert.match(sql, /This account can access Fitters bay only/);
  assert.doesNotMatch(sql.slice(sql.indexOf('CREATE FUNCTION public.get_pdc_psc_sublet_board_711')), /mmt\|malaga\)'\s*\n\s*AND v\.deleted_at/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261029040000_r711_psc_sublet.down.sql'));
});
