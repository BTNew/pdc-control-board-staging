'use strict';
const assert=require('assert'),fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/20260825030000_366_overnight_wrapper_postgrest_argument_names.sql','utf8');
assert.match(sql,/project_ref='cdsmnqxtyyoeoznmbidd'/);
assert.match(sql,/365_overnight_synthetic_mutation_wrappers/);
assert.match(sql,/NOT public\.pdc_hermes_test_dependency_guard_365\(\)/);
for(const name of ['vehicle_edit','set_work_states','lifecycle','parts','parts_stoppage','schedule','booking','sublet']){
 assert.match(sql,new RegExp(`CREATE OR REPLACE FUNCTION public\\.pdc_hermes_test_${name}_365\\(\\n p_run_id text`));
}
assert.match(sql,/array_to_string\(p\.proargnames,','\)=expected\.argnames/);
assert.doesNotMatch(sql,/GRANT\s+(?:INSERT|UPDATE|DELETE|ALL)\s+ON/i);
assert.doesNotMatch(sql,/queue_vehicle_notification|TRUNCATE|DISABLE TRIGGER/i);
console.log('Overnight wrapper PostgREST argument-name contract passed.');
