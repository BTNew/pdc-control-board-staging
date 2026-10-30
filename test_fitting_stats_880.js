/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r880 (F420): Fitting statistics Times list with Remove / Restore per job. Synthetic data only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const stats = require('./pdc-fitting-stats.js');
const read = file => fs.readFileSync(path.join(__dirname, file), 'utf8');
const md5 = text => crypto.createHash('md5').update(text).digest('hex');

const B1 = 'aaaaaaaa-1111-4222-8333-444444444444', B2 = 'bbbbbbbb-1111-4222-8333-444444444444';
const line = extra => ({line_type:'Steel Bull Bar - Commercial', type_key:'steel bull bar - commercial', completed:4, timed:3, excluded:0, avg_minutes:120, median_minutes:110, min_minutes:90, max_minutes:150, avg_allowance_minutes:150, ...extra});
const report = lines => ({ok:true, days:0, generated_at:'2026-10-30T05:00:00Z', since:null, technicians:[], models:[{model:'HILUX', categories:[{category:'FITTING', jobs_completed:1, lines}]}]});
const entries = (extra = []) => ({ok:true, entries:[
  {booking_id:B1, line_identity:'L1', done_at:'2026-10-29T03:00:00Z', fitter:'Ben Palmer', stock_number:'13047122', key_number:'322', minutes:1, allowance_minutes:150, excluded:false},
  {booking_id:B2, line_identity:'L2', done_at:'2026-10-28T03:00:00Z', fitter:'Jamie Bello', stock_number:'13047225', key_number:null, minutes:130, allowance_minutes:150, excluded:false},
  ...extra]});

test('entries: bad rows dropped; a 1 minute bull bar is marked check; removed rows say removed and offer Restore', () => {
  const rows = stats.normalizeEntries(entries([{booking_id:'nope', line_identity:'x'}, {booking_id:B2, line_identity:'L3', minutes:95, excluded:true}]));
  assert.equal(rows.length, 3);
  assert.equal(rows[0].id, B1 + '|L1');
  assert.throws(() => stats.normalizeEntries({ok:false, code:'permission_denied'}), /Administrators only/);
  const key = stats.entriesKey('HILUX', 'FITTING', 'steel bull bar - commercial');
  const r = stats.normalizeReport(report([line({excluded:1})]));
  const html = stats.reportHtml(r, {entries:{[key]:{rows, loading:false, busy:'', error:''}}});
  assert.match(html, /data-fitting-stats-times="HILUX\|FITTING\|steel bull bar - commercial" aria-expanded="true">Hide times</);
  assert.match(html, /<tr class="is-suspect">.*?Ben Palmer.*?13047122 · Key 322.*?1m <span class="fitting-stats-vs is-over">check<\/span>.*?data-excluded="true"[^>]*>Remove</s);
  assert.match(html, /<tr class="">.*?Jamie Bello.*?2h 10m.*?>Remove</s);
  assert.match(html, /<tr class="is-removed">.*?1h 35m <span class="fitting-stats-vs is-even">removed<\/span>.*?data-excluded="false"[^>]*>Restore</s);
  assert.match(html, /<small> · 1 removed<\/small>/);
  assert.match(html, /still counts as done and nothing on the job changes/);
});

test('removed times are not "without Start"; Times button only where there is a time and a line type', () => {
  const r = stats.normalizeReport(report([line({completed:4, timed:2, excluded:1}), line({line_type:'Cargo Barrier', type_key:'cargo barrier', completed:2, timed:0, excluded:0, avg_minutes:null}), line({line_type:'Snorkel', type_key:'', completed:1, timed:1})]));
  const bull = r.models[0].categories[0].lines.find(l => l.type_key === 'steel bull bar - commercial');
  assert.equal(bull.untimed, 1);
  const html = stats.reportHtml(r);
  assert.match(html, /<small> · 1 without Start<\/small><small> · 1 removed<\/small>/);
  assert.match(html, /data-fitting-stats-times="HILUX\|FITTING\|steel bull bar - commercial" aria-expanded="false">Times</);
  assert.doesNotMatch(html, /data-fitting-stats-times="HILUX\|FITTING\|cargo barrier"/);
  assert.equal((html.match(/data-fitting-stats-times=/g) || []).length, 1);
  // The r489 fallback (no models) never shows Times.
  const legacy = stats.normalizeReport({ok:true, days:30, categories:[{category:'FITTING', lines:[line()]}]});
  assert.doesNotMatch(stats.reportHtml(legacy), /data-fitting-stats-times/);
});

