'use strict';

const fs = require('fs');
const assert = require('assert');

const migrationPath = 'supabase/migrations/047_shared_navision_approved_user_visibility.sql';
assert.ok(fs.existsSync(migrationPath), 'additive shared visibility migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const app = fs.readFileSync('app.js', 'utf8');
const staging = fs.readFileSync('staging.html', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');

assert.ok(sql.includes('get_navision_visible_snapshot'), 'restricted visible snapshot RPC exists');
assert.ok(sql.includes("array['viewer','operator','importer','administrator']"), 'every approved signed-in role can call the restricted view');
assert.ok(sql.includes('security definer') && sql.includes('set search_path = pg_catalog, public, extensions'), 'restricted view has a fixed security-definer boundary');
assert.ok(/grant execute on function public\.get_navision_visible_snapshot\(text,\s*text,\s*uuid,\s*integer,\s*bigint\)\s+to authenticated/.test(sql), 'only authenticated callers receive RPC execute');
assert.ok(/revoke all on function public\.get_navision_visible_snapshot\([^)]+\)\s+from public, anon, authenticated/.test(sql), 'RPC replacement clears inherited/default execution before the authenticated grant');
assert.ok(sql.includes("'stock_number'") && sql.includes("'toyota_order_number'") && sql.includes("'model'") && sql.includes("'colour'") && sql.includes("'vehicle_status'") && sql.includes("'eta_to_kewdale'"), 'restricted output contains useful non-sensitive vehicle display fields');
assert.ok(!sql.includes("'customer'") && !sql.includes("'vin'") && !sql.includes("'normalized_data',") && !sql.includes("'raw_evidence'"), 'restricted output excludes customer, VIN and full source payloads');
assert.ok(!/\b(insert|update|delete)\s+(into\s+)?public\.vehicles\b/.test(sql), 'visibility migration does not mutate operational vehicle authority');
assert.ok(sql.includes('navision_backend_revision_approved_read'), 'all approved sessions can receive the revision-only realtime signal');
assert.ok(sql.includes('select id from selected order by id desc limit 1') && !sql.includes('max(id)'), 'UUID pagination cursor uses deterministic ordering instead of unsupported max(uuid)');

assert.ok(app.includes('async function loadSharedNavisionVisibleRows('), 'UI loads shared imports from the restricted RPC');
assert.ok(app.includes("state: 'Shared Navision'"), 'shared imported rows are visibly identified and read-only');
assert.ok(app.includes('subscribeSharedNavisionVisibility'), 'open sessions refresh from the revision signal after another user imports');
assert.ok(app.includes('sharedNavisionVisibleRows'), 'shared rows are held in session state, not browser-local authority');
assert.ok(staging.includes('<option value="shared">Shared Navision imports</option>'), 'staging filter can isolate shared imports');
assert.ok(index.includes('<option value="shared">Shared Navision imports</option>'), 'production-shaped HTML remains structurally in parity');
assert.ok(staging.includes('id="backend-data-refresh-shared"'), 'staff have an explicit shared refresh control');
assert.ok(app.includes('subscribeSharedNavisionVisibility') && app.includes("table: 'navision_backend_revision'"), 'open staff browsers subscribe to revision changes');
assert.ok(app.includes("if (app.currentView === 'backend') loadSharedNavisionVisibleRows({ force: true });") && app.includes('sharedNavisionVisibleGeneration += 1'), 'auth-ready refresh and auth-lock generation invalidation are wired');
assert.ok(app.includes('sharedNavisionVisibleRows = []') && app.includes('removeChannel(app.sharedNavisionVisibleRealtime)'), 'auth lock clears imported rows and tears down Realtime');
assert.ok(app.includes("'<span class=\"badge neutral\">Read only</span>'"), 'shared imported rows cannot invoke browser-local or operational actions');
assert.ok(app.includes('Restricted online view'), 'shared rows make excluded personal details explicit instead of displaying misleading customer data');

console.log('Shared Navision approved-user visibility and read-only authority boundary checks passed');
