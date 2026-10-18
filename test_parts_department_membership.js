'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js', 'utf8');
test('Parts filters use canonical multi-department membership, including shared jobs', () => {
  let department = '139';
  const c = {window: {PDC_DEPARTMENT_FILTER: require('./pdc-department-filter')}, app: {},
    $: selector => ({value: selector === '#parts-department-filter' ? department : ''}),
    vehicleHasBatchNumber: () => true, partsQueueVisibleVehicle: () => true,
    partsMatchesOperationalFilter: () => true, partsDepartmentStatus: () => 'onorder',
    displayStockNumber: row => row.stock, vehicleDepartmentCode: row => row.departmentCode};
  vm.createContext(c);
  vm.runInContext(source.slice(source.indexOf('function partsDepartmentRows('), source.indexOf('function renderPartsSummary(')), c);
  const rows = [{stock:'1',pdcDepartmentCodes:['139'],departmentCode:''},
    {stock:'2',pdcDepartmentCodes:['138','139']}, {stock:'3',pdcDepartmentCodes:['138']},
    {stock:'4',pdcDepartmentCodes:[],departmentCode:'139'}, {stock:'5',departmentCode:'137'}];
  assert.deepEqual(Array.from(c.partsDepartmentRows(rows), x=>x.stock), ['1','2']);
  department = '137';
  assert.deepEqual(Array.from(c.partsDepartmentRows(rows), x=>x.stock), ['5']);
  department = '';
  assert.equal(c.partsDepartmentRows(rows).length, 5);
});
