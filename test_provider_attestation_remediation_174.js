'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = process.env.PDC_TEST_ROOT ? path.resolve(process.env.PDC_TEST_ROOT) : __dirname;
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '174_restore_provider_attestation_boundary_and_key_snapshot.sql'), 'utf8').toLowerCase();
const runtime = fs.readFileSync(path.join(root, 'backend', 'pdc_jobcard_runtime_client.py'), 'utf8');
const mapper = fs.readFileSync(path.join(root, 'pdc-email-vehicle-location-service.js'), 'utf8');

assert(sql.includes("version='173' and name='enrolled_importer_provider_attestation'"), 'Migration 174 must require the exact installed predecessor');
assert(sql.includes("auth.role()<>'service_role'"), 'Provider-authentication claims must be accepted only from service role');
assert(sql.includes('from public,anon,authenticated'), 'Authenticated Importers must lose direct attestation execution');
assert(sql.includes('to service_role'), 'Trusted attestation execution must remain available to service role');
assert(sql.includes("jsonb_build_object('key_number',v.key_number)"), 'Snapshot must use canonical vehicles.key_number');
assert(sql.includes('rename to get_pdc_email_vehicle_location_snapshot_pre_174'), 'Snapshot predecessor must be retained behind the wrapper');
assert(sql.includes('grant execute on function public.get_pdc_email_vehicle_location_snapshot() to authenticated'), 'Authenticated staff must retain snapshot access');
assert(runtime.includes('getattr(service_client, "authority", None) != "service_role"'), 'Runtime must require the trusted service authority');
assert(runtime.includes('getattr(actor_client, "authority", None) != "authenticated_monitor"'), 'Runtime must keep extraction/import bound to the enrolled actor');
assert(mapper.includes("keyNumber: String(row.key_number || '').trim()"), 'Client mapper must expose canonical key number');

console.log('Provider-attestation boundary and key snapshot remediation contract passed');
