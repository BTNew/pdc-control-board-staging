/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r850 (F400): Admin > Fitting statistics by model and fitter. Synthetic data only (line names are real job card wording).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const stats = require('./pdc-fitting-stats.js');
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');

const BEN = '0ed9b06b-5314-4f18-9290-c9d115a2f951';
const JAMIE = '11111111-2222-4333-8444-555555555555';
const line = extra => ({line_type:'Steel Bull Bar - Commercial', completed:3, timed:2, avg_minutes:75, median_minutes:75, min_minutes:60, max_minutes:90, avg_allowance_minutes:150, ...extra});
const report = (models, extra = {}) => ({ok:true, days:0, generated_at:'2026-10-30T03:00:00Z', since:null, timing_started_at:'2026-10-20T04:57:15Z',
  technician:null, technicians:[{id:BEN, name:'Ben Palmer', completed:90}, {id:JAMIE, name:'Jamie Bello', completed:22}], models, ...extra});
const hilux = () => ({model:'HILUX', categories:[
  {category:'FITTING', jobs_completed:2, job_avg_elapsed_minutes:240, lines:[
    line(),
    line({line_type:'STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY', completed:2, timed:2, avg_minutes:150, min_minutes:120, max_minutes:180, avg_allowance_minutes:150}),
    line({line_type:'Cargo Barrier', completed:1, timed:0, avg_minutes:null}),
    line({line_type:'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Small Round Plug (Long Tongue)', completed:4, timed:1, avg_minutes:40, min_minutes:40, max_minutes:40, avg_allowance_minutes:60})]},
  {category:'TINT', jobs_completed:1, job_avg_elapsed_minutes:60, lines:[line({line_type:'Darkest Legal Window Tint', completed:1, timed:1, avg_minutes:55, avg_allowance_minutes:60})]}]});

test('item types: real job card wording groups as a fitter would (bull bars together, tow bar not tray, typos)', () => {
  const cases = {
    'STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY':'Bull bar', 'ARB DELUXE BULLBAR':'Bull bar', 'Supply and Fit ARB Summit Bar MK2 Hilus MY265':'Bull bar', 'ARB Spartanbar SMARTBAR':'Bull bar',
    'Front Recovery Points - For Bull Bar (w/o Winch)':'Recovery points', 'SIDE STEP & SIDE RAIL KIT - FOR STEEL BULL BAR - MATTE - BROOME TO SUPPLY':'Side steps / rails',
    'FITTING KIT FOR DRIVING LIGHTS - FOR HOOPED STEEL BULL BAR - BROOME TO SUPPLY':'Lights',
    'Cargo Barrier':'Cargo barrier', 'CARGO BARRIER - REAR POSITION - BROOME TO SUPPLY':'Cargo barrier', 'Certified Mesh Cab Rack Barrier Rated To 60kg':'Cab rack',
    'Tow Bar [For 2550mm/2100mm/1800mm Tray Body] with Small Round Plug (Long Tongue)':'Tow bar', '7pin Small Round Wiring Harness':'Tow bar',
    'Safety Traingle Kit & Holder Mounted to L/H Tray Headboard or Cargo area':'Safety triangle', '41MM Wheel Nut Indicaors':'Wheel nut indicators',
    'PRE-DELIVERY (COMMERCIAL) 04L2A *SUS 16C6A*':'Pre-delivery', 'CARRY OUT PRE DELIVERY INSPECTION':'Pre-delivery',
    'Heavy Duty Denim/Canvas seat covers order Cargo storage nets at same time to be fitted':'Seat covers',
    'ARB Long Range Fuel Tank':'Long range fuel tank', 'COMPLEMENTARY FULL TANK OF FUEL -- 05I2A':'Fuel', 'PIT AND WEIGH':'Pit and weigh',
    'MINE BAR WITH FORWARD FACING INDICATORS, DUAL SOUND REVERSE BUZZER & WORK LIGHTS- Isuzu- ACOT500':'Beacons / buzzers / mine bars',
    'Coaster Bus 4x4 Conversion - 6 Speed 2.8':'Bus 4×4 conversion', 'UHF GME XRS330C OUTBACK PACK AE4707B AERIAL':'UHF / radio / comms',
    'OME Premium 40mm Nitro+ Lift 300Kg Rears Includes Wheel alignment':'Suspension / GVM', 'Darkest Legal Window Tint':'Window tint',
    'MY 26 HILUX BONNET STRUT GAS':'My 26 hilux bonnet strut gas', '':'Line no longer on the job card'
  };
  for (const [text, want] of Object.entries(cases)) assert.equal(stats.itemType(text), want, text);
  assert.equal(stats.cleanLineType('PRE-DELIVERY (COMMERCIAL) -- 05H2A'), 'PRE-DELIVERY (COMMERCIAL)');
  assert.equal(stats.cleanLineType('STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY'), 'STEEL BULL BAR - PREMIUM');
  assert.ok(stats.itemType('ALSO CHECK OVERALL ANY PANEL DAMAGE OR BODY DAMAGE THAT WE CANT QUOTE TO REPAIR TO LET THE CUSTOMER KNOW').length <= 49);
});

