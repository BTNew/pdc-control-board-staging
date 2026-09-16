'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const {createNavisionBackendService,NAVISION_STAGING_PROJECT_REF}=require('./navision-backend-service');
const {createFixture}=require('./qa/dashboard-render-fixture.cjs');
const f=createFixture({vehicleCount:0});f.loadHelper('navision-vin.js');
const rows=f.context.parseNavisionInput('Order\tBatch\tModel Description\tDealer\n101\t91000001\tHilux\t014450\n102\t91000002\tHilux\t001234\n103\t91000003\tHiace\t002345\n104\t91000004\tHilux\t090000').vehicles;
test('original Dealer columns support one combined preview without wrong-dealer conflicts',()=>{
 assert.equal(rows.length,4);
 assert.equal(f.context.navisionClientPreflight(rows,'combined').blocking,false);
 assert.equal(f.context.navisionClientPreflight(rows,'14450').blocking,true);
});
test('duplicates across dealer groups remain blocked; missing Dealer cannot be guessed',()=>{
 const duplicate={...rows[1],stock:rows[0].stock};
 assert.equal(f.context.navisionClientPreflight([rows[0],duplicate],'combined').blocking,true);
 assert.equal(f.context.navisionClientPreflight([{id:'a',stock:'a'}],'combined').issues[0].reason,'missing_dealer_column');
});
test('combined preview, approval and apply use one server request each',async()=>{
 const calls=[];
 const service=createNavisionBackendService({projectRef:NAVISION_STAGING_PROJECT_REF,getAccessToken:()=> 'fixture',client:{rpc:async(token,name,params)=>{calls.push({name,params});return {ok:true,status:200,body:{ok:true}};}}});
 const metadata={dealerCode:'combined',sourceName:'014450-export.xlsx'};
 await service.preview(rows,metadata);await service.approveInitialScope(rows,metadata);
 const preview={data:{preview_hash:'preview',source_hash:'source',base_revision:3,counts:{total:3},blocking:false}};
 await service.apply(rows,preview,{...metadata,confirmed:true,idempotencyKey:'request'});
 assert.deepEqual(calls.map(c=>c.name),['preview_navision_combined_import','approve_navision_combined_initial_scopes','apply_navision_combined_import']);
 assert.equal(calls[2].params.p_rows,rows);
 assert.equal(calls[2].params.p_expected_revision,3);
 assert.equal(calls[2].params.p_dealer_code,undefined);
 assert.equal(calls[2].params.p_source_name,'014450-export.xlsx');
 assert.equal((await service.apply(rows,preview,{...metadata})).error,'explicit_confirmation_required');
});
test('combined issue merge preserves original source indexes around excluded and reordered rows',()=>{
 const data={items:[{row_index:3,classification:'new'},{row_index:1,classification:'new'}]};
 const merged=f.context.mergeNavisionPreflightData(data,{blocking:true,issues:[{row_index:3,classification:'conflict',reason:'duplicate_stock_number'}]});
 assert.equal(merged.items[0].classification,'conflict');assert.equal(merged.items[1].classification,'new');
});
test('combined preview lists included counts and excluded stock/dealer for review',()=>{
 const html=f.context.renderNavisionCombinedSummary({dealer_groups:[{dealer_code:'14450',counts:{total:1}},{dealer_code:'001234',counts:{total:1}}],excluded_rows:[{stock_number:'91000004',dealer_code:'090000',row_index:4}]});
 assert.match(html,/014450/);assert.match(html,/001234/);assert.match(html,/91000004/);assert.match(html,/090000/);
 assert.match(fs.readFileSync('index.html','utf8'),/value="combined" selected/);
});
