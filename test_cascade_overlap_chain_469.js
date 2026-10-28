/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r469 (F82): staging-only database release + planner message. Behaviour is proven by tests/r469_local_harness/run.sh
// (throwaway local PostgreSQL: the pre-r469 cascade refuses a free-time drop with vehicle_overlap, the r469 cascade books it
// and moves only the overlapping chain, the undo restores bbdc1ae1), by tests/cascade_overlap_chain_469.sql (staging,
// real drag path, rolled back) and daily by cascade_insert_overlap_chain_469 (sort 268) in pdc_ops.fault_regression_check().
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),crypto=require('node:crypto');
const MIG='supabase/migrations/20261022020500_r469_cascade_overlap_chain.sql';
const DOWN='supabase/rollbacks/20261022020500_r469_cascade_overlap_chain.down.sql';
const mig=fs.readFileSync(MIG,'utf8'),down=fs.readFileSync(DOWN,'utf8');
const md5=s=>crypto.createHash('md5').update(s,'utf8').digest('hex');
const PRE='public.cascade_workshop_schedule_pre_087(text,uuid,integer,text,integer,timestamp with time zone,integer,uuid,integer,text,jsonb)';
const pins={[PRE]:'5f76d7e74c9ced8e948beebdee02a250',
 'pdc_cascade_private.target_end_469(uuid,uuid,timestamp with time zone,integer)':'b7b98893bfc7a04b39330ca689f8f1b1',
 'pdc_cascade_private.overlap_chain_469(uuid[],timestamp with time zone)':'e3602ba6f9d5973deea4eef09f5077c0',
 'pdc_cascade_private.validation_rejection_469(text)':'621c8e5756bf4996b416c25b38c783b9'};
