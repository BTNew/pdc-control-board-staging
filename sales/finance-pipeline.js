(function(root){
'use strict';
const columns=[['customer','Customer'],['new_used','New / Used'],['financier','Financier'],['group_name','Group'],['approval','Approval'],['finance_comm','Finance Comm'],['dof_daf','DOF/DAF'],['mvi','MVI'],['rsa','RSA'],['total_comm','Total Comm'],['naf','NAF'],['settlement','Settlement'],['notes','Notes'],['access','Access'],['payout_complete','Payout Complete']];
const amounts=new Set(['finance_comm','dof_daf','mvi','rsa','naf']),privateFields=new Set(['financier',...amounts,'total_comm']);
const choices={new_used:['New','Used'],group_name:['Broome','Port Hedland'],approval:['','Yes','No'],settlement:['','Yes','No'],access:['','Yes','No'],payout_complete:['','Yes','No']};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function money(value){if(value===''||value==null)return null;const text=String(value).trim();if(!/^\d+(?:\.\d{1,2})?$/.test(text)||Number(text)>999999999.99)throw new Error('Use a positive amount with up to two decimal places.');return Number(text);}
function total(data){return ['finance_comm','dof_daf','mvi','rsa'].reduce((n,k)=>n+Math.round((Number(data[k])||0)*100),0)/100;}
function patch(key,value){
 if(!columns.some(([k])=>k===key)||key==='total_comm')throw new Error('Choose an editable finance field.');
 if(amounts.has(key))return {[key]:money(value)};
 const text=String(value??'').trim();if(text.length>(key==='notes'?4000:200))throw new Error('This field is too long.');
 if(choices[key]&&!choices[key].includes(text))throw new Error('Choose a valid '+columns.find(([k])=>k===key)[1]+'.');
 if(key==='customer'&&!text)throw new Error('Enter the customer name.');return {[key]:text};
}
function projection(entries){
 // Only explicitly saved applications can supply a salesperson's finance summary.
 const latest=new Map();for(const r of [...entries].sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at))||String(b.id).localeCompare(String(a.id))))if(r.tracking_id&&!latest.has(r.tracking_id))latest.set(r.tracking_id,r);
 return [...latest.values()].map(r=>({id:r.id,tracking_id:r.tracking_id,version:r.version,current_application:true,approval_status:r.approval==='Yes'?'approved':r.approval==='No'?'declined':'not_started',settlement_status:r.settlement==='Yes'?'settled':r.settlement==='No'?'pending':'not_started',access_status:r.access==='Yes'?'active':r.access==='No'?'not_required':'requested',payout_status:r.payout_complete==='Yes'?'complete':r.payout_complete==='No'?'pending':'not_required',shared_update:r.notes||''}));
}
const api={columns,patch,money,total,projection};if(typeof module==='object'&&module.exports)module.exports=api;root.BROOME_SALES_FINANCE=api;
if(!root.document)return;
const $=id=>root.document.getElementById(id);let options,entries=[],refs=[],people=[],ctx=null,epoch=0,request=0,principal='',scope='',drafts=new Map(),busy=new Set(),message='',creating=null,createBusy=false;
const token=()=>options?.getToken?.(),selected=()=>options?.getSalesperson?.()||'';
const editor=()=>ctx?.can_edit_finance===true;
const visible=()=>entries.filter(r=>!selected()||r.salesperson_code===selected());
const candidates=()=>refs.filter(r=>!selected()||r.salesperson_code===selected());
function close(){creating=null;createBusy=false;$('finance-add-dialog').close();$('finance-add-content').innerHTML='';}
function clear(){epoch++;request++;entries=[];refs=[];people=[];ctx=null;drafts.clear();busy.clear();message='';principal=token();scope=selected();close();$('sales-finance').innerHTML='';}
function guard(){if(token()!==principal){clear();return;}if(selected()!==scope){scope=selected();epoch++;drafts.clear();busy.clear();message='';close();}}
function select(key,value,attrs){return '<select '+attrs+'>'+choices[key].map(v=>'<option value="'+esc(v)+'"'+(v===value?' selected':'')+'>'+esc(v||'—')+'</option>').join('')+'</select>';}
function input(key,value,attrs){return choices[key]?select(key,value,attrs):key==='notes'?'<textarea rows="2" maxlength="4000" '+attrs+'>'+esc(value)+'</textarea>':'<input '+attrs+' type="'+(amounts.has(key)?'number':'text')+'" '+(amounts.has(key)?'min="0" max="999999999.99" step="0.01"':'maxlength="200"')+' value="'+esc(value??'')+'">';}
function render(){
 guard();if(!options?.getContext?.()){$('sales-finance').innerHTML='';return;}
 // Do not replace controls while the user is typing, or lose unsubmitted cell edits on a poll.
 const focus=root.document.activeElement,restore=focus?.dataset?.financeId?{id:focus.dataset.financeId,key:focus.dataset.financeKey,start:focus.selectionStart,end:focus.selectionEnd}:null;
 const list=visible();
 const table='<div class="table-wrap finance-table-wrap"><table class="finance-pipeline-table" aria-label="Active finance applications"><thead><tr>'+columns.map(([k,label])=>'<th scope="col">'+label+'</th>').join('')+'</tr></thead><tbody>'+list.map(r=>{
  const draft=drafts.get(r.id),data={...r,...draft?.data,...draft?.raw},saving=busy.has(r.id),conflict=draft&&draft.version!==r.version,invalid=Object.keys(draft?.errors||{}).length>0;
  return '<tr>'+columns.map(([k,label])=>{
   const hidden=!editor()&&privateFields.has(k),value=k==='total_comm'?total({...r,...draft?.data}):data[k];
   const control=k==='total_comm'?hidden?'—':esc(new Intl.NumberFormat('en-AU',{style:'currency',currency:'AUD'}).format(value)):
    hidden?'—':editor()?input(k,value,'data-finance-id="'+esc(r.id)+'" data-finance-key="'+k+'" aria-label="'+esc(label+' for '+r.customer)+'"'+(saving?' disabled':'')):esc(value??'—');
   const state=['approval','settlement','access','payout_complete'].includes(k)?data[k]==='Yes'?' finance-yes':data[k]==='No'?' finance-no':'':'';
   return '<td class="'+state+'" data-label="'+label+'">'+control+(k==='customer'?'<small class="finance-vehicle-label">'+esc(r.vehicle?.model||'')+(r.vehicle?.stock?' · '+esc(r.vehicle.stock):r.vehicle?.order?' · Order '+esc(r.vehicle.order):'')+'</small>'+(editor()?'<div class="finance-row-actions"><button class="small-button" type="button" data-finance-save="'+esc(r.id)+'"'+(!draft||saving||conflict||invalid?' disabled':'')+'>'+(saving?'Saving…':'Save row')+'</button>'+(draft?'<button class="small-button" type="button" data-finance-discard="'+esc(r.id)+'">Discard edits</button>':'')+'</div>'+(conflict?'<small class="finance-conflict">Changed elsewhere. Discard edits and re-enter your changes using the current row.</small>':''):''):'')+'</td>';
  }).join('')+'</tr>';
 }).join('')+'</tbody></table></div>';
 $('sales-finance').innerHTML='<section class="panel finance-home"><div class="panel-header"><div><h2>Finance applications</h2><p>Only applications added by finance staff appear here.'+(editor()?' Edit the cells, then save the row.':' View your applications and finance updates.')+'</p></div><div class="panel-actions">'+(editor()?'<button class="primary" type="button" data-finance-add>Add finance entry</button>':'')+'<button class="small-button" type="button" data-finance-refresh>Refresh finance</button></div></div><p class="tracking-note" role="status">'+esc(message)+'</p><div class="finance-pipeline-heading">ACTIVE FINANCE PIPELINE</div>'+(list.length?table:'<div class="empty-state">No finance entries in this view.'+(editor()?' Choose Add finance entry to find an existing vehicle or add vehicle details.':'')+'</div>')+'</section>';
 if(restore){const el=$('sales-finance').querySelector('[data-finance-id="'+restore.id+'"][data-finance-key="'+restore.key+'"]');if(el&&!el.disabled){el.focus({preventScroll:true});if(typeof el.setSelectionRange==='function'&&el.type!=='number'&&el.tagName!=='SELECT')try{el.setSelectionRange(restore.start,restore.end);}catch{}}}
}
async function refresh(){
 if(!options?.getContext?.()||!root.PDC_AUTH_CONTEXT)return;
 const identity=token(),generation=epoch,sequence=++request;
 try{
  const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_finance_pipeline');
  if(identity!==token()||generation!==epoch||sequence!==request)return;
  if(error||!Array.isArray(data?.entries)||!['administrator','salesperson'].includes(data.context?.role))throw error||new Error('Finance applications could not be loaded.');
  if(editor()&&!data.context.can_edit_finance){drafts.clear();busy.clear();close();}
  ctx=data.context;entries=data.entries;refs=data.vehicle_options||[];people=data.salespeople||[];
  options.onLoaded?.(projection(entries));
 }catch(e){if(identity!==token()||generation!==epoch||sequence!==request)return;entries=[];refs=[];people=[];ctx=null;drafts.clear();close();options.onLoaded?.([]);message=e.message||'Finance could not be loaded. Refresh to retry.';}
 if(options.getView?.()==='finance')render();
}
function add(){guard();if(!editor())return;creating={id:root.crypto.randomUUID()};createBusy=false;
 $('finance-add-content').innerHTML='<div class="panel-header"><div><h2 id="finance-add-title">Add finance entry</h2><p>Find an existing vehicle, or add vehicle details for this finance application.</p></div><button class="small-button" type="button" data-finance-close>Close finance entry</button></div><form id="finance-add-form" class="finance-add-form"><fieldset class="finance-mode"><legend>Vehicle</legend><label><input type="radio" name="mode" value="existing" checked> Find existing vehicle</label><label><input type="radio" name="mode" value="new"> Add a vehicle</label></fieldset><div id="finance-existing-fields"><label><span>Find vehicle</span><input id="finance-vehicle-search" type="search" placeholder="Stock, Toyota order, customer or vehicle"></label><label><span>Existing vehicle</span><select name="tracking_id" id="finance-vehicle-picker"></select></label></div><div id="finance-new-fields" hidden><label><span>Vehicle model</span><input name="model" maxlength="200"></label><label><span>Stock number (optional)</span><input name="stock" maxlength="200"></label><label><span>Toyota order (optional)</span><input name="order" maxlength="200"></label><label><span>Salesperson (optional)</span><select name="salesperson_code"><option value="">Unassigned</option>'+people.map(p=>'<option value="'+esc(p.code)+'"'+(p.code===(selected()||ctx.salesperson_code)?' selected':'')+'>'+esc(p.code+' · '+p.name)+'</option>').join('')+'</select></label></div><label><span>Customer</span><input name="customer" maxlength="200" required></label><label><span>New / Used</span>'+select('new_used','New','name="new_used"')+'</label><label><span>Group</span>'+select('group_name','Broome','name="group_name"')+'</label><p class="tracking-note">Vehicle details added here belong to the finance application. The remaining finance fields can be edited on the Finance page after adding the entry.</p><button class="primary" type="submit">Add finance entry</button><p id="finance-add-message" role="status"></p></form>';
 findVehicles('');$('finance-add-dialog').showModal();
 $('finance-add-content').querySelector('input[name="mode"][value="existing"]').focus();
}
function findVehicles(text){const value=$('finance-vehicle-picker').value,find=String(text).trim().toLowerCase(),list=candidates().filter(r=>[r.stock,r.order,r.client,r.vehicle].some(v=>String(v||'').toLowerCase().includes(find)));
 $('finance-vehicle-picker').innerHTML='<option value="">Choose a vehicle</option>'+list.map(r=>'<option value="'+esc(r.tracking_id)+'">'+esc([r.stock||'Order '+r.order,r.client,r.vehicle].filter(Boolean).join(' · '))+'</option>').join('');if(list.some(r=>r.tracking_id===value))$('finance-vehicle-picker').value=value;}
