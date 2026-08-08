'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join('supabase', 'staging_only', '141_sublet_queued_rebind_and_concurrency_corrections.sql');
assert(fs.existsSync(migrationPath), 'Corrective migration 141 must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');
const lowerSql = sql.toLowerCase();
assert(lowerSql.includes("version='140' and name='sublet_return_calendar_and_workshop_availability'"), 'Migration 141 must require exact predecessor 140');
assert(/values\s*\(\s*'141'\s*,\s*'sublet_queued_rebind_and_concurrency_corrections'/i.test(sql), 'Migration 141 ledger entry must be exact');
assert((sql.match(/'queued','planned','started','stoppage'/g) || []).length >= 3, 'Queued must be active in both guards and overlap postconditions');
assert(lowerSql.includes('update of vehicle_id,booking_date,expected_return_date,actual_return_date'), 'Reverse trigger must fire on vehicle reassignment');
assert(sql.includes("least(old.vehicle_id::text,new.vehicle_id::text)") && sql.includes("greatest(old.vehicle_id::text,new.vehicle_id::text)"), 'Vehicle reassignment must lock old and new identities deterministically');
assert(sql.includes("'workshop_booking_conflict'"), 'Reverse conflict must retain its canonical code');

const app = fs.readFileSync('app.js', 'utf8');
const today = app.slice(app.indexOf('function subletTodayDateKey('), app.indexOf('function subletCalendarRange('));
assert(today.includes("timeZone: 'Australia/Perth'"), 'Returned must use the authoritative Perth business date');
assert(today.includes('formatToParts'), 'Perth date formatting must not depend on browser-local date getters');

const installerPath = path.join('supabase', 'staging_only', 'install_migration_141.py');
assert(fs.existsSync(installerPath), 'Migration 141 requires a durable guarded installer');
const installer = fs.readFileSync(installerPath, 'utf8');
assert(!installer.includes('--expected-commit'), 'Installer must not trust a caller-selected source commit');
assert(installer.includes('EXPECTED_BACKUP_RECEIPT_SHA256'), 'Installer must pin a trusted restore-verification receipt');
assert(installer.includes('EXPECTED_SOURCE_BUNDLE_SHA256'), 'Installer must pin the reviewed source bundle');
assert(installer.includes('APPLY-STAGING-MIGRATION-141'), 'Apply requires a run-specific explicit staging confirmation');
assert(installer.includes('backupRelations') && installer.includes('foreignKeyViolations') && installer.includes('restoreSchemaCleanupVerified'), 'Receipt must establish inventory, FK and cleanup evidence');

console.log('Sublet delayed-review correction contracts passed');