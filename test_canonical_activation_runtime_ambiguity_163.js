#!/usr/bin/env node
const fs=require('fs');
const crypto=require('crypto');
const assert=(v,m)=>{if(!v)throw new Error(m);};
const p='supabase/staging_only/163_canonical_activation_runtime_ambiguity_fix.sql';
const sql=fs.readFileSync(p,'utf8');
const lower=sql.toLowerCase();
const sha=x=>crypto.createHash('sha256').update(fs.readFileSync(x,'utf8').replace(/\r\n/g,'\n')).digest('hex');
assert(sha('supabase/staging_only/162_manager_approved_workbook_canonical_activation.sql')==='09e80662b0f861a03b39544b9238334c6df6b0e9e9dd343b45501be0ceaada4b','Migration162 source drift');
assert((sql.match(/#variable_conflict use_column/g)||[]).length===5,'all five authenticated RPCs require use_column compilation policy');
assert(!/declare[^;\n]*\bemail\s+text/i.test(sql),'ambiguous local email variable remains');
assert(!/;id\s+uuid;/i.test(sql),'ambiguous local id variable remains');
for(const name of [
 'configure_pdc_pmb_canonical_manager_authority','manager_approve_pdc_pmb_canonical_activation',
 'administrator_countersign_pdc_pmb_canonical_activation','authorize_pdc_pmb_canonical_activation_apply',
 'apply_pdc_pmb_canonical_activations']){
 assert(new RegExp(`create or replace function public\\.${name}\\(`,'i').test(sql),`${name} replacement missing`);
}
assert(/pdc_monitor_staging_guard\(\)/.test(sql),'staging guard missing');
assert(/version='162' and name='manager_approved_workbook_canonical_activation'/.test(sql),'exact predecessor missing');
assert(/exists\(select 1 from supabase_migrations\.schema_migrations where version>'162'\)/.test(sql),'newer-ledger refusal missing');
assert(/values\('163','canonical_activation_runtime_ambiguity_fix'/.test(sql),'ledger163 insert missing');
assert(/notify pgrst,'reload schema'/.test(sql),'PostgREST schema reload missing');
assert(!/grant execute[^;]+to service_role/is.test(sql),'service_role execute grant forbidden');
assert((lower.match(/grant execute on function public\./g)||[]).length===5,'authenticated grants incomplete');
console.log('Migration163 canonical activation runtime ambiguity contracts passed');
