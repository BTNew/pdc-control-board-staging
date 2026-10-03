'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
globalThis.XLSX = require('./vendor/xlsx/xlsx.full.min.js');
const nuvu = require('./karratha/nuvu.js');
const mapping = {stock_number:'Stock',repair_order_number:'Jobcard',operation_description:'Description',store_code:'Store',original_line_number:'Line',source_estimated_hours:'Hours',stage_code:'Stage',parts_required:'Parts'};
test('text preserves quoted multiline, leading zero identifiers, blanks and escaped quotes', () => {
  const source={text:'Stock\tJobcard\tDescription\tStore\tLine\tHours\tStage\tParts\r\n001234\t00008\t"Fit \"\"tray\"\"\r\nwith ties"\t135\t1\t2.5\tFITTING\tYes\r\n001234\t00009\tUnmapped\t135\t\t\tUnknown\t\r\n'};
  const table=nuvu.table(source,'Text export',1,'\t'),rows=nuvu.mapped(table,mapping);
  assert.equal(rows.length,2); assert.equal(rows[0].stock_number,'001234'); assert.equal(rows[0].repair_order_number,'00008');
  assert.equal(rows[0].operation_description,'Fit "tray"\r\nwith ties'); assert.equal(rows[0].raw_row.Description,rows[0].operation_description);
  assert.equal(rows[0].source_estimated_hours,2.5); assert.equal(rows[0].parts_required,true);
  assert.equal(rows[1].stage_code,null); assert.equal(rows[1].source_estimated_hours,null); assert.equal(rows[1].parts_required,null);
  assert.equal(rows[1].raw_row.__source_row,3); assert.equal(rows[1].raw_row.Stage,'Unknown');
});
test('Excel preserves identifier formatting and raw numeric hours plus unknown lines', () => {
  const sheet=XLSX.utils.aoa_to_sheet([['Stock','Jobcard','Description','Store','Line','Hours','Stage','Parts'],[1234,8,'Tint',135,1,1.25,'TINT','No'],['001234','00009','Header',135,2,'','UNKNOWN','']]);
  sheet.A2.z='000000';sheet.B2.z='00000';
  const bytes=XLSX.write({SheetNames:['NuVu'],Sheets:{NuVu:sheet}},{type:'buffer',bookType:'xlsx'});
  const workbook=XLSX.read(bytes,{cellNF:true,cellText:true});
  const table=nuvu.table({workbook},'NuVu'),rows=nuvu.mapped(table,mapping);
  assert.equal(rows[0].stock_number,'001234');assert.equal(rows[0].repair_order_number,'00008');
  assert.equal(rows[0].raw_row.Stock,1234);assert.equal(rows[0].raw_row.__cell_formats.Stock.number_format,'000000');
  assert.equal(rows[0].source_estimated_hours,1.25);assert.equal(rows[0].parts_required,false);
  assert.equal(rows[1].source_estimated_hours,null);assert.equal(rows[1].stage_code,null);assert.equal(rows[1].raw_row.Description,'Header');
});
test('unsafe/incomplete mapping, duplicated headings and damaged quotes require correction', () => {
  assert.throws(()=>nuvu.parseDelimited('"unfinished',','),/unfinished/);
  assert.throws(()=>nuvu.table({text:'Stock\tStock\n1\t2'},'Text export'),/duplicate/);
  const table=nuvu.table({text:'Stock\tJobcard\tDescription\tStore\n1\t2\tTest\t135'},'Text export');
  assert.throws(()=>nuvu.mapped(table,{}),/explicitly/);
});
test('SheetJS vendor bytes are pinned and frontend only imports its own APIs', () => {
  const vendor=fs.readFileSync(path.join(__dirname,'vendor/xlsx/xlsx.full.min.js'));
  assert.equal(crypto.createHash('sha256').update(vendor).digest('hex'),'cc015130aa8521e7f088f88898eba949ccdcbfb38df0bd129b44b7273c3a6f41');
  const html=fs.readFileSync(path.join(__dirname,'karratha/index.html'),'utf8');
  assert.match(html,/integrity="sha384-EnyY0\/GSHQGSxSgMwaIPzSESbqoOLSexfnSMN2AP\+39Ckmn92stwABZynq1JyzdT"/);
  assert.doesNotMatch(html,/src="\.\.\/(?:app\.js|pdc-auth\.js|workshop-data-service\.js|broome-navision-import\.js)/);
});
