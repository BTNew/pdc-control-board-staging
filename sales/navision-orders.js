(function(root){
 'use strict';
 const key=s=>String(s||'').replace(/^\uFEFF/,'').toLowerCase().replace(/[^a-z0-9]/g,'');
 function cells(text){
  const sample=String(text).split(/\r?\n/).slice(0,12).join('\n');
  const delimiter=sample.includes('\t')?'\t':sample.split(';').length>sample.split(',').length?';':',';
  const rows=[];let row=[],value='',quoted=false;
  for(let i=0;i<text.length;i++){
   const c=text[i];
   if(c==='"'){if(quoted&&text[i+1]==='"'){value+='"';i++;}else if(!value||quoted)quoted=!quoted;else value+=c;}
   else if(c===delimiter&&!quoted){row.push(value);value='';}
   else if((c==='\r'||c==='\n')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(value);if(row.some(x=>x.trim()))rows.push(row);row=[];value='';}
   else value+=c;
  }
  if(quoted)throw new Error('An export cell has an unclosed quote.');
  row.push(value);if(row.some(x=>x.trim()))rows.push(row);
  return rows;
 }
 function parse(text){
  const rows=cells(String(text));
  const start=rows.findIndex(r=>r.some(c=>key(c)==='order')&&r.some(c=>key(c)==='cosi'));
  if(start<0)throw new Error('Include the Navision headings, including Order, COSI, Dealer and Salesperson.');
  const headers=rows[start].map(key);
  for(const header of ['order','cosi','dealer','salesperson'])if(!headers.includes(header))throw new Error('Missing Navision column: '+header);
  const get=(r,...names)=>{for(const n of names){const i=headers.indexOf(key(n));if(i>=0)return String(r[i]??'').trim();}return '';};
  // 037047 is the exact Broome export alias; preserve all other dealer strings.
  return rows.slice(start+1).map(r=>({dealer_code:get(r,'Dealer')==='037047'?'37047':get(r,'Dealer'),order:get(r,'Order'),cosi:get(r,'COSI'),
   batch:get(r,'Batch','Stock','Stock Number'),consultant:get(r,'Salesperson'),
   client:get(r,'Customer Surname','Dealer Customer Name'),
   vehicle:[get(r,'Model Description','Model'),get(r,'Suffix Description')].filter(Boolean).join(' '),
   colourDescription:get(r,'Colour Description','Colour'),suffixDescription:get(r,'Suffix Description'),trimDescription:get(r,'Trim Description'),
   vin:get(r,'VIN'),prodMth:get(r,'Production Month'),navisionSubLocationDescription:get(r,'Sub Location Description'),
   navisionLocationStatus:get(r,'Location Status'),navisionKewdaleEta:get(r,'ETA At Kewdale Yard'),
   navisionEtaAtDealerBB:get(r,'ETA At Dealer/BB'),navisionPortPlantEta:get(r,'Port/Plant ETA Date'),navisionDealerComments:get(r,'Dealer Comments')
  }));
 }
 const api={parse,cells};if(typeof module==='object'&&module.exports)module.exports=api;if(root)root.BROOME_NAVISION_ORDERS=api;
})(typeof window==='undefined'?null:window);
