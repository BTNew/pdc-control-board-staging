/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const fitters = fs.readFileSync('pdc-fitters.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261028091500_r594_resume_bay_cascade.sql', 'utf8');

function extract(src, name) {
  const start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let i = src.indexOf('{', start), depth = 0;
  for (; i < src.length; i += 1) {
    if (src[i] === '{') depth += 1;
    if (src[i] === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(name);
}

test('resume failure is a sentence and not an overlap code', () => {
  const ctx = {
    workshopAdministratorCanMove: () => true,
    workshopAdministratorErrorDetail: result => `Server code: ${result.error}.`,
  };
  vm.createContext(ctx);
  vm.runInContext(`${extract(planner, 'workshopDescribeSharedActionError')}\nthis.describe = workshopDescribeSharedActionError;`, ctx);
  const named = ctx.describe({ ok: false, error: 'resume_cascade_blocked', message: 'Key 359 is still in Ben Palmer, so this resume was not saved. Nothing was moved.' });
  assert.equal(named, 'Key 359 is still in Ben Palmer, so this resume was not saved. Nothing was moved.');
  assert.equal(named.includes('bay_overlap'), false);
  assert.equal(named.includes('resume_cascade_blocked'), false);
  const fallback = ctx.describe({ ok: false, error: 'resume_cascade_blocked', message: 'bay_overlap' });
  assert.equal(fallback, 'This resume was not saved. Nothing was moved.');
  assert.equal(fallback.includes('bay_overlap'), false);
});

test('the fitter screen uses the server sentence for a blocked resume', () => {
  assert.match(fitters, /resume_cascade_blocked/);
  assert.match(fitters, /This resume was not saved\. Nothing was moved\./);
  assert.match(fitters, /body\?\.message/);
});

test('resume SQL pushes the bay and does not return an overlap code', () => {
  const start = sql.indexOf('FUNCTION public.resume_workshop_work_pre345');
  const body = sql.slice(start, sql.indexOf('$resume594$;', start));
  assert.match(body, /pdc_ops\.push_later_planned_in_bay_594/);
  assert.equal(body.includes("'bay_overlap'"), false);
  assert.equal(body.includes("'technician_overlap'"), false);
  assert.equal(body.includes("'vehicle_overlap'"), false);
  assert.match(sql, /workshop_admin_next_operational_minute/);
  assert.match(sql, /cascade_move_shifted/);
  assert.match(sql, /affected_overlap_chain/);
  assert.match(sql, /sort_order = 364/);
  assert.match(sql, /'F208'/);
  assert.match(sql, /resume_cascade_594/);
});
