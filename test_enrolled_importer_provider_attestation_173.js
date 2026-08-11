'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = process.env.PDC_TEST_ROOT ? path.resolve(process.env.PDC_TEST_ROOT) : __dirname;
const sql = fs.readFileSync(path.join(root, 'supabase', 'staging_only', '173_enrolled_importer_provider_attestation.sql'), 'utf8');
const runtime = fs.readFileSync(path.join(root, 'backend', 'pdc_jobcard_runtime_client.py'), 'utf8');
const lower = sql.toLowerCase();

assert(lower.includes("version='172' and name='sublet_calendar_return_station_completion'"), 'Migration 173 must require the exact predecessor');
assert(lower.includes("version::integer>172") && lower.includes("version='173'"), 'Migration 173 must reject newer or repeated ledgers');
assert(lower.includes("v_authority='service_role' or v_enrolled_importer"), 'Attestation must remain limited to service role or enrolled Importer');
assert(lower.includes("r.role='importer'") && lower.includes("r.account_status='approved'"), 'Viewer access must not satisfy the Importer gate');
assert(lower.includes('pdc_monitor_stage_activation_writers') && lower.includes('w.revoked_at is null'), 'Attestation actor must retain active monitor-writer enrollment');
assert(lower.includes("provider_authserv_id") && lower.includes("v_authserv<>'mx.google.com'"), 'Gmail provider authority binding must remain enforced');
assert(lower.includes('pdc_monitor_exact_sender_enrollments'), 'Exact sender enrollment must remain enforced');
assert(lower.includes('provider_observation_replay_conflict'), 'Hash-bound replay conflict behavior must remain enforced');
assert(lower.includes('attested_by') && lower.includes('attested_authority'), 'Immutable evidence must record who attested it');
assert(lower.includes('grant execute on function public.attest_pdc_provider_email_observation(uuid,uuid,text,text,text,text,jsonb) to authenticated,service_role'), 'Authenticated Importer and service role must have RPC access');
assert(lower.includes("has_function_privilege('anon'") && lower.includes("'execute')"), 'Anonymous RPC access must be explicitly rejected');
assert(runtime.includes('attestation_client = RpcClient(url, service_key, service_key, "service_role") if service_key else actor_client'), 'Runtime must fall back to the enrolled Importer when no service-role secret is present');
assert(runtime.includes('enrolled Importer attestation must use the same actor session'), 'Actor-only attestation must not allow mixed identities');

console.log('Enrolled Importer provider-attestation permission contract passed');
