(function(root){
'use strict';
const columns=[['customer','Customer'],['new_used','New / Used'],['financier','Financier'],['group_name','Group'],['approval','Approval'],['finance_comm','Finance Comm'],['dof_daf','DOF/DAF'],['mvi','MVI'],['rsa','RSA'],['total_comm','Total Comm'],['naf','NAF'],['settlement','Settlement'],['notes','Notes'],['access','Access'],['payout_complete','Payout Complete']];
const amounts=new Set(['finance_comm','dof_daf','mvi','rsa','naf']),privateFields=new Set(['financier',...amounts,'total_comm']);
const choices={financier:['','TFS','TFM','FARADAY','OTHER'],new_used:['New','Used'],group_name:['Broome','Port Hedland'],approval:['','Yes','No'],settlement:['','Yes','No'],access:['','Yes','No'],payout_complete:['','Yes','No']};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function money(value){if(value===''||value==null)return null;const text=String(value).trim();if(!/^\d+(?:\.\d{1,2})?$/.test(text)||Number(text)>999999999.99)throw new Error('Use a positive amount with up to two decimal places.');return Number(text);}
function total(data){return ['finance_comm','dof_daf','mvi','rsa'].reduce((n,k)=>n+Math.round((Number(data[k])||0)*100),0)/100;}
function patch(key,value){
 if(key==='settlement_date'){const date=String(value||'');if(date&&!validSettlementDate(date))throw new Error('Use a valid settlement date up to today.');return {settlement:date?'Yes':'No',settlement_date:date};}
 if(!columns.some(([k])=>k===key)||key==='total_comm')throw new Error('Choose an editable finance field.');
 if(amounts.has(key))return {[key]:money(value)};
 const text=String(value??'').trim();if(text.length>(key==='notes'?4000:200))throw new Error('This field is too long.');
 if(choices[key]&&!choices[key].includes(text))throw new Error('Choose a valid '+columns.find(([k])=>k===key)[1]+'.');
 if(key==='customer'&&!text)throw new Error('Enter the customer name.');return {[key]:text};
}
function projection(entries){
 // Only explicitly saved applications can supply a salesperson's finance summary.
 const latest=new Map();for(const r of [...entries].sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at))||String(b.id).localeCompare(String(a.id))))if(r.tracking_id&&!latest.has(r.tracking_id))latest.set(r.tracking_id,r);
 return [...latest.values()].map(r=>({id:r.id,tracking_id:r.tracking_id,version:r.version,current_application:true,approval_status:r.approval==='Yes'?'approved':r.approval==='No'?'declined':'not_started',settlement_status:r.settlement==='Yes'?'settled':r.settlement==='No'?'pending':'not_started',settlement_date:r.settlement_date||'',access_status:r.access==='Yes'?'active':r.access==='No'?'not_required':'',payout_status:r.payout_complete==='Yes'?'complete':r.payout_complete==='No'?'pending':'',shared_update:r.notes||''}));
}

function matchVehicles(rows,text){
 const terms=String(text||'').trim().toLowerCase().split(/\s+/).filter(Boolean);
 if(!terms.length)return [];
 const query=terms.join(' '),rank=r=>[r.stock,r.order].some(v=>String(v||'').toLowerCase()===query)?0:
  [r.stock,r.order].some(v=>String(v||'').toLowerCase().startsWith(query))?1:String(r.client||'').toLowerCase().startsWith(query)?2:3;
 return rows.filter(r=>terms.every(t=>[r.stock,r.order,r.client,r.vehicle].some(v=>String(v||'').toLowerCase().includes(t))))
  .slice().sort((a,b)=>rank(a)-rank(b)||String(a.client||'').localeCompare(String(b.client||''))||String(a.stock||a.order||'').localeCompare(String(b.stock||b.order||''),undefined,{numeric:true}));
}

