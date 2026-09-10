'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {createWorkshopDataService}=require('./workshop-data-service');
const {buildWorkshopSharedActions}=require('./workshop-shared-actions');
async function setup(reject=false,role='administrator') {
 let block={id:'synthetic-admin',version:4,label:'Admin downtime'},calls=[];
 const service=createWorkshopDataService({config:{workshop:{sharedData:true}},getAccessToken:()=> 'test-token',getRole:()=>role,
 client:{rpc:async(token,name,params)=>{
   calls.push({name,params});
   if(name==='get_workshop_snapshot')return {ok:true,status:200,body:{revision:block.version,admin_blocks:[{...block}],bookings:[],vehicles:[]}};
   assert.equal(name,'rename_workshop_admin_block_20260904');
   if(reject)return {ok:true,status:200,body:{ok:false,error:'admin_block_version_conflict'}};
   assert.equal(params.p_expected_version,4);assert.equal(params.p_block_id,'synthetic-admin');
   block={...block,version:5,label:params.p_label};
   return {ok:true,status:200,body:{ok:true,code:'admin_block_renamed',admin_block:block}};
 }}});
 await service.loadSnapshot('test'); return {service,actions:buildWorkshopSharedActions(service),calls};
}
test('Admin description passes through the real action bridge and data service then reloads saved label',async()=>{
 const {service,actions,calls}=await setup();
 try {
 const result=await actions.renameAdminBlock({blockId:'synthetic-admin',expectedVersion:4,label:'John at TAFE'});
 assert.equal(result.ok,true);assert.equal(service.getTrustedSnapshot().admin_blocks[0].label,'John at TAFE');
 assert.deepEqual(calls.map(x=>x.name),['get_workshop_snapshot','rename_workshop_admin_block_20260904','get_workshop_snapshot']);
 } finally {service.destroy();}
});
test('Admin rename rejects missing version before a save request',async()=>{
 const {service,actions,calls}=await setup();
 try {assert.equal((await actions.renameAdminBlock({blockId:'synthetic-admin',label:'Hoist Broken'})).error,'missing_expected_version');
 assert.equal(calls.length,1);}finally{service.destroy();}
});
test('Rejected Admin rename reloads original description and never reports success',async()=>{
 const {service,actions}=await setup(true);
 try {const r=await actions.renameAdminBlock({blockId:'synthetic-admin',expectedVersion:4,label:'Hoist Broken'});
 assert.equal(r.ok,false);assert.equal(service.getTrustedSnapshot().admin_blocks[0].label,'Admin downtime');}finally{service.destroy();}
});
test('Versioned data service is loaded once before app initialization',()=>{
 const html=fs.readFileSync('index.html','utf8');
 assert.match(html,/id="workshop-data-service-script" data-loaded="true" src="workshop-data-service.js\?v=2026.09.10.02-admin-rename"/);
 assert.ok(html.indexOf('id="workshop-data-service-script"')<html.indexOf('<script src="app.js?'));
});

