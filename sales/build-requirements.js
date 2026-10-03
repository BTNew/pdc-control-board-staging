(function(root){
  'use strict';
  const salespeople=new Set(['BG','AW','PM','CW']);
  const escapeHtml=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
  const orderKey=value=>String(value??'').trim().toUpperCase();
  const sameSource=(record,row)=>Boolean(record?.navision_record_id&&row?.navision_record_id)&&record.navision_record_id===row.navision_record_id;
  function eligibleRows(rows,selected='') {
    return (Array.isArray(rows)?rows:[]).filter(row=>row&&salespeople.has(row.salesperson_code)&&
      (row.cosi===true||/^(?:yes|true|1)$/i.test(String(row.cosi??'').trim()))&&row.source_current!==false&&
      row.sales_hidden!==true&&row.identity_conflict!==true&&row.tracking_id&&orderKey(row.order)&&(!selected||row.salesperson_code===selected));
  }
  function rowLabel(rows) {
    const valid=[...new Set((Array.isArray(rows)?rows:[]).filter(row=>Number.isSafeInteger(row)&&row>0))];
    return valid.length?(valid.length===1?'Source row ':'Source rows ')+valid.join(', '):'';
  }
  function importedDate(value) {
    if(!value)return 'Date not recorded';
    const date=new Date(value);
    return Number.isFinite(date.getTime())?date.toLocaleString('en-AU',{timeZone:'Australia/Perth',dateStyle:'medium',timeStyle:'short'}):'Date not recorded';
  }
  function filename(value) {return String(value??'').replace(/\\/g,'/').split('/').pop()||'Sales export';}
  function metadata(item,includeQuote=true) {
    const text=[includeQuote&&item.quote_number?'Quote '+item.quote_number:'',rowLabel(item.source_rows)].filter(Boolean).join(' · ');
    return text?'<small class="sales-build-source-row">'+escapeHtml(text)+'</small>':'';
  }
  function recordContent(record) {
    const items=Array.isArray(record.items)?record.items:[],notes=Array.isArray(record.notes)?record.notes:[],other=Array.isArray(record.other_lines)?record.other_lines:[];
    let html='';
    if(items.length)html+='<h3>Accessory requirements</h3><ul class="sales-build-list">'+items.map(item=>'<li><span class="sales-build-marker" aria-hidden="true">•</span><div><strong>'+escapeHtml(item.description)+'</strong>'+metadata(item)+'</div></li>').join('')+'</ul>';
    if(notes.length)html+='<h3>Sales export notes</h3><div class="sales-build-notes">'+notes.map(note=>'<article><p>'+escapeHtml(note.text)+'</p>'+metadata(note,false)+'</article>').join('')+'</div>';
    if(!items.length&&!notes.length)html+='<p class="sales-build-empty">This import recorded no accessory requirements or sales notes for this vehicle.</p>';
    if(other.length)html+='<details class="sales-build-other"><summary>Other quote items to review ('+other.length+')</summary><ul class="sales-build-list">'+other.map(item=>'<li><span class="sales-build-marker" aria-hidden="true">•</span><div><strong>'+escapeHtml(item.description)+'</strong>'+(item.reason?'<p class="sales-build-review-reason">'+escapeHtml(item.reason)+'</p>':'')+metadata(item,false)+'</div></li>').join('')+'</ul></details>';
    const sourceStock=record.source_stock?' · Imported stock '+record.source_stock:'';
    return html+'<p class="sales-build-provenance">'+escapeHtml(filename(record.source_file))+' · Imported '+escapeHtml(importedDate(record.imported_at))+escapeHtml(sourceStock)+'</p>';
  }
  function normaliseRecord(record) {
    if(!record||typeof record!=='object'||Array.isArray(record))throw new Error('Invalid imported requirements record.');
    const result={tracking_id:String(record.tracking_id??''),navision_record_id:String(record.navision_record_id??''),order:String(record.order??''),stock:String(record.stock??''),
      source_file:String(record.source_file??''),imported_at:record.imported_at||null,source_stock:String(record.source_stock??'')};
    for(const key of ['items','notes','other_lines']) {
      if(!Array.isArray(record[key]))throw new Error('Imported requirements are incomplete.');
      result[key]=record[key].map(item=>{
        if(!item||typeof item!=='object'||Array.isArray(item))throw new Error('Imported requirements are incomplete.');
        const textKey=key==='notes'?'text':'description';
        if(typeof item[textKey]!=='string')throw new Error('Imported requirements are incomplete.');
        const clean={[textKey]:item[textKey],source_rows:Array.isArray(item.source_rows)?item.source_rows.filter(row=>Number.isSafeInteger(row)&&row>0):[]};
        if(key==='items')clean.quote_number=String(item.quote_number??'');
        if(key==='other_lines')clean.reason=String(item.reason??'');
        return clean;
      }).filter(item=>String(item[key==='notes'?'text':'description']).trim());
    }
    return result;
  }
  function createBuildRequirements(host) {
    let options,records=new Map(),mode='idle',epoch=0,request=0,identity='',scope='',detailId=null,lastContent='',lastSummary='';
    const $=id=>host.document?.getElementById(id);
    const context=()=>options?.getContext?.();
    const currentIdentity=()=>JSON.stringify([host.PDC_AUTH_CONTEXT?.userId||null,options?.getToken?.()??null,context()?.role||null,context()?.salesperson_code||null]);
    const currentScope=()=>options?.getSalesperson?.()||'';
    const rows=()=> {
      const ctx=context(),owner=ctx?.role==='salesperson'?String(ctx.salesperson_code||'').trim().toUpperCase():'';
      if(ctx?.role==='salesperson'&&!salespeople.has(owner))return [];
      return eligibleRows(options?.getRows?.()||[],currentScope()).filter(row=>!owner||row.salesperson_code===owner);
    };
    const rowFor=id=>rows().find(row=>row.tracking_id===id);
    function hideDetail() {
      detailId=null;lastContent='';lastSummary='';
      const panel=$('sales-build-requirements');if(panel){panel.hidden=true;panel.open=false;}
      if($('sales-build-content'))$('sales-build-content').innerHTML='';
      if($('sales-build-summary'))$('sales-build-summary').textContent='Accessories and sales notes';
    }
    function clear() {epoch++;request++;records.clear();mode='idle';identity=currentIdentity();scope=currentScope();hideDetail();}
    function syncScope() {
      if(!host.PDC_AUTH_CONTEXT?.userId||!['administrator','salesperson'].includes(context()?.role)){clear();return false;}
      if(identity!==currentIdentity()||scope!==currentScope())clear();
      const permitted=new Map(rows().map(row=>[row.tracking_id,row]));
      for(const [id,record] of records)if(!permitted.has(id)||orderKey(record.order)!==orderKey(permitted.get(id).order)||!sameSource(record,permitted.get(id))) {
        records.delete(id);
        if(id===detailId&&permitted.has(id)) {
          mode='idle';lastContent='';lastSummary='';
          if($('sales-build-content'))$('sales-build-content').innerHTML='<p class="sales-build-loading" role="status">Loading accessories and sales notes…</p>';
          if($('sales-build-summary'))$('sales-build-summary').textContent='Accessories and sales notes';
        }
      }
      if(detailId&&!permitted.has(detailId))hideDetail();
      return true;
    }
    function body(row) {
      const record=records.get(row.tracking_id);
      if(mode==='error')return '<p class="sales-build-error" role="status">Accessories and sales notes could not be loaded. Refresh vehicles to try again.</p>';
      if(record)return (mode==='loading'?'<p class="sales-build-loading" role="status">Checking for updates…</p>':'')+recordContent(record);
      if(mode==='idle'||mode==='loading')return '<p class="sales-build-loading" role="status">Loading accessories and sales notes…</p>';
      return '<p class="sales-build-empty">No accessory requirements or sales notes have been imported for this vehicle.</p>';
    }
    function summary(row) {
      const record=records.get(row.tracking_id),count=record?.items.length||0;
      return 'Accessories and sales notes'+(count?' · '+count+' item'+(count===1?'':'s'):'');
    }
    function detailHtml(row) {
      if(!syncScope()||!rowFor(row?.tracking_id))return '';
      const current=rowFor(row.tracking_id);
      return '<details id="sales-build-requirements" class="sales-build-requirements"><summary id="sales-build-summary">'+escapeHtml(summary(current))+'</summary><div id="sales-build-content" class="sales-build-content">'+body(current)+'</div></details>';
    }
    function render() {
      if(!syncScope())return;
      const row=rowFor(detailId),panel=$('sales-build-requirements');if(!row||!panel)return;
      panel.hidden=false;
      const text=summary(row),html=body(row),content=$('sales-build-content'),heading=$('sales-build-summary');
      if(heading&&(text!==lastSummary||heading.textContent!==text)){heading.textContent=text;lastSummary=text;}
      if(content&&(html!==lastContent||content.innerHTML==='')) {
        const open=content.querySelector?.('.sales-build-other')?.open===true;
        content.innerHTML=html;if(open&&content.querySelector?.('.sales-build-other'))content.querySelector('.sales-build-other').open=true;
        lastContent=html;
      }
    }
    function bindDetail(id) {
      if(!syncScope()||!rowFor(id))return;
      detailId=id;lastContent='';lastSummary='';render();
      if(mode==='idle')void refresh();
    }
    async function refresh() {
      if(!syncScope())return;
      const generation=epoch,owner=currentIdentity(),selected=currentScope(),sequence=++request;
      mode='loading';render();
      try {
        const {data,error}=await host.PDC_SUPABASE.rpc('get_broome_sales_builds');
        if(!syncScope()||generation!==epoch||owner!==currentIdentity()||selected!==currentScope()||sequence!==request)return;
        if(error||!Array.isArray(data?.items)||!['administrator','salesperson'].includes(data.context?.role)||data.context.role!==context()?.role)throw new Error('Imported requirements could not be checked.');
        const current=new Map(rows().map(row=>[row.tracking_id,row])),next=new Map();
        for(const candidate of data.items) {
          const row=current.get(candidate?.tracking_id);
          if(!row||orderKey(candidate.order)!==orderKey(row.order)||!sameSource(candidate,row))continue;
          const record=normaliseRecord(candidate);
          if(next.has(record.tracking_id))throw new Error('Imported requirements have an ambiguous order link.');
          next.set(record.tracking_id,record);
        }
        records=next;mode='ready';
      }catch(error) {
        if(!syncScope()||generation!==epoch||owner!==currentIdentity()||selected!==currentScope()||sequence!==request)return;
        records.clear();mode='error';
      }
      render();
    }
    function init(settings) {
      options=settings;clear();
      host.addEventListener?.('pdc-auth-locked',clear);host.addEventListener?.('pdc-auth-failed',clear);
      host.addEventListener?.('pdc-auth-ready',()=>{if(identity!==currentIdentity())clear();});
      return api;
    }
    const api={init,clear,syncScope,detailHtml,bindDetail,refresh,render,closeDetail:hideDetail};
    return api;
  }
  const exports={eligibleRows,escapeHtml,orderKey,rowLabel,filename,normaliseRecord,recordContent,createBuildRequirements};
  if(typeof module==='object'&&module.exports)module.exports=exports;
  if(root.document)root.BROOME_SALES_BUILDS=createBuildRequirements(root);
})(typeof window==='object'?window:globalThis);