function perthDay(now=new Date()){const p=new Intl.DateTimeFormat('en-AU',{timeZone:'Australia/Perth',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);return ['year','month','day'].map(k=>p.find(x=>x.type===k).value).join('-');}
function validSettlementDate(value,today=perthDay()){
 if(!/^\d{4}-\d{2}-\d{2}$/.test(value)||value<'1900-01-01'||value>today)return false;
 const date=new Date(value+'T00:00:00Z');return !Number.isNaN(date.getTime())&&date.toISOString().slice(0,10)===value;
}
function financierGroup(value){const text=String(value||'').toUpperCase();return /^TFS(?:\s|$)/.test(text)?'TFS':/^TFM(?:\s|$)/.test(text)?'TFM':text==='FARADAY'?'FARADAY':'OTHER';}
function financeGroup(value){
 const text=String(value||'').trim().toLowerCase().replace(/\s+/g,' ');
 return text==='broome'?'broome':['pilbara','port hedland'].includes(text)?'pilbara':'';
}
function financeStatistics(rows,month=perthDay().slice(0,7),filters={}){
 rows=rows.filter(r=>(!filters.group||filters.group==='all'||financeGroup(r.group_name)===filters.group)&&(!filters.newUsed||filters.newUsed==='all'||String(r.new_used||'').trim().toLowerCase()===filters.newUsed));
 const settled=rows.filter(r=>r.settlement==='Yes'),pipeline=rows.filter(r=>r.settlement!=='Yes');
 const dated=settled.filter(r=>validSettlementDate(r.settlement_date||'')),undated=settled.filter(r=>!validSettlementDate(r.settlement_date||''));
 const selected=month==='all'?settled:month==='undated'?undated:dated.filter(r=>r.settlement_date.slice(0,7)===month);
 const sum=(list,key)=>Math.round(list.reduce((n,r)=>n+Math.round((Number(key==='total_comm'?total(r):r[key])||0)*100),0))/100;
 const products=list=>({rsaCount:list.filter(r=>Number(r.rsa)>0).length,rsaTotal:sum(list,'rsa'),accessCount:list.filter(r=>r.access==='Yes').length,mviCount:list.filter(r=>Number(r.mvi)>0).length,mviTotal:sum(list,'mvi')});
 const months=[...new Set(dated.map(r=>r.settlement_date.slice(0,7)))].sort().reverse().map(key=>{const list=dated.filter(r=>r.settlement_date.slice(0,7)===key);return {month:key,count:list.length,naf:sum(list,'naf'),commission:sum(list,'total_comm'),...products(list)};});
 return {settled:selected,pipeline,settledCount:selected.length,contractCount:selected.length,...products(selected),naf:sum(selected,'naf'),commission:sum(selected,'total_comm'),pipelineCount:pipeline.length,pipelineNaf:sum(pipeline,'naf'),approved:pipeline.filter(r=>r.approval==='Yes').length,undated:undated.length,months,
  financiers:['TFS','TFM','FARADAY','OTHER'].map(name=>({name,pipeline:pipeline.filter(r=>financierGroup(r.financier)===name).length,settled:selected.filter(r=>financierGroup(r.financier)===name).length}))};
}

const filterAmounts=new Set([...amounts,'total_comm']);
function financeFilterValue(row,key){
 if(key==='settlement')return row.settlement==='Yes'?(validSettlementDate(row.settlement_date||'')?row.settlement_date:'undated'):'';
 if(key==='total_comm')return String(total(row));
 const value=row[key];if(value==null||String(value).trim()==='')return '';
 return filterAmounts.has(key)&&Number.isFinite(Number(value))?String(Number(value)):String(value).trim();
}
function financeFilterOptions(rows,key,canEdit=false){
 if(!columns.some(([k])=>k===key)||(!canEdit&&privateFields.has(key)))return [];
 return [...new Set(rows.map(r=>financeFilterValue(r,key)))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true,sensitivity:'base'}));
}
function filterFinanceEntries(rows,filters={},canEdit=false){
 const rules=Object.entries(filters).filter(([key])=>columns.some(([k])=>k===key)&&(canEdit||!privateFields.has(key)));
 return rows.filter(row=>rules.every(([key,rule])=>{
  const value=financeFilterValue(row,key);
  if(rule.mode==='blank'&&value!=='')return false;
  if(rule.mode==='value'&&value!==String(rule.value??''))return false;
  if(rule.query&&!value.toLowerCase().includes(String(rule.query).trim().toLowerCase()))return false;
  if(filterAmounts.has(key)&&((rule.min??'')!==''||(rule.max??'')!=='')){
   if(value===''||!Number.isFinite(Number(value)))return false;
   if((rule.min??'')!==''&&(!Number.isFinite(Number(rule.min))||Number(value)<Number(rule.min)))return false;
   if((rule.max??'')!==''&&(!Number.isFinite(Number(rule.max))||Number(value)>Number(rule.max)))return false;
  }
  return true;
 }));
}

