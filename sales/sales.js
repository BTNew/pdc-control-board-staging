(function (root) {
  'use strict';
  const dateTools = root.BROOME_SALES_TOOLS || (typeof module === 'object' && module.exports ? require('./dashboard-tools.js') : null);
  // Sales planner roster only; shared PMB people, imports and access remain unchanged.
  const salespeople = Object.freeze(['BG','AW','PM','CW']);
  const categories = [
    ['all','All vehicles'],['unconfirmed','Awaiting stock'],['production','Production'],
    ['transit','In Transit'],['yardhold','YH / Yard Hold'],['hold','Hold/Waiting'],
    ['released','Released'],['dealer','Dealer'],['unknown','Status not recorded']
  ];
  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }
  function category(row) {
    if (!row.stock || /^(?:0|TBA)$/i.test(row.stock)) return 'unconfirmed';
    const status = String(row.toyota_status || '').toLowerCase();
    if (String(row.location_status || '').toUpperCase() === 'YH' || status.includes('yard hold')) return 'yardhold';
    if (/planned for production|line off|final inspection|o\/s wharf|eastern states/.test(status)) return 'production';
    if (/consignment|body builder|ready for transport|ready for despatch|ready for dispatch|despatched|dispatched|despatch to|dispatch to/.test(status)) return 'released';
    if (/waiting pd|waiting for wholesale|delayed|hold|waiting/.test(status)) return 'hold';
    if (/ready for shipment|in transit|wharf|shipment/.test(status)) return 'transit';
    if (/delivered.*dealer|at dealer/.test(status)) return 'dealer';
    return 'unknown';
  }
  function flag(value) {
    if (value === true || /^(?:yes|true|1)$/i.test(String(value).trim())) return 'yes';
    if (value === false || /^(?:no|false|0)$/i.test(String(value).trim())) return 'no';
    return 'unknown';
  }
  function scopeRows(rows, salesperson='', visibility='visible') {
    return rows.filter(row=>salespeople.includes(row.salesperson_code)&&flag(row.cosi)==='yes'&&row.source_current!==false&&
      (visibility==='hidden'?row.sales_hidden===true:row.sales_hidden!==true)&&(!salesperson||row.salesperson_code===salesperson));
  }
  function todayKey(){return new Date().toLocaleDateString('en-CA',{timeZone:'Australia/Perth'});}
  function quickMatch(row,quick,today=todayKey()){
    if(!quick)return true;
    if(quick==='waiting_finance')return ['applied','pending'].includes(row.crm_finance?.approval_status)||row.crm_finance?.documents_status==='requested'||row.crm_finance?.settlement_status==='pending';
    if(quick==='needs_attention')return row.source_current===false||category(row)==='unknown'||row.parts?.stoppage===true||
      Boolean(row.pmb_stoppage_started_at&&!row.pmb_stoppage_cleared_at)||row.crm_finance?.approval_status==='declined'||
      Boolean(row.crm_contact?.next_contact_date&&row.crm_contact.next_contact_date<=today)||
      (row.crm_tasks||[]).some(t=>!t.completed&&t.due_date&&t.due_date<=today);
    if(quick==='due_week'){
      const due=dateTools?.dateKey(row.crm_delivery?.promised_delivery_date||row.dealer_eta),start=dateTools?.dateKey(today);
      if(!due||!start)return false;
      const end=new Date(start+'T00:00:00Z');end.setUTCDate(end.getUTCDate()+7);
      return due>=start&&due<=end.toISOString().slice(0,10);
    }
    return true;
  }
  const orderingLabels={tint:'TINT',build_po:'BUILD',tray_ordered:'TRAY'};
  const orderingValues={not_decided:'Not decided',not_needed:'Not required',orders_raised:'Orders Raised',completed:'Completed'};
  const orderingFields=['tint','tint_complete','build_po','build_complete','tray_ordered','tray_complete','tint_not_required','build_not_required','tray_not_required'];
  function orderingState(row,key){
    const complete={tint:'tint_complete',build_po:'build_complete',tray_ordered:'tray_complete'}[key];
    const notRequired={tint:'tint_not_required',build_po:'build_not_required',tray_ordered:'tray_not_required'}[key];
    return row[complete]===true?'completed':row[key]===true?'orders_raised':row[notRequired]===true?'not_needed':'not_decided';
  }
  function nextOrderingState(value){return value==='not_decided'?'not_needed':value==='not_needed'?'orders_raised':value==='orders_raised'?'completed':'not_decided';}
  function orderingControl(row,key,pending){
    const value=pending?.key===key?pending.status:orderingState(row,key);
    const label=orderingLabels[key]+' for '+(row.stock||'Toyota order '+(row.order||'not recorded'));
    const name=orderingValues[value],next=orderingValues[nextOrderingState(value)];
    return '<button type="button" role="checkbox" class="ordering-status '+value+'" data-ordering-id="'+escapeHtml(row.tracking_id)+'" data-ordering-flag="'+key+'" data-ordering-status="'+value+'" aria-checked="'+(value==='completed'?'true':value==='not_decided'?'false':'mixed')+'" aria-label="'+escapeHtml(label+': '+name+'. Click for '+next)+'" '+(pending||row.identity_conflict||row.sales_hidden?'disabled ':'')+'title="'+escapeHtml(name+' — click for '+next)+'"><span aria-hidden="true">'+(value==='completed'?'✓':value==='orders_raised'?'−':value==='not_needed'?'/':'')+'</span></button>';
  }
  function selectRows(rows, filters) {
    const search = String(filters.search || '').toLowerCase();
    return scopeRows(rows,filters.salesperson,filters.visibility||'visible').filter(row =>
      (filters.category === 'all' || category(row) === filters.category) && quickMatch(row,filters.quick,filters.today) &&
      (!filters.salesperson || row.salesperson_code === filters.salesperson) &&
      (!filters.month || row.production_month === filters.month) &&
      (!filters.status || row.toyota_status === filters.status) &&
      (!search || [row.stock,row.order,row.client,row.vehicle,row.vin,row.navision_notes,row.pmb_location]
        .some(value => String(value || '').toLowerCase().includes(search)))
    ).slice().sort((a,b) => {
      const rank=row=>['not_decided','not_needed','orders_raised','completed'].indexOf(orderingState(row,filters.sort));
      const sortValue=row=>filters.sort==='kewdale_eta'?dateTools?.dateKey(row.kewdale_eta):orderingLabels[filters.sort]?rank(row):row[filters.sort];
      const aa = sortValue(a), bb = sortValue(b);
      if (aa == null || aa === '') return bb == null || bb === '' ? 0 : 1;
      if (bb == null || bb === '') return -1;
      return String(aa).localeCompare(String(bb),undefined,{numeric:true,sensitivity:'base'}) * filters.direction;
    });
  }
  const bookingLabels={queued:'Awaiting bay booking',planned:'Booked',started:'Work started',stoppage:'Work stopped',completed:'Completed',deleted:'Deleted'};
  function bookingStatus(value){return bookingLabels[value]||value||'Not recorded';}
  function pmbSummary(row){
    if(!row.canonical_vehicle_id)return {status:'Not linked to PMB',location:'PMB details appear when the order is linked',bookings:[]};
    const all=Array.isArray(row.bay_bookings)?row.bay_bookings:[];
    const live=all.filter(b=>['started','stoppage'].includes(b.status));
    const active=live.find(b=>b.booking_id===row.active_workshop_booking_id);
    const bookings=active?[active,...live.filter(b=>b!==active)]:live;
    if(bookings.length)return {status:bookings.map(b=>bookingStatus(b.status)+' · '+(b.stage||'Workshop')+' / '+(b.bay||'Bay not recorded')).join('; '),location:row.pmb_location||'Location not recorded',bookings};
    const planned=all.filter(b=>b.status==='planned').sort((a,b)=>String(a.scheduled_start_at||'9999').localeCompare(String(b.scheduled_start_at||'9999')));
    if(row.pmb_stoppage_started_at&&!row.pmb_stoppage_cleared_at)return {status:'Work stopped'+(row.pmb_stoppage_reason?' · '+row.pmb_stoppage_reason:''),location:row.pmb_location||'Location not recorded',bookings:[]};
    if(planned.length)return {status:'Booked · '+(planned[0].stage||'Workshop')+' / '+(planned[0].bay||'Bay not recorded'),location:row.pmb_location||'Location not recorded',bookings:[planned[0]]};
    return {status:row.workshop_status?bookingStatus(row.workshop_status):(row.pmb_stage||'Status not recorded'),location:row.pmb_location||'Location not recorded',bookings:[]};
  }
  function partsStatus(parts){
    if(!parts)return 'Not recorded';
    if(parts.status)return parts.status;
    if(parts.received===true)return 'Parts received';
    if(parts.required===false)return 'No parts required';
    if(parts.ordered===true)return 'Parts ordered · awaiting receipt';
    if(parts.required===true)return 'Parts required · order not confirmed';
    return 'Not recorded';
  }
  const api = { salespeople, category, flag, scopeRows, selectRows, quickMatch, escapeHtml, pmbSummary, partsStatus, bookingStatus, orderingState, orderingControl, nextOrderingState };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (!root.document) return;
  const $ = id => root.document.getElementById(id);
  const defaultFilters=()=>({category:'all',search:'',salesperson:'',month:'',status:'',quick:'',sort:'stock',direction:1});
  const state = { hiddenItems:[],showHidden:false,hiddenBusy:false,hiddenRequest:0,visibilitySaving:new Set(),visibilityConfirmed:new Map(),refreshQueued:false,items:[], context:null, generation:0, busy:false, accounts:null,view:'dashboard',selected:new Set(),detailId:null,reviewedOrders:null,importBusy:false,orderRevision:0,printBusy:false,printerBusy:false,printers:[],printerName:'',saving:new Map(),
    filters:defaultFilters(),workspace:null,workspaceRequest:0,workspaceBusy:false,savedView:'',searchTimer:null,html:new Map() };
  const columns = [
    ['salesperson_code','SP'],['stock','SN'],['production_month','P/Month'],['client','Client'],
    ['vehicle','Vehicle'],['tint','TINT'],['build_po','BUILD'],['tray_ordered','TRAY'],['toyota_status','Toyota Status'],
    ['kewdale_eta','Kewdale ETA'],['pmb_location','PMB Status'],['navision_notes','Navision Notes']
  ];
  const orderingKeys = new Set(['tint','build_po','tray_ordered']);
  function html(id,content){if(state.html.get(id)!==content){$(id).innerHTML=content;state.html.set(id,content);}}
  const viewNames=['myday','dashboard','pipeline','alerts','finance','labels','history','customeremails'];
  const viewTitles={myday:'My Day',dashboard:'Dashboard',pipeline:'Pipeline',alerts:'Alerts',finance:'Finance',labels:'Labels',history:'History',customeremails:'Customer emails'};
  function currentContext(){return state.workspace?.context||state.context;}
  function moduleOptions(){return {getRows:()=>scopeRows(state.items,state.filters.salesperson),getContext:currentContext,getSalesperson:()=>state.filters.salesperson,getView:()=>state.view,
    openVehicle:openDetail,showView,onChanged:()=>refreshWorkspace().then(render)};}
  function attachWorkspace(){
    const w=state.workspace||{};
    for(const row of state.items){
      row.crm_contact=(w.contacts||[]).find(x=>x.tracking_id===row.tracking_id);
      row.crm_delivery=(w.delivery||[]).find(x=>x.tracking_id===row.tracking_id);
      row.crm_finance=(w.finance||[]).find(x=>x.tracking_id===row.tracking_id&&x.current_application!==false);
      row.crm_tasks=(w.tasks||[]).filter(x=>x.tracking_id===row.tracking_id);
    }
  }
  function populateSalespeople(){
    if(state.context?.role!=='administrator')return;
    const selected=state.filters.salesperson;
    const people=salespeople;
    html('salesperson-filter','<option value="">All salespeople</option>'+people.map(code=>'<option value="'+escapeHtml(code)+'">'+escapeHtml(code)+'</option>').join(''));
    state.filters.salesperson=people.includes(selected)?selected:'';
    $('salesperson-filter').value=state.filters.salesperson;
  }
  function populateSavedViews(){
    const own=state.workspace?.views||[];
    const presets=[['','All orders'],['preset:due_week','Due this week'],['preset:waiting_finance','Waiting on finance'],['preset:needs_attention','Needs attention']];
    html('sales-saved-view',presets.map(([v,label])=>'<option value="'+v+'">'+label+'</option>').join('')+
      own.map(v=>'<option value="'+escapeHtml(v.id)+'">'+escapeHtml(v.name)+'</option>').join(''));
    if(state.savedView&&!state.savedView.startsWith('preset:')&&!own.some(v=>v.id===state.savedView))state.savedView='';
    $('sales-saved-view').value=state.savedView;
  }
  async function refreshWorkspace(){
    if(!root.BROOME_SALES_CRM)return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,request=++state.workspaceRequest;
    if(!principal)return;
    state.workspaceBusy=true;
    try{
      const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_sales_workspace');
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId||request!==state.workspaceRequest)return;
      if(error||!data||!['administrator','salesperson'].includes(data.context?.role))throw error||new Error('Sales workspace is unavailable.');
      if(root.BROOME_SALES_FINANCE)data.finance=state.financeProjection||[];data.leads=[];state.workspace=data;populateSalespeople();
      root.BROOME_SALES_CRM?.setWorkspace(data);
      attachWorkspace();populateSavedViews();$('sales-workspace-status').textContent='';
    }catch(e){
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId||request!==state.workspaceRequest)return;
      state.workspace=null;root.BROOME_SALES_CRM?.clear();attachWorkspace();populateSavedViews();
      $('sales-workspace-status').textContent=e.message||'Sales updates could not be loaded. Refresh to retry.';
    }finally{if(generation===state.generation&&request===state.workspaceRequest)state.workspaceBusy=false;}
  }
  async function saveView(){
    if(!state.workspace||!$('sales-view-name').value.trim())return;
    const existing=(state.workspace.views||[]).find(v=>v.id===state.savedView);
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId;
    $('sales-save-view').disabled=true;
    try{
      const filters=Object.fromEntries(['category','search','month','status','quick','sort','direction'].map(k=>[k,state.filters[k]]));
      const {data,error}=await root.PDC_SUPABASE.rpc('save_broome_sales_crm',{p_kind:'view',p_id:existing?.id||null,p_tracking_id:null,
        p_data:{name:$('sales-view-name').value.trim(),filters},p_expected_version:existing?.version||0});
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      if(error)throw error;
      state.savedView=data.record.id;await refreshWorkspace();
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      $('sales-view-status').textContent='View saved.';
    }catch(e){if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)$('sales-view-status').textContent=e.message||'View was not saved.';}
    finally{if(generation===state.generation)$('sales-save-view').disabled=false;}
  }
  function message(text) { $('sales-error').textContent=text; $('sales-error').hidden=!text; }
  function dateLabel(value) {
    if (!value) return 'Not recorded';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? String(value) :
      date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'});
  }
  function clear() {
    state.hiddenRequest++;state.hiddenItems=[];state.showHidden=false;state.hiddenBusy=false;state.visibilitySaving.clear();state.visibilityConfirmed.clear();state.refreshQueued=false;
    $('sales-visibility-status').textContent='';$('sales-hidden-toggle').disabled=false;
    state.generation++;state.workspaceRequest++;state.workspace=null;state.workspaceBusy=false;state.savedView='';state.html.clear();
    if(state.searchTimer!==null)root.clearTimeout?.(state.searchTimer);state.searchTimer=null;
    root.BROOME_SALES_CRM?.clear();root.BROOME_SALES_BUILDS?.clear();root.BROOME_SALES_EMAIL?.clear();root.BROOME_CUSTOMER_EMAILS?.clear();root.BROOME_SALES_FINANCE?.clear();state.financeProjection=[];columnWidths?.clear();
    $('sales-mobile-vehicles').innerHTML='';$('sales-saved-view').innerHTML='';$('sales-view-name').value='';$('sales-view-status').textContent='';$('sales-workspace-status').textContent='';
    state.busy=false; state.printBusy=false;state.printerBusy=false;state.printers=[];state.printerName='';$('sales-label-printer').innerHTML='<option value="">Connect to load printers</option>';$('sales-label-printer').disabled=true;$('sales-connect-printer').disabled=false;$('sales-save-view').disabled=false;$('sales-label-status').textContent=''; state.items=[]; state.context=null; state.accounts=null;
    state.selected.clear();
    state.saving.clear();$('sales-checklist-status').textContent='';
    state.detailId=null;state.reviewedOrders=null;state.importBusy=false;state.orderRevision++;
    $('vehicle-table').innerHTML=''; $('status-tabs').innerHTML=''; $('sales-summary').innerHTML='';
    $('sales-pipeline').innerHTML=''; $('sales-labels').innerHTML=''; $('sales-print-labels').disabled=true;
    $('sales-data-date').textContent=''; $('sales-data-count').textContent='';
    $('sales-sync').textContent=''; $('sales-scope').textContent='';
    $('salesperson-filter').innerHTML=''; $('salesperson-filter-label').hidden=true;
    $('sales-detail').close(); $('sales-detail-content').innerHTML=''; message('');
    $('sales-refresh').disabled=false;
    state.filters=defaultFilters();
    $('search').value='';
    for(const id of ['sales-month-filter','sales-status-filter'])$(id).innerHTML='';

  }
  const categoryDescriptions={all:'COSI sold vehicles in this view',unconfirmed:'Rows without a stock number',production:'Production and early transit statuses',transit:'Shipment, WA transit and wharf',yardhold:'Location status YH or yard hold',hold:'Delayed, wholesale, PD and wharf waits',released:'Body builder and TWA despatch',dealer:'Delivered to the dealer',unknown:'Toyota status needs confirmation'};
  function showView(view) {
    if(!viewNames.includes(view))return;
    if(state.detailId){state.detailId=null;$('sales-detail').close();$('sales-detail-content').innerHTML='';}
    state.view=view;
    for(const name of viewNames)$('sales-'+name+'-view').hidden=name!==view;
    $('sales-page-title').textContent=viewTitles[view];
    for(const button of root.document.querySelectorAll?.('[data-sales-view]')||[]){
      button.classList.toggle('active',button.dataset.salesView===view);
      if(button.dataset.salesView===view)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');
    }
    render();
  }
  function populateFilters() {
    const scoped=scopeRows(state.showHidden?state.hiddenItems:state.items,state.filters.salesperson,state.showHidden?'hidden':'visible');
    for(const [id,key,label] of [['sales-month-filter','production_month','All months'],['sales-status-filter','toyota_status','All statuses']]) {
      const value=$(id).value;
      const options=[...new Set(scoped.map(r=>r[key]).filter(Boolean))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
      html(id,'<option value="">'+label+'</option>'+options.map(x=>'<option value="'+escapeHtml(x)+'">'+escapeHtml(x)+'</option>').join(''));
      $(id).value=options.includes(value)?value:'';
      state.filters[key==='production_month'?'month':'status']=$(id).value;
    }
  }
  function renderSecondaryViews() {
    const scoped=scopeRows(state.items,state.filters.salesperson);
    if(state.view==='pipeline')html('sales-pipeline',categories.filter(([key])=>key!=='all').map(([key,label])=>{
      const rows=scoped.filter(r=>category(r)===key);
      return '<section class="pipeline-column"><h2>'+label+' <span>'+rows.length+'</span></h2>'+
        (rows.length?rows.map(r=>'<button class="pipeline-card" type="button" data-open="'+escapeHtml(r.tracking_id)+'"><strong>'+escapeHtml(r.stock||r.order||'Unconfirmed')+'</strong><p>'+escapeHtml(r.client||'Customer not recorded')+'</p><p>'+escapeHtml(r.vehicle||'Vehicle not recorded')+'</p><span class="status-pill '+key+'">'+escapeHtml(r.toyota_status||'Not recorded')+'</span>'+(r.pmb_location?'<p>PMB: '+escapeHtml(r.pmb_location)+'</p>':'')+'</button>').join(''):'<div class="empty-state">No vehicles</div>')+'</section>';
    }).join(''));else html('sales-pipeline','');
    if(state.view!=='labels'){html('sales-labels','');$('sales-print-labels').disabled=true;return;}
    $('sales-connect-printer').disabled=state.printerBusy||state.printBusy;$('sales-label-printer').disabled=state.printerBusy||state.printBusy||!state.printers.length;
    const labels=scoped.filter(r=>state.selected.has(r.tracking_id));
    html('sales-labels',labels.length?labels.map(r=>{
      const data=root.BROOME_ZEBRA_LABELS.labelData(r);
      return '<div class="label-item"><article class="vehicle-label zebra-label" aria-label="Zebra label for '+escapeHtml(r.stock||'Toyota order '+r.order)+'">'+
      '<strong class="label-stock-top">'+escapeHtml(data.stock||'NO STOCK')+'</strong><div class="label-customer">'+escapeHtml(data.customer||'(Dealer Order)')+'</div>'+
      '<div class="label-sales">'+escapeHtml(data.sales||'—')+'</div><div class="label-model">'+escapeHtml(data.model||'Vehicle not listed')+'</div>'+
      '<div class="label-description">'+escapeHtml(data.description||'Details not recorded')+'</div><div class="label-vin">'+escapeHtml(data.vin||'VIN not recorded')+'</div>'+
      '<strong class="label-stock-bottom">'+escapeHtml(data.stock||'NO STOCK')+'</strong></article>'+
      (!r.stock?'<p class="label-warning">Toyota order '+escapeHtml(r.order||'Not recorded')+' · awaiting stock number. Both stock fields print NO STOCK.</p>':'')+(!data.vin?'<p class="label-warning">VIN is not available in the uploaded vehicle data. Labels update when Navision supplies it.</p>':'')+'</div>';
    }).join(''):'<div class="empty-state">Select vehicles on the Dashboard, then choose View labels.</div>');
    $('sales-print-labels').disabled=!labels.length||state.printBusy||state.printerBusy;
  }
  function render() {
    root.BROOME_SALES_EMAIL?.syncScope();root.BROOME_CUSTOMER_EMAILS?.render();
    root.BROOME_SALES_CRM?.syncScope?.();root.BROOME_SALES_BUILDS?.syncScope();root.BROOME_SALES_BUILDS?.render();
    const scoped=scopeRows(state.items,state.filters.salesperson);
    $('sales-data-count').textContent=scoped.length+' COSI vehicles · Navision';
    const currentIds=new Set(scoped.map(r=>r.tracking_id));
    for(const id of state.selected)if(!currentIds.has(id))state.selected.delete(id);
    if(state.detailId&&!currentIds.has(state.detailId)){state.detailId=null;$('sales-detail').close();$('sales-detail-content').innerHTML='';}
    if(state.view!=='dashboard'){
      if(state.view==='finance'&&root.BROOME_SALES_FINANCE)root.BROOME_SALES_FINANCE.render();
      else if(['myday','alerts','finance','history'].includes(state.view))root.BROOME_SALES_CRM?.render(state.view);
      renderSecondaryViews();return;
    }
    const focus=root.document.activeElement;
    const focusKey=focus?.dataset?.orderingId?{id:focus.dataset.orderingId,flag:focus.dataset.orderingFlag,mobile:!!focus.closest?.('#sales-mobile-vehicles')}:null;
    const rows=selectRows(state.showHidden?state.hiddenItems:state.items,{...state.filters,visibility:state.showHidden?'hidden':'visible'});
    $('sales-hidden-toggle').textContent=state.showHidden?'Show dashboard':'Hidden vehicles';
    $('sales-hidden-toggle').setAttribute('aria-pressed',String(state.showHidden));
    $('sales-hidden-toggle').disabled=state.hiddenBusy;
    $('sales-tracker-title').textContent=state.showHidden?'Hidden vehicles':'Navision vehicle tracker';
    $('sales-tracker-help').textContent=state.showHidden?'These vehicles are hidden from the sales dashboard, My Day, labels and customer email lists. Choose Show on sales planner in the Action menu to restore a vehicle. Vehicles absent from the latest successful Navision update are removed from both lists.':'';
    html('status-tabs',categories.map(([key,label]) => '<button type="button" data-category="'+key+
      '" class="status-card '+key+(state.filters.category===key?' active':'')+'" aria-pressed="'+(state.filters.category===key)+'">'+
      '<span>'+label+'</span><strong>'+scoped.filter(r=>key==='all'||category(r)===key).length+'</strong><small>'+categoryDescriptions[key]+'</small></button>').join(''));
    html('sales-summary','<span>'+rows.length+(state.showHidden?' hidden vehicles shown':' vehicles shown')+'</span><span>'+
      (state.showHidden?rows:scoped).filter(r=>r.canonical_vehicle_id).length+' linked to PMB</span><span>'+state.selected.size+' selected for labels</span>');
    $('sales-data-count').textContent=scoped.length+' COSI vehicles · Navision';
    html('vehicle-table','<colgroup>'+[...columns,['action','Action']].map(()=>'<col>').join('')+'</colgroup><thead><tr>'+columns.map(([key,label],index)=>'<th aria-sort="'+
      (state.filters.sort===key?(state.filters.direction===1?'ascending':'descending'):'none')+
      '">'+(key==='salesperson_code'?'<input type="checkbox" id="sales-select-visible" aria-label="Select visible vehicles for labels" '+(state.showHidden?'disabled ':rows.length&&rows.every(r=>state.selected.has(r.tracking_id))?'checked':'')+'>':'')+'<button type="button" data-sort="'+key+'">'+label+(state.filters.sort===key?(state.filters.direction===1?' ↑':' ↓'):'')+
      '</button>'+resizeHandle(index,label)+'</th>').join('')+'<th>Action'+resizeHandle(columns.length,'Action')+'</th></tr></thead><tbody>'+
      (rows.length?rows.map(row=>'<tr class="'+(state.selected.has(row.tracking_id)?'selected':'')+'">'+columns.map(([key])=>{
        const val=row[key];
        if (key==='salesperson_code')return '<td><input type="checkbox" data-select="'+escapeHtml(row.tracking_id)+'" aria-label="Select '+escapeHtml(row.stock||row.order||'vehicle')+' for labels" '+(row.sales_hidden?'disabled ':state.selected.has(row.tracking_id)?'checked':'')+'>'+escapeHtml(val||'—')+'</td>';
        if (key==='production_month')return '<td><span class="month-pill">'+escapeHtml(val||'—')+'</span></td>';
        if (orderingKeys.has(key)) return '<td class="sales-ordering-cell">'+orderingControl(row,key,state.saving.get(row.tracking_id)||(state.visibilitySaving.has(row.tracking_id)?{}:null))+'</td>';
        if (key==='stock') return '<td><button type="button" class="stock-button" '+(row.sales_hidden?'disabled ':'')+'data-open="'+escapeHtml(row.tracking_id)+'">'+
          escapeHtml(val||row.order||'Unconfirmed')+'</button><span class="subtle">Toyota '+escapeHtml(row.order||'Not recorded')+'</span>'+(!val?'<span class="subtle">Awaiting stock number</span>':'')+(row.source_current===false?'<span class="source-warning">Not in latest PDC import</span>':'')+(row.identity_conflict?'<span class="source-warning">Order link needs review</span>':'')+'</td>';
        if (key==='toyota_status') return '<td><span class="status-pill '+category(row)+'" title="'+escapeHtml(val||'Not recorded')+'">'+escapeHtml(val||'Not recorded')+'</span></td>';
        if (key==='kewdale_eta')return '<td class="eta-cell">'+etaHtml(val)+'</td>';
        if (key==='pmb_location') {const summary=pmbSummary(row);return '<td class="pmb-status-cell"><strong>'+escapeHtml(summary.status)+'</strong><div class="subtle">'+escapeHtml(summary.location)+'</div>'+
          (summary.bookings[0]?.scheduled_start_at?'<div class="subtle">Booked '+escapeHtml(dateLabel(summary.bookings[0].scheduled_start_at))+'</div>':'')+'</td>';}
        return '<td class="'+(key==='navision_notes'?'notes-cell':'')+'" title="'+escapeHtml(val||'')+'">'+escapeHtml(val||'—')+'</td>';
      }).join('')+'<td>'+actionHtml(row)+'</td></tr>').join(''):'<tr><td colspan="13"><div class="empty-state">No vehicles match this view.</div></td></tr>')+'</tbody>');
    columnWidths?.apply();
    html('sales-mobile-vehicles',rows.length?rows.map(row=>'<article class="mobile-vehicle"><div class="mobile-vehicle-head"><input type="checkbox" data-select="'+escapeHtml(row.tracking_id)+'" aria-label="Select '+escapeHtml(row.stock||row.order)+' for labels" '+(row.sales_hidden?'disabled ':state.selected.has(row.tracking_id)?'checked':'')+'><button class="stock-button" type="button" '+(row.sales_hidden?'disabled ':'')+'data-open="'+escapeHtml(row.tracking_id)+'">'+escapeHtml(row.stock||'Order '+row.order)+'</button><span>'+escapeHtml(row.salesperson_code||'')+'</span></div><strong>'+escapeHtml(row.client||'Customer not recorded')+'</strong><p>'+escapeHtml(row.vehicle||'Vehicle not recorded')+'</p><span class="status-pill '+category(row)+'">'+escapeHtml(row.toyota_status||'Status not recorded')+'</span><p class="mobile-pmb">'+escapeHtml(pmbSummary(row).status)+'</p><p class="mobile-eta">Kewdale ETA: '+etaHtml(row.kewdale_eta)+'</p><p>Dealer ETA: '+escapeHtml(row.dealer_eta||'Not recorded')+'</p><div class="mobile-ordering">'+[...orderingKeys].map(key=>'<label><span>'+orderingLabels[key]+'</span>'+orderingControl(row,key,state.saving.get(row.tracking_id)||(state.visibilitySaving.has(row.tracking_id)?{}:null))+'</label>').join('')+'</div><button class="small-button" type="button" '+(row.sales_hidden?'disabled ':'')+'data-open="'+escapeHtml(row.tracking_id)+'">Vehicle and customer details</button>'+actionHtml(row)+'</article>').join(''):'<div class="empty-state">No vehicles match this view.</div>');
    if(focusKey)root.document.querySelector?.((focusKey.mobile?'#sales-mobile-vehicles ':'#vehicle-table ')+'[data-ordering-id="'+focusKey.id+'"][data-ordering-flag="'+focusKey.flag+'"]')?.focus?.({preventScroll:true});
    renderSecondaryViews();
  }

  function resizeHandle(index,label){return '<span class="column-resize" role="separator" tabindex="0" data-resize="'+index+'" aria-orientation="vertical" aria-label="Resize '+escapeHtml(label)+' column" aria-valuemin="40" aria-valuemax="600" title="Drag to resize. Arrow keys adjust width; Home or double-click resets."></span>';}
  function etaHtml(value){
    const info=root.BROOME_SALES_TOOLS?.etaInfo(value);
    if(!info)return escapeHtml(value||'Not recorded');
    return '<strong>'+escapeHtml(info.date)+'</strong>'+(info.label?'<span class="eta-counter '+info.tone+'">'+escapeHtml(info.label)+'</span>':'');
  }
  function actionHtml(row){
    const id=escapeHtml(row.tracking_id),label='Action for '+escapeHtml(row.stock||'Toyota order '+row.order);
    return '<select class="sales-action" data-email-id="'+id+'" aria-label="'+label+'" '+(row.identity_conflict||state.visibilitySaving.has(row.tracking_id)?'disabled ':'')+'><option value="">Select action…</option>'+
      (row.sales_hidden?'<option value="show">Show on sales planner</option>':'<option value="details">View details</option>'+
      (root.BROOME_SALES_EMAIL?.types||[]).map(([key,title])=>'<option value="'+key+'">'+title+'</option>').join('')+'<option value="hide">Hide from sales planner</option>')+'</select>';
  }
  function emailAction(target){
    if(!target.dataset.emailId)return false;
    const id=target.dataset.emailId,kind=target.value;target.value='';
    if(kind==='hide'||kind==='show')setVehicleVisibility(id,kind==='hide');
    else if(kind==='details')openDetail(id);else if(kind)root.BROOME_SALES_EMAIL?.open(kind,id);
    return true;
  }

  function vehicleInfoHtml(r) {
    const details=[
      ['Stock',r.stock],['Toyota order',r.order],['Division',r.division],['Salesperson',r.salesperson_name],
      ['Vehicle',r.vehicle],['Colour',r.colour],['Suffix',r.suffix],['Trim',r.trim],['VIN',r.vin],
      ['Production month',r.production_month],['Toyota status',r.toyota_status],['Kewdale ETA',r.kewdale_eta],
      ['Dealer / body builder ETA',r.dealer_eta],['Port / plant ETA',r.port_plant_eta],['PMB arrival',r.pmb_arrival_date],
      ['Delivered to dealer',r.dealer_delivered_date],['Transport booked',r.transport_booked_at?dateLabel(r.transport_booked_at):null],['Collected',r.collected_at?dateLabel(r.collected_at):null],
      ['PMB location',r.pmb_location],['PMB stage',r.pmb_stage],['Workshop progress',r.workshop_status],
      ['Key number',r.key_number],['Job card',r.job_card],['Sales type',r.sales_type],
      ['Customer category',r.customer_category],['QC completed',r.qc_completed_at?dateLabel(r.qc_completed_at):null],
      ['RFT transferred',r.rft_transferred_at?dateLabel(r.rft_transferred_at):null],
      ['Tracking identifier',r.tracking_id],['PMB permanent identifier',r.permanent_vehicle_id],
      ['Navision updated',dateLabel(r.navision_updated_at)],['PMB updated',r.pmb_updated_at?dateLabel(r.pmb_updated_at):null]
    ];
    return '<h3>Vehicle and delivery details</h3><dl class="detail-grid">'+details.map(([label,val])=>'<div><dt>'+escapeHtml(label)+'</dt><dd>'+escapeHtml(val||'Not recorded')+
      '</dd></div>').join('')+'</dl><h3>Navision notes</h3><p class="detail-notes">'+escapeHtml(r.navision_notes||'No notes recorded')+'</p>';
  }
  function openDetail(id) {
    const r=scopeRows(state.items,state.filters.salesperson).find(row=>row.tracking_id===id); if (!r) return;
    state.detailId=id;

    $('sales-detail-content').innerHTML='<div class="panel-header"><div><h2>'+escapeHtml(r.stock||r.order||'Vehicle')+
      '</h2><p>'+escapeHtml(r.client)+'</p></div><button type="button" class="small-button" id="sales-detail-close">Close</button></div>'+
      '<div id="sales-pmb-live">'+workshopHtml(r)+'</div>'+(root.BROOME_SALES_BUILDS?.detailHtml(r)||'')+(root.BROOME_SALES_CRM?.detailHtml(r)||'')+'<div id="sales-source-detail">'+vehicleInfoHtml(r)+'</div>';
    $('sales-detail-close').addEventListener('click',()=>{ state.detailId=null;$('sales-detail').close(); $('sales-detail-content').innerHTML=''; });
    state.html.delete('sales-pmb-live');state.html.delete('sales-source-detail');
    root.BROOME_SALES_CRM?.bindDetail(id);
    root.BROOME_SALES_BUILDS?.bindDetail(id);
    if(!$('sales-detail').open)$('sales-detail').showModal();
  }
  function bookingHtml(bookings) {
    if(!Array.isArray(bookings)||!bookings.length)return '<p class="detail-notes">No bay bookings recorded.</p>';
    return '<div class="booking-list">'+bookings.map(b=>'<article class="booking-card"><strong>'+escapeHtml(b.stage||'Workshop')+' · '+escapeHtml(b.bay||'Bay not recorded')+'</strong><span class="status-pill">'+escapeHtml(bookingStatus(b.status))+'</span><dl><div><dt>Scheduled</dt><dd>'+escapeHtml(dateLabel(b.scheduled_start_at))+' → '+escapeHtml(dateLabel(b.scheduled_end_at))+'</dd></div><div><dt>Started</dt><dd>'+escapeHtml(dateLabel(b.actual_start_at))+'</dd></div><div><dt>Finished</dt><dd>'+escapeHtml(dateLabel(b.actual_end_at))+'</dd></div></dl>'+
      (b.stoppage_reason?'<p class="detail-notes">Stopped: '+escapeHtml(b.stoppage_reason)+(b.stoppage_started_at?' · '+escapeHtml(dateLabel(b.stoppage_started_at)):'')+'</p>':'')+
      (b.progress?'<p class="detail-notes">Recorded work: '+escapeHtml(b.progress.completed_lines)+' of '+escapeHtml(b.progress.total_lines)+' items complete · '+escapeHtml(b.progress.percent)+'%</p>':'')+'</article>').join('')+'</div>';
  }
  function workshopHtml(row){
    const summary=pmbSummary(row),parts=row.parts;
    if(!row.canonical_vehicle_id)return '<section class="pmb-overview"><h3>PMB status</h3><p>'+escapeHtml(summary.status)+'. '+escapeHtml(summary.location)+'.</p></section>';
    const yesNo=value=>value===true?'Yes':value===false?'No':'Not recorded';
    const facts=[['Location',summary.location],['PMB arrival',row.pmb_arrival_date],['PMB stage',row.pmb_stage],
      ['QC completed',row.qc_completed_at?dateLabel(row.qc_completed_at):null],['Ready for transport confirmed',row.rft_confirmed_at?dateLabel(row.rft_confirmed_at):null],
      ['Transferred to RFT',row.rft_transferred_at?dateLabel(row.rft_transferred_at):null]];
    return '<section class="pmb-overview"><h3>PMB status</h3><p class="pmb-current">'+escapeHtml(summary.status)+'</p><p class="subtle">Live PMB information · read-only · updated '+escapeHtml(dateLabel(row.pmb_updated_at))+'</p><dl class="detail-grid">'+facts.map(([label,val])=>'<div><dt>'+escapeHtml(label)+'</dt><dd>'+escapeHtml(val||'Not recorded')+'</dd></div>').join('')+'</dl></section>'+
      '<h3>Parts</h3><p class="parts-current">'+escapeHtml(partsStatus(parts))+'</p>'+
      (parts?'<dl class="detail-grid">'+[['Parts required',yesNo(parts.required)],['Order recorded',yesNo(parts.ordered)],['Receipt recorded',yesNo(parts.received)],
        ['Parts ETA',parts.eta],['Parts feed updated',parts.snapshot_at?dateLabel(parts.snapshot_at):null],['PMB parts update',parts.updated_at?dateLabel(parts.updated_at):null]]
        .map(([label,val])=>'<div><dt>'+escapeHtml(label)+'</dt><dd>'+escapeHtml(val||'Not recorded')+'</dd></div>').join('')+'</dl>'+
        (parts.stoppage===true?'<p class="parts-stoppage">Parts stoppage: '+escapeHtml(parts.stoppage_reason||'Reason not recorded')+'</p>':'')+
        (Array.isArray(parts.jobs)&&parts.jobs.length?'<div class="parts-jobs">'+parts.jobs.map(j=>'<p><strong>Job '+escapeHtml(j.job_number||'Not recorded')+'</strong> · '+escapeHtml(j.status||'Status not recorded')+'</p>').join('')+'</div>':''):'')+
      '<h3>Bay bookings and work progress</h3>'+bookingHtml(row.bay_bookings);
  }
  async function saveOrderingFlag(id,key,status) {
    const row=scopeRows(state.items,state.filters.salesperson).find(r=>r.tracking_id===id);
    if(!row||row.identity_conflict||!orderingKeys.has(key)||!Object.hasOwn(orderingValues,status)||state.saving.has(id)||!['salesperson','administrator'].includes(state.context?.role))return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId;
    const label=columns.find(([name])=>name===key)[1];
    state.saving.set(id,{key,status});message('');$('sales-checklist-status').textContent='Saving '+label+'…';render();
    try{
      const {data,error}=await root.PDC_SUPABASE.rpc('set_broome_sales_ordering_status',{
        p_tracking_id:id,p_item:{tint:'tint',build_po:'build',tray_ordered:'tray'}[key],p_status:status,p_expected_version:row.ordering_version||0
      });
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      if(error||!data||data.tracking_id!==id||data.ordering_version!==(row.ordering_version||0)+1||!orderingFields.every(name=>typeof data[name]==='boolean'))throw error||new Error('The ordering status could not be confirmed. Refresh and check it before trying again.');
      const current=state.items.find(r=>r.tracking_id===id);
      if(current&&(data.ordering_version||0)>=(current.ordering_version||0)){
        for(const name of orderingFields)current[name]=data[name]===true;
        current.ordering_version=data.ordering_version;current.ordering_updated_at=data.ordering_updated_at;
      }
      $('sales-checklist-status').textContent=label+' saved for '+(row.stock||'Toyota order '+row.order)+'.';
    }catch(e){
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){
        state.saving.delete(id);render();$('sales-checklist-status').textContent='Status could not be confirmed. Refresh and check it before trying again.';
        message(e.message||'The ordering status could not be confirmed. Refresh and check it before trying again.');
      }
    }finally{
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){state.saving.delete(id);render();}
    }
  }
  async function connectPrinter(){
    if(state.printerBusy||state.printBusy||!['administrator','salesperson'].includes(state.context?.role)||state.view!=='labels')return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,salesperson=state.filters.salesperson;
    const current=()=>generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId&&state.view==='labels'&&salesperson===state.filters.salesperson&&['administrator','salesperson'].includes(state.context?.role);
    state.printerBusy=true;renderSecondaryViews();$('sales-label-status').textContent='Connecting to QZ Tray and checking printers…';
    try{
      const result=await root.BROOME_ZEBRA_LABELS.checkConnection(current);if(!current())return;
      state.printers=result.printers;
      let saved='';try{saved=root.localStorage?.getItem('broome-sales-qz-printer-v1')||'';}catch{}
      state.printerName=state.printers.includes(saved)?saved:result.printer||'';
      html('sales-label-printer','<option value="">Choose a Zebra / ZPL printer</option>'+state.printers.map(name=>'<option value="'+escapeHtml(name)+'">'+escapeHtml(name)+'</option>').join(''));
      $('sales-label-printer').value=state.printerName;
      $('sales-label-status').textContent=state.printerName?'QZ Tray connected. Printer: '+state.printerName+'.':state.printers.length?'QZ Tray connected. Choose the Zebra / ZPL printer from the list.':'QZ Tray connected, but no printer queues were found on this computer.';
    }catch(error){if(current()){$('sales-label-status').textContent=root.BROOME_ZEBRA_LABELS.errorMessage(error)+' If prompted, allow this website to connect to QZ Tray / apps on this device.';}}
    finally{if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){state.printerBusy=false;if(!current())$('sales-label-status').textContent='Printer check cancelled. Connect again for this view.';renderSecondaryViews();}}
  }
  async function printLabels(){
    if(state.view!=='labels'||state.printBusy||state.printerBusy)return;
    const rows=scopeRows(state.items,state.filters.salesperson).filter(r=>state.selected.has(r.tracking_id));
    if(!rows.length||!['administrator','salesperson'].includes(state.context?.role))return;
    if(state.printers.length&&!state.printerName){$('sales-label-status').textContent='Choose the Zebra / ZPL printer before printing.';return;}
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,ids=rows.map(r=>r.tracking_id),facts=new Map(rows.map(r=>[r.tracking_id,JSON.stringify(root.BROOME_ZEBRA_LABELS.labelData(r))]));
    state.printBusy=true;renderSecondaryViews();$('sales-label-status').textContent='Connecting to Zebra printer…';
    try{
      const printer=await root.BROOME_ZEBRA_LABELS.print(rows,()=>state.view==='labels'&&generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId&&
        ids.every(id=>{const current=scopeRows(state.items,state.filters.salesperson).find(r=>r.tracking_id===id);return current&&state.selected.has(id)&&JSON.stringify(root.BROOME_ZEBRA_LABELS.labelData(current))===facts.get(id);}),state.printerName);
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)$('sales-label-status').textContent='Sent 2 label copies for each of '+rows.length+' vehicle'+(rows.length===1?'':'s')+' to '+printer+'.';
    }catch(error){
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)$('sales-label-status').textContent=(root.BROOME_ZEBRA_LABELS.errorMessage?.(error)||error?.message||String(error||'Printing failed.'))+' QZ Tray must be running. Allow QZ Tray / apps on this device if prompted.';
    }finally{
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){state.printBusy=false;renderSecondaryViews();}
    }
  }
  async function refresh() {
    if (state.busy || !root.PDC_AUTH_CONTEXT) return;
    const generation=state.generation; const principal=root.PDC_AUTH_CONTEXT.userId;
    state.busy=true; $('sales-refresh').disabled=true;
    try {
      const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_sales_snapshot');
      if (generation!==state.generation || principal!==root.PDC_AUTH_CONTEXT?.userId) return;
      if (error || !data || !Array.isArray(data.items)) throw error||new Error('Vehicle data could not be loaded.');
      if (!['administrator','salesperson'].includes(data.context?.role)) throw new Error('Sales access is not approved.');
      // A poll started before a tick save must not replace its newer confirmed version.
      const previous=new Map(state.items.map(r=>[r.tracking_id,r]));
      state.items=scopeRows(data.items.map(applyConfirmedVisibility)).map(r=>{
        const old=previous.get(r.tracking_id);
        if(old&&(old.ordering_version||0)>(r.ordering_version||0)){
          for(const name of orderingFields)r[name]=old[name];
          r.ordering_version=old.ordering_version;r.ordering_updated_at=old.ordering_updated_at;
        }
        return r;
      }); state.context=data.context; message('');
      if(state.detailId&&!state.items.some(r=>r.tracking_id===state.detailId)){state.detailId=null;$('sales-detail').close();$('sales-detail-content').innerHTML='';}
      const currentIds=new Set(state.items.map(r=>r.tracking_id));
      for(const id of state.selected)if(!currentIds.has(id))state.selected.delete(id);
      $('sales-data-date').textContent=dateLabel(data.navision_updated_at);
      $('sales-scope').textContent=data.context.role==='administrator'?'Broome Toyota · Administrator view':
        data.context.display_name+' · My vehicles · Broome Toyota';
      $('sales-sync').textContent='Navision updated '+dateLabel(data.navision_updated_at)+' · Checked '+dateLabel(data.checked_at)+' (Perth)';
      $('salesperson-filter-label').hidden=data.context.role!=='administrator';
      if (data.context.role==='administrator') populateSalespeople();
      if(state.detailId){const detailRow=state.items.find(r=>r.tracking_id===state.detailId);if(detailRow){html('sales-pmb-live',workshopHtml(detailRow));html('sales-source-detail',vehicleInfoHtml(detailRow));}}
      attachWorkspace();populateFilters();render();
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)await root.BROOME_SALES_BUILDS?.refresh();
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      await refreshWorkspace();
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)await root.BROOME_SALES_FINANCE?.refresh();
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)await root.BROOME_CUSTOMER_EMAILS?.refresh();
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId&&state.showHidden)await loadHiddenVehicles();
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId)render();
    } catch (error) {
      if (generation!==state.generation || principal!==root.PDC_AUTH_CONTEXT?.userId) return;
      clear(); message(error.message||'Unable to refresh vehicles. Try again.');
    } finally { if (generation===state.generation) {state.busy=false; $('sales-refresh').disabled=false;if(state.refreshQueued){state.refreshQueued=false;refresh();}} }
  }
  function applyConfirmedVisibility(row){
    const confirmed=state.visibilityConfirmed.get(row.tracking_id);
    return confirmed&&confirmed.version>(row.sales_visibility_version||0)?
      {...row,sales_hidden:confirmed.hidden,sales_visibility_version:confirmed.version}:row;
  }
  async function loadHiddenVehicles(){
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,request=++state.hiddenRequest;
    if(!principal||!state.showHidden)return;
    state.hiddenBusy=true;render();
    try{
      const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_hidden_sales_vehicles');
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId||request!==state.hiddenRequest||!state.showHidden)return;
      if(error||!data||!Array.isArray(data.items)||data.context?.role!==state.context?.role)throw error||new Error('Hidden vehicles could not be loaded.');
      state.hiddenItems=scopeRows(data.items.map(applyConfirmedVisibility),'','hidden');populateSalespeople();populateFilters();message('');
    }catch(e){
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId&&request===state.hiddenRequest){
        state.hiddenItems=[];message(e.message||'Hidden vehicles could not be loaded. Refresh to retry.');
      }
    }finally{if(generation===state.generation&&request===state.hiddenRequest){state.hiddenBusy=false;render();}}
  }
  async function setVehicleVisibility(id,hidden){
    const row=scopeRows(hidden?state.items:state.hiddenItems,state.filters.salesperson,hidden?'visible':'hidden').find(r=>r.tracking_id===id);
    if(!row||row.identity_conflict||state.visibilitySaving.has(id)||state.saving.has(id)||!['administrator','salesperson'].includes(state.context?.role))return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,version=row.sales_visibility_version||0;
    state.visibilitySaving.add(id);message('');$('sales-visibility-status').textContent=hidden?'Hiding vehicle…':'Showing vehicle…';render();
    try{
      const {data,error}=await root.PDC_SUPABASE.rpc('set_broome_sales_vehicle_visibility',{p_tracking_id:id,p_hidden:hidden,p_expected_version:version});
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      if(error||!data||data.tracking_id!==id||data.sales_hidden!==hidden||data.sales_visibility_version!==version+1)
        throw error||new Error('The visibility change could not be confirmed. Refresh before trying again.');
      state.visibilityConfirmed.set(id,{hidden,version:data.sales_visibility_version});
      if(hidden){
        state.items=state.items.filter(r=>r.tracking_id!==id);state.selected.delete(id);
        if(state.detailId===id){state.detailId=null;$('sales-detail').close();$('sales-detail-content').innerHTML='';}
      }
      state.hiddenItems=state.hiddenItems.filter(r=>r.tracking_id!==id);populateFilters();render();
      $('sales-visibility-status').textContent=hidden?'Vehicle hidden from the sales planner. Use Hidden vehicles to show it again.':'Vehicle shown on the sales planner.';
      // A poll started before saving can return an older snapshot. Queue a fresh read.
      if(state.busy)state.refreshQueued=true;else refresh();
    }catch(e){
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){
        $('sales-visibility-status').textContent='Visibility was not changed. Refresh and try again.';message(e.message||'The visibility change could not be confirmed.');
      }
    }finally{if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){state.visibilitySaving.delete(id);render();}}
  }
  $('sales-hidden-toggle').addEventListener('click',()=>{
    state.showHidden=!state.showHidden;state.hiddenRequest++;state.hiddenItems=[];state.hiddenBusy=false;
    if(state.showHidden)loadHiddenVehicles();else{populateFilters();render();}
  });
  $('sales-refresh').addEventListener('click',refresh);
  for(const button of root.document.querySelectorAll?.('[data-sales-view]')||[])button.addEventListener('click',()=>showView(button.dataset.salesView));
  $('sales-view-labels').addEventListener('click',()=>showView('labels'));
  $('sales-print-labels').addEventListener('click',printLabels);
  $('sales-connect-printer').addEventListener('click',connectPrinter);
  $('sales-label-printer').addEventListener('change',event=>{const name=event.target.value;state.printerName=state.printers.includes(name)?name:'';try{if(state.printerName)root.localStorage?.setItem('broome-sales-qz-printer-v1',state.printerName);else root.localStorage?.removeItem('broome-sales-qz-printer-v1');}catch{}});
  $('sales-sidebar-toggle').addEventListener('click',()=>{
    const collapsed=$('app-shell').classList.toggle('sidebar-collapsed');
    $('sales-sidebar-toggle').textContent=collapsed?'›':'‹';
    $('sales-sidebar-toggle').setAttribute('aria-expanded',String(!collapsed));
    $('sales-sidebar-toggle').setAttribute('aria-label',collapsed?'Expand menu':'Collapse menu');
  });
  $('sales-show-all').addEventListener('click',()=>{state.filters.category='all';render();});
  $('sales-clear-filters').addEventListener('click',()=>{
    state.filters=defaultFilters();state.savedView='';$('sales-saved-view').value='';$('search').value='';$('salesperson-filter').value='';
    for(const id of ['sales-month-filter','sales-status-filter'])$(id).value='';populateFilters();render();
  });
  for(const [id,key] of [['sales-month-filter','month'],['sales-status-filter','status']])$(id).addEventListener('change',event=>{state.filters[key]=event.target.value;render();});
  $('search').addEventListener('input',event=>{
    state.filters.search=event.target.value;
    if(!root.setTimeout){render();return;}
    if(state.searchTimer!==null)root.clearTimeout?.(state.searchTimer);
    const generation=state.generation;
    state.searchTimer=root.setTimeout(()=>{state.searchTimer=null;if(generation===state.generation)render();},160);
  });
  $('salesperson-filter').addEventListener('change',event=>{state.filters.salesperson=event.target.value;state.selected.clear();populateFilters();render();});
  $('status-tabs').addEventListener('click',event=>{const button=event.target.closest('[data-category]');if(button){state.filters.category=button.dataset.category;render();}});
  function cycleOrderingControl(event){
    const control=event.target.closest?.('[data-ordering-id]')||event.target;
    if(!control.dataset?.orderingId)return false;
    if(!control.disabled)saveOrderingFlag(control.dataset.orderingId,control.dataset.orderingFlag,nextOrderingState(control.dataset.orderingStatus));
    return true;
  }
  $('vehicle-table').addEventListener('click',event=>{
    if(cycleOrderingControl(event))return;
    const sort=event.target.closest('[data-sort]'); if(sort){const key=sort.dataset.sort;state.filters.direction=state.filters.sort===key?-state.filters.direction:1;state.filters.sort=key;render();}
    const open=event.target.closest('[data-open]'); if(open)openDetail(open.dataset.open);
  });
  $('vehicle-table').addEventListener('change',event=>{
    if(emailAction(event.target))return;
    const orderingId=event.target.dataset.orderingId;
    if(orderingId){saveOrderingFlag(orderingId,event.target.dataset.orderingFlag,event.target.value);return;}
    const id=event.target.dataset.select;
    if(id&&scopeRows(state.items,state.filters.salesperson).some(r=>r.tracking_id===id)){if(event.target.checked)state.selected.add(id);else state.selected.delete(id);}
    if(!state.showHidden&&event.target.id==='sales-select-visible')for(const r of selectRows(state.items,state.filters)){if(event.target.checked)state.selected.add(r.tracking_id);else state.selected.delete(r.tracking_id);}
    render();
  });
  $('sales-pipeline').addEventListener('click',event=>{const open=event.target.closest('[data-open]');if(open)openDetail(open.dataset.open);});
  root.addEventListener('pdc-auth-ready',()=>{clear();refresh();});
  root.addEventListener('pdc-auth-locked',clear);
  root.document.addEventListener('visibilitychange',()=>{if(!root.document.hidden)refresh();});
  root.setInterval(()=>{if(!root.document.hidden)refresh();},30000);
  $('sales-detail').addEventListener('close',()=>{state.detailId=null;root.BROOME_SALES_BUILDS?.closeDetail();$('sales-detail-content').innerHTML='';});
  $('sales-mobile-vehicles').addEventListener('click',event=>{if(cycleOrderingControl(event))return;const open=event.target.closest('[data-open]');if(open)openDetail(open.dataset.open);});
  $('sales-mobile-vehicles').addEventListener('change',event=>{
    const t=event.target;if(emailAction(t))return;if(t.dataset.orderingId){saveOrderingFlag(t.dataset.orderingId,t.dataset.orderingFlag,t.value);return;}
    if(t.dataset.select&&scopeRows(state.items,state.filters.salesperson).some(r=>r.tracking_id===t.dataset.select)){if(t.checked)state.selected.add(t.dataset.select);else state.selected.delete(t.dataset.select);render();}
  });
  $('sales-saved-view').addEventListener('change',event=>{
    state.savedView=event.target.value;
    if(state.savedView.startsWith('preset:'))state.filters.quick=state.savedView.slice(7);
    else{const saved=(state.workspace?.views||[]).find(v=>v.id===state.savedView);state.filters={...defaultFilters(),...saved?.filters,salesperson:state.filters.salesperson};$('sales-view-name').value=saved?.name||'';}
    $('search').value=state.filters.search;
    for(const [id,key] of [['sales-month-filter','month'],['sales-status-filter','status'],['sales-jita-filter','jita']])$(id).value=state.filters[key]||'';
    populateFilters();render();
  });
  $('sales-save-view').addEventListener('click',saveView);
  root.BROOME_SALES_CRM?.init(moduleOptions());
  root.BROOME_SALES_BUILDS?.init({...moduleOptions(),getToken:()=>JSON.stringify([root.PDC_AUTH_CONTEXT?.userId,state.generation])});
  const columnWidths=root.BROOME_SALES_TOOLS?.initColumns($('vehicle-table'),$('sales-reset-widths'));
  root.BROOME_SALES_EMAIL?.init({getRows:()=>scopeRows(state.items,state.filters.salesperson),getToken:()=>JSON.stringify([root.PDC_AUTH_CONTEXT?.userId,state.generation,state.filters.salesperson])});
  root.BROOME_CUSTOMER_EMAILS?.init({...moduleOptions(),getToken:()=>JSON.stringify([root.PDC_AUTH_CONTEXT?.userId,state.generation])});
  root.BROOME_SALES_FINANCE?.init({...moduleOptions(),getToken:()=>JSON.stringify([root.PDC_AUTH_CONTEXT?.userId,state.generation]),onLoaded:projection=>{state.financeProjection=projection;if(state.workspace){state.workspace.finance=projection;root.BROOME_SALES_CRM?.setWorkspace(state.workspace);attachWorkspace();}}});
  if(root.PDC_AUTH_CONTEXT)refresh();
})(typeof window === 'object' ? window : globalThis);
