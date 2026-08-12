'use strict';
const assert=require('assert');
const fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/235_reversible_workshop_operation_removal.sql','utf8');
for(const needle of [
  "project_ref='cdsmnqxtyyoeoznmbidd'","version='234'",
  'pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235',
  'manual_operator','completed_work_protected','vehicle_protected',
  'pdc_auditor_recalculate_required_work_226','pdc_email_vehicle_revision',
  'idempotency_conflict','later_manual_or_protected_change','operation_restored'
]) assert(sql.includes(needle),`missing ${needle}`);
assert(!/delete\s+from\s+public\.(vehicles|pdc_authenticated_email_operation_lines|vehicle_workshop_line_adjustments)/i.test(sql));
assert(/before update or delete on public\.pdc_workshop_operation_removal_receipts_235/i.test(sql));
assert(/grant execute on function public\.remove_pdc_workshop_operation_line_235\([^)]*\) to authenticated/i.test(sql));
console.log('Reversible operation removal migration static tests passed.');