const api={columns,choices,patch,money,total,projection,matchVehicles,perthDay,validSettlementDate,financeGroup,financeStatistics,financeFilterValue,financeFilterOptions,filterFinanceEntries};if(typeof module==='object'&&module.exports)module.exports=api;root.BROOME_SALES_FINANCE=api;
if(!root.document)return;
const $=id=>root.document.getElementById(id);let options,entries=[],refs=[],people=[],ctx=null,epoch=0,request=0,principal='',scope='',drafts=new Map(),busy=new Set(),message='',creating=null,createBusy=false;
const token=()=>options?.getToken?.(),selected=()=>options?.getSalesperson?.()||'';
const editor=()=>ctx?.can_edit_finance===true;
const visible=()=>entries.filter(r=>!selected()||r.salesperson_code===selected());
const candidates=()=>refs.filter(r=>!selected()||r.salesperson_code===selected());
let financeView='pipeline',statisticsMonth=perthDay().slice(0,7),statisticsGroup='all',statisticsNewUsed='all',dateRenderPending=false;
let vehicleMatches=[],activeMatch=-1,pickedCustomer='',columnFilters={},filterEditing=null;
function close(){vehicleMatches=[];activeMatch=-1;pickedCustomer='';creating=null;createBusy=false;$('finance-add-dialog').close();$('finance-add-content').innerHTML='';}
function clear(){closeFilter();columnFilters={};dateRenderPending=false;financeView='pipeline';statisticsMonth=perthDay().slice(0,7);statisticsGroup='all';statisticsNewUsed='all';epoch++;request++;entries=[];refs=[];people=[];ctx=null;drafts.clear();busy.clear();message='';principal=token();scope=selected();close();$('sales-finance').innerHTML='';}
function guard(){if(token()!==principal){clear();return true;}if(selected()!==scope){scope=selected();epoch++;closeFilter();columnFilters={};dateRenderPending=false;drafts.clear();busy.clear();message='';close();return true;}return false;}
function select(key,value,attrs){return '<select '+attrs+' title="'+esc(value||'Not selected')+'">'+(choices[key].includes(value)?choices[key]:[value,...choices[key]]).map(v=>'<option value="'+esc(v)+'"'+(v===value?' selected':'')+'>'+esc(v||'—')+'</option>').join('')+'</select>';}
function input(key,value,attrs){return choices[key]?select(key,value,attrs):key==='notes'?'<input type="text" maxlength="4000" '+attrs+' value="'+esc(value||'')+'" title="'+esc(value||'')+'">':'<input '+attrs+' type="'+(amounts.has(key)?'number':'text')+'" '+(amounts.has(key)?'min="0" max="999999999.99" step="0.01"':'maxlength="200"')+' value="'+esc(value??'')+'">';}
function render(force=false){
 const scopeChanged=guard();if(!options?.getContext?.()){$('sales-finance').innerHTML='';return;}
 // Native date inputs keep partly typed day/month segments internally. Leave a focused
 // date control intact on polls; refresh it on blur, unless scope or permission is lost.
 const focus=root.document.activeElement;
 if(!force&&!scopeChanged&&focus?.dataset?.financeKey==='settlement_date'&&editor()){
  const row=visible().find(r=>r.id===focus.dataset.financeId);
  if(row&&!busy.has(row.id)){dateRenderPending=true;const d=drafts.get(row.id),tr=focus.closest('tr');if((d&&d.version!==row.version)||Number(focus.dataset.financeVersion)!==row.version){tr.querySelector('[data-finance-save]').disabled=true;message='This finance entry changed. Discard edits and refresh.';const status=$('sales-finance').querySelector('[role="status"]');if(status)status.textContent=message;}return;}
 }
 dateRenderPending=false;
 const restore=focus?.dataset?.financeId?{id:focus.dataset.financeId,key:focus.dataset.financeKey,start:focus.selectionStart,end:focus.selectionEnd}:null;

 const all=visible(),report=financeStatistics(all,statisticsMonth,financeView==='statistics'?{group:statisticsGroup,newUsed:statisticsNewUsed}:{}),baseList=financeView==='statistics'?report.settled:financeView==='all'?all:report.pipeline;
 const list=financeView==='statistics'?baseList:filterFinanceEntries(baseList,columnFilters,editor());
 const widths=[17,5,6,6,4,5.5,5,4,4,6,6,8.5,14.5,4,4.5];
 const table='<div class="table-wrap finance-table-wrap"><table class="finance-pipeline-table" aria-label="Finance applications"><colgroup>'+widths.map(w=>'<col style="width:'+w+'%">').join('')+'</colgroup><thead><tr>'+columns.map(([k,label])=>'<th scope="col">'+(financeView==='statistics'||(!editor()&&privateFields.has(k))?label:'<button type="button" class="finance-header-filter'+(columnFilters[k]?' active':'')+'" data-finance-filter="'+k+'" aria-label="Filter '+label+'" aria-haspopup="dialog" title="'+(columnFilters[k]?'Filter applied — ':'')+'Filter '+label+'"><span>'+label+'</span><span aria-hidden="true">'+(columnFilters[k]?'●':'▾')+'</span></button>')+'</th>').join('')+'</tr></thead><tbody>'+list.map(r=>{
  const draft=drafts.get(r.id),data={...r,...draft?.data,...draft?.raw},saving=busy.has(r.id),conflict=draft&&draft.version!==r.version,invalid=Object.keys(draft?.errors||{}).length>0;
  return '<tr>'+columns.map(([k,label])=>{
   const hidden=!editor()&&privateFields.has(k),value=k==='total_comm'?total({...r,...draft?.data}):data[k];
   let control=k==='total_comm'?hidden?'—':'<span class="finance-amount" title="'+esc(currency(value))+'">'+esc(currency(value))+'</span>':
    hidden?'—':editor()?input(k,value,'data-finance-id="'+esc(r.id)+'" data-finance-key="'+k+'" data-finance-version="'+r.version+'" aria-label="'+esc(label+' for '+r.customer)+'"'+(saving?' disabled':'')):esc(value??'—');
   if(k==='customer')control='<div class="finance-customer-cell">'+control+(editor()?'<div class="finance-row-actions"><button class="small-button" type="button" data-finance-save="'+esc(r.id)+'" aria-label="Save row for '+esc(r.customer)+'" '+(!draft?'hidden ':'')+(!draft||saving||conflict||invalid?'disabled':'')+'>'+(saving?'…':'Save')+'</button><button class="small-button" type="button" data-finance-discard="'+esc(r.id)+'" aria-label="Discard edits for '+esc(r.customer)+'" '+(!draft?'hidden':'')+'>×</button></div>':'')+'</div>'+(conflict?'<small class="finance-conflict">Changed elsewhere. Discard edits and refresh.</small>':'');
   if(k==='settlement'){
    const date=data.settlement_date||'',undated=data.settlement==='Yes'&&!validSettlementDate(date)&&!draft?.errors?.settlement_date;
    control=(editor()?'<input class="finance-settlement-date" type="date" data-finance-id="'+esc(r.id)+'" data-finance-key="settlement_date" data-finance-version="'+r.version+'" aria-label="Settlement date for '+esc(r.customer)+'" value="'+esc(date)+'" min="1900-01-01" max="'+perthDay()+'"'+(saving?' disabled':'')+'>':esc(validSettlementDate(date)?settlementDateLabel(date):undated?'Settled — date not recorded':'—'))+(editor()&&undated?'<small class="finance-settlement-undated">Settled — date not recorded</small>':'');
   }
   const state=k==='settlement'?(validSettlementDate(data.settlement_date||'')&&!draft?.errors?.settlement_date?' finance-yes':''):['approval','access','payout_complete'].includes(k)?data[k]==='Yes'?' finance-yes':data[k]==='No'?' finance-no':'':'';
   return '<td class="'+state+'" data-label="'+label+'">'+control+'</td>';
  }).join('')+'</tr>';
 }).join('')+'</tbody></table></div>';
 const viewControl='<label class="finance-view-picker"><span>Finance view</span><select data-finance-view aria-label="Finance view">'+[['pipeline','Pipeline'],['statistics','Statistics'],['all','All applications']].map(([key,name])=>'<option value="'+key+'" '+(financeView===key?'selected':'')+'>'+name+'</option>').join('')+'</select></label>';
 $('sales-finance').innerHTML='<section class="panel finance-home"><div class="panel-header"><div><h2>'+(financeView==='statistics'?'Finance statistics':'Finance applications')+'</h2><p>'+(financeView==='statistics'?'Monthly settlements and the current application pipeline.':editor()?'Edit the cells, then save the row.':'View your applications and finance updates.')+'</p></div><div class="panel-actions">'+viewControl+(editor()?'<button class="primary" type="button" data-finance-add>Add finance entry</button>':'')+'<button class="small-button" type="button" data-finance-refresh>Refresh finance</button></div></div><p class="tracking-note" role="status">'+esc(message)+'</p>'+(financeView==='statistics'?statisticsHtml(report,all):'')+'<div class="finance-pipeline-heading">'+(financeView==='statistics'?'SETTLED APPLICATIONS':financeView==='all'?'ALL FINANCE APPLICATIONS':'ACTIVE FINANCE PIPELINE')+'</div>'+(financeView==='statistics'?(list.length?table:'<div class="empty-state">No settlements in this period.</div>'):filterSummaryHtml(baseList,list)+table+(list.length?'':'<div class="empty-state">'+(baseList.length?'No entries match these filters. Clear filters to show all entries.':'No finance entries in this view. Choose Add finance entry to add a customer or link an existing vehicle.')+'</div>'))+'</section>';
 if(restore){const el=$('sales-finance').querySelector('[data-finance-id="'+restore.id+'"][data-finance-key="'+restore.key+'"]');if(el&&!el.disabled){el.focus({preventScroll:true});if(typeof el.setSelectionRange==='function'&&el.type!=='number'&&el.tagName!=='SELECT')try{el.setSelectionRange(restore.start,restore.end);}catch{}}}
}

