(function (root) {
  'use strict';
  const kinds = {
    contact: ['email','phone','last_contact_date','next_contact_date','next_action'],
    note: ['activity_type','body','occurred_at'],
    task: ['title','due_date','completed'],
    delivery: ['documents','accessories','finance','handover','promised_delivery_date','completed_date','documents_date','accessories_date','finance_date','handover_date'],
    finance: ['approval_status','approval_date','documents_status','documents_date','settlement_status','settlement_date','access_status','access_date','payout_status','payout_date','shared_update','current_application','lender','application_date','amount','commission','internal_notes'],
    view: ['name','filters'],
    dismiss_alert: [],
    finance_access: ['enabled']
  };
  const financeStates = {
    approval: [['not_started','Not started'],['applied','Applied'],['pending','Pending'],['approved','Approved'],['declined','Declined']],
    documents: [['not_started','Not started'],['requested','Requested'],['received','Received'],['complete','Complete']],
    settlement: [['not_started','Not started'],['pending','Pending'],['settled','Settled']],
    access: [['not_required','Not required'],['requested','Requested'],['approved','Approved'],['active','Active']],
    payout: [['not_required','Not required'],['requested','Requested'],['pending','Pending'],['complete','Complete']]
  };
  const financeLabels = {approval:'Approval',documents:'Documents',settlement:'Settlement',access:'Access product',payout:'Existing loan payout'};
  const privateFinance = new Set(['lender','application_date','amount','commission','internal_notes']);
  const arrays = ['contacts','activities','tasks','delivery','finance','views','timeline','alerts','history','order_refs','finance_accounts'];
  const e = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function isSold(row) { return row.cosi === true || /^(yes|true|1)$/i.test(String(row.cosi ?? '').trim()); }
  function dateValue(value) {
    if (value == null || value === '') return null;
    const text=String(value), match=/^(20\d{2}|2100)-(\d{2})-(\d{2})$/.exec(text);
    if(!match) throw new Error('Choose a date from 2000 to 2100.');
    const date=new Date(text+'T00:00:00Z');
    if(!Number.isFinite(date.getTime()) || date.toISOString().slice(0,10)!==text) throw new Error('Choose a valid calendar date.');
    return text;
  }
  function perthToday(now=new Date()) {
    const parts=new Intl.DateTimeFormat('en-AU',{timeZone:'Australia/Perth',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now);
    return ['year','month','day'].map(type=>parts.find(p=>p.type===type).value).join('-');
  }
  function calendarDateKey(value) {
    // This module loads before the dashboard tools in the browser. Resolve them
    // when formatting, after all scripts have loaded, and share their date rules.
    const tools=root.BROOME_SALES_TOOLS || (typeof module==='object'&&module.exports?require('./dashboard-tools.js'):null);
    return tools?.dateKey(value)||null;
  }
  function dateLabel(value, time=false) {
    if (!value) return 'Not recorded';
    const text=String(value).trim(),calendarDate=/^\d{4}-\d{2}-\d{2}$|^\d{1,2}\/\d{1,2}\/\d{4}$/.test(text);
    const key=calendarDate?calendarDateKey(text):null;
    if(calendarDate&&!key)return 'Not recorded';
    const date=new Date(calendarDate?key+'T00:00:00+08:00':value);
    if(!Number.isFinite(date.getTime())) return 'Not recorded';
    return date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',...(time?{timeStyle:'short'}:{})});
  }

  function calendarDays(month) {
    if(!/^20\d{2}-(0[1-9]|1[0-2])$|^2100-(0[1-9]|1[0-2])$/.test(month)) throw new Error('Choose a valid calendar month.');
    const first=new Date(month+'-01T00:00:00Z'),start=new Date(first);
    start.setUTCDate(1-(first.getUTCDay()+6)%7);
    const last=new Date(Date.UTC(first.getUTCFullYear(),first.getUTCMonth()+1,0));
    const size=Math.ceil(((first.getUTCDay()+6)%7+last.getUTCDate())/7)*7;
    return Array.from({length:size},(_,i)=>{const day=new Date(start);day.setUTCDate(start.getUTCDate()+i);return day.toISOString().slice(0,10);});
  }
  function shiftMonth(month,step) {
    const date=new Date(month+'-01T00:00:00Z');date.setUTCMonth(date.getUTCMonth()+step);
    return date.toISOString().slice(0,7);
  }
  function orderLabel(row) {
    return (row.stock ? 'Stock '+row.stock : 'Toyota order '+(row.order||'Not recorded'))+' · '+(row.client||'Customer not recorded');
  }
  function statusLabel(key,value) { return financeStates[key]?.find(([v])=>v===value)?.[1] || 'Not recorded'; }
  function financeSummary(record) {
    if(!record) return 'Finance not recorded';
    return 'Finance '+statusLabel('approval',record.approval_status).toLowerCase()+' · '+statusLabel('settlement',record.settlement_status).toLowerCase();
  }
  const factLabels={stock:'Stock number',kewdale_eta:'Kewdale ETA',dealer_eta:'Dealer ETA',port_plant_eta:'Port / plant ETA',toyota_status:'Toyota status',location_status:'Toyota location code',pmb_location:'PMB location',pmb_stage:'PMB stage',workshop_status:'Workshop status',pmb_arrival_date:'PMB arrival',dealer_delivered_date:'Delivered to dealer',status:'Status',required:'Parts required',ordered:'Parts ordered',received:'Parts received',eta:'ETA',stoppage:'Work stopped',reason:'Reason',stoppage_reason:'Stop reason',note:'Update',notes:'Updates',confirmed:'Confirmed',received_at:'Parts received',stage:'Stage',bay:'Bay',scheduled_start_at:'Booked start',scheduled_end_at:'Booked finish',actual_start_at:'Work started',actual_end_at:'Work finished',stoppage_started_at:'Work stopped',stoppage_cleared_at:'Work resumed',parts_required:'Parts required',parts_ordered:'Parts ordered',parts_received:'Parts received'};
  const workLabels={queued:'Awaiting bay booking',planned:'Booked',started:'Work started',stoppage:'Work stopped',completed:'Completed'};
  function factText(value,key='') {
    if(value==null || value==='')return key==='stock'?'Awaiting allocation':'Not recorded';
    if(typeof value==='boolean')return value?'Yes':'No';
    if(Array.isArray(value))return value.length?value.map(booking=>booking&&typeof booking==='object'?[booking.stage||'Workshop',booking.bay||'Bay not recorded',workLabels[booking.status]||booking.status||'Status not recorded',booking.scheduled_start_at?'Booked '+dateLabel(booking.scheduled_start_at,true):'',booking.actual_start_at?'Started '+dateLabel(booking.actual_start_at,true):'',booking.actual_end_at?'Finished '+dateLabel(booking.actual_end_at,true):''].filter(Boolean).join(' · '):String(booking)).join('; '):'No bay bookings';
    if(typeof value==='object')return Object.entries(value).filter(([name])=>Object.hasOwn(factLabels,name)).map(([name,item])=>factLabels[name]+': '+factText(item,name)).join('; ')||'Not recorded';
    if(/(?:_date|_at|_eta)$/.test(key)||key==='eta')return dateLabel(value,/_at$/.test(key));
    return workLabels[value]||String(value);
  }
  function eventDetails(details,eventType='') {
    if(details==null)return '';
    if(typeof details!=='object')return String(details);
    if(Object.hasOwn(details,'before')||Object.hasOwn(details,'after')) {
      const before=details.before,after=details.after;
      if(before&&after&&typeof before==='object'&&typeof after==='object'&&!Array.isArray(before)&&!Array.isArray(after)) {
        const keys=[...new Set([...Object.keys(before),...Object.keys(after)])];
        return keys.filter(key=>Object.hasOwn(factLabels,key)&&JSON.stringify(before[key])!==JSON.stringify(after[key])).map(key=>factLabels[key]+': '+factText(before[key],key)+' → '+factText(after[key],key)).join('\n')||'Recorded status update';
      }
      const label=eventType.startsWith('stock_')?'Stock number':eventType==='workshop_changed'?'Bay bookings':eventType==='parts_changed'?'Parts':'Status';
      return label+': '+factText(before,eventType.startsWith('stock_')?'stock':'')+' → '+factText(after,eventType.startsWith('stock_')?'stock':'');
    }
    if(details.observed&&typeof details.observed==='object') {
      const facts=details.observed;
      return ['Recorded when sales tracking began.',Object.hasOwn(facts,'stock')?'Stock number: '+factText(facts.stock,'stock'):'',facts.eta?'ETAs: '+factText(facts.eta):'',facts.location?'Location: '+factText(facts.location):'',Array.isArray(facts.workshop)&&facts.workshop.length?'Bay bookings: '+factText(facts.workshop):'',facts.parts?'Parts: '+factText(facts.parts):''].filter(Boolean).join('\n');
    }
    return factText(details);
  }
  function validate(kind,data) {
    if(!Object.hasOwn(kinds,kind)) throw new Error('This type of update is not supported.');
    if(!data || typeof data!=='object' || Array.isArray(data)) throw new Error('Check the information before saving.');
    const result={};
    for(const [key,value] of Object.entries(data)) {
      if(!kinds[kind].includes(key)) throw new Error('This field cannot be changed here.');
      if(/_date$/.test(key)) result[key]=dateValue(value);
      else if(['completed','documents','accessories','finance','handover','current_application','enabled'].includes(key)) {
        if(typeof value!=='boolean') throw new Error('Choose a tick-box value.');
        result[key]=value;
      } else if(['amount','commission'].includes(key)) {
        if(value==null || value==='') result[key]=null;
        else if(!Number.isFinite(Number(value)) || Number(value)<0 || Number(value)>10000000 || Math.abs(Number(value)*100-Math.round(Number(value)*100))>0.000001) throw new Error('Enter an amount from zero to $10,000,000 with up to two decimal places.');
        else result[key]=Number(value);
      } else if(key==='filters') {
        if(!value || typeof value!=='object' || Array.isArray(value)) throw new Error('Check the saved view filters.');
        result[key]=value;
      } else {
        const text=String(value??'').trim();
        const limit=['internal_notes','body','shared_update'].includes(key)?4000:key==='email'?254:key==='phone'?60:['next_action','title','lender'].includes(key)?200:key==='name'?60:80;
        if(text.length>limit || /[\x00-\x08\x0B\x0C\x0E-\x1F]/.test(text)) throw new Error('This entry is too long or contains unsupported characters. Please shorten it.');
        result[key]=text;
      }
    }
    if(kind==='note') {
      if(!['note','call','email','meeting'].includes(result.activity_type||'note')) throw new Error('Choose an activity type.');
      if(!result.body) throw new Error('Enter a note or activity update.');
      if(result.occurred_at && !Number.isFinite(new Date(result.occurred_at).getTime())) throw new Error('Choose a valid activity time.');
    }
    if(kind==='task' && (!result.title || !result.due_date)) throw new Error('Enter a task and its due date.');
    if(kind==='contact' && result.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(result.email)) throw new Error('Enter a valid email address.');
    if(kind==='finance') {
      for(const key of Object.keys(financeStates)) if(Object.hasOwn(result,key+'_status')) {
        if(!financeStates[key].some(([v])=>v===result[key+'_status'])) throw new Error('Choose a valid '+financeLabels[key].toLowerCase()+' status.');
        const needsDate={approval:['approved'],documents:['complete'],settlement:['settled'],access:['approved','active'],payout:['complete']}[key];
        if(needsDate.includes(result[key+'_status']) && !result[key+'_date']) throw new Error('Enter the '+financeLabels[key].toLowerCase()+' date.');
      }
    }
    return result;
  }
  function createWorkspace(host) {
    const state={options:null,workspace:null,principal:null,generation:0,scope:'',view:'myday',detailId:null,detailMarkup:null,editor:null,calendarMonth:null,calendarEditor:null,calendarDrag:null,message:'',busy:new Set(),drafts:new Map(),creates:new Map(),html:new Map()};
    const $=id=>host.document?.getElementById(id);
    const principal=()=>host.PDC_AUTH_CONTEXT?.userId||null;
    const context=()=>state.options?.getContext?.()||null;
    const salesperson=()=>state.options?.getSalesperson?.()||'';
    const canEditFinance=()=>state.workspace?.context?.can_edit_finance===true;
    const isAdmin=()=>context()?.role==='administrator';
    const currentRows=()=> (state.options?.getRows?.()||[]).filter(row=>isSold(row)&&(!salesperson()||row.salesperson_code===salesperson()));
    const ids=()=>new Set(currentRows().map(row=>row.tracking_id));
    const financeRefs=()=> {
      const permitted=ids();
      return (state.workspace?.order_refs||[]).filter(row=>(canEditFinance()||permitted.has(row.tracking_id))&&(!salesperson()||row.salesperson_code===salesperson()));
    };
    const recordList=(name,finance=false)=> {
      const permitted=new Set((finance?financeRefs():currentRows()).map(row=>row.tracking_id));
      return (state.workspace?.[name]||[]).filter(record=>permitted.has(record.tracking_id));
    };
    const getRecord=(name,id)=> (state.workspace?.[name]||[]).find(record=>record.id===id);
    const getLinked=(name,id)=>recordList(name).find(record=>record.tracking_id===id);
    const rowFor=(id,finance=false)=>(finance?financeRefs():currentRows()).find(row=>row.tracking_id===id);
    const currentFinance=id=>recordList('finance',true).find(record=>record.tracking_id===id && record.current_application===true);
    function setHtml(id,html) {
      const container=$(id); if(!container)return;
      if(state.html.get(id)!==html || container.innerHTML==='') { container.innerHTML=html;state.html.set(id,html); }
    }
    function errorMessage(error) {
      if(/version|conflict|changed|concurrent/i.test(error?.message||'')) return 'Someone updated this record. Refresh and try again.';
      return String(error?.message||'The update could not be saved. Please try again.').slice(0,500);
    }
    const messageHtml=()=>state.message?'<p class="crm-message" role="status">'+e(state.message)+'</p>':'';
    function scopeGuard() {
      if(state.principal!==principal() || !principal() || !context()) { clear();return false; }
      const next=salesperson();
      if(state.scope!==next) {
        state.scope=next;state.generation++;state.drafts.clear();state.creates.clear();state.busy.clear();state.editor=null;state.calendarEditor=null;state.calendarDrag=null;state.detailId=null;state.detailMarkup=null;state.message='';state.html.clear();
        for(const id of ['sales-myday','sales-alerts','sales-finance','sales-history','sales-crm-detail'])if($(id))$(id).innerHTML='';
      }
      return !!state.workspace;
    }
    function clear() {
      state.generation++;state.workspace=null;state.principal=principal();state.scope=salesperson();state.busy.clear();state.drafts.clear();state.creates.clear();state.html.clear();state.editor=null;state.calendarEditor=null;state.calendarDrag=null;state.detailId=null;state.detailMarkup=null;state.message='';
      for(const id of ['sales-myday','sales-alerts','sales-finance','sales-history','sales-crm-detail']) if($(id))$(id).innerHTML='';
    }
    function init(options) {
      state.options=options;state.principal=principal();state.scope=salesperson();
      for(const id of ['sales-myday','sales-alerts','sales-finance','sales-history']) bindContainer($(id));
      host.addEventListener?.('pdc-auth-locked',clear);
      host.addEventListener?.('pdc-auth-failed',clear);
      host.addEventListener?.('pdc-auth-ready',()=>{if(state.principal!==principal())clear();});
      return api;
    }
    function setWorkspace(data) {
      if(!principal() || !context()) {clear();return;}
      if(state.principal!==principal()) clear();
      if(!data || typeof data!=='object' || !data.context) throw new Error('Sales workspace access could not be checked.');
      const next={context:{...data.context}};
      for(const key of arrays) next[key]=Array.isArray(data[key])?data[key].map(record=>({...record})):[];
      if(!next.context.can_edit_finance) next.finance=next.finance.map(record=>Object.fromEntries(Object.entries(record).filter(([key])=>!privateFinance.has(key))));
      if(!isAdmin()) {
        next.finance_accounts=[];
        const permitted=ids();
        for(const key of ['contacts','activities','tasks','delivery','timeline','alerts','history'])next[key]=next[key].filter(record=>permitted.has(record.tracking_id));
        if(!next.context.can_edit_finance){next.finance=next.finance.filter(record=>permitted.has(record.tracking_id));next.order_refs=next.order_refs.filter(record=>permitted.has(record.tracking_id));}
      }
      if(canEditFinance()&&!next.context.can_edit_finance) {
        state.generation++;state.editor=null;state.busy.clear();
        for(const key of [...state.drafts.keys()])if(key.startsWith('finance:'))state.drafts.delete(key);
        for(const key of [...state.creates.keys()])if(key.startsWith('finance:'))state.creates.delete(key);
        if($('sales-finance'))$('sales-finance').innerHTML='';state.html.delete('sales-finance');
      }
      state.workspace=next;state.principal=principal();
      render(state.options?.getView?.()||state.view);repaintDetail();
    }
    function field(name,label,value,type='text',extra='') {
      return '<label><span>'+e(label)+'</span><input name="'+e(name)+'" type="'+e(type)+'" value="'+e(value??'')+'" '+extra+'></label>';
    }
    function textarea(name,label,value,extra='') {
      return '<label class="crm-wide"><span>'+e(label)+'</span><textarea name="'+e(name)+'" rows="3" '+extra+'>'+e(value||'')+'</textarea></label>';
    }
    function select(name,label,options,value,extra='') {
      return '<label><span>'+e(label)+'</span><select name="'+e(name)+'" '+extra+'>'+options.map(([v,text])=>'<option value="'+e(v)+'"'+(v===value?' selected':'')+'>'+e(text)+'</option>').join('')+'</select></label>';
    }
    const checked=(name,label,value)=>'<label class="crm-check"><input type="checkbox" name="'+e(name)+'"'+(value===true?' checked':'')+'><span>'+e(label)+'</span></label>';
    function keyFor(kind,id,trackingId) { return [kind,id||'new',trackingId||''].join(':'); }
    function createIdentity(kind,trackingId) {
      const key=keyFor(kind,null,trackingId);
      if(!state.creates.has(key)) {
        let id;
        if(host.crypto?.randomUUID) id=host.crypto.randomUUID();
        else if(host.crypto?.getRandomValues) {
          const bytes=host.crypto.getRandomValues(new Uint8Array(16));bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128;
          const hex=[...bytes].map(b=>b.toString(16).padStart(2,'0')).join('');id=[hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
        }
        if(!id)throw new Error('Secure record identifiers are unavailable. Refresh this page.');
        state.creates.set(key,{id,occurred_at:null});
      }
      return state.creates.get(key);
    }
    function formRecord(kind,id,trackingId,record) { return state.drafts.get(keyFor(kind,id,trackingId))?.data || record || {}; }
    function formStart(kind,id,trackingId,version=0,extra='') {
      const createId=!id&&['note','task','finance'].includes(kind)?createIdentity(kind,trackingId).id:'';
      return '<form class="crm-form" data-crm-form="'+e(kind)+'" data-crm-id="'+e(id||'')+'" data-crm-create-id="'+e(createId)+'" data-crm-tracking="'+e(trackingId||'')+'" data-crm-version="'+e(state.drafts.get(keyFor(kind,id,trackingId))?.version??version)+'" '+extra+'>';
    }
    const saveButton=(label='Save')=>'<div class="crm-form-actions crm-wide"><button type="submit" class="primary">'+label+'</button><span class="crm-form-status" role="status"></span></div>';
    function orderPicker(refs,selected='') {return select('tracking_id','Vehicle',[['','Choose stock / Toyota order'],...refs.map(row=>[row.tracking_id,orderLabel(row)])],selected,'required');}
    function openButton(row,label='Open vehicle') {
      return row&&ids().has(row.tracking_id)?'<button type="button" class="small-button" data-crm-open="'+e(row.tracking_id)+'">'+e(label)+'</button>':'';
    }
    function itemTitle(row) {return '<strong>'+e(orderLabel(row))+'</strong><span class="crm-muted">'+e(row?.vehicle||'')+'</span>';}
    function linkedTitle(id,finance=false) {const row=rowFor(id,finance);return row?itemTitle(row):'<strong>Vehicle no longer in this view</strong>';}

    function calendarEntries() {
      const entries=[];
      for(const record of recordList('tasks')) if(record.due_date&&record.completed!==true) entries.push({kind:'task',id:record.id,trackingId:record.tracking_id,date:record.due_date,title:record.title||'Task',version:record.version});
      for(const record of recordList('contacts')) if(record.next_contact_date) entries.push({kind:'contact',id:record.id,trackingId:record.tracking_id,date:record.next_contact_date,title:record.next_action||'Contact customer',version:record.version});
      for(const record of recordList('delivery')) if(record.promised_delivery_date&&record.handover!==true) entries.push({kind:'delivery',id:record.id,trackingId:record.tracking_id,date:record.promised_delivery_date,title:'Promised customer delivery'});
      for(const row of currentRows()) {
        const date=calendarDateKey(row.kewdale_eta);
        if(date) entries.push({kind:'eta',id:row.tracking_id,trackingId:row.tracking_id,date,title:'Kewdale ETA · estimated'});
      }
      return entries.sort((a,b)=>a.date.localeCompare(b.date)||a.kind.localeCompare(b.kind)||String(a.id).localeCompare(String(b.id)));
    }
    function calendarEvent(entry) {
      const row=rowFor(entry.trackingId),movable=['task','contact'].includes(entry.kind),late=movable&&entry.date<perthToday(),busy=state.busy.has(keyFor(entry.kind,entry.id,entry.trackingId));
      return '<button type="button" class="crm-calendar-event crm-calendar-'+e(entry.kind)+(late?' crm-calendar-overdue':'')+'" data-calendar-kind="'+e(entry.kind)+'" data-calendar-id="'+e(entry.id)+'"'+(movable&&!busy?' draggable="true"':'')+(busy?' disabled':'')+' aria-label="'+e(entry.title+' · '+orderLabel(row)+' · '+dateLabel(entry.date)+(movable?' · Click to edit or drag to a day':' · Open vehicle'))+'"><span>'+e(entry.title)+'</span><small>'+e(row.stock||'Order '+row.order)+' · '+e(row.client)+'</small>'+(late?'<small>Overdue · '+e(dateLabel(entry.date))+'</small>':'')+'</button>';
    }
    function calendarEditorHtml() {
      const editor=state.calendarEditor;if(!editor)return '';
      const record=editor.id?recordList(editor.kind==='task'?'tasks':'contacts').find(r=>r.id===editor.id):null;
      if(editor.id&&!record){state.calendarEditor=null;return '';}
      const trackingId=record?.tracking_id||null,kind=editor.kind;
      const data=formRecord(kind,record?.id,trackingId,record||{due_date:editor.date||perthToday(),completed:false});
      const fields=(record?'<div class="crm-wide">'+linkedTitle(trackingId)+'</div>':orderPicker(currentRows(),data.tracking_id||''))+(kind==='task'?field('title','Task / reminder',data.title,'text','required maxlength="200"')+field('due_date','Due date',data.due_date,'date','required min="2000-01-01" max="2100-12-31"')+(record?checked('completed','Completed',data.completed===true):''):textarea('next_action','Customer reminder',data.next_action,'maxlength="200"')+field('next_contact_date','Reminder date',data.next_contact_date,'date','min="2000-01-01" max="2100-12-31"'));
      return '<section class="panel crm-editor crm-calendar-editor"><div class="panel-header"><h3>'+(record?'Edit '+(kind==='task'?'task':'customer reminder'):'Add task / reminder')+'</h3><button type="button" class="small-button" data-calendar-close>Close</button></div>'+formStart(kind,record?.id,trackingId,record?.version||0)+fields+saveButton('Save '+(kind==='task'?'task':'reminder'))+'</form>'+(record?openButton(rowFor(trackingId)):'')+'</section>';
    }
    function renderMyDay() {
      const today=perthToday();state.calendarMonth=state.calendarMonth||today.slice(0,7);
      const month=state.calendarMonth,days=calendarDays(month),entries=calendarEntries();
      const tasks=entries.filter(r=>r.kind==='task'&&r.date<=today),contacts=entries.filter(r=>r.kind==='contact'&&r.date<=today);
      const overdue=entries.filter(r=>['task','contact'].includes(r.kind)&&r.date<days[0]);
      const monthTitle=new Date(month+'-01T00:00:00Z').toLocaleDateString('en-AU',{timeZone:'UTC',month:'long',year:'numeric'});
      const cards='<div class="crm-summary-cards"><article><span>Tasks due</span><strong>'+tasks.length+'</strong><small>Today and overdue</small></article><article><span>Customer reminders due</span><strong>'+contacts.length+'</strong><small>Ordered vehicles only</small></article><article><span>Vehicle deliveries this month</span><strong>'+entries.filter(r=>r.kind==='delivery'&&r.date.startsWith(month)).length+'</strong><small>Promised customer delivery dates</small></article></div>';
      const cells=days.map(day=>'<section class="crm-calendar-day'+(day.startsWith(month)?'':' crm-calendar-outside')+(day===today?' crm-calendar-today':'')+'" data-calendar-day="'+day+'" aria-label="'+e(dateLabel(day))+'"><button type="button" class="crm-calendar-date" data-calendar-add="'+day+'" aria-label="Add task on '+e(dateLabel(day))+'">'+Number(day.slice(-2))+(day===today?' <span>Today</span>':'')+'</button><div class="crm-calendar-events">'+entries.filter(entry=>entry.date===day).map(calendarEvent).join('')+'</div></section>').join('');
      setHtml('sales-myday','<div class="section-intro crm-heading"><div><h2>My Day</h2><p>Tasks, customer reminders and delivery plans for ordered vehicles. Click a task or reminder to edit it, or drag it to another day. Dates use Perth time.</p></div>'+(currentRows().length?'<button type="button" class="primary" data-calendar-add="'+today+'">Add task / reminder</button>':'')+'</div>'+messageHtml()+cards+calendarEditorHtml()+'<section class="panel crm-calendar-panel"><div class="crm-calendar-toolbar"><h3>'+e(monthTitle)+'</h3><div><button type="button" class="small-button" data-calendar-month="-1" aria-label="Previous month"'+(month==='2000-01'?' disabled':'')+'>‹</button><button type="button" class="small-button" data-calendar-today>Today</button><button type="button" class="small-button" data-calendar-month="1" aria-label="Next month"'+(month==='2100-12'?' disabled':'')+'>›</button></div></div><div class="crm-calendar-legend"><span>Tasks</span><span>Customer reminders</span><span>Promised delivery</span><span>Kewdale estimate · read-only</span></div><div class="crm-calendar-scroll"><div class="crm-calendar-weekdays">'+['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map(day=>'<span>'+day+'</span>').join('')+'</div><div class="crm-calendar-grid">'+cells+'</div></div></section>'+(overdue.length?'<section class="crm-calendar-earlier"><h3>Earlier outstanding tasks and reminders</h3><div>'+overdue.map(calendarEvent).join('')+'</div></section>':''));
    }
    function calendarRecord(kind,id) {
      if(!['task','contact'].includes(kind))return null;
      return recordList(kind==='task'?'tasks':'contacts').find(record=>record.id===id)||null;
    }
    function beginCalendarDrag(kind,id) {
      if(!scopeGuard())return null;
      const record=calendarRecord(kind,id);
      if(!record||state.busy.has(keyFor(kind,id,record.tracking_id))||state.drafts.has(keyFor(kind,id,record.tracking_id)))return null;
      return {kind,id,trackingId:record.tracking_id,version:record.version,generation:state.generation,owner:principal()};
    }
    async function moveCalendarEntry(drag,date) {
      if(!scopeGuard()||!drag||drag.generation!==state.generation||drag.owner!==principal())return null;
      date=dateValue(date);if(!date)return null;
      const record=calendarRecord(drag.kind,drag.id);
      if(!record||record.tracking_id!==drag.trackingId)return null;
      if(record.version!==drag.version)throw new Error('This reminder changed. Refresh before moving it.');
      if(state.drafts.has(keyFor(drag.kind,drag.id,record.tracking_id)))throw new Error('Save or close your edits before moving this reminder.');
      const before=drag.kind==='task'?record.due_date:record.next_contact_date;
      if(before===date)return record;
      const patch=drag.kind==='task'?{title:record.title,due_date:date,completed:record.completed===true}:{next_contact_date:date};
      const result=await save(drag.kind,record.id,record.tracking_id,patch,drag.version);
      if(result&&drag.generation===state.generation&&drag.owner===principal()) {state.message='Moved to '+dateLabel(date)+'.';render('myday');repaintDetail();}
      return result;
    }
    function bindCalendar(container) {
      container.addEventListener('dragstart',event=>{
        const button=event.target.closest?.('[data-calendar-kind]'),data=button?.dataset;
        const drag=data?beginCalendarDrag(data.calendarKind,data.calendarId):null;
        if(!drag){event.preventDefault();return;}
        state.calendarDrag=drag;event.dataTransfer.effectAllowed='move';event.dataTransfer.setData('text/plain','sales-calendar-reminder');
      });
      container.addEventListener('dragover',event=>{
        const day=event.target.closest?.('[data-calendar-day]');
        if(!day||!state.calendarDrag)return;event.preventDefault();event.dataTransfer.dropEffect='move';
        container.querySelectorAll?.('.crm-calendar-drop').forEach(node=>node.classList.remove('crm-calendar-drop'));day.classList.add('crm-calendar-drop');
      });
      const clearDrop=()=>container.querySelectorAll?.('.crm-calendar-drop').forEach(node=>node.classList.remove('crm-calendar-drop'));
      container.addEventListener('dragend',()=>{state.calendarDrag=null;clearDrop();});
      container.addEventListener('drop',async event=>{
        const day=event.target.closest?.('[data-calendar-day]'),drag=state.calendarDrag;
        state.calendarDrag=null;clearDrop();if(!day||!drag)return;event.preventDefault();
        try{await moveCalendarEntry(drag,day.dataset.calendarDay);}
        catch(error){if(drag.generation===state.generation&&drag.owner===principal()){state.message=errorMessage(error);render('myday');}}
      });
    }
    function renderAlerts() {
      const records=recordList('alerts').filter(a=>!a.dismissed_at).sort((a,b)=>String(b.occurred_at||'').localeCompare(String(a.occurred_at||'')));
      setHtml('sales-alerts','<div class="section-intro"><h2>Vehicle alerts</h2><p>Recorded changes to stock, ETA, Toyota location and PMB progress. First-time observations establish a baseline.</p></div>'+messageHtml()+(records.length?'<div class="crm-columns">'+records.map(a=>'<article class="crm-card crm-alert"><div class="crm-card-top">'+linkedTitle(a.tracking_id)+'<span class="crm-muted">'+e(dateLabel(a.occurred_at,true))+'</span></div><h3>'+e(a.title||'Vehicle updated')+'</h3><p>'+e(eventDetails(a.details,a.event_type))+'</p><div class="crm-card-actions">'+openButton(rowFor(a.tracking_id))+'<button type="button" class="small-button" data-crm-dismiss="'+e(a.id)+'">Dismiss</button></div></article>').join('')+'</div>':'<div class="crm-empty">No new vehicle alerts.</div>'));
    }
    function financeStatus(record,key) {
      const value=record[key+'_status'];
      return '<span class="crm-badge '+(['approved','complete','settled','active'].includes(value)?'crm-good':['declined'].includes(value)?'crm-late':'')+'">'+e(statusLabel(key,value))+'</span><small>'+e(record[key+'_date']?dateLabel(record[key+'_date']):'')+'</small>';
    }
    function financeForm() {
      if(!canEditFinance() || !state.editor) return '';
      const record=state.editor.id?getRecord('finance',state.editor.id):null;
      if(record&&!financeRefs().some(row=>row.tracking_id===record.tracking_id)) {state.editor=null;return '';}
      const trackingId=record?.tracking_id||state.editor.trackingId||null;
      const data=formRecord('finance',record?.id,trackingId,record||{current_application:true});
      let fields=record?'<div class="crm-wide crm-edit-vehicle">'+linkedTitle(trackingId,true)+'</div>':orderPicker(financeRefs(),data.tracking_id||trackingId||'');
      for(const key of Object.keys(financeStates)) fields+=select(key+'_status',financeLabels[key],financeStates[key],data[key+'_status']||financeStates[key][0][0])+field(key+'_date',financeLabels[key]+' date',data[key+'_date'],'date','min="2000-01-01" max="2100-12-31"');
      fields+=checked('current_application','Current finance application',data.current_application===true)+textarea('shared_update','Update visible to the salesperson',data.shared_update,'maxlength="4000"');
      const privateFields=field('lender','Financier',data.lender)+field('application_date','Application date',data.application_date,'date','min="2000-01-01" max="2100-12-31"')+field('amount','NAF / finance amount',data.amount,'number','min="0" step="0.01"')+field('commission','Commission',data.commission,'number','min="0" step="0.01"')+textarea('internal_notes','Private finance notes',data.internal_notes,'maxlength="4000"');
      return '<section class="crm-editor panel"><div class="panel-header"><div><h3>'+(record?'Update finance':'New finance entry')+'</h3><p>The vehicle link uses its permanent order identity.</p></div><button type="button" class="small-button" data-crm-finance-cancel>Close</button></div>'+formStart('finance',record?.id,trackingId,record?.version||0)+fields+'<fieldset class="crm-private crm-wide"><legend>Finance staff only</legend><div class="crm-form">'+privateFields+'</div></fieldset>'+saveButton('Save finance')+'</form></section>';
    }
    function financeAccessHtml() {
      if(!isAdmin()) return '';
      const accounts=state.workspace?.finance_accounts||[];
      return '<details class="crm-finance-access"><summary>Finance editor access</summary><p>Select an approved staff account. This grants editing of sales finance records only.</p>'+(accounts.length?'<div class="crm-account-list">'+accounts.map(account=>'<article class="crm-account"><div><strong>'+e(account.name||account.email||'Approved staff account')+'</strong><span class="crm-muted">'+e(account.email||'')+'</span></div><span class="crm-badge">'+(account.enabled?'Finance editor':'No finance editing')+'</span><button type="button" class="small-button" data-crm-finance-access="'+e(account.id)+'">'+(account.enabled?'Remove finance editing':'Allow finance editing')+'</button></article>').join('')+'</div>':'<p class="crm-empty">No approved salesperson accounts are available.</p>')+'</details>';
    }
    function renderFinance() {
      const refs=financeRefs(),records=recordList('finance',true),current=records.filter(f=>f.current_application===true);
      const rows=refs.map(row=>({row,record:current.find(f=>f.tracking_id===row.tracking_id)}));
      const approved=current.filter(f=>f.approval_status==='approved').length,waiting=current.filter(f=>f.settlement_status==='pending').length;
      const table=rows.length?'<div class="table-wrap"><table class="crm-finance-table"><thead><tr><th scope="col">Vehicle / customer</th>'+Object.values(financeLabels).map(label=>'<th scope="col">'+e(label)+'</th>').join('')+'<th scope="col">Shared update</th><th scope="col">Action</th></tr></thead><tbody>'+rows.map(({row,record})=>'<tr><td data-label="Vehicle / customer"><div class="crm-finance-cell">'+itemTitle(row)+'</div></td>'+Object.keys(financeStates).map(key=>'<td data-label="'+e(financeLabels[key])+'"><div class="crm-finance-cell">'+financeStatus(record||{},key)+'</div></td>').join('')+'<td class="crm-update" data-label="Shared update"><div class="crm-finance-cell">'+e(record?.shared_update||'')+(record?'<small>Updated '+e(dateLabel(record.updated_at,true))+'</small>':'')+'</div></td><td data-label="Action"><div class="crm-finance-actions">'+openButton(row)+(canEditFinance()?'<button type="button" class="small-button" '+(record?'data-crm-edit-finance="'+e(record.id)+'"':'data-crm-new-finance="'+e(row.tracking_id)+'"')+'>'+(record?'Update':'Add finance')+'</button>':'')+'</div></td></tr>').join('')+'</tbody></table></div>':'<p class="crm-empty">No authorised vehicles in this view.</p>';
      const history=records.filter(f=>f.current_application!==true);
      const prior=history.length?'<details class="crm-finance-history"><summary>Previous finance applications ('+history.length+')</summary><div class="crm-columns">'+history.map(record=>'<article class="crm-card">'+linkedTitle(record.tracking_id,true)+'<p>'+e(financeSummary(record))+'</p><p class="crm-muted">'+e(record.shared_update||'')+'</p>'+(canEditFinance()?'<button type="button" class="small-button" data-crm-edit-finance="'+e(record.id)+'">Review application</button>':'')+'</article>').join('')+'</div></details>':'';
      setHtml('sales-finance','<div class="section-intro crm-heading"><div><h2>Finance</h2><p>Approval, documents, settlement, Access and existing loan payout are tracked separately.</p></div>'+(canEditFinance()?'<button type="button" class="primary" data-crm-new-finance="">New finance entry</button>':'')+'</div>'+messageHtml()+'<div class="crm-summary-cards"><article><span>Current applications</span><strong>'+current.length+'</strong><small>'+refs.length+' authorised vehicles</small></article><article><span>Approved</span><strong>'+approved+'</strong><small>Approval recorded by finance staff</small></article><article><span>Awaiting settlement</span><strong>'+waiting+'</strong><small>New finance settlement</small></article></div>'+financeForm()+'<section class="panel crm-finance-panel">'+table+'</section>'+prior+financeAccessHtml());
    }
    function renderHistory() {
      const records=recordList('history');
      setHtml('sales-history','<div class="section-intro"><h2>Order history</h2><p>Completed orders will appear here when an authoritative RDR confirmation is connected.</p></div>'+(records.length?'<div class="crm-columns">'+records.map(r=>'<article class="crm-card">'+linkedTitle(r.tracking_id)+'<p>'+e(r.title||'RDR confirmed')+'</p><span class="crm-muted">'+e(dateLabel(r.occurred_at,true))+'</span></article>').join('')+'</div>':'<div class="crm-empty">RDR confirmation is awaiting its Navision field. Delivered vehicles stay on the active page.</div>'));
    }
    function render(view=state.view) {
      state.view=view;
      if(!scopeGuard()) return;
      if(view==='myday') renderMyDay();
      else if(view==='alerts') renderAlerts();
      else if(view==='finance') {if(host.BROOME_SALES_FINANCE)host.BROOME_SALES_FINANCE.render();else renderFinance();}
      else if(view==='history') renderHistory();
    }
    function timeline(row) {
      const records=recordList('timeline').filter(r=>r.tracking_id===row.tracking_id).map(r=>({...r}));
      const current=[['pmb_arrival_date','PMB arrival'],['qc_completed_at','QC completed'],['rft_confirmed_at','Ready for transport confirmed'],['rft_transferred_at','Transferred to RFT'],['transport_booked_at','Transport booked'],['collected_at','Vehicle collected'],['dealer_delivered_date','Delivered to dealer']];
      for(const [key,title] of current) if(row[key]) records.push({id:'current-'+key,title,occurred_at:row[key],details:'Recorded vehicle milestone'});
      for(const booking of row.bay_bookings||[]) for(const [key,title] of [['scheduled_start_at','Bay booking'],['actual_start_at','Work started'],['actual_end_at','Work finished'],['stoppage_started_at','Work stopped']]) if(booking[key]) records.push({id:booking.booking_id+'-'+key,title,occurred_at:booking[key],details:(booking.stage||'Workshop')+' · '+(booking.bay||'Bay not recorded')+(key==='stoppage_started_at'&&booking.stoppage_reason?' · '+booking.stoppage_reason:'')});
      return records.filter(r=>r.occurred_at).sort((a,b)=>String(b.occurred_at).localeCompare(String(a.occurred_at)));
    }
    function detailHtml(row) {
      if(!scopeGuard() || !ids().has(row.tracking_id)) return '';
      state.detailId=row.tracking_id;
      const id=row.tracking_id,contact=getLinked('contacts',id),delivery=getLinked('delivery',id);
      const c=formRecord('contact',contact?.id,id,contact),d=formRecord('delivery',delivery?.id,id,delivery);
      const notes=recordList('activities').filter(r=>r.tracking_id===id).sort((a,b)=>String(b.occurred_at||b.created_at).localeCompare(String(a.occurred_at||a.created_at)));
      const tasks=recordList('tasks').filter(r=>r.tracking_id===id),events=timeline(row),finance=currentFinance(id);
      const note=formRecord('note',null,id,{}),task=formRecord('task',null,id,{});
      const contactForm=formStart('contact',contact?.id,id,contact?.version||0)+field('email','Customer email',c.email,'email','maxlength="254"')+field('phone','Customer phone',c.phone,'tel','maxlength="60"')+field('last_contact_date','Last contact date',c.last_contact_date,'date','min="2000-01-01" max="2100-12-31"')+field('next_contact_date','Next contact date',c.next_contact_date,'date','min="2000-01-01" max="2100-12-31"')+textarea('next_action','Next action',c.next_action,'maxlength="200"')+saveButton('Save contact plan')+'</form>';
      const noteForm=formStart('note',null,id)+select('activity_type','Activity',[['note','Note'],['call','Call'],['email','Email logged'],['meeting','Meeting']],note.activity_type||'note')+textarea('body','Customer update',note.body,'required maxlength="4000"')+saveButton('Log activity')+'</form>';
      const taskForm=formStart('task',null,id)+field('title','Task',task.title,'text','required maxlength="200"')+field('due_date','Due date',task.due_date,'date','required min="2000-01-01" max="2100-12-31"')+saveButton('Add task')+'</form>';
      const deliveryForm=formStart('delivery',delivery?.id,id,delivery?.version||0)+['documents','accessories','finance','handover'].map(key=>checked(key,{documents:'Documents ready',accessories:'Accessories ready',finance:'Finance checked',handover:'Customer handover complete'}[key],d[key]===true)).join('')+field('promised_delivery_date','Promised customer delivery',d.promised_delivery_date,'date','min="2000-01-01" max="2100-12-31"')+field('completed_date','Customer handover date',d.completed_date,'date','min="2000-01-01" max="2100-12-31"')+saveButton('Save delivery checklist')+'</form>';
      const markup='<section id="sales-crm-detail" class="crm-detail"><h3>Customer and follow-ups</h3>'+messageHtml()+'<p class="crm-muted">These notes and checks are saved on the sales page. PMB progress remains read-only.</p><details open><summary>Contact plan</summary>'+contactForm+'</details><details><summary>Customer history ('+notes.length+')</summary><div class="crm-activities">'+(notes.length?notes.map(n=>'<article><strong>'+e(({note:'Note',call:'Call',email:'Email logged',meeting:'Meeting'})[n.activity_type]||'Activity')+'</strong><span class="crm-muted">'+e(dateLabel(n.occurred_at||n.created_at,true))+'</span><p>'+e(n.body)+'</p></article>').join(''):'<p class="crm-empty">No customer activities recorded.</p>')+'</div>'+noteForm+'<p class="crm-muted">Logging an email records your update. It does not send a message.</p></details><details><summary>Tasks ('+tasks.filter(t=>!t.completed).length+' open)</summary>'+tasks.map(t=>'<article class="crm-inline-task"><span>'+e(t.title)+'<small>'+e(dateLabel(t.due_date))+'</small></span><button type="button" class="small-button" data-crm-task-toggle="'+e(t.id)+'">'+(t.completed?'Reopen':'Mark done')+'</button></article>').join('')+taskForm+'</details><details><summary>Delivery checklist</summary>'+deliveryForm+'<p class="crm-muted">A handover tick does not mark RDR or change workshop completion.</p></details><details><summary>Finance status</summary><p>'+e(financeSummary(finance))+'</p>'+(finance?'<dl class="crm-finance-detail">'+Object.keys(financeStates).map(key=>'<div><dt>'+e(financeLabels[key])+'</dt><dd>'+financeStatus(finance,key)+'</dd></div>').join('')+'</dl><p>'+e(finance.shared_update||'')+'</p>':'')+'<button type="button" class="small-button" data-crm-show="finance">View Finance</button></details><details><summary>Vehicle timeline</summary>'+(events.length?'<ol class="crm-timeline">'+events.map(event=>'<li><strong>'+e(event.title||'Vehicle update')+'</strong><time>'+e(dateLabel(event.occurred_at,true))+'</time><p>'+e(eventDetails(event.details,event.event_type))+'</p></li>').join('')+'</ol>':'<p class="crm-empty">No dated vehicle milestones recorded yet.</p>')+'</details></section>';
      state.pendingDetailMarkup=markup;return markup;
    }
    function bindDetail(trackingId) { if(!ids().has(trackingId))return;state.detailId=trackingId;state.detailMarkup=state.pendingDetailMarkup;bindContainer($('sales-crm-detail')); }
    function readForm(form) {
      const data={};
      for(const element of form.elements||[]) {
        if(!element.name || element.disabled || ['submit','button'].includes(element.type)) continue;
        data[element.name]=element.type==='checkbox'?element.checked:element.value;
      }
      return data;
    }
    function rememberForm(form) {
      const kind=form.dataset.crmForm,key=keyFor(kind,form.dataset.crmId,form.dataset.crmTracking);
      state.drafts.set(key,{version:Number(form.dataset.crmVersion||0),data:readForm(form)});
    }
    function repaintDetail() {
      const row=rowFor(state.detailId),container=$('sales-crm-detail');
      if(!row||!container || [...state.drafts.keys()].some(key=>key.endsWith(':'+state.detailId)))return;
      const prior=state.detailMarkup,markup=detailHtml(row);
      if(markup===prior)return;
      const open=[...(container.querySelectorAll?.('details')||[])].map(detail=>detail.open);
      container.outerHTML=markup;bindDetail(row.tracking_id);
      [...($('sales-crm-detail')?.querySelectorAll?.('details')||[])].forEach((detail,index)=>{if(index<open.length)detail.open=open[index];});
    }
    function bindContainer(container) {
      if(!container || container.dataset?.crmBound==='yes') return;
      if(container.dataset)container.dataset.crmBound='yes';
      if(container.id==='sales-myday')bindCalendar(container);
      container.addEventListener('input',event=>{const form=event.target.closest?.('[data-crm-form]');if(form)rememberForm(form);});
      container.addEventListener('change',event=>{const form=event.target.closest?.('[data-crm-form]');if(form)rememberForm(form);});
      container.addEventListener('submit',async event=>{
        const form=event.target.closest?.('[data-crm-form]');if(!form)return;
        event.preventDefault();if(!scopeGuard())return;
        const kind=form.dataset.crmForm,fields=readForm(form),trackingId=form.dataset.crmTracking||fields.tracking_id||null;delete fields.tracking_id;
        const create=!form.dataset.crmId&&['note','task','finance'].includes(kind)?createIdentity(kind,form.dataset.crmTracking||null):null;
        if(kind==='note'){create.occurred_at=create.occurred_at||new Date().toISOString();fields.occurred_at=create.occurred_at;}
        if(kind==='task'&&!Object.hasOwn(fields,'completed'))fields.completed=false;
        const button=form.querySelector?.('[type="submit"]'),status=form.querySelector?.('.crm-form-status');
        if(button)button.disabled=true;if(status)status.textContent='Saving…';
        const generation=state.generation,owner=principal();
        try {
          const record=await save(kind,form.dataset.crmId||create?.id||null,trackingId,fields,Number(form.dataset.crmVersion||0));
          if(!record||generation!==state.generation||owner!==principal())return;
          state.drafts.delete(keyFor(kind,form.dataset.crmId,form.dataset.crmTracking));
          state.creates.delete(keyFor(kind,null,form.dataset.crmTracking));
          if(status)status.textContent='Saved.';
          if(kind==='finance')state.editor=null;
          if(state.view==='myday'&&state.calendarEditor?.kind===kind)state.calendarEditor=null;
          render(state.view);repaintDetail();
        } catch(error) {
          if(generation===state.generation&&owner===principal()) {state.message=errorMessage(error);if(status)status.textContent=state.message;}
        } finally {if(generation===state.generation&&owner===principal()&&button)button.disabled=false;}
      });
      container.addEventListener('click',async event=> {
        if(!scopeGuard())return;
        const calendarButton=event.target.closest?.('[data-calendar-month],[data-calendar-today],[data-calendar-add],[data-calendar-close],[data-calendar-kind]');
        if(calendarButton&&['calendarMonth','calendarToday','calendarAdd','calendarClose','calendarKind'].some(key=>Object.hasOwn(calendarButton.dataset,key))){
          const d=calendarButton.dataset;
          if(d.calendarMonth){const month=shiftMonth(state.calendarMonth||perthToday().slice(0,7),Number(d.calendarMonth));if(month>='2000-01'&&month<='2100-12')state.calendarMonth=month;}
          else if(d.calendarToday!==undefined)state.calendarMonth=perthToday().slice(0,7);
          else if(d.calendarClose!==undefined){const editor=state.calendarEditor,record=editor?.id?calendarRecord(editor.kind,editor.id):null;if(editor){state.drafts.delete(keyFor(editor.kind,editor.id,record?.tracking_id));state.creates.delete(keyFor(editor.kind,null,record?.tracking_id));}state.calendarEditor=null;}
          else if(d.calendarAdd&&currentRows().length){state.calendarEditor={kind:'task',date:dateValue(d.calendarAdd)};}
          else if(d.calendarKind){const record=calendarRecord(d.calendarKind,d.calendarId);if(record)state.calendarEditor={kind:d.calendarKind,id:record.id};else {const entry=calendarEntries().find(r=>r.kind===d.calendarKind&&r.id===d.calendarId);if(entry)state.options?.openVehicle?.(entry.trackingId);return;}}
          state.message='';render('myday');$('sales-myday')?.querySelector?.('.crm-calendar-editor')?.scrollIntoView?.({block:'nearest'});return;
        }
        const button=event.target.closest?.('[data-crm-open],[data-crm-task-toggle],[data-crm-dismiss],[data-crm-new-finance],[data-crm-edit-finance],[data-crm-finance-cancel],[data-crm-finance-access],[data-crm-show]');
        if(!button)return;const data=button.dataset;
        if(data.crmOpen!==undefined){if(ids().has(data.crmOpen))state.options?.openVehicle?.(data.crmOpen);return;}
        if(data.crmShow){state.options?.showView?.(data.crmShow);return;}
        if(data.crmFinanceCancel!==undefined){state.editor=null;for(const key of [...state.drafts.keys()])if(key.startsWith('finance:'))state.drafts.delete(key);for(const key of [...state.creates.keys()])if(key.startsWith('finance:'))state.creates.delete(key);state.message='';render('finance');return;}
        if(data.crmNewFinance!==undefined){if(canEditFinance()){state.editor={trackingId:data.crmNewFinance||null};state.message='';render('finance');$('sales-finance')?.querySelector?.('.crm-editor')?.scrollIntoView?.({block:'nearest'});}return;}
        if(data.crmEditFinance!==undefined){if(canEditFinance()&&recordList('finance',true).some(r=>r.id===data.crmEditFinance)){state.editor={id:data.crmEditFinance};state.message='';render('finance');$('sales-finance')?.querySelector?.('.crm-editor')?.scrollIntoView?.({block:'nearest'});}return;}
        const generation=state.generation,owner=principal();button.disabled=true;
        try {
          let result;
          if(data.crmTaskToggle){const task=recordList('tasks').find(t=>t.id===data.crmTaskToggle);if(task)result=await save('task',task.id,task.tracking_id,{title:task.title,due_date:task.due_date,completed:!task.completed},task.version);}
          if(data.crmDismiss){const alert=recordList('alerts').find(a=>a.id===data.crmDismiss);if(alert)result=await save('dismiss_alert',alert.id,alert.tracking_id,{},alert.version);}
          if(data.crmFinanceAccess&&isAdmin()){const account=(state.workspace?.finance_accounts||[]).find(a=>a.id===data.crmFinanceAccess);if(account)result=await save('finance_access',account.id,null,{enabled:!account.enabled},account.version);}
          if(result&&generation===state.generation&&owner===principal()){render(state.view);repaintDetail();}
        }catch(error){if(generation===state.generation&&owner===principal()){state.message=errorMessage(error);render(state.view);repaintDetail();}}
        finally{if(generation===state.generation&&owner===principal())button.disabled=false;}
      });
    }
    async function save(kind,id,trackingId,data,version=0) {
      if(!scopeGuard()) throw new Error('Sign in again before saving.');
      if(!Number.isInteger(version)||version<0)throw new Error('Refresh this record before saving.');
      if(kind==='finance'&&!canEditFinance())throw new Error('Finance editor access is required.');
      if(kind==='finance_access'&&!isAdmin())throw new Error('Administrator access is required.');
      const permitted=(kind==='finance'?new Set(financeRefs().map(r=>r.tracking_id)):ids());
      if(!['finance_access','view'].includes(kind)&&!permitted.has(trackingId))throw new Error('This vehicle is no longer in your view.');
      const fields=validate(kind,data),key=keyFor(kind,id,trackingId);
      if(state.busy.has(key))throw new Error('This update is already saving.');
      const generation=state.generation,owner=principal();state.busy.add(key);
      try {
        const {data:response,error}=await host.PDC_SUPABASE.rpc('save_broome_sales_crm',{p_kind:kind,p_id:id||null,p_tracking_id:trackingId||null,p_data:fields,p_expected_version:version});
        if(generation!==state.generation||owner!==principal()||!context())return null;
        if(kind==='finance'&&!canEditFinance() || kind==='finance_access'&&!isAdmin())return null;
        if(!['finance_access','view'].includes(kind)&&!(kind==='finance'?new Set(financeRefs().map(r=>r.tracking_id)):ids()).has(trackingId))return null;
        if(error)throw new Error(error.message||'The update could not be saved.');
        if(!response?.record)throw new Error('The saved record could not be checked. Refresh and try again.');
        const record={...response.record};
        if(!canEditFinance())for(const field of privateFinance)delete record[field];
        const listKey={contact:'contacts',note:'activities',task:'tasks',delivery:'delivery',finance:'finance',view:'views',dismiss_alert:'alerts',finance_access:'finance_accounts'}[kind];
        if(listKey&&state.workspace){const list=state.workspace[listKey],index=list.findIndex(r=>r.id===record.id);if(index<0)list.push(record);else list[index]={...list[index],...record};}
        state.message='Saved.';
        await state.options?.onChanged?.(kind,record);
        if(generation!==state.generation||owner!==principal())return null;
        if(!['finance_access','view'].includes(kind)&&!(kind==='finance'?new Set(financeRefs().map(r=>r.tracking_id)):ids()).has(trackingId))return null;
        return record;
      } finally {if(generation===state.generation&&owner===principal())state.busy.delete(key);}
    }
    async function refresh() {
      if(!principal()||!context()) {clear();return;}
      const generation=state.generation,owner=principal();
      const {data,error}=await host.PDC_SUPABASE.rpc('get_broome_sales_workspace');
      if(generation!==state.generation||owner!==principal())return;
      if(error){clear();throw new Error(error.message||'The workspace could not be refreshed.');}
      setWorkspace(data);
    }
    function getWorkspace() {return state.workspace;}
    const api={init,setWorkspace,render,detailHtml,bindDetail,clear,save,refresh,getWorkspace,beginCalendarDrag,moveCalendarEntry,syncScope:scopeGuard,refreshDetail:repaintDetail,financeSummary,perthToday,dateLabel};
    return api;
  }
  const exports={createWorkspace,validate,isSold,dateValue,dateLabel,perthToday,orderLabel,statusLabel,financeSummary,eventDetails,calendarDays,shiftMonth};
  if(typeof module==='object'&&module.exports)module.exports=exports;
  if(root.document)root.BROOME_SALES_CRM=createWorkspace(root);
})(typeof window==='object'?window:globalThis);
