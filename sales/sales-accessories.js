(function(root){
  'use strict';
  // r392: sales-side accessory / PO lines from the Broome Sales "Results" export and the derived
  // Build / Tint / Tray ticks. Read-only: data comes from get_broome_sales_accessories; manual ticks stay in sales.js.
  const salespeople=new Set(['BG','AW','PM','CW']);
  const groups=[['build','Build'],['tray','Tray'],['tint','Tint'],['admin','Admin']];
  const tickGroups={tint:'tint',build_po:'build',tray_ordered:'tray'};
  const derivedStates=new Set(['green','grey','red','review']);
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
        po_state:text(line.po_state),notes:text(line.notes),in_house:line.in_house===true};
    });
    return {tracking_id:text(record.tracking_id),navision_record_id:text(record.navision_record_id),order:text(record.order),stock:text(record.stock),
      quote:text(record.quote),source_file:text(record.source_file),snapshot_at:record.snapshot_at||null,derived,lines};
  }
  const emptySentence='No accessory lines in the latest sales export.';
  // Same classification as the r394 derived ticks: blank is red, unrecognised text is amber review, a PO or C&S ONLY / SELL ONLY / NO UPDATE is green.
  function poTone(line) {
    const po=line.po.trim();
    if(!po||line.po_state==='blank')return 'red';
    if(line.po_state==='other')return 'review';
    return 'green';
  }
  function poLabel(line){return poTone(line)==='red'?'Not raised':line.po.trim();}
  function lineHtml(line) {
    const note=line.notes.trim();
    return '<div class="sales-notes-accessory-line"><div class="sales-notes-accessory-item"><span>'+escapeHtml(line.item)+'</span>'+(note?'<small class="sales-notes-accessory-note">'+escapeHtml(note)+'</small>':'')+'</div><div class="sales-notes-accessory-po sales-notes-po-'+poTone(line)+'">'+escapeHtml(poLabel(line))+'</div></div>';
  }
  // r417: every accessory type (accessory, aftermarket, miscacc, special, other) is one list grouped by PO; Admin stays separate.
  // r416: lines that share a PO sit together. PO numbers first in ascending order, then other raised
  // values (C&S ONLY, SELL ONLY, NO UPDATE, review text) A to Z, and every Not raised line last. A stable sort keeps the
  // export order inside each group. Display only: no line, PO, tick or note changes.
  const poCollator=new Intl.Collator('en',{numeric:true,sensitivity:'base'});
  function poGroupKey(line){return poTone(line)==='red'?'':line.po.trim().replace(/\s+/g,' ').toUpperCase();}
  function poRank(line){return poTone(line)==='red'?2:line.po_state==='po'||/^PO\d/i.test(line.po.trim())?0:1;}
  function poGroups(lines) {
    const groups=new Map();
    lines.forEach((line,index)=>{
      const key=poGroupKey(line);
      if(!groups.has(key))groups.set(key,{key,rank:poRank(line),label:poLabel(line),first:index,lines:[]});
      const group=groups.get(key);group.rank=Math.min(group.rank,poRank(line));group.lines.push(line);
    });
    return [...groups.values()].sort((a,b)=>a.rank-b.rank||(a.rank===2?0:poCollator.compare(a.key,b.key))||a.first-b.first);
  }
  function groupedLinesHtml(lines,alwaysLabel=false) {
    const groups=poGroups(lines);
    // The combined list always names its PO groups. In Admin a label only helps when there is more than one group.
    if(groups.length<2&&!alwaysLabel)return groups.map(group=>group.lines.map(lineHtml).join('')).join('');
    return groups.map(group=>'<div class="sales-notes-po-group-head" data-po-group="'+escapeHtml(group.rank===2?'not-raised':group.key)+'">'+
      escapeHtml((group.rank===2?'Not raised':group.label)+' · '+group.lines.length+' line'+(group.lines.length===1?'':'s'))+'</div>'+group.lines.map(lineHtml).join('')).join('');
  }
  function notesLinesHtml(record) {
    const lines=Array.isArray(record?.lines)?record.lines:[];
    const admin=lines.filter(line=>line.group==='admin'),rest=lines.filter(line=>line.group!=='admin');
    if(!rest.length&&!admin.length)return '<section class="sales-notes-accessories" aria-label="Accessory lines"><p class="sales-notes-accessory-empty">'+emptySentence+'</p></section>';
    let html='';
    if(rest.length)html+='<section class="sales-notes-accessory-type sales-notes-po-list" data-po-list="accessories">'+groupedLinesHtml(rest,true)+'</section>';
    // r417: Admin (Pit and Weigh, Transport...) is always visible under a plain heading; no collapsible boxes in the order dropdown.
    if(admin.length)html+='<section class="sales-notes-accessory-type sales-notes-admin-list" data-admin-list="admin"><h3 class="sales-notes-accessory-head">Admin · '+admin.length+' line'+(admin.length===1?'':'s')+'</h3>'+groupedLinesHtml(admin)+'</section>';
    return '<section class="sales-notes-accessories" aria-label="Accessory lines">'+html+'</section>';
  }
  function createSalesAccessories(host) {
    let options,records=new Map(),epoch=0,request=0,identity='',readStatus='idle';
    const context=()=>options?.getContext?.();
    const currentIdentity=()=>JSON.stringify([host.PDC_AUTH_CONTEXT?.userId||null,options?.getToken?.()??null,context()?.role||null,context()?.salesperson_code||null]);
    // The dashboard salesperson filter is a view, not a cache key. Ticks stay for every vehicle this user may see.
    const rows=()=>{
      const ctx=context(),owner=ctx?.role==='salesperson'?String(ctx.salesperson_code||'').trim().toUpperCase():'';
      if(ctx?.role==='salesperson'&&!salespeople.has(owner))return [];
      return eligibleRows(options?.getRows?.()||[],'').filter(row=>!owner||row.salesperson_code===owner);
    };
    function clear(){epoch++;request++;records.clear();identity=currentIdentity();readStatus='idle';}
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
    function notesPanelHtml(row) {
      if(!row||!syncScope())return '';
      const record=recordFor(row);
      if(record)return notesLinesHtml(record);
      return readStatus==='ready'?'<section class="sales-notes-accessories" aria-label="Accessory lines"><p class="sales-notes-accessory-empty">'+emptySentence+'</p></section>':'';
    }
    // r394: the derived tick is the only state shown for TINT / BUILD / TRAY; manual values are ignored.
    // null when this vehicle has no sales export lines (shown grey by sales.js).
    function tickFor(row,key) {
      const group=tickGroups[key];if(!group)return null;
      const record=recordFor(row);
      return record?record.derived[group]:null;
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
      return api;
    }
    const api={init,clear,syncScope,refresh,detailHtml,notesPanelHtml,tickFor,recordFor};
    return api;
  }
  const exports={escapeHtml,normaliseRecord,notesLinesHtml,poGroups,eligibleRows,createSalesAccessories};
  if(typeof module==='object'&&module.exports)module.exports=exports;
  if(root.document)root.BROOME_SALES_ACCESSORIES=createSalesAccessories(root);
})(typeof window==='object'?window:globalThis);
