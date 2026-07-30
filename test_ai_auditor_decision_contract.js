'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '122_ai_auditor_human_review_decisions.sql'), 'utf8').replace(/\r\n/g, '\n');
const lower = sql.toLowerCase();

function functionBody(name, delimiter) {
  const start = lower.indexOf(`create or replace function public.${name}`);
  const end = lower.indexOf(`${delimiter};`, start);
  assert.ok(start >= 0 && end > start, `${name} body missing`);
  return lower.slice(start, end);
}

assert.match(lower, /^-- staging-only migration 122:/);
assert.ok(lower.includes("version='121' and name='beta_ai_auditor_foundation'"), 'exact migration 121 predecessor is required');
assert.ok(lower.includes("version='122' and name<>'ai_auditor_human_review_decisions'"), 'migration 122 conflict guard is required');
assert.ok(lower.includes('create table if not exists public.pdc_auditor_decisions'));
assert.ok(lower.includes("decision in ('approved','denied')"));
assert.ok(lower.includes('unique (finding_id,evidence_fingerprint)'));
assert.ok(lower.includes('operational_change boolean not null default false check (not operational_change)'));
assert.ok(lower.includes('execution_reference text check (execution_reference is null)'));
assert.ok(lower.includes('pdc_auditor_decisions_immutable'));
assert.ok(lower.includes('pdc_auditor_reject_history_mutation()'));

const queue = functionBody('get_pdc_auditor_review_queue', '$queue$');
assert.ok(queue.includes('pdc_auditor_actor_scope()'));
assert.ok(queue.includes("v_role in ('operator','administrator')"));
assert.ok(queue.includes("f.lifecycle_status='current'"));
assert.ok(queue.includes("'operational_change',false"));

const decide = functionBody('record_pdc_auditor_decision', '$decide$');
assert.ok(decide.includes("v_role not in ('operator','administrator')"), 'viewer must be denied in the backend');
assert.ok(decide.includes('pg_advisory_xact_lock'), 'one finding decision must serialize');
assert.ok(decide.includes('for update'), 'current finding must be locked');
assert.ok(decide.includes('v_finding.evidence_fingerprint<>p_evidence_fingerprint'));
assert.ok(decide.includes('v_finding.last_seen_run_id<>p_last_seen_run_id'));
assert.ok(decide.includes('pdc_auditor_operational_revision(v_dealer)<>v_run.operational_revision'), 'operational changes must stale the recommendation');
assert.ok(decide.includes("raise exception 'pdc_auditor_finding_stale'"));
assert.ok(decide.includes("p_decision='denied' and (v_reason is null"), 'Deny requires a reason');
assert.ok(decide.includes("raise exception 'pdc_auditor_already_decided'"), 'conflicting repeat decisions must fail');
assert.ok(decide.includes("'idempotent',true"), 'same repeat decision must be idempotent');
assert.ok(decide.includes("'operational_change',false"));
assert.ok(decide.includes("'execution_reference',null"));

const allowedWrites = new Set(['pdc_auditor_decisions', 'pdc_auditor_revision']);
const writes = [...decide.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?([a-z0-9_]+)/g)].map(match => match[1]);
assert.ok(writes.length >= 2, 'decision write inventory unexpectedly small');
for (const table of writes) assert.ok(allowedWrites.has(table), `decision writes forbidden table ${table}`);
for (const table of ['vehicles', 'vehicle_work_items', 'workshop_bookings', 'workshop_booking_assignments', 'vehicle_parts_updates', 'pdc_sublet_bookings']) {
  assert.ok(!new RegExp(`\\b(?:insert\\s+into|update|delete\\s+from)\\s+(?:public\\.)?${table}\\b`).test(decide), `decision mutates operational table ${table}`);
}
assert.ok(!/(execute|perform)\s+public\.(move|apply|update|schedule|complete|import|assign)/.test(decide), 'decision function delegates to an operational function');
assert.ok(lower.includes('revoke all on table public.pdc_auditor_decisions from public,anon,authenticated'));
assert.ok(lower.includes('grant select on table public.pdc_auditor_decisions to authenticated'));
assert.ok(!lower.includes('grant insert on table public.pdc_auditor_decisions'));
assert.ok(lower.includes('grant execute on function public.record_pdc_auditor_decision(uuid,text,uuid,text,text) to authenticated'));

console.log('AI Auditor human decision contract passed: immutable audited dispositions, exact evidence/run/role checks, and no operational execution path');
