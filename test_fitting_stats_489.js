/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r489 (F102): Admin > Fitting statistics (administrators only). Synthetic data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const stats = require('./pdc-fitting-stats.js');
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');

const report = (categories, extra = {}) => ({ok:true, days:30, generated_at:'2026-10-22T16:00:00Z', since:'2026-09-22T16:00:00Z', timing_started_at:'2026-10-20T04:57:15Z', categories, ...extra});
const line = (extra) => ({line_type:'Steel Bull Bar', completed:3, timed:2, avg_minutes:75, median_minutes:75, min_minutes:60, max_minutes:90, avg_allowance_minutes:150, ...extra});

test('minutes read as hours and minutes; blanks never become a made-up time', () => {
  assert.equal(stats.formatMinutes(75), '1h 15m');
  assert.equal(stats.formatMinutes(45), '45m');
  assert.equal(stats.formatMinutes(0), '0m');
  assert.equal(stats.formatMinutes(0.4), 'under 1m');
  assert.equal(stats.formatMinutes(1044), '17h 24m');
  for (const v of [null, undefined, '', -5, 'abc']) assert.equal(stats.formatMinutes(v), '—');
});

test('report groups by category in board order with totals; times only from timed lines', () => {
  const r = stats.normalizeReport(report([
    {category:'TINT', jobs_completed:3, job_avg_elapsed_minutes:891.3, lines:[line({line_type:'Darkest Legal Window Tint', completed:2, timed:0, avg_minutes:null})]},
    {category:'FITTING', jobs_completed:1, job_avg_elapsed_minutes:120, lines:[line(), line({line_type:'Snorkel', completed:1, timed:1, avg_minutes:30, median_minutes:30, min_minutes:30, max_minutes:30, avg_allowance_minutes:60})]},
    {category:'BUS_MECHANICAL', jobs_completed:0, lines:[line({line_type:null, completed:1, timed:0})]},
    {category:'HOIST', jobs_completed:0, lines:[]}
  ]));
  assert.deepEqual(r.categories.map(c => c.label), ['Fitting', 'Tint', 'Bus 4×4 · Mechanical']);
  assert.deepEqual(r.totals, {completed:7, timed:3, jobs:4});
  const fitting = r.categories[0];
  assert.equal(fitting.completed, 4); assert.equal(fitting.timed, 3);
  assert.equal(Math.round(fitting.avg_line_minutes), 60); // (75*2 + 30) / 3
  const tint = r.categories[1].lines[0];
  assert.equal(tint.avg_minutes, null); assert.equal(tint.untimed, 2);
  const html = stats.reportHtml(r);
  assert.match(html, /Lines completed<\/span><strong>7</);
  assert.match(html, /<h3>Fitting<\/h3><p><strong>4<\/strong> lines completed · <strong>3<\/strong> timed · average 1h 00m per timed line/);
  assert.match(html, /1 station job completed · average 2h 00m start to finish/);
  assert.match(html, /Steel Bull Bar<\/th><td data-label="Completed">3<\/td><td data-label="Timed \(Start → Done\)">2<small> · 1 without Start<\/small>/);
  assert.match(html, /1h 15m<span class="fitting-stats-vs is-under">1h 15m under<\/span>/);
  assert.match(html, /Fastest – slowest">1h 00m – 1h 30m/);
  assert.match(html, /Line no longer on the job card/);
  assert.match(html, /Item timing was first recorded 20 Oct 2026/);
  assert.doesNotMatch(html, /HOIST|Hoist/);
});

test('over allowance shows red; category filter and sort work; text is escaped', () => {
  const r = stats.normalizeReport(report([{category:'FITTING', jobs_completed:0, lines:[
    line({line_type:'<img src=x onerror=alert(1)>', completed:1, timed:1, avg_minutes:90, avg_allowance_minutes:30}),
    line({line_type:'Alpha', completed:5, timed:0, avg_minutes:null}),
    line({line_type:'Beta', completed:2, timed:2, avg_minutes:200, avg_allowance_minutes:300})]},
    {category:'ELECTRICAL', jobs_completed:0, lines:[line({line_type:'UHF', completed:1, timed:0})]}]));
  const html = stats.reportHtml(r, {category:'FITTING', sort:'over'});
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /&lt;img src=x/);
  assert.match(html, /1h 00m over/);
  assert.doesNotMatch(html, /UHF/);
  const order = [...html.matchAll(/<th scope="row" data-label="Line type">([^<]+)</g)].map(m => m[1]);
  assert.deepEqual(order, ['&lt;img src=x onerror=alert(1)&gt;', 'Beta', 'Alpha']);
  assert.deepEqual(stats.sortLines(r.categories[0].lines, 'line_type').map(l => l.line_type), ['<img src=x onerror=alert(1)>', 'Alpha', 'Beta'].sort((a,b) => a.localeCompare(b,'en-AU',{sensitivity:'base'})));
  assert.deepEqual(stats.sortLines(r.categories[0].lines, 'avg_minutes').map(l => l.line_type)[0], 'Beta');
});