test('item type figures: completed and timed add up, average weighted by timed lines, range across lines, no made-up median', () => {
  const r = stats.normalizeReport(report([hilux()]));
  const bull = r.models[0].categories[0].items.find(i => i.item === 'Bull bar');
  assert.equal(bull.completed, 5); assert.equal(bull.timed, 4); assert.equal(bull.untimed, 1);
  assert.equal(bull.avg_minutes, (75 * 2 + 150 * 2) / 4);
  assert.equal(bull.min_minutes, 60); assert.equal(bull.max_minutes, 180);
  assert.equal(bull.avg_allowance_minutes, 150);
  assert.equal(bull.median_minutes, undefined);
  assert.equal(bull.lines.length, 2);
  const barrier = r.models[0].categories[0].items.find(i => i.item === 'Cargo barrier');
  assert.equal(barrier.avg_minutes, null); assert.equal(barrier.timed, 0);
});

test('models in board order with friendly names; totals; fitter list sorted; model drop-down sections', () => {
  const r = stats.normalizeReport(report([
    {model:'UNKNOWN', categories:[{category:'FITTING', lines:[line({completed:1, timed:0})]}]},
    {model:'PRADO', categories:[{category:'FITTING', jobs_completed:1, job_avg_elapsed_minutes:90, lines:[line({line_type:'Safari Snorkel', completed:1, timed:1, avg_minutes:50})]}]},
    {model:'LC70', categories:[{category:'FITTING', lines:[line({completed:2, timed:0})]}]},
    {model:'DMAX', categories:[{category:'FITTING', lines:[line({completed:1, timed:0})]}]},
    hilux(),
    {model:'LC300', categories:[{category:'HOIST', jobs_completed:0, lines:[]}]}
  ]));
  assert.equal(r.legacy, false);
  assert.deepEqual(r.models.map(m => m.label), ['HiLux', 'Prado', '70 Series', 'Isuzu D-Max', 'Model not recorded']);
  assert.deepEqual(r.totals, {completed:16, timed:7, jobs:4});
  assert.deepEqual(r.technicians.map(t => t.name), ['Ben Palmer', 'Jamie Bello']);
  assert.deepEqual(r.categoryCodes, ['FITTING', 'TINT']);
  const html = stats.reportHtml(r);
  assert.match(html, /<details class="fitting-stats-model" data-fitting-stats-model="HILUX"[^>]*><summary><h3>HiLux<\/h3><span><strong>11<\/strong> lines completed · 6 timed · 3 station jobs<\/span><\/summary>/);
  assert.match(html, /data-fitting-stats-item="Bull bar"[^>]*><summary><span class="fitting-stats-item-name">Bull bar<\/span><span class="fitting-stats-item-figures"><strong>5<\/strong> done · 4 timed · average 1h 53m · 1h 00m – 3h 00m · allowance 2h 30m<span class="fitting-stats-vs is-under">38m under<\/span>/);
  assert.match(html, /STEEL BULL BAR - PREMIUM - BROOME TO SUPPLY<\/th>/);
  assert.match(html, /Models<\/span><strong>5</);
  assert.doesNotMatch(html, /data-fitting-stats-model="LC300"|<h4>Hoist/);
  // Choosing one model opens it and shows only that model.
  const one = stats.reportHtml(r, {model:'HILUX'});
  assert.match(one, /data-fitting-stats-model="HILUX"[^>]* open>/);
  assert.doesNotMatch(one, /data-fitting-stats-model="PRADO"/);
  assert.match(one, /Lines completed<\/span><strong>11</);
  // Category filter across models.
  const tint = stats.reportHtml(r, {category:'TINT'});
  assert.match(tint, /Window tint/);
  assert.doesNotMatch(tint, /data-fitting-stats-item="Bull bar"|data-fitting-stats-model="PRADO"/);
});

