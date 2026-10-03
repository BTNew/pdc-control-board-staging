'use strict';
// Executes the real app event handlers against fictional state and a minimal DOM.
// This tests account/scope/form behavior; visual layout is verified in the browser.
const test=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const code=fs.readFileSync(path.resolve(__dirname,'./karratha/app.js'),'utf8');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const baseContext={centre:'KARRATHA',user_id:'fixture-a',role:'administrator',display_name:'Fictional staff',membership_version:1,can_edit:true,can_admin:true,can_import:true};
const baseSnapshot={revision:1,context:baseContext,vehicles:[{id:'v1',stock_number:'0012345',customer_name:'Fictional Customer',model:'Example vehicle',location:'on_site',source_current:true}],
 jobs:[{id:'j1',vehicle_id:'v1',selected:true,identity_status:'matched',job_card_number:'RO1',version:1},
 {id:'j2',vehicle_id:'v1',selected:false,identity_status:'matched',job_card_number:'RO2',version:1},
 {id:'j3',vehicle_id:null,selected:false,identity_status:'unmatched',job_card_number:'RO-unmatched',stock_number:'',store_code:'135',version:1}],
 operations:[{id:'o1',vehicle_id:'v1',job_id:'j1',original_line_number:1,description:'First selected operation',stage_code:'FITTING',estimated_hours:1,source_estimated_hours:1,parts_required:false,version:1},
 {id:'o2',vehicle_id:'v1',job_id:'j2',original_line_number:2,description:'Second card operation',stage_code:'TINT',estimated_hours:1,source_estimated_hours:1,parts_required:false,version:1},
 {id:'o3',job_id:'j3',original_line_number:3,description:'Unmatched original description',stage_code:'REVIEW',parts_required:null,source_row:{note:'Original raw evidence'},version:1}],
 bookings:[],bays:[],technicians:[],history:[],memberships:[],settings:[{id:'set1',key:'import_contract',version:1,value:{mapping_verified:true,column_mapping:{},allowed_dealer_codes:['14450']}},{id:'set2',key:'calendar',value:{day_start:'06:00',day_end:'16:30'}}]};
