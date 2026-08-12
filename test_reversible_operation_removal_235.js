'use strict';
const assert=require('assert');
const fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/235_reversible_workshop_operation_removal.sql','utf8');
for(const needle of [
  "project_ref='cdsmnqxtyyoeoznmbidd'","version='234'",
  'pdc_workshop_operation_removal_receipts_235','pdc_workshop_operation_removal_undo_receipts_235',
  'manual_operator','completed_work_protected','vehicle_protected',
  'auditor_evidence_protected','live_workshop_booking_protected',
  'pdc_auditor_recalculate_required_work_226','pdc_email_vehicle_revision',
  'idempotency_conflict','later_manual_or_protected_change','operation_restored'
]) assert(sql.includes(needle),`missing ${needle}`);
assert(!/delete\s+from\s+public\.(vehicles|pdc_authenticated_email_operation_lines|vehicle_workshop_line_adjustments)/i.test(sql));
assert(/before update or delete on public\.pdc_workshop_operation_removal_receipts_235/i.test(sql));
assert(/grant execute on function public\.remove_pdc_workshop_operation_line_235\([^)]*\) to authenticated/i.test(sql));
assert(sql.includes("hashtextextended('pdc-staging-migration-installation',0)"));
assert(/version~'\^\[0-9\]\+\$' and version::numeric>234/.test(sql),'must fail closed when any later numeric migration exists');
assert(/pdc_auditor_finding_evidence[\s\S]*entity_type='operation_line'[\s\S]*entity_id=p_operation_line_id/i.test(sql),'Auditor evidence protects the immutable line');
assert(/status::text not in\('completed','cancelled'\)[\s\S]*s\.code=v_effective_stage/i.test(sql),'live booking protecting the effective stage is rejected');
assert(!/update public\.pdc_email_vehicle_revision set revision=revision\+1/i.test(sql),'RPC must rely on canonical mutation triggers, not duplicate explicit increments');
assert((sql.match(/select revision into strict v_revision from public\.pdc_email_vehicle_revision where singleton/g)||[]).length===2,'remove and undo return the exact resulting canonical revision');
assert(/if found then[\s\S]*already_removed[\s\S]*v_existing\.realtime_revision/i.test(sql),'exact remove replay returns its original revision without mutation');
assert(/if found then return public\.navision_backend_response\(v_existing\.outcome='restored'[\s\S]*v_existing\.realtime_revision/i.test(sql),'undo replay returns its original revision without mutation');
assert(/not found or to_jsonb\(v_current\)<>v_receipt\.removed_value[\s\S]*'conflict_preserved'[\s\S]*'later_manual_or_protected_change'/i.test(sql),'undo preserves a later conflicting adjustment instead of overwriting it');
assert(/previous_value is null[\s\S]*set active=true[\s\S]*else[\s\S]*jsonb_populate_record[\s\S]*version=v_current\.version\+1/i.test(sql),'undo restores either the source-backed effective line or the prior overlay with one exact adjustment version increment');
console.log('Reversible operation removal migration static tests passed.');
