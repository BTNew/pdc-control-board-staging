'use strict';
// r617 (F232): Kajel's Service as a Whole import in two calls. Static checks on the migration.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const sql = fs.readFileSync('supabase/migrations/20261028180000_r617_one_step_import.sql', 'utf8');

test('calls the existing pinned import functions unchanged, with Kajel\'s pins and guards', () => {
  for (const pin of ['ea9a62537a146f05a01e866c636d367b', '9be0883b1a555f48f3c1ba9fa111c891', 'b62fb7c29ffd2a1629f214f696e5cb14', '66379d312c3fddfd2eaab5b37c0ba497', '6083fb5bcf03d341d9101831c2217cb8']) assert.ok(sql.includes(pin), pin);
  assert.match(sql, /public\.pdc_pilbara_service_preview_v1\(p_rows, v_hash, 'codex-owner-email-preview-' \|\| v_hash\)/);
  assert.match(sql, /public\.pdc_pilbara_service_apply_v1\(v_bid, v_hash, 'codex-owner-email-apply-' \|\| v_hash\)/);
  assert.doesNotMatch(sql, /CREATE (OR REPLACE )?FUNCTION public\./, 'no public function is created or replaced');
  assert.match(sql, /'workshop-clock-cascade-20260911'[\s\S]*'pdc:workshop:top-level-mutation'/);
  assert.match(sql, /LOCK TABLE public\.vehicles, public\.navision_backend_records IN SHARE ROW EXCLUSIVE MODE/);
  assert.match(sql, /pdc_codex_intake_private\.management_connection\(\) IS NOT TRUE/);
});

test('importer unban only inside a transaction and always checked back to its ban', () => {
  const unbans = (sql.match(/SET banned_until = NULL/g) || []).length;
  const rebans = (sql.match(/SET banned_until = v_ban/g) || []).length;
  assert.equal(unbans, 2); assert.equal(rebans, 2);
  assert.equal((sql.match(/importer_restore_failed/g) || []).length, 2);
  assert.match(sql, /IF v_ban IS DISTINCT FROM pdc_import_617\.importer_ban\(\) THEN RAISE EXCEPTION 'unexpected_importer_state'/);
});

test('same protections as apply.sql, holds, sanity gates, resumable worker', () => {
  for (const s of ['existing_parts_flags_changed_by_service', 'staff_or_person_parts_state_changed', 'parked135_state_changed', 'sales_written', 'archive_count_not_0', 'r442_apply_without_sublet_pos']) assert.ok(sql.includes(s), s);
  assert.match(sql, /len\(cur\)|jsonb_array_length\(v_cur\) \+ v_stock\.n > 180/);
  assert.match(sql, /v_new > 15/); assert.match(sql, /v_archived > 15/);
  assert.match(sql, /'13044312', 7[\s\S]*'13042994'[\s\S]*'13092999'[\s\S]*'13073002'/);
  assert.match(sql, /CREATE PROCEDURE pdc_import_617\.run_jobs\(\)\nLANGUAGE plpgsql AS/, 'no SET clause so it can COMMIT');
  assert.match(sql, /step_attempts >= 3/);
  assert.match(sql, /cron\.schedule\('pdc-import-617-worker', '\* \* \* \* \*', 'CALL pdc_import_617\.run_jobs\(\)'\)/);
  assert.match(sql, /REVOKE ALL ON SCHEMA pdc_import_617 FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(sql, /project_ref = 'cdsmnqxtyyoeoznmbidd'/);
  assert.match(sql, /expected_function_md5\) <> 241/);
  assert.doesNotMatch(sql.split('$chk617$')[1], /expected_function_md5/, 'F227: checks never lock the pin total');
  assert.ok(fs.existsSync('supabase/rollbacks/20261028180000_r617_one_step_import.down.sql'));
});
