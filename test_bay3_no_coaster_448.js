/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r448 (F61, Bhavesh 21 Oct 18:19, approved by Craig): Bus Bay 3 takes any vehicle except a Coaster.
// A Coaster (model text "coaster" or the TOYCOA code) is warn-and-confirm with a logged override (r417);
// Book all stations skips Bay 3 for a Coaster. Mirrors pdc_bus_private.booking_rule (check bay3_no_coaster_448).
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');

test('planner text: Bay 3 refuses only a Coaster and offers the logged confirm',()=>{
  const planner=fs.readFileSync('workshop-planner.js','utf8');
  const line=planner.split('\n').find(l=>l.includes("error === 'bus_bay_vehicle_incompatible'"));
  assert.match(line,/Bay 3 has a height restriction and does not take a Coaster/);
  assert.match(line,/override is logged/);
  assert.doesNotMatch(line,/HiAce/);
});

test('migration, undo and rolled-back test are in the repo and consistent',()=>{
  const mig=fs.readdirSync('supabase/migrations').find(f=>/_r448_bay3_no_coaster\.sql$/.test(f));
  assert.ok(mig,'r448 migration');
  const up=fs.readFileSync('supabase/migrations/'+mig,'utf8'),down=fs.readFileSync('supabase/rollbacks/'+mig.replace('.sql','.down.sql'),'utf8');
  assert.match(up,/IF bay=3 AND \(model_name~\* 'coaster' OR upper\(btrim\(model_name\)\)='TOYCOA'\)/);
  assert.doesNotMatch(up.split('CREATE OR REPLACE FUNCTION pdc_bus_private.booking_rule')[1].split('$function$;')[0],/TOYHIA|required_model/);
  assert.match(up,/Bay %s has a height restriction and does not take a Coaster\./);
  assert.match(up,/'bay3_no_coaster_448','F61'/);assert.match(up,/SET LOCAL lock_timeout = '2s'/);assert.match(up,/NOT BETWEEN 2 AND 45/);
  assert.match(down,/model_name!~\* 'hi\[\[:space:\]-\]\?ace' AND upper\(btrim\(model_name\)\)<>'TOYHIA'/);
  assert.match(down,/r448_undo_kept/);assert.match(down,/Bay %s is for %s vehicles only/);
  const rb=fs.readFileSync('tests/bay3_no_coaster_448_rollback.sql','utf8');
  assert.match(rb,/R448_RB_RESULT/);assert.match(rb,/pg_temp\.deadline\(\)/);
  assert.ok(rb.indexOf('r448 undo')>rb.indexOf('-- r448 (F61'),'undo runs after apply');
});
