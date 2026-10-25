/* © 2026 Specialise Pty Ltd ATFT Specialise Trust (ABN 33 539 964 819). All rights reserved. Proprietary and confidential: no copying, modification, distribution, resale or commercial use without written permission. See LICENSE. */
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const test = require('node:test');
const acc = require('./sales/sales-accessories.js');

const MIG = 'supabase/migrations/20261025120000_r528_karratha_sales_accessories.sql';
const DOWN = 'supabase/rollbacks/20261025120000_r528_karratha_sales_accessories.down.sql';
const KEY = 'ab'.repeat(32);
const row = (patch) => ({tracking_id:'cf',navision_record_id:'source-cf',order:'00001',stock:'13001',cosi:true,source_current:true,salesperson_code:'CF',...patch});
const line = (item, extra={}) => ({group:'build',line:'1',item,type:'accessory',sublet:'SUB',po:'',po_state:'blank',notes:'',in_house:false,line_key:KEY,delay:'none',...extra});
const record = (patch={}) => ({tracking_id:'cf',navision_record_id:'source-cf',order:'00001',stock:'13001',quote:'47439',source_file:'KTA Allocation - Deal Items - Job 1.xls',snapshot_at:'2026-10-25T09:27:15Z',
  derived:{build:{state:'red',reason:'po_not_raised'},tint:{state:'grey',reason:'not_on_quote'},tray:{state:'grey',reason:'not_on_quote'}},
  lines:[line('Canopy')],...patch});

function body(sql, tag) {
  const open = sql.indexOf(tag);
  assert.notEqual(open, -1, tag);
  const start = open + tag.length;
  const end = sql.indexOf(tag, start);
  assert.notEqual(end, -1, tag);
  return sql.slice(start, end);
}
function md5(text) { return crypto.createHash('md5').update(text).digest('hex'); }

function hostFor(branchKey) {
  const calls = [];
  const host = {
    PDC_AUTH_CONTEXT:{userId:'u'},
    addEventListener(){},
    PDC_SUPABASE:{rpc(name){return new Promise(resolve => calls.push({name, resolve}));}}
  };
  if (branchKey === 'karratha') {
    host.PDC_SALES_BRANCH = {key:'karratha'};
    host.BROOME_SALES_BRANCH = {roster(){ return ['CF','SL']; }};
  }
  return {host, calls};
}

test('Karratha Sales uses the CF/SL roster and does not offer the Broome delay write', async () => {
  const {host, calls} = hostFor('karratha');
  const cf = row(), bg = row({tracking_id:'bg',navision_record_id:'source-bg',salesperson_code:'BG',stock:'13002',order:'00002'});
  const api = acc.createSalesAccessories(host);
  api.init({getRows:()=>[cf, bg], getContext:()=>({role:'administrator'}), getSalesperson:()=>'', getToken:()=>'t'});
  const pending = api.refresh();
  assert.equal(calls[0].name, 'get_broome_sales_accessories');
  calls[0].resolve({data:{context:{role:'administrator'}, items:[record(), record({tracking_id:'bg',navision_record_id:'source-bg',order:'00002',stock:'13002'})]}});
  await pending;
  const cfHtml = api.notesPanelHtml(cf);
  assert.match(cfHtml, /Canopy/);
  assert.doesNotMatch(cfHtml, /data-accessory-delay|Delay until yard hold/);
  const bgHtml = api.notesPanelHtml(bg);
  assert.doesNotMatch(bgHtml, /Canopy|data-accessory-delay|Delay until yard hold/);
  assert.match(bgHtml, /No accessory lines in the latest sales export\./);
  assert.equal(api.tickFor(bg, 'build_po'), null);
  const before = calls.length;
  await api.setDelay(cf.tracking_id, KEY, true);
  assert.equal(calls.length, before);
});

