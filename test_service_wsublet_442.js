// r442 (F54): 'PMG PD Service Complete w/Sublet' replaces 'PMG PD Service Complete'. The migration adds a w/Sublet manifest branch
// (no Type, PO # required, collapse marker), a row rule (one row per Dept/R/O/Line, no Type key, hours never summed) and feeds the
// file's sublet POs through import_sublet_pos_439 inside the service apply. These tests check the migration and its undo are
// self-consistent (every pinned md5 equals the md5 of the body it ships) and that nothing else is touched.
const test = require('node:test'), assert = require('node:assert/strict'), fs = require('node:fs'), crypto = require('node:crypto'), path = require('node:path');
const V = '20261021073319_r442_service_wsublet';
const up = fs.readFileSync(path.join(__dirname, 'supabase/migrations', V + '.sql'), 'utf8');
const down = fs.readFileSync(path.join(__dirname, 'supabase/rollbacks', V + '.down.sql'), 'utf8');
const md5 = s => crypto.createHash('md5').update(s, 'utf8').digest('hex');
const SIG = {
  man: 'pdc_codex_intake_private.revolution_service_manifest_20261006(jsonb,text,text)',
  rows: 'pdc_codex_intake_private.revolution_service_rows_20261006(jsonb)',
  app: 'public.pdc_pilbara_service_apply_v1(uuid,text,text)',
  feed: 'pdc_codex_intake_private.service_sublet_po_feed_442(uuid,boolean)'
};
const OLD = { man: '88c75359be6f3e4802c3c1a8f8fd3e10', rows: '56d5702b8946007875a85041e8260020', app: '84e1ed9f1a722719c8c4b5b113e1884f' };
function bodies(sql) {
  const out = {};
  const re = /CREATE (?:OR REPLACE )?FUNCTION ([a-z0-9_.]+)\(([\s\S]*?)\)\s+RETURNS[\s\S]*?AS \$f\$([\s\S]*?)\$f\$/g;
  let m;
  while ((m = re.exec(sql))) out[m[1]] = m[3].replace(/~~CR~~/g, '\r');
  return out;
}
const B = bodies(up), D = bodies(down);
const pin = (sql, sig) => { const m = sql.match(new RegExp(`\\('${sig.replace(/[().]/g, '\\$&')}','([0-9a-f]{32})','r442'`)); return m && m[1]; };
test('every r442 pin equals the md5 of the body the migration installs', () => {
  assert.equal(md5(B['pdc_codex_intake_private.revolution_service_rows_20261006']), pin(up, SIG.rows));
  assert.equal(md5(B['public.pdc_pilbara_service_apply_v1']), pin(up, SIG.app));
  assert.equal(md5(B['pdc_codex_intake_private.service_sublet_po_feed_442']), pin(up, SIG.feed));
  assert.match(up, new RegExp(`SET prosrc_md5='${md5(B['pdc_codex_intake_private.revolution_service_manifest_20261006'])}',release='r442'`));
  assert.match(up, new RegExp(`WHERE oid='${SIG.app.replace(/[().]/g, '\\$&')}'::regprocedure\\)<>'${md5(B['public.pdc_pilbara_service_apply_v1'])}'`));
});
test('undo restores the exact previous bodies (manifest r439, row validator, service apply)', () => {
  assert.equal(md5(D['pdc_codex_intake_private.revolution_service_manifest_20261006']), OLD.man);
  assert.equal(md5(D['pdc_codex_intake_private.revolution_service_rows_20261006']), OLD.rows);
  assert.equal(md5(D['public.pdc_pilbara_service_apply_v1']), OLD.app);
  assert.match(down, /DROP FUNCTION pdc_codex_intake_private\.service_sublet_po_feed_442\(uuid,boolean\);/);
  assert.match(down, /DELETE FROM pdc_ops\.regression_checks WHERE check_name='service_wsublet_contract_and_po_feed' AND added_in='r442'/);
  assert.match(down, /release='r439'/);
});
test('manifest: w/Sublet branch added, the old title and CW CSV branches kept byte for byte', () => {
  const now = B['pdc_codex_intake_private.revolution_service_manifest_20261006'], was = D['pdc_codex_intake_private.revolution_service_manifest_20261006'];
  const keep = was.slice(0, was.lastIndexOf(' ),false);'));
  assert.ok(now.startsWith(keep), 'existing branches unchanged');
  assert.match(now, /p_provenance->>'subject'='PMG PD Service Complete w\/Sublet'/);
  assert.match(now, /p_provenance->>'report_title'='PMG PD Service Complete w\/Sublet'/);
  assert.match(now, /\^PMG PD Service Complete w\[\/_ -\]\?Sublet\( - Job 1\)\?\[\.\]xlsx\?\$/);
  assert.match(now, /revolution_service_headers_439\(p_provenance->'source_headers','\["Dept","Stock #"/);
  assert.doesNotMatch(now.slice(keep.length), /"Type"/);
  assert.match(now, /source_headers' \? 'PO #'/);
  assert.match(now, /type_column'='absent_r442'/); assert.match(now, /line_collapse'='r442_one_row_per_dept_ro_line'/);
  const re = new RegExp('^PMG PD Service Complete w[/_ -]?Sublet( - Job 1)?[.]xlsx?$');
  for (const ok of ['PMG PD Service Complete w/Sublet.xlsx', 'PMG PD Service Complete w_Sublet.xls', 'PMG PD Service Complete wSublet - Job 1.xlsx']) assert.ok(re.test(ok), ok);
  for (const bad of ['PMG PD Service Complete.xlsx', 'PMG PD Service Complete w/Sublet - Job 2.xlsx', 'PMG PD Service Complete w/Sublet.csv', 'x PMG PD Service Complete w/Sublet.xlsx']) assert.ok(!re.test(bad), bad);
});
test('rows: w/Sublet lines carry no Type, every PO and hours_summed false; one row per Dept/R/O/Line; no mixed titles', () => {
  const r = B['pdc_codex_intake_private.revolution_service_rows_20261006'];
  assert.match(r, /NOT \(x->'raw_row' \? 'Type'\)/);
  assert.match(r, /'hours_summed'='false'::jsonb/);
  assert.match(r, /jsonb_typeof\(x->'raw_row'->'sublet_pos'\)='array'/);
  assert.match(r, /IN \(0,count\(\*\)\)/);
  assert.match(r, /=count\(DISTINCT \(x->>'department'\)/);
  assert.ok(r.includes(D['pdc_codex_intake_private.revolution_service_rows_20261006'].split("OR coalesce(x->>'repair_order_number'")[0].slice(0, 400)));
});
test('apply: only changes are the PO feed before the single apply receipt and WHERE true on the existing ON CONFLICT DO UPDATE', () => {
  const a = B['public.pdc_pilbara_service_apply_v1'], o = D['public.pdc_pilbara_service_apply_v1'];
  const feed = a.indexOf("service_sublet_po_feed_442(v_preview.batch_id,false)");
  const rec = a.indexOf("'apply',v_response,v_actor,v_actor_label");
  assert.ok(feed > 0 && rec > feed);
  assert.equal(a.split("'apply',v_response,v_actor,v_actor_label").length, 2, 'exactly one apply receipt');
  assert.ok(feed > a.indexOf('pdc_parts_private.sync_service_jobs()'), 'after the job sync');
  const A1 = 'apply_service_arrival(v_apply_batch);\r\n', A2 = '  RETURN v_response||';
  const cut = s => s.slice(0, s.indexOf(A1) + A1.length) + s.slice(s.indexOf(A2, s.indexOf(A1)));
  const oldReceipt = o.slice(o.indexOf('   -- Persist the final response'), o.indexOf("v_actor,v_actor_label);\r\n", o.indexOf('   -- Persist the final response')) + "v_actor,v_actor_label);\r\n".length);
  assert.ok(oldReceipt.startsWith('   -- Persist') && oldReceipt.length < 400);
  const U = 'approval_key=NULL,approval_hash=NULL,approval_receipt=NULL';
  assert.equal(a.split(U + ' WHERE true;').length, 2, "ON CONFLICT ... DO UPDATE gets 'WHERE true' (same behaviour) for the safeupdate lint");
  const added = cut(a).replace(U + ' WHERE true;', U + ';'), removed = cut(o.replace(oldReceipt, ''));
  assert.ok(a.slice(a.indexOf(A1), a.indexOf(A2, a.indexOf(A1))).includes(oldReceipt.trim().split('\r\n').slice(-1)[0].trim()), 'the receipt moved, unchanged');
  assert.equal(added, removed, 'nothing else in the apply changed');
});
test('feed: private, reuses import_sublet_pos_439, writes nothing itself, reports failures without undoing the apply', () => {
  const f = B['pdc_codex_intake_private.service_sublet_po_feed_442'];
  assert.match(up, /REVOKE ALL ON FUNCTION pdc_codex_intake_private\.service_sublet_po_feed_442\(uuid,boolean\) FROM PUBLIC, anon, authenticated, service_role;/);
  assert.doesNotMatch(up, /GRANT [^;]*service_sublet_po_feed_442/);
  assert.match(f, /public\.import_sublet_pos_439\(v_rows,v_sha,coalesce\(p_dry_run,true\)\)/);
  assert.doesNotMatch(f, /(INSERT INTO|UPDATE|DELETE FROM)\s+public\./i);
  assert.match(f, /EXCEPTION WHEN OTHERS THEN/); assert.match(f, /'sublet_po_feed_failed'/);
  assert.match(f, /'category_changes',0,'booking_changes',0,'ticks_cleared',0,'pos_removed',0/);
});
test('release guards: staging only, :02-:45, clock tick and preview untouched, short lock timeout, no frontend or Karratha change', () => {
  for (const s of [up, down]) {
    assert.match(s, /SET LOCAL lock_timeout = '2s';/);
    assert.match(s, /project_ref='cdsmnqxtyyoeoznmbidd'/);
    assert.match(s, /NOT BETWEEN 2 AND 45/);
    assert.match(s, /workshop_clock_tick\(boolean,timestamptz\)'::regprocedure\)<>'84af7607bfd0ce9907c89bae8644d5b6'/);
    assert.doesNotMatch(s, /vjdtsswhroyguxyfjdkt/);
    assert.doesNotMatch(s, /CREATE (OR REPLACE )?FUNCTION public\.workshop_clock_tick|cron\./);
    assert.doesNotMatch(s, /karratha135/);
  }
  assert.match(up, /pdc_pilbara_service_preview_v1\(jsonb,text,text\)'::regprocedure\)<>'375bffc2dced95a7a5c74c3273dbccb3'/);
  assert.match(up, /sort_order=242/); assert.match(up, /'service_wsublet_contract_and_po_feed','F54'/);
  assert.doesNotMatch(up + down, /\b1[23][0-9]{6}\b/, 'no stock numbers');
});
test('docs and fault log describe the w/Sublet contract', () => {
  const doc = fs.readFileSync(path.join(__dirname, 'docs/revolution-service-email.md'), 'utf8');
  for (const s of ['PMG PD Service Complete w/Sublet', 'type_column', 'absent_r442', 'r442_one_row_per_dept_ro_line', 'sublet_pos', 'pdc-service-sublet-po-feed-442', 'fc3717a5215de94c93ebb2c7facfe744', 'never summed']) assert.ok(doc.includes(s), s);
  const log = fs.readFileSync(path.join(__dirname, 'docs/FAULT_LOG.md'), 'utf8');
  assert.match(log, /^\| F54 \| 21 Oct 15:08 \|/m);
  assert.ok(log.indexOf('| F54 |') > log.indexOf('| F53 |'));
});
