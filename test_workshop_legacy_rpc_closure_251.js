'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/251_exact_complete_legacy_workshop_rpc_closure.sql', 'utf8').replace(/\r\n/g, '\n').toLowerCase();
const authority = fs.readFileSync('supabase/staging_only/244_workshop_admin_authority_intent_receipt_undo.sql', 'utf8').replace(/\r\n/g, '\n').toLowerCase();
const legacy = [
  'schedule_vehicle_work(uuid,integer,text,integer,timestamptz,integer,uuid,text,jsonb)',
  'cascade_workshop_schedule(text,uuid,integer,text,integer,timestamptz,integer,uuid,integer,text,jsonb)',
  'move_workshop_booking(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'cascade_workshop_booking_move(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'cascade_workshop_booking_move_pre_116(uuid,integer,text,integer,timestamptz,integer,text,jsonb)',
  'resize_workshop_booking(uuid,integer,integer,jsonb)',
  'change_booking_bay(uuid,integer,integer,jsonb)',
];
function declaredSignature(name) {
  const match = authority.match(new RegExp(`create or replace function public\\.${name}\\(([\\s\\S]*?)\\)\\s*returns`));
  assert(match, `${name} declaration missing from migration 244`);
  const types = match[1].split(',').map(parameter => {
    const type = parameter.trim().match(/^p_[a-z0-9_]+\s+([a-z0-9_]+)(?:\s+default\s+[\s\S]+)?$/);
    assert(type, `cannot derive ${name} parameter type from ${parameter.trim()}`);
    return type[1];
  });
  return `${name}(${types.join(',')})`;
}
const controlled = [
  declaredSignature('administrator_schedule_workshop_vehicle'),
  declaredSignature('administrator_move_workshop_booking'),
  declaredSignature('undo_administrator_workshop_booking_move'),
];

assert(sql.includes("version='250' and name='revoke_service_role_legacy_workshop_rpc'"));
assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"));
assert(sql.includes('pdc_production_environment_sentinel'));
for (const signature of legacy) {
  assert(sql.includes(`revoke all on function public.${signature} from public,anon,authenticated,service_role;`), `${signature} revoke missing`);
  assert(sql.includes(`'public.${signature}'`), `${signature} exact postcondition missing`);
}
for (const signature of controlled) assert(sql.includes(`'public.${signature}'`), `${signature} controlled endpoint postcondition missing`);
assert(sql.includes("has_function_privilege('service_role',endpoint,'execute')"));
assert(sql.includes("not has_function_privilege('authenticated',endpoint,'execute')"));
assert(sql.includes('pre-116 cascade move'));
assert(!/grant\s+execute/.test(sql), 'draft closure must not add grants');
console.log('Draft migration 251 contract passed: exact seven-RPC closure and authenticated-only controlled endpoint postconditions');
