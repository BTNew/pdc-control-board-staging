'use strict';
const fs = require('fs');
function assert(value, message) { if (!value) throw new Error(message); }
const app = fs.readFileSync('app.js', 'utf8');
const css = fs.readFileSync('styles.css', 'utf8');
const sql = fs.readFileSync('supabase/staging_only/092_vehicle_provenance_and_detailed_history.sql', 'utf8');
assert(app.includes("actionLabel: 'Source / next step'"), 'Vehicle Locations must label source/access rather than generic Actions');
assert(app.includes("'Imported by email · Read only'") && app.includes("'Navision source · Read only'"), 'Read-only authority badges must explain source');
assert(!app.includes('<div class="detail-metrics">'), 'Redundant vehicle detail metrics panel must be removed');
assert(css.includes('grid-template-columns: repeat(9, minmax(52px, 1fr))'), 'Required Work controls must use one compact nine-cell row');
assert(css.includes('min-height: 40px !important') && css.includes('.pdc-work-state-required .pdc-work-state-code::after'), 'Required Work controls must use compact Vehicle-Locations-style states');
assert(app.includes('How this vehicle was imported') && app.includes('Detailed history'), 'Vehicle card must expose provenance and detailed history');
assert(app.includes('authoritativeAuditChangeSummary') && app.includes("action: 'Vehicle moved'"), 'Detailed audit renderer must show changed fields and movements');
assert(sql.includes('PDC_STAGING_SENTINEL_MISMATCH') && sql.includes('security definer'), 'History RPC must be staging guarded and protected');
assert(sql.includes('pdc_authenticated_email_import_receipts') && sql.includes('navision_import_batches') && sql.includes('audit_events') && sql.includes('vehicle_movements'), 'History RPC must combine import receipts, Navision batches, audit events and movements');
assert(sql.includes('limit 100') && sql.includes('grant execute') && sql.includes('to authenticated'), 'History must be bounded and authenticated');
console.log('Vehicle source label, compact details/work controls, and authoritative provenance history contract passed');