function fixture() {
  const ctx = {userId:'synthetic-admin', role:'administrator', token:'t', url:'https://example.invalid', key:'k'};
  const calls = {report:[], entries:[], exclude:[]};
  const controller = stats.createController({context:() => ctx,
    request:(c, days, tech) => new Promise(resolve => calls.report.push({days, tech, resolve})),
    entries:(c, days, tech, model, category, typeKey) => new Promise((resolve, reject) => calls.entries.push({days, tech, model, category, typeKey, resolve, reject})),
    exclude:(c, bookingId, lineIdentity, excluded) => new Promise(resolve => calls.exclude.push({bookingId, lineIdentity, excluded, resolve})),
    render:() => {}});
  return {controller, calls};
}
const tick = () => new Promise(r => setImmediate(r));

test('controller: Times loads the list for that model / category / line; Remove saves, reloads the list and the figures', async () => {
  const {controller, calls} = fixture();
  const open = controller.open(); calls.report[0].resolve(report([line()])); await open;
  const key = stats.entriesKey('HILUX', 'FITTING', 'steel bull bar - commercial');
  const loading = controller.toggleEntries(key);
  assert.deepEqual({m:calls.entries[0].model, c:calls.entries[0].category, t:calls.entries[0].typeKey, d:calls.entries[0].days}, {m:'HILUX', c:'FITTING', t:'steel bull bar - commercial', d:0});
  calls.entries[0].resolve(entries()); await loading;
  assert.equal(controller.getState().entries[key].rows.length, 2);
  const saving = controller.setExcluded(key, B1 + '|L1', true);
  assert.equal(controller.getState().entries[key].busy, B1 + '|L1');
  assert.deepEqual({b:calls.exclude[0].bookingId, l:calls.exclude[0].lineIdentity, e:calls.exclude[0].excluded}, {b:B1, l:'L1', e:true});
  calls.exclude[0].resolve({ok:true, excluded:true}); await tick();
  assert.equal(calls.entries.length, 2);
  assert.equal(controller.getState().entries[key].rows.length, 2, 'old rows stay on screen while reloading');
  calls.entries[1].resolve(entries().entries && {ok:true, entries:entries().entries.map((e, i) => i === 0 ? {...e, excluded:true} : e)}); await tick();
  assert.equal(calls.report.length, 2, 'figures reload after a remove');
  calls.report[1].resolve(report([line({timed:2, excluded:1})])); await saving;
  const s = controller.getState();
  assert.equal(s.entries[key].rows[0].excluded, true);
  assert.equal(s.report.models[0].categories[0].lines[0].excluded, 1);
  // A refused save shows an error and changes nothing.
  const refused = controller.setExcluded(key, B2 + '|L2', true);
  calls.exclude[1].resolve({ok:false, code:'permission_denied'}); await refused;
  assert.equal(controller.getState().entries[key].error, 'Administrators only.');
  assert.equal(calls.entries.length, 2);
  // Hide times, and a period change clears open lists.
  controller.toggleEntries(key); assert.equal(controller.getState().entries[key], undefined);
  const again = controller.toggleEntries(key); calls.entries[2].resolve(entries()); await again;
  controller.setDays('30'); assert.deepEqual(controller.getState().entries, {});
});

test('controller: missing database update says so; unknown entry or legacy report does nothing', async () => {
  const {controller, calls} = fixture();
  const open = controller.open(); calls.report[0].resolve(report([line()])); await open;
  const key = stats.entriesKey('HILUX', 'FITTING', 'steel bull bar - commercial');
  const loading = controller.toggleEntries(key);
  const e = new Error('nd'); e.code = 'not_deployed'; calls.entries[0].reject(e); await loading;
  assert.equal(controller.getState().entries[key].error, 'Times need the database update.');
  await controller.setExcluded(key, 'nope', true);
  assert.equal(calls.exclude.length, 0);
  const g = fixture(); const o = g.controller.open(); g.calls.report[0].resolve({ok:true, days:30, categories:[{category:'FITTING', lines:[line()]}]}); await o;
  await g.controller.toggleEntries('ALL|FITTING|x'); assert.equal(g.calls.entries.length, 0);
});

