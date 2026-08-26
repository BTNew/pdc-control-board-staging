'use strict';
const assert=require('assert'),fs=require('fs');
const sql=fs.readFileSync('supabase/staging_only/20260827032000_482_jobcard_header_only_all_lines.sql','utf8');
const app=fs.readFileSync('app.js','utf8');
for(const marker of ['pdc_owner_jobcard_import_rules_482','first-op-header-only','all-pre-delivery-1.5-hours','every-jobcard-op-visible','pdc_email_header_only_runtime_binding_482','Unallocated - mapping review']) assert.ok(sql.includes(marker),marker);
const match=sql.match(/\$ops\$(\[[\s\S]*?\])\$ops\$/);assert.ok(match,'manifest missing');const ops=JSON.parse(match[1]);
assert.strictEqual(ops.length,22);assert.deepStrictEqual(ops.map(x=>x.operation_no),Array.from({length:22},(_,i)=>`OP${i+1}`));
assert.strictEqual(ops.find(x=>x.operation_no==='OP2').description,'Pre-Delivery (Commercial)');assert.strictEqual(ops.find(x=>x.operation_no==='OP2').estimated_hours,1.5);
assert.strictEqual(ops.filter(x=>x.work_key==='owner_supplied_document').length,14);assert.strictEqual(ops.filter(x=>x.estimated_hours===null).length,5);assert.strictEqual(ops.filter(x=>x.estimated_hours===0).length,7);
for(const op of ops){assert.doesNotMatch(op.description,/(^| )(?:CN|SN) |Notes :/);assert.ok(op.description.length<=180);}
assert.ok(sql.includes("manifest_sha256='3a59213d5120954eddd3cbc049b3eecde65e1f72f315b08d474f34ef3fed3468'"));
assert.match(app,/OWNER_SUPPLIED_DOCUMENT: \{ label: 'Unallocated – mapping review'/);
assert.match(app,/function vehicleWorkshopAdjustedSourceDescription[\s\S]{0,180}adjustment\?\.description \?\? line\?\.description/);
assert.doesNotMatch(app,/if \(line\?\.authenticatedEmailOperation === true\) return String\(line\.description/);
console.log('Job Card header-only all-lines 482: PASS');
