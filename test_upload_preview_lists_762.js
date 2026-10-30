'use strict';
// r762 (F368, Craig 31 Oct 05:27): "give me a preview when i load it" - the dry run lists the stock numbers behind each count.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const DEAL_HEADERS = ['Type', 'Quote #', 'Stock #', 'PO Line', 'Price Level Desc', 'Notes', 'PO #', 'Transaction Sub-Type', 'Transaction Type'];
function htmlTable(title, dataRows) {
  const rows = [[title], ['Company = "01"'], [], DEAL_HEADERS, ...dataRows];
  return new TextEncoder().encode(`<table>${rows.map((r) => `<tr>${r.map((c) => `<td>${c == null ? '' : c}</td>`).join('')}</tr>`).join('')}</table>`);
}

test('r762: dry run returns per-vehicle change lists that match the counts', async () => {
  const { parseRevolutionUpload, dryRun, dealLineKeys } = await import('./supabase/functions/revolution-upload/parse.js');
  const rows = [['D', '1', 'STK1', 1, 'Mat', '', 'PO1', 'Deal', 'Order'], ['D', '1', 'STK2', 1, 'Mat', '', 'PO1', 'Deal', 'Order']];
  const parsed = await parseRevolutionUpload(htmlTable('BT Allocation — Deal Items', rows), 'bt.html');
  const keys = dealLineKeys(parsed.rows).get('STK2');
  const out = dryRun(parsed, { board: { vehicles: [{ stock: 'STK2', dealer_code: '37047', line_keys: keys }], jobs: [] } });
  assert.deepEqual(out.changes.new, [{ stock: 'STK1', lines: 1 }]);
  assert.deepEqual(out.changes.unchanged, [{ stock: 'STK2', lines: 1 }]);
  assert.equal(out.changes.new.length, out.counts.new);
  assert.equal(out.changes.unchanged.length, out.counts.unchanged);
  assert.ok(Array.isArray(out.changes.archived));
});

test('r762: the upload page renders the lists and the cache tags moved', () => {
  const js = fs.readFileSync('pdc-revolution-upload.js', 'utf8');
  assert.match(js, /function renderChanges762\(host, payload\)/);
  assert.match(js, /renderChanges762\(host, payload\);/);
  assert.match(js, /Leaving the board/);
  assert.match(js, /Coming onto the board/);
  assert.match(js, /Held lines/);
  const html = fs.readFileSync('index.html', 'utf8');
  assert.equal((html.match(/r762=2026\.10\.31\.r762/g) || []).length, 2);
  assert.match(fs.readFileSync('pdc-revolution-upload.css', 'utf8'), /\.ru-change-list/);
});