function filterSummaryHtml(baseList,list){
 const count=Object.keys(columnFilters).filter(k=>editor()||!privateFields.has(k)).length;
 const shown=new Set(list.map(r=>r.id)),hiddenEdits=baseList.filter(r=>drafts.has(r.id)&&!shown.has(r.id)).length;
 return '<div class="finance-filter-summary"><span role="status" aria-live="polite">'+list.length+' of '+baseList.length+' entries'+(count?' · '+count+' column '+(count===1?'filter':'filters'):'')+'</span><button class="small-button" type="button" data-finance-filters>Filter columns</button>'+(count?'<button class="small-button" type="button" data-finance-clear-filters>Clear filters</button>':'')+(hiddenEdits?'<span class="finance-filter-drafts">'+hiddenEdits+' unsaved '+(hiddenEdits===1?'row is':'rows are')+' hidden by filters.</span>':'')+'</div>';
}
function closeFilter(){filterEditing=null;$('finance-filter-dialog').close();$('finance-filter-content').innerHTML='';}
function openFilter(key){
 guard();if(!ctx||financeView==='statistics')return;
 const available=columns.filter(([k])=>editor()||!privateFields.has(k));
 if(key&&!available.some(([k])=>k===key))return;
 filterEditing=key||available[0][0];renderFilter();$('finance-filter-dialog').showModal();
 $('finance-filter-content').querySelector('[name="'+(['customer','notes'].includes(filterEditing)?'query':'value')+'"]').focus();
}
function renderFilter(){
 const key=filterEditing;if(!key||(!editor()&&privateFields.has(key)))return;
 const rule=columnFilters[key]||{},list=financeView==='all'?visible():visible().filter(r=>r.settlement!=='Yes');
 const values=financeFilterOptions(list,key,editor()).filter(v=>v!=='');
 if(rule.mode==='value'&&!values.includes(rule.value))values.push(rule.value);
 const chosen=rule.mode==='blank'?'blank':rule.mode==='value'?'value:'+rule.value:'all';
 const label=columns.find(([k])=>k===key)[1],numeric=filterAmounts.has(key),text=['customer','notes'].includes(key);
 $('finance-filter-content').innerHTML='<div class="panel-header"><h2 id="finance-filter-title">Filter '+esc(label)+'</h2><button class="small-button" type="button" data-finance-filter-close>Close</button></div><form id="finance-filter-form"><label><span>Column</span><select name="column" aria-label="Filter column">'+columns.filter(([k])=>editor()||!privateFields.has(k)).map(([k,l])=>'<option value="'+k+'"'+(k===key?' selected':'')+'>'+l+'</option>').join('')+'</select></label>'+(text?'<label><span>Contains</span><input name="query" type="search" maxlength="4000" autocomplete="off" value="'+esc(rule.query||'')+'" placeholder="Search '+esc(label.toLowerCase())+'"></label>':'')+'<label><span>Value</span><select name="value" aria-label="Filter value"><option value="all"'+(chosen==='all'?' selected':'')+'>All values</option><option value="blank"'+(chosen==='blank'?' selected':'')+'>Not recorded</option>'+values.map(v=>'<option value="'+esc('value:'+v)+'"'+(chosen==='value:'+v?' selected':'')+'>'+esc(numeric?currency(Number(v)):key==='settlement'?v==='undated'?'Settled — date not recorded':settlementDateLabel(v):v.length>100?v.slice(0,100)+'…':v)+'</option>').join('')+'</select></label>'+(numeric?'<div class="finance-filter-range"><label><span>Minimum</span><input name="min" type="number" min="0" max="999999999.99" step="0.01" value="'+esc(rule.min??'')+'"></label><label><span>Maximum</span><input name="max" type="number" min="0" max="999999999.99" step="0.01" value="'+esc(rule.max??'')+'"></label></div>':'')+'<div class="panel-actions"><button class="primary" type="submit">Apply filter</button><button class="small-button" type="button" data-finance-filter-clear>Clear this filter</button></div><p id="finance-filter-error" role="alert"></p></form>';
}
function applyFilter(event){
 event.preventDefault();guard();const key=filterEditing;if(!key||(!editor()&&privateFields.has(key)))return;
 try{
  const values=new FormData(event.target),value=String(values.get('value')||'all');
  const rule={mode:value==='blank'?'blank':value.startsWith('value:')?'value':'all',value:value.startsWith('value:')?value.slice(6):''};
  if(['customer','notes'].includes(key))rule.query=String(values.get('query')||'').trim();
  if(filterAmounts.has(key)){
   rule.min=String(values.get('min')||'').trim();rule.max=String(values.get('max')||'').trim();
   const min=money(rule.min),max=money(rule.max);if(min!==null&&max!==null&&min>max)throw new Error('Minimum must be no greater than maximum.');
  }
  if(rule.mode==='all'&&!rule.query&&!rule.min&&!rule.max)delete columnFilters[key];else columnFilters[key]=rule;
  closeFilter();render(true);focusFilter(key);
 }catch(error){$('finance-filter-error').textContent=error.message||'Check the filter values.';}
}
function focusFilter(key){
 const target=$('sales-finance').querySelector('[data-finance-filter="'+key+'"]');
 const mobile=root.matchMedia?.('(max-width:800px)')?.matches;
 (mobile?$('sales-finance').querySelector('[data-finance-filters]'):target)?.focus?.({preventScroll:true});
}

