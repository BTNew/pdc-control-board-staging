'use strict';
const assert = require('assert');
const fs = require('fs');
const { buildWorkshopSharedActions } = require('./workshop-shared-actions.js');
const dataService = require('./workshop-data-service.js');

const sql = fs.readFileSync('supabase/staging_only/170_authoritative_workshop_admin_blocks.sql', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const css = fs.readFileSync('workshop-planner.css', 'utf8');
const backup = fs.readFileSync('scripts/pdc_backup.py', 'utf8');
let count = 0;
const ok = (condition, message) => { assert.ok(condition, message); count += 1; };

ok(sql.includes("version='169' and name='vehicle_location_latches_and_milestones'"), '170 requires exact Migration 169');
ok(sql.includes("version~'^[0-9]+$' and version::numeric>169"), '170 rejects an out-of-order ledger tip');
ok(sql.includes("values('170','authoritative_workshop_admin_blocks'"), '170 records its exact ledger identity');
for (const table of ['workshop_admin_blocks', 'workshop_admin_block_history', 'workshop_admin_block_receipts']) {
  ok(sql.includes(`create table public.${table}`), `${table} is created`);
  ok(sql.includes(`alter table public.${table} enable row level security`), `${table} has RLS enabled`);
  ok(backup.includes(`"${table}"`) && backup.includes(`'${table}'`), `${table} is in ordered and ledger-versioned backup inventories`);
}
ok(sql.includes("public.is_pdc_role('administrator')"), 'direct table visibility is administrator-only');
ok((sql.match(/perform public\.require_pdc_role\('administrator'\)/g) || []).length === 4, 'all four public mutation RPCs require administrator authority');
for (const rpc of ['create_workshop_admin_block', 'move_workshop_admin_block', 'resize_workshop_admin_block', 'delete_workshop_admin_block']) {
  ok(sql.includes(`create function public.${rpc}(`), `${rpc} is defined`);
  ok(sql.includes(`comment on function public.${rpc}(`), `${rpc} has an operational contract comment`);
  ok(dataService.WORKSHOP_MUTATION_RPCS.includes(rpc), `${rpc} is allow-listed by the shared service`);
}
ok(sql.includes('workshop_admin_block_history_immutable') && sql.includes('workshop_admin_block_receipts_immutable'), 'history and receipts are append-only');
ok(sql.includes('workshop_lock_resources') && sql.includes('exact same physical-bay advisory-lock namespace'), 'Admin blocks share the canonical workshop-bay lock namespace');
ok(sql.includes('workshop_calendar_minute_available') && sql.includes('workshop_add_operational_minutes') && sql.includes('workshop_operational_minutes_between'), 'interval validation uses canonical operational-minute functions');
ok(sql.includes('workshop_bookings_admin_block_conflict') && sql.includes("'admin_block_conflict'"), 'reverse booking trigger prevents ordinary scheduling through a block');
const repack = sql.slice(sql.indexOf('create function public.workshop_admin_repack_planned('), sql.indexOf('create function public.workshop_admin_write_evidence('));
ok(repack.includes("b.status='planned'"), 'repack selects only planned rows');
ok(repack.includes("b.status in ('queued','started','stoppage','completed')"), 'queued/started/stoppage/completed rows are fixed obstacles');
ok(!/update public\.workshop_bookings[\s\S]*status\s+in\s*\('queued','started','stoppage','completed'\)/.test(repack), 'fixed states are never UPDATE targets');
ok(sql.includes("'admin_blocks'") && sql.includes('get_station_workshop_snapshot_pre_170'), 'station snapshot includes authoritative Admin blocks');
ok(sql.includes('get_workshop_snapshot_pre_170') && sql.includes("'admin_blocks'"), 'combined snapshot includes authoritative Admin blocks');
ok((sql.match(/workshop_bump_revision\(\)/g) || []).length >= 5 && (sql.match(/workshop_bump_station_revision/g) || []).length >= 5, 'mutations invalidate global and station snapshots transactionally');
ok(!sql.includes('alter publication supabase_realtime add table public.workshop_admin_blocks'), 'no duplicate Realtime channel/table stream is introduced');
ok(planner.includes('function workshopAdminBlockCanMutate(') && planner.includes("=== 'administrator'"), 'planner mutation UX mirrors administrator authority');
ok(planner.includes('Array.isArray(snapshot?.admin_blocks)'), 'planner normalizes Admin blocks from the trusted snapshot');
ok(planner.includes('data-workshop-add-admin-block') && planner.includes('data-workshop-admin-block-id'), 'toolbar and block interactions are wired');
ok(css.includes('.workshop-admin-block') && css.includes('background: #ffd84d'), 'yellow block CSS is integrated into the canonical planner stylesheet');
ok(!fs.existsSync('admin-block-styles.tmp'), 'temporary CSS file was removed after integration');

(async () => {
  const calls = [];
  const actions = buildWorkshopSharedActions({ mutate: async (name, params) => { calls.push({ name, params }); return { ok: true }; } });
  await actions.createAdminBlock({ expectedRevision: 12, stageCode: 'HOIST', bayNumber: 2, blockType: 'training', label: 'Training', scheduledStartAt: '2026-08-12T01:00:00Z', durationMinutes: 60, metadata: { source: 'test' } });
  await actions.moveAdminBlock({ blockId: 'a', expectedVersion: 1, stageCode: 'FITTING', bayNumber: 3, scheduledStartAt: '2026-08-12T02:00:00Z' });
  await actions.resizeAdminBlock({ blockId: 'a', expectedVersion: 2, durationMinutes: 90 });
  await actions.deleteAdminBlock({ blockId: 'a', expectedVersion: 3, reason: 'Done' });
  assert.deepStrictEqual(calls.map(call => call.name), ['create_workshop_admin_block', 'move_workshop_admin_block', 'resize_workshop_admin_block', 'delete_workshop_admin_block']);
  assert.strictEqual(calls[0].params.p_expected_revision, 12);
  assert.strictEqual(calls[1].params.p_expected_version, 1);
  assert.strictEqual(calls[2].params.p_duration_minutes, 90);
  assert.strictEqual(calls[3].params.p_reason, 'Done');
  console.log(`Authoritative Admin block migration/UI contracts passed (${count} static assertions + action mapping)`);
})().catch(error => { console.error(error); process.exitCode = 1; });
