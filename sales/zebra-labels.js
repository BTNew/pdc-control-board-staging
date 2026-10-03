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
let connectorLoad=null,connectionAttempt=null;
function errorMessage(error,fallback='Printing failed.'){
 const value=typeof error==='string'?error:typeof error?.message==='string'?error.message:'';
 return value.trim()||fallback;
}
function authorise(stillAuthorised){if(!stillAuthorised())throw new Error('Vehicle access changed. Refresh before printing.');}
function phaseError(error,phase){
 const label=phase==='connect'?'Could not connect to QZ Tray.':phase==='printers'?'Could not read printers from QZ Tray.':'QZ Tray could not accept the label job.';
 const help=phase==='connect'?'Make sure QZ Tray is running. In your browser site settings, allow Apps on this device / local network access, and approve the QZ Tray request when prompted.':phase==='printers'?'Approve the QZ Tray request and check that the Zebra printer is installed on this computer.':'Check the selected printer and its queue before trying again.';
 const result=new Error(label+' '+errorMessage(error,'No further error details were supplied.')+' '+help);result.phase=phase;return result;
}
async function connect(stillAuthorised){
 authorise(stillAuthorised);
 if(!root.qz){
  if(!connectorLoad)connectorLoad=new Promise((resolve,reject)=>{
   const script=root.document.createElement('script');script.src='../vendor/qz/qz-tray.js?v=2.2.6';script.async=true;
   script.addEventListener('load',resolve,{once:true});script.addEventListener('error',()=>{connectorLoad=null;script.remove?.();reject(new Error('The printer connection could not load. Please try again.'));},{once:true});
   root.document.head.appendChild(script);
  });
  await connectorLoad;
 }
 authorise(stillAuthorised);
 const qz=root.qz;
 if(typeof qz?.websocket?.isActive!=='function'||typeof qz?.websocket?.connect!=='function'||typeof qz?.printers?.find!=='function'||typeof qz?.configs?.create!=='function'||typeof qz?.print!=='function'){
  connectorLoad=null;throw new Error('The QZ Tray browser connector did not load correctly. Refresh and try again.');
 }
 if(!qz.websocket.isActive()){
  if(!connectionAttempt)connectionAttempt=Promise.resolve().then(()=>qz.websocket.connect({retries:2,delay:1})).catch(error=>{throw phaseError(error,'connect');}).finally(()=>{connectionAttempt=null;});
  await connectionAttempt;
 }
 authorise(stillAuthorised);return qz;
}
function printerList(printers){
 const list=Array.isArray(printers)?printers:[printers],seen=new Set();
 return list.filter(name=>typeof name==='string'&&name.trim()).map(name=>name.trim()).filter(name=>{const key=name.toLowerCase();if(seen.has(key))return false;seen.add(key);return true;});
}
function choosePrinter(printers,explicitPrinter=''){
 const list=printerList(printers);
 if(explicitPrinter){
  const name=String(explicitPrinter).trim(),match=list.find(value=>value.toLowerCase()===name.toLowerCase());
  if(match)return match;
  throw new Error('The selected printer is no longer available. Load printers and choose it again.');
 }
 for(const target of printerNames){const match=list.find(n=>String(n).toLowerCase()===target.toLowerCase());if(match)return match;}
 for(const target of printerNames){const match=list.find(n=>String(n).toLowerCase().includes(target.toLowerCase()));if(match)return match;}
 const match=list.find(n=>/zebra|zdesigner|bt-zebra/i.test(String(n)));if(match)return match;
 throw new Error('Zebra printer not found. Check the printer is available on this computer.');
}
async function listPrinters(stillAuthorised=()=>true){
 const qz=await connect(stillAuthorised);let names;
 try{names=await qz.printers.find();}catch(error){authorise(stillAuthorised);throw phaseError(error,'printers');}
 authorise(stillAuthorised);return printerList(names);
}
async function checkConnection(stillAuthorised=()=>true){
 const printers=await listPrinters(stillAuthorised);let printer='';
 try{printer=choosePrinter(printers);}catch{/* The connection can work without a Zebra queue installed. */}
 return {connected:true,printers,printer};
}
async function print(rows,stillAuthorised=()=>true,explicitPrinter=''){
 if(!rows.length)throw new Error('Select vehicles to print.');
 authorise(stillAuthorised);
 const zpl=build(rows),printers=await listPrinters(stillAuthorised),printer=choosePrinter(printers,explicitPrinter),qz=root.qz;
 authorise(stillAuthorised);
 try{await qz.print(qz.configs.create(printer,{copies:1,scaleContent:false,encoding:'UTF-8'}),[{type:'raw',format:'plain',data:zpl}]);}catch(error){authorise(stillAuthorised);throw phaseError(error,'print');}
 return printer;
}
const api={cleanZplField,vehicleToZplBlock,labelData,build,choosePrinter,errorMessage,listPrinters,checkConnection,print};
if(typeof module==='object'&&module.exports)module.exports=api;
root.BROOME_ZEBRA_LABELS=api;
})(typeof window==='object'?window:globalThis);
