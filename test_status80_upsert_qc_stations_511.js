/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r511 (F124): Status 80 UPSERTs missing station work_items from open QC lines. Status 99 is not added.
const test = require('node:test');
const assert = require('node:assert');
const crypto = require('node:crypto');
const fs = require('fs');

const ID = '20261023131000_r511_status80_upsert_qc_stations';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const OLD = '5162460f98589c34aa976b5ed36fdbd2';
const NEW = '9808feb2a0a93a79b0d67aebdca0a4aa';

function applyBody(sql) {
  const start = sql.indexOf('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.apply_service_pmb_complete');
  const fn = sql.indexOf('AS $fn$', start);
  const end = sql.indexOf('$fn$;', fn + 6);
  assert.ok(start >= 0 && fn > start && end > fn, 'apply function body markers');
  return sql.slice(fn + 'AS $fn$'.length, end);
}

test('migration: staging only, pins the r504 apply body, never names production', () => {
  assert.match(up, /pdc_monitor_staging_guard\(\)/);
  assert.match(up, /cdsmnqxtyyoeoznmbidd/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'));
  assert.ok(up.includes(`'${OLD}'`), 'base apply md5');
  assert.equal(crypto.createHash('md5').update(applyBody(up)).digest('hex'), NEW);
  assert.equal(crypto.createHash('md5').update(applyBody(down)).digest('hex'), OLD);
  assert.ok(up.includes(NEW) && down.includes(NEW));
});

test('migration: Status 80 UPSERTs completed station rows from open QC lines and keeps r504 completes', () => {
  const apply = applyBody(up);
  assert.match(apply, /INSERT INTO public\.vehicle_work_items/);
  assert.match(apply, /ON CONFLICT\(vehicle_id,work_key\) DO UPDATE/);
  assert.match(apply, /WHERE NOT vehicle_work_items\.completed/);
  assert.match(apply, /pdc_qc_operation_lines_379/);
  assert.match(apply, /BUS_MECHANICAL','BUS_ACCESSORIES','BUS_ELECTRICAL','BUS_QA','BUS_PIT','BUS_4X4/);
  assert.match(apply, /lower\(work_key\) IN\('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','parts','sublet'\)/);
  assert.match(apply, /UPDATE public\.workshop_bookings wb SET status='completed'/);
  assert.match(apply, /'started','stoppage'/);
  assert.ok(!apply.includes('pdc_qc_operation_completions_379'), 'does not write QC checklist completions');
  assert.equal(apply.split("sub_status='99'").length - 1, 1, 'sub_status 99 stays the existing skip only');
  assert.match(apply, /sub_status='80'/);
  assert.match(up, /'status80_upserts_qc_station_work_items'/);
  assert.match(up, /'F124'/);
  assert.match(apply, /-- r510 \(F123\): UPSERT/, 'live function comment stays; renumbering it would change md5 9808feb2');
});

test('backfill: QC vehicles with open stations and no completed work_item; not reversed', () => {
  assert.match(up, /DO \$bf\$/);
  assert.match(up, /upper\(btrim\(coalesce\(v\.current_location,''\)\)\)='QC'/);
  assert.match(up, /v\.qc_completed_at IS NULL/);
  assert.match(up, /r511 backfill/);
  assert.match(up, /13101428/);
  assert.ok(!up.includes('pdc_qc_operation_completions_379') || up.indexOf('pdc_qc_operation_completions_379') < up.indexOf('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.apply_service_pmb_complete'), 'completions named only outside the new function');
  assert.match(down, /Does NOT reverse the one-shot QC backfill/i);
  assert.match(down, /5162460f98589c34aa976b5ed36fdbd2/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='status80_upserts_qc_station_work_items'/);
});

test('FAULT_LOG has F124 and the release stays SQL only', () => {
  assert.match(log, /^\| F124 \| /m);
  assert.ok(log.indexOf('| F123 |') < log.indexOf('| F124 |'));
  assert.match(log, /r511_status80_upsert_qc_stations/);
  assert.match(log, /status80_upserts_qc_station_work_items/);
  assert.match(up, /Does not change app\.js or pdc-qc-rework\.js/);
  assert.match(up, /Status 99 is not a new apply path|does not add a sub_status 99 path|Does not handle sub_status 99/);
});

test('no locked frontend files and no data writes outside the function and backfill', () => {
  let top = up.replace(/\$fn\$[\s\S]*?\$fn\$/g, '')
    .replace(/\$bf\$[\s\S]*?\$bf\$/g, '')
    .replace(/\$c\d+\$[\s\S]*?\$c\d+\$/g, '')
    .replace(/\$g\$[\s\S]*?\$g\$/g, '')
    .replace(/\$p\$[\s\S]*?\$p\$/g, '');
  assert.doesNotMatch(top, /^\s*(UPDATE|DELETE FROM|INSERT INTO)\s+public\.(vehicles|vehicle_work_items|workshop_bookings|pdc_qc_operation_completions_379)\b/im);
});