test('a refused or broken report is an error, never an empty page of zeros', () => {
  assert.throws(() => stats.normalizeReport({ok:false, code:'permission_denied'}), /Administrators only/);
  for (const bad of [null, {}, {ok:true}, {ok:true, categories:'x'}]) assert.throws(() => stats.normalizeReport(bad));
  const r = stats.normalizeReport(report([{category:'FITTING', lines:[line({completed:2, timed:9})]}], {days:999}));
  assert.equal(r.categories[0].lines[0].timed, 2);
  assert.equal(r.days, 30);
});

function fixture(role = 'administrator') {
  let ctx = {userId:'synthetic-admin', role, token:'t', url:'https://example.invalid', key:'k'};
  const pending = [], renders = [];
  const controller = stats.createController({context:() => ctx, request:(c, days) => new Promise((resolve, reject) => pending.push({c, days, resolve, reject})), render:s => renders.push(s)});
  return {controller, pending, renders, change:v => { ctx = {...ctx, ...v}; }};
}

test('only an administrator loads it; period changes reload; late answers are dropped', async () => {
  const viewer = fixture('controller');
  await viewer.controller.open();
  assert.equal(viewer.pending.length, 0);
  assert.equal(viewer.renders.at(-1).allowed, false);
  const f = fixture();
  const opening = f.controller.open();
  assert.equal(f.pending.length, 1); assert.equal(f.pending[0].days, 30);
  f.pending[0].resolve(report([{category:'FITTING', lines:[line()]}]));
  await opening;
  assert.equal(f.controller.getState().report.totals.completed, 3);
  const changing = f.controller.setDays('90');
  assert.equal(f.pending[1].days, 90);
  f.pending[1].resolve(report([], {days:90})); await changing;
  assert.equal(f.controller.getState().days, 90);
  f.controller.setDays('12345'); assert.equal(f.pending[2].days, 30);
  f.controller.close();
  f.pending[2].resolve(report([{category:'FITTING', lines:[line()]}])); await new Promise(r => setImmediate(r));
  assert.equal(f.controller.getState().report, null);
  const g = fixture(); const p = g.controller.open();
  g.change({role:'controller'});
  g.pending[0].resolve(report([{category:'FITTING', lines:[line()]}])); await p;
  assert.equal(g.controller.getState().report, null);
  const h = fixture(); const q = h.controller.open();
  h.pending[0].reject(new Error('net')); await q;
  assert.match(h.controller.getState().error, /Could not load fitting statistics/);
});

