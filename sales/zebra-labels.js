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
  const stock = cleanZplField(vehicle.stock || 'NO STOCK');
  const customer = cleanZplField(vehicle.customer || '(Dealer Order)');
  const model = cleanZplField(vehicle.model || 'Vehicle not listed');
  const sales = cleanZplField(vehicle.sales || '—');
  const description = cleanZplField(vehicle.description || 'Details not recorded');
  const vin = cleanZplField(vehicle.vin || 'VIN not recorded');
  return [
    '^XA', '^PW540', '^LL360', '^LH0,0', '^CI28',
    `^FO20,20^A0N,50,50^FB500,1,0,L,0^FD${stock}^FS`,
    `^FO20,90^A0N,25,25^FB500,1,0,L,0^FD${customer}^FS`,
    `^FO20,125^A0N,25,25^FB500,1,0,L,0^FD${sales}^FS`,
    `^FO20,160^A0N,25,25^FB500,1,0,L,0^FD${model}^FS`,
    `^FO20,195^A0N,25,25^FB500,2,0,L,0^FD${description}^FS`,
    `^FO20,260^A0N,25,25^FB500,1,0,L,0^FD${vin}^FS`,
    `^FO20,300^A0N,50,50^FB500,1,0,L,0^FD${stock}^FS`,
    '^PQ2', '^XZ'
  ].join('\n');
}
function labelData(row){
 const suffix=cleanZplField(row.suffix),model=cleanZplField(row.vehicle);
 // Navision's vehicle display can already end with its separate suffix description.
 const modelOnly=suffix&&model.toLowerCase().endsWith(' '+suffix.toLowerCase())?model.slice(0,-suffix.length).trim():model;
 const descriptions=[suffix,cleanZplField(row.trim),cleanZplField(row.colour)].filter(Boolean);
 return {stock:cleanZplField(row.stock||''),customer:cleanZplField(row.client||'(Dealer Order)'),
 model:modelOnly,sales:cleanZplField(row.salesperson_name||row.salesperson_code||''),
 description:descriptions.filter((v,i)=>descriptions.findIndex(x=>x.toLowerCase()===v.toLowerCase())===i).join(' '),vin:cleanZplField(row.vin)};
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
