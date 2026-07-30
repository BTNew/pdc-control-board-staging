'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const sql = fs.readFileSync(path.join(__dirname, 'supabase', 'staging_only', '123_harden_ai_auditor_human_review_binding.sql'), 'utf8').replace(/\r\n/g, '\n').toLowerCase();
const functionBody = name => {
  const start = sql.indexOf(`create or replace function public.${name}`);
  const delimiter = name === 'get_pdc_auditor_review_queue' ? '$queue$;' : '$decide$;';
  const end = sql.indexOf(delimiter, start);
  assert.ok(start >= 0 && end > start, `${name} missing`);
  return sql.slice(start, end);
};

assert.match(sql, /^-- staging-only migration 123:/);
assert.ok(sql.includes("version='122' and name='ai_auditor_human_review_decisions'"));
assert.ok(sql.includes('unique (finding_id,evidence_fingerprint,finding_last_seen_run_id)'), 'exact occurrence uniqueness must include run');
assert.ok(sql.includes("values('123','harden_ai_auditor_human_review_binding'"));

const queue = functionBody('get_pdc_auditor_review_queue');
assert.ok(queue.includes('d.finding_last_seen_run_id=f.last_seen_run_id'), 'queue decisions must join on exact run');
for (const field of ['run_operational_revision', 'run_rule_set_hash', 'run_model_key']) assert.ok(queue.includes(`'${field}'`), `${field} missing`);

const decide = functionBody('record_pdc_auditor_decision');
const replay = decide.indexOf('select * into v_existing');
const current = decide.indexOf('select * into v_finding');
assert.ok(replay >= 0 && replay < current, 'exact replay must be detected before current-finding freshness rejection');
assert.ok(decide.includes('d.finding_last_seen_run_id=p_last_seen_run_id'), 'replay must bind exact run');
assert.ok(decide.includes('v_existing.reason is distinct from v_reason'), 'idempotent replay must bind exact note/reason');
assert.ok(decide.includes("v_snapshot->>'operational_revision'<>v_run.operational_revision"));
assert.ok(decide.includes("v_snapshot->>'rule_set_hash'<>v_run.rule_set_hash"), 'rule changes must stale findings');
assert.ok(decide.includes("'operational_change',false"));
assert.ok(decide.includes("'execution_reference',null"));

const writes = [...decide.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?([a-z0-9_]+)/g)].map(match => match[1]);
for (const table of writes) assert.ok(['pdc_auditor_decisions', 'pdc_auditor_revision'].includes(table), `forbidden write ${table}`);

console.log('AI Auditor migration 123 contract passed: exact run/reason, rule freshness, queue binding and non-execution');
