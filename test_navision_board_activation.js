'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/migrations/053_navision_board_activation_and_display_fields.sql';
assert.ok(fs.existsSync(migrationPath), 'append-only Navision board activation migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8').toLowerCase();
const app = fs.readFileSync('app.js', 'utf8');
const service = fs.readFileSync('navision-backend-service.js', 'utf8');

assert.ok(sql.includes('create table if not exists public.navision_board_activations'), 'durable activation table must exist');
assert.ok(sql.includes('enable row level security'), 'activation table must enable RLS');
assert.ok(sql.includes('activate_navision_backend_record'), 'manual/email activation RPC must exist');
assert.ok(sql.includes("array['operator','importer','administrator']"), 'viewer must not activate vehicles');
assert.ok(sql.includes('p_expected_revision') && sql.includes('for update') && sql.includes('stale_revision'), 'activation must lock and compare the shared revision');
assert.ok(sql.includes("'manual'") && sql.includes("'approved_email_build'") && sql.includes("'approved_pd_document'"), 'activation source must be constrained to approved sources');
assert.ok(sql.includes("'board_activated'") && sql.includes("'activation_source'"), 'visible snapshot must expose durable activation state');
assert.ok(sql.includes("'customer_name'") && sql.includes("'salesperson'") && sql.includes("'model'") && sql.includes("'colour'"), 'approved Back End Data projection must expose requested display fields');
assert.ok(sql.includes("normalized_data ->> 'batch'"), 'Navision Batch must remain the Stock display authority');
assert.ok(sql.includes('activated_stock_number text not null') && sql.includes('activated_stock_number = nullif'), 'activation must be invalidated when the backend row changes to a different Batch identity');
assert.ok(!sql.includes("coalesce(nullif(normalized_data ->> 'batch', ''), nullif(normalized_data ->> 'stock'"), 'legacy Stock must not be a fallback for blank Batch');
assert.ok(!sql.includes("'toyota_order_number'"), 'visible shared projection must not expose Toyota order');
assert.ok(sql.includes('navisionrawevidence') && sql.includes("'salesperson'"), 'full salesperson must be recoverable from preserved original import evidence');
assert.ok(/revoke all on function public\.activate_navision_backend_record/.test(sql) && /grant execute on function public\.activate_navision_backend_record[\s\S]+to authenticated/.test(sql), 'activation RPC execution must be explicitly bounded');
assert.ok(!/grant\s+(select|insert|update|delete)[\s\S]+navision_board_activations[\s\S]+to authenticated/.test(sql), 'authenticated clients must not receive direct activation-table writes');

assert.ok(app.includes('item.board_activated === true'), 'Vehicle Locations must exclude unactivated shared imports');
assert.ok(app.includes('data-shared-backend-activate='), 'authorized staff need a Back End Data activation control');
assert.ok(app.includes('customer_name') && app.includes('salesperson'), 'shared display mapper must retain customer and salesperson');
assert.ok(app.includes('activateSharedNavisionForApprovedEmailReview'), 'approved build-email flow must use durable shared activation when a unique Navision row matches');
assert.ok(app.includes("activateSharedNavisionForApprovedDocumentReview(reviewed, 'approved_pd_document')"), 'approved PD Document review must activate one exact shared Batch match');
assert.ok(/function activateSharedNavisionForApprovedDocumentReview[\s\S]{0,500}?sharedNavisionVisibilityConfigured\(\)[\s\S]{0,180}?!sharedNavisionLocationAuthorityReady\(\)[\s\S]{0,180}?shared_authority_unavailable/.test(app), 'PD activation must fail closed until configured shared visibility and Realtime authority are ready');
assert.ok(app.includes("return cleanNavisionText(value).toUpperCase();"), 'shared Batch matching must preserve punctuation for exact matching');
assert.ok(app.includes('loadSharedNavisionVisibleRows({ force: true })'), 'successful activation must force an authoritative refresh rather than retain the pre-activation cache');
assert.ok(service.includes("call('activate_navision_backend_record'"), 'frontend service must call the protected activation RPC');

console.log('Navision durable board activation and requested display-field contract passed');
