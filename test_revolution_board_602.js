const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync } = require('node:fs');

async function parser() {
  return import('./supabase/functions/revolution-upload/parse.js');
}

const DEAL_HEADERS = ['Type', 'Quote #', 'Stock #', 'PO Line', 'Price Level Desc', 'Notes', 'PO #', 'Transaction Sub-Type', 'Transaction Type'];

function htmlTable(title, dataRows, headers = DEAL_HEADERS) {
  const rows = [[title], ['Company = "01"'], [], headers, ...dataRows];
  const html = `<table>${rows.map((row) => `<tr>${row.map((cell) => `<td>${cell == null ? '' : cell}</td>`).join('')}</tr>`).join('')}</table>`;
  return new TextEncoder().encode(html);
}

function dealRow(stock, line, quote = '43925') {
  return ['D', quote, stock, line, `Accessory ${line}`, '', `PO${line}`, 'Deal', 'Order'];
}

test('a postgres line key matches the sales accessory array', async () => {
  const { accessoryLineKey } = await parser();
  assert.equal(
    accessoryLineKey('43925', '1', 'Deal', 'Mat', 'Order', '', 'PO9', 1),
    '054c427386601be1d518c37ebc12e86aaacf7c5ad9bb1ddd150dbb56be136840',
  );
});

test('thirty three lines of one stock are one vehicle, not thirty three new vehicles', async () => {
  const { parseRevolutionUpload, dryRun, dealLineKeys, previewAllowsApply } = await parser();
  const rows = [];
  for (let line = 1; line <= 33; line += 1) rows.push(dealRow('13136535', line));
  const parsed = await parseRevolutionUpload(htmlTable('BT Allocation — Deal Items', rows), 'bt-synthetic.html');
  assert.equal(parsed.kind, 'bt_deal_items');
  assert.equal(parsed.rows.length, 33);

  const empty = dryRun(parsed, { board: { vehicles: [], jobs: [] } });
  assert.equal(empty.counts.new, 1);
  assert.equal(empty.counts.updated, 0);
  assert.equal(empty.counts.unchanged, 0);
  assert.equal(empty.needs_admin_confirm, false);
  assert.equal(empty.counts.errors, 0);
  assert.equal(empty.ok, true);
  assert.equal(empty.summary, '1 new, 1 vehicle/33 lines new, errors 0');
  assert.equal(previewAllowsApply(), false);
  assert.equal(empty.apply_enabled, false);

  const keys = dealLineKeys(parsed.rows).get('13136535');
  assert.equal(keys.length, 33);
  const same = dryRun(parsed, {
    board: { vehicles: [{ stock: '13136535', quote: '43925', dealer_code: '37047', line_keys: keys }], jobs: [] },
  });
  assert.equal(same.counts.new, 0);
  assert.equal(same.counts.updated, 0);
  assert.equal(same.counts.unchanged, 1);
  assert.equal(same.counts.errors, 0);
  assert.equal(same.needs_admin_confirm, false);
  assert.equal(same.ok, true);
  assert.equal(same.summary, '0 new, 1 vehicle/33 lines unchanged, errors 0');

  const changed = dryRun(parsed, {
    board: { vehicles: [{ stock: '13136535', dealer_code: '37047', line_keys: ['abc'] }], jobs: [] },
  });
  assert.equal(changed.counts.new, 0);
  assert.equal(changed.counts.updated, 1);
  assert.equal(changed.counts.unchanged, 0);
  assert.equal(changed.needs_admin_confirm, false);
  assert.equal(changed.ok, true);
  assert.equal(changed.summary, '0 new, 1 vehicle/33 lines updated, errors 0');

  const wideRows = [];
  for (let stock = 1; stock <= 16; stock += 1) wideRows.push(dealRow(`STK${stock}`, 1, '1'));
  const wide = dryRun(await parseRevolutionUpload(htmlTable('BT Allocation — Deal Items', wideRows)), { board: { vehicles: [], jobs: [] } });
  assert.equal(wide.counts.new, 16);
  // r761 (F367): new cars are not gated; only cars leaving the board are.
  assert.equal(wide.needs_admin_confirm, false);
  assert.equal(wide.ok, true);
  assert.equal(wide.errors.some((error) => error.code === 'sanity_gate'), false);
});

test('the board snapshot does not rewrite Kajel', () => {
  const up = readFileSync('supabase/migrations/20261028123000_r602_revolution_board.sql', 'utf8');
  const down = readFileSync('supabase/rollbacks/20261028123000_r602_revolution_board.down.sql', 'utf8');
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION pdc_sales_private.import_sales_accessories_20261020'), false);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION pdc_codex_intake_private.revolution_service_rows_20261006'), false);
  assert.equal(up.includes('CREATE OR REPLACE FUNCTION public.pdc_pilbara_service_apply_v1'), false);
  assert.match(up, /9be0883b1a555f48f3c1ba9fa111c891/);
  assert.match(up, /b62fb7c29ffd2a1629f214f696e5cb14/);
  assert.match(up, /fd05b9eef69498002ac06dd68e01cdff/);
  assert.match(up, /sort_order=373/);
  assert.match(up, /F216/);
  assert.match(up, /service_role/);
  assert.match(up, /superseded_receipt_id IS NULL/);
  assert.match(down, /DROP FUNCTION IF EXISTS public.pdc_revolution_board_602\(text\)/);
  assert.equal(up.includes('previewAllowsApply'), false);
});
