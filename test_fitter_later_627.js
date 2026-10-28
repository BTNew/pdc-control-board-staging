'use strict';
// r627 (F242): fitter Later. Item stays outstanding for the station; only this booking can complete without it.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const js = fs.readFileSync('pdc-fitters.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261028210000_r627_fitter_later.sql', 'utf8');

test('tablet: Start, Done and Later on one row; Later form and set chip; wired to set_line_later_627', () => {
  const start = js.indexOf('const LATER_REASONS'); const end = js.indexOf('  function fitterLineCardHtml(');
  const ctx = { esc: v => String(v ?? '') }; vm.runInNewContext(js.slice(start, end) + ';this.f=fitterLaterHtml;', ctx);
  const form = ctx.f({ line_identity: 'source:x' }, { editable: true, disabled: false });
  assert.match(form, /<summary>Later<\/summary>/); assert.match(form, /data-fitter-later-save="source:x"/);
  assert.match(form, /Waiting on parts[\s\S]*Out of time[\s\S]*Needs another trade[\s\S]*Other/);
  const set = ctx.f({ line_identity: 'source:x', later: { reason: 'parts', note: 'tank' } }, { editable: true });
  assert.match(set, /Later · Waiting on parts · tank/); assert.match(set, /data-fitter-later-undo="source:x"/);
  assert.equal(ctx.f({ line_identity: 'a', completed: true }, { editable: true }), '');
  assert.equal(ctx.f({ line_identity: 'a' }, { editable: false }), '');
  assert.match(js, /setLater:body => \{ invalidateReads\(\); return rpc\('set_line_later_627', body, true\); \}/);
  assert.match(js, /<b class="fitter-done-cap" aria-hidden="true">Done<\/b><\/label>/);
  assert.match(js, /\.fitter-todo-list \.fitter-line>\.fitter-line-check\{display:contents\}/);
  assert.match(js, /\.fitter-todo-list \.fitter-item-ticks\{order:2\}'[\s\S]*fitter-line-check>input\{order:3/);
  assert.match(fs.readFileSync('index.html', 'utf8'), /pdc-fitters\.js\?[^"]*&amp;r627=2026\.10\.28\.r627"/);
});

test('server: never ticks or completes, per booking, fitter on own booking only, gate allows it, Dept 135 untouched', () => {
  const setFn = sql.slice(sql.indexOf('CREATE FUNCTION public.set_line_later_627'), sql.indexOf('REVOKE ALL ON FUNCTION public.set_line_later_627'));
  assert.doesNotMatch(setFn, /pdc_panel_line_completion|complete_workshop_work|operation_progress|UPDATE public\.vehicles/);
  assert.match(setFn, /pdc_fitter_private\.assigned\(p_booking_id, v_uid\)/);
  assert.match(sql, /PRIMARY KEY \(booking_id, line_identity\)/);
  assert.match(sql, /SELECT \* INTO later FROM pdc_work_categories_private\.line_later_627\(b\.id, code, lines, progress\);/);
  assert.match(sql, /'rpc\/list_line_handoffs_583','rpc\/set_line_later_627'\)/);
  assert.match(sql, /\(v_total = 0 AND v_unknown = 0 AND \(v_later > 0 OR/);
  assert.match(sql, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(sql, /11c9967c8fe76e4ba8fe0bd88f20ed1f/, 'gate replaced only from the exact text it was written against');
  assert.doesNotMatch(sql.split('$chk627$')[1], /expected_function_md5/);
  assert.ok(fs.existsSync('supabase/rollbacks/20261028210000_r627_fitter_later.down.sql'));
});

test('complete & leave items for later; station stays on the list to book', () => {
  assert.match(js, /data-fitter-complete-later/);
  assert.match(js, /Complete &amp; leave \$\{left\} item/);
  assert.match(js, /p_reason:'time', p_note:'Not finished this booking'/);
  assert.match(js, /if \(detail\?\.progress\?\.can_complete\) await act\('complete'\);/);
  assert.match(sql, /CREATE TRIGGER keep_station_open_627 BEFORE INSERT OR UPDATE OF completed ON public\.vehicle_work_items/);
  assert.match(sql, /keep_station_open_627\(\) RETURNS trigger SECURITY DEFINER/);
  assert.match(sql, /NEW\.completed := false; NEW\.completed_by := NULL; NEW\.completed_at := NULL;/);
});
