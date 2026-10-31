// r781 (F386): CW parts and BT / KTA deal items can be applied from the website.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');

const edge = fs.readFileSync('supabase/functions/revolution-upload/index.ts', 'utf8');
const ui = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
const sql = fs.readFileSync('supabase/migrations/20261031120000_r781_website_apply_parts_and_deal_items.sql', 'utf8');

test('edge function queues parts and deal items through the r781 RPC', () => {
  assert.match(edge, /const OTHER_781 = new Set\(\['cw_parts', 'bt_deal_items', 'kta_deal_items'\]\)/);
  assert.match(edge, /action === 'apply' && OTHER_781\.has\(parsed\.kind\)\) return await applyOther781/);
  assert.match(edge, /rpcAs\(projectUrl, auth, 'revolution_upload_other_781'/);
  assert.match(edge, /apply_enabled: parsed\.kind === 'service_whole' \|\| OTHER_781\.has\(parsed\.kind\)/);
  assert.ok(!/service_complete'\]\)/.test(edge), 'Service Complete stays off');
});

test('page follows the importer result', () => {
  assert.match(ui, /revolution_upload_other_status_781/);
  assert.match(ui, /if \(payload\.other_upload_id\) \{ setStatus\(payload\.message\); followOther781\(payload\.other_upload_id\); return; \}/);
});

test('migration: administrator-only queue, management-connection worker, KTA website rule bound to the running upload', () => {
  assert.match(sql, /IF v_role <> 'administrator' OR v_uid IS NULL/);
  assert.match(sql, /REVOKE ALL ON pdc_import_620\.other_uploads_781 FROM PUBLIC, anon, authenticated, service_role/);
  assert.match(sql, /IF pdc_codex_intake_private\.management_connection\(\) IS NOT TRUE THEN RETURN; END IF;/);
  assert.match(sql, /'source_kind', 'user_attached_workbook'/);
  assert.match(sql, /u\.status = 'running'/);
  assert.match(sql, /cron\.schedule\('pdc-import-other-781', '\* \* \* \* \*'/);
  assert.ok(!/CREATE PROCEDURE pdc_import_620\.run_other_781\(\)\s*LANGUAGE plpgsql SET/.test(sql), 'a procedure that commits has no SET clause');
});
