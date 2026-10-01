const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const zebra=require('./sales/zebra-labels.js');
const app=fs.readFileSync('app.js','utf8');
function extract(name){const start=app.indexOf('function '+name+'('),end=app.indexOf('\nfunction ',start+1);return app.slice(start,end);}
const scope={};vm.runInNewContext(extract('cleanZplField')+'\n'+extract('vehicleToZplBlock')+'\nresult=vehicleToZplBlock;',scope);
test('sales ZPL matches the requested stock-first format with separate customer/salesperson and two copies',()=>{
 const data={stock:'001234',customer:'Example customer',sales:'Bryce Guthrie',model:'HiLux SR5',description:'Rogue 48V Mineral Leather Frosted White',vin:'EXAMPLEVIN1234567'};
 assert.equal(zebra.vehicleToZplBlock(data),[
 '^XA','^PW540','^LL360','^LH0,0','^CI28',
 '^FO20,20^A0N,50,50^FB500,1,0,L,0^FD001234^FS',
 '^FO20,90^A0N,25,25^FB500,1,0,L,0^FDExample customer^FS',
 '^FO20,125^A0N,25,25^FB500,1,0,L,0^FDBryce Guthrie^FS',
 '^FO20,160^A0N,25,25^FB500,1,0,L,0^FDHiLux SR5^FS',
 '^FO20,195^A0N,25,25^FB500,2,0,L,0^FDRogue 48V Mineral Leather Frosted White^FS',
 '^FO20,260^A0N,25,25^FB500,1,0,L,0^FDEXAMPLEVIN1234567^FS',
 '^FO20,300^A0N,50,50^FB500,1,0,L,0^FD001234^FS','^PQ2','^XZ'].join('\n'));
 assert.notEqual(zebra.vehicleToZplBlock(data),scope.result(data));
});
test('Navision suffix/trim/colour and VIN map without repeating a combined vehicle suffix',()=>{
 const data=zebra.labelData({stock:'001234',order:'000999',key_number:'42',job_card:'JC0001',client:'Example customer',vehicle:'HiLux SR5 Rogue 48V',suffix:'Rogue 48V',trim:'Mineral Leather',colour:'Frosted White',vin:'EXAMPLEVIN1234567',salesperson_name:'Bryce Guthrie'});
 assert.equal(data.model,'HiLux SR5');assert.equal(data.description,'Rogue 48V Mineral Leather Frosted White');assert.equal(data.vin,'EXAMPLEVIN1234567');assert.equal(data.stock,'001234');
 assert.equal(zebra.labelData({vehicle:'Rogue 48V HiLux',suffix:'Rogue 48V'}).model,'Rogue 48V HiLux');
 assert.equal(zebra.labelData({vehicle:'HiLux',suffix:'Rogue',trim:'Rogue',colour:'White'}).description,'Rogue White');
});
test('stockless orders remain stockless and customer values cannot inject printer commands',()=>{
 const data=zebra.labelData({stock:'',order:'000123',client:'Example^XZ~JA\nName'});
 assert.equal(data.stock,'');assert.doesNotMatch(zebra.build([{order:'000123',key_number:'999'}]),/000123|999/);
 assert.equal((zebra.build([{order:'000123'}]).match(/\^FDNO STOCK\^FS/g)||[]).length,2);
 const output=zebra.vehicleToZplBlock(data);assert.equal((output.match(/\^XA/g)||[]).length,1);assert.equal((output.match(/\^XZ/g)||[]).length,1);
 assert.match(zebra.build([{stock:'001'},{stock:'002'}]),/\^XZ\n\n\^XA/);
});
test('every label field retains PDC command cleaning without leaking removed key/job fields',()=>{
 const result=zebra.build([{stock:'0^XZ~JA\n01',client:'A\tB',salesperson_name:'C^XA',vehicle:'D~JA',suffix:'E^XZ',trim:'F\nG',colour:'H~JA',vin:'I^XZ',key_number:'SECRETKEY',job_card:'SECRETJOB'}]);
 assert.equal((result.match(/\^XA/g)||[]).length,1);assert.equal((result.match(/\^XZ/g)||[]).length,1);
 assert.doesNotMatch(result,/~|SECRETKEY|SECRETJOB|JOB CARD/);assert.match(result,/\^FDA B\^FS/);assert.match(result,/\^FDEXZ F G HJA\^FS/);
});
test('Zebra discovery matches PDC preferred printers and refuses unrelated printers',()=>{
 assert.equal(zebra.choosePrinter(['Office','ZDesigner','BT-Zebra-EricComp']),'BT-Zebra-EricComp');
 assert.equal(zebra.choosePrinter(['dc-01\\BT-Zebra-EricComp','Office']),'dc-01\\BT-Zebra-EricComp');
 assert.equal(zebra.choosePrinter(['Office','ZDesigner ZD421']),'ZDesigner ZD421');
 assert.throws(()=>zebra.choosePrinter(['Office laser']),/Zebra printer not found/);
});
function printerHarness(){const calls=[],window={qz:{websocket:{isActive:()=>true},printers:{find:async()=>['BT-Zebra-EricComp']},configs:{create:(name,options)=>({name,options})},print:async(config,data)=>calls.push({config,data})}};
 vm.runInNewContext(fs.readFileSync('sales/zebra-labels.js','utf8'),{window,module:undefined});return {api:window.BROOME_ZEBRA_LABELS,calls};}
test('selected labels request two copies per block and one QZ job copy, without multiplying to four',async()=>{
 const h=printerHarness();assert.equal(await h.api.print([{stock:'001'},{stock:'002'}]),'BT-Zebra-EricComp');
 assert.equal(h.calls.length,1);const job=h.calls[0];assert.equal(job.config.options.copies,1);assert.equal(job.config.options.scaleContent,false);assert.equal(job.config.options.encoding,'UTF-8');
 assert.equal(job.data[0].type,'raw');assert.equal(job.data[0].format,'plain');assert.equal((job.data[0].data.match(/\^XA/g)||[]).length,2);
 assert.equal((job.data[0].data.match(/\^PQ2/g)||[]).length,2);assert.doesNotMatch(job.data[0].data,/\^PQ1/);
});
test('access revoked during printer connection cancels before sending labels',async()=>{
 const h=printerHarness();await assert.rejects(h.api.print([{stock:'001'}],()=>false),/Vehicle access changed/);assert.equal(h.calls.length,0);
 await assert.rejects(h.api.print([]),/Select vehicles/);assert.equal(h.calls.length,0);
});
