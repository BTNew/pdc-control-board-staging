'use strict';
const assert=require('assert');
const fs=require('fs');
const path=require('path');
const root=__dirname;
const migration=fs.readFileSync(path.join(root,'supabase/migrations/046_workshop_authoritative_validation_and_lifecycle.sql'),'utf8');
const lower=migration.toLowerCase();
const stages=['BUS_4X4','TINT','HOIST','FITTING','FABRICATION','ELECTRICAL','TYRE','PIT_INSPECTION'];

assert(lower.includes('p_duration_minutes<60'), 'canonical validator must reject values below 60');
assert(lower.includes("'minimum_minutes',60"), 'machine-readable minimum must remain exactly 60');
assert(!/minimum(?:_|\s|-)*(?:duration|minutes)[^\n]{0,80}120/i.test(migration), 'no two-hour minimum may enter migration contract');
assert(lower.includes("p_status in ('queued','planned','started','stoppage')"), 'active booking states must be explicit');
assert(lower.includes("tstzrange(scheduled_start_at,scheduled_end_at,'[)')"), 'half-open intervals must permit back-to-back bookings');
assert(lower.includes("pg_advisory_xact_lock(hashtextextended('workshop:vehicle:'||new.vehicle_id::text,0))"), 'transaction-safe vehicle advisory lock required');
assert(lower.includes('workshop_bookings_active_bay_no_overlap'), 'authoritative bay exclusion constraint required');
assert(lower.includes('workshop_assignments_active_technician_no_overlap'), 'authoritative technician exclusion constraint required');
assert(lower.includes('workshop_calendar_minute_available') && lower.includes('workshop_operational_minutes_between'), 'canonical database calendar authority required');
for(const key of ['working_week','day_start_time','day_end_time','closures','break_windows','overtime_windows','technician_leave']){
  assert(lower.includes(`key='${key}'`) || lower.includes(key), `calendar authority missing ${key}`);
}
for(const code of ['PMB','YH','IT']) assert(migration.includes(`'${code}'`), `location rule missing ${code}`);
assert(lower.includes("'it_eta_missing'") && lower.includes("'it_before_eta'"), 'IT ETA rules required');
assert(lower.includes('canonical_requirement_missing_or_completed'), 'canonical incomplete requirement required');
assert(lower.includes('bay_inactive_or_wrong_station'), 'bay authority required');
assert(lower.includes('technician_leave_conflict') && lower.includes('technician_overlap'), 'technician authority required');

const requiredTransitions=[
  "old.status in ('queued','planned') and new.status='started'",
  "old.status='started' and new.status='stoppage'",
  "old.status='stoppage' and new.status='started'",
  "old.status in ('started','stoppage') and new.status='completed'",
  "old.status in ('queued','planned','stoppage') and new.status='deleted'",
  "old.status='completed' and new.status='queued'",
  "old.status='deleted' and new.status='queued'",
];
for(const transition of requiredTransitions) assert(lower.includes(transition),`lifecycle transition missing: ${transition}`);
for(const capability of ['reopen_completed','restore','return_to_queue']) assert(lower.includes(`workshop_consume_transition_authorization(old.id,'${capability}')`),`protected lifecycle capability missing: ${capability}`);
assert(lower.includes('revoke all on table public.workshop_transition_authorizations from public, anon, authenticated'), 'transition capabilities must be private');

for(const fn of ['workshop_create_booking','workshop_move_booking','workshop_resize_booking','workshop_restore_booking','workshop_start_booking','workshop_record_stoppage','workshop_resume_booking','workshop_complete_booking','workshop_return_booking_to_queue','workshop_delete_booking']){
  assert(lower.includes(`revoke execute on function public.${fn}`),`weaker helper remains runtime-callable: ${fn}`);
}

// All eight physical planners are required to share this single function. The
// database test exercises each station; this static test prevents station forks.
assert.strictEqual(stages.length,8);
assert.strictEqual((migration.match(/create or replace function public\.workshop_validate_booking\(/gi)||[]).length,1,'exactly one canonical validator definition expected');

// Operational tooling denylist. Transactional tests may use direct fixture DML;
// runtime/operational scripts may not disable guards or call low-level helpers.
const fixtureOnly=/^(?:_staging_test_tools[\\/]|scripts[\\/]test_|backend[\\/]test_|test_)/;
const forbidden=[/alter\s+table\s+(?:public\.)?workshop_bookings\s+disable\s+trigger/i,/\bworkshop_(?:create|move|resize|restore)_booking\s*\(/i,/insert\s+into\s+(?:public\.)?workshop_bookings/i];
const operational=[];
function walk(dir){for(const ent of fs.readdirSync(dir,{withFileTypes:true})){
  if(['.git','node_modules','supabase','review-evidence'].includes(ent.name)) continue;
  const full=path.join(dir,ent.name); if(ent.isDirectory()) walk(full);
  else if(/\.(?:js|py)$/i.test(ent.name)) operational.push(full);
}}
walk(root);
for(const file of operational){
  const rel=path.relative(root,file);
  if(fixtureOnly.test(rel)) continue;
  const source=fs.readFileSync(file,'utf8');
  if(rel.replace(/\\/g,'/')==='scripts/workshop_legacy_import.py'){
    assert(source.includes('WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED = True'),'legacy direct apply tripwire missing');
    assert(/if apply and WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED:\s*\n\s*raise RuntimeError/.test(source),'legacy apply must fail closed before direct DML');
    continue;
  }
  for(const pattern of forbidden) assert(!pattern.test(source),`operational tooling uses fixture-only/direct booking path: ${rel} (${pattern})`);
}
console.log(JSON.stringify({canonical_validator:1,planner_stations:stages.length,minimum_minutes:60,half_open_overlap:true,lifecycle_guard:true,operational_files_scanned:operational.length}));
