const fs=require('fs');
const assert=require('assert');
const sql=fs.readFileSync('supabase/staging_only/144_restore_narrow_pdc_monitor_canonical_importer.sql','utf8');
const runner=fs.readFileSync('scripts/apply_migration_144_staging.py','utf8');
for(const token of [
  "project_ref='cdsmnqxtyyoeoznmbidd'","pdc_production_environment_sentinel",
  "version='132'","version='143'","jsonb_array_length(v_email->''stock_numbers'') is distinct from 1",
  'backend_stock_not_found','backend_stock_ambiguous','job_card_source_conflict','operational_job_card_conflict',
  "'contract_version'',3","pdc_monitor_canonical_stock_import_144",
  'from public,anon,authenticated,service_role','to authenticated',
  "values('144','restore_narrow_pdc_monitor_canonical_importer'"
]) assert(sql.includes(token),`missing migration token: ${token}`);
assert(sql.includes("set search_path=pg_catalog,public,extensions") || sql.includes('pg_get_functiondef'));
assert(!/grant\s+(insert|update|delete|all)\s+on\s+(table\s+)?public\./i.test(sql),'must not grant direct table writes');
assert(!/grant\s+execute[\s\S]+to\s+(service_role|anon|public)/i.test(sql),'must not grant importer execute outside authenticated');
for(const token of ['EXPECTED_SHA','--expected-commit','refusing apply from unreviewed or dirty worktree','production_changed']) assert(runner.includes(token),`missing runner token: ${token}`);
console.log('PASS migration 144 narrow Monitor importer contract');
