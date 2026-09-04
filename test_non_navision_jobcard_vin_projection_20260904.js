'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const migrationPath = path.join(
  __dirname,
  'supabase/staging_only/20260904010800_non_navision_jobcard_vin_projection.sql',
);
assert.ok(fs.existsSync(migrationPath), 'append-only VIN projection migration must exist');
const sql = fs.readFileSync(migrationPath, 'utf8');

for (const marker of [
  "project_ref='cdsmnqxtyyoeoznmbidd'",
  "v_head IS DISTINCT FROM '20260904010700'",
  'pdc_non_navision_vin_projection_receipts_20260904',
  'project_pdc_non_navision_jobcard_vin_20260904',
  'read_pdc_non_navision_vin_projection_20260904',
  'p_expected_vehicle_version',
  'p_source_receipt_id',
  'p_expected_source_hash',
  'p_idempotency_key',
  "'authenticated_source_vin'",
  "'source_provenance'",
  "'effective_provenance'",
  'non_navision_vin_collision',
  'non_navision_existing_vin_mismatch',
  'pdc_non_navision_vin_projection_immutable_20260904',
  'FORCE ROW LEVEL SECURITY',
  'UNIQUE(vehicle_id,source_receipt_id)',
  'lock table public.navision_backend_records',
  'lock table public.vehicles',
  'lock table public.vehicle_aliases',
  "VALUES('20260904010800'",
]) assert.ok(sql.toLowerCase().includes(marker.toLowerCase()), `missing VIN projection contract marker: ${marker}`);

assert.match(sql, /public\.is_valid_vehicle_vin\(v_vin\)/i, 'server must validate normalized VIN');
assert.match(sql, /upper\(btrim\(coalesce\(p_vin,''\)\)\)/i, 'server must normalize source VIN to uppercase');
assert.match(sql, /\[A-HJ-NPR-Z0-9\]\{17\}/, 'VIN must use the exact 17-character alphabet');
assert.match(sql, /where[\s\S]{0,80}v\.vin_normalized=v_vin/i, 'all canonical vehicle VIN owners must be checked');
assert.match(sql, /a\.alias_type_normalized='vin'[\s\S]*a\.normalized_alias_value=v_vin/i, 'VIN aliases must be checked');
assert.match(sql, /n\.is_current[\s\S]*normalize_vehicle_vin/i, 'all current backend VIN identities must be checked');
assert.match(
  sql,
  /'source_provenance'[\s\S]{0,220}'source_receipt_id',v_receipt_id/i,
  'fresh VIN-bearing imports must bind source provenance to their generated Job Card receipt',
);
assert.match(
  sql,
  /'effective_provenance'[\s\S]{0,260}'vin'[\s\S]{0,160}'source_receipt_id',v_receipt_id/i,
  'fresh VIN-bearing imports must bind effective VIN provenance to their generated Job Card receipt',
);
assert.match(
  sql,
  /v_result:=public\.navision_backend_response[\s\S]{0,700}'source_provenance'[\s\S]{0,300}'source_receipt_id',v_receipt_id/i,
  'fresh provenance must be persisted in the immutable Job Card receipt response',
);
assert.match(sql, /v_r\.response#>'\{data,source_provenance\}'/i, 'reader must prefer immutable receipt source provenance');
assert.match(sql, /v_r\.response#>'\{data,effective_provenance\}'/i, 'reader must prefer immutable receipt effective provenance');
assert.match(
  sql,
  /select p\.source_provenance[\s\S]*from public\.pdc_non_navision_vin_projection_receipts_20260904 p[\s\S]*p\.source_receipt_id=v_r\.receipt_id/i,
  'Job Card readback must take corrected source provenance from the immutable projection receipt',
);
assert.match(
  sql,
  /select p\.effective_provenance[\s\S]*from public\.pdc_non_navision_vin_projection_receipts_20260904 p[\s\S]*p\.source_receipt_id=v_r\.receipt_id/i,
  'Job Card readback must take corrected effective provenance from the immutable projection receipt',
);
assert.ok(!sql.includes('vjdtsswhroyguxyfjdkt'), 'migration must not contain Production project ref');

const runtime = fs.readFileSync(path.join(__dirname, 'backend/pdc_jobcard_runtime_client_successor_20260904.py'), 'utf8');
assert.match(runtime, /len\(stocks\) != 1 and len\(vins\) != 1/, 'runtime must separate lookup identity from optional VIN');
const processor = fs.readFileSync(path.join(__dirname, 'backend/email_intake_processor_successor_20260904.py'), 'utf8');
assert.match(processor, /valid_lookup = len\(stocks\) <= 1 and len\(vins\) <= 1/, 'canonical request must permit stock plus optional VIN');
const applyScript = fs.readFileSync(path.join(__dirname, 'scripts/apply_non_navision_vin_projection_20260904.py'), 'utf8');
assert.match(applyScript, /EXPECTED_TARGET_VERSION = 2/, 'authorized correction must pin the exact inspected target version');
assert.doesNotMatch(applyScript, /version = before\["vehicle"\]\["version"\]/, 'authorized correction must not accept a freshly inspected arbitrary version');
assert.match(
  applyScript,
  /'source_receipt_id',source_receipt_id,[\s\S]{0,100}'source_hash',source_hash/,
  'post-commit inspector must project the source hash required by verification',
);
assert.match(applyScript, /claims\.replace\("'", "''"\)/, 'JWT claims must be encoded as a quoted SQL text literal');
assert.doesNotMatch(applyScript, /set_config\('request\.jwt\.claims',\{json\.dumps\(claims\)\}/, 'JWT claims must not be emitted as a SQL identifier');

console.log('Audited non-Navision Job Card VIN projection contract: PASS');
