'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
global.XLSX=require(path.resolve(__dirname,'./karratha/vendor/xlsx/xlsx.full.min.js'));
const nuvu=require(path.resolve(__dirname,'./karratha/pd135-nuvu-parser.js'));
const mapping={stock_number:'Stock',repair_order_number:'Job',original_line_number:'Line',operation_description:'Description',
 source_estimated_hours:'Hours',store_code:'Store',stage_code:'Stage',parts_required:'Parts',dealer_code:'Dealer'};
const header=['Stock','Job','Line','Description','Hours','Store','Stage','Parts','Dealer'];

test('CSV quoted multiline/comma/escaped quote evidence is preserved exactly',()=>{
 const source={text:'Stock,Job,Line,Description,Hours,Store,Stage,Parts,Dealer\r\n001234,RO001,10,"Fit canopy, then inspect\nAccessory ""special""",1.5,135,FITTING,Yes,001234\r\n'};
 const table=nuvu.table(source,'Text export',1,',');
 const rows=nuvu.mapped(table,mapping);
 assert.equal(rows.length,1);
 assert.equal(rows[0].stock_number,'001234');
 assert.equal(rows[0].dealer_code,'001234');
 assert.equal(rows[0].operation_description,'Fit canopy, then inspect\nAccessory "special"');
 assert.equal(rows[0].raw_row.Description,rows[0].operation_description);
 assert.equal(rows[0].raw_row.__source_row,2);
 assert.equal(rows[0].source_estimated_hours,1.5);
 assert.equal(rows[0].parts_required,true);
});

test('duplicate headers/unclosed quote are rejected with actionable import error',()=>{
 assert.throws(()=>nuvu.table({text:'Stock\tStock\n1\t1'},'Text export',1,'\t'),/duplicate/);
 assert.throws(()=>nuvu.parseDelimited('Stock,Job\n1,"unfinished',','),/unfinished/);
});

test('missing identity/unknown stage/parts remain explicit original evidence',()=>{
 const source={text:header.join('\t')+'\n\tRO002\t20\tUncertain work\t0\t135\tBUS_4X4\tUnknown\t001234\n'};
 const [row]=nuvu.mapped(nuvu.table(source,'Text export'),mapping);
 assert.equal(row.stock_number,'');
 assert.equal(row.stage_code,null);
 assert.equal(row.parts_required,null);
 assert.equal(row.source_estimated_hours,0);
 assert.equal(row.raw_row.Stage,'BUS_4X4');
 assert.equal(row.raw_row.Parts,'Unknown');
});

test('same stock different repair orders remains two independent rows',()=>{
 const source={text:header.join('\t')+'\n123456\tRO003\t10\tFit tray\t1\t135\tFITTING\tYes\t001234\n123456\tRO004\t10\tWindow tint\t2\t135\tTINT\tNo\t001234'};
 const rows=nuvu.mapped(nuvu.table(source,'Text export'),mapping);
 assert.equal(rows.length,2);
 assert.equal(rows[0].stock_number,rows[1].stock_number);
 assert.notEqual(rows[0].repair_order_number,rows[1].repair_order_number);
});

test('formatted numeric stock uses original integer while digit padding survives',()=>{
 const sheet=global.XLSX.utils.aoa_to_sheet([header,[13023161,'RO005',10,'Fit accessories',1.25,135,'FITTING','No',1234],
  [123456,'RO006',20,'Window tint',2,135,'TINT','Yes',1234]]);
 sheet.A2.z='#,##0';sheet.A2.w='13,023,161';
 sheet.A3.z='000000000';sheet.A3.w='000123456';
 sheet.I2.z='000000';sheet.I2.w='001234';sheet.I3.z='000000';sheet.I3.w='001234';
 const source={workbook:{Sheets:{Report:sheet}}};
 const rows=nuvu.mapped(nuvu.table(source,'Report'),mapping);
 assert.equal(rows[0].stock_number,'13023161');
 assert.equal(rows[1].stock_number,'000123456');
 assert.equal(rows[0].dealer_code,'001234');
 assert.equal(rows[0].raw_row.Stock,13023161);
 assert.equal(rows[0].raw_row.__cell_formats.Stock.formatted,'13,023,161');
});

test('XLSX offset retains physical header/source row and original cell formatting',()=>{
 const sheet=global.XLSX.utils.aoa_to_sheet([]);
 global.XLSX.utils.sheet_add_aoa(sheet,[header,[13023161,'RO007',10,'Long\nsource notes',1.5,135,'FITTING','No',1234]],{origin:'B3'});
 sheet['!ref']='B3:J4';sheet.B4.z='000000000';sheet.B4.w='013023161';sheet.J4.z='000000';sheet.J4.w='001234';
 const source={workbook:{Sheets:{Report:sheet}}};
 const table=nuvu.table(source,'Report',3);
 const [row]=nuvu.mapped(table,mapping);
 assert.equal(row.stock_number,'013023161');
 assert.equal(row.dealer_code,'001234');
 assert.equal(row.raw_row.__source_row,4);
 assert.equal(row.operation_description,'Long\nsource notes');
 assert.equal(row.raw_row.__cell_formats.Stock.formatted,'013023161');
});

test('long source description is neither truncated nor split into fake operations',()=>{
 const description='Original source line\n'.repeat(80);
 const table={headers:header,rows:[{cells:['123456','RO008',10,description,1,135,'FITTING','No','001234'],
  formatted:['123456','RO008',10,description,1,135,'FITTING','No','001234'],formats:[],source_row:2}],sheet_name:'Report',header_row:1};
 const rows=nuvu.mapped(table,mapping);
 assert.equal(rows.length,1);
 assert.equal(rows[0].operation_description,description);
 assert.equal(rows[0].raw_row.Description,description);
});

