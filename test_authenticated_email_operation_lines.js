'use strict';
const fs = require('fs');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');
function assert(value, message) { if (!value) throw new Error(message); }

const lines = [
  { operation_no: 'OP3', work_key: 'tyre', description: 'TYRE UPGRADE - BFG KO3 A/T X 6', source_uid: '1:193' },
  { operation_no: 'OP4', work_key: 'electrical', description: 'ULTRASONIC SHU ROO MK5 - MOUNTED TO BULL BAR', source_uid: '1:193' },
];
const mapped = mapServerVehicle({
  id: 'vehicle-1', stock_number: '13056899', visible_on_board: true,
  work_items: [{ work_key: 'tyre', required: true, completed: false }, { work_key: 'electrical', required: true, completed: false }],
  operation_lines: lines,
});
assert(Array.isArray(mapped.pdcEmailOperationLines) && mapped.pdcEmailOperationLines.length === 2, 'Authenticated operation lines must survive the server-to-card mapping');
assert(mapped.pdcEmailOperationLines[1].work_key === 'electrical', 'Operation lines must retain their canonical work key');

const sql = fs.readFileSync('supabase/staging_only/093_authenticated_email_operation_lines.sql', 'utf8').toLowerCase();
for (const required of [
  'pdc_authenticated_email_operation_lines',
  'operation_no',
  'operation_fingerprint',
  'jsonb_array_length(v_operations)>50',
  "work_key in ('bus4x4','tint','hoist','fitting','fabrication','electrical','tyre','pitinspection','parts')",
  'on conflict(source_hash,operation_fingerprint) do nothing',
  "'operation_lines'",
  'booking_created',
]) assert(sql.includes(required), `Migration 093 is missing ${required}`);
assert(!sql.includes("work_key in ('sublet'"), 'PMG accounting Sublet must not become a PDC Sublet operation');
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(sql), 'Operation evidence import must never create a booking');
assert(!/update\s+public\.vehicle_work_items\s+set\s+completed/i.test(sql), 'Operation evidence import must never complete work');

const deployer = fs.readFileSync('scripts/apply_migration_093_staging.py', 'utf8');
for (const required of [
  'conn.autocommit = False', 'insert into supabase_migrations.schema_migrations',
  "EXPECTED_LEDGER_HEAD = '072'", 'conn.rollback()', "'productionChanged': False",
]) assert(deployer.includes(required), `Migration 093 deployer is missing ${required}`);
const backup = fs.readFileSync('scripts/pdc_backup.py', 'utf8');
assert(backup.includes("MIGRATION_093_BACKUP_TABLES = frozenset({'pdc_authenticated_email_operation_lines'})"), 'Migration 093 evidence must be in ledger-gated backup inventory');
assert(backup.includes('if number >= 93:'), 'Backup must require operation evidence at migration 093');

const replayRevision = fs.readFileSync('supabase/staging_only/094_authenticated_operation_replay_revision.sql', 'utf8').toLowerCase();
assert(replayRevision.includes('for each row execute function public.bump_pdc_email_vehicle_revision()'), 'Exact operation replays must not bump revision without an inserted row');
assert(!replayRevision.includes('for each statement execute function public.bump_pdc_email_vehicle_revision()'), 'Operation evidence revision trigger must not be statement-level');

const app = fs.readFileSync('app.js', 'utf8');
assert(app.includes('function authenticatedEmailOperationLinesHtml('), 'Vehicle cards must have a bounded operation-line renderer');
assert(app.includes('Operations from authenticated job cards'), 'The card must label operation lines as authenticated job-card evidence');
assert(app.includes('pdcEmailOperationLines'), 'The card renderer must consume the mapped operation lines');
assert(app.includes('escapeHtml(operation.description'), 'Untrusted operation descriptions must be escaped');
assert(app.includes('${authenticatedEmailOperationLinesHtml(vehicle)}'), 'The expanded vehicle card must render operation lines');

const staging = fs.readFileSync('staging.html', 'utf8');
const production = fs.readFileSync('index.html', 'utf8');
assert(staging.includes('pdc-email-vehicle-location-service.js'), 'Staging must load the authenticated email vehicle service');
assert(!production.includes('pdc-email-vehicle-location-service.js'), 'Production must remain isolated from the staging operation-line feature');
console.log('Authenticated email operation-line persistence, mapping, rendering and safety contract passed');