test('Broome Sales keeps BG/AW/PM/CW and the delay checkbox when no branch is set', async () => {
  const {host, calls} = hostFor('broome');
  const bg = row({tracking_id:'bg',navision_record_id:'source-bg',salesperson_code:'BG'});
  const cf = row();
  const api = acc.createSalesAccessories(host);
  api.init({getRows:()=>[bg, cf], getContext:()=>({role:'administrator'}), getSalesperson:()=>'', getToken:()=>'t'});
  const pending = api.refresh();
  calls[0].resolve({data:{context:{role:'administrator'}, items:[record({tracking_id:'bg',navision_record_id:'source-bg'})]}});
  await pending;
  assert.match(api.notesPanelHtml(bg), new RegExp('data-accessory-delay="'+KEY+'"'));
  assert.match(api.notesPanelHtml(bg), /Delay until yard hold/);
  const cfHtml = api.notesPanelHtml(cf);
  assert.doesNotMatch(cfHtml, /Canopy|data-accessory-delay/);
  assert.match(cfHtml, /No accessory lines in the latest sales export\./);
  const module = fs.readFileSync('sales/sales-accessories.js', 'utf8');
  assert.deepEqual([...new Set([...module.matchAll(/rpc\('([a-z_]+)'/g)].map(m => m[1]))].sort(), ['get_broome_sales_accessories','set_broome_sales_accessory_delay']);
  assert.doesNotMatch(module, /import_karratha_sales|import_sales_accessories/);
});

test('r528 SQL is a dedicated Karratha importer and leaves the Broome writer alone', () => {
  const sql = fs.readFileSync(MIG, 'utf8');
  const down = fs.readFileSync(DOWN, 'utf8');
  const pins = {
    '$k528n$':'ef85e5393c5039ac4e8421f6b058c405',
    '$k528c$':'b3fb58ca909d0f706426a4996dd9d489',
    '$k528p$':'fd4caaffec31dcb70f47756676d40d37',
    '$k528i$':'c70dc4234952dfb58cbc022c98bcecdb',
    '$k528r$':'faab38bf242ef572522dc4c3bf32285f'
  };
  for (const [tag, hash] of Object.entries(pins)) assert.equal(md5(body(sql, tag)), hash, tag);
  const getBody = body(sql, '$function$');
  assert.equal(md5(getBody), 'ff5de642f867c80b62d6c3fef987f131');
  assert.match(getBody, /dealer_code'='14450'/);
  assert.match(body(down, '$function$'), /Broome Toyota \(37047\) only/);
  assert.equal(md5(body(down, '$function$')), '2f7f060cdaca01cc2763a15b921debf8');
  const importer = body(sql, '$k528i$');
  assert.equal(importer.includes('37047'), false);
  assert.doesNotMatch(importer, /INSERT INTO public\.|public\.vehicles|workshop_bookings|tracked_orders/);
  assert.match(importer, /internet_message_id/);
  assert.match(importer, /pdc@pmgwa\.com\.au/);
  assert.match(importer, /noreply@revolutionsoftware\.com\.au/);
  assert.match(sql, /CREATE FUNCTION pdc_sales_private\.import_karratha_sales_accessories_20261025\(p_action text, p_envelope jsonb, p_rows jsonb DEFAULT NULL::jsonb, p_expected_preview_hash text DEFAULT NULL::text\)\n RETURNS jsonb/);
  assert.match(sql, /Dept = "105"/);
  assert.match(sql, /Dept = "107"/);
  assert.match(sql, /Dept = "135"/);
  assert.match(sql, /CHECK \(dealer_code='14450'\)/);
  assert.match(sql, /pin count is not 236/);
  assert.match(sql, /pin count is not 241/);
  assert.match(sql, /true,309,'r528'/);
  assert.doesNotMatch(sql, /CREATE OR REPLACE FUNCTION pdc_sales_private\.import_sales_accessories_20261020/);
  assert.doesNotMatch(sql, /CREATE FUNCTION pdc_sales_private\.import_karratha_sales_orders/);
  assert.match(down, /pin count is not 241/);
  assert.match(down, /pin count is not 236/);
  assert.match(down, /sort_order=309/);
  assert.match(down, /qa_bay_technician_527/);
  const broome = fs.readFileSync('supabase/migrations/20261023091500_r505_outlook_pdc_mailbox.sql', 'utf8');
  assert.match(broome, /dealer_code='37047'/);
  assert.match(fs.readFileSync('sales/index.html', 'utf8'), /sales-accessories\.js\?[^"]*r528=2026\.10\.25\.r528&amp;no-yard-flag=2026\.10\.22\.r486"/);
  assert.match(fs.readFileSync('docs/FAULT_LOG.md', 'utf8'), /\| F142 \|/);
  assert.doesNotMatch(fs.readFileSync('karratha/index.html', 'utf8'), /r528=2026\.10\.25\.r528/);
});
