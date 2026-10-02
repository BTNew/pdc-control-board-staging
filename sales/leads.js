(function (root) {
  'use strict';
  const stages = Object.freeze({enquiry:'Enquiry',testdrive:'Test drive',quote:'Quote',order:'Ordered',lost:'Lost'});
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const code = value => String(value || '').trim().toUpperCase();
  function scopeRows(rows, context, selected) {
    const owner = context?.role === 'administrator' ? code(selected) : code(context?.salesperson_code);
    if (!['administrator','salesperson'].includes(context?.role) || (context.role === 'salesperson' && !owner)) return [];
    return (Array.isArray(rows) ? rows : []).filter(r => r && (!owner || code(r.salesperson_code) === owner));
  }
  function validDate(value) {
    if (!value) return true;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(value + 'T00:00:00Z');
    return !Number.isNaN(date.getTime()) && date.toISOString().slice(0,10) === value && value >= '2000-01-01' && value <= '2100-12-31';
  }
  function validateLead(data, refs, people, context) {
    const limits = {customer_name:200,phone:60,email:254,vehicle_interest:200,next_action:200,notes:4000};
    const clean = {};
    for (const [key,max] of Object.entries(limits)) {
      clean[key] = String(data[key] || '').trim();
      if (clean[key].length > max) throw new Error('Please shorten ' + key.replace(/_/g,' ') + '.');
    }
    if (!clean.customer_name) throw new Error('Enter a customer name.');
    if (clean.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(clean.email)) throw new Error('Enter a valid email address.');
    if (!Object.prototype.hasOwnProperty.call(stages,data.stage)) throw new Error('Select a recognised lead stage.');
    clean.stage = data.stage;
    clean.next_contact_date = String(data.next_contact_date || '').trim();
    if (!validDate(clean.next_contact_date)) throw new Error('Enter a valid next contact date.');
    clean.last_contact_date = String(data.last_contact_date || '').trim();
    if (!validDate(clean.last_contact_date)) throw new Error('Enter a valid last contact date.');
    clean.salesperson_code = context?.role === 'administrator' ? code(data.salesperson_code) : code(context?.salesperson_code);
    if (!clean.salesperson_code || (context?.role === 'administrator' && !(people || []).some(p => code(p.code) === clean.salesperson_code))) {
      throw new Error('Select an active salesperson.');
    }
    const tracking = String(data.tracking_id || '').trim();
    if (tracking && (!uuid.test(tracking) || !(refs || []).some(r => r.tracking_id === tracking && code(r.salesperson_code) === clean.salesperson_code))) {
      throw new Error('Choose a current COSI order assigned to this salesperson.');
    }
    if (clean.stage === 'order' && !tracking) throw new Error('Choose the existing COSI order for this ordered lead.');
    return {data:clean,tracking_id:tracking || null};
  }
  const api = {stages,scopeRows,validateLead,escapeHtml:esc};
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.BROOME_SALES_LEADS = api;
  if (!root.document) return;

  let config, container, state = {workspace:null,generation:0,principal:'',scope:'',editing:null,busy:false,message:'',search:'',stage:''};
  const $ = id => root.document.getElementById('sales-leads-' + id);
  function context() { return state.workspace?.context || config?.getContext?.() || null; }
  function principal() {
    const auth = root.PDC_AUTH_CONTEXT;
    return auth ? [auth.userId || '',auth.role || '',context()?.salesperson_id || '',context()?.salesperson_code || ''].join('|') : '';
  }
  function selected() { return code(config?.getSalesperson?.()); }
  function allowed() {
    const ctx = context(), auth = root.PDC_AUTH_CONTEXT;
    return !!state.workspace && !!auth && ['administrator','salesperson'].includes(ctx?.role) && (!auth.role || auth.role === ctx.role);
  }
  function scopedLeads() { return allowed() ? scopeRows(state.workspace?.leads,context(),selected()) : []; }
  function refs() { return allowed() ? scopeRows(state.workspace?.order_refs,context(),selected()) : []; }
  function people() { return Array.isArray(state.workspace?.salespeople) ? state.workspace.salespeople : []; }
  function text(message) { state.message=message; if ($('message')) $('message').textContent=message; }
  function discardEditor() {
    state.generation++; state.busy=false; state.editing=null; state.message='';
    if ($('form')) { $('form').hidden=true; $('form').reset?.(); }
    for (const key of ['customer_name','phone','email','vehicle_interest','last_contact_date','next_contact_date','next_action','notes']) if ($(key)) $(key).value='';
    if ($('tracking_id')) $('tracking_id').innerHTML='';
    if ($('salesperson_code')) $('salesperson_code').innerHTML='';
    for(const key of ['customer_name','phone','email','vehicle_interest','stage','salesperson_code','tracking_id','last_contact_date','next_contact_date','next_action','notes','save','cancel']) if ($(key)) $(key).disabled=false;
  }
  function checkScope() {
    const key = principal(), scope = selected();
    if (key !== state.principal || scope !== state.scope) {
      discardEditor(); state.principal=key; state.scope=scope;
      if ($('list')) $('list').innerHTML='';
      if ($('count')) $('count').textContent='';
    }
    return allowed();
  }
  function orderOptions(owner, previous) {
    const options = refs().filter(r => code(r.salesperson_code) === code(owner));
    $('tracking_id').innerHTML='<option value="">No order linked</option>'+options.map(r=>'<option value="'+esc(r.tracking_id)+'">'+esc([r.stock?'Stock '+r.stock:'Order '+r.order,r.client,r.vehicle].filter(Boolean).join(' · '))+'</option>').join('');
    $('tracking_id').value=options.some(r=>r.tracking_id===previous)?previous:'';
  }
  function openEditor(id) {
    if (!checkScope() || state.busy) return;
    const row = id ? scopedLeads().find(r=>r.id===id) : null;
    if (id && !row) return;
    const version = row ? Number(row.version) : 0;
    if (!Number.isSafeInteger(version) || version < 0) { text('Refresh this lead before editing.'); return; }
    state.editing=row ? {...row} : {id:null,version:0};
    text(''); $('form').hidden=false; $('form-title').textContent=row?'Edit lead':'New lead';
    for (const key of ['customer_name','phone','email','vehicle_interest','last_contact_date','next_contact_date','next_action','notes']) $(key).value=String(row?.[key] || '');
    $('stage').value=row?.stage || 'enquiry';
    const ctx = context(), owner=code(row?.salesperson_code || selected() || ctx.salesperson_code);
    $('owner-label').hidden=ctx.role!=='administrator';
    $('salesperson_code').innerHTML='<option value="">Choose salesperson</option>'+people().map(p=>'<option value="'+esc(p.code)+'">'+esc(p.name || p.code)+' ('+esc(p.code)+')</option>').join('');
    $('salesperson_code').value=owner;
    orderOptions(owner,row?.tracking_id); $('save').disabled=false;
    $('customer_name').focus?.();
  }
  function setBusy(busy) {
    state.busy=busy;
    for(const key of ['customer_name','phone','email','vehicle_interest','stage','salesperson_code','tracking_id','last_contact_date','next_contact_date','next_action','notes','save','cancel']) if ($(key)) $(key).disabled=busy;
    $('new').disabled=busy || !allowed();
  }
  async function save(event) {
    event?.preventDefault?.();
    if (!checkScope() || !state.editing || state.busy) return;
    const values={};
    for(const key of ['customer_name','phone','email','vehicle_interest','stage','salesperson_code','tracking_id','last_contact_date','next_contact_date','next_action','notes']) values[key]=$(key).value;
    let clean;
    try { clean=validateLead(values,refs(),people(),context()); }
    catch(error) { text(error.message); return; }
    const current = state.editing, generation=state.generation, key=principal(), scope=selected();
    if (current.id && !scopedLeads().some(r=>r.id===current.id)) { discardEditor(); render(); return; }
    setBusy(true); text('Saving lead…');
    try {
      const result=await root.PDC_SUPABASE.rpc('save_broome_sales_crm',{p_kind:'lead',p_id:current.id || null,p_tracking_id:clean.tracking_id,p_data:clean.data,p_expected_version:current.version});
      if (generation!==state.generation || key!==principal() || scope!==selected() || !allowed()) return;
      if(result.error) throw new Error(result.error.message || 'The lead could not be saved.');
      const record=result.data?.record;
      if(!record?.id || !uuid.test(record.id) || !Number.isSafeInteger(record.version) || record.version <= current.version || code(record.salesperson_code)!==clean.data.salesperson_code) throw new Error('The save could not be confirmed. Refresh before trying again.');
      const rows=state.workspace.leads || [];
      const newer=rows.find(r=>r.id===record.id && Number(r.version)>record.version);
      state.workspace.leads=rows.filter(r=>r.id!==record.id).concat(newer || record);
      discardEditor(); text('Lead saved.'); render(); config?.onChanged?.({kind:'lead',record});
    } catch(error) {
      if(generation===state.generation && key===principal() && scope===selected() && allowed()) text(error.message || 'The lead could not be saved.');
    } finally {
      if(generation===state.generation && key===principal() && scope===selected() && allowed()) { setBusy(false); render(); }
    }
  }
  function render() {
    if(!container) return;
    if (!checkScope()) { clear(); return; }
    const search=state.search.trim().toLowerCase();
    const all=scopedLeads(), rows=all.filter(r=>(!state.stage || r.stage===state.stage) && (!search || [r.customer_name,r.vehicle_interest,r.phone,r.email,r.next_action,r.notes].some(v=>String(v || '').toLowerCase().includes(search))));
    $('count').textContent=all.length+' lead'+(all.length===1?'':'s')+(selected()?' · '+selected():'');
    $('new').disabled=state.busy;
    const today=new Date().toLocaleDateString('en-CA',{timeZone:'Australia/Perth'});
    const markup=rows.length?rows.sort((a,b)=>String(a.next_contact_date || '9999').localeCompare(String(b.next_contact_date || '9999')) || String(b.updated_at || '').localeCompare(String(a.updated_at || ''))).map(r=>{
      const link=refs().find(o=>o.tracking_id===r.tracking_id);
      const overdue=r.next_contact_date && r.next_contact_date<today && !['lost','order'].includes(r.stage);
      return '<article class="sales-lead-card"><div class="sales-lead-card-heading"><h3>'+esc(r.customer_name)+'</h3><span class="sales-lead-stage">'+esc(stages[r.stage] || 'Unknown stage')+'</span></div><p>'+esc(r.vehicle_interest || 'Vehicle interest not recorded')+'</p><p class="sales-lead-contact">'+esc([r.phone,r.email].filter(Boolean).join(' · ') || 'Contact details not recorded')+'</p>'+(r.last_contact_date?'<p class="sales-lead-contact">Last contact '+esc(r.last_contact_date)+'</p>':'')+'<p class="sales-lead-next'+(overdue?' overdue':'')+'"><strong>'+esc(r.next_contact_date?'Next contact '+r.next_contact_date:'No next contact date')+'</strong>'+ (r.next_action?'<span>'+esc(r.next_action)+'</span>':'')+'</p>'+(r.notes?'<p class="sales-lead-notes">'+esc(r.notes)+'</p>':'')+'<div class="sales-lead-card-actions"><span>'+esc(r.salesperson_name || r.salesperson_code)+'</span>'+(link?'<button class="small-button" type="button" data-lead-open="'+esc(link.tracking_id)+'">'+esc(link.stock?'Stock '+link.stock:'Order '+link.order)+'</button>':'')+'<button class="small-button" type="button" data-lead-edit="'+esc(r.id)+'">Edit lead</button></div></article>';
    }).join(''):'<p class="empty-state">'+(all.length?'No leads match these filters.':'No leads in this salesperson view. Add an enquiry to start tracking follow-ups.')+'</p>';
    if ($('list').innerHTML!==markup) $('list').innerHTML=markup;
    if (state.editing) {
      const confirmed=all.find(r=>r.id===state.editing.id);
      if (state.editing.id && !confirmed) { discardEditor(); text('This lead is no longer in your current view.'); }
      else if (state.editing.id && Number(confirmed.version)>state.editing.version && !state.busy) text('This lead changed elsewhere. Cancel and reopen it before saving.');
    }
    $('message').textContent=state.message;
  }
  function clear() {
    discardEditor(); state.workspace=null;state.principal='';state.scope='';state.search='';state.stage='';
    if (!container) return;
    $('list').innerHTML='';$('count').textContent='';$('message').textContent='';$('search').value='';$('filter-stage').value='';$('new').disabled=true;
  }
  function setWorkspace(data) {
    if (!data || !root.PDC_AUTH_CONTEXT) { clear(); return; }
    const authKey=[root.PDC_AUTH_CONTEXT.userId || '',root.PDC_AUTH_CONTEXT.role || ''].join('|');
    if(state.principal && !state.principal.startsWith(authKey+'|')) clear();
    const old = state.workspace;
    state.workspace={...data,leads:(Array.isArray(data.leads)?data.leads:[]).map(r=>{
      const newer=old?.leads?.find(x=>x.id===r.id && Number(x.version)>Number(r.version));
      return newer || r;
    })};
    render();
  }
  function init(options) {
    if(container) { config=options;render();return api; }
    config=options || {};container=root.document.getElementById('sales-leads');
    if(!container) return api;
    container.classList.add('sales-leads-module');
    const fields=[['customer_name','Customer name','text',200],['phone','Phone','tel',60],['email','Email','email',254],['vehicle_interest','Vehicle interest','text',200],['last_contact_date','Last contact date','date'],['next_contact_date','Next contact date','date'],['next_action','Next action','text',200]];
    container.innerHTML='<section class="panel"><div class="panel-header"><div><h2>Leads &amp; follow-ups</h2><p>Enquiries, test drives and quotes. Link an ordered lead to its existing COSI vehicle.</p></div><button id="sales-leads-new" type="button" class="primary">Add lead</button></div><div class="sales-leads-toolbar"><label><span>Search leads</span><input id="sales-leads-search" type="search" placeholder="Customer, vehicle, contact or next action…"></label><label><span>Stage</span><select id="sales-leads-filter-stage"><option value="">All stages</option>'+Object.entries(stages).map(([v,l])=>'<option value="'+v+'">'+l+'</option>').join('')+'</select></label><p id="sales-leads-count" role="status"></p></div><p id="sales-leads-message" class="sales-leads-message" role="status" aria-live="polite"></p><form id="sales-leads-form" class="sales-leads-form" hidden><h3 id="sales-leads-form-title">New lead</h3><div class="sales-leads-fields">'+fields.map(([id,label,type,max])=>'<label><span>'+label+'</span><input id="sales-leads-'+id+'" type="'+type+'"'+(max?' maxlength="'+max+'"':'')+(id==='customer_name'?' required':'')+'></label>').join('')+'<label><span>Stage</span><select id="sales-leads-stage">'+Object.entries(stages).map(([v,l])=>'<option value="'+v+'">'+l+'</option>').join('')+'</select></label><label id="sales-leads-owner-label"><span>Salesperson</span><select id="sales-leads-salesperson_code"></select></label><label class="sales-leads-wide"><span>Existing COSI order</span><select id="sales-leads-tracking_id"></select><small>Required for Ordered. This links to a current order; it does not create a vehicle.</small></label><label class="sales-leads-wide"><span>Customer history &amp; notes</span><textarea id="sales-leads-notes" rows="4" maxlength="4000" placeholder="Conversation notes, test drive details or quote updates…"></textarea></label></div><div class="panel-actions"><button id="sales-leads-save" type="submit" class="primary">Save lead</button><button id="sales-leads-cancel" type="button" class="small-button">Cancel</button></div></form><div id="sales-leads-list" class="sales-leads-list"></div></section>';
    $('new').addEventListener('click',()=>openEditor());
    $('form').addEventListener('submit',save);
    $('cancel').addEventListener('click',()=>{discardEditor();render();});
    $('search').addEventListener('input',()=>{state.search=$('search').value;render();});
    $('filter-stage').addEventListener('change',()=>{state.stage=$('filter-stage').value;render();});
    $('salesperson_code').addEventListener('change',()=>{orderOptions($('salesperson_code').value,'');});
    $('list').addEventListener('click',event=>{
      const edit=event.target.closest?.('[data-lead-edit]');
      if(edit) {openEditor(edit.dataset.leadEdit);return;}
      const open=event.target.closest?.('[data-lead-open]');
      if(open && checkScope() && refs().some(r=>r.tracking_id===open.dataset.leadOpen)) config?.openVehicle?.(open.dataset.leadOpen);
    });
    root.addEventListener?.('pdc-auth-locked',clear);
    root.addEventListener?.('pdc-auth-ready',()=>{if(principal()!==state.principal) clear();});
    clear();return api;
  }
  Object.assign(api,{init,setWorkspace,render,clear,syncScope:checkScope});
})(typeof window !== 'undefined' ? window : globalThis);