test('sort applies to item types and to the lines inside them; text is escaped', () => {
  const r = stats.normalizeReport(report([{model:'HILUX', categories:[{category:'FITTING', lines:[
    line({line_type:'<img src=x onerror=alert(1)>', completed:9, timed:1, avg_minutes:10, avg_allowance_minutes:5}),
    line({line_type:'Safari Snorkel', completed:1, timed:1, avg_minutes:200, avg_allowance_minutes:60}),
    line({line_type:'Cargo Barrier', completed:3, timed:0})]}]}]));
  const html = stats.reportHtml(r, {sort:'over'});
  assert.doesNotMatch(html, /<img/);
  assert.match(html, /&lt;img src=x/);
  const order = [...html.matchAll(/class="fitting-stats-item-name">([^<]+)</g)].map(m => m[1]);
  assert.equal(order[0], 'Snorkel');
  const byCount = [...stats.reportHtml(r, {sort:'completed'}).matchAll(/class="fitting-stats-item-name">([^<]+)</g)].map(m => m[1]);
  assert.equal(byCount[1], 'Cargo barrier');
});

test('fitter chosen: status names them; empty period says so', () => {
  const r = stats.normalizeReport(report([], {technician:{id:BEN, name:'Ben Palmer'}}));
  assert.equal(r.technician.name, 'Ben Palmer');
  assert.match(stats.reportHtml(r), /Nothing was completed in this period by Ben Palmer\./);
});

test('a refused or broken report is an error; bad fitter ids are dropped', () => {
  assert.throws(() => stats.normalizeReport({ok:false, code:'permission_denied'}), /Administrators only/);
  for (const bad of [null, {}, {ok:true}, {ok:true, models:'x'}]) assert.throws(() => stats.normalizeReport(bad));
  const r = stats.normalizeReport(report([hilux()], {technicians:[{id:'x', name:'Bad'}, {id:BEN, name:' '}, {id:BEN.toUpperCase(), name:'Ben Palmer', completed:3}]}));
  assert.deepEqual(r.technicians, [{id:BEN, name:'Ben Palmer', completed:3}]);
});

function fixture(role = 'administrator') {
  let ctx = {userId:'synthetic-admin', role, token:'t', url:'https://example.invalid', key:'k'};
  const pending = [], renders = [];
  const controller = stats.createController({context:() => ctx, request:(c, days, technician) => new Promise((resolve, reject) => pending.push({c, days, technician, resolve, reject})), render:s => renders.push(s)});
  return {controller, pending, renders, change:v => { ctx = {...ctx, ...v}; }};
}

test('controller: All time by default; fitter change reloads with that fitter; model/category kept or reset; late answers dropped', async () => {
  const viewer = fixture('controller');
  await viewer.controller.open();
  assert.equal(viewer.pending.length, 0);
  const f = fixture();
  const opening = f.controller.open();
  assert.equal(f.pending[0].days, 0); assert.equal(f.pending[0].technician, null);
  f.pending[0].resolve(report([hilux()])); await opening;
  f.controller.setModel('HILUX'); f.controller.setCategory('TINT');
  const picking = f.controller.setTechnician(BEN);
  assert.equal(f.pending[1].technician, BEN); assert.equal(f.pending[1].days, 0);
  f.pending[1].resolve(report([{model:'PRADO', categories:[{category:'FITTING', lines:[line()]}]}], {technician:{id:BEN, name:'Ben Palmer'}})); await picking;
  const s = f.controller.getState();
  assert.equal(s.technician, BEN); assert.equal(s.model, 'all'); assert.equal(s.category, 'all');
  const period = f.controller.setDays('30');
  assert.equal(f.pending[2].days, 30); assert.equal(f.pending[2].technician, BEN);
  const back = f.controller.setTechnician('');
  assert.equal(f.pending[3].technician, null);
  f.pending[2].resolve(report([hilux()], {technician:{id:BEN, name:'Ben Palmer'}})); await period; // stale (fitter changed since)
  assert.equal(f.controller.getState().report, null);
  f.pending[3].resolve(report([hilux()], {days:30})); await back;
  assert.equal(f.controller.getState().report.models[0].label, 'HiLux');
  f.controller.setTechnician('not-a-uuid'); assert.equal(f.controller.getState().technician, '');
  f.controller.setDays('12345'); assert.equal(f.pending.at(-1).days, 0);
  const h = fixture(); const q = h.controller.open();
  h.pending[0].reject(new Error('net')); await q;
  assert.match(h.controller.getState().error, /Could not load fitting statistics/);
});