function harness(options={}){
 let context={...baseContext,...options.context},epoch=1,snapshot=structuredClone({...baseSnapshot,context}),changed;
 const elements=new Map(),listeners={},intervals=[],calls=[];
 class Element{
  constructor(id){this.id=id;this.innerHTML='';this.textContent='';this.open=false;this.value='';this.hidden=false;this.disabled=false;this.listeners={};this.classes=new Set();this.elements={};this.values={};
   this.classList={add:name=>this.classes.add(name),remove:name=>this.classes.delete(name),contains:name=>this.classes.has(name),toggle:(name,force)=>{if(force??!this.classes.has(name))this.classes.add(name);else this.classes.delete(name);}};}
  addEventListener(name,handler){this.listeners[name]=handler;}
  setAttribute(name,value){this[name]=value;}
  replaceChildren(){this.innerHTML='';this.textContent='';}
  showModal(){this.open=true;}
  close(){this.open=false;this.listeners.close?.({target:this});}
  querySelector(){return element(this.id+'-submit');}
 }
 function element(id){if(!elements.has(id))elements.set(id,new Element(id));return elements.get(id);}
 const document={hidden:false,getElementById:element,addEventListener(name,handler){listeners[name]=handler;}};
 const api={clear(){calls.push({clear:true});},async snapshot(){calls.push({snapshot:true});if(options.snapshotHandler)return options.snapshotHandler();return structuredClone(snapshot);},async save(action,id,version,data){calls.push({action,id,version,data});return {record:{id,version:version+1}};}};
 const auth={getContext:()=>context,getOwner:()=>context?.user_id+':'+epoch,onChanged(handler){changed=handler;},adoptContext(data){context={...data};},lock(){context=null;epoch++;changed?.();}};
 const nuvu={fields:[],async read(file){return {name:file.name,hash:'fixture-hash',sheets:['Data']};},table(){return {headers:['Stock'],rows:[{}]};}};
 const window={KARRATHA_API:api,KARRATHA_AUTH:auth,KARRATHA_NUVU:nuvu,KARRATHA_CALENDAR:{add:(date,n)=>{const d=new Date(date+'T12:00Z');d.setUTCDate(d.getUTCDate()+n);return d.toISOString().slice(0,10);},days:()=>['2030-01-01'],init(){},render(){}},
  KARRATHA_AUTH_READY:Promise.resolve(),crypto:require('node:crypto').webcrypto,setInterval(fn){intervals.push(fn);},addEventListener(){}};
 class FormDataFixture{constructor(node){this.values=node.values;}get(name){return this.values[name]??'';}has(name){return Object.hasOwn(this.values,name);}}
 vm.runInNewContext(code,{window,document,FormData:FormDataFixture,Intl,Date,Set,Map,Array,Object,String,Number,Boolean,JSON,Promise});
 return {window,e:element,calls,async ready(){await tick();},setSnapshot(data){snapshot=structuredClone(data);},async click(dataset){listeners.click({target:{closest(){return {dataset,hasAttribute(name){return Object.hasOwn(dataset,name.replace(/^data-/,'').replace(/-([a-z])/g,(_,a)=>a.toUpperCase()));}};}}});await tick();},
  async change(target){listeners.change({target});await tick();},async poll(){intervals[0]();await tick();},async changeContext(value){context=value;epoch++;changed();await tick();},
  async submit(values){element('edit-form').values=values;await element('edit-form').listeners.submit({preventDefault(){},currentTarget:element('edit-form')});await tick();}};
}
test('unmatched card opens original work review without a vehicle',async()=>{
 const h=harness();await h.ready();await h.click({job:'j3'});
 assert.equal(h.e('detail-dialog').open,true);assert.match(h.e('detail-content').innerHTML,/RO-unmatched/);
 assert.match(h.e('detail-content').innerHTML,/Unmatched original description/);assert.match(h.e('detail-content').innerHTML,/Original raw evidence/);
 assert.doesNotMatch(h.e('detail-content').innerHTML,/data-book-operation|data-parts|data-location/);
});
test('viewer sees no editor or administrator buttons and synthetic edit clicks do not write',async()=>{
 const h=harness({context:{role:'viewer',can_edit:false,can_admin:false,can_import:false}});await h.ready();await h.click({job:'j1'});
 assert.doesNotMatch(h.e('detail-content').innerHTML,/data-operation|data-parts|data-book-operation|data-external|data-deselect/);
 assert.doesNotMatch(h.e('navigation').innerHTML,/Centre settings/);await h.click({operation:'o1'});
 assert.equal(h.e('edit-dialog').open,false);assert.equal(h.calls.filter(call=>call.action).length,0);
});
test('active vehicle board does not include unselected and unmatched cards',async()=>{
 const h=harness();await h.ready();assert.match(h.e('page-content').innerHTML,/RO1/);
 assert.doesNotMatch(h.e('page-content').innerHTML,/RO2|RO-unmatched|Second card operation/);
});
test('polling preserves dirty open forms and uses the captured expected version',async()=>{
 const h=harness();await h.ready();await h.click({parts:'o1'});assert.equal(h.e('edit-dialog').open,true);
 h.e('edit-content').innerHTML+='DIRTY_UNSAVED_TEXT';const next=structuredClone(baseSnapshot);next.operations[0].version=2;h.setSnapshot(next);await h.poll();
 assert.equal(h.e('edit-dialog').open,true);assert.match(h.e('edit-content').innerHTML,/DIRTY_UNSAVED_TEXT/);
 await h.submit({received:'on',location:'Fictional shelf',notes:'User draft'});
 const save=h.calls.find(call=>call.action==='parts');assert.equal(save.version,1);assert.equal(save.id,'o1');assert.equal(save.data.notes,'User draft');
});
test('account or capability loss discards dialogs and source preview/file state',async()=>{
 const h=harness();await h.ready();await h.window.KARRATHA_APP.showView('newvehicles');await tick();
 await h.change({id:'nuvu-file',dataset:{},files:[{name:'Fictional-source.xlsx'}]});assert.match(h.e('page-content').innerHTML,/Fictional-source.xlsx/);
 await h.click({operation:'o1'});assert.equal(h.e('edit-dialog').open,true);
 await h.changeContext({...baseContext,role:'viewer',can_edit:false,can_admin:false,can_import:false,membership_version:2});
 assert.equal(h.e('edit-dialog').open,false);assert.equal(h.e('detail-dialog').open,false);assert.equal(h.e('edit-content').innerHTML,'');
 assert.doesNotMatch(h.e('page-content').innerHTML,/Fictional-source.xlsx|data-apply-import|data-confirm-mapping/);
 await h.changeContext(null);assert.equal(h.e('page-content').innerHTML,'');assert.ok(h.calls.some(call=>call.clear));
});
test('approval sends only explicitly selected exact job-card IDs',async()=>{
 const h=harness();await h.ready();h.window.KARRATHA_APP.showView('newvehicles');await tick();
 await h.change({id:'check',dataset:{selectJob:'j2'},checked:true});await h.click({approveSelected:''});
 const saves=h.calls.filter(call=>call.action==='job_selection');assert.equal(saves.length,1);assert.equal(saves[0].id,'j2');assert.equal(saves[0].version,1);assert.equal(saves[0].data.selected,true);
});
test('Sunday calendar selection submits ISO weekday seven and a supported increment',async()=>{
 const h=harness();await h.ready();const next=structuredClone(baseSnapshot);
 next.settings[1].value={timezone:'Australia/Perth',working_week:[7],day_start:'06:00',day_end:'16:30',scheduling_increment_minutes:15,break_windows:[],closures:[],future_only:true};
 h.setSnapshot(next);await h.window.KARRATHA_APP.refresh();await h.click({calendarSettings:''});
 assert.match(h.e('edit-content').innerHTML,/name="weekday_7" checked/);
 assert.doesNotMatch(h.e('edit-content').innerHTML,/name="weekday_0"/);
 await h.submit({weekday_7:'on',day_start:'06:00',day_end:'16:30',increment:'15',breaks:'',closures:''});
 const save=h.calls.find(call=>call.action==='setting');assert.deepEqual(Array.from(save.data.value.working_week),[7]);assert.equal(save.data.value.scheduling_increment_minutes,15);
});
