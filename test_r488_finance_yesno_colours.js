/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r488 (F101): every Yes/No drop-down on the Finance table (Approval, Access, Payout Complete)
// uses Approval's solid colours: Yes = solid green + white text, No = solid dark red + white text, blank = neutral.
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const finance=require('./sales/finance-pipeline.js');
const source=fs.readFileSync(path.join(__dirname,'sales/finance-pipeline.js'),'utf8');
const css=fs.readFileSync(path.join(__dirname,'sales/finance-pipeline.css'),'utf8');
const html=fs.readFileSync(path.join(__dirname,'sales/index.html'),'utf8');
const YESNO=[['approval','Approval'],['access','Access'],['payout_complete','Payout Complete']];
const rows=[
 {id:'r-yes',customer:'Example Yes',new_used:'New',financier:'TFS',group_name:'Broome',approval:'Yes',settlement:'No',notes:'',access:'Yes',payout_complete:'Yes',salesperson_code:'ZZ',version:1},
 {id:'r-no',customer:'Example No',new_used:'Used',financier:'TFM',group_name:'Broome',approval:'No',settlement:'No',notes:'',access:'No',payout_complete:'No',salesperson_code:'ZZ',version:1},
 {id:'r-blank',customer:'Example Blank',new_used:'New',financier:'OTHER',group_name:'Port Hedland',approval:'',settlement:'No',notes:'',access:'',payout_complete:'',salesperson_code:'ZZ',version:1}
];
function harness(){
 const calls=[],elements=new Map();
 function el(id){if(!elements.has(id))elements.set(id,{id,innerHTML:'',textContent:'',hidden:false,disabled:false,dataset:{},events:{},attrs:{},
  addEventListener(n,h){this.events[n]=h;},setAttribute(n,v){this.attrs[n]=v;},getAttribute(n){return this.attrs[n];},removeAttribute(n){delete this.attrs[n];},
  focus(){},scrollIntoView(){},close(){},showModal(){},querySelector(){return {hidden:false,disabled:false,textContent:'',dataset:{},focus(){},querySelector(){return null;}};},querySelectorAll(){return [];}});return elements.get(id);}
 const window={setTimeout:()=>1,clearTimeout(){},document:{getElementById:el,activeElement:null},crypto:{randomUUID:()=>'x'},PDC_AUTH_CONTEXT:{userId:'t'},PDC_SUPABASE:{rpc(name,args){return new Promise(resolve=>calls.push({name,args,resolve}));}}};
 vm.runInNewContext(source,{window,globalThis:window,module:undefined,console,Map,Set,FormData:class{}});
 const api=window.BROOME_SALES_FINANCE;
 api.init({getToken:()=>'t',getContext:()=>({role:'administrator'}),getSalesperson:()=>'',getView:()=>'finance'});
 async function refresh(canEdit=true){const p=api.refresh();calls.at(-1).resolve({data:{context:{role:canEdit?'administrator':'salesperson',can_edit_finance:canEdit},entries:JSON.parse(JSON.stringify(rows)),vehicle_options:[],salespeople:[]}});await p;}
 const view=v=>el('sales-finance').events.click({target:{dataset:{financeView:v},hasAttribute:n=>n==='data-finance-view',closest(){return this;}}});
 return {el,api,refresh,view,calls,html:()=>el('sales-finance').innerHTML};
}
// class attribute of the <td> for one customer + column
function cellClass(page,customer,label){
 const body=page.match(/<tbody>([\s\S]*?)<\/tbody>/)?.[1]||'';
 const tr=Array.from(body.matchAll(/<tr>([\s\S]*?)<\/tr>/g)).map(m=>m[1]).find(t=>t.includes(customer));
 assert.ok(tr,'row for '+customer);
 const m=tr.match(new RegExp('<td class="([^"]*)" data-label="'+label+'">'));assert.ok(m,label+' cell for '+customer);
 return m[1].split(/\s+/).filter(Boolean);
}
function assertColours(page,where){
 for(const [,label] of YESNO){
  const yes=cellClass(page,'Example Yes',label),no=cellClass(page,'Example No',label),blank=cellClass(page,'Example Blank',label);
  assert.ok(yes.includes('finance-yesno')&&yes.includes('finance-yes')&&!yes.includes('finance-no'),where+' '+label+' Yes → green: '+yes);
  assert.ok(no.includes('finance-yesno')&&no.includes('finance-no')&&!no.includes('finance-yes'),where+' '+label+' No → dark red: '+no);
  assert.ok(blank.includes('finance-yesno')&&!blank.includes('finance-yes')&&!blank.includes('finance-no'),where+' '+label+' blank → neutral: '+blank);
 }
}

