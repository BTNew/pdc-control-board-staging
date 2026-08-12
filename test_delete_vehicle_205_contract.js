'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sqlPath = path.join(__dirname, 'supabase', 'staging_only', '205_admin_recoverable_vehicle_archive.sql');
const sql206Path = path.join(__dirname, 'supabase', 'staging_only', '206_recoverable_archive_booking_history_identity.sql');
const sql = fs.readFileSync(sqlPath, 'utf8');
const sql206 = fs.readFileSync(sql206Path, 'utf8');
const sql207 = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '207_admin_vehicle_actor_lock_volatility.sql'), 'utf8');
const sql208 = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '208_archived_vehicle_snapshot_lock_volatility.sql'), 'utf8');
const lower = sql.toLowerCase();

function has(re, message) { assert.ok(re.test(sql), message); }

has(/begin;[\s\S]*pg_advisory_xact_lock[\s\S]*commit;/i, 'Migration must be transactional and installation-locked');
has(/public\.pdc_monitor_staging_guard\(\)/i, 'Migration and RPCs must use the strict staging guard');
has(/version='204'\s+and name='align_monitor_enqueue_acl_and_upload_policy'/i, 'Migration must require exact predecessor 204');
has(/exists\(select 1 from supabase_migrations\.schema_migrations where version='205'\)/i, 'Migration must reject a duplicate install');
has(/version,name,statements\) values\('205','admin_recoverable_vehicle_archive'/i, 'Migration must append ledger 205');

for (const table of ['pdc_vehicle_tombstones', 'pdc_vehicle_lifecycle_events', 'pdc_vehicle_recreation_permissions']) {
  has(new RegExp(`create table public\\.${table}\\(`, 'i'), `${table} must exist`);
  has(new RegExp(`alter table public\\.${table} enable row level security`, 'i'), `${table} must enable RLS`);
}
has(/tombstone_kind text not null check\(tombstone_kind in\('manual_delete','staging_reset'\)\)/i, 'Manual archive and reset tombstones must be distinct');
has(/normalized_stock text not null[\s\S]*deleted_by uuid not null[\s\S]*deleted_at timestamptz not null[\s\S]*reason text not null[\s\S]*previous_lifecycle_state[\s\S]*previous_location[\s\S]*previous_visible_on_board[\s\S]*previous_status[\s\S]*vehicle_snapshot jsonb not null/i, 'Tombstone must retain identity, actor, time, reason, prior state, and restore snapshot');
has(/pdc_vehicle_tombstones_immutable before update or delete/i, 'Tombstones must be immutable');
has(/pdc_vehicle_lifecycle_events_immutable before update or delete/i, 'Lifecycle events must be append-only');
has(/event_kind text not null check\(event_kind in\('archived','reset','restored','recreation_authorized','recreation_consumed'\)\)/i, 'Immutable trail must cover every lifecycle transition');

has(/create or replace function public\.pdc_admin_vehicle_actor\(\)[\s\S]*auth\.uid\(\)[\s\S]*auth\.jwt\(\)->>'email'[\s\S]*r\.auth_user_id=v_uid[\s\S]*lower\(r\.email\)=v_email[\s\S]*r\.active and r\.account_status='approved'[\s\S]*v_role is distinct from 'administrator'/i, 'Authority must bind UUID/email to exact active approved Administrator');
has(/revoke all on function public\.pdc_admin_vehicle_actor\(\) from public,anon,authenticated,service_role/i, 'Internal actor helper must be fully revoked');
for (const fn of [
  'pdc_admin_archive_vehicle', 'pdc_admin_reset_staging_test_vehicle', 'pdc_admin_restore_vehicle',
  'pdc_admin_allow_vehicle_recreation_once', 'pdc_admin_archived_vehicle_snapshot',
]) {
  assert.ok(lower.includes(`function public.${fn}`), `${fn} must exist`);
}
has(/revoke all on function public\.pdc_admin_archive_vehicle[\s\S]*from public,anon,authenticated,service_role;[\s\S]*grant execute[\s\S]*to authenticated;/i, 'Public/anon/service role must have no lifecycle RPC execute; authenticated callers are role-checked');
assert.ok(!/grant execute[\s\S]*to (?:public|anon|service_role)/i.test(sql), 'No privileged lifecycle execute may be granted to public, anon, or service_role');

has(/length\(btrim\(coalesce\(p_reason,''\)\)\) not between 8 and 300/i, 'Archive reason must be required at 8-300 characters');
has(/p_confirmation_stock is distinct from v_stock/i, 'Archive confirmation must exactly equal canonical normalized stock');
has(/p_confirmation_stock is distinct from t\.normalized_stock/i, 'Restore/recreation confirmation must exactly equal tombstone normalized stock');
has(/'confirmation_stock_mismatch'/i, 'Confirmation mismatch must be a stable detail');

