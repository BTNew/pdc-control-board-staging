'use strict';
const fs = require('fs');
const { mapServerVehicle } = require('./pdc-email-vehicle-location-service.js');
function assert(value, message) { if (!value) throw new Error(message); }

const lines = [
  { operation_no: 'OP3', work_key: 'tyre', description: 'TYRE UPGRADE - BFG KO3 A/T X 6', source_uid: '1:193' },
  { operation_no: 'OP4', work_key: 'electrical', description: 'ULTRASONIC SHU ROO MK5 - MOUNTED TO BULL BAR', estimated_hours: '1.25', source_uid: '1:193' },
];
const mapped = mapServerVehicle({
  id: 'vehicle-1', stock_number: '13056899', visible_on_board: true,
  work_items: [{ work_key: 'tyre', required: true, completed: false }, { work_key: 'electrical', required: true, completed: false }],
  operation_lines: lines,
});
assert(Array.isArray(mapped.pdcEmailOperationLines) && mapped.pdcEmailOperationLines.length === 2, 'Authenticated operation lines must survive the server-to-card mapping');
assert(mapped.pdcEmailOperationLines[1].work_key === 'electrical', 'Operation lines must retain their canonical work key');
assert(mapped.pdcEmailOperationLines[1].estimatedHours === 1.25, 'Authenticated estimated hours must survive the server-to-card mapping as a finite number');
const pdMapped = mapServerVehicle({ operation_lines: [{ operation_no: 'PD003-A75EB7AE', work_key: 'fitting', description: 'Vehicle Pre-Delivery' }] });
assert(pdMapped.pdcEmailOperationLines.length === 1, 'Authenticated PD accessory line was not mapped');
assert(pdMapped.pdcEmailOperationLines[0].operation_no === 'PD003-A75EB7AE', 'Authenticated PD source-line key was not retained');

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
const exactReplay = fs.readFileSync('supabase/staging_only/095_authenticated_operation_exact_replay.sql', 'utf8').toLowerCase();
assert(exactReplay.includes("'operation_lines_already_imported'"), 'Exact operation replays need an explicit no-mutation receipt');
assert(exactReplay.indexOf('operation_lines_already_imported') < exactReplay.indexOf('return public.import_pdc_authenticated_email_operations_093_internal'), 'Exact replay must return before delegating to mutation statements');
assert(exactReplay.includes("'booking_created',false"), 'Exact replay receipt must state that no booking was created');

const snapshotRepair = fs.readFileSync('supabase/staging_only/097_authenticated_operation_snapshot.sql', 'utf8').toLowerCase();
assert(snapshotRepair.includes('create or replace function public.get_pdc_email_vehicle_location_snapshot()'), 'Migration 097 must reassert the deployed staging snapshot contract');
assert(snapshotRepair.includes("'operation_lines'"), 'Migration 097 snapshot must expose bounded authenticated operation lines');
assert(snapshotRepair.includes('from public.pdc_authenticated_email_operation_lines ol where ol.vehicle_id=v.id'), 'Migration 097 must source operation lines only from typed evidence for the exact vehicle');
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(snapshotRepair), 'Snapshot repair must never create bookings');
assert(!/update\s+public\.(vehicles|vehicle_work_items|workshop_bookings)/i.test(snapshotRepair), 'Snapshot repair must not mutate operational vehicle state');
const snapshotDeployer = fs.readFileSync('scripts/apply_migration_097_staging.py', 'utf8');
for (const required of ["EXPECTED_LEDGER_HEAD='096'", "VERSION='097'", 'ROLLBACK_ONLY', "'productionChanged':False", 'lock table supabase_migrations.schema_migrations in exclusive mode', "grantee='authenticated'"])
  assert(snapshotDeployer.includes(required), `Migration 097 deployer is missing ${required}`);

const pdMigration = fs.readFileSync('supabase/staging_only/099_authenticated_pd_accessory_lines.sql', 'utf8').toLowerCase();
for (const required of ['import_pdc_authenticated_email_pd_lines', '^pd[0-9]{3}-[a-f0-9]{8}$', 'limit 50', "'booking_created',false", "completed_work_reopened',false"])
  assert(pdMigration.includes(required), `Migration 099 is missing ${required}`);
assert(pdMigration.includes('operation_identity_conflict'), 'Migration 099 must return a deterministic fail-closed result for a changed replay using the same PD line key');
assert(pdMigration.includes("count(distinct x->>'operation_no')"), 'Migration 099 must reject duplicate PD line keys inside one request before any mutation');
assert(!/insert\s+into\s+public\.workshop_bookings/i.test(pdMigration), 'PD line import must never create a booking');
assert(!/set\s+completed\s*=\s*true/i.test(pdMigration), 'PD line import must never complete work');
const pdDeployer = fs.readFileSync('scripts/apply_migration_099_staging.py', 'utf8');
assert(pdDeployer.includes('applied migration ledger checksum/name mismatch'), 'Migration 099 runner must verify the recorded name and source checksum on an already-applied ledger row');
for (const required of ["expected_ledger_head='098'", "version='099'", 'rollback_only', 'operationalSignaturesUnchanged', "'productionChanged':False", 'lock table supabase_migrations.schema_migrations in exclusive mode'])
  assert(pdDeployer.toLowerCase().includes(required.toLowerCase()), `Migration 099 deployer is missing ${required}`);

const app = fs.readFileSync('app.js', 'utf8');
assert(app.includes('function authenticatedEmailOperationLinesHtml('), 'Vehicle cards must have a bounded operation-line renderer');
assert(app.includes('Operations from authenticated PD documents and job cards'), 'The card must label operation lines as authenticated job-card evidence');
assert(app.includes('pdcEmailOperationLines'), 'The card renderer must consume the mapped operation lines');
assert(app.includes('escapeHtml(operation.description'), 'Untrusted operation descriptions must be escaped');
assert(app.includes("operation.estimatedHours != null ? `${Number(operation.estimatedHours).toFixed(2)} h` : 'Hours not stated'"), 'Vehicle cards must render authenticated estimated hours with an explicit missing-hours fallback');
assert(app.includes('${authenticatedEmailOperationLinesHtml(vehicle)}'), 'The expanded vehicle card must render operation lines');

const staging = fs.readFileSync('staging.html', 'utf8');
const production = fs.readFileSync('index.html', 'utf8');
assert(staging.includes('pdc-email-vehicle-location-service.js'), 'Staging must load the authenticated email vehicle service');
assert(!production.includes('pdc-email-vehicle-location-service.js'), 'Production must remain isolated from the staging operation-line feature');
console.log('Authenticated email operation-line persistence, mapping, rendering and safety contract passed');
