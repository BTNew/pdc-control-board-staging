'use strict';
// r452 (F65): the clock tick re-saves the jobs chained behind start-of-shift overdue jobs (real moves, never a no-op). Each re-save
// fired the QC line cache trigger, so every later capacity check in the same tick rebuilt that vehicle's QC lines (~25 ms each,
// ~770 of ~1050 ms). The tick now puts the same cached set back after a re-save that changed only clock fields.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const crypto = require('node:crypto');
const V = '20261021230113_r452_clock_tick_qc_cache_keep';
const forward = fs.readFileSync(`supabase/migrations/${V}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${V}.down.sql`, 'utf8');
const rb = fs.readFileSync('tests/clock_tick_speed_452_rollback.sql', 'utf8');
const OLD = '84af7607bfd0ce9907c89bae8644d5b6';
const NEW = '0aaaa15690ca286ed0db87fc72271d5a';
const md5 = s => crypto.createHash('md5').update(s).digest('hex');
function body(sql) {
  const at = sql.indexOf('CREATE OR REPLACE FUNCTION public.workshop_clock_tick(');
  assert.ok(at >= 0);
  const open = sql.indexOf('AS $function$', at) + 'AS $function$'.length;
  return sql.slice(open, sql.indexOf('$function$;', open)).replace(/\r/g, '');
}
const KEYS = "ARRAY['scheduled_start_at','scheduled_end_at','version','updated_at','updated_by','eta_at_booking','eta_risk_status','eta_risk_detected_at','bus_calendar_version','default_duration_minutes','capacity_base_minutes','capacity_estimate_minutes','capacity_efficiency_percent']";

test('forward installs the reviewed tick and the undo restores #368 byte for byte', () => {
  assert.equal(md5(body(forward)), NEW);
  assert.equal(md5(body(down)), OLD);
  for (const sql of [forward, down]) {
    assert.ok(sql.includes(OLD) && sql.includes(NEW));
    assert.match(sql, /pdc_monitor_staging_guard/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/);
    assert.match(sql, /SET LOCAL lock_timeout = '2s';/);
    assert.equal(sql.includes('vjdtsswhroyguxyfjdkt'), false);
    assert.equal(/cron\.(schedule|unschedule|alter_job)|UPDATE cron\.|UPDATE public\.workshop_bookings SET[^;]*WHERE true/i.test(sql), false, 'no cron or bulk booking writes');
    assert.equal((sql.match(/CREATE OR REPLACE FUNCTION/g) || []).length, 1, 'only the tick');
    assert.match(sql, /SET lock_timeout TO '3s'\n SET statement_timeout TO '120s'/);
  }
  assert.match(down, /updated_at='2026-10-20T10:55:01\.195622\+00:00'::timestamptz/);
  assert.match(down, /release='#368',note='clock tick - do not interfere'/);
});

test('the only behaviour change is the QC cache keep; every move, guard and write is the old one', () => {
  const o = body(down), n = body(forward);
  // Remove the r452 additions and the lint-only WHERE true: what is left is the old body.
  let stripped = n
    .replace(/ qc_lines jsonb; qc_computed_at timestamptz; qc_gen bigint; qc_global_gen bigint;\n/, '')
    .replace(/     -- r452 \(F65\): a re-time changes no[\s\S]*?WHERE e\.vehicle_id='00000000-0000-0000-0000-000000000000'::uuid;\n/, '')
    .replace(/     -- r452 \(F65\): QC lines read[\s\S]*?ON CONFLICT \(vehicle_id\) DO NOTHING;\n     END IF;\n/, '')
    .replace(/\n     WHERE true;/g, ';');
  assert.equal(stripped, o);
  assert.ok(n.includes(`after_row-${KEYS}\n       IS NOT DISTINCT FROM item.before_row-${KEYS} THEN`));
  assert.match(n, /FOR SHARE OF e SKIP LOCKED\)=qc_gen\+1/);
  assert.match(n, /FOR SHARE OF e SKIP LOCKED\)=qc_global_gen/);
  assert.equal((n.match(/INSERT INTO pdc_work_categories_private\.qc_operation_lines_cache\(/g) || []).length, 1);
  assert.equal(/DELETE FROM|UPDATE pdc_work_categories_private/.test(n), false, 'never deletes or edits cache rows');
});

test('pin moves (count unchanged), new check F65 sort 251, latency trend kept', () => {
  assert.match(forward, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5='0aaaa15690ca286ed0db87fc72271d5a',release='r452'/);
  assert.match(forward, /'clock_tick_resaves_per_tick','F65'/);
  assert.match(forward, /,true,251,'r452'\);/);
  assert.match(forward, /check_name='clock_tick_latency_trend' AND enabled/);
  assert.equal(/DELETE FROM pdc_ops\.regression_checks/.test(forward), false);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='clock_tick_resaves_per_tick' AND added_in='r452';/);
  assert.match(forward, /current_setting\('pdc\.r452_pins'\)::bigint/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F65 \| 22 Oct 06:37 \|/m);
  assert.equal(fs.existsSync(`supabase/migrations/${V}.down.sql`), false);
});

test('rolled-back test compares old and new on the same state and holds no IDs', () => {
  assert.match(rb, /r452_runs\('old'\)/);
  assert.match(rb, /r452_runs\('new'\)/);
  assert.match(rb, /'result_same',o->'result'=n->'result','snap_same',o->'snap'=n->'snap'/);
  assert.match(rb, /RAISE EXCEPTION 'R452_RB_RESULT %'/);
  assert.match(rb, /ROLLBACK;\s*$/);
  assert.equal(/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i.test(rb), false, 'no record ids');
});
