#!/usr/bin/env node
const fs=require('fs'),crypto=require('crypto');
const assert=(v,m)=>{if(!v)throw new Error(m)};
const sql=fs.readFileSync('supabase/staging_only/165_receipt_bound_retained_jobcard_classification.sql','utf8');
const sha=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
assert(sha('supabase/staging_only/164_canonical_activation_shared_vehicle_pairs.sql')==='e54868ee95dd8ecd0b2f0e8e50e4142adcb36930e822b0a9539923d3b1ff6ded','Migration164 source drift');
assert(/version='164' and name='canonical_activation_shared_vehicle_pairs'/.test(sql),'exact predecessor missing');
assert(/version>'164'/.test(sql) && /pdc_monitor_staging_guard\(\)/.test(sql),'staging/newer-ledger guards missing');
assert(/create or replace function public\.pdc_pmb_workbook_classify_identity/.test(sql),'classifier replacement missing');
assert(/pdc_pmb_canonical_pair_receipts cr/.test(sql),'canonical pair receipt proof missing');
assert(/prior\.stock_number=p_stock and prior\.job_card_number=p_job_card/.test(sql),'exact Stock/job-card tuple binding missing');
assert(/prior\.registration is not distinct from p_registration/.test(sql),'exact registration tuple binding missing');
assert(/cr\.backend_record_id=v_backend\.id and cr\.vehicle_id=v_vehicle\.id/.test(sql),'canonical backend/vehicle receipt binding missing');
assert(/update public\.navision_backend_revision set revision=revision\+1/.test(sql),'stale-preview invalidation missing');
assert(/values\('165','receipt_bound_retained_jobcard_classification'/.test(sql),'Migration165 ledger entry missing');
assert(!/grant execute/i.test(sql),'classifier must remain private');
console.log('Migration165 receipt-bound retained job-card classification contracts passed');
