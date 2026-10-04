(function(root){
 'use strict';
 const key=s=>String(s||'').replace(/^\uFEFF/,'').toLowerCase().replace(/[^a-z0-9]/g,'');
 function salespersonCode(value){
  const raw=String(value||'').trim(),match=raw.match(/^([a-z]{1,4})(?:\s+\d{8})?$/i);
  return match?match[1].toUpperCase():raw;
 }
 function dateValue(value,column,row){
  const raw=String(value||'').trim(),match=raw.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if(!match)return raw;
  const day=Number(match[1]),month=Number(match[2]),year=Number(match[3]),date=new Date(Date.UTC(year,month-1,day));
  if(date.getUTCFullYear()!==year||date.getUTCMonth()!==month-1||date.getUTCDate()!==day)throw new Error('Invalid '+column+' date in export row '+row+'.');
  return match[3]+'-'+String(month).padStart(2,'0')+'-'+String(day).padStart(2,'0');
 }
 function vinValue(explicit,wmi,vds,frame){
  const clean=v=>String(v||'').replace(/\s+/g,'').toUpperCase(),valid=v=>/^[A-HJ-NPR-Z0-9]{17}$/.test(v);
  const source=clean(explicit);if(valid(source))return source;
  const parts=[wmi,vds,frame].map(clean);if(parts.some(v=>!v))return '';
  const candidate=parts.join('');return valid(candidate)?candidate:'';
 }
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
  return rows.slice(start+1).map((r,index)=>({dealer_code:get(r,'Dealer')==='037047'?'37047':get(r,'Dealer'),order:get(r,'Order'),cosi:get(r,'COSI'),
   batch:get(r,'Batch','Stock','Stock Number'),consultant:salespersonCode(get(r,'Salesperson')),
   client:get(r,'Customer Surname')||get(r,'Dealer Customer Name'),
   vehicle:[get(r,'Model Description','Model'),get(r,'Suffix Description')].filter(Boolean).join(' '),
   colourDescription:get(r,'Colour Description','Colour'),suffixDescription:get(r,'Suffix Description'),trimDescription:get(r,'Trim Description'),
   vin:vinValue(get(r,'VIN'),get(r,'WMI'),get(r,'VDS Number'),get(r,'Frame')),prodMth:get(r,'Production Month'),navisionSubLocationDescription:get(r,'Sub Location Description'),
   navisionLocationStatus:get(r,'Location Status'),navisionKewdaleEta:dateValue(get(r,'ETA At Kewdale Yard'),'Kewdale ETA',start+index+2),
   navisionEtaAtDealerBB:dateValue(get(r,'ETA At Dealer/BB'),'Dealer ETA',start+index+2),navisionPortPlantEta:dateValue(get(r,'Port/Plant ETA Date'),'Port/plant ETA',start+index+2),navisionDealerComments:get(r,'Dealer Comments')
  }));
 }
 const api={parse,cells,salespersonCode,dateValue,vinValue};if(typeof module==='object'&&module.exports)module.exports=api;if(root)root.BROOME_NAVISION_ORDERS=api;
})(typeof window==='undefined'?null:window);
