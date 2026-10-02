(function(root){
  'use strict';
  function createImporter(host) {
    const identity=()=>[host.PDC_AUTH_CONTEXT?.userId||host.PDC_AUTH_CONTEXT?.user_id||'',host.PDC_AUTH_CONTEXT?.email||'',host.PDC_AUTH_CONTEXT?.role||''].map(v=>String(v).trim().toLowerCase()).join('|');
    function allowed() {return host.PDC_SUPABASE_CONFIG?.projectRef==='cdsmnqxtyyoeoznmbidd'&&String(host.PDC_AUTH_CONTEXT?.role||'').trim().toLowerCase()==='administrator'&&!!(host.PDC_AUTH_CONTEXT?.userId||host.PDC_AUTH_CONTEXT?.user_id)&&!!host.PDC_SUPABASE?.rpc;}
    function parse(text) {
      if(!host.BROOME_NAVISION_ORDERS?.parse)throw new Error('Broome Navision importer is unavailable. Refresh the page.');
      return host.BROOME_NAVISION_ORDERS.parse(text);
    }
    function checkResult(data, applied) {
      if(!data||data.applied!==applied||!['accepted','without_stock','skipped_unsold','changed','visibility_updates'].every(k=>Number.isSafeInteger(data[k])&&data[k]>=0))throw new Error('The Broome import result could not be checked.');
      return data;
    }
    async function preview(text) {
      if(!allowed())throw new Error('Administrator access is required for Broome sales order uploads.');
      const authorityIdentity=identity(),rows=parse(text);
      const {data,error}=await host.PDC_SUPABASE.rpc('import_broome_sales_orders',{p_rows:rows,p_apply:false});
      if(!allowed()||authorityIdentity!==identity())return null;
      if(error)throw new Error(error.message||'Broome order preview failed.');
      checkResult(data,false);
      return {route:'broome_sales_orders',dealerCode:'37047',rows,previewData:data,authorityIdentity,rowFingerprint:JSON.stringify(rows)};
    }
    async function apply(pending) {
      if(!allowed()||pending?.route!=='broome_sales_orders'||pending.authorityIdentity!==identity())throw new Error('Broome import access changed. Preview the file again.');
      if(pending.rowFingerprint!==JSON.stringify(pending.rows))throw new Error('The reviewed order rows changed. Preview the file again.');
      const authorityIdentity=identity();
      const {data,error}=await host.PDC_SUPABASE.rpc('import_broome_sales_orders',{p_rows:pending.rows,p_apply:true});
      if(!allowed()||authorityIdentity!==identity())return null;
      if(error)throw new Error(error.message||'Broome order import could not be confirmed. Keep this preview and retry the same file.');
      checkResult(data,true);return data;
    }
    return {allowed,parse,preview,apply};
  }
  if(typeof module==='object'&&module.exports)module.exports={createImporter};
  if(root?.document)root.BROOME_NAVISION_IMPORT=createImporter(root);
})(typeof window==='object'?window:null);
