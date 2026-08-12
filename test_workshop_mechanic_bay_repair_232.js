'use strict';
const assert = require('assert');
const fs = require('fs');

const sql = fs.readFileSync('supabase/staging_only/232_workshop_mechanic_bay_assignment_repair.sql','utf8');
assert(sql.includes("where stage_code in (select code from public.workshop_stages)"), 'revision bump is bounded');
assert(sql.includes('workshop_bays_one_default_bay_per_technician'), 'one-bay-per-mechanic unique index exists');
assert(sql.includes('workshop_bay_default_technician_history'), 'assignment history is persisted');
assert(sql.includes("'technician_already_assigned_to_bay'"), 'useful exclusivity error is returned');
assert(sql.includes("'idempotent',true"), 'exact replay is idempotent');
assert(sql.includes("where id=p_bay_id and version=p_expected_version"), 'bay update is version-bound');
assert(sql.includes("revoke all on function public.set_bay_default_technician(uuid,integer,uuid) from public,anon,service_role"), 'RPC excludes public/anon/service_role');
const bumpBody = sql.slice(
  sql.indexOf('create or replace function public.workshop_bump_all_station_revisions()'),
  sql.indexOf('revoke all on function public.workshop_bump_all_station_revisions()')
);
assert(/update public\.workshop_station_revision[\s\S]*where stage_code in \(select code from public\.workshop_stages\)/i.test(bumpBody), 'revision update has an explicit station-key predicate');
console.log('Migration 232 mechanic/default-technician contracts passed');
