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

// r850 (F400) replaced the page with a model / fitter breakdown (test_fitting_stats_850.js). These keep the r489 report working
// as the fallback when the r850 database update is missing: the old shape loads as one 'All models' section with the same totals.
test('r489 report still loads (fallback): one All models section, categories in board order, totals unchanged', () => {
  const r = stats.normalizeReport(report([
    {category:'TINT', jobs_completed:3, job_avg_elapsed_minutes:891.3, lines:[line({line_type:'Darkest Legal Window Tint', completed:2, timed:0, avg_minutes:null})]},
    {category:'FITTING', jobs_completed:1, job_avg_elapsed_minutes:120, lines:[line(), line({line_type:'Snorkel', completed:1, timed:1, avg_minutes:30, median_minutes:30, min_minutes:30, max_minutes:30, avg_allowance_minutes:60})]},
    {category:'BUS_MECHANICAL', jobs_completed:0, lines:[line({line_type:null, completed:1, timed:0})]},
    {category:'HOIST', jobs_completed:0, lines:[]}
  ]));
  assert.equal(r.legacy, true);
  assert.deepEqual(r.models.map(m => m.label), ['All models']);
  assert.deepEqual(r.models[0].categories.map(c => c.label), ['Fitting', 'Tint', 'Bus 4×4 · Mechanical']);
  assert.deepEqual(r.totals, {completed:7, timed:3, jobs:4});
  assert.equal(Math.round(r.models[0].categories[0].avg_line_minutes), 60);
  const html = stats.reportHtml(r);
  assert.match(html, /Lines completed<\/span><strong>7</);
  assert.match(html, /needs the database update/);
  assert.match(html, /Line no longer on the job card/);
  assert.doesNotMatch(html, /HOIST|Hoist/);
});

test('a refused or broken report is an error, never an empty page of zeros', () => {
  assert.throws(() => stats.normalizeReport({ok:false, code:'permission_denied'}), /Administrators only/);
  for (const bad of [null, {}, {ok:true}, {ok:true, categories:'x'}]) assert.throws(() => stats.normalizeReport(bad));
  const r = stats.normalizeReport(report([{category:'FITTING', lines:[line({completed:2, timed:9})]}], {days:999}));
  assert.equal(r.models[0].categories[0].lines[0].timed, 2);
  assert.equal(r.days, 30);
});

test('board wiring: hidden admin nav item and view, route guard, Pages allowlist (r850 cache busts)', () => {
  const html = read('index.html'), app = read('app.js');
  assert.match(html, /<button type="button" class="nav-item nav-admin-item" id="nav-fitting-stats" data-view="fitting-stats" data-short="FST" hidden>Fitting statistics<\/button>/);
  assert.match(html, /<section id="fitting-stats" class="view" hidden>\s*<div id="fitting-stats-content" class="panel"><\/div>/);
  assert.match(html, /<script src="app\.js\?[^"]*r489=2026\.10\.23\.r489/);
  assert.match(app, /if \(requestedView === 'fitting-stats' && !userManagementAdministratorActive\(\)\) \{\s*window\.PdcFittingStats\?\.reset\(\);\s*requestedView = 'dashboard';/);
  assert.match(app, /new Set\(\['user-management', 'update-history', 'fitting-stats',/);
  assert.match(app, /case 'fitting-stats':\s*window\.PdcFittingStats\?\.open\(\);/);
  assert.match(app, /'fitting-stats': 'Fitting statistics'/);
  assert.match(app, /window\.PdcFittingStats\?\.syncAccess\(\);/);
  const builder = require('./scripts/build_pages_runtime.js');
  for (const f of ['pdc-fitting-stats.js', 'pdc-fitting-stats.css']) assert.ok(builder.RUNTIME_FILES.includes(f), f);
  assert.match(read('pdc-fitting-stats.js'), /rpc\/' \+ rpc|get_pdc_fitting_statistics_489/);
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
