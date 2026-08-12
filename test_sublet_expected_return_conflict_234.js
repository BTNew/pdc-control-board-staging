'use strict';
const assert=require('assert');
const fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/234_sublet_expected_return_conflict_details.sql','utf8');
assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"));
assert(sql.includes("version='233'"));
assert(sql.includes("hashtextextended('pdc-staging-migration-installation',0)"));
assert(/version~'\^\[0-9\]\+\$' and version::numeric>233/.test(sql),'must fail closed when any later numeric migration exists');
assert(sql.includes("expected_return_date+1"),'expected return must bound active Sublet through that Perth date');
assert(sql.includes("at time zone 'Australia/Perth'"));
assert(sql.includes("workshop_booking_id"));
assert(sql.includes("workshop_start_date_perth"));
assert(sql.includes("perform public.pdc_lock_canonical_sublet_vehicle(new.vehicle_id)"));
assert(sql.includes("status in('queued','planned','started','stoppage')"));
assert(!/delete\s+from\s+public\.(vehicles|pdc_sublet)/i.test(sql));
for(const [version,predecessor] of [[234,233],[235,234],[236,235]]) {
  const migration=fs.readFileSync(`supabase/staging_only/${version}_${version===234?'sublet_expected_return_conflict_details':version===235?'reversible_workshop_operation_removal':'complete_authorised_operation_rules'}.sql`,'utf8');
  assert(migration.includes("hashtextextended('pdc-staging-migration-installation',0)"),`${version} uses the shared installation lock`);
  assert(migration.includes(`version::numeric>${predecessor}`),`${version} fails closed on every later numeric ledger row`);
}
console.log('Sublet expected-return conflict migration static tests passed.');
