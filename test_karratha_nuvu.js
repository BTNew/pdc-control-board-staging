'use strict';
const test=require('node:test');const assert=require('node:assert/strict');const crypto=require('node:crypto');const fs=require('node:fs');const path=require('node:path');
const intake=require('./karratha/pd135-nuvu-intake.js');
const parentHash='a'.repeat(64),hash=text=>Promise.resolve(crypto.createHash('sha256').update(text).digest('hex'));
const row=(stock='000123',job='000456',line=7,extra={})=>({stock_number:stock,repair_order_number:job,original_line_number:line,operation_description:'Fit item\nretain complete source description',source_estimated_hours:1.25,store_code:'135',stage_code:'FITTING',raw_row:{Stock:stock,RO:job,Line:line,Quoted:'first\nsecond',Amount:2.3},...extra});
function fixture(rpc){let authority='actor:membership1';const calls=[];const model=intake.create({getAuthority:()=>authority,hash,rpc:async(name,payload)=>{calls.push({name,payload});return rpc(name,payload,calls.length);}});return {model,calls,setAuthority:value=>authority=value};}
const preview=payload=>({ok:true,preview_batch_id:'own-preview',source_hash:payload.p_source_hash,workbook_sha256:parentHash,apply_allowed:true,source_rows:payload.p_rows.length,accepted_lines:payload.p_rows.length,operations:{insert:payload.p_rows.length}});
const applied=payload=>({ok:true,code:'applied',source_hash:payload.p_source_hash,atomic:true,approvals_created:0,bookings_created:0,completions_created:0});

