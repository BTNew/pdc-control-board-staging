(function(root){
 'use strict';
 const e=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 function selectRows(rows,search='',salesperson=''){
  const query=String(search).trim().toLowerCase();
  return rows.filter(r=>r.source_current===false&&r.completion_reason==='absent_from_navision'&&
   (!salesperson||r.salesperson_code===salesperson)&&(!query||
    [r.stock,r.order,r.client,r.vehicle,r.navision_notes,r.notes,r.custom_information]
     .some(value=>String(value||'').toLowerCase().includes(query))));
 }
 function dateLabel(value){
  const date=value?new Date(value):null;
  return date&&Number.isFinite(date.getTime())?date.toLocaleString('en-AU',{
   timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'}):'Not recorded';
 }
 function notesHtml(row){
  const manual=Boolean(String(row.notes||'').trim()||String(row.custom_information||'').trim());
  return '<details class="completed-notes"><summary>View saved information</summary>'+[
   ['Navision notes',row.navision_notes],['Staff notes',row.notes],['Custom information',row.custom_information]
  ].map(([label,value],index)=>'<div'+(index===0&&manual?' class="has-staff-note" title="A staff note or custom information is saved for this vehicle"':'')+'><strong>'+label+'</strong><p>'+e(value||'None recorded')+'</p></div>').join('')+'</details>';
 }
 function tableHtml(rows){
  if(!rows.length)return '<div class="empty-state">No completed vehicles match this view.</div>';
  return '<div class="table-wrap"><table class="data-table completed-table" aria-label="Completed vehicles"><thead><tr>'+[
   'SP','Stock / Toyota Order','Customer','Vehicle','Last seen in Navision','Moved to Completed','Last Toyota status','Saved information'
  ].map(x=>'<th scope="col">'+x+'</th>').join('')+'</tr></thead><tbody>'+rows.map(row=>'<tr>'+
   '<td>'+e(row.salesperson_code||'—')+'</td><td><strong>'+e(row.stock||'Toyota Order '+row.order)+'</strong>'+
   (row.stock&&row.order?'<small>Toyota Order '+e(row.order)+'</small>':'')+'</td><td>'+e(row.client||'Customer not recorded')+
   '</td><td>'+e(row.vehicle||'Vehicle not recorded')+'</td><td>'+e(dateLabel(row.last_seen_at))+
   '</td><td>'+e(dateLabel(row.completed_at))+'<small>Absent from Navision upload</small></td><td>'+e(row.toyota_status||'Not recorded')+
   '</td><td>'+notesHtml(row)+'</td></tr>').join('')+'</tbody></table></div>';
 }
 function create(host){
  const $=id=>host.document?.getElementById(id);
  const state={options:null,rows:[],request:0,busy:false,loaded:false,error:'',search:'',principal:null,scope:'',updatedAt:null};
  const principal=()=>host.PDC_AUTH_CONTEXT?.userId||null;
  const context=()=>state.options?.getContext?.();
  const scope=()=>state.options?.getSalesperson?.()||'';
  const active=()=>state.options?.getView?.()==='history';
  function clear(){
   state.request++;state.rows=[];state.busy=false;state.loaded=false;state.error='';state.search='';state.updatedAt=null;
   state.principal=principal();state.scope=scope();
   if($('completed-results'))$('completed-results').innerHTML='';
   if($('completed-status'))$('completed-status').textContent='';
   if($('sales-history'))$('sales-history').innerHTML='';
  }
  function render(){
   if(!active())return;
   if(state.principal!==principal()||state.scope!==scope())clear();
   if(!principal()||!['administrator','salesperson'].includes(context()?.role))return;
   const container=$('sales-history');if(!container)return;
   if(!container.querySelector?.('#completed-search')){
    container.innerHTML='<section class="panel completed-panel"><div class="panel-header"><div><h2>Completed vehicles</h2>'+
     '<p>Vehicles absent from the latest successful Navision upload. They return to the active board if a later upload includes them.</p></div>'+
     '<button class="small-button" type="button" id="completed-refresh">Refresh completed vehicles</button></div>'+
     '<div class="completed-toolbar"><label><span>Search completed vehicles</span><input id="completed-search" type="search" placeholder="Stock, Toyota order, customer or notes…"></label></div>'+
     '<p class="tracking-note">Moved here because they left the upload. This does not confirm customer handover.</p>'+
     '<p id="completed-status" class="tracking-note" role="status" aria-live="polite"></p><div id="completed-results"></div></section>';
    if($('completed-search')){
     $('completed-search').value=state.search;
     $('completed-search').addEventListener('input',event=>{state.search=event.target.value;render();});
    }
    $('completed-refresh')?.addEventListener('click',refresh);
   }
   const rows=selectRows(state.rows,state.search,scope());
   if($('completed-refresh'))$('completed-refresh').disabled=state.busy;
   if($('completed-status'))$('completed-status').textContent=state.error|| (state.busy?'Checking completed vehicles…':
    state.loaded?rows.length+' completed vehicle'+(rows.length===1?'':'s')+' · Navision updated '+dateLabel(state.updatedAt)+' (Perth)':'Checking completed vehicles…');
   if($('completed-results'))$('completed-results').innerHTML=state.error?'':tableHtml(rows);
  }
  async function refresh(){
   if(!active()||state.busy||!principal())return;
   if(state.principal!==principal()||state.scope!==scope())clear();
   const user=principal(),selected=scope(),request=++state.request;
   state.rows=[];state.busy=true;state.error='';render();
   try{
    const {data,error}=await host.PDC_SUPABASE.rpc('get_broome_completed_sales_vehicles');
    if(user!==principal()||selected!==scope()||request!==state.request)return;
    if(error||!data||!Array.isArray(data.items)||!['administrator','salesperson'].includes(data.context?.role))
     throw error||new Error('Completed vehicle access could not be checked.');
    // Never accept an active record in this list, even if a malformed response arrives.
    state.rows=selectRows(data.items,'',data.context.role==='salesperson'&&data.context.can_view_all_salespeople!==true?data.context.salesperson_code:'');
    state.updatedAt=data.navision_updated_at;state.loaded=true;
   }catch(error){
    if(user===principal()&&selected===scope()&&request===state.request){
     state.rows=[];state.loaded=false;state.error=error?.message||'Completed vehicles could not be loaded. Refresh to retry.';
    }
   }finally{
    if(user===principal()&&selected===scope()&&request===state.request){state.busy=false;render();}
   }
  }
  function show(){
   if(state.principal!==principal()||state.scope!==scope())clear();
   render();if(!state.loaded&&!state.busy&&!state.error)refresh();
  }
  function currentSnapshot(){
   // A new active snapshot invalidates even a closed Completed page. Returning
   // to it cannot show an order that reappeared while this page was hidden.
   state.request++;state.rows=[];state.loaded=false;state.busy=false;state.error='';
   if(active())refresh();
  }
  function init(options){
   state.options=options;state.principal=principal();state.scope=scope();
   host.addEventListener?.('pdc-auth-locked',clear);host.addEventListener?.('pdc-auth-failed',clear);
   return api;
  }
  const api={init,clear,render:show,refresh,currentSnapshot};return api;
 }
 if(typeof module==='object'&&module.exports)module.exports={create,selectRows,tableHtml,dateLabel};
 if(root.document)root.BROOME_COMPLETED_VEHICLES=create(root);
})(typeof window==='object'?window:globalThis);
