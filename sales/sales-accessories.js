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
  function snapshotDate(value) {
    const date=new Date(value||'');
    return Number.isFinite(date.getTime())?date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'}):'Date not recorded';
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
  function poCell(line) {
    if(line.po_state==='blank')return line.group==='admin'?'<span class="sales-accessory-po-none">—</span>':
      '<span class="sales-accessory-po-missing">Not raised</span>'+(line.in_house?' <small class="sales-accessory-in-house">In-house</small>':'');
    return escapeHtml(line.po);
  }
  function tableHtml(lines) {
    return '<div class="sales-accessory-table-wrap"><table class="sales-accessory-table"><thead><tr><th scope="col">Line</th><th scope="col">Item</th><th scope="col">Type</th><th scope="col">Sublet</th><th scope="col">PO #</th><th scope="col">Notes</th></tr></thead><tbody>'+
      lines.map(line=>'<tr><td>'+escapeHtml(line.line)+'</td><td class="sales-accessory-item">'+escapeHtml(line.item)+'</td><td>'+escapeHtml(line.type)+'</td><td>'+escapeHtml(line.sublet)+'</td><td>'+poCell(line)+'</td><td class="sales-accessory-notes">'+escapeHtml(line.notes)+'</td></tr>').join('')+'</tbody></table></div>';
  }
  const stateLabel={green:'PO raised or not needed',grey:'Not on quote',red:'PO not raised',review:'Check PO text'};
  function recordHtml(record) {
    let html='<h3>Accessory and PO lines</h3>';
    for(const [key,label] of groups) {
      const lines=record.lines.filter(line=>line.group===key);
      if(!lines.length)continue;
      const tick=record.derived[key];
      const heading=escapeHtml(label)+' · '+lines.length+' line'+(lines.length===1?'':'s')+(tick?' · <span class="sales-accessory-state '+tick.state+'">'+escapeHtml(stateLabel[tick.state])+'</span>':'');
      if(key==='admin')html+='<details class="sales-accessory-admin"><summary>'+heading+'</summary>'+tableHtml(lines)+'</details>';
      else html+='<section class="sales-accessory-group" data-accessory-group="'+key+'"><h4>'+heading+'</h4>'+tableHtml(lines)+'</section>';
    }
    if(!record.lines.length)html+='<p class="sales-build-empty">The latest sales export listed no accessory lines for this vehicle.</p>';
    return html+'<p class="sales-build-provenance">'+escapeHtml(record.source_file||'Sales export')+' · Quote '+escapeHtml(record.quote||'not recorded')+' · Extracted '+escapeHtml(snapshotDate(record.snapshot_at))+'</p>';
  }
  function createSalesAccessories(host) {
    let options,records=new Map(),epoch=0,request=0,identity='',scope='';
    const context=()=>options?.getContext?.();
    const currentIdentity=()=>JSON.stringify([host.PDC_AUTH_CONTEXT?.userId||null,options?.getToken?.()??null,context()?.role||null,context()?.salesperson_code||null]);
    const currentScope=()=>options?.getSalesperson?.()||'';
    const rows=()=>{
      const ctx=context(),owner=ctx?.role==='salesperson'?String(ctx.salesperson_code||'').trim().toUpperCase():'';
      if(ctx?.role==='salesperson'&&!salespeople.has(owner))return [];
      return eligibleRows(options?.getRows?.()||[],currentScope()).filter(row=>!owner||row.salesperson_code===owner);
    };
    function clear(){epoch++;request++;records.clear();identity=currentIdentity();scope=currentScope();}
    function syncScope() {
      if(!host.PDC_AUTH_CONTEXT?.userId||!['administrator','salesperson'].includes(context()?.role)){clear();return false;}
      if(identity!==currentIdentity()||scope!==currentScope())clear();
      const permitted=new Map(rows().map(row=>[row.tracking_id,row]));
      for(const [id,record] of records)if(!permitted.has(id)||orderKey(record.order)!==orderKey(permitted.get(id).order)||!sameSource(record,permitted.get(id)))records.delete(id);
      return true;
    }
    function recordFor(row) {
      if(!row||!syncScope())return null;
      const record=records.get(row.tracking_id);
      return record&&orderKey(record.order)===orderKey(row.order)&&sameSource(record,row)?record:null;
    }
    function detailHtml(row){const record=recordFor(row);return record?recordHtml(record):'';}
    // r394: the derived tick is the only state shown for TINT / BUILD / TRAY; manual values are ignored.
    // null when this vehicle has no sales export lines (shown grey by sales.js).
    function tickFor(row,key) {
      const group=tickGroups[key];if(!group)return null;
      const record=recordFor(row);
      return record?record.derived[group]:null;
    }
    async function refresh() {
      if(!syncScope())return;
      const generation=epoch,owner=currentIdentity(),selected=currentScope(),sequence=++request;
      const stale=()=>!syncScope()||generation!==epoch||owner!==currentIdentity()||selected!==currentScope()||sequence!==request;
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
        records=next;
      }catch(error){if(stale())return;records.clear();}
      options?.onUpdate?.();
    }
    function init(settings) {
      options=settings;clear();
      host.addEventListener?.('pdc-auth-locked',clear);host.addEventListener?.('pdc-auth-failed',clear);
      host.addEventListener?.('pdc-auth-ready',()=>{if(identity!==currentIdentity())clear();});
      return api;
    }
    const api={init,clear,syncScope,refresh,detailHtml,tickFor,recordFor};
    return api;
  }
  const exports={escapeHtml,normaliseRecord,recordHtml,tableHtml,eligibleRows,createSalesAccessories};
  if(typeof module==='object'&&module.exports)module.exports=exports;
  if(root.document)root.BROOME_SALES_ACCESSORIES=createSalesAccessories(root);
})(typeof window==='object'?window:globalThis);
