/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r403 (F12): every server code the planner can get back has plain English;
// protected_booking no longer reaches staff raw.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const vm = require('vm');

const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const service = fs.readFileSync('workshop-data-service.js', 'utf8');
function extract(src, name, opener = ') {') {
  const start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, name);
  let i = src.indexOf(opener, start) + opener.length - 1, depth = 0;
  for (; i < src.length; i += 1) {
    if (src[i] === '{') depth += 1;
    if (src[i] === '}' && --depth === 0) return src.slice(start, i + 1);
  }
  throw new Error(name);
}
function constBlock(src, name) {
  const start = src.indexOf(`const ${name} =`);
  assert.ok(start >= 0, name);
  return src.slice(start, src.indexOf(']);', start) >= 0 && name.endsWith('ERRORS') ? src.indexOf(']);', start) + 3 : src.indexOf('});', start) + 3);
}

const codes = (() => {
  const ctx = {};
  vm.createContext(ctx);
  vm.runInContext(constBlock(service, 'WORKSHOP_CANONICAL_MUTATION_ERRORS') + '\nthis.codes=[...WORKSHOP_CANONICAL_MUTATION_ERRORS];', ctx);
  return ctx.codes;
})();

function describer({ admin }) {
  const ctx = {
    workshopAdministratorCanMove: () => admin,
    workshopAdministratorErrorDetail: result => `Server code: ${result.error}.`,
    workshopVehicleConflictDetail: () => '',
  };
  vm.createContext(ctx);
  vm.runInContext(constBlock(planner, 'WORKSHOP_PLAIN_ERROR_MESSAGES') + '\n' + extract(planner, 'workshopDescribeSharedActionError') + '\nthis.describe=workshopDescribeSharedActionError;', ctx);
  return ctx.describe;
}

test('protected_booking reads as plain English for staff and administrators', () => {
  for (const admin of [false, true]) {
    const text = describer({ admin })({ ok: false, error: 'protected_booking' });
    assert.match(text, /already been started/);
    assert.match(text, /Ask a manager to re-plan it/);
    assert.equal(text.includes('protected_booking'), false);
    assert.equal(text.includes('The server rejected this change'), false);
  }
});

test('every canonical mutation code has its own plain message', () => {
  assert.ok(codes.length >= 50, `found ${codes.length} codes`);
  const describe = describer({ admin: true });
  const missing = codes.filter(code => {
    const text = describe({ ok: false, error: code });
    return text.includes(code) || text.startsWith('The server rejected this change');
  });
  assert.deepEqual(missing, []);
});

test('the ten other previously raw codes are mapped', () => {
  const describe = describer({ admin: true });
  for (const code of ['invalid_admin_block_type', 'admin_block_not_found', 'invalid_label', 'invalid_idempotency_key',
    'idempotency_conflict', 'receipt_not_found', 'undo_actor_mismatch', 'already_undone', 'undo_expired', 'undo_conflict']) {
    const text = describe({ ok: false, error: code });
    assert.equal(text.includes(code), false, code);
    assert.ok(text.length > 30, code);
  }
});

test('an unknown code still falls back safely', () => {
  assert.match(describer({ admin: false })({ ok: false, error: 'something_new' }), /No update was saved/);
});
