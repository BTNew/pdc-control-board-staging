'use strict';

const assert = require('assert');
const fs = require('fs');

const migration = fs.readFileSync('supabase/staging_only/20260827110100_708_navision_delivery_scope_674_alignment_successor.sql', 'utf8');
const lower = migration.toLowerCase();

assert.match(migration, /^-- STAGING ONLY 708:/);
assert.match(migration, /20260827109100/);
assert.match(migration, /707_navision_delivery_monitor_identity_security_successor/);
assert.match(migration, /20260827109000/);
assert.match(migration, /675_authenticated_monitor_enqueue_trigger_compatibility/);
assert.match(migration, /20260827110000/);
assert.match(migration, /676_authenticated_monitor_rollback_control_repair/);
assert.match(migration, /pdc_monitor_authenticated_active_scope_673/);
assert.match(migration, /pdc_monitor_authenticated_active_scope_674/);
assert.match(migration, /pg_get_functiondef\('public\.reconcile_navision_delivery_700\(uuid\)'::regprocedure\)/i);
assert.match(migration, /pg_get_functiondef\('public\.reconcile_navision_operational_record\(uuid,uuid,text\)'::regprocedure\)/i);
assert.match(migration, /length\(v_delivery\)-length\(replace\(v_delivery,v_old,''\)\)/i);
assert.match(migration, /length\(v_wrapper\)-length\(replace\(v_wrapper,v_old,''\)\)/i);
assert.match(migration, /replace\(v_delivery,v_old,v_new\)/i);
assert.match(migration, /replace\(v_wrapper,v_old,v_new\)/i);
assert.match(migration, /position\(v_new in v_delivery\)/i);
assert.ok(!/\bdrop\s+(?:table|function|trigger)\b/i.test(migration));
assert.ok(!/\bdelete\s+from\b/i.test(migration));
assert.ok(!lower.includes('vjdtsswhroyguxyfjdkt'));
assert.strictEqual((migration.match(/^BEGIN;$/gm) || []).length, 1);
assert.strictEqual((migration.match(/^COMMIT;$/gm) || []).length, 1);
console.log('708 Navision delivery scope alignment successor contract passed');
