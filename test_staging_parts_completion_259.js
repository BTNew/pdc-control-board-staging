'use strict';

const assert = require('assert');
const fs = require('fs');
const sql = fs.readFileSync('supabase/staging_only/259_authenticated_parts_completion.sql', 'utf8');

for (const token of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  'public.mark_pdc_parts_complete',
  'p_expected_version integer',
  "perform public.require_pdc_role('operator')",
  'vehicle_version_conflict',
  'parts_already_received',
  "'parts_completed'",
  "'replayed'",
  'receipt_id',
  "'mark_pdc_parts_complete'",
  'parts_received',
  'parts_stoppage',
  'worst_eta',
  'pdc_email_vehicle_revision',
  "version='259'",
]) assert(sql.includes(token), `Parts completion migration missing ${token}`);
assert(sql.includes('grant execute on function public.mark_pdc_parts_complete(uuid,integer) to authenticated'), 'Parts completion RPC must be authenticated-only');
assert(!sql.includes('grant execute on function public.mark_pdc_parts_complete(uuid,integer) to anon'), 'Parts completion RPC must not be callable by anon');
assert(sql.indexOf('update public.pdc_email_vehicle_revision') < sql.indexOf("return public.navision_backend_response(true,'parts_completed'"), 'Completion must publish revision before returning success');
console.log('Staging Parts completion migration contract passed.');
