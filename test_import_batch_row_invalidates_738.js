'use strict';
// r738 (F344): a service import batch row wiped the whole QC lines cache (80 wipes per Service as a Whole run), so every
// board load recomputed 617 cars and timed out. A batch row now invalidates only the cars whose history points at it.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const up = fs.readFileSync('supabase/migrations/20261030070500_r738_import_batch_row_invalidates_its_vehicles.sql', 'utf8');
const down = fs.readFileSync('supabase/rollbacks/20261030070500_r738_import_batch_row_invalidates_its_vehicles.down.sql', 'utf8');

test('the batches table leaves the global list and gets its own per-car branch', () => {
  assert.match(up, /c_new text := \$n\$  IF TG_OP = 'TRUNCATE' OR TG_TABLE_NAME IN \('ai_routing_20261019', 'import_rules_139_20261018', 'import_rules_20261017', 'navision_backend_records', 'workshop_stage_aliases', 'workshop_stages'\) THEN\$n\$;/);
  assert.match(up, /IF TG_TABLE_NAME = 'pdc_pilbara_service_import_batches' THEN/);
  assert.match(up, /JOIN public\.pdc_pilbara_service_operations o ON o\.operation_id = hist\.operation_id/);
  assert.match(up, /OR b\.source_hash IN \(CASE WHEN TG_OP <> 'INSERT' THEN OLD\.source_hash END, CASE WHEN TG_OP <> 'DELETE' THEN NEW\.source_hash END\)/);
  assert.doesNotMatch(up.split('c_new2 text :=')[1].split('BEGIN')[0], /DELETE FROM pdc_work_categories_private\.qc_operation_lines_cache WHERE true/);
});

test('import guard, two anchors, pin follows, check added; rollback removes the branch and restores the list', () => {
  assert.match(up, /r738: an import job is running/);
  assert.match(up, /r738: anchor 1 not found once/);
  assert.match(up, /r738: anchor 2 not found once/);
  assert.match(up, /UPDATE pdc_ops\.expected_function_md5 SET prosrc_md5 = md5\(v_new\) WHERE prosrc_md5 = v_md5;/);
  assert.match(up, /'import_batch_row_invalidates_its_vehicles_738', 'F344'/);
  assert.match(down, /r738 down: branch not found/);
  assert.match(down, /'navision_backend_records', 'pdc_pilbara_service_import_batches', 'workshop_stage_aliases'/);
});
