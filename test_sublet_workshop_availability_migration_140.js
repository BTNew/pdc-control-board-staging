'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join('supabase', 'staging_only', '140_sublet_return_calendar_and_workshop_availability.sql');
assert(fs.existsSync(migrationPath), 'Migration 140 must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

assert(sql.includes("project_ref='cdsmnqxtyyoeoznmbidd'"), 'Migration must be staging-sentinel guarded');
assert(sql.includes("from supabase_migrations.schema_migrations where version='139' and name='navision_from_twa_it_parity'"), 'Migration must require exact predecessor 139');
assert(sql.includes("values('140','sublet_return_calendar_and_workshop_availability'"), 'Migration ledger entry must be exact');
assert(sql.includes('create or replace function public.pdc_sublet_away_on_date'), 'One canonical actual-return availability predicate is required');
assert(sql.includes('actual_return_date'), 'Availability must be ended only by the actual return date');
assert(!/expected_return_date\s*(?:<=|>=|>|<).*p_workshop_date/i.test(sql), 'Expected return must not reopen workshop availability');
assert(sql.includes('create trigger pdc_workshop_booking_sublet_away_guard'), 'Workshop writes need a database-level away guard');
assert(sql.includes('create trigger pdc_sublet_booking_workshop_overlap_guard'), 'Sublet date moves need the reverse workshop-overlap guard');
assert(sql.includes('before insert or update of booking_date,expected_return_date,actual_return_date'), 'Sublet-date trigger must reject reverse overlaps and invalid date order');
assert(sql.includes("'sublet_away'"), 'Rejected workshop bookings must expose a canonical sublet_away error');
assert(sql.includes("'workshop_booking_conflict'"), 'Rejected Sublet date changes must expose a canonical workshop conflict error');
assert(sql.includes("lower(wi.work_key)='sublet'"), 'Shared Sublet snapshot must include every canonical required Sublet vehicle');
assert(sql.includes("or exists(select 1 from public.pdc_sublet_bookings"), 'Returned/history rows must remain in the shared Sublet snapshot');
assert(sql.includes("v_field='actual_return_date'"), 'Returned mutation must remain inside the guarded shared RPC');
assert(sql.includes('v_next_booking_date') && sql.includes('v_next_expected_return_date') && sql.includes('v_next_actual_return_date'), 'Server must validate prospective multi-date ordering, not trust the browser');
assert(sql.includes('pg_advisory_xact_lock'), 'Sublet and workshop date checks must serialize against concurrent scheduling');

console.log('Migration 140 Sublet authority and workshop availability contract passed');
