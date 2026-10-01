const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const zebra=require('./sales/zebra-labels.js');
const app=fs.readFileSync('app.js','utf8');
function extract(name){const start=app.indexOf('function '+name+'('),end=app.indexOf('\nfunction ',start+1);return app.slice(start,end);}
const scope={};vm.runInNewContext(extract('cleanZplField')+'\n'+extract('vehicleToZplBlock')+'\nresult=vehicleToZplBlock;',scope);
test('sales label raw ZPL exactly matches PDC format for field values and defaults',()=>{
 for(const data of [{},{keyNumber:'42',stock:'001234',jobCard:'JC0001',customer:'Example customer',model:'HiLux SR5',sales:'Bryce Guthrie',department:'Broome Toyota'},
 {keyNumber:'^XZ~JA',customer:'A\nB\tC ^XA',model:'Prado & Hilux'}])assert.equal(zebra.vehicleToZplBlock(data),scope.result(data));
 const result=zebra.build([{stock:'001234',order:'000999',key_number:'42',job_card:'JC0001',client:'Example customer',vehicle:'HiLux SR5',salesperson_name:'Bryce Guthrie',division:'Broome Toyota'}]);
 assert.equal(result,scope.result({keyNumber:'42',stock:'001234',jobCard:'JC0001',customer:'Example customer',model:'HiLux SR5',sales:'Bryce Guthrie',department:'Broome Toyota'}));
});
test('stockless orders remain stockless and customer values cannot inject printer commands',()=>{
 const data=zebra.labelData({stock:'',order:'000123',client:'Example^XZ~JA\nName'});
 assert.equal(data.stock,'');assert.equal(data.keyNumber,'NO KEY');assert.doesNotMatch(zebra.build([{order:'000123'}]),/STOCK 000123/);
 const output=zebra.vehicleToZplBlock(data);assert.equal((output.match(/\^XA/g)||[]).length,1);assert.equal((output.match(/\^XZ/g)||[]).length,1);
 assert.match(zebra.build([{stock:'001'},{stock:'002'}]),/\^XZ\n\n\^XA/);
});
test('Zebra discovery matches PDC preferred printers and refuses unrelated printers',()=>{
 assert.equal(zebra.choosePrinter(['Office','ZDesigner','BT-Zebra-EricComp']),'BT-Zebra-EricComp');
 assert.equal(zebra.choosePrinter(['dc-01\\BT-Zebra-EricComp','Office']),'dc-01\\BT-Zebra-EricComp');
 assert.equal(zebra.choosePrinter(['Office','ZDesigner ZD421']),'ZDesigner ZD421');
 assert.throws(()=>zebra.choosePrinter(['Office laser']),/Zebra printer not found/);
});
function printerHarness(){const calls=[],window={qz:{websocket:{isActive:()=>true},printers:{find:async()=>['BT-Zebra-EricComp']},configs:{create:(name,options)=>({name,options})},print:async(config,data)=>calls.push({config,data})}};
 vm.runInNewContext(fs.readFileSync('sales/zebra-labels.js','utf8'),{window,module:undefined});return {api:window.BROOME_ZEBRA_LABELS,calls};}
test('selected labels go as one raw ZPL job with PDC settings, no scaling',async()=>{
 const h=printerHarness();assert.equal(await h.api.print([{stock:'001'},{stock:'002'}]),'BT-Zebra-EricComp');
 assert.equal(h.calls.length,1);const job=h.calls[0];assert.equal(job.config.options.copies,1);assert.equal(job.config.options.scaleContent,false);assert.equal(job.config.options.encoding,'UTF-8');
 assert.equal(job.data[0].type,'raw');assert.equal(job.data[0].format,'plain');assert.equal((job.data[0].data.match(/\^XA/g)||[]).length,2);
});
test('access revoked during printer connection cancels before sending labels',async()=>{
 const h=printerHarness();await assert.rejects(h.api.print([{stock:'001'}],()=>false),/Vehicle access changed/);assert.equal(h.calls.length,0);
 await assert.rejects(h.api.print([]),/Select vehicles/);assert.equal(h.calls.length,0);
});
