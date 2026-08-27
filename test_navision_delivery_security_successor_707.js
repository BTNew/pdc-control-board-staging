'use strict';

const assert = require('assert');
const fs = require('fs');

const migrationPath = 'supabase/staging_only/20260827109100_707_navision_delivery_monitor_identity_security_successor.sql';
const migration = fs.existsSync(migrationPath) ? fs.readFileSync(migrationPath, 'utf8') : '';
const lower = migration.toLowerCase();
const service = fs.readFileSync('pdc-email-vehicle-location-service.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

assert.ok(migration, '707 append-only staging successor exists');
assert.strictEqual((migration.match(/^BEGIN;$/gm) || []).length, 1, 'one transaction');
assert.strictEqual((migration.match(/^COMMIT;$/gm) || []).length, 1, 'one commit');
assert.ok(lower.includes('20260827109000'), 'exact live ledger head is required');
assert.ok(lower.includes('706_final_booked_synthetic_payload_identity_repair_after_673_collision'), 'exact 706 predecessor is required');
assert.ok(lower.includes('675_authenticated_monitor_enqueue_trigger_compatibility'), 'exact live 675 predecessor is required');
assert.ok(!/\bdrop\s+(?:table|function|trigger)\b/i.test(migration), 'successor does not drop applied objects');
assert.ok(!/\bdelete\s+from\b/i.test(migration), 'successor does not delete applied evidence');
assert.ok(!lower.includes('vjdtsswhroyguxyfjdkt'), 'production project reference is absent');

assert.match(migration, /alter\s+function\s+public\.reconcile_navision_delivery_700\(uuid,uuid,text\)\s+rename\s+to\s+reconcile_navision_delivery_700_pre707/i);
assert.match(migration, /revoke\s+all\s+on\s+function\s+public\.reconcile_navision_delivery_700_pre707\(uuid,uuid,text\)/i);
assert.match(migration, /create\s+function\s+public\.reconcile_navision_delivery_700\(p_backend_record_id\s+uuid\)/i);
assert.match(migration, /public\.pdc_monitor_authenticated_active_scope_673\(null\)/i);
assert.match(migration, /auth\.uid\(\)/i);
assert.match(migration, /auth\.jwt\(\)->>'email'/i);
assert.match(migration, /grant\s+execute\s+on\s+function\s+public\.reconcile_navision_delivery_700\(uuid\)\s+to\s+authenticated/i);
assert.match(migration, /revoke\s+all\s+on\s+function\s+public\.reconcile_navision_delivery_700\(uuid\)\s+from\s+public,anon,authenticated,service_role,pdc_email_monitor/i);
assert.match(migration, /has_function_privilege\('authenticated','public\.reconcile_navision_delivery_700\(uuid\)','execute'\)/i);
assert.match(migration, /has_function_privilege\('anon','public\.reconcile_navision_delivery_700\(uuid\)','execute'\)/i);
assert.match(migration, /has_function_privilege\('service_role','public\.reconcile_navision_delivery_700\(uuid\)','execute'\)/i);
assert.match(migration, /has_function_privilege\('pdc_email_monitor','public\.reconcile_navision_delivery_700\(uuid\)','execute'\)/i);

const wrapperStart = lower.indexOf('create function public.reconcile_navision_operational_record(');
assert.ok(wrapperStart >= 0, 'replacement operational wrapper exists');
const wrapperEnd = migration.indexOf('$wrapper$;', wrapperStart);
assert.ok(wrapperEnd > wrapperStart, 'replacement wrapper body is delimited');
const wrapper = migration.slice(wrapperStart, wrapperEnd);
assert.match(wrapper, /p_actor_id\s+is\s+not\s+null\s+and\s+p_actor_id\s+is\s+distinct\s+from\s+v_uid/i);
assert.match(wrapper, /p_actor_email\s+is\s+not\s+null\s+and\s+lower\(btrim\(p_actor_email\)\)\s+is\s+distinct\s+from\s+v_email/i);
assert.match(wrapper, /reconcile_navision_delivery_700\(p_backend_record_id\)/i);
assert.ok(!/reconcile_navision_delivery_700\(p_backend_record_id\s*,/i.test(wrapper), 'wrapper cannot forward caller actor values');
assert.match(wrapper, /reconcile_navision_operational_record_pre707\(p_backend_record_id\s*,v_uid,v_email\)/i);
assert.match(migration, /revoke\s+all\s+on\s+function\s+public\.reconcile_navision_operational_record\(uuid,uuid,text\)/i);
assert.match(migration, /grant\s+execute\s+on\s+function\s+public\.reconcile_navision_operational_record\(uuid,uuid,text\)\s+to\s+authenticated/i);

assert.ok(!/reconcileNavisionDelivery700/.test(service), 'browser service no longer exports direct delivery reconciliation');
assert.ok(!/PDC_FINAL_NAVISION_DELIVERY_RPC/.test(service), 'browser service has no direct delivery RPC constant');
assert.match(html, /navision-delivery-security=2026\.08\.27\.707-708/);

console.log('707 Navision delivery security successor contract passed');
