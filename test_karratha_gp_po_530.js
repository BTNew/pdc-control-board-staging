/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const test = require('node:test');
const acc = require('./sales/sales-accessories.js');

const UP = 'supabase/migrations/20261026070000_r530_karratha_gp_po.sql';
const DOWN = 'supabase/rollbacks/20261026070000_r530_karratha_gp_po.down.sql';
const KEY = 'ab'.repeat(32);

function body(sql, tag) {
  const open = sql.indexOf(tag);
  assert.notEqual(open, -1, tag);
  const start = open + tag.length;
  const end = sql.indexOf(tag, start);
  assert.notEqual(end, -1, tag);
  return sql.slice(start, end);
}
const md5 = text => crypto.createHash('md5').update(text).digest('hex');
const line = (item, extra={}) => ({group:'build',line:'1',item,type:'accessory',sublet:'SUB',po:'',po_state:'blank',notes:'',in_house:false,line_key:KEY,delay:'none',...extra});

test('r530 recognises a Karratha GP purchase order and leaves both importers alone', () => {
  const sql = fs.readFileSync(UP, 'utf8');
  const down = fs.readFileSync(DOWN, 'utf8');
  assert.equal(md5(body(sql, '$k530p$')), '46e12a20dfa13eb9c4bdbabd9f402cfd');
  assert.equal(md5(body(sql, '$k530t$')), 'a453b201d8d56853e6cca39bc6dd5c42');
  assert.equal(md5(body(sql, '$k528p$')), '694b7a7c95b7af1a46040b500dcbf40f');
  assert.equal(md5(body(sql, '$k528r$')), '0e5f6c5e90b6cd91f631671c065fb9c7');
  assert.equal(md5(body(down, '$k528p$')), 'fd4caaffec31dcb70f47756676d40d37');
  assert.equal(md5(body(down, '$k528r$')), 'faab38bf242ef572522dc4c3bf32285f');
  assert.match(body(sql, '$k530p$'), /\^GP\[0-9\]\{8\}\$/);
  assert.equal(body(sql, '$k530p$').includes('37047'), false);
  assert.match(sql, /pin count is not 241/);
  assert.match(sql, /pin count changed/);
  assert.match(sql, /true, 311, 'r530'/);
  assert.match(sql, /AS ok,/);
  assert.match(sql, /AS detail/);
  assert.doesNotMatch(body(sql, '$chk530$'), /expected_function_md5\)\s*=/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION pdc_sales_private\.import_sales_accessories_20261020/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION pdc_sales_private\.import_karratha_sales_accessories_20261025/);
  assert.match(sql, /46d4b464c5c1800c8ada245fb2d33bd3/);
  assert.match(sql, /c70dc4234952dfb58cbc022c98bcecdb/);
  assert.match(down, /sort_order=311/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F144 \|/);
  assert.doesNotMatch(fs.readFileSync('karratha/index.html', 'utf8'), /r530=2026/);
});

test('Karratha accessories and enhancements stay on one line, and only a blank PO flags', () => {
  const html = acc.notesLinesHtml({
    tracking_id:'cf', navision_record_id:'source-cf', order:'00001', stock:'13001', quote:'47439',
    lines:[
      line('Canopy', {type:'accessory', po:'GP10516751', po_state:'po'}),
      line('Light bar', {type:'aftermarket', po:'GP10516752', po_state:'po', line_key:'cd'.repeat(32)}),
      line('IVMS', {type:'special', po:'NO UPDATE', po_state:'no_update', line_key:'ef'.repeat(32)}),
      line('Mats', {type:'miscacc', po:'C&S ONLY', po_state:'cs_only', line_key:'12'.repeat(32)}),
      line('Towbar', {po:'', po_state:'blank', line_key:'34'.repeat(32)})
    ]
  }, {delay_enabled:false});
  assert.equal((html.match(/data-po-list="accessories"/g)||[]).length, 1);
  assert.doesNotMatch(html, /Enhancement|data-po-list="enhancements"/);
  assert.match(html, /sales-notes-po-green[^>]*>GP10516751/);
  assert.match(html, /sales-notes-po-green[^>]*>NO UPDATE/);
  assert.match(html, /sales-notes-po-green[^>]*>C&amp;S ONLY/);
  assert.match(html, /sales-notes-po-red[^>]*>Not raised/);
  assert.doesNotMatch(html, /sales-notes-po-review|data-accessory-delay/);
});
