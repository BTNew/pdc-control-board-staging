'use strict';

const assert = require('assert');
const fs = require('fs');

const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const migrationPath = 'supabase/staging_only/20260905010200_archived_snapshot_volatility_repair.sql';
const controllerPath = 'scripts/apply_archived_snapshot_volatility_repair_20260905.py';

assert.ok(fs.existsSync(migrationPath), 'archived snapshot volatility repair migration exists');
const migration = fs.readFileSync(migrationPath, 'utf8');
assert.match(migration, /create or replace function public\.pdc_admin_archived_vehicle_snapshot\(p_tombstone_id uuid default null,p_limit integer default 100\)[\s\S]*?returns jsonb language plpgsql volatile security definer/i);
assert.match(migration, /to_regprocedure\('public\.pdc_admin_archived_vehicle_snapshot\(uuid,integer\)'\)/i);
assert.match(migration, /order by version::bigint desc limit 1\) is distinct from '\(20260905010100,navision_projection_cleanup_evidence_parity\)'/i);
assert.match(migration, /provolatile='v'/i);
assert.match(migration, /grant execute on function public\.pdc_admin_archived_vehicle_snapshot\(uuid,integer\) to authenticated/i);
assert.match(migration, /has_function_privilege\('anon','public\.pdc_admin_archived_vehicle_snapshot\(uuid,integer\)','execute'\)/i);
assert.doesNotMatch(migration, /grant execute[\s\S]*to (?:anon|service_role)/i);
assert.ok(fs.existsSync(controllerPath), 'STAGING-only migration controller exists');
const controller = fs.readFileSync(controllerPath, 'utf8');
assert.match(controller, /STAGING_REF\s*!=\s*['"]cdsmnqxtyyoeoznmbidd['"]/);
assert.match(controller, /production_sentinel_present/);
assert.match(controller, /provolatile/);
assert.match(controller, /PDC_APPROVE_STAGING_MIGRATION_20260905010200/);

assert.match(app, /collected:\s*'Collected Vehicles'/);
assert.match(html, /data-view="ai-auditor"[^>]*title="Requires separately approved AI Auditor access"[^>]*>AI Auditor · Restricted<\/button>/);
assert.match(html, /class="nav-scroll-cue"[^>]*>Swipe navigation for more/);
assert.match(app, /class="table-scroll-cue"[^>]*>Swipe horizontally to view all columns/);
assert.match(css, /\.table-scroll-cue/);
assert.match(css, /\.nav-scroll-cue/);
assert.match(css, /\.parts-queue-table th:nth-child\(4\)[\s\S]*min-width:\s*190px/);

console.log('Overnight QA UI remediation contracts: PASS');
