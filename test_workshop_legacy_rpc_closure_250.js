'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/250_revoke_service_role_legacy_workshop_rpc.sql', 'utf8').replace(/\r\n/g, '\n');
const lower = sql.toLowerCase();
const signatures = [
  'schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)',
  'cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)',
  'move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'resize_workshop_booking(uuid,integer,integer,jsonb)',
  'change_booking_bay(uuid,integer,integer,jsonb)',
];

assert(lower.includes("version='249' and name='workshop_admin_create_undo_history_order'"));
assert(lower.includes("project_ref='cdsmnqxtyyoeoznmbidd'"));
assert(lower.includes('pdc_production_environment_sentinel'));
for (const signature of signatures) {
  assert(lower.includes(`revoke all on function public.${signature} from public,anon,authenticated,service_role;`), `${signature} must be closed to every client/service role`);
}
for (const name of signatures.map(value => value.slice(0, value.indexOf('(')))) {
  assert(new RegExp(`foreach n[\\s\\S]*'${name}'[\\s\\S]*has_function_privilege\\('service_role',p\\.oid,'execute'\\)`).test(lower), `${name} must be covered by the postcondition`);
}
assert(lower.includes('schedule, cascade schedule, move, cascade move, resize and bay-change legacy rpcs denied'), 'ledger statement must list the exact public closure');
assert(!/grant\s+execute/i.test(lower), 'closure migration must grant no execution path');
console.log('Migration250 exact legacy Workshop RPC closure passed: public, anon, authenticated and service_role denied for all six endpoints');