has(/update public\.workshop_bookings set deleted_at=v_now,deleted_reason=/i, 'Active workshop bookings must be archived, not deleted');
has(/insert into public\.workshop_booking_history[\s\S]*'vehicle_archived'/i, 'Booking archive history must be retained');
has(/update public\.vehicle_workshop_line_adjustments set active=false/i, 'Mutable overlays must be deactivated rather than deleted');
has(/update public\.navision_board_activations set active=false/i, 'Board activations must be deactivated rather than deleted');
for (const protectedTable of ['workshop_bookings', 'vehicle_work_items', 'vehicle_parts_updates', 'vehicle_workshop_line_adjustments', 'vehicle_sublet_providers', 'pdc_sublet_bookings', 'vehicle_movements', 'audit_events']) {
  assert.ok(!new RegExp(`delete\\s+from\\s+public\\.${protectedTable}`, 'i').test(sql), `${protectedTable} evidence must never be hard-deleted`);
}
assert.ok(!/purge_vehicle_from_board\s*\(/i.test(sql), 'Recoverable lifecycle must not call destructive migration-154 purge');

has(/create trigger pdc_vehicle_archive_recreation_gate before insert or update[\s\S]*on public\.vehicles/i, 'Vehicle INSERT/UPDATE tombstone gate must block automatic resurrection paths');
has(/new\.source_system[\s\S]*v_source<>'authenticated_email'/i, 'Only authenticated_email may consume recreation permission');
has(/for update;[\s\S]*update public\.pdc_vehicle_recreation_permissions set consumed_at=/i, 'One-use recreation permission must be consumed under row lock atomically');
has(/pdc_vehicle_recreation_one_open_idx[\s\S]*where consumed_at is null/i, 'Only one open permission may exist per tombstone');
has(/t\.tombstone_kind<>'staging_reset'[\s\S]*'manual_tombstone_restore_required'/i, 'Manual tombstones must require explicit restore');
has(/'recreation_authorization_required'|'PDC_RECREATION_AUTHORIZATION_REQUIRED'/i, 'Missing recreation permission must have a stable error');
has(/'recreation_authorization_expired'|'PDC_RECREATION_AUTHORIZATION_EXPIRED'/i, 'Expired recreation permission must have a stable error');
has(/'recreation_authorization_consumed'/i, 'Consumed recreation permission must have a stable error');

has(/update public\.vehicles set stock_number=t\.stock_number[\s\S]*where id=t\.vehicle_id returning/i, 'Restore must reactivate the original same UUID');
has(/active_workshop_booking_id=null/i, 'Restore must not reconnect an archived booking');
has(/'bookings_reactivated',false[\s\S]*'overlays_reactivated',false/i, 'Restore response/event must state that bookings and overlays remain archived');
assert.ok(!/update public\.workshop_bookings set deleted_at=null/i.test(sql), 'Restore must not reactivate archived bookings');
assert.ok(!/update public\.vehicle_workshop_line_adjustments set active=true/i.test(sql), 'Restore must not reactivate overlays');

for (const revision of ['pdc_email_vehicle_revision', 'navision_backend_revision']) {
  has(new RegExp(`update public\\.${revision} set revision=revision\\+1`, 'i'), `${revision} must be bumped`);
}
has(/perform public\.workshop_bump_revision\(\)/i, 'Workshop revision must be bumped');
has(/pg_publication_tables[\s\S]*tablename='vehicles'[\s\S]*alter publication supabase_realtime add table public\.vehicles/i, 'Vehicles publication must be guarded');
has(/pdc_admin_archived_vehicle_snapshot[\s\S]*vehicle_snapshot[\s\S]*lifecycle_events/i, 'Administrator archive snapshot must be server-side and include restore/audit evidence');

for (const fnBlock of sql.matchAll(/create or replace function public\.(pdc_[a-z0-9_]+)[\s\S]*?\$\$;/gi)) {
  if (['pdc_admin_vehicle_actor', 'pdc_vehicle_archive_recreation_gate', 'pdc_vehicle_archive_immutable', 'pdc_vehicle_recreation_permission_guard'].includes(fnBlock[1]) || fnBlock[1].startsWith('pdc_admin_')) {
    assert.ok(/security definer set search_path=pg_catalog,public/i.test(fnBlock[0]), `${fnBlock[1]} must pin a safe search_path`);
  }
}
assert.ok(!/exception when others then\s+return/i.test(sql), 'Unexpected database errors must not be swallowed into generic responses');

assert.ok(/version='205' and name='admin_recoverable_vehicle_archive'/i.test(sql206), 'Migration 206 must require exact predecessor 205');
assert.ok(/to_regclass\('public\.pdc_production_environment_sentinel'\) is not null/i.test(sql206), 'Migration 206 must fail closed outside staging');
assert.ok(/actor_email,vehicle_id,purged_booking_id\)/i.test(sql206), 'Migration 206 must preserve required Workshop history identity');
assert.ok(/values\('206','recoverable_archive_booking_history_identity'/i.test(sql206), 'Migration 206 ledger row missing');
assert.ok(/version='206' and name='recoverable_archive_booking_history_identity'/i.test(sql207), 'Migration 207 must require exact predecessor 206');
assert.ok(/returns jsonb language plpgsql volatile security definer/i.test(sql207), 'Migration 207 must make the row-locking actor helper VOLATILE');
assert.ok(/for share;/i.test(sql207), 'Migration 207 must retain the auth-bound role lock');
assert.ok(/values\('207','admin_vehicle_actor_lock_volatility'/i.test(sql207), 'Migration 207 ledger row missing');
assert.ok(/version='207' and name='admin_vehicle_actor_lock_volatility'/i.test(sql208), 'Migration 208 must require exact predecessor 207');
assert.ok(/pdc_admin_archived_vehicle_snapshot[\s\S]*returns jsonb language plpgsql volatile security definer/i.test(sql208), 'Migration 208 must make archived snapshot VOLATILE');
assert.ok(/revoke all on function public\.pdc_admin_archived_vehicle_snapshot\(uuid,integer\)/i.test(sql208), 'Migration 208 must reset snapshot ACL');
assert.ok(/grant execute on function public\.pdc_admin_archived_vehicle_snapshot\(uuid,integer\) to authenticated/i.test(sql208), 'Migration 208 must retain authenticated entry with internal Administrator validation');
assert.ok(/values\('208','archived_vehicle_snapshot_lock_volatility'/i.test(sql208), 'Migration 208 ledger row missing');

console.log('Migration 205 recoverable vehicle lifecycle and migrations 206-208 corrections contract tests passed.');
