'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const root = __dirname;
const read = name => fs.readFileSync(path.join(root, 'supabase', 'staging_only', name), 'utf8');
const m318 = read('20260822130000_318_reinstate_uid590_591_exact_archived_vehicles.sql');
const m319 = read('20260822131000_319_complete_uid590_navision_vin_from_authenticated_pdf.sql');
const m320 = read('20260822132000_320_reopen_uid590_activation_and_harden_monitor_wrapper.sql');
const m321 = read('20260822133000_321_allow_explicit_zero_hour_jobcard_receipts.sql');
for (const sql of [m318,m319,m320,m321]) {
  assert(sql.includes('pdc_production_environment_sentinel'));
  assert(sql.includes('pdc_monitor_staging_guard()'));
  assert(sql.includes('cdsmnqxtyyoeoznmbidd'));
  assert(sql.trim().endsWith('commit;'));
}
assert(m318.includes('imap_uid:590') && m318.includes('imap_uid:591'));
assert(m318.includes('13018324') && m318.includes('13001466'));
assert(m318.includes('14450') && m318.includes('37047'));
assert(m318.includes('PDC_318_IDENTITY_CONFLICT'));
assert(m319.includes('MABAV402403845') && m319.includes('MR0MABAV402403845'));
assert(m319.includes("position('MR0MABAV402403845' in coalesce(att.extracted_text,''))"));
assert(m320.includes("completion_reason<>'Overnight staging page clear'"));
assert(m320.includes("r->>'code'<>'jobcard_attachment_receipt'"));
assert(m320.includes('monitor_nonreceipt_success_rejected'));
assert(m321.includes('drop constraint pdc_jobcard_attachment_import_receipt_estimated_hours_sum_check'));
assert(m321.includes('pdc_jobcard_attachment_import_receipts_estimated_hours_sum_chec'));
console.log('uid590_591_runtime_repair: PASS');
