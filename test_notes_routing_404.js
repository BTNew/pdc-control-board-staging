/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r404 (F13): a job-card notes line is never kept on the QC checklist as work.
// Craig's rule (r400): notes lines never block QC. Decision 20 Oct 2026 21:18 AWST:
// automatic locks give way; manual operator locks, QC ticks, owner overrides and
// completed vehicles stay as they are.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');

const ID = '20261020133118_r404_notes_never_work';
const up = fs.readFileSync(`supabase/migrations/${ID}.sql`, 'utf8');
const down = fs.readFileSync(`supabase/rollbacks/${ID}.down.sql`, 'utf8');
const log = fs.readFileSync('docs/FAULT_LOG.md', 'utf8');
const helper = (() => {
  const s = up.indexOf('CREATE FUNCTION pdc_work_categories_private.job_card_note_forced_404');
  assert.ok(s >= 0, 'helper defined');
  return up.slice(s, up.indexOf('ALTER FUNCTION', s));
})();

test('migration runs on staging only, once, over the exact r400 function', () => {
  assert.match(up, /pdc_staging_environment_sentinel WHERE singleton AND project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.match(up, /pdc_production_environment_sentinel/);
  assert.match(up, /already applied/);
  assert.match(up, /<>'b677d7bfdf67c046fd05922da249325c'/);
  assert.match(up, /'fa4651cce7bb0fdb8985857779b62d93'/);
  assert.ok(!up.includes('vjdtsswhroyguxyfjdkt') && !down.includes('vjdtsswhroyguxyfjdkt'), 'never names production');
});

test('helper only forces notes when nobody chose otherwise', () => {
  assert.match(helper, /category='JOB_CARD_NOTES'/);
  assert.match(helper, /NOT coalesce\(\(l->>'completed'\)::boolean,false\)/, 'QC-ticked lines kept');
  assert.match(helper, /NOT coalesce\(\(l->>'rejected'\)::boolean,false\)/);
  assert.match(helper, /coalesce\(\(l->>'category_version'\)::integer,0\)=0/, 'owner overrides kept');
  assert.match(helper, /v\.deleted_at IS NULL AND v\.lifecycle_state='active'/, 'completed vehicles kept');
  assert.match(helper, /manual_assignment_locked AND a\.correction_origin='manual_operator'/, 'manual operator lock kept');
  assert.match(helper, /owner_line_reviews/, 'owner reviews kept');
  assert.match(helper, /STABLE/);
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_work_categories_private\.job_card_note_forced_404\(uuid,jsonb\) FROM PUBLIC, anon, authenticated, service_role/);
});

test('the preserve gate is wrapped, not replaced', () => {
  assert.match(up, /AND NOT pdc_work_categories_private\.job_card_note_forced_404\(p_vehicle_id,l\)/);
  for (const gate of ["category_version')::integer,0)>0", 'owner_line_reviews', 'manual_assignment_locked']) {
    assert.ok(up.includes(gate), gate);
  }
});

test('pins, regression check and cache refresh are part of the release', () => {
  assert.match(up, /'cfe0fd4c29d9eaf82c06ed1d0ffdd541','r404'/);
  assert.match(up, /'97fc4caaf7b462163d35b4a3511bc487','r404'/);
  assert.match(up, /'notes_lines_never_on_qc_checklist','F13'/);
  assert.match(up, /'1e4b22a822531ba2c4b90668e8202c01'/);
  assert.match(up, /bump_qc_operation_lines_cache_epoch/);
});

test('undo asserts the new md5s and restores the exact old function', () => {
  assert.match(down, /pdc_staging_environment_sentinel/);
  assert.match(down, /97fc4caaf7b462163d35b4a3511bc487/);
  assert.match(down, /cfe0fd4c29d9eaf82c06ed1d0ffdd541/);
  assert.match(down, /b677d7bfdf67c046fd05922da249325c/);
  assert.match(down, /DROP FUNCTION pdc_work_categories_private\.job_card_note_forced_404\(uuid,jsonb\)/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='notes_lines_never_on_qc_checklist'/);
  assert.match(down, /bump_qc_operation_lines_cache_epoch/);
  assert.ok(!down.includes('job_card_note_forced_404(p_vehicle_id,l)'), 'old body has no helper call');
});

test('F13 is logged with its check, rollback and test', () => {
  const row = log.split('\n').find((l) => l.startsWith('| F13 |'));
  assert.ok(row, 'F13 row');
  for (const s of ['notes_lines_never_on_qc_checklist', `${ID}.down.sql`, 'test_notes_routing_404.js', '20261020133118']) {
    assert.ok(row.includes(s), s);
  }
});
