/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('app.js','utf8');
const start = source.indexOf('function vehicleJobcardSearchNumbers(');
const end = source.indexOf('function incomingSearchText(',start);
const context = { vehicleJobcardNumber: v => v.jobcard || '' };
vm.createContext(context); vm.runInContext(source.slice(start,end),context);
const vehicle={jobcard:'J138000001',pdcJobCardNumbers:['J139125060','CW123456'],
  pdcQcOperationLines:[{jobCardNumber:'J139999999'}]};
for(const q of ['J138000001','139125060','j139-125060','CW 123456','999999'])
  assert.equal(context.vehicleMatchesJobcardSearch(vehicle,q),true,q);
for(const q of ['J139888888','','---']) assert.equal(context.vehicleMatchesJobcardSearch(vehicle,q),false,q);
assert.equal(context.vehicleMatchesJobcardSearch({},'123'),false);
console.log('Primary, secondary, partial and formatted jobcard search: PASS');
