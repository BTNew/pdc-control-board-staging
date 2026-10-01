(function(root){
'use strict';
function cleanZplField(value) {
  return String(value ?? '')
    .replace(/[\^~]/g, '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function vehicleToZplBlock(vehicle) {
  const keyNumber = cleanZplField(vehicle.keyNumber || vehicle.batch || 'NO KEY');
  const stock = cleanZplField(vehicle.stock || '—');
  const jobCard = cleanZplField(vehicle.jobCard || '—');
  const customer = cleanZplField(vehicle.customer || '(Dealer Order)');
  const model = cleanZplField(vehicle.model || 'Vehicle not listed');
  const sales = cleanZplField(vehicle.sales || '—');
  const department = cleanZplField(vehicle.department || 'PDC');
  return [
    '^XA', '^PW540', '^LL360', '^LH0,0', '^CI28',
    `^FO18,12^A0N,62,62^FB504,1,0,L,0^FD${keyNumber}^FS`,
    `^FO18,82^A0N,28,28^FB504,1,0,L,0^FDSTOCK ${stock}^FS`,
    `^FO18,116^A0N,25,25^FB504,1,0,L,0^FDJOB CARD ${jobCard}^FS`,
    `^FO18,150^A0N,27,27^FB504,2,2,L,0^FD${customer}^FS`,
    `^FO18,210^A0N,25,25^FB504,2,2,L,0^FD${model}^FS`,
    `^FO18,276^A0N,23,23^FB504,1,0,L,0^FDSALES ${sales}^FS`,
    `^FO18,308^A0N,22,22^FB504,1,0,L,0^FD${department}^FS`,
    '^PQ1', '^XZ'
  ].join('\n');
}
function labelData(row){
 return {keyNumber:cleanZplField(row.key_number||row.stock||'NO KEY'),stock:cleanZplField(row.stock||''),
 jobCard:cleanZplField(row.job_card||''),customer:cleanZplField(row.client||'Dealer Order'),
 model:cleanZplField(row.vehicle||''),sales:cleanZplField(row.salesperson_name||row.salesperson_code||''),
 department:cleanZplField(row.division||'Broome Toyota')};
}
function build(rows){return rows.map(r=>vehicleToZplBlock(labelData(r))).join('\n\n');}
const printerNames=['BT-Zebra-EricComp','dc-01\\BT-Zebra-EricComp','192.168.0.164'];
let connectorLoad=null;
async function connect(){
 if(!root.qz){if(!connectorLoad)connectorLoad=new Promise((resolve,reject)=>{
 const script=root.document.createElement('script');script.src='../vendor/qz/qz-tray.js?v=2.2.6';script.async=true;
 script.addEventListener('load',resolve,{once:true});script.addEventListener('error',()=>{connectorLoad=null;reject(new Error('The printer connection could not load. Please try again.'));},{once:true});
 root.document.head.appendChild(script);
 });await connectorLoad;}
 const qz=root.qz;if(!qz?.websocket||!qz?.printers||!qz?.configs||!qz?.print)throw new Error('QZ Tray must be installed and running to print Zebra labels.');
 if(!qz.websocket.isActive())await qz.websocket.connect({retries:2,delay:1});return qz;
}
function choosePrinter(printers){
 const list=Array.isArray(printers)?printers:[printers].filter(Boolean);
 for(const target of printerNames){const match=list.find(n=>String(n).toLowerCase()===target.toLowerCase());if(match)return match;}
 for(const target of printerNames){const match=list.find(n=>{const a=String(n).toLowerCase(),b=target.toLowerCase();return a&&(a.includes(b)||b.includes(a));});if(match)return match;}
 const match=list.find(n=>/zebra|zdesigner|bt-zebra/i.test(String(n)));if(match)return match;
 throw new Error('Zebra printer not found. Check the printer is available on this computer.');
}
async function print(rows,stillAuthorised=()=>true){
 if(!rows.length)throw new Error('Select vehicles to print.');
 const zpl=build(rows),qz=await connect(),printer=choosePrinter(await qz.printers.find());
 if(!stillAuthorised())throw new Error('Vehicle access changed. Refresh before printing.');
 await qz.print(qz.configs.create(printer,{copies:1,scaleContent:false,encoding:'UTF-8'}),[{type:'raw',format:'plain',data:zpl}]);
 return printer;
}
const api={cleanZplField,vehicleToZplBlock,labelData,build,choosePrinter,print};
if(typeof module==='object'&&module.exports)module.exports=api;
root.BROOME_ZEBRA_LABELS=api;
})(typeof window==='object'?window:globalThis);
