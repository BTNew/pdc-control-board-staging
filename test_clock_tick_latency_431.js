/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r431 (F49): the workshop clock tick re-saved every job chained behind an overdue, not-started job every
// minute. workshop_clock_plan now moves such a job to the next 30-minute mark (clock_overdue_step_minutes),
// and workshop_clock_next_minute jumps calendar edges instead of walking minutes. The tick itself is untouched.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const forward = fs.readFileSync('supabase/migrations/20261021053203_r431_clock_tick_latency.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261021053203_r431_clock_tick_latency.down.sql', 'utf8');
const TICK = '84af7607bfd0ce9907c89bae8644d5b6';
const OLD = { nm: '6849b6c6eb2360f04a7f66a3828a351a', plan: '6846b2ae63456d905f66dad6868fb636' };
const NEW = { nm: '32c9642c7f1d89e9a981fa554b2a2122', plan: '58384098be842b62c87b0fa374a15bb6' };
const crypto = require('node:crypto');
const md5 = s => crypto.createHash('md5').update(s).digest('hex');
function body(sql, name) {
  const at = sql.indexOf('CREATE OR REPLACE FUNCTION public.' + name + '(');
  assert.ok(at >= 0, name);
  const open = sql.indexOf('AS $function$', at) + 'AS $function$'.length;
  const close = sql.indexOf('$function$;', open);
  return sql.slice(open, close).replace(/\r/g, '');
}

test('forward installs the reviewed bodies and the undo restores the old ones byte for byte', () => {
  assert.equal(md5(body(forward, 'workshop_clock_next_minute')), NEW.nm);
  assert.equal(md5(body(forward, 'workshop_clock_plan')), NEW.plan);
  assert.equal(md5(body(down, 'workshop_clock_next_minute')), OLD.nm);
  assert.equal(md5(body(down, 'workshop_clock_plan')), OLD.plan);
  for (const sql of [forward, down]) {
    for (const m of [TICK, OLD.nm, OLD.plan, NEW.nm, NEW.plan]) assert.ok(sql.includes(m), m);
    assert.match(sql, /pdc_monitor_staging_guard/);
    assert.match(sql, /NOT BETWEEN 2 AND 45/);
    assert.equal(sql.includes('vjdtsswhroyguxyfjdkt'), false);
    assert.equal(/CREATE OR REPLACE FUNCTION public\.workshop_clock_tick/.test(sql), false, 'tick never replaced');
    assert.equal(/cron\.(schedule|unschedule|alter_job)|UPDATE cron\.|workshop_bookings SET/i.test(sql), false, 'no cron or booking writes');
  }
});

test('overdue step: 30 minutes by default, 1..60 from the setting, only for jobs already overdue', () => {
  const plan = body(forward, 'workshop_clock_plan');
  assert.match(plan, /key='clock_overdue_step_minutes'\),30\)/);
  assert.match(plan, /BETWEEN 1 AND 60/);
  assert.match(plan, /IF orig<floor_at AND step_minutes>1 THEN/);
  assert.match(plan, /ELSE step_floor:=floor_at; END IF;/);
  assert.ok(plan.includes('step_floor,coalesce(cursor_at,orig)'));
});

test('next open minute keeps the 90-day guard and asks the calendar for every answer', () => {
  const nm = body(forward, 'workshop_clock_next_minute');
  assert.match(nm, /No workshop opening within 90 days/);
  assert.match(nm, /IF public\.workshop_calendar_minute_available\(t\) THEN RETURN t; END IF;/);
  assert.match(nm, /IF edges IS NULL THEN t:=t\+interval '1 minute'; CONTINUE; END IF;/);
});

test('regression check, pins and fault id', () => {
  assert.match(forward, /'clock_tick_latency_trend','F49'/);
  assert.match(forward, /,true,240,'r431'\)/);
  assert.match(forward, /INSERT INTO pdc_ops\.expected_function_md5/);
  assert.match(down, /DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r431'/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='clock_tick_latency_trend' AND added_in='r431'/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /^\| F49 \| 21 Oct 12:31 \|/m);
  assert.equal(fs.existsSync('supabase/migrations/20261021053203_r431_clock_tick_latency.down.sql'), false);
});

test('clock rollback tests expect the 30-minute step, and the old-plan parity test pins step 1', () => {
  const bus = fs.readFileSync('tests/workshop_bus_clock_regression_rollback.sql', 'utf8');
  assert.match(bus, /time '09:01:15'\);expected_start:=pg_temp\.bc_at\(day\+step\*7,time '09:30'\)/);
  assert.match(bus, /time '09:30'\) AND version=2 FROM public\.workshop_bookings WHERE id=free/);
  assert.match(fs.readFileSync('tests/clock_plan_calendar_reuse_rollback.sql', 'utf8'), /VALUES\('clock_overdue_step_minutes','1'::jsonb\)/);
});