test('source groups use exact stock plus job card and preserve complete typed raw evidence',()=>{
 const rows=[row(),row('000123','000999',8),row('000123','000456',9)],original=JSON.stringify(rows);
 const groups=intake.groupRows(rows,parentHash);assert.equal(groups.length,2);assert.equal(groups[0].rows.length,2);assert.equal(groups[1].job,'000999');
 assert.equal(groups[0].rows[0].line.stock_number,'000123');assert.equal(groups[0].rows[0].line.department,'135');assert.equal(groups[0].rows[0].line.raw_row.Amount,2.3);assert.equal(groups[0].rows[0].line.raw_row.Quoted,'first\nsecond');assert.equal(groups[0].rows[0].line.raw_row.parent_attachment_sha256,parentHash);assert.equal(JSON.stringify(rows),original);
});
test('missing identities/lines and foreign stores remain visible and cannot be selected',()=>{
 const f=fixture(()=>{});f.model.setRows([row('', '000456',null),row('other','other',8,{store_code:'139'}),row('third','third',9,{source_estimated_hours:1.234})],parentHash);
 assert.equal(f.model.state().cards.length,3);for(const card of f.model.state().cards)assert.throws(()=>f.model.select(card.key,true),/source review/);assert.equal(f.calls.length,0);
});
test('unknown stations stay REVIEW; missing hours are retained without inventing an estimate',()=>{
 const groups=intake.groupRows([row('001','002',1,{stage_code:'BUS_4X4',source_estimated_hours:null})],parentHash);assert.equal(groups[0].rows[0].line.proposed_station,'REVIEW');assert.equal(groups[0].rows[0].line.source_estimated_hours,null);
});
test('only explicitly selected job cards reach native preview, in original row order',async()=>{
 const f=fixture((_name,payload)=>preview(payload));f.model.setRows([row('1','A',1),row('2','B',2),row('1','A',3)],parentHash);assert.equal(f.model.state().selected.size,0);assert.equal(f.calls.length,0);
 f.model.select(f.model.state().cards[0].key,true);await f.model.preview();assert.equal(f.calls[0].name,'pdc_pilbara_service_preview_v1');assert.deepEqual(f.calls[0].payload.p_rows.map(line=>line.original_line_number),[1,3]);assert.equal(f.model.state().preview.apply_allowed,true);assert.equal(f.model.state().result,null);
});
test('uncertain preview retry keeps byte-identical rows, source hash and nonce',async()=>{
 const f=fixture((_name,payload,count)=>{if(count===1)throw new Error('Connection interrupted');return preview(payload);});f.model.setRows([row()],parentHash);f.model.select(f.model.state().cards[0].key,true);await f.model.preview();assert.match(f.model.state().error,/interrupted/);await f.model.preview();assert.deepEqual(f.calls[0].payload,f.calls[1].payload);assert.throws(()=>f.model.state().attempt.rows[0].stock_number='changed');
});
test('selection edits invalidate the earlier preview and require a new native review',async()=>{
 const f=fixture((_name,payload)=>preview(payload));f.model.setRows([row(),row('other','job',8)],parentHash);f.model.select(f.model.state().cards[0].key,true);await f.model.preview();const nonce=f.calls[0].payload.p_idempotency_key;f.model.select(f.model.state().cards[1].key,true);assert.equal(f.model.state().preview,null);await assert.rejects(f.model.apply(),/Review/);await f.model.preview();assert.notEqual(f.calls[1].payload.p_idempotency_key,nonce);assert.equal(f.calls[1].payload.p_rows.length,2);
});
test('native apply is explicit and uncertain retry reuses the same receipt identity',async()=>{
 let applies=0;const f=fixture((name,payload)=>{if(name.includes('preview'))return preview(payload);if(++applies===1)throw new Error('Unknown response');return applied(payload);});f.model.setRows([row()],parentHash);f.model.select(f.model.state().cards[0].key,true);await f.model.preview();assert.equal(f.calls.length,1);await f.model.apply();await f.model.apply();assert.equal(f.calls[1].name,'pdc_pilbara_service_apply_v1');assert.deepEqual(f.calls[1].payload,f.calls[2].payload);assert.equal(f.model.state().result.approvals_created,0);
});
test('delayed source responses cannot restore evidence after account replacement or clearing',async()=>{
 let done;const f=fixture((_name,payload)=>new Promise(resolve=>done=()=>resolve(preview(payload))));f.model.setRows([row()],parentHash);f.model.select(f.model.state().cards[0].key,true);const pending=f.model.preview();await new Promise(resolve=>setImmediate(resolve));f.setAuthority('another-user');f.model.clear();done();await pending;assert.equal(f.model.state().cards.length,0);assert.equal(f.model.state().preview,null);assert.equal(f.model.state().attempt,null);
});
test('mismatched source hash or workbook hash is rejected without an import claim',async()=>{
 for(const wrong of ['source','workbook']){const f=fixture((_name,payload)=>({...preview(payload),[wrong==='source'?'source_hash':'workbook_sha256']:'b'.repeat(64)}));f.model.setRows([row()],parentHash);f.model.select(f.model.state().cards[0].key,true);await f.model.preview();assert.equal(f.model.state().preview,null);assert.equal(f.model.state().result,null);assert.ok(f.model.state().error);}
});
test('adapter text is escaped and pinned SheetJS loads before file parsing and native queue',()=>{
 assert.equal(intake.esc('<img onerror="evil">'),'&lt;img onerror=&quot;evil&quot;&gt;');
 const html=fs.readFileSync(path.join(__dirname,'karratha/index.html'),'utf8');assert.ok(html.includes('integrity="sha384-EnyY0/GSHQGSxSgMwaIPzSESbqoOLSexfnSMN2AP+39Ckmn92stwABZynq1JyzdT"'));assert.ok(html.indexOf('vendor/xlsx/xlsx.full.min.js')<html.indexOf('pd135-nuvu-parser.js'));
 assert.equal(crypto.createHash('sha384').update(fs.readFileSync(path.join(__dirname,'karratha/vendor/xlsx/xlsx.full.min.js'))).digest('base64'),'EnyY0/GSHQGSxSgMwaIPzSESbqoOLSexfnSMN2AP+39Ckmn92stwABZynq1JyzdT');
});