test('r488: yesNoCellClass gives Yes green, No dark red and blank neutral for Approval, Access and Payout Complete',()=>{
 assert.deepEqual(finance.yesNoColumns,['approval','access','payout_complete']);
 for(const [key] of YESNO){
  assert.equal(finance.yesNoCellClass(key,'Yes'),'finance-yesno finance-yes',key);
  assert.equal(finance.yesNoCellClass(key,'No'),'finance-yesno finance-no',key);
  for(const v of ['','—',null,undefined,'yes','no','Declined'])assert.equal(finance.yesNoCellClass(key,v),'finance-yesno',key+' '+String(v));
 }
 for(const key of ['customer','settlement','notes','financier','group_name','new_used'])assert.equal(finance.yesNoCellClass(key,'Yes'),'',key+' is not a Yes/No drop-down');
 // every column offering only Yes/No (plus blank) as a drop-down is covered; Settlement is a date picker, not a drop-down
 const dropdownYesNo=Object.entries(finance.choices).filter(([k,v])=>k!=='settlement'&&v.filter(Boolean).sort().join()==='No,Yes').map(([k])=>k);
 assert.deepEqual(dropdownYesNo.sort(),[...finance.yesNoColumns].sort());
});

test('r488: Active finance pipeline and All applications render the colour classes on each Yes/No cell',async()=>{
 const h=harness();await h.refresh();
 assert.match(h.html(),/ACTIVE FINANCE PIPELINE/);assertColours(h.html(),'pipeline');
 h.view('all');assert.match(h.html(),/ALL FINANCE APPLICATIONS/);assertColours(h.html(),'all');
 // Approval keeps its r428 scope class too
 assert.ok(cellClass(h.html(),'Example Yes','Approval').includes('finance-approval'));
 assert.ok(!cellClass(h.html(),'Example Yes','Access').includes('finance-approval'));
});

test('r488: read-only (salesperson) view colours the plain Yes/No text the same way',async()=>{
 const h=harness();await h.refresh(false);assert.doesNotMatch(h.html(),/<select[^>]*data-finance-key="access"/);assertColours(h.html(),'read-only');
});

test('r488: changing Access / Payout Complete recolours the cell straight away (Yes, No, blank)',async()=>{
 const h=harness();await h.refresh();
 for(const key of ['access','payout_complete']){
  const classes=new Set(['finance-yesno']),td={classList:{contains:c=>classes.has(c),toggle:(c,on)=>on?classes.add(c):classes.delete(c),remove:c=>classes.delete(c)}};
  const tr={querySelector(){return {hidden:true,disabled:false,textContent:'',title:'',querySelector(){return null;}};}};
  const input=value=>h.el('sales-finance').events.input({target:{dataset:{financeId:'r-blank',financeKey:key,financeVersion:'1'},value,closest:s=>s==='td'?td:tr}});
  input('Yes');assert.ok(classes.has('finance-yes')&&!classes.has('finance-no'),key+' Yes');
  input('No');assert.ok(classes.has('finance-no')&&!classes.has('finance-yes'),key+' No');
  input('');assert.ok(!classes.has('finance-yes')&&!classes.has('finance-no'),key+' blank');
 }
});

test('r488: CSS copies Approval exactly: solid #2e7d32 Yes and #c62828 No with white bold text, white arrow, plain options',()=>{
 const approvalYes=css.match(/td\.finance-approval\.finance-yes\{([^}]*)\}/)[1],approvalNo=css.match(/td\.finance-approval\.finance-no\{([^}]*)\}/)[1];
 assert.equal(css.match(/td\.finance-yesno\.finance-yes\{([^}]*)\}/)[1],approvalYes);
 assert.equal(css.match(/td\.finance-yesno\.finance-no\{([^}]*)\}/)[1],approvalNo);
 assert.equal(approvalYes,'background:#2e7d32;color:#fff;font-weight:700');
 assert.equal(approvalNo,'background:#c62828;color:#fff;font-weight:700');
 assert.equal(css.match(/td\.finance-yesno\.finance-yes select\{([^}]*)\}/)[1],css.match(/td\.finance-approval\.finance-yes select\{([^}]*)\}/)[1]);
 assert.equal(css.match(/td\.finance-yesno\.finance-no select\{([^}]*)\}/)[1],css.match(/td\.finance-approval\.finance-no select\{([^}]*)\}/)[1]);
 assert.match(css,/td\.finance-yesno select option\{background:#fff;color:#173b57;font-weight:400\}/);
 assert.doesNotMatch(css,/td\.finance-yesno(?!\.finance-(?:yes|no)\b)[^{,]*\{[^}]*background(?:-color)?:#(?:2e7d32|c62828)/,'blank Yes/No cells stay neutral');
});

test('r488: cache bust and FAULT_LOG F101',()=>{
 assert.match(html,/finance-pipeline\.css\?v=2026\.10\.06\.01&amp;approval-dark=2026\.10\.21\.01&amp;yesno-dark=2026\.10\.22\.01/);
 assert.match(html,/finance-pipeline\.js\?v=2026\.10\.06\.01&amp;approval-dark=2026\.10\.21\.01&amp;yesno-dark=2026\.10\.22\.01/);
 assert.ok(/^\| F101 \| 22 Oct /m.test(fs.readFileSync(path.join(__dirname,'docs/FAULT_LOG.md'),'utf8')),'FAULT_LOG row F101');
});
