'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '237_workshop_snapshot_calendar_performance.sql'), 'utf8');
const lower = sql.toLowerCase();

assert(lower.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'Migration 237 must be pinned to the authorized staging project');
assert(lower.includes("version='236' and name='complete_authorised_operation_rules'"), 'Migration 237 must require exact head 236');
assert(lower.includes("version::numeric>236") && lower.includes("version='237'"), 'Migration 237 must reject later or duplicate ledgers');
assert(lower.includes("pg_advisory_xact_lock(hashtextextended('pdc-staging-migration-installation',0))"), 'Migration 237 must share the staging installation lock');
assert(lower.includes('workshop_add_operational_minutes_pre237'), 'Migration 237 must retain a private parity baseline');
assert(lower.includes('revoke all on function public.workshop_add_operational_minutes_pre237'), 'The parity baseline must not be an alternate operational path');
const optimizedStart = lower.indexOf('create or replace function public.workshop_add_operational_minutes(\n');
const optimizedEnd = lower.indexOf('-- consolidate station eligibility', optimizedStart);
const optimizedDuration = lower.slice(optimizedStart, optimizedEnd);
assert(optimizedDuration.includes("select jsonb_object_agg(key,value)"), 'Calendar settings must be loaded once per duration calculation');
assert(!optimizedDuration.includes('workshop_calendar_minute_available(v_cursor)'), 'The optimized duration loop must not issue the legacy settings query for every minute');
assert(optimizedDuration.includes('while v_remaining>0 and v_cursor<v_limit loop'), 'The exact minute cursor semantics must remain explicit');
assert(lower.includes('create or replace function public.get_station_workshop_snapshot_pre_170'), 'The station snapshot implementation must be optimized behind the existing public wrapper');
assert(lower.includes('eligibility as materialized') && lower.includes('hours as materialized'), 'Eligibility and operation hours must be calculated once per snapshot');
assert(lower.includes('selected_filtered as materialized'), 'Selected bookings must be filtered from one calculated effective-end set');
assert(lower.includes("'outstanding_candidates'") && lower.includes("'unscheduled_candidates'") && lower.includes("'selected_date_bookings'"), 'Snapshot count contract must remain present');
assert(lower.includes("'bookings'") && lower.includes("'vehicles'") && lower.includes("'work_items'"), 'Snapshot payload collections must remain present');
assert(lower.includes("'237','workshop_snapshot_calendar_performance'"), 'Migration 237 must record its exact ledger identity');

console.log('Workshop snapshot performance migration 237 contract passed');
