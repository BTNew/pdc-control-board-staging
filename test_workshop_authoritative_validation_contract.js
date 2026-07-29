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
assert(lower.includes('workshop_bookings_active_vehicle_no_overlap'), 'authoritative same-vehicle exclusion constraint required');
assert(lower.includes('existing active same-vehicle booking overlaps require adjudication before migration 046'), 'migration must fail closed on pre-existing active vehicle overlaps without rewriting rows');
assert(lower.includes('workshop_bookings_active_bay_no_overlap'), 'authoritative bay exclusion constraint required');
assert(lower.includes('workshop_assignments_active_technician_no_overlap'), 'authoritative technician exclusion constraint required');
assert(lower.includes('workshop_calendar_minute_available') && lower.includes('workshop_operational_minutes_between'), 'canonical database calendar authority required');
assert(/create or replace function public\.workshop_add_operational_minutes[\s\S]*workshop_calendar_minute_available\(v_cursor\)/i.test(migration), 'cascade operational-minute helper must consume the canonical break/overtime calendar');
assert(/v_new_start\s*:=\s*public\.workshop_next_calendar_window\([\s\S]{0,220}public\.workshop_add_operational_minutes/i.test(migration), 'cascade must place every shifted booking in a full contiguous canonical window');
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

for(const fn of ['workshop_create_booking','workshop_move_booking','workshop_resize_booking','workshop_reassign_booking','workshop_restore_booking','workshop_start_booking','workshop_record_stoppage','workshop_resume_booking','workshop_complete_booking','workshop_return_booking_to_queue','workshop_delete_booking']){
  assert(lower.includes(`revoke execute on function public.${fn}`),`weaker helper remains runtime-callable: ${fn}`);
}

// All eight physical planners are required to share this single function. The
// database test exercises each station; this static test prevents station forks.
assert.strictEqual(stages.length,8);
assert.strictEqual((migration.match(/create or replace function public\.workshop_validate_booking\(/gi)||[]).length,1,'exactly one canonical validator definition expected');
assert(lower.includes("workshop_operational_minutes_between(p_scheduled_start_at,p_scheduled_end_at)<>p_duration_minutes"),'validator must compare configured operating minutes, not elapsed wall time');
for(const expression of [
  'workshop_add_operational_minutes(p_scheduled_start_at, p_duration_minutes)',
  'workshop_add_operational_minutes(p_scheduled_start_at, v_duration)',
  'workshop_add_operational_minutes(v_booking.scheduled_start_at, p_duration_minutes)',
  'workshop_add_operational_minutes(v_new_start,v_shifted.default_duration_minutes)'
]) assert(lower.includes(expression),`operational-duration override missing: ${expression}`);
assert(/public\.workshop_require_planner_operator\(\);\s*perform public\.workshop_require_version\(p_target_expected_version\)/.test(lower),'cascade must use the exact schema-qualified planner-role guard');
assert(lower.includes("at time zone 'australia/perth'"),'technician leave must use the AWST business timezone');
const cascade=lower.slice(lower.indexOf('create or replace function public.cascade_workshop_schedule'),lower.indexOf('create or replace function public.workshop_validate_booking'));
assert(!/status\s*=\s*'planned'(?![\s\S]{0,80}deleted_at\s+is\s+null)/.test(cascade),'cascade planned-row paths must exclude soft-deleted rows');
assert(cascade.indexOf('for update;')<cascade.indexOf('workshop_lock_resources(v_bay.id, null)'),'cascade must lock booking rows before the bay advisory lock');

// Operational tooling denylist. Transactional tests may use direct fixture DML;
// runtime/operational scripts may not disable guards or call low-level helpers.
const fixtureOnly=/^(?:_staging_test_tools[\\/]|scripts[\\/](?:test_|verify_)|backend[\\/]test_|test_)/;
const forbidden=[
  /alter\s+table\s+(?:public\.)?workshop_bookings\s+disable\s+trigger/i,
  /\bworkshop_(?:create|move|resize|restore|reassign)_booking\s*\(/i,
  /["'`]workshop_(?:create|move|resize|restore|reassign)_booking["'`]/i,
  /insert\s+into\s+(?:public\.)?workshop_bookings/i,
  /(?:from|import|require\s*\(|import\s*\(|__import__\s*\(|import_module\s*\()[^\n]*(?:_staging_test_tools|(?:^|[\\/])test_|scripts[\\/]test_)/i
];
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
  if(rel.replace(/\\/g,'/')==='scripts/benchmark_stage_a_150_transaction.py'){
    assert(/N\s*=\s*1(?:6\d|[7-9]\d|\d{3,})\b/.test(source),'Stage A benchmark must create at least 160 transaction-only fixtures');
    assert(source.includes('PROJECT_REF = "cdsmnqxtyyoeoznmbidd"') && /assert\s+baseline_q\.fetchone\(\)\[0\]\s*==\s*PROJECT_REF/.test(source),'Stage A benchmark must pin the staging project sentinel');
    assert(/autocommit\s*=\s*False/.test(source),'Stage A benchmark must own one rollback-safe transaction');
    assert(/\b(?:c|conn|connection)\.rollback\(\)/.test(source),'Stage A benchmark must explicitly roll back all fixture DML');
    assert(!/\bc\.commit\(\)|\bconn\.commit\(\)/.test(source),'Stage A benchmark must never commit fixture DML');
    assert(!forbidden.slice(0,3).some(pattern=>pattern.test(source)),'Stage A benchmark must not disable guards or call low-level booking helpers');
    continue;
  }
  if(rel.replace(/\\/g,'/')==='scripts/workshop_legacy_import.py'){
    assert(source.includes('WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED = True'),'legacy direct apply tripwire missing');
    assert(/if apply and WORKSHOP_LEGACY_DIRECT_APPLY_DISABLED:\s*\n\s*raise RuntimeError/.test(source),'legacy apply must fail closed before direct DML');
    continue;
  }
  for(const pattern of forbidden) assert(!pattern.test(source),`operational tooling uses fixture-only/direct booking path: ${rel} (${pattern})`);
}
console.log(JSON.stringify({canonical_validator:1,planner_stations:stages.length,minimum_minutes:60,half_open_overlap:true,lifecycle_guard:true,operational_files_scanned:operational.length}));