test('page: new RPC with fitter, r489 fallback only on 404, lazy cache busts', () => {
  const js = read('pdc-fitting-stats.js');
  assert.equal(stats.VERSION, '2026.10.30.r880');
  assert.match(js, /post\(ctx, 'get_pdc_fitting_statistics_850', \{p_days:days, p_technician_id:technician\}\)/);
  assert.match(js, /if \(response\.status === 404 && !technician\) \{/);
  assert.match(js, /post\(ctx, 'get_pdc_fitting_statistics_489', \{p_days: LEGACY_PERIODS\.includes\(days\) \? days : 365\}\)/);
  const lazy = require('./pdc-lazy-admin-views.js').DEFINITIONS.find(view => view.name === 'PdcFittingStats');
  assert.equal(lazy.script, 'pdc-fitting-stats.js?r880=2026.10.30.r880');
  assert.equal(lazy.css, 'pdc-fitting-stats.css?r880=2026.10.30.r880');
  assert.match(read('index.html'), /<script src="pdc-lazy-admin-views\.js\?v=2026\.10\.26\.opt1&amp;r880=2026\.10\.30\.r880" defer><\/script>/);
  assert.match(read('pdc-fitting-stats.css'), /\.fitting-stats-model > summary/);
});

test('migration: one new read-only admin RPC, r489 untouched, staging guard, pin and check, LF only, matching undo', () => {
  const up = read('supabase/migrations/20261030120000_r850_fitting_statistics_by_model_fitter.sql');
  const down = read('supabase/rollbacks/20261030120000_r850_fitting_statistics_by_model_fitter.down.sql');
  for (const sql of [up, down]) { assert.equal(sql.includes('\r'), false); assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/); assert.match(sql, /NOT BETWEEN 2 AND 45/); assert.doesNotMatch(sql, /vjdtsswhroyguxyfjdkt/); }
  assert.match(up, /CREATE FUNCTION public\.get_pdc_fitting_statistics_850\(p_days integer, p_technician_id uuid DEFAULT NULL\)\n RETURNS jsonb\n LANGUAGE plpgsql\n STABLE SECURITY DEFINER\n SET search_path TO 'pg_catalog'/);
  assert.match(up, /REVOKE ALL ON FUNCTION public\.get_pdc_fitting_statistics_850\(integer,uuid\) FROM PUBLIC, anon, authenticated;\nGRANT EXECUTE ON FUNCTION public\.get_pdc_fitting_statistics_850\(integer,uuid\) TO authenticated;/);
  const body = up.match(/AS \$function\$([\s\S]*?)\$function\$;/)[1];
  const md5 = crypto.createHash('md5').update(body).digest('hex');
  assert.ok(up.includes("('public.get_pdc_fitting_statistics_850(integer,uuid)','" + md5 + "','r850'"), 'pin matches body');
  assert.ok(down.includes(md5), 'undo checks the same body');
  assert.match(body, /r\.role::text = 'administrator'\s+AND r\.active IS TRUE AND r\.account_status = 'approved'/);
  assert.match(body, /p_days NOT IN \(0, 7, 30, 90, 365\)/);
  assert.match(body, /WHEN m ~ '\(hilux\|toyhil\)' THEN 'HILUX'/);
  assert.match(body, /WHEN m ~ '\(isuzu\|d-\?max\|isudma\)' THEN 'DMAX'/);
  assert.doesNotMatch(body, /\b(INSERT|UPDATE|DELETE|TRUNCATE|PERFORM)\b/i);
  assert.doesNotMatch(body, /stock_number|customer|\bvin\b|registration/i);
  assert.doesNotMatch(up, /CREATE OR REPLACE|DROP FUNCTION|get_pdc_fitting_statistics_489\(integer\) (?:FROM|TO)/);
  assert.match(up, /IS DISTINCT FROM '306a3d7a5ecd306492dcfafe00c70005' THEN RAISE EXCEPTION 'r850: r489 report changed'/);
  const check = up.match(/\$chk\$([\s\S]*?)\$chk\$/)[1];
  assert.ok(up.includes("IS DISTINCT FROM '" + crypto.createHash('md5').update(check).digest('hex') + "' THEN RAISE EXCEPTION 'r850: check did not land"), 'check md5');
  assert.match(up, /'fitting_statistics_850','F400'/);
  assert.match(up, /,true,520,'r850'\);/);
  assert.match(down, /DROP FUNCTION public\.get_pdc_fitting_statistics_850\(integer,uuid\);/);
  assert.doesNotMatch(down, /get_pdc_fitting_statistics_489\(integer\);/);
});

test('FAULT_LOG F400', () => {
  assert.match(read('docs/FAULT_LOG.md'), /^\| F400 \| 30 Oct 2026/m);
});
