/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
// r435 (F46): a salesperson with "view all salespeople" sees every Sales Finance entry (Finance, Pipeline and All applications),
// read-only and masked like any non-editor. Before r435 view-all widened vehicles only, so Finance showed just the caller's own entries.
// Server: supabase/migrations/20261021051514_r435_salesperson_view_all_finance.sql (+ rollback).
const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const mig=fs.readFileSync('supabase/migrations/20261021051514_r435_salesperson_view_all_finance.sql','utf8');
const down=fs.readFileSync('supabase/rollbacks/20261021051514_r435_salesperson_view_all_finance.down.sql','utf8');
const finance=fs.readFileSync('sales/finance-pipeline.js','utf8');
const body=s=>s.slice(s.indexOf('CREATE OR REPLACE FUNCTION pdc_sales_private.finance_pipeline()'),s.indexOf('$f$;',s.indexOf('CREATE OR REPLACE FUNCTION pdc_sales_private.finance_pipeline()')));
test('finance_pipeline returns every entry to view-all callers, and still own-only otherwise',()=>{
 const b=body(mig);
 assert.match(b,/WHERE editor OR coalesce\(\(ctx->>'can_view_all_salespeople'\)::boolean,false\)\n  OR r\.salesperson_id=\(ctx->>'salesperson_id'\)::uuid;/);
 // masking and editor-only extras are unchanged: non-editors get no financier/commission fields, no vehicle picker, no people list
 assert.match(b,/pdc_sales_private\.finance_application_json\(r,editor\)/);
 assert.match(b,/IF editor THEN\n  refs:=pdc_sales_private\.crm_finance_refs\(\);/);
 assert.match(b,/STABLE SECURITY DEFINER/);
});
test('the rollback restores the original own-only filter byte for byte',()=>{
 const b=body(down);
 assert.match(b,/WHERE editor OR r\.salesperson_id=\(ctx->>'salesperson_id'\)::uuid;\n/);
 assert.doesNotMatch(b,/can_view_all_salespeople/);
 assert.match(down,/6f9bf4771df31527d847f81b186c5cdf/);
 assert.match(down,/DROP FUNCTION pdc_sales_private\.finance_visibility_check_435\(\);/);
});
test('the screen keeps non-editors read-only, so view-all salespeople can look but not edit',()=>{
 assert.match(finance,/const editor=\(\)=>ctx\?\.can_edit_finance===true;/);
 assert.match(finance,/hidden=!editor\(\)&&privateFields\.has\(k\)/);
 assert.match(finance,/function add\(\)\{guard\(\);if\(!editor\(\)\)return;/);
});
test('regression check, pins, release guards and undo are in place',()=>{
 assert.match(mig,/'salesperson_view_all_sees_all_finance','F46'/);
 assert.match(mig,/FROM pdc_sales_private\.finance_visibility_check_435\(\) c/);
 assert.match(mig,/REVOKE ALL ON FUNCTION pdc_sales_private\.finance_visibility_check_435\(\) FROM PUBLIC, anon, authenticated, service_role;/);
 assert.match(mig,/PERFORM set_config\('request\.jwt\.claims',coalesce\(prev,''\),true\);/);
 assert.match(mig,/'pdc_sales_private\.finance_pipeline\(\)','372dcae199c750594923e2269f661e43','r435'/);
 for(const s of [mig,down]){
  assert.match(s,/NOT BETWEEN 2 AND 45/);
  assert.match(s,/project_ref='cdsmnqxtyyoeoznmbidd'/);
  assert.match(s,/workshop_clock_tick\(boolean,timestamptz\)'::regprocedure\)<>'84af7607bfd0ce9907c89bae8644d5b6'/);
  assert.doesNotMatch(s,/vjdtsswhroyguxyfjdkt/);
  assert.doesNotMatch(s,/@broometoyota|@pmgwa/);
 }
 assert.doesNotMatch(mig,/UPDATE pdc_sales_private\.account_scopes|INSERT INTO pdc_sales_private\.account_scopes/);
});
