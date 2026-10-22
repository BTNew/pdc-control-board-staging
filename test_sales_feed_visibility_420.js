/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r420 (F35): Sales shows every current Navision feed vehicle, whatever its PMB state; only the manual hide hides one.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const V='20261021002331_r420_sales_feed_visibility';
const up=fs.readFileSync('supabase/migrations/'+V+'.sql','utf8'),down=fs.readFileSync('supabase/rollbacks/'+V+'.down.sql','utf8');
const fns=['visibility_source_snapshot(boolean)','board_visibility_source_snapshot(boolean)','completed_vehicle_snapshot()','build_stock_counts()','crm_finance_refs()','sales_accessory_candidates()'];
const defs=(sql)=>sql.split(/(?=CREATE OR REPLACE FUNCTION )/).filter(s=>s.startsWith('CREATE OR REPLACE FUNCTION'));

test('the deleted-PMB-vehicle filter is gone from all six Sales functions and only from them',()=>{
  const created=defs(up);assert.equal(created.length,6);
  for(const f of fns)assert.ok(created.some(d=>d.startsWith('CREATE OR REPLACE FUNCTION pdc_sales_private.'+f.replace(/\(.*$/,'')+'(')),f);
  for(const d of created){
    assert.doesNotMatch(d,/canonical_vehicle_id IS NULL OR v\.id IS NOT NULL|canonical_vehicle_id IS NULL OR vehicle_id IS NOT NULL/);
    assert.match(d,/r420 \(F35\)/);
  }
  // Only Sales (pdc_sales_private) functions change: no vehicle, booking or workshop board function and no data.
  assert.doesNotMatch(up,/CREATE OR REPLACE FUNCTION public\./);
  assert.doesNotMatch(up,/\b(UPDATE|DELETE FROM|INSERT INTO) public\./);
  assert.doesNotMatch(up,/workshop_clock_tick\(boolean,timestamptz\)'::regprocedure\)<>'84af7607bfd0ce9907c89bae8644d5b6' THEN RAISE EXCEPTION 'r420: clock tick changed'; END IF;[\s\S]*CREATE OR REPLACE FUNCTION public\.workshop/);
  assert.doesNotMatch(up+down,/deleted_at\s*=\s*NULL|SET deleted_at/,'deleted PMB vehicles are never restored');
});

test('kept: latest feed batch, current rows, COSI, the manual hide and salesperson scope; a deleted PMB vehicle reads as unlinked',()=>{
  const vss=defs(up).find(d=>d.startsWith('CREATE OR REPLACE FUNCTION pdc_sales_private.visibility_source_snapshot('));
  assert.match(vss,/JOIN latest_scope applied ON applied\.id=n\.last_seen_batch_id[^\n]*n\.is_current AND n\.record_status='current'/);
  assert.match(vss,/WHERE n\.cosi_status IN \('yes','true','1'\)\n AND \(p_hidden IS NULL OR coalesce\(h\.hidden,false\)=p_hidden\)\n -- r420[^\n]*\n AND \(ctx->>'role'='administrator' OR/);
  assert.match(vss,/LEFT JOIN public\.vehicles v ON v\.id=n\.canonical_vehicle_id AND v\.deleted_at IS NULL/);
  assert.match(vss,/'canonical_vehicle_id',v\.id/);assert.match(vss,/'identity_status',CASE WHEN v\.id IS NULL THEN 'awaiting_pmb_link' ELSE 'linked' END/);
  const cand=defs(up).find(d=>d.includes('sales_accessory_candidates('));
  assert.match(cand,/'visible',\(cosi AND NOT hidden\),/);
});

test('guards, pins, the F35 regression check and an exact undo',()=>{
  assert.match(up,/NOT BETWEEN 2 AND 45/);assert.match(up,/project_ref='cdsmnqxtyyoeoznmbidd'/);assert.doesNotMatch(up+down,/vjdtsswhroyguxyfjdkt/);
  for(const m of ['c51d473d947b4dea1ef457bb57f6d16d','2cdd2ec2581551363d39d055e2cf1397','0166ce1a667d93f7bf4283a80561add2','82ee924af02273cb364235a7625ad6eb','1af3213189df1550d202e9f0dc6e274c','9e7cb1a8044d8840aa306e813ef63df7']){
    assert.ok(up.includes("'"+m+"'"),'apply asserts old '+m);assert.ok(down.includes("'"+m+"'"),'undo restores and asserts '+m);
  }
  assert.match(up,/owner, grants, security or settings of the Sales functions are not as expected/);
  assert.equal((up.match(/','r420','/g)||[]).length,7);
  assert.match(up,/\('sales_shows_every_feed_row','F35',[\s\S]*feed_visibility_check_420\(\) r\) x\$chk\$,true,222,'r420'\);/);
  assert.match(up,/REVOKE ALL ON FUNCTION pdc_sales_private\.feed_visibility_check_420\(\) FROM PUBLIC, anon, authenticated, service_role;/);
  assert.match(up,/PERFORM set_config\('request\.jwt\.claims',coalesce\(old_claims,''\),true\);\n RETURN|PERFORM set_config\('request\.jwt\.claims',coalesce\(old_claims,''\),true\);\n WITH/);
  assert.match(up,/deleted PMB vehicles on the workshop board: /);
  assert.equal(defs(down).length,6);assert.doesNotMatch(defs(down).map(d=>d.slice(0,d.indexOf('$function$;'))).join(''),/r420/);
  assert.match(down,/DROP FUNCTION pdc_sales_private\.feed_visibility_check_420\(\);/);
  assert.match(down,/DELETE FROM pdc_ops\.expected_function_md5 WHERE release='r420';/);
  assert.match(down,/r420 undo: Sales functions not restored/);
});

test('no personal identifiers in Git: no user ids, emails or the unhide data step',()=>{
  assert.doesNotMatch(up+down,/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
  assert.doesNotMatch(up+down,/@[a-z0-9.-]+\.[a-z]{2,}/i);
  assert.doesNotMatch(up+down,/vehicle_visibility SET|sales_visibility_unhide/);
});

test('Sales says "Awaiting PMB link" for an unlinked or deleted-PMB row; the fixed roster rule is unchanged',()=>{
  const sales=require('./sales/sales.js');
  assert.equal(sales.pmbSummary({tracking_id:'t',canonical_vehicle_id:null,identity_status:'awaiting_pmb_link'}).status,'Awaiting PMB link');
  const rows=['BG','ZZ'].map((c,i)=>({tracking_id:'t'+i,salesperson_code:c,cosi:true,source_current:true,sales_hidden:false}));
  assert.deepEqual(sales.scopeRows(rows).map(r=>r.salesperson_code),['BG']);
  assert.match(fs.readFileSync('sales/index.html','utf8'),/sales\.js\?[^"]*&amp;feed-visibility=2026\.10\.21\.04"/);
  const log=fs.readFileSync('docs/FAULT_LOG.md','utf8');
  assert.match(log,/\| F35 \| 21 Oct 08:23 \|[^\n]*20261021002331[^\n]*sales_shows_every_feed_row/);
  assert.doesNotMatch(log.match(/\| F35 \|[^\n]*/)[0],/\b1[0-3]\d{6}\b/,'no stock numbers in the public log');
});
