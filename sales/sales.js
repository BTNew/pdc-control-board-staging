(function (root) {
  'use strict';
  const categories = [
    ['all','All vehicles'],['unconfirmed','Unconfirmed'],['production','Production'],
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
      (!search || [row.stock,row.order,row.client,row.vehicle,row.vin,row.navision_notes,row.pmb_location]
        .some(value => String(value || '').toLowerCase().includes(search)))
    ).slice().sort((a,b) => {
      const aa = a[filters.sort], bb = b[filters.sort];
      if (aa == null || aa === '') return bb == null || bb === '' ? 0 : 1;
      if (bb == null || bb === '') return -1;
      return String(aa).localeCompare(String(bb),undefined,{numeric:true,sensitivity:'base'}) * filters.direction;
    });
  }
  const api = { category, flag, selectRows, escapeHtml };
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (!root.document) return;
  const $ = id => root.document.getElementById(id);
  const state = { items:[], context:null, generation:0, busy:false, accounts:null,
    filters:{category:'all',search:'',salesperson:'',sort:'stock',direction:1} };
  const columns = [
    ['salesperson_code','SP'],['stock','SN'],['production_month','P/Month'],['client','Client'],
    ['vehicle','Vehicle'],['tint','Tint'],['build_po','Build PO'],['build_complete','Build Complete'],
    ['tray_ordered','Tray Ordered'],['tray_complete','Tray Complete'],['toyota_status','Toyota Status'],
    ['kewdale_eta','Kewdale ETA'],['pmb_location','PMB Location'],['navision_notes','Navision Notes'],['jita','JITA']
  ];
  const flagKeys = new Set(['tint','build_po','build_complete','tray_ordered','tray_complete','jita']);
  function message(text) { $('sales-error').textContent=text; $('sales-error').hidden=!text; }
  function dateLabel(value) {
    if (!value) return 'Not recorded';
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? String(value) :
      date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'});
  }
  function clear() {
    state.generation++; state.busy=false; state.items=[]; state.context=null; state.accounts=null;
    $('vehicle-table').innerHTML=''; $('status-tabs').innerHTML=''; $('sales-summary').innerHTML='';
    $('sales-sync').textContent=''; $('sales-scope').textContent=''; $('sales-accounts').hidden=true;
    $('sales-account').innerHTML=''; $('sales-person').innerHTML=''; $('sales-account-message').textContent='';
    $('salesperson-filter').innerHTML=''; $('salesperson-filter-label').hidden=true;
    $('sales-detail').close(); $('sales-detail-content').innerHTML=''; message('');
    $('sales-refresh').disabled=false;
    state.filters={category:'all',search:'',salesperson:'',sort:'stock',direction:1};
    $('search').value='';
  }
  function render() {
    const rows=selectRows(state.items,state.filters);
    $('status-tabs').innerHTML=categories.map(([key,label]) => '<button type="button" data-category="'+key+
      '" class="'+(state.filters.category===key?'active':'')+'" aria-pressed="'+(state.filters.category===key)+'">'+
      label+' <span>'+state.items.filter(r=>key==='all'||category(r)===key).length+'</span></button>').join('');
    $('sales-summary').innerHTML='<span>'+rows.length+' vehicles shown</span><span>'+
      state.items.filter(r=>r.canonical_vehicle_id).length+' linked to PMB</span>';
    $('vehicle-table').innerHTML='<thead><tr>'+columns.map(([key,label])=>'<th aria-sort="'+
      (state.filters.sort===key?(state.filters.direction===1?'ascending':'descending'):'none')+
      '"><button type="button" data-sort="'+key+'">'+label+(state.filters.sort===key?(state.filters.direction===1?' ↑':' ↓'):'')+
      '</button></th>').join('')+'</tr></thead><tbody>'+
      (rows.length?rows.map(row=>'<tr>'+columns.map(([key])=>{
        const val=row[key];
        if (flagKeys.has(key)) { const f=flag(val); return '<td class="sales-flag '+f+'" title="'+
          (f==='yes'?'Recorded yes':f==='no'?'Recorded no':'Not recorded')+'">'+(f==='yes'?'✓':f==='no'?'×':'—')+'</td>'; }
        if (key==='stock') return '<td><button type="button" class="stock-button" data-open="'+escapeHtml(row.tracking_id)+'">'+
          escapeHtml(val||row.order||'Unconfirmed')+'</button></td>';
        if (key==='toyota_status') return '<td><span class="status-pill '+category(row)+'">'+escapeHtml(val||'Not recorded')+'</span></td>';
        if (key==='pmb_location') return '<td>'+escapeHtml(val||(row.canonical_vehicle_id?'Not recorded':'Not linked to PMB'))+
          (row.pmb_stage?'<div class="subtle">'+escapeHtml(row.pmb_stage)+'</div>':'')+'</td>';
        return '<td>'+escapeHtml(val||'—')+'</td>';
      }).join('')+'</tr>').join(''):'<tr><td colspan="15"><div class="empty-state">No vehicles match this view.</div></td></tr>')+'</tbody>';
  }
  function openDetail(id) {
    const r=state.items.find(row=>row.tracking_id===id); if (!r) return;
    const details=[
      ['Stock',r.stock],['Toyota order',r.order],['Division',r.division],['Salesperson',r.salesperson_name],
      ['Vehicle',r.vehicle],['Colour',r.colour],['Suffix',r.suffix],['Trim',r.trim],['VIN',r.vin],
      ['Production month',r.production_month],['Toyota status',r.toyota_status],['Kewdale ETA',r.kewdale_eta],
      ['PMB location',r.pmb_location],['PMB stage',r.pmb_stage],['Workshop progress',r.workshop_status],
      ['Key number',r.key_number],['Job card',r.job_card],['Sales type',r.sales_type],
      ['Customer category',r.customer_category],['QC completed',r.qc_completed_at?dateLabel(r.qc_completed_at):null],
      ['RFT transferred',r.rft_transferred_at?dateLabel(r.rft_transferred_at):null],
      ['Tracking identifier',r.tracking_id],['PMB permanent identifier',r.permanent_vehicle_id],
      ['Navision updated',dateLabel(r.navision_updated_at)],['PMB updated',r.pmb_updated_at?dateLabel(r.pmb_updated_at):null]
    ];
    $('sales-detail-content').innerHTML='<div class="panel-header"><div><h2>'+escapeHtml(r.stock||r.order||'Vehicle')+
      '</h2><p>'+escapeHtml(r.client)+'</p></div><button type="button" class="small-button" id="sales-detail-close">Close</button></div>'+
      '<dl class="detail-grid">'+details.map(([label,val])=>'<div><dt>'+escapeHtml(label)+'</dt><dd>'+escapeHtml(val||'Not recorded')+
      '</dd></div>').join('')+'</dl><h3>Navision notes</h3><p class="detail-notes">'+escapeHtml(r.navision_notes||'No notes recorded')+'</p>';
    $('sales-detail-close').addEventListener('click',()=>{ $('sales-detail').close(); $('sales-detail-content').innerHTML=''; });
    $('sales-detail').showModal();
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
      state.items=data.items; state.context=data.context; message('');
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
  $('search').addEventListener('input',event=>{state.filters.search=event.target.value;render();});
  $('salesperson-filter').addEventListener('change',event=>{state.filters.salesperson=event.target.value;render();});
  $('status-tabs').addEventListener('click',event=>{const button=event.target.closest('[data-category]');if(button){state.filters.category=button.dataset.category;render();}});
  $('vehicle-table').addEventListener('click',event=>{
    const sort=event.target.closest('[data-sort]'); if(sort){const key=sort.dataset.sort;state.filters.direction=state.filters.sort===key?-state.filters.direction:1;state.filters.sort=key;render();}
    const open=event.target.closest('[data-open]'); if(open)openDetail(open.dataset.open);
  });
  root.addEventListener('pdc-auth-ready',()=>{clear();refresh();});
  root.addEventListener('pdc-auth-locked',clear);
  root.document.addEventListener('visibilitychange',()=>{if(!root.document.hidden)refresh();});
  root.setInterval(()=>{if(!root.document.hidden)refresh();},30000);
  $('sales-detail').addEventListener('close',()=>{$('sales-detail-content').innerHTML='';});
  if(root.PDC_AUTH_CONTEXT)refresh();
})(typeof window === 'object' ? window : globalThis);
