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
function printerHarness(){const calls=[],window={qz:{websocket:{isActive:()=>true,connect:async()=>{}},printers:{find:async()=>['BT-Zebra-EricComp']},configs:{create:(name,options)=>({name,options})},print:async(config,data)=>calls.push({config,data})}};
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

function connectionHarness(options={}){
 const calls={scripts:[],connect:[],find:[],config:[],print:[]};let active=options.active||false;
 const qz={websocket:{isActive:()=>active,connect:async config=>{calls.connect.push(config);await options.connect?.(config);active=true;}},printers:{find:async()=>{calls.find.push(true);return options.find?options.find():options.queues||['BT-Zebra-EricComp'];}},configs:{create:(name,settings)=>{const config={name,settings};calls.config.push(config);return config;}},print:async(config,data)=>{calls.print.push({config,data});return options.print?.(config,data);}};
 const window={qz:options.load?undefined:qz,document:{createElement(){return {events:{},addEventListener(name,fn){this.events[name]=fn;},remove(){this.removed=true;}};},head:{appendChild(script){calls.scripts.push(script);}}}};
 vm.runInNewContext(fs.readFileSync('sales/zebra-labels.js','utf8'),{window,module:undefined});return {api:window.BROOME_ZEBRA_LABELS,calls,qz,window};
}
const tick=()=>new Promise(resolve=>setImmediate(resolve));

test('connection diagnostics list exact available printers without submitting a label job',async()=>{
 const h=connectionHarness({queues:['Office laser',' BT-Zebra-EricComp ','bt-zebra-ericcomp','',null,2]});
 const result=await h.api.checkConnection();assert.equal(result.connected,true);assert.equal(result.printer,'BT-Zebra-EricComp');assert.deepEqual(Array.from(result.printers),['Office laser','BT-Zebra-EricComp']);
 assert.equal(h.calls.connect.length,1);assert.deepEqual(JSON.parse(JSON.stringify(h.calls.connect[0])),{retries:2,delay:1});assert.equal(h.calls.find.length,1);assert.equal(h.calls.config.length,0);assert.equal(h.calls.print.length,0);
 const noZebra=connectionHarness({queues:['Office laser']});const status=await noZebra.api.checkConnection();assert.equal(status.connected,true);assert.equal(status.printer,'');assert.deepEqual(Array.from(status.printers),['Office laser']);assert.equal(noZebra.calls.print.length,0);
});

test('explicit printer selections require an exact current queue and never silently fall back',async()=>{
 assert.throws(()=>zebra.choosePrinter(['B','Office laser']),/Zebra printer not found/,'a short unrelated name must not reverse-match a preferred queue');
 assert.equal(zebra.choosePrinter(['ZDesigner First','ZDesigner Second'],'zdesigner second'),'ZDesigner Second');
 assert.throws(()=>zebra.choosePrinter(['BT-Zebra-EricComp'],'BT-Zebra'),/selected printer.*no longer available/i);
 const h=connectionHarness({active:true,queues:['BT-Zebra-EricComp','ZDesigner Second']});assert.equal(await h.api.print([{stock:'EXAMPLE'}],()=>true,'ZDesigner Second'),'ZDesigner Second');assert.equal(h.calls.print[0].config.name,'ZDesigner Second');
 await assert.rejects(h.api.print([{stock:'EXAMPLE'}],()=>true,'Missing Zebra'),/selected printer.*no longer available/i);assert.equal(h.calls.print.length,1);assert.equal(h.calls.config.length,1);
});

test('the connector script and websocket attempt are shared while pending and load failures permit a clean retry',async()=>{
 const h=connectionHarness({load:true}),first=h.api.checkConnection(),second=h.api.checkConnection();assert.equal(h.calls.scripts.length,1);assert.equal(h.calls.scripts[0].src,'../vendor/qz/qz-tray.js?v=2.2.6');assert.equal(h.calls.print.length,0);
 h.calls.scripts[0].events.error();await assert.rejects(first,/could not load/);await assert.rejects(second,/could not load/);assert.equal(h.calls.scripts[0].removed,true);
 const retry=h.api.checkConnection();assert.equal(h.calls.scripts.length,2);h.window.qz=h.qz;h.calls.scripts[1].events.load();await retry;assert.equal(h.calls.connect.length,1);assert.equal(h.calls.print.length,0);
 let finish;const connecting=connectionHarness({connect:()=>new Promise(resolve=>finish=resolve)}),a=connecting.api.checkConnection(),b=connecting.api.listPrinters();await tick();assert.equal(connecting.calls.connect.length,1);finish();await Promise.all([a,b]);assert.equal(connecting.calls.connect.length,1);assert.equal(connecting.calls.find.length,2);assert.equal(connecting.calls.print.length,0);
});

test('failed websocket connections retain the original error and allow a later manual retry',async()=>{
 let attempts=0;const h=connectionHarness({connect:async()=>{if(++attempts===1)throw 'Browser blocked localhost connection';}});
 await assert.rejects(h.api.checkConnection(),error=>{assert.equal(error.phase,'connect');assert.match(error.message,/Browser blocked localhost connection/);assert.match(error.message,/Apps on this device.*local network/i);return true;});assert.equal(h.calls.find.length,0);assert.equal(h.calls.print.length,0);
 assert.equal((await h.api.checkConnection()).printer,'BT-Zebra-EricComp');assert.equal(h.calls.connect.length,2);assert.equal(h.calls.print.length,0);
});

test('access lost before connection, during connection or discovery cancels diagnostics and printing',async()=>{
 const denied=connectionHarness({load:true});await assert.rejects(denied.api.checkConnection(()=>false),/Vehicle access changed/);assert.equal(denied.calls.scripts.length,0);
 await assert.rejects(denied.api.print([{stock:'EXAMPLE'}],()=>false),/Vehicle access changed/);assert.equal(denied.calls.print.length,0);
 let allowed=true,finish;const connecting=connectionHarness({connect:()=>new Promise(resolve=>finish=resolve)}),pending=connecting.api.checkConnection(()=>allowed);await tick();allowed=false;finish();await assert.rejects(pending,/Vehicle access changed/);assert.equal(connecting.calls.find.length,0);
 allowed=true;let found;const discovering=connectionHarness({active:true,find:()=>new Promise(resolve=>found=resolve)}),printing=discovering.api.print([{stock:'EXAMPLE'}],()=>allowed);await tick();allowed=false;found(['BT-Zebra-EricComp']);await assert.rejects(printing,/Vehicle access changed/);assert.equal(discovering.calls.config.length,0);assert.equal(discovering.calls.print.length,0);
});

test('printer-discovery and job rejection errors keep string details and never retry a submitted job',async()=>{
 const discovery=connectionHarness({active:true,find:async()=>{throw 'QZ permission denied';}});await assert.rejects(discovery.api.checkConnection(),error=>{assert.equal(error.phase,'printers');assert.match(error.message,/QZ permission denied/);return true;});assert.equal(discovery.calls.print.length,0);
 const job=connectionHarness({active:true,print:async()=>{throw 'Printer queue offline';}});await assert.rejects(job.api.print([{stock:'EXAMPLE'}]),error=>{assert.equal(error.phase,'print');assert.match(error.message,/Printer queue offline/);return true;});assert.equal(job.calls.print.length,1,'an uncertain submission must not automatically print another copy');
 assert.equal(zebra.errorMessage('Specific failure'),'Specific failure');assert.equal(zebra.errorMessage(new Error('Error details')),'Error details');assert.equal(zebra.errorMessage(null),'Printing failed.');assert.equal(zebra.errorMessage({privateCustomer:'do not serialize'}),'Printing failed.');assert.equal(zebra.errorMessage('', 'Check connection'),'Check connection');
});

test('the Sales CSP permits exactly the bundled QZ secure loopback hosts and ports',()=>{
 const html=fs.readFileSync('sales/index.html','utf8'),policy=html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)?.[1],connect=policy?.match(/(?:^|;)\s*connect-src ([^;]+)/)?.[1].split(/\s+/)||[];
 for(const host of ['localhost','localhost.qz.io'])for(const port of [8181,8282,8383,8484])assert.ok(connect.includes('wss://'+host+':'+port),'QZ endpoint missing: '+host+':'+port);
 const qzHosts=connect.filter(value=>value.includes('localhost'));assert.equal(qzHosts.length,8);assert.ok(connect.includes("'self'"));assert.ok(connect.some(value=>/^https:\/\/[\w]+\.supabase\.co$/.test(value)));
 assert.doesNotMatch(connect.join(' '),/(?:^|\s)(?:\*|wss?:)(?=\s|$)|(?:^|\s)(?:wss?:\/\/\*|ws:\/\/)/,'printer permission must not broaden to all hosts or insecure websockets');
 const code=fs.readFileSync('sales/zebra-labels.js','utf8');assert.doesNotMatch(code,/setCertificatePromise|setSignaturePromise|private-key|usingSecure\s*:\s*false/,'manual QZ approval must not be bypassed');
});
