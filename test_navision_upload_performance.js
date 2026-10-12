'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const folder=path.join(__dirname,'supabase','migrations');
const migrations=fs.readdirSync(folder).filter(f=>f.endsWith('.sql')).sort().map(f=>fs.readFileSync(path.join(folder,f),'utf8')).join('\n');
function latestBody(name,predicate=()=>true){
 const pattern=new RegExp(`CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+public\\.${name}\\s*\\(([\\s\\S]*?)\\)\\s+RETURNS[\\s\\S]*?AS\\s+(\\$[a-z0-9_]*\\$)([\\s\\S]*?)\\2`,'gi');
 const matches=[...migrations.matchAll(pattern)].filter(m=>predicate(m[1]));
 assert.ok(matches.length,`Missing function ${name}`);
 return matches.at(-1)[3];
}
test('scoped Navision preview performs one normalisation per source row across hash and identity checks',()=>{
 const body=latestBody('navision_backend_preview_internal',args=>args.includes('p_dealer_code'));
 assert.equal((body.match(/public\.navision_backend_normalize_row\(/g)||[]).length,1);
 assert.equal((body.match(/public\.navision_backend_row_hash\(/g)||[]).length,0);
 assert.match(body,/with prepared as materialized/i);
 assert.match(body,/into v_source_hash\s*,\s*v_items/i);
 for(const guard of ['duplicate_source_record_id','ambiguous_canonical_identity','forbidden_operational_field','legacy_claim_requires_administrator'])assert.ok(body.includes(guard),guard);
});
test('apply reuses its validated preview row hashes and preserves exact-source and revision guards',()=>{
 const body=latestBody('apply_navision_backend_import_preholding_055');
 assert.match(body,/v_row_hash\s*:=\s*v_item\s*->>\s*'row_hash'/);
 assert.match(body,/v_source_record_id\s*:=\s*v_item\s*->>\s*'source_record_id'/);
 for(const guard of ['unauthorized','source_changed','preview_changed','stale_revision','blocking_reconciliation','idempotency_conflict'])assert.ok(body.includes(guard),guard);
 assert.match(body,/navision_import_items/);
 assert.match(body,/navision_operation_receipts/);
});