async function saveRow(id){
 guard();const row=visible().find(r=>r.id===id),draft=drafts.get(id);if(!editor()||!row||!draft||busy.has(id)||Object.keys(draft.errors||{}).length)return;
 const identity=token(),generation=epoch;busy.add(id);render();
 try{
  const {data,error}=await root.PDC_SUPABASE.rpc('save_broome_finance_application',{p_id:id,p_tracking_id:row.tracking_id||null,p_vehicle:null,p_salesperson_code:null,p_data:draft.data,p_expected_version:draft.version});
  if(identity!==token()||generation!==epoch)return;if(error||!data?.record)throw error||new Error('Finance was not saved.');
  entries=entries.map(r=>r.id===id?data.record:r);drafts.delete(id);message='Finance entry saved.';options.onLoaded?.(projection(entries));
 }catch(e){if(identity===token()&&generation===epoch)message=e.message||'Finance was not saved. Your edits remain in the row.';}
 finally{if(identity===token()&&generation===epoch){busy.delete(id);render();}}
}
async function create(e){
 e.preventDefault();guard();if(!creating||createBusy||!editor())return;const form=e.target,identity=token(),generation=epoch,id=creating.id;
 try{
  const values=new FormData(form),existing=values.get('mode')==='existing',tracking=existing?values.get('tracking_id'):null;
  if(existing&&!candidates().some(r=>r.tracking_id===tracking))throw new Error('Choose an existing vehicle.');
  const vehicle=existing?null:Object.fromEntries(['model','stock','order'].map(k=>[k,String(values.get(k)||'').trim()]));if(vehicle&&!vehicle.model)throw new Error('Enter a vehicle model.');
  const fields={...patch('customer',values.get('customer')),...patch('new_used',values.get('new_used')),...patch('group_name',values.get('group_name'))};
  createBusy=true;form.querySelector('button[type="submit"]').disabled=true;
  const {data,error}=await root.PDC_SUPABASE.rpc('save_broome_finance_application',{p_id:id,p_tracking_id:tracking||null,p_vehicle:vehicle,p_salesperson_code:existing?null:values.get('salesperson_code')||null,p_data:fields,p_expected_version:0});
  if(identity!==token()||generation!==epoch||creating?.id!==id)return;if(error||!data?.record)throw error||new Error('Finance entry was not added.');
  entries=[...entries.filter(r=>r.id!==id),data.record];message='Finance entry added. Enter the application details in its row.';options.onLoaded?.(projection(entries));close();render();
 }catch(error){if(identity===token()&&generation===epoch&&creating?.id===id)$('finance-add-message').textContent=error.message||'Finance entry was not added.';}
 finally{if(identity===token()&&generation===epoch&&creating?.id===id){createBusy=false;form.querySelector('button[type="submit"]').disabled=false;}}
}
function init(settings){
 options=settings;principal=token();scope=selected();
 $('sales-finance').addEventListener('input',e=>{
  const t=e.target,id=t.dataset.financeId,key=t.dataset.financeKey;if(!id||!key||!editor()||busy.has(id))return;const row=visible().find(r=>r.id===id);if(!row)return;
  const d=drafts.get(id)||{version:row.version,data:{},raw:{},errors:{}};d.raw[key]=t.value;drafts.set(id,d);
  try{Object.assign(d.data,patch(key,t.value));delete d.errors[key];const tr=t.closest('tr');tr.querySelector('[data-finance-save]').disabled=Object.keys(d.errors).length>0||d.version!==row.version;const totalCell=tr.querySelector('[data-label="Total Comm"]');if(totalCell)totalCell.textContent=new Intl.NumberFormat('en-AU',{style:'currency',currency:'AUD'}).format(total({...row,...d.data}));message='';}
  catch(error){d.errors[key]=error.message;message=error.message;t.closest('tr').querySelector('[data-finance-save]').disabled=true;const status=$('sales-finance').querySelector('[role="status"]');if(status)status.textContent=message;}
 });
 $('sales-finance').addEventListener('click',e=>{const t=e.target.closest('[data-finance-add],[data-finance-refresh],[data-finance-save],[data-finance-discard]');if(!t)return;guard();if(t.hasAttribute('data-finance-add'))add();else if(t.hasAttribute('data-finance-refresh'))refresh();else if(t.dataset.financeSave)saveRow(t.dataset.financeSave);else if(t.dataset.financeDiscard){drafts.delete(t.dataset.financeDiscard);message='Edits discarded. The current saved entry is shown.';render();}});
 $('finance-add-dialog').addEventListener('cancel',close);
 $('finance-add-content').addEventListener('click',e=>{if(e.target.closest('[data-finance-close]'))close();});
 $('finance-add-content').addEventListener('input',e=>{if(e.target.id==='finance-vehicle-search')findVehicles(e.target.value);});
 $('finance-add-content').addEventListener('change',e=>{
  if(e.target.name==='mode'){const existing=e.target.value==='existing';$('finance-existing-fields').hidden=!existing;$('finance-new-fields').hidden=existing;}
  if(e.target.id==='finance-vehicle-picker'){const row=candidates().find(r=>r.tracking_id===e.target.value);if(row)$('finance-add-form').querySelector('[name="customer"]').value=row.client||'';}
 });
 $('finance-add-content').addEventListener('submit',create);
}
Object.assign(api,{init,refresh,clear,render,syncScope:guard});
})(typeof window==='object'?window:globalThis);