test('page: calls the r880 RPCs, keeps drop-downs open across re-renders, cache busts', () => {
  const js = read('pdc-fitting-stats.js');
  assert.equal(stats.VERSION, '2026.10.30.r880');
  assert.match(js, /post\(ctx, 'get_pdc_fitting_line_entries_880', \{p_days:days, p_technician_id:technician, p_model:model, p_category:category, p_type_key:typeKey\}\)/);
  assert.match(js, /post\(ctx, 'set_pdc_fitting_time_excluded_880', \{p_booking_id:bookingId, p_line_identity:lineIdentity, p_excluded:excluded\}\)/);
  assert.match(js, /const openState = new Map\(\[\.\.\.host\.querySelectorAll\('details\[data-fitting-stats-open\]'\)\]/);
  assert.match(js, /host\.__fittingStatsClicks = true;/);
  const lazy = require('./pdc-lazy-admin-views.js').DEFINITIONS.find(view => view.name === 'PdcFittingStats');
  assert.equal(lazy.script, 'pdc-fitting-stats.js?r880=2026.10.30.r880');
  assert.match(read('pdc-fitting-stats.css'), /\.fitting-stats-entries tr\.is-removed td/);
});

test('migration: removed-times table private with RLS; 4 new functions + stats re-pinned; r489 untouched; undo restores the r850 body', () => {
  const up = read('supabase/migrations/20261030130000_r880_fitting_stats_remove_times.sql');
  const down = read('supabase/rollbacks/20261030130000_r880_fitting_stats_remove_times.down.sql');
  for (const sql of [up, down]) { assert.equal(sql.includes('\r'), false); assert.match(sql, /project_ref='cdsmnqxtyyoeoznmbidd'/); assert.match(sql, /NOT BETWEEN 2 AND 45/); }
  assert.match(up, /CREATE TABLE pdc_fitter_private\.fitting_stats_excluded_880 \(/);
  assert.match(up, /ALTER TABLE pdc_fitter_private\.fitting_stats_excluded_880 ENABLE ROW LEVEL SECURITY;\nREVOKE ALL ON TABLE pdc_fitter_private\.fitting_stats_excluded_880 FROM PUBLIC, anon, authenticated;/);
  const bodies = [...up.matchAll(/CREATE (?:OR REPLACE )?FUNCTION (\S+?)\(([\s\S]*?)\$function\$([\s\S]*?)\$function\$;/g)].map(m => ({name:m[1], body:m[3]}));
  assert.deepEqual(bodies.map(b => b.name), ['pdc_fitter_private.fitting_model_family_880', 'pdc_fitter_private.fitting_lines_880', 'public.get_pdc_fitting_statistics_850', 'public.get_pdc_fitting_line_entries_880', 'public.set_pdc_fitting_time_excluded_880']);
  for (const b of bodies) assert.ok(up.includes("'" + md5(b.body) + "'"), b.name + ' pinned with its md5');
  const stats850 = bodies[2].body, entriesFn = bodies[3].body, setFn = bodies[4].body, linesFn = bodies[1].body;
  assert.ok(up.includes("UPDATE pdc_ops.expected_function_md5 SET prosrc_md5='" + md5(stats850) + "', release='r880'"));
  for (const b of [stats850, entriesFn, setFn]) assert.match(b, /r\.role::text = 'administrator'\s+AND r\.active IS TRUE AND r\.account_status = 'approved'/);
  assert.match(linesFn, /CASE WHEN d\.excluded THEN NULL ELSE d\.actual_seconds \/ 60\.0 END AS actual_minutes/);
  assert.doesNotMatch(entriesFn + stats850 + linesFn, /\b(INSERT|UPDATE|DELETE|TRUNCATE)\b/);
  // The only write is to the removed-times list; the job's own tick and times are never touched.
  assert.doesNotMatch(setFn, /operation_progress\s+SET|operation_timing|UPDATE /i);
  assert.match(setFn, /INSERT INTO pdc_fitter_private\.fitting_stats_excluded_880/);
  assert.match(setFn, /DELETE FROM pdc_fitter_private\.fitting_stats_excluded_880 x WHERE x\.booking_id = p_booking_id AND x\.line_identity = p_line_identity;/);
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_fitter_private\.fitting_lines_880\(timestamp with time zone,uuid\) FROM PUBLIC, anon, authenticated;/);
  const check = up.match(/\$chk\$([\s\S]*?)\$chk\$/)[1];
  assert.match(check, /count\(\*\)=5 AND bool_and/);
  assert.ok(up.includes("IS DISTINCT FROM '" + md5(check) + "' THEN RAISE EXCEPTION 'r880: check did not land"));
  assert.match(up, /'fitting_stats_remove_times_880','F420'/);
  assert.match(up, /,true,540,'r880'\);/);
  assert.doesNotMatch(up, /get_pdc_fitting_statistics_489\(integer\) (?:FROM|TO)|CREATE OR REPLACE FUNCTION public\.get_pdc_fitting_statistics_489/);
  // Undo puts back the exact r850 body (pinned 170ecb56...) and drops everything r880 added.
  const r850 = read('supabase/migrations/20261030120000_r850_fitting_statistics_by_model_fitter.sql').match(/AS \$function\$([\s\S]*?)\$function\$;/)[1];
  const restored = down.match(/AS \$function\$([\s\S]*?)\$function\$;/)[1];
  assert.equal(md5(restored), md5(r850));
  assert.equal(md5(r850), '170ecb5674f39d78f3fd9135cb75aae5');
  assert.match(down, /DROP TABLE pdc_fitter_private\.fitting_stats_excluded_880;/);
});

test('FAULT_LOG F420', () => {
  assert.match(read('docs/FAULT_LOG.md'), /^\| F420 \| 30 Oct 2026/m);
});