async function refresh(){
 if(!options?.getContext?.()||!root.PDC_AUTH_CONTEXT)return;
 const identity=token(),generation=epoch,sequence=++request;
 try{
  const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_finance_pipeline');
  if(identity!==token()||generation!==epoch||sequence!==request)return;
  if(error||!Array.isArray(data?.entries)||!['administrator','salesperson'].includes(data.context?.role))throw error||new Error('Finance applications could not be loaded.');
  if(editor()&&!data.context.can_edit_finance){drafts.clear();busy.clear();columnFilters={};closeFilter();close();dateRenderPending=false;}
  ctx=data.context;entries=data.entries;refs=data.vehicle_options||[];people=data.salespeople||[];
  options.onLoaded?.(projection(entries));
 }catch(e){if(identity!==token()||generation!==epoch||sequence!==request)return;entries=[];refs=[];people=[];ctx=null;drafts.clear();columnFilters={};closeFilter();close();dateRenderPending=false;options.onLoaded?.([]);message=e.message||'Finance could not be loaded. Refresh to retry.';}
 if(options.getView?.()==='finance')render();
}

function settlementDateLabel(value){return /^\d{4}-\d{2}-\d{2}$/.test(value)?value.slice(8,10)+'/'+value.slice(5,7)+'/'+value.slice(0,4):value;}
function currency(value){return new Intl.NumberFormat('en-AU',{style:'currency',currency:'AUD',maximumFractionDigits:2}).format(value);}
function monthLabel(key){if(key==='all')return 'All months';if(key==='undated')return 'Date not recorded';return new Date(key+'-01T00:00:00Z').toLocaleDateString('en-AU',{timeZone:'Australia/Perth',month:'long',year:'numeric'});}
function monthOptions(report){
 const date=new Date(perthDay().slice(0,7)+'-01T00:00:00Z'),months=new Set(report.months.map(r=>r.month));
 for(let i=0;i<12;i++){months.add(date.toISOString().slice(0,7));date.setUTCMonth(date.getUTCMonth()-1);}
 if(/^[0-9]{4}-[0-9]{2}$/.test(statisticsMonth))months.add(statisticsMonth);
 return [...months].sort().reverse().concat(['all'],report.undated||statisticsMonth==='undated'?['undated']:[]);
}
function statisticsHtml(report,all){
 const cards=[['Settled applications / contracts',report.contractCount],['Access products',report.accessCount],['Active pipeline',report.pipelineCount],['Approved in pipeline',report.approved]];
 if(editor())cards.push(['RSI products (RSA)',report.rsaCount,currency(report.rsaTotal)],['MVI products',report.mviCount,currency(report.mviTotal)],['Settled NAF',currency(report.naf)],['Settled commission',currency(report.commission)],['Pipeline NAF',currency(report.pipelineNaf)]);
 const monthly='<table class="finance-statistics-table"><thead><tr><th>Month</th><th>Contracts</th><th>Access</th>'+(editor()?'<th>RSI</th><th>MVI</th><th>NAF</th><th>Commission</th>':'')+'</tr></thead><tbody>'+report.months.map(r=>'<tr><td><button type="button" class="finance-month-link" data-finance-month="'+r.month+'">'+esc(monthLabel(r.month))+'</button></td><td>'+r.count+'</td><td>'+r.accessCount+'</td>'+(editor()?'<td>'+r.rsaCount+'</td><td>'+r.mviCount+'</td><td>'+esc(currency(r.naf))+'</td><td>'+esc(currency(r.commission))+'</td>':'')+'</tr>').join('')+'</tbody></table>';
 const filters='<label class="finance-month-picker"><span>Location</span><select data-finance-group aria-label="Finance location">'+[['all','All locations'],['broome','Broome'],['pilbara','Pilbara']].map(([key,label])=>'<option value="'+key+'" '+(statisticsGroup===key?'selected':'')+'>'+label+'</option>').join('')+'</select></label><label class="finance-month-picker"><span>New / Used</span><select data-finance-new-used aria-label="Finance New / Used">'+[['all','New and Used'],['new','New'],['used','Used']].map(([key,label])=>'<option value="'+key+'" '+(statisticsNewUsed===key?'selected':'')+'>'+label+'</option>').join('')+'</select></label>';
 return '<section class="finance-statistics"><div class="finance-stat-filters"><label class="finance-month-picker"><span>Settlement month</span><select data-finance-period aria-label="Settlement month">'+monthOptions(report).map(key=>'<option value="'+key+'" '+(key===statisticsMonth?'selected':'')+'>'+esc(monthLabel(key))+'</option>').join('')+'</select></label>'+filters+'</div><p class="finance-stat-note">Contracts and products are counted on applications settled in the selected period. RSI uses the RSA column; RSI and MVI are counted when an amount is recorded above $0. Pilbara includes Port Hedland entries.</p><div class="finance-stat-cards">'+cards.map(([label,value,amount])=>'<article><span>'+label+'</span><strong>'+value+'</strong>'+(amount?'<small>'+esc(amount)+' total</small>':'')+'</article>').join('')+'</div>'+(report.undated?'<p class="finance-undated">'+report.undated+' settled '+(report.undated===1?'entry has':'entries have')+' no settlement date. Choose Date not recorded, enter the actual date in Settlement and save the row to assign the correct month.</p>':'')+'<div class="finance-stat-panels"><section><h3>Previous months</h3>'+(report.months.length?monthly:'<p>No dated settlements yet.</p>')+'</section>'+(editor()?'<section><h3>Financier overview</h3><table class="finance-statistics-table"><thead><tr><th>Financier</th><th>Pipeline</th><th>Settled in period</th></tr></thead><tbody>'+report.financiers.map(r=>'<tr><td>'+r.name+'</td><td>'+r.pipeline+'</td><td>'+r.settled+'</td></tr>').join('')+'</tbody></table></section>':'')+'</div></section>';
}
function add(){guard();if(!editor())return;creating={id:root.crypto.randomUUID()};createBusy=false;
 $('finance-add-content').innerHTML='<div class="panel-header"><div><h2 id="finance-add-title">Add finance entry</h2><p>Link an existing vehicle, or add a finance customer.</p></div><button class="small-button" type="button" data-finance-close>Close finance entry</button></div><form id="finance-add-form" class="finance-add-form"><fieldset class="finance-mode"><legend>Application</legend><label><input type="radio" name="mode" value="existing" checked> Find existing vehicle</label><label><input type="radio" name="mode" value="new"> Customer only</label></fieldset><div id="finance-existing-fields"><div class="finance-find-vehicle"><label><span>Find vehicle</span><input id="finance-vehicle-search" type="search" placeholder="Stock, Toyota order, customer or vehicle" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="finance-vehicle-matches" autocomplete="off"></label><div id="finance-vehicle-matches" class="finance-vehicle-matches" role="listbox" aria-label="Matching vehicles" hidden></div><p id="finance-vehicle-match-status" class="finance-match-status" role="status" aria-live="polite"></p></div><label><span>Existing vehicle</span><select name="tracking_id" id="finance-vehicle-picker"></select></label></div><div id="finance-new-fields" hidden><label><span>Salesperson (optional)</span><select name="salesperson_code"><option value="">Unassigned</option>'+people.map(p=>'<option value="'+esc(p.code)+'"'+(p.code===(selected()||ctx.salesperson_code)?' selected':'')+'>'+esc(p.code+' · '+p.name)+'</option>').join('')+'</select></label></div><label><span>Customer</span><input name="customer" maxlength="200" required></label><label><span>New / Used</span>'+select('new_used','New','name="new_used"')+'</label><label><span>Group</span>'+select('group_name','Broome','name="group_name"')+'</label><label><span>Financier</span>'+select('financier','','name="financier"')+'</label><p class="tracking-note">Enter the remaining application details on the Finance page after adding the entry.</p><button class="primary" type="submit">Add finance entry</button><p id="finance-add-message" role="status"></p></form>';
 findVehicles('');$('finance-add-dialog').showModal();
 $('finance-add-content').querySelector('input[name="mode"][value="existing"]').focus();
}
function vehicleLabel(row){return [row.stock||'Order '+row.order,row.client,row.vehicle].filter(Boolean).join(' · ');}
function hideMatches(){
 activeMatch=-1;$('finance-vehicle-matches').hidden=true;
 $('finance-vehicle-search').setAttribute('aria-expanded','false');$('finance-vehicle-search').removeAttribute('aria-activedescendant');
}
function renderMatches(){
 const list=$('finance-vehicle-matches'),search=$('finance-vehicle-search');
 list.innerHTML=vehicleMatches.map((r,i)=>'<button type="button" role="option" id="finance-match-'+i+'" data-finance-match="'+esc(r.tracking_id)+'" aria-selected="'+(i===activeMatch)+'" aria-label="'+esc(vehicleLabel(r))+'"><strong>'+esc(r.stock||'Order '+r.order)+'</strong><span>'+esc(r.client||'Customer not recorded')+'</span><small>'+esc(r.vehicle||'Vehicle not recorded')+'</small></button>').join('');
 list.hidden=!vehicleMatches.length;search.setAttribute('aria-expanded',String(vehicleMatches.length>0));
 if(activeMatch>=0)search.setAttribute('aria-activedescendant','finance-match-'+activeMatch);else search.removeAttribute('aria-activedescendant');
}
function findVehicles(text,show=false,reset=false){
 if(!creating)return;
 const picker=$('finance-vehicle-picker'),value=reset?'':picker.value,find=String(text).trim(),all=candidates();
 const list=find?matchVehicles(all,find):all;
 picker.innerHTML='<option value="">Choose a vehicle</option>'+list.map(r=>'<option value="'+esc(r.tracking_id)+'">'+esc(vehicleLabel(r))+'</option>').join('');
 picker.value=list.some(r=>r.tracking_id===value)?value:'';
 if(reset){
  const customer=$('finance-add-form').querySelector('[name="customer"]');if(pickedCustomer&&customer.value===pickedCustomer)customer.value='';
  pickedCustomer='';$('finance-add-message').textContent='';
 }
 vehicleMatches=list.slice(0,10);activeMatch=-1;
 if(show&&find){renderMatches();$('finance-vehicle-match-status').textContent=list.length?list.length>10?'Showing 10 of '+list.length+' matches. Keep typing to narrow the list.':list.length+' matching vehicle'+(list.length===1?'':'s')+'.':'No matching vehicles. Try another stock number or customer name.';}
 else{hideMatches();$('finance-vehicle-match-status').textContent='';}
}
function chooseVehicle(id){
 guard();if(!creating||!editor()||createBusy)return;
 const row=candidates().find(r=>r.tracking_id===id);if(!row)return;
 const search=$('finance-vehicle-search');search.value=row.stock||row.order||row.client||'';
 findVehicles(search.value);$('finance-vehicle-picker').value=id;
 const form=$('finance-add-form');form.querySelector('[name="customer"]').value=row.client||'';pickedCustomer=row.client||'';
 for(const [field,value] of [['new_used',row.new_used],['group_name',row.group_name]])if(choices[field].includes(value))form.querySelector('[name="'+field+'"]').value=value;
 hideMatches();$('finance-add-message').textContent='';$('finance-vehicle-match-status').textContent='Vehicle selected. Customer details filled in.';
}
async function saveRow(id){
 guard();const row=visible().find(r=>r.id===id),draft=drafts.get(id);if(!editor()||!row||!draft||busy.has(id)||Object.keys(draft.errors||{}).length)return;
 if(draft.version!==row.version){message='This finance entry changed. Discard edits and refresh.';render(true);return;}
 const identity=token(),generation=epoch;busy.add(id);render(true);
 try{
  const {data,error}=await root.PDC_SUPABASE.rpc('save_broome_finance_application',{p_id:id,p_tracking_id:row.tracking_id||null,p_vehicle:null,p_salesperson_code:null,p_data:draft.data,p_expected_version:draft.version});
  if(identity!==token()||generation!==epoch)return;if(error||!data?.record)throw error||new Error('Finance was not saved.');
  entries=entries.map(r=>r.id===id?data.record:r);drafts.delete(id);message='Finance entry saved.';options.onLoaded?.(projection(entries));
 }catch(e){if(identity===token()&&generation===epoch)message=e.message||'Finance was not saved. Your edits remain in the row.';}
 finally{if(identity===token()&&generation===epoch){busy.delete(id);render(true);}}
}
async function create(e){
 e.preventDefault();guard();if(!creating||createBusy||!editor())return;const form=e.target,identity=token(),generation=epoch,id=creating.id;
 try{
  const values=new FormData(form),existing=values.get('mode')==='existing',tracking=existing?values.get('tracking_id'):null;
  if(existing&&!candidates().some(r=>r.tracking_id===tracking))throw new Error('Choose an existing vehicle.');
  const vehicle=existing?null:{};
  const fields={...patch('customer',values.get('customer')),...patch('new_used',values.get('new_used')),...patch('group_name',values.get('group_name')),...patch('financier',values.get('financier')||'')};
  createBusy=true;form.querySelector('button[type="submit"]').disabled=true;
  const {data,error}=await root.PDC_SUPABASE.rpc('save_broome_finance_application',{p_id:id,p_tracking_id:tracking||null,p_vehicle:vehicle,p_salesperson_code:existing?null:values.get('salesperson_code')||null,p_data:fields,p_expected_version:0});
  if(identity!==token()||generation!==epoch||creating?.id!==id)return;if(error||!data?.record)throw error||new Error('Finance entry was not added.');
  entries=[...entries.filter(r=>r.id!==id),data.record];message='Finance entry added. Enter the application details in its row.';options.onLoaded?.(projection(entries));close();render(true);
 }catch(error){if(identity===token()&&generation===epoch&&creating?.id===id)$('finance-add-message').textContent=error.message||'Finance entry was not added.';}
 finally{if(identity===token()&&generation===epoch&&creating?.id===id){createBusy=false;form.querySelector('button[type="submit"]').disabled=false;}}
}
function init(settings){
 options=settings;principal=token();scope=selected();
 $('sales-finance').addEventListener('input',e=>{
  guard();const t=e.target,id=t.dataset.financeId,key=t.dataset.financeKey;if(!id||!key||!editor()||busy.has(id))return;const row=visible().find(r=>r.id===id);if(!row)return;
  const displayedVersion=Number(t.dataset.financeVersion),d=drafts.get(id)||{version:Number.isInteger(displayedVersion)?displayedVersion:row.version,data:{},raw:{},errors:{}};d.raw[key]=t.value;drafts.set(id,d);
  const tr=t.closest('tr'),save=tr.querySelector('[data-finance-save]');save.hidden=false;tr.querySelector('[data-finance-discard]').hidden=false;
  try{
   if(key==='settlement_date'&&t.validity?.badInput)throw new Error('Finish entering a valid settlement date, or clear the date.');
   Object.assign(d.data,patch(key,t.value));delete d.errors[key];
   save.disabled=Object.keys(d.errors).length>0||d.version!==row.version;
   const totalCell=tr.querySelector('[data-label="Total Comm"]');if(totalCell){const value=currency(total({...row,...d.data})),amount=totalCell.querySelector('.finance-amount');if(amount){amount.textContent=value;amount.title=value;}}
   message=key==='settlement_date'?'Settlement date changed. Save the row to update statistics.':'';
  }catch(error){d.errors[key]=error.message;message=error.message;save.disabled=true;}
  if(key==='settlement_date'){
   const cell=tr.querySelector('[data-label="Settlement"]');cell?.classList.toggle('finance-yes',!d.errors[key]&&validSettlementDate(t.value));cell?.classList.remove('finance-no');
   const undated=cell?.querySelector('.finance-settlement-undated');if(undated)undated.hidden=true;
   t.setAttribute('aria-invalid',String(!!d.errors[key]));
  }
  const status=$('sales-finance').querySelector('[role="status"]');if(status)status.textContent=message;
 });
 $('sales-finance').addEventListener('click',e=>{const t=e.target.closest('[data-finance-add],[data-finance-refresh],[data-finance-save],[data-finance-discard],[data-finance-month],[data-finance-filter],[data-finance-filters],[data-finance-clear-filters]');if(!t)return;guard();if(t.hasAttribute('data-finance-filter'))openFilter(t.dataset.financeFilter);else if(t.hasAttribute('data-finance-filters'))openFilter();else if(t.hasAttribute('data-finance-clear-filters')){columnFilters={};closeFilter();render(true);$('sales-finance').querySelector('[data-finance-filters]')?.focus?.({preventScroll:true});}else if(t.hasAttribute('data-finance-add'))add();else if(t.hasAttribute('data-finance-refresh'))refresh();else if(t.dataset.financeMonth){statisticsMonth=t.dataset.financeMonth;render(true);}else if(t.dataset.financeSave)saveRow(t.dataset.financeSave);else if(t.dataset.financeDiscard){drafts.delete(t.dataset.financeDiscard);message='Edits discarded. The current saved entry is shown.';render(true);}});

 $('sales-finance').addEventListener('focusout',e=>{if(e.target.dataset.financeKey==='settlement_date'&&dateRenderPending&&!e.relatedTarget?.closest?.('[data-finance-save],[data-finance-discard]'))root.setTimeout(()=>{if(dateRenderPending)render();},0);});
 $('sales-finance').addEventListener('change',e=>{if(e.target.hasAttribute('data-finance-view')){financeView=['pipeline','statistics','all'].includes(e.target.value)?e.target.value:'pipeline';render(true);}else if(e.target.hasAttribute('data-finance-period')){statisticsMonth=e.target.value;render(true);}else if(e.target.hasAttribute('data-finance-group')){statisticsGroup=['all','broome','pilbara'].includes(e.target.value)?e.target.value:'all';render(true);}else if(e.target.hasAttribute('data-finance-new-used')){statisticsNewUsed=['all','new','used'].includes(e.target.value)?e.target.value:'all';render(true);}});

 $('finance-filter-dialog').addEventListener('cancel',closeFilter);
 $('finance-filter-content').addEventListener('submit',applyFilter);
 $('finance-filter-content').addEventListener('change',e=>{if(e.target.name!=='column')return;guard();if(!filterEditing||!columns.some(([k])=>k===e.target.value&&(editor()||!privateFields.has(k))))return;filterEditing=e.target.value;renderFilter();$('finance-filter-content').querySelector('[name="column"]').focus();});
 $('finance-filter-content').addEventListener('click',e=>{if(e.target.closest('[data-finance-filter-close]')){closeFilter();return;}if(e.target.closest('[data-finance-filter-clear]')){guard();const key=filterEditing;if(!key||(!editor()&&privateFields.has(key)))return;delete columnFilters[key];closeFilter();render(true);focusFilter(key);}});
 $('finance-add-dialog').addEventListener('cancel',close);
 $('finance-add-content').addEventListener('click',e=>{
  if(e.target.closest('[data-finance-close]')){close();return;}
  const match=e.target.closest('[data-finance-match]');if(match){chooseVehicle(match.dataset.financeMatch);$('finance-vehicle-search').focus();}
 });
 $('finance-add-content').addEventListener('input',e=>{if(e.target.id==='finance-vehicle-search'){guard();if(creating)findVehicles(e.target.value,true,true);}});
 $('finance-add-content').addEventListener('change',e=>{
  if(e.target.name==='mode'){hideMatches();const existing=e.target.value==='existing';$('finance-existing-fields').hidden=!existing;$('finance-new-fields').hidden=existing;}
  if(e.target.id==='finance-vehicle-picker')chooseVehicle(e.target.value);
 });

 $('finance-add-content').addEventListener('keydown',e=>{
  if(e.target.id!=='finance-vehicle-search')return;guard();if(!creating)return;
  if(e.key==='Escape'){if(!$('finance-vehicle-matches').hidden){e.preventDefault();e.stopPropagation();hideMatches();}return;}
  if(e.key==='Tab'){hideMatches();return;}
  if(!['ArrowDown','ArrowUp','Enter'].includes(e.key))return;
  if($('finance-vehicle-matches').hidden){if(e.key==='Enter')return;findVehicles(e.target.value,true);}
  if(!vehicleMatches.length||$('finance-vehicle-matches').hidden)return;
  e.preventDefault();
  if(e.key==='Enter'){chooseVehicle(vehicleMatches[activeMatch<0?0:activeMatch].tracking_id);return;}
  activeMatch=e.key==='ArrowDown'?(activeMatch+1)%vehicleMatches.length:(activeMatch<0?vehicleMatches.length-1:(activeMatch-1+vehicleMatches.length)%vehicleMatches.length);
  renderMatches();$('finance-match-'+activeMatch)?.scrollIntoView?.({block:'nearest'});
 });
 $('finance-add-content').addEventListener('focusout',e=>{
  if(e.target.id==='finance-vehicle-search'&&!e.relatedTarget?.closest?.('.finance-find-vehicle'))hideMatches();
 });
 $('finance-add-content').addEventListener('submit',create);
}
Object.assign(api,{init,refresh,clear,render,syncScope:guard});
})(typeof window==='object'?window:globalThis);
