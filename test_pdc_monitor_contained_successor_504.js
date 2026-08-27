'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const sql = fs.readFileSync(
  path.join(root, 'supabase', 'staging_only', '20260827052000_504_forward_reconcile_contained_email_runtime.sql'),
  'utf8',
).replace(/\r\n/g, '\n');

function includes(value, message) {
  assert.ok(sql.includes(value), message || `missing SQL contract: ${value}`);
}

const exactReviewedPair = {
  actor: 'df7c55d9-6ba0-47f6-ba16-44d6ae2c2a4b',
  gateway: 'pdc-monitor-staging-sales-uid509-v1',
  release: 'pdc-monitor-staging-m502-2026.08.44',
  source: 'e850c319989d98b45b95a28aa815d78e2c2e3a4b',
  manifest: 'd48b49f6598a99fbef99fc4f0d0ab36b8b47576b8ff7cd8ecd2cb64d6cfed58d',
  archive: '4ba4d827839f6dfe1835110719f0906a8b9345b0e41b653f96269abdeaccbf90',
};
const exactPredecessor = {
  source: '37a1fc0d83e0aa311cfb40b8c1804b9840922ea9',
  manifest: '5b84745badb9f7bf90690ae82196960ad51a19489c3c5c841b1a2019f42f67ca',
};

assert.match(sql, /^-- STAGING ONLY 504:/);
assert.strictEqual((sql.match(/^BEGIN;$/gm) || []).length, 1, 'migration has one transaction start');
assert.strictEqual((sql.match(/^COMMIT;$/gm) || []).length, 1, 'migration has one transaction commit');
assert.ok(sql.indexOf('BEGIN;') < sql.indexOf('COMMIT;'), 'transaction markers are ordered');

includes("project_ref='cdsmnqxtyyoeoznmbidd'");
includes("to_regclass('public.pdc_production_environment_sentinel') IS NOT NULL");
includes("provision_pdc_monitor_contained_binding_503(uuid,text,text,text,text)");
includes('PDC_504_STAGING_PREDECESSOR_OR_COLLISION_MISMATCH');
includes('LOCK TABLE supabase_migrations.schema_migrations IN EXCLUSIVE MODE');

for (const value of Object.values(exactReviewedPair)) includes(value, `reviewed pair is not exact: ${value}`);
for (const value of Object.values(exactPredecessor)) includes(value, `predecessor pair is not exact: ${value}`);
includes('migration_head integer NOT NULL CHECK(migration_head=503)');
includes("mode text NOT NULL CHECK(mode='contained')");
includes('PDC_504_REVIEWED_PAIR_MISMATCH');
includes('PDC_504_DEDICATED_MONITOR_IDENTITY_REQUIRED');
includes("coalesce(raw_app_meta_data->>'pdc_identity_type','')='non_human_monitor'");
includes("role::text='viewer'");
includes('PDC_504_CONTAINMENT_REQUIRED');
includes('PDC_504_EXACT_LEDGER_HEAD_REQUIRED');
includes('PDC_504_PREDECESSOR_FUNCTION_MARKER_MISMATCH');
includes('predecessor_ledger_sha256');
includes('predecessor_provision_function_sha256');
includes('predecessor_verify_function_sha256');
includes('predecessor_markers');
includes('source_tree_sha');
includes('8981540501bc629e189c39c9ea8a9adf3165d397');
assert.match(sql, /WHERE active AND revoked_at IS NULL/i, 'active writer checks include revoked-at containment');
includes("where singleton and (enabled or automatic_rule_application");

assert.ok(sql.includes('ENABLE ROW LEVEL SECURITY'), 'successor event table uses RLS');
assert.ok(sql.includes('FORCE ROW LEVEL SECURITY'), 'successor event table forces RLS');
assert.ok(sql.includes('REVOKE ALL ON public.pdc_monitor_contained_binding_reconciliations_504 FROM public,anon,authenticated,service_role'), 'direct table DML is denied');
assert.ok(sql.includes('PDC_504_RECONCILIATION_HISTORY_IMMUTABLE'), 'history update/delete is fail-closed');
assert.ok(!/\b(UPDATE|DELETE|TRUNCATE)\s+public\.pdc_monitor_contained_binding_reconciliations_504\b/i.test(sql), 'successor never overwrites or purges its event history');

includes('event_key text NOT NULL UNIQUE');
includes('WHERE event_key=v_event_key');
includes("'idempotent',true");
includes("'idempotent',false");
includes("'rollback_available',true");
includes("rollback_contract='transaction rollback only; predecessor 503 remains unchanged'");
includes("'production_untouched',true");
includes('INSERT INTO public.audit_events');

includes('CREATE FUNCTION public.reconcile_pdc_monitor_contained_binding_504(');
includes('GRANT EXECUTE ON FUNCTION public.reconcile_pdc_monitor_contained_binding_504');
includes('CREATE FUNCTION public.verify_pdc_monitor_contained_binding_504(');
includes('CREATE FUNCTION public.get_pdc_monitor_contained_binding_504()');
includes("'contained_reviewed_pair_mismatch'");
includes("'contained_successor_not_reconciled'");
includes("'operational',false");
includes("'activation_ready',false");
includes("'writer_active',false");
includes("'planner_commissioned',false");
includes("'production_writes',false");
includes("VALUES('504','504_forward_reconcile_contained_email_runtime'");

assert.ok(!/CREATE\s+EXTENSION/i.test(sql), 'migration does not change extensions');
assert.ok(!/INSERT\s+INTO\s+public\.(monitored_mailboxes|pdc_email_monitor_pilot|pdc_monitor_stage_activation_writers)/i.test(sql), 'migration does not enable runtime actors');
assert.ok(!/CREATE\s+TRIGGER[^;]+ON\s+public\.(vehicles|vehicle_work_items|workshop_bookings)/is.test(sql), 'migration does not add vehicle triggers');

console.log('PDC contained runtime 504 successor contract passed: exact reviewed pair, predecessor drift guard, append-only immutable RLS history, least-privilege RPCs, idempotency, rollback metadata, and fail-closed readiness');