test('board wiring: hidden admin nav item and view, route guard, cache busts, Pages allowlist', () => {
  const html = read('index.html'), app = read('app.js');
  assert.match(html, /<button type="button" class="nav-item nav-admin-item" id="nav-fitting-stats" data-view="fitting-stats" data-short="FST" hidden>Fitting statistics<\/button>/);
  assert.match(html, /<section id="fitting-stats" class="view" hidden>\s*<div id="fitting-stats-content" class="panel"><\/div>/);
  const lazy = require('./pdc-lazy-admin-views.js').DEFINITIONS.find(view => view.name === 'PdcFittingStats');
  assert.equal(lazy.css, 'pdc-fitting-stats.css?r489=2026.10.23.r489');
  assert.equal(lazy.script, 'pdc-fitting-stats.js?r489=2026.10.23.r489');
  assert.match(html, /<script src="pdc-lazy-admin-views\.js\?v=2026\.10\.26\.opt1" defer><\/script>/);
  assert.match(html, /<script src="app\.js\?[^"]*r489=2026\.10\.23\.r489/);
  assert.match(app, /if \(requestedView === 'fitting-stats' && !userManagementAdministratorActive\(\)\) \{\s*window\.PdcFittingStats\?\.reset\(\);\s*requestedView = 'dashboard';/);
  assert.match(app, /new Set\(\['user-management', 'update-history', 'fitting-stats',/);
  assert.match(app, /case 'fitting-stats':\s*window\.PdcFittingStats\?\.open\(\);/);
  assert.match(app, /'fitting-stats': 'Fitting statistics'/);
  assert.match(app, /window\.PdcFittingStats\?\.syncAccess\(\);/);
  const builder = require('./scripts/build_pages_runtime.js');
  for (const f of ['pdc-fitting-stats.js', 'pdc-fitting-stats.css']) assert.ok(builder.RUNTIME_FILES.includes(f), f);
  assert.equal(stats.VERSION, '2026.10.23.r489');
  assert.match(read('pdc-fitting-stats.js'), /rpc\/get_pdc_fitting_statistics_489/);
});

test('migration (prepared, not applied): read-only admin RPC, staging guard, pin and check, LF only, matching undo', () => {
  const up = read('supabase/migrations/20261023020000_r489_fitting_statistics.sql');
  const down = read('supabase/rollbacks/20261023020000_r489_fitting_statistics.down.sql');
  for (const sql of [up, down]) { assert.equal(sql.includes('\r'), false); assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/); assert.match(sql, /NOT BETWEEN 2 AND 45/); assert.doesNotMatch(sql, /vjdtsswhroyguxyfjdkt/); }
  assert.match(up, /CREATE FUNCTION public\.get_pdc_fitting_statistics_489\(p_days integer\)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE SECURITY DEFINER\n SET search_path TO 'pg_catalog'/);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.get_pdc_fitting_statistics_489\(integer\) FROM PUBLIC, anon, authenticated;\nGRANT EXECUTE ON FUNCTION public\.get_pdc_fitting_statistics_489\(integer\) TO authenticated;/);
  const body = up.match(/AS \$function\$([\s\S]*?)\$function\$;/)[1];
  const md5 = crypto.createHash('md5').update(body).digest('hex');
  assert.ok(up.includes("('public.get_pdc_fitting_statistics_489(integer)','" + md5 + "','r489'"), 'pin matches body');
  assert.ok(down.includes(md5), 'undo checks the same body');
  assert.match(body, /r\.role::text = 'administrator'\s+AND r\.active IS TRUE AND r\.account_status = 'approved'/);
  assert.match(body, /RETURN jsonb_build_object\('ok', false, 'code', 'permission_denied'\)/);
  assert.match(body, /p_days NOT IN \(7, 30, 90, 365\)/);
  assert.doesNotMatch(body, /\b(INSERT|UPDATE|DELETE|TRUNCATE|PERFORM)\b/i);
  assert.doesNotMatch(body, /stock_number|customer|vin\b|registration/i);
  assert.match(up, /'fitting_statistics_489','F102'/);
  assert.match(up, /,true,289,'r489'\);/);
  assert.match(down, /DROP FUNCTION public\.get_pdc_fitting_statistics_489\(integer\);/);
});

test('FAULT_LOG F102', () => {
  assert.match(read('docs/FAULT_LOG.md'), /^\| F102 \| \d+ Oct /m);
});
