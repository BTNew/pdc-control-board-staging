(function(root){
 'use strict';
 /* r495 (F108): recognise a Karratha sales export the same way Broome's sales intake
    recognises Broome (same TSV columns via BROOME_NAVISION_ORDERS.parse). Daily import
    (Kajel) should route only files that match; until go-live those files are held and must
    never be applied as Broome Upload / import_broome_sales_orders. */
 const BROOME_DEALERS=new Set(['37047','037047']);
 const KARRATHA_DEALERS=new Set(['14450','014450']);
 const SUBJECT_RE=/\bkarratha\b.*\b(sales|navision|toyota|export)\b|\b(sales|navision|toyota|export)\b.*\bkarratha\b|\b014450\b/i;
 const FILENAME_RE=/(^|[^a-z])karratha([^a-z]|$)|014450|pilbara[_\-. ]*sales|sales[_\-. ]*karratha/i;
 const BROOME_SUBJECT_RE=/\bbroome\b.*\b(sales|navision|toyota|export)\b|\b(sales|navision|toyota|export)\b.*\bbroome\b|\b037047\b/i;
 const BROOME_FILENAME_RE=/(^|[^a-z])broome([^a-z]|$)|037047|broome[_\-. ]*sales|sales[_\-. ]*broome/i;

 function canonicalDealer(value){
  const raw=String(value||'').trim(),stripped=raw.replace(/^0+/,'')||'0';
  if(raw==='037047'||stripped==='37047')return '37047';
  if(raw==='014450'||stripped==='14450')return '14450';
  return stripped;
 }
 function parseText(text,host){
  const parser=(host&&host.BROOME_NAVISION_ORDERS)||(typeof require==='function'?require('./navision-orders.js'):null);
  if(!parser||typeof parser.parse!=='function')throw new Error('Navision sales parser is unavailable.');
  /* Same Broome parser/format; map the Karratha export alias 014450 -> 14450 here (Broome maps 037047 -> 37047 in the parser). */
  return parser.parse(text).map(r=>{const d=canonicalDealer(r.dealer_code);return d===r.dealer_code?r:{...r,dealer_code:d};});
 }
 function dealerSet(rows){
  return new Set(rows.map(r=>canonicalDealer(r.dealer_code)));
 }
 function recognise({subject='',fileName='',text=''}={},host){
  const reasons=[];
  let rows=null,dealers=null;
  if(text&&String(text).trim()){
   try{
    rows=parseText(text,host);
    dealers=dealerSet(rows);
    const onlyK=dealers.size>0&&[...dealers].every(d=>d==='14450');
    const onlyB=dealers.size>0&&[...dealers].every(d=>d==='37047');
    if(onlyK)reasons.push('dealer_column_14450');
    if(onlyB)reasons.push('dealer_column_37047');
    if(dealers.has('14450')&&dealers.has('37047'))reasons.push('mixed_broome_and_karratha_dealers');
   }catch(err){reasons.push('parse_failed:'+String(err.message||err));}
  }
  if(SUBJECT_RE.test(subject||''))reasons.push('subject_karratha');
  if(FILENAME_RE.test(fileName||''))reasons.push('filename_karratha');
  if(BROOME_SUBJECT_RE.test(subject||''))reasons.push('subject_broome');
  if(BROOME_FILENAME_RE.test(fileName||''))reasons.push('filename_broome');

  const karrathaHints=reasons.some(r=>r==='dealer_column_14450'||r==='subject_karratha'||r==='filename_karratha');
  const broomeHints=reasons.some(r=>r==='dealer_column_37047'||r==='subject_broome'||r==='filename_broome');
  const mixed=reasons.includes('mixed_broome_and_karratha_dealers');
  let kind='other';
  if(reasons.includes('dealer_column_14450')&&!mixed)kind='karratha_sales';
  else if(reasons.includes('dealer_column_37047')&&!mixed)kind='broome_sales';
  else if(karrathaHints&&!broomeHints)kind='karratha_sales';
  else if(broomeHints&&!karrathaHints)kind='broome_sales';

  return {
   kind,
   reasons,
   rowCount:rows?rows.length:0,
   dealers:dealers?[...dealers]:[],
   /* Daily import must use Pilbara Upload / dealer 14450 for Karratha. Never Broome Upload. */
   uploadProfile:kind==='karratha_sales'?'pilbara':kind==='broome_sales'?'broome':null,
   goesIntoBroomeSales:false,
   goesIntoKarrathaSales:kind==='karratha_sales'
  };
 }
 function assertKarrathaOnly(rows){
  if(!Array.isArray(rows)||!rows.length)throw new Error('A Karratha Toyota dealer 14450 export is required');
  for(const row of rows){
   if(canonicalDealer(row.dealer_code)!=='14450')throw new Error('A Karratha Toyota dealer 14450 export is required');
  }
  return rows.map(r=>({...r,dealer_code:'14450'}));
 }
 function createImporter(host){
  const identity=()=>[host.PDC_AUTH_CONTEXT?.userId||host.PDC_AUTH_CONTEXT?.user_id||'',host.PDC_AUTH_CONTEXT?.email||'',host.PDC_AUTH_CONTEXT?.role||''].map(v=>String(v).trim().toLowerCase()).join('|');
  function allowed(){return host.PDC_SUPABASE_CONFIG?.projectRef==='cdsmnqxtyyoeoznmbidd'&&String(host.PDC_AUTH_CONTEXT?.role||'').trim().toLowerCase()==='administrator'&&!!(host.PDC_AUTH_CONTEXT?.userId||host.PDC_AUTH_CONTEXT?.user_id)&&!!host.PDC_SUPABASE?.rpc;}
  function parse(text){return assertKarrathaOnly(parseText(text,host));}
  function checkResult(data,applied){
   if(!data||data.applied!==applied||!['accepted','without_stock','skipped_unsold','changed','visibility_updates'].every(k=>Number.isSafeInteger(data[k])&&data[k]>=0))throw new Error('The Karratha import result could not be checked.');
   return data;
  }
  async function preview(text){
   if(!allowed())throw new Error('Administrator access is required for Karratha sales order uploads.');
   const authorityIdentity=identity(),rows=parse(text);
   /* Mirror Broome's import_broome_sales_orders. The RPC is prepared with the r495 migration;
      until it is applied, preview refuses rather than writing Broome or shared operational data. */
   const rpc=host.PDC_SUPABASE.rpc;
   const {data,error}=await rpc('import_karratha_sales_orders',{p_rows:rows,p_apply:false});
   if(!allowed()||authorityIdentity!==identity())return null;
   if(error)throw new Error(error.message||'Karratha order preview failed.');
   checkResult(data,false);
   return {route:'karratha_sales_orders',dealerCode:'14450',rows,previewData:data,authorityIdentity,rowFingerprint:JSON.stringify(rows)};
  }
  async function apply(pending){
   if(!allowed()||pending?.route!=='karratha_sales_orders'||pending.authorityIdentity!==identity())throw new Error('Karratha import access changed. Preview the file again.');
   if(pending.rowFingerprint!==JSON.stringify(pending.rows))throw new Error('The reviewed order rows changed. Preview the file again.');
   const authorityIdentity=identity();
   const {data,error}=await host.PDC_SUPABASE.rpc('import_karratha_sales_orders',{p_rows:pending.rows,p_apply:true});
   if(!allowed()||authorityIdentity!==identity())return null;
   if(error)throw new Error(error.message||'Karratha order import could not be confirmed. Keep this preview and retry the same file.');
   checkResult(data,true);return data;
  }
  return {allowed,parse,preview,apply,recognise:(meta)=>recognise(meta,host)};
 }
 const api={recognise,canonicalDealer,createImporter,SUBJECT_RE,FILENAME_RE};
 if(typeof module==='object'&&module.exports)module.exports=api;
 if(root){root.KARRATHA_SALES_IMPORT=api;if(root.document)root.KARRATHA_NAVISION_IMPORT=createImporter(root);}
})(typeof window==='object'?window:null);
