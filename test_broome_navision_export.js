const test=require('node:test'),assert=require('node:assert/strict');
const parser=require('./sales/navision-orders.js'),vin=require('./navision-vin.js');
test('Navision code plus eight-digit suffix becomes the active code while unknown names remain unguessed',()=>{
 for(const value of ['BG','bg','  bg 12345678  '])assert.equal(parser.salespersonCode(value),'BG');
 for(const value of ['Bryce Guthrie','BG extra','BG 123','BG 123456789','BG12345678'])assert.equal(parser.salespersonCode(value),value);
});
test('the complete TSV layout preserves stockless COSI rows, leading-zero orders and empty cells',()=>{
 const columns=['Order','Batch','Production Month','Compliance Date','Model Description','Suffix Description','Trim Description','Colour Description','Model','Suffix','Spec Sheet','Customer Surname','Dealer Comments','Location Status','Sub Location Description','Dealer','ETA At Kewdale Yard','COSI','Port/Plant ETA Date','ETA At Dealer/BB','Dealer Customer Name','Salesperson','WMI','VDS Number','Frame'];
 const row={'Order':'000123','Batch':'','Model Description':'HiLux','Suffix Description':'SR5','Dealer':'037047','COSI':'Yes','Salesperson':'bg 12345678','Dealer Customer Name':'Example company','ETA At Kewdale Yard':'6/10/2026','ETA At Dealer/BB':'18/10/2026','Port/Plant ETA Date':'2/11/2026','WMI':'MR0','VDS Number':'REBHVX','Frame':'00541949'};
 const text=columns.join('\t')+'\n'+columns.map(c=>row[c]||'').join('\t');
 const [result]=parser.parse(text);assert.equal(result.order,'000123');assert.equal(result.batch,'');assert.equal(result.cosi,'Yes');assert.equal(result.dealer_code,'37047');assert.equal(result.consultant,'BG');assert.equal(result.client,'Example company');
 assert.equal(result.vehicle,'HiLux SR5');assert.equal(result.navisionKewdaleEta,'2026-10-06');assert.equal(result.navisionEtaAtDealerBB,'2026-10-18');assert.equal(result.navisionPortPlantEta,'2026-11-02');assert.equal(result.vin,'MR0REBHVX00541949');
 assert.equal(parser.parse(text.replace('\tYes\t','\tNo\t'))[0].cosi,'No');
});
test('complete VIN components follow the PDC helper and partial/invalid values remain blank',()=>{
 assert.equal(parser.vinValue('',' mr0 ',' rebhvx ','00541949'),vin.buildNavisionVinParts(' mr0 ',' rebhvx ','00541949').vin);
 assert.equal(parser.vinValue('MR0REBHVX00541949','','',''),'MR0REBHVX00541949');
 for(const parts of [['MR0','',''],['MR0','REBHVX','123'],['MR0','REBHVX','0054I949'],['','','MR0REBHVX00541949']])assert.equal(parser.vinValue('',...parts),'');
});
test('day-first dates never change October to June and invalid calendar dates cannot be imported',()=>{
 assert.equal(parser.dateValue('6/10/2026','ETA',2),'2026-10-06');assert.equal(parser.dateValue('29/2/2028','ETA',2),'2028-02-29');
 assert.equal(parser.dateValue('2026-10-06','ETA',2),'2026-10-06');assert.equal(parser.dateValue('','ETA',2),'');
 assert.throws(()=>parser.dateValue('31/2/2026','ETA',2),/Invalid ETA date in export row 2/);
});
