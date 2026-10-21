(function(root){
  'use strict';
  // r392: sales-side accessory / PO lines from the Broome Sales "Results" export and the derived
  // Build / Tint / Tray ticks. Read-only: data comes from get_broome_sales_accessories; manual ticks stay in sales.js.
  const salespeople=new Set(['BG','AW','PM','CW']);
  const groups=[['build','Build'],['tray','Tray'],['tint','Tint'],['admin','Admin']];
  const tickGroups={tint:'tint',build_po:'build',tray_ordered:'tray'};
  const derivedStates=new Set(['green','grey','red','review']);
  const delayStates=new Set(['none','delayed','lifted']);
  const liftedMessage='Vehicle is at yard hold, delay removed, please raise the PO';
  const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const orderKey=value=>String(value??'').trim().toUpperCase();
  const sameSource=(record,row)=>Boolean(record?.navision_record_id&&row?.navision_record_id)&&record.navision_record_id===row.navision_record_id;
  function eligibleRows(rows,selected='') {
    return (Array.isArray(rows)?rows:[]).filter(row=>row&&salespeople.has(row.salesperson_code)&&
      (row.cosi===true||/^(?:yes|true|1)$/i.test(String(row.cosi??'').trim()))&&row.source_current!==false&&
      row.sales_hidden!==true&&row.identity_conflict!==true&&row.tracking_id&&orderKey(row.order)&&(!selected||row.salesperson_code===selected));
  }
  const text=value=>typeof value==='string'?value:value==null?'':String(value);
  function normaliseRecord(record) {
    if(!record||typeof record!=='object'||Array.isArray(record)||!Array.isArray(record.lines)||!record.derived||typeof record.derived!=='object')throw new Error('Invalid accessory record.');
    const derived={};
    for(const group of ['build','tint','tray']) {
      const state=record.derived[group]?.state;
      if(!derivedStates.has(state))throw new Error('Invalid accessory tick.');
      derived[group]={state,reason:text(record.derived[group].reason)};
    }
    const lines=record.lines.map(line=>{
      if(!line||typeof line!=='object'||!groups.some(([key])=>key===line.group))throw new Error('Invalid accessory line.');
      return {group:line.group,line:text(line.line),item:text(line.item),type:text(line.type),sublet:text(line.sublet),po:text(line.po),
        po_state:text(line.po_state),notes:text(line.notes),in_house:line.in_house===true,
        // r418: export line identity and "Delay until yard hold" state from the server (none / delayed / lifted).
        line_key:/^[0-9a-f]{64}$/.test(text(line.line_key))?text(line.line_key):'',delay:delayStates.has(line.delay)?line.delay:'none'};
    });
    return {tracking_id:text(record.tracking_id),navision_record_id:text(record.navision_record_id),order:text(record.order),stock:text(record.stock),
      quote:text(record.quote),source_file:text(record.source_file),snapshot_at:record.snapshot_at||null,derived,lines,
      at_or_past_yard_hold:record.at_or_past_yard_hold===true,delay_lifted_lines:Number.isInteger(record.delay_lifted_lines)&&record.delay_lifted_lines>0?record.delay_lifted_lines:0};
  }
  // r427 (F40): the yard hold stage order, the same as the server's accessory_yard_hold_reached. Board (PMB) locations run
  // IT, YH, PMB, PIT, QC, RFT, Completed, Collected; Navision location codes run blank (production), IT (transit),
  // Y? (at the Toyota WA yard: YH, YN, YR, YW), O? (out of the yard: OD despatched / at body builder / at dealer, OC consignment).
  // Rank 2 or more is at or past yard hold. The Toyota status text covers a blank or unknown code.
  const pmbStages=['IT','YH','PMB','PIT','QC','RFT','COMPLETED','COLLECTED'];
  function yardHoldStageRank(locationStatus,toyotaStatus) {
    const code=text(locationStatus).trim().toUpperCase(),status=text(toyotaStatus).toLowerCase();
    const byCode=code==='IT'?1:/^Y[A-Z]$/.test(code)?2:/^O[A-Z]$/.test(code)?3:0;
    const byText=/delivered|at dealer|body builder|consignment|ready for transport|ready for despatch|ready for dispatch|despatch|dispatch/.test(status)?3:
      /yard hold|waiting pd|waiting for wholesale|\byh\b/.test(status)?2:/in transit|wharf|shipment/.test(status)?1:0;
    return Math.max(byCode,byText);
  }
  function atOrPastYardHold(row) {
    if(!row||typeof row!=='object')return false;
    if(pmbStages.indexOf(text(row.pmb_location).trim().toUpperCase())>=1)return true;
    if(['pmb_arrival_date','qc_completed_at','rft_transferred_at','collected_at','dealer_delivered_date'].some(key=>text(row[key]).trim()))return true;
    return yardHoldStageRank(row.location_status,row.toyota_status)>=2;
  }
  const emptySentence='No accessory lines in the latest sales export.';
  // Same classification as the r394 derived ticks: blank is red, unrecognised text is amber review, a PO or C&S ONLY / SELL ONLY / NO UPDATE is green.
  // r418: a Not raised line delayed until yard hold is amber "Delayed – yard hold" (never red) until the server lifts it.
  function poTone(line) {
    const po=line.po.trim();
    if(!po||line.po_state==='blank')return line.delay==='delayed'?'delayed':'red';
    if(line.po_state==='other')return 'review';
    return 'green';
  }
  function poLabel(line){const tone=poTone(line);return tone==='red'?'Not raised':tone==='delayed'?'Delayed – yard hold':line.po.trim();}
  // The tick box shows on Not raised lines while the vehicle is before yard hold (and on delayed lines, to untick).
  // r427: never at or past yard hold, delayed or not: the delay has lifted and the PO is due.
  function delayHtml(line,view) {
    if(!view?.tracking_id||!line.line_key||line.delay==='lifted')return '';
    const tone=poTone(line);if(tone!=='red'&&tone!=='delayed')return '';
    if(view.at_or_past_yard_hold)return '';
    const key=view.tracking_id+'|'+line.line_key,busy=view.busy?.has?.(key),message=view.messages?.get?.(key);
    return '<label class="sales-notes-delay"><input type="checkbox" data-accessory-delay="'+escapeHtml(line.line_key)+'" data-accessory-vehicle="'+escapeHtml(view.tracking_id)+'"'+
      (line.delay==='delayed'?' checked':'')+(busy||view.editable===false?' disabled':'')+'><span>'+(busy?'Saving…':'Delay until yard hold')+'</span></label>'+
      (message?'<small class="sales-notes-delay-error" role="alert">'+escapeHtml(message)+'</small>':'');
  }
  function lineHtml(line,view) {
    const note=line.notes.trim();
    return '<div class="sales-notes-accessory-line"><div class="sales-notes-accessory-item"><span>'+escapeHtml(line.item)+'</span>'+(note?'<small class="sales-notes-accessory-note">'+escapeHtml(note)+'</small>':'')+
      (line.delay==='lifted'&&poTone(line)==='red'?'<small class="sales-notes-delay-lifted" role="alert">'+liftedMessage+'</small>':'')+delayHtml(line,view)+
      '</div><div class="sales-notes-accessory-po sales-notes-po-'+poTone(line)+'">'+escapeHtml(poLabel(line))+'</div></div>';
  }
  // r417: every accessory type (accessory, aftermarket, miscacc, special, other) is one list grouped by PO; Admin stays separate.
  // r416: lines that share a PO sit together. PO numbers first in ascending order, then other raised
  // values (C&S ONLY, SELL ONLY, NO UPDATE, review text) A to Z, and every Not raised line last. A stable sort keeps the
  // export order inside each group. Display only: no line, PO, tick or note changes.
  const poCollator=new Intl.Collator('en',{numeric:true,sensitivity:'base'});
  // r418: delayed lines form their own group after Not raised.
  function poGroupKey(line){const tone=poTone(line);return tone==='red'?'':tone==='delayed'?'delayed':line.po.trim().replace(/\s+/g,' ').toUpperCase();}
  function poRank(line){const tone=poTone(line);return tone==='red'?2:tone==='delayed'?3:line.po_state==='po'||/^PO\d/i.test(line.po.trim())?0:1;}
  function poGroups(lines) {
    const groups=new Map();
    lines.forEach((line,index)=>{
      const key=poGroupKey(line);
      if(!groups.has(key))groups.set(key,{key,rank:poRank(line),label:poLabel(line),first:index,lines:[]});
      const group=groups.get(key);group.rank=Math.min(group.rank,poRank(line));group.lines.push(line);
    });
    return [...groups.values()].sort((a,b)=>a.rank-b.rank||(a.rank>=2?0:poCollator.compare(a.key,b.key))||a.first-b.first);
  }
  const groupLabel=group=>group.rank===2?'Not raised':group.rank===3?'Delayed – yard hold':group.label;
  const groupId=group=>group.rank===2?'not-raised':group.rank===3?'delayed':group.key;
  function groupedLinesHtml(lines,alwaysLabel=false,view=null) {
    const groups=poGroups(lines);
    // The combined list always names its PO groups. In Admin a label only helps when there is more than one group.
    const linesHtml=group=>group.lines.map(line=>lineHtml(line,view)).join('');
    if(groups.length<2&&!alwaysLabel)return groups.map(linesHtml).join('');
    return groups.map(group=>'<div class="sales-notes-po-group-head" data-po-group="'+escapeHtml(groupId(group))+'">'+
      escapeHtml(groupLabel(group)+' · '+group.lines.length+' line'+(group.lines.length===1?'':'s'))+'</div>'+linesHtml(group)).join('');
  }
  function notesLinesHtml(record,view=null) {
    // r427: at or past yard hold by the server or by this row's own stage, a stored delay reads lifted (red, raise the PO).
    const past=record?.at_or_past_yard_hold===true||view?.row_past_yard_hold===true;
    view=view?{...view,tracking_id:record?.tracking_id||'',at_or_past_yard_hold:past}:null;
    const lines=(Array.isArray(record?.lines)?record.lines:[]).map(line=>past&&line.delay==='delayed'?{...line,delay:'lifted'}:line);
    const admin=lines.filter(line=>line.group==='admin'),rest=lines.filter(line=>line.group!=='admin');
    if(!rest.length&&!admin.length)return '<section class="sales-notes-accessories" aria-label="Accessory lines"><p class="sales-notes-accessory-empty">'+emptySentence+'</p></section>';
    let html='';
    if(rest.length)html+='<section class="sales-notes-accessory-type sales-notes-po-list" data-po-list="accessories">'+groupedLinesHtml(rest,true,view)+'</section>';
    // r417: Admin (Pit and Weigh, Transport...) is always visible under a plain heading; no collapsible boxes in the order dropdown.
    if(admin.length)html+='<section class="sales-notes-accessory-type sales-notes-admin-list" data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · '+admin.length+' line'+(admin.length===1?'':'s')+'</h3>'+groupedLinesHtml(admin,false,view)+'</section>';
    return '<section class="sales-notes-accessories" aria-label="Accessory lines">'+html+'</section>';
  }
  function createSalesAccessories(host) {
    let options,records=new Map(),epoch=0,request=0,identity='',readStatus='idle';
    const delayBusy=new Set(),delayMessages=new Map();
    const context=()=>options?.getContext?.();
    const currentIdentity=()=>JSON.stringify([host.PDC_AUTH_CONTEXT?.userId||null,options?.getToken?.()??null,context()?.role||null,context()?.salesperson_code||null]);
    // The dashboard salesperson filter is a view, not a cache key. Ticks stay for every vehicle this user may see.
    const rows=()=>{
      const ctx=context(),owner=ctx?.role==='salesperson'?String(ctx.salesperson_code||'').trim().toUpperCase():'';
      if(ctx?.role==='salesperson'&&!salespeople.has(owner))return [];
      return eligibleRows(options?.getRows?.()||[],'').filter(row=>!owner||row.salesperson_code===owner);
    };
    function clear(){epoch++;request++;records.clear();delayBusy.clear();delayMessages.clear();identity=currentIdentity();readStatus='idle';}
    function syncScope() {
      if(!host.PDC_AUTH_CONTEXT?.userId||!['administrator','salesperson'].includes(context()?.role)){clear();return false;}
      if(identity!==currentIdentity())clear();
      const permitted=new Map(rows().map(row=>[row.tracking_id,row]));
      for(const [id,record] of records)if(!permitted.has(id)||orderKey(record.order)!==orderKey(permitted.get(id).order)||!sameSource(record,permitted.get(id)))records.delete(id);
      return true;
    }
    function recordFor(row) {
      if(!row||!syncScope())return null;
      const record=records.get(row.tracking_id);
      return record&&orderKey(record.order)===orderKey(row.order)&&sameSource(record,row)?record:null;
    }
    // The Build/Tray/Tint line table used to render in the stock detail. Lines now render only in the notes panel.
    function detailHtml(){return '';}
    function notesPanelHtml(row,settings={}) {
      if(!row||!syncScope())return '';
      const record=recordFor(row);
      if(record)return notesLinesHtml(record,{editable:settings.editable!==false,busy:delayBusy,messages:delayMessages,row_past_yard_hold:atOrPastYardHold(row)});
      return readStatus==='ready'?'<section class="sales-notes-accessories" aria-label="Accessory lines"><p class="sales-notes-accessory-empty">'+emptySentence+'</p></section>':'';
    }
    // r394: the derived tick is the only state shown for TINT / BUILD / TRAY; manual values are ignored.
    // null when this vehicle has no sales export lines (shown grey by sales.js).
    function tickFor(row,key) {
      const group=tickGroups[key];if(!group)return null;
      const record=recordFor(row);
      if(!record)return null;
      // r427: a tick held amber only by delays turns red once this row is at or past yard hold.
      const tick=record.derived[group];
      return tick.reason==='delayed_until_yard_hold'&&atOrPastYardHold(row)?{state:'red',reason:'po_not_raised'}:tick;
    }
    // r418: tick / untick "Delay until yard hold". The server checks access, the line and yard hold; the list re-reads after.
    async function setDelay(trackingId,lineKey,delayed) {
      const row=rows().find(item=>item.tracking_id===trackingId),record=row&&recordFor(row);
      const line=record?.lines.find(item=>item.line_key===lineKey),key=trackingId+'|'+lineKey;
      if(!line||delayBusy.has(key))return;
      // r427: no new delay at or past yard hold (the server refuses it too).
      if(delayed&&(record.at_or_past_yard_hold||atOrPastYardHold(row))){delayMessages.set(key,liftedMessage);options?.onUpdate?.();return;}
      const generation=epoch,owner=currentIdentity();
      delayBusy.add(key);delayMessages.delete(key);options?.onUpdate?.();
      try {
        const {data,error}=await host.PDC_SUPABASE.rpc('set_broome_sales_accessory_delay',{p_tracking_id:trackingId,p_line_key:lineKey,p_delayed:delayed});
        if(generation!==epoch||owner!==currentIdentity())return;
        if(error)throw error;
        if(data?.tracking_id!==trackingId||data?.line_key!==lineKey||data?.delayed!==delayed)throw new Error('The change could not be confirmed. Reload to check it.');
      }catch(error){if(generation===epoch&&owner===currentIdentity())delayMessages.set(key,error?.message||'The delay could not be saved.');}
      finally{if(generation===epoch&&owner===currentIdentity()){delayBusy.delete(key);await refresh();}}
    }
    function rowFlagHtml(row) {
      const record=row&&recordFor(row);
      if(!record)return '';
      const lifted=record.delay_lifted_lines||(atOrPastYardHold(row)?record.lines.filter(line=>line.delay==='delayed'&&(!line.po.trim()||line.po_state==='blank')).length:0);
      if(!lifted)return '';
      return '<span class="sales-yard-hold-flag" role="status" title="'+escapeHtml(liftedMessage)+'">Raise PO · at yard hold</span>';
    }
    async function refresh() {
      if(!syncScope())return;
      const generation=epoch,owner=currentIdentity(),sequence=++request;
      const stale=()=>!syncScope()||generation!==epoch||owner!==currentIdentity()||sequence!==request;
      try {
        const {data,error}=await host.PDC_SUPABASE.rpc('get_broome_sales_accessories');
        if(stale())return;
        if(error||!Array.isArray(data?.items)||data.context?.role!==context()?.role)throw new Error('Accessory lines could not be checked.');
        const current=new Map(rows().map(row=>[row.tracking_id,row])),next=new Map();
        for(const candidate of data.items) {
          const row=current.get(candidate?.tracking_id);
          if(!row||orderKey(candidate.order)!==orderKey(row.order)||!sameSource(candidate,row))continue;
          if(next.has(row.tracking_id))throw new Error('Accessory lines have an ambiguous order link.');
          next.set(row.tracking_id,normaliseRecord(candidate));
        }
        records=next;readStatus='ready';
      }catch(error){if(stale())return;records.clear();readStatus='error';}
      options?.onUpdate?.();
    }
    function init(settings) {
      options=settings;clear();
      host.addEventListener?.('pdc-auth-locked',clear);host.addEventListener?.('pdc-auth-failed',clear);
      host.addEventListener?.('pdc-auth-ready',()=>{if(identity!==currentIdentity())clear();});
      host.document?.addEventListener?.('change',event=>{
        const box=event.target?.closest?.('[data-accessory-delay]');if(!box)return;
        const delayed=box.checked===true;box.checked=!delayed;// shown from the server's answer, never optimistically
        void setDelay(box.dataset.accessoryVehicle,box.dataset.accessoryDelay,delayed);
      });
      return api;
    }
    const api={init,clear,syncScope,refresh,detailHtml,notesPanelHtml,tickFor,recordFor,setDelay,rowFlagHtml};
    return api;
  }
  const exports={escapeHtml,normaliseRecord,notesLinesHtml,poGroups,eligibleRows,createSalesAccessories,liftedMessage,atOrPastYardHold,yardHoldStageRank};
  if(typeof module==='object'&&module.exports)module.exports=exports;
  if(root.document)root.BROOME_SALES_ACCESSORIES=createSalesAccessories(root);
})(typeof window==='object'?window:globalThis);
