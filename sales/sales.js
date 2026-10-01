(function (root) {
  'use strict';
  const categories = [
    ['all','All vehicles'],['unconfirmed','Awaiting stock'],['production','Production'],
    ['transit','In Transit'],['yardhold','YH / Yard Hold'],['hold','Hold/Waiting'],
    ['released','Released'],['dealer','Dealer']
  ];
  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  }
  function category(row) {
    if (!row.stock || /^(?:0|TBA)$/i.test(row.stock)) return 'unconfirmed';
    const status = String(row.toyota_status || '').toLowerCase();
    if (String(row.location_status || '').toUpperCase() === 'YH' || status.includes('yard hold')) return 'yardhold';
    if (/planned for production|line off|final inspection|o\/s wharf|eastern states/.test(status)) return 'production';
    if (/consignment|body builder|ready for despatch|ready for dispatch|despatch to|dispatch to/.test(status)) return 'released';
    if (/waiting pd|waiting for wholesale|delayed|hold|waiting/.test(status)) return 'hold';
    if (/ready for shipment|in transit|wharf|shipment/.test(status)) return 'transit';
    return 'dealer';
  }
  function flag(value) {
    if (value === true || /^(?:yes|true|1)$/i.test(String(value))) return 'yes';
    if (value === false || /^(?:no|false|0)$/i.test(String(value))) return 'no';
    return 'unknown';
  }
  function selectRows(rows, filters) {
    const search = String(filters.search || '').toLowerCase();
    return rows.filter(row =>
      (filters.category === 'all' || category(row) === filters.category) &&
      (!filters.salesperson || row.salesperson_code === filters.salesperson) &&
      (!filters.month || row.production_month === filters.month) &&
      (!filters.status || row.toyota_status === filters.status) &&
      (!filters.jita || flag(row.jita) === filters.jita) &&
      (!search || [row.stock,row.order,row.client,row.vehicle,row.vin,row.navision_notes,row.pmb_location]
        .some(value => String(value || '').toLowerCase().includes(search)))
    ).slice().sort((a,b) => {
      const aa = a[filters.sort], bb = b[filters.sort];
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
  const api = { category, flag, selectRows, escapeHtml, pmbSummary, partsStatus, bookingStatus };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (!root.document) return;
  const $ = id => root.document.getElementById(id);
  const defaultFilters=()=>({category:'all',search:'',salesperson:'',month:'',status:'',jita:'',sort:'stock',direction:1});
  const state = { items:[], context:null, generation:0, busy:false, accounts:null,view:'dashboard',selected:new Set(),detailId:null,reviewedOrders:null,importBusy:false,orderRevision:0,saving:new Map(),
    filters:defaultFilters() };
  const columns = [
    ['salesperson_code','SP'],['stock','SN'],['production_month','P/Month'],['client','Client'],
    ['vehicle','Vehicle'],['tint','Tint'],['build_po','Build PO'],['build_complete','Build Complete'],
    ['tray_ordered','Tray Ordered'],['tray_complete','Tray Complete'],['toyota_status','Toyota Status'],
    ['kewdale_eta','Kewdale ETA'],['pmb_location','PMB Status'],['navision_notes','Navision Notes'],['jita','JITA']
  ];
  const flagKeys = new Set(['tint','build_po','build_complete','tray_ordered','tray_complete','jita']);
  const orderingKeys = new Set(['tint','build_po','build_complete','tray_ordered','tray_complete']);
  function message(text) { $('sales-error').textContent=text; $('sales-error').hidden=!text; }
  function dateLabel(value) {
    if (!value) return 'Not recorded';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? String(value) :
      date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'});
  }
  function clear() {
    state.generation++; state.busy=false; state.items=[]; state.context=null; state.accounts=null;
    state.selected.clear();
    state.saving.clear();$('sales-checklist-status').textContent='';
    state.detailId=null;state.reviewedOrders=null;state.importBusy=false;state.orderRevision++;
    $('sales-order-intake').hidden=true;$('sales-order-text').value='';$('sales-order-file').value='';
    $('sales-order-message').textContent='';$('sales-order-apply').disabled=true;$('sales-order-preview').disabled=false;
    $('vehicle-table').innerHTML=''; $('status-tabs').innerHTML=''; $('sales-summary').innerHTML='';
    $('sales-pipeline').innerHTML=''; $('sales-labels').innerHTML=''; $('sales-print-labels').disabled=true;
    $('sales-data-date').textContent=''; $('sales-data-count').textContent='';
    $('sales-sync').textContent=''; $('sales-scope').textContent=''; $('sales-accounts').hidden=true;
    $('sales-account').innerHTML=''; $('sales-person').innerHTML=''; $('sales-account-message').textContent='';
    $('salesperson-filter').innerHTML=''; $('salesperson-filter-label').hidden=true;
    $('sales-detail').close(); $('sales-detail-content').innerHTML=''; message('');
    $('sales-refresh').disabled=false;
    state.filters=defaultFilters();
    $('search').value='';
    for(const id of ['sales-month-filter','sales-status-filter'])$(id).innerHTML='';
    $('sales-jita-filter').value='';
  }
  const categoryDescriptions={all:'Shows every authorised vehicle',unconfirmed:'Rows without a stock number',production:'Production and early transit statuses',transit:'Shipment, WA transit and wharf',yardhold:'Location status YH or yard hold',hold:'Delayed, wholesale, PD and wharf waits',released:'Body builder and TWA despatch',dealer:'Remaining source statuses'};
  function showView(view) {
    if(!['dashboard','pipeline','labels','finance'].includes(view))return;
    state.view=view;
    for(const name of ['dashboard','pipeline','labels','finance'])$('sales-'+name+'-view').hidden=name!==view;
    $('sales-page-title').textContent={dashboard:'Dashboard',pipeline:'Pipeline',labels:'Labels',finance:'Finance'}[view];
    for(const button of root.document.querySelectorAll?.('[data-sales-view]')||[]) {
      button.classList.toggle('active',button.dataset.salesView===view);
      if(button.dataset.salesView===view)button.setAttribute('aria-current','page');else button.removeAttribute('aria-current');
    }
    if(view!=='finance')render();
  }
  function populateFilters() {
    for(const [id,key,label] of [['sales-month-filter','production_month','All months'],['sales-status-filter','toyota_status','All statuses']]) {
      const value=$(id).value;
      const options=[...new Set(state.items.map(r=>r[key]).filter(Boolean))].sort((a,b)=>a.localeCompare(b,undefined,{numeric:true}));
      $(id).innerHTML='<option value="">'+label+'</option>'+options.map(x=>'<option value="'+escapeHtml(x)+'">'+escapeHtml(x)+'</option>').join('');
      $(id).value=options.includes(value)?value:'';
      state.filters[key==='production_month'?'month':'status']=$(id).value;
    }
  }
  function renderSecondaryViews() {
    $('sales-pipeline').innerHTML=categories.filter(([key])=>key!=='all').map(([key,label])=>{
      const rows=state.items.filter(r=>category(r)===key);
      return '<section class="pipeline-column"><h2>'+label+' <span>'+rows.length+'</span></h2>'+
        (rows.length?rows.map(r=>'<button class="pipeline-card" type="button" data-open="'+escapeHtml(r.tracking_id)+'"><strong>'+escapeHtml(r.stock||r.order||'Unconfirmed')+'</strong><p>'+escapeHtml(r.client||'Customer not recorded')+'</p><p>'+escapeHtml(r.vehicle||'Vehicle not recorded')+'</p><span class="status-pill '+key+'">'+escapeHtml(r.toyota_status||'Not recorded')+'</span>'+(r.pmb_location?'<p>PMB: '+escapeHtml(r.pmb_location)+'</p>':'')+'</button>').join(''):'<div class="empty-state">No vehicles</div>')+'</section>';
    }).join('');
    const labels=state.items.filter(r=>state.selected.has(r.tracking_id));
    $('sales-labels').innerHTML=labels.length?labels.map(r=>'<article class="vehicle-label"><small>Broome Toyota · '+escapeHtml(r.salesperson_code||'')+'</small><p><strong>'+escapeHtml(r.stock||r.order||'Unconfirmed')+'</strong></p><p>'+escapeHtml(r.client||'Customer not recorded')+'</p><p>'+escapeHtml(r.vehicle||'Vehicle not recorded')+'</p><small>Toyota order '+escapeHtml(r.order||'Not recorded')+'</small></article>').join(''):'<div class="empty-state">Select vehicles on the Dashboard, then choose View labels.</div>';
    $('sales-print-labels').disabled=!labels.length;
  }
  function render() {
    const rows=selectRows(state.items,state.filters);
    $('status-tabs').innerHTML=categories.map(([key,label]) => '<button type="button" data-category="'+key+
      '" class="status-card '+key+(state.filters.category===key?' active':'')+'" aria-pressed="'+(state.filters.category===key)+'">'+
      '<span>'+label+'</span><strong>'+state.items.filter(r=>key==='all'||category(r)===key).length+'</strong><small>'+categoryDescriptions[key]+'</small></button>').join('');
    $('sales-summary').innerHTML='<span>'+rows.length+' vehicles shown</span><span>'+
      state.items.filter(r=>r.canonical_vehicle_id).length+' linked to PMB</span><span>'+state.selected.size+' selected for labels</span>';
    $('vehicle-table').innerHTML='<thead><tr>'+columns.map(([key,label])=>'<th aria-sort="'+
      (state.filters.sort===key?(state.filters.direction===1?'ascending':'descending'):'none')+
      '">'+(key==='salesperson_code'?'<input type="checkbox" id="sales-select-visible" aria-label="Select visible vehicles for labels" '+(rows.length&&rows.every(r=>state.selected.has(r.tracking_id))?'checked':'')+'>':'')+'<button type="button" data-sort="'+key+'">'+label+(state.filters.sort===key?(state.filters.direction===1?' ↑':' ↓'):'')+
      '</button></th>').join('')+'<th>Action</th></tr></thead><tbody>'+
      (rows.length?rows.map(row=>'<tr class="'+(state.selected.has(row.tracking_id)?'selected':'')+'">'+columns.map(([key])=>{
        const val=row[key];
        if (key==='salesperson_code')return '<td><input type="checkbox" data-select="'+escapeHtml(row.tracking_id)+'" aria-label="Select '+escapeHtml(row.stock||row.order||'vehicle')+' for labels" '+(state.selected.has(row.tracking_id)?'checked':'')+'>'+escapeHtml(val||'—')+'</td>';
        if (key==='production_month')return '<td><span class="month-pill">'+escapeHtml(val||'—')+'</span></td>';
        if (orderingKeys.has(key)) {
          const pending=state.saving.get(row.tracking_id),checked=pending?.key===key?pending.checked:val===true;
          const label=columns.find(([name])=>name===key)[1]+' for '+(row.stock||'Toyota order '+(row.order||'not recorded'));
          return '<td class="sales-flag"><input class="ordering-checkbox" type="checkbox" data-ordering-id="'+escapeHtml(row.tracking_id)+'" data-ordering-flag="'+key+'" aria-label="'+escapeHtml(label)+'" '+(checked?'checked ':'')+(pending||row.identity_conflict?'disabled ':'')+'title="Sales ordering checklist"></td>';
        }
        if (flagKeys.has(key)) { const f=flag(val); return '<td class="sales-flag '+(key==='jita'?'jita':'')+'"><span class="flag-indicator '+f+'" role="img" aria-label="'+
          (f==='yes'?'Recorded yes':f==='no'?'Recorded no':'Not recorded')+'">'+(f==='yes'?'✓':f==='no'?'×':'—')+'</span></td>'; }
        if (key==='stock') return '<td><button type="button" class="stock-button" data-open="'+escapeHtml(row.tracking_id)+'">'+
          escapeHtml(val||row.order||'Unconfirmed')+'</button><span class="subtle">Toyota '+escapeHtml(row.order||'Not recorded')+'</span>'+(!val?'<span class="subtle">Awaiting stock number</span>':'')+(row.source_current===false?'<span class="source-warning">Not in latest PDC import</span>':'')+(row.identity_conflict?'<span class="source-warning">Order link needs review</span>':'')+'</td>';
        if (key==='toyota_status') return '<td><span class="status-pill '+category(row)+'" title="'+escapeHtml(val||'Not recorded')+'">'+escapeHtml(val||'Not recorded')+'</span></td>';
        if (key==='pmb_location') {const summary=pmbSummary(row);return '<td class="pmb-status-cell"><strong>'+escapeHtml(summary.status)+'</strong><div class="subtle">'+escapeHtml(summary.location)+'</div>'+
          (summary.bookings[0]?.scheduled_start_at?'<div class="subtle">Booked '+escapeHtml(dateLabel(summary.bookings[0].scheduled_start_at))+'</div>':'')+'</td>';}
        return '<td class="'+(key==='navision_notes'?'notes-cell':'')+'" title="'+escapeHtml(val||'')+'">'+escapeHtml(val||'—')+'</td>';
      }).join('')+'<td><button type="button" class="view-button" data-open="'+escapeHtml(row.tracking_id)+'">View details</button></td></tr>').join(''):'<tr><td colspan="16"><div class="empty-state">No vehicles match this view.</div></td></tr>')+'</tbody>';
    renderSecondaryViews();
  }
  function openDetail(id) {
    const r=state.items.find(row=>row.tracking_id===id); if (!r) return;
    state.detailId=id;
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
    $('sales-detail-content').innerHTML='<div class="panel-header"><div><h2>'+escapeHtml(r.stock||r.order||'Vehicle')+
      '</h2><p>'+escapeHtml(r.client)+'</p></div><button type="button" class="small-button" id="sales-detail-close">Close</button></div>'+
      workshopHtml(r)+'<h3>Vehicle and delivery details</h3><dl class="detail-grid">'+details.map(([label,val])=>'<div><dt>'+escapeHtml(label)+'</dt><dd>'+escapeHtml(val||'Not recorded')+
      '</dd></div>').join('')+'</dl><h3>Navision notes</h3><p class="detail-notes">'+escapeHtml(r.navision_notes||'No notes recorded')+'</p>';
    $('sales-detail-close').addEventListener('click',()=>{ state.detailId=null;$('sales-detail').close(); $('sales-detail-content').innerHTML=''; });
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
  async function saveOrderingFlag(id,key,checked) {
    const row=state.items.find(r=>r.tracking_id===id);
    if(!row||row.identity_conflict||!orderingKeys.has(key)||state.saving.has(id)||!['salesperson','administrator'].includes(state.context?.role))return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId;
    const label=columns.find(([name])=>name===key)[1];
    state.saving.set(id,{key,checked});message('');$('sales-checklist-status').textContent='Saving '+label+'…';render();
    try{
      const {data,error}=await root.PDC_SUPABASE.rpc('set_broome_sales_ordering_flag',{
        p_tracking_id:id,p_flag:key,p_checked:checked,p_expected_version:row.ordering_version||0
      });
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      if(error||!data||data.tracking_id!==id)throw error||new Error('The ordering tick could not be saved.');
      const current=state.items.find(r=>r.tracking_id===id);
      if(current&&(data.ordering_version||0)>=(current.ordering_version||0)){
        for(const name of orderingKeys)current[name]=data[name]===true;
        current.ordering_version=data.ordering_version;current.ordering_updated_at=data.ordering_updated_at;
      }
      $('sales-checklist-status').textContent=label+' saved for '+(row.stock||'Toyota order '+row.order)+'.';
    }catch(e){
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){
        state.saving.delete(id);render();$('sales-checklist-status').textContent='Tick was not saved. Refresh and try again.';
        message(e.message||'The ordering tick could not be saved.');
      }
    }finally{
      if(generation===state.generation&&principal===root.PDC_AUTH_CONTEXT?.userId){state.saving.delete(id);render();}
    }
  }
  function invalidateOrderReview(){state.orderRevision++;state.reviewedOrders=null;$('sales-order-apply').disabled=true;$('sales-order-message').textContent='';}
  async function importOrders(apply) {
    if(state.context?.role!=='administrator'||state.importBusy)return;
    const generation=state.generation,principal=root.PDC_AUTH_CONTEXT?.userId,revision=state.orderRevision;
    state.importBusy=true;$('sales-order-preview').disabled=true;$('sales-order-apply').disabled=true;
    try{
      const rows=apply?state.reviewedOrders:root.BROOME_NAVISION_ORDERS.parse($('sales-order-text').value);
      if(!rows)throw new Error('Review the export before importing.');
      const {data,error}=await root.PDC_SUPABASE.rpc('import_broome_sales_orders',{p_rows:rows,p_apply:apply});
      if(generation!==state.generation||principal!==root.PDC_AUTH_CONTEXT?.userId)return;
      if(error)throw error;
      if(!apply&&revision!==state.orderRevision)return;
      $('sales-order-message').textContent=(apply?'Imported':'Reviewed')+' '+data.accepted+' orders · '+data.without_stock+' awaiting stock · '+data.skipped_unsold+' unsold rows without stock skipped.';
      state.reviewedOrders=apply?null:rows;
      if(apply){$('sales-order-text').value='';$('sales-order-file').value='';await refresh();}
    }catch(e){if(generation===state.generation){state.reviewedOrders=null;$('sales-order-message').textContent=e.message||'Orders could not be imported.';}}
    finally{if(generation===state.generation){state.importBusy=false;$('sales-order-preview').disabled=false;$('sales-order-apply').disabled=!state.reviewedOrders;}}
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
      state.items=data.items.map(r=>{
        const old=previous.get(r.tracking_id);
        if(old&&(old.ordering_version||0)>(r.ordering_version||0)){
          for(const name of orderingKeys)r[name]=old[name];
          r.ordering_version=old.ordering_version;r.ordering_updated_at=old.ordering_updated_at;
        }
        return r;
      }); state.context=data.context; message('');
      $('sales-order-intake').hidden=data.context.role!=='administrator';
      if(state.detailId){if(data.items.some(r=>r.tracking_id===state.detailId))openDetail(state.detailId);else{state.detailId=null;$('sales-detail').close();$('sales-detail-content').innerHTML='';}}
      const currentIds=new Set(data.items.map(r=>r.tracking_id));
      for(const id of state.selected)if(!currentIds.has(id))state.selected.delete(id);
      populateFilters();
      $('sales-data-date').textContent=dateLabel(data.navision_updated_at);
      $('sales-data-count').textContent=data.items.length+' vehicles · Navision';
      $('sales-scope').textContent=data.context.role==='administrator'?'Broome Toyota · Administrator view':
        data.context.display_name+' · My vehicles · Broome Toyota';
      $('sales-sync').textContent='Navision updated '+dateLabel(data.navision_updated_at)+' · Checked '+dateLabel(data.checked_at)+' (Perth)';
      $('salesperson-filter-label').hidden=data.context.role!=='administrator';
      if (data.context.role==='administrator') {
        const selected=state.filters.salesperson;
        const people=[...new Set(data.items.map(r=>r.salesperson_code).filter(Boolean))].sort();
        $('salesperson-filter').innerHTML='<option value="">All salespeople</option>'+people.map(code=>'<option value="'+
          escapeHtml(code)+'">'+escapeHtml(code)+'</option>').join('');
        $('salesperson-filter').value=selected; $('sales-accounts').hidden=false;
      } else { $('sales-accounts').hidden=true; state.accounts=null; $('sales-account').innerHTML=''; $('sales-person').innerHTML=''; }
      render();
    } catch (error) {
      if (generation!==state.generation || principal!==root.PDC_AUTH_CONTEXT?.userId) return;
      clear(); message(error.message||'Unable to refresh vehicles. Try again.');
    } finally { if (generation===state.generation) {state.busy=false; $('sales-refresh').disabled=false;} }
  }
  async function loadAccounts() {
    if (state.context?.role!=='administrator') return;
    const generation=state.generation;
    const {data,error}=await root.PDC_SUPABASE.rpc('get_broome_sales_accounts');
    if (generation!==state.generation || root.PDC_AUTH_CONTEXT?.role!=='administrator') return;
    if (error) { $('sales-account-message').textContent=error.message; return; }
    state.accounts=data;
    $('sales-account').innerHTML='<option value="">Choose a registration</option>'+data.accounts.map(a=>'<option value="'+
      escapeHtml(a.id)+'">'+escapeHtml(a.name+' · '+a.email+' · '+a.status)+'</option>').join('');
    $('sales-person').innerHTML='<option value="">Choose a salesperson</option>'+data.salespeople.map(s=>'<option value="'+
      escapeHtml(s.id)+'">'+escapeHtml(s.code+' · '+s.name)+'</option>').join('');
    $('sales-account-message').textContent=data.accounts.length?'':'No pending registrations or salesperson accounts.';
  }
  $('sales-account').addEventListener('change',()=>{
    const a=state.accounts?.accounts.find(a=>a.id===$('sales-account').value);
    $('sales-person').value=a?.salesperson_id||'';
  });
  $('sales-access-form').addEventListener('submit',async event=>{
    event.preventDefault(); if (state.context?.role!=='administrator') return;
    const account=$('sales-account').value, salesperson=$('sales-person').value;
    if (!account||!salesperson) return;
    const generation=state.generation; $('sales-grant').disabled=true;
    try {
      const {error}=await root.PDC_SUPABASE.rpc('assign_broome_sales_access',{p_user_role_id:account,p_salesperson_id:salesperson});
      if (generation!==state.generation) return;
      if (error) throw error;
      await loadAccounts(); if (generation!==state.generation) return;
      $('sales-account-message').textContent='Salesperson access saved. The account can now sign in to Broome Toyota.';
    } catch(error) { if (generation===state.generation) $('sales-account-message').textContent=error.message; }
    finally { $('sales-grant').disabled=false; }
  });
  $('sales-load-accounts').addEventListener('click',()=>loadAccounts().catch(e=>{$('sales-account-message').textContent=e.message;}));
  $('sales-refresh').addEventListener('click',refresh);
  $('sales-order-preview').addEventListener('click',()=>importOrders(false));
  $('sales-order-apply').addEventListener('click',()=>importOrders(true));
  $('sales-order-text').addEventListener('input',invalidateOrderReview);
  $('sales-order-file').addEventListener('change',async event=>{
    invalidateOrderReview();const file=event.target.files?.[0],generation=state.generation;
    if(!file)return;
    if(file.size>8000000){$('sales-order-message').textContent='Use an export smaller than 8 MB.';return;}
    try{const text=await file.text();if(generation===state.generation&&state.context?.role==='administrator')$('sales-order-text').value=text;}
    catch(e){if(generation===state.generation)$('sales-order-message').textContent='The export could not be read.';}
  });
  for(const button of root.document.querySelectorAll?.('[data-sales-view]')||[])button.addEventListener('click',()=>showView(button.dataset.salesView));
  $('sales-view-labels').addEventListener('click',()=>showView('labels'));
  $('sales-print-labels').addEventListener('click',()=>{if(state.view==='labels'&&state.selected.size)root.print();});
  $('sales-sidebar-toggle').addEventListener('click',()=>{
    const collapsed=$('app-shell').classList.toggle('sidebar-collapsed');
    $('sales-sidebar-toggle').textContent=collapsed?'›':'‹';
    $('sales-sidebar-toggle').setAttribute('aria-expanded',String(!collapsed));
    $('sales-sidebar-toggle').setAttribute('aria-label',collapsed?'Expand menu':'Collapse menu');
  });
  $('sales-show-all').addEventListener('click',()=>{state.filters.category='all';render();});
  $('sales-clear-filters').addEventListener('click',()=>{
    state.filters=defaultFilters();$('search').value='';$('salesperson-filter').value='';
    for(const id of ['sales-month-filter','sales-status-filter','sales-jita-filter'])$(id).value='';render();
  });
  for(const [id,key] of [['sales-month-filter','month'],['sales-status-filter','status'],['sales-jita-filter','jita']])$(id).addEventListener('change',event=>{state.filters[key]=event.target.value;render();});
  $('search').addEventListener('input',event=>{state.filters.search=event.target.value;render();});
  $('salesperson-filter').addEventListener('change',event=>{state.filters.salesperson=event.target.value;render();});
  $('status-tabs').addEventListener('click',event=>{const button=event.target.closest('[data-category]');if(button){state.filters.category=button.dataset.category;render();}});
  $('vehicle-table').addEventListener('click',event=>{
    const sort=event.target.closest('[data-sort]'); if(sort){const key=sort.dataset.sort;state.filters.direction=state.filters.sort===key?-state.filters.direction:1;state.filters.sort=key;render();}
    const open=event.target.closest('[data-open]'); if(open)openDetail(open.dataset.open);
  });
  $('vehicle-table').addEventListener('change',event=>{
    const orderingId=event.target.dataset.orderingId;
    if(orderingId){saveOrderingFlag(orderingId,event.target.dataset.orderingFlag,event.target.checked);return;}
    const id=event.target.dataset.select;
    if(id&&state.items.some(r=>r.tracking_id===id)){if(event.target.checked)state.selected.add(id);else state.selected.delete(id);}
    if(event.target.id==='sales-select-visible')for(const r of selectRows(state.items,state.filters)){if(event.target.checked)state.selected.add(r.tracking_id);else state.selected.delete(r.tracking_id);}
    render();
  });
  $('sales-pipeline').addEventListener('click',event=>{const open=event.target.closest('[data-open]');if(open)openDetail(open.dataset.open);});
  root.addEventListener('pdc-auth-ready',()=>{clear();refresh();});
  root.addEventListener('pdc-auth-locked',clear);
  root.document.addEventListener('visibilitychange',()=>{if(!root.document.hidden)refresh();});
  root.setInterval(()=>{if(!root.document.hidden&&state.view!=='finance')refresh();},30000);
  $('sales-detail').addEventListener('close',()=>{state.detailId=null;$('sales-detail-content').innerHTML='';});
  if(root.PDC_AUTH_CONTEXT)refresh();
})(typeof window === 'object' ? window : globalThis);
