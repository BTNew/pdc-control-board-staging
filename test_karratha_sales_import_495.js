/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
// r495 (F108): Karratha sales export recognition for the daily import (mirror Broome sales format).
const test = require('node:test');
const assert = require('node:assert/strict');
const { createImporter } = require('./broome-navision-import.js');
const parser = require('./sales/navision-orders.js');
const karratha = require('./sales/karratha-sales-import.js');

const header = 'Order\tBatch\tCOSI\tDealer\tSalesperson\tCustomer Surname\tModel Description\tETA At Kewdale Yard';
const karrathaText = header + '\n0099001\t\tYes\t014450\tQK 19900101\tExample\tExample Hilux\t15/11/2026\n0099002\t13009999\tYes\t014450\tQL 19900202\tExample\tExample Hilux\t16/11/2026';
const broomeText = header + '\n0099001\t\tYes\t037047\tBG 19751217\tExample\tExample Hilux\t15/11/2026';
const mixedText = header + '\n0099001\t\tYes\t014450\tQK 19900101\tExample\tExample Hilux\t15/11/2026\n0099002\t\tYes\t037047\tBG 19751217\tExample\tExample Hilux\t15/11/2026';

test('same Broome sales parse format; Karratha importer maps 014450 -> 14450 (Broome parser maps 037047 -> 37047)', () => {
  assert.equal(parser.parse(broomeText)[0].dealer_code, '37047');
  const host = { BROOME_NAVISION_ORDERS: parser };
  const rows = karratha.createImporter(host).parse(karrathaText);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].dealer_code, '14450');
  assert.equal(rows[0].consultant, 'QK');
});

test('recognise: dealer column 014450 => karratha_sales, Pilbara route, not Broome Sales', () => {
  const r = karratha.recognise({ text: karrathaText, fileName: 'anything.tsv', subject: 'Daily export' });
  assert.equal(r.kind, 'karratha_sales');
  assert.equal(r.uploadProfile, 'pilbara');
  assert.equal(r.goesIntoBroomeSales, false);
  assert.equal(r.goesIntoKarrathaSales, true);
  assert.ok(r.reasons.includes('dealer_column_14450'));
});

test('recognise: subject and filename patterns without body still mark Karratha', () => {
  const bySubject = karratha.recognise({ subject: 'Karratha Toyota Sales Export 2026-10-23' });
  assert.equal(bySubject.kind, 'karratha_sales');
  assert.equal(bySubject.uploadProfile, 'pilbara');
  const byFile = karratha.recognise({ fileName: 'Navision_014450_Karratha.tsv' });
  assert.equal(byFile.kind, 'karratha_sales');
});

test('recognise: Broome dealer/subject stays Broome; mixed dealers are not auto-routed to either', () => {
  const b = karratha.recognise({ text: broomeText, subject: 'Broome Sales Navision' });
  assert.equal(b.kind, 'broome_sales');
  assert.equal(b.uploadProfile, 'broome');
  assert.equal(b.goesIntoKarrathaSales, false);
  const m = karratha.recognise({ text: mixedText });
  assert.equal(m.kind, 'other');
  assert.ok(m.reasons.includes('mixed_broome_and_karratha_dealers'));
});

test('Broome sales import RPC path rejects a Karratha-only export (does not go into Broome Sales)', async () => {
  const calls = [];
  const host = {
    PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' },
    PDC_AUTH_CONTEXT: { userId: 'example-admin', email: 'admin@example.invalid', role: 'administrator' },
    BROOME_NAVISION_ORDERS: parser,
    PDC_SUPABASE: { rpc: async (name, args) => { calls.push({ name, args }); return { data: null, error: { message: 'A Broome Toyota dealer 37047 export is required' } }; } }
  };
  const api = createImporter(host);
  await assert.rejects(() => api.preview(karrathaText), /Broome Toyota dealer 37047|Karratha|dealer/);
  // Even if the client parsed rows, Broome's importer sends them to import_broome_sales_orders only after parse;
  // parse itself does not rewrite 014450 into 37047, so the server rejects.
  const rows = parser.parse(karrathaText);
  assert.ok(rows.every(r => ['14450', '014450'].includes(r.dealer_code)));
  assert.ok(rows.every(r => r.dealer_code !== '37047'));
});

test('Karratha importer mirror: parse keeps 14450 only; preview calls import_karratha_sales_orders never Broome', async () => {
  const calls = [];
  const host = {
    PDC_SUPABASE_CONFIG: { projectRef: 'cdsmnqxtyyoeoznmbidd' },
    PDC_AUTH_CONTEXT: { userId: 'example-admin', email: 'admin@example.invalid', role: 'administrator' },
    BROOME_NAVISION_ORDERS: parser,
    PDC_SUPABASE: { rpc: async (name, args) => {
      calls.push({ name, args });
      return { data: { accepted: 2, without_stock: 1, skipped_unsold: 0, visibility_updates: 0, changed: 0, applied: false }, error: null };
    } }
  };
  const api = karratha.createImporter(host);
  assert.equal(api.parse(karrathaText).length, 2);
  assert.throws(() => api.parse(broomeText), /14450/);
  const pending = await api.preview(karrathaText);
  assert.equal(pending.route, 'karratha_sales_orders');
  assert.equal(pending.dealerCode, '14450');
  assert.equal(calls.length, 1);
  assert.equal(calls[0].name, 'import_karratha_sales_orders');
  assert.equal(calls[0].args.p_apply, false);
  assert.ok(calls.every(c => c.name !== 'import_broome_sales_orders'));
});
