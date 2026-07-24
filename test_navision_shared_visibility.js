'use strict';

const fs = require('fs');
const assert = require('assert');

const migrationPath = 'supabase/migrations/053_navision_board_activation_and_display_fields.sql';
assert.ok(fs.existsSync(migrationPath), 'effective shared visibility and activation migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const baselineSql = fs.readFileSync('supabase/migrations/047_shared_navision_approved_user_visibility.sql', 'utf8').toLowerCase();
const app = fs.readFileSync('app.js', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

assert.ok(sql.includes('get_navision_visible_snapshot'), 'restricted visible snapshot RPC exists');
assert.ok(sql.includes("array['viewer','operator','importer','administrator']"), 'every approved signed-in role can call the restricted view');
assert.ok(sql.includes('security definer') && sql.includes('set search_path = pg_catalog, public, extensions'), 'restricted view has a fixed security-definer boundary');
assert.ok(/grant execute on function public\.get_navision_visible_snapshot\(text,\s*text,\s*uuid,\s*integer,\s*bigint\)\s+to authenticated/.test(sql), 'only authenticated callers receive RPC execute');
assert.ok(/revoke all on function public\.get_navision_visible_snapshot\([^)]+\)\s+from public, anon, authenticated/.test(sql), 'RPC replacement clears inherited/default execution before the authenticated grant');
assert.ok(sql.includes("'stock_number'") && sql.includes("'customer_name'") && sql.includes("'salesperson'") && sql.includes("'model'") && sql.includes("'colour'") && sql.includes("'vehicle_status'") && sql.includes("'eta_to_kewdale'"), 'approved staff output contains the requested vehicle display fields');
assert.ok(!sql.includes("'toyota_order_number'"), 'approved staff output must not expose Toyota order');
assert.ok(!sql.includes("'vin'") && !sql.includes("'normalized_data',") && !sql.includes("'raw_evidence'"), 'approved display output still excludes VIN and complete source payloads');
assert.ok(!/\b(insert|update|delete)\s+(into\s+)?public\.vehicles\b/.test(sql), 'visibility migration does not mutate operational vehicle authority');
assert.ok(baselineSql.includes('navision_backend_revision_approved_read'), 'all approved sessions can receive the revision-only realtime signal');
assert.ok(sql.includes('select id from selected order by id desc limit 1') && !sql.includes('max(id)'), 'UUID pagination cursor uses deterministic ordering instead of unsupported max(uuid)');

assert.ok(app.includes('async function loadSharedNavisionVisibleRows('), 'UI loads shared imports from the restricted RPC');
assert.ok(app.includes("state: 'Shared Navision'"), 'shared imported rows are visibly identified and read-only');
assert.ok(app.includes('subscribeSharedNavisionVisibility'), 'open sessions refresh from the revision signal after another user imports');
assert.ok(app.includes('sharedNavisionVisibleRows'), 'shared rows are held in session state, not browser-local authority');
assert.ok(staging.includes('<option value="shared">Shared Navision imports</option>'), 'staging filter can isolate shared imports');
assert.ok(index.includes('<option value="shared">Shared Navision imports</option>'), 'production-shaped HTML remains structurally in parity');
assert.ok(staging.includes('id="backend-data-refresh-shared"'), 'staff have an explicit shared refresh control');
assert.ok(app.includes('subscribeSharedNavisionVisibility') && app.includes("table: 'navision_backend_revision'"), 'open staff browsers subscribe to revision changes');
assert.ok(app.includes("loadSharedNavisionVisibleRows({ force: true });") && !app.includes("if (app.currentView === 'backend') loadSharedNavisionVisibleRows"), 'every authenticated view refreshes the shared Navision snapshot instead of limiting it to Back End Data');
assert.ok(app.includes('vehicleLocationBoardRows()') && app.includes('item.board_activated === true') && app.includes('__sharedNavisionReadOnly'), 'Locations excludes unactivated imports and exposes only durably activated shared-only rows');
assert.ok(app.includes('Shared Navision locations online') && app.includes('synchronized across signed-in computers') && app.includes("sharedNavisionVisibleRealtimeState === 'subscribed'") && app.includes('sharedNavisionVisibleRealtimeReconciled === true'), 'Locations claims cross-computer synchronization only after Realtime ownership and its reconciliation snapshot are both proven');
assert.ok(app.includes("status === 'SUBSCRIBED'") && app.includes("status === 'CHANNEL_ERROR'") && app.includes("status === 'TIMED_OUT'") && app.includes("status === 'CLOSED'"), 'Realtime lifecycle proves subscription health and handles every failure boundary');
assert.ok(app.includes('firstHealthySubscription') && app.includes('loadSharedNavisionVisibleRows({ force: true })'), 'a post-subscribe snapshot reconciliation closes the load-before-subscribe race');
const sharedSubscribeStart = app.indexOf('function subscribeSharedNavisionVisibility');
const subscribedLifecycleStart = app.indexOf("if (status === 'SUBSCRIBED')", sharedSubscribeStart);
const subscribedLifecycle = app.slice(subscribedLifecycleStart, app.indexOf('async function loadSharedNavisionVisibleRows', subscribedLifecycleStart));
assert.ok(subscribedLifecycle.includes('sharedNavisionVisibleStableTimer = setTimeout') && subscribedLifecycle.indexOf('sharedNavisionVisibleReconnectAttempt = 0') > subscribedLifecycle.indexOf('sharedNavisionVisibleStableTimer = setTimeout') && subscribedLifecycle.includes('}, 10000);'), 'short-lived SUBSCRIBED/CLOSED flapping must retain exponential backoff until a stable-health interval completes');
assert.ok(app.includes('scheduleSharedNavisionVisibilityReconnect') && app.includes('sharedNavisionVisibleRealtimeGeneration'), 'failed and stale Realtime channels are generation-bound and reconnect with a bounded lifecycle');
assert.ok(app.includes('sharedNavisionVisibilityConfigured()') && app.includes("app.sharedNavisionVisibleState = 'idle'"), 'unsupported entry points keep shared visibility dormant instead of showing a false outage');
assert.ok(app.includes('sharedNavisionVisibleGeneration += 1'), 'auth lock invalidates shared snapshot generations');
assert.ok(app.includes('sharedNavisionVisibleRows = []') && app.includes('releaseSharedNavisionVisibilityChannel()') && app.includes('clearSharedNavisionVisibilityReconnectTimer()'), 'auth lock clears imported rows, timers and Realtime ownership');
assert.ok(app.includes('data-shared-backend-activate=') && app.includes('navisionBoardActivationRoleAllowed'), 'authorized staff can explicitly activate a Back End Data row through the protected shared RPC');
assert.ok(app.includes('vehicleCustomerName(v)') && app.includes('consultantName(v)') && app.includes('Stock (Batch)'), 'Back End Data displays customer, salesperson and explicit Batch-as-Stock semantics');

console.log('Shared Navision approved-user visibility and read-only authority boundary checks passed');