const bodies=src=>[...src.matchAll(/CREATE (?:OR REPLACE )?FUNCTION ([\w.]+)\([\s\S]*?AS \$function\$([\s\S]*?)\$function\$/g)].map(m=>({name:m[1],md5:md5(m[2])}));

test('r469: guarded apply (window :02-:45, lock_timeout 2s, staging only, clock tick and fault runner untouched)',()=>{
  for(const s of [mig,down]){assert.match(s,/SET LOCAL lock_timeout = '2s'/);assert.match(s,/NOT BETWEEN 2 AND 45/);assert.match(s,/staging only/);assert.match(s,/pdc\.r469_tick/);}
  assert.doesNotMatch(mig,/FUNCTION public\.workshop_clock_tick/i);
  assert.doesNotMatch(mig,/FUNCTION pdc_ops\.fault_regression_check/i);
  assert.doesNotMatch(mig,/^(UPDATE|DELETE FROM|TRUNCATE|DROP TABLE)\s+public\.(workshop_bookings|vehicles)/im,'no booking or vehicle row is written');
  assert.doesNotMatch(mig+down,/\b1[23]\d{6}\b/,'no stock numbers in Git');
});

test('r469: every shipped function body matches its pin; the old body in the undo is bbdc1ae1',()=>{
  const shipped=bodies(mig);
  assert.equal(shipped.length,4);
  for(const [sig,m] of Object.entries(pins)){assert.ok(mig.includes(`('${sig}','${m}','r469'`),sig);}
  assert.deepEqual(shipped.map(b=>b.md5).sort(),Object.values(pins).sort());
  const old=bodies(down); assert.equal(old.length,1); assert.equal(old[0].md5,'bbdc1ae1525d7e5060bfda8a8406b8f4');
  assert.ok(mig.includes("IS DISTINCT FROM 'bbdc1ae1525d7e5060bfda8a8406b8f4'"),'apply refuses if pre_087 changed since prepared');
});

test('r469: the cascade moves only the overlapping chain and names a clash instead of a bare DB error',()=>{
  const body=bodies(mig).find(b=>b.name.endsWith('cascade_workshop_schedule_pre_087'));
  const src=mig.slice(mig.indexOf('CREATE OR REPLACE FUNCTION public.cascade_workshop_schedule_pre_087'));
  assert.ok(body);
  assert.match(src,/v_plan := pdc_cascade_private\.overlap_chain_469\(v_expected_ids, v_insert_end\);/);
  assert.doesNotMatch(src.slice(0,src.indexOf('$function$;')),/workshop_add_operational_minutes\(v_shifted\.scheduled_start_at, p_shift_minutes\)/,'no uniform push of every later booking');
  assert.match(src,/when sqlstate '22023' then[\s\S]*validation_rejection_469\(sqlerrm\)[\s\S]*'pushed_booking'/);
  const chain=mig.slice(mig.indexOf('CREATE FUNCTION pdc_cascade_private.overlap_chain_469'));
  assert.match(chain,/exit when v_row\.scheduled_start_at >= v_cursor;/,'a gap stops the chain');
  assert.match(chain,/STABLE/);
});

test('r469: daily check registered at sort 268 (F82) and run by the apply; private schema closed; undo removes it all',()=>{
  assert.match(mig,/\('cascade_insert_overlap_chain_469','F82',/);assert.match(mig,/\$chk\$,true,268,'r469'\)/);
  assert.match(mig,/REVOKE ALL ON SCHEMA pdc_cascade_private FROM anon, authenticated, service_role/);
  assert.match(mig,/EXECUTE x\.check_sql INTO y; IF y\.ok IS NOT TRUE/);
  assert.match(down,/DELETE FROM pdc_ops\.regression_checks WHERE check_name='cascade_insert_overlap_chain_469'/);
  assert.match(down,/DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r469'/);
  assert.match(down,/DROP SCHEMA pdc_cascade_private;/);
});

test('r469: the planner says which booking the push would clash with',()=>{
  global.parseIsoTimestamp=v=>{const d=new Date(v);return Number.isNaN(d.getTime())?null:d;};global.cleanNavisionText=v=>String(v??'').trim();
  global.escapeHtml=v=>String(v??'');
  const planner=require('./workshop-planner.js');
  const conflictId='3a69a07c-6d9b-4d1e-8c16-dbc67a650fbe';
  const result={ok:false,error:'vehicle_overlap',conflict_booking_id:conflictId,
    conflict:{conflict_type:'vehicle_overlap',existing_booking:{booking_id:conflictId,vehicle_id:'e4205525-9179-4124-a2d3-bf0dd6662400',
      vehicle:{stock_number:'TESTSTOCK1'},stage:{code:'FABRICATION',display_name:'Fab'},bay:{bay_number:1},
      scheduled_start_at:'2026-11-16T03:55:00+00:00',scheduled_end_at:'2026-11-16T07:55:00+00:00'}},
    pushed_booking_id:'afb05e02-9659-44b6-8163-1635dcd2ff8a',
    pushed_booking:{booking_id:'afb05e02-9659-44b6-8163-1635dcd2ff8a',vehicle:{stock_number:'TESTSTOCK1'},stage:{code:'FITTING',display_name:'Fitting'},bay:{bay_number:1}}};
  const msg=planner.workshopDescribeSharedActionError(result);
  assert.match(msg,/^Booking here would push stock TESTSTOCK1 \(Fitting Bay 1\) back onto its own booking \(stock TESTSTOCK1 · Fabrication · Bay 1 · scheduled .*\(Perth time\)\)\. No changes were saved\. Drop this vehicle after that job, use Best slot, or move the affected booking first\.$/);
  // Without a pushed booking the existing messages are unchanged.
  const plain=planner.workshopDescribeSharedActionError({ok:false,error:'vehicle_overlap'});
  assert.match(plain,/cross-bay overlap rule is switched off/);
  assert.equal(plain.includes('1-hour buffer'), false);
  const named=planner.workshopDescribeSharedActionError({...result,pushed_booking:undefined,pushed_booking_id:undefined});
  assert.match(named,/cross-bay overlap rule is switched off/);
  assert.match(named,/Fabrication/);
});
