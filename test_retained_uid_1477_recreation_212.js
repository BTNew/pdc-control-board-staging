const fs=require('fs'),assert=require('assert');
const s=fs.readFileSync('supabase/staging_only/212_retained_uid_1477_recreation_import.sql','utf8');
for(const x of ["version='211'","version='212'","project_ref='cdsmnqxtyyoeoznmbidd'","pdc_production_environment_sentinel","get_pdc_retained_reset_binding_212","r.role='importer'","p_provider_uid text","vuid<>'1:477'","s<>'13047224'","jc<>'J139125358'","vin<>'MR0PEBHV600404885'","jsonb_array_length(ops)<>13","total<>13.32","<>8.42","<>1.40","<>2.00","<>1.50","pdc_retained_reset_import_receipts_212","recreation_consumed","booking_created',false","deleted_vehicle',false","grant execute on function public.import_pdc_retained_reset_jobcard_212","revoke all on function public.import_pdc_retained_reset_jobcard_212"]) assert(s.includes(x),x);
assert(!/grant\s+execute[^;]+to\s+(viewer|auditor|anon|public|service_role)/i.test(s));
console.log('Migration 212 retained UID 1:477 controlled recreation contract passed');
