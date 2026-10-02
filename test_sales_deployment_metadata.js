'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

test('sales deployment metadata names the version and pages actually served by the entry point', () => {
  const html = fs.readFileSync('sales/index.html', 'utf8');
  const identity = JSON.parse(fs.readFileSync('deployment-identity.json', 'utf8'));
  const manifest = JSON.parse(fs.readFileSync('deployment-manifest.json', 'utf8'));
  const version = html.match(/src="sales\.js\?v=([^"&]+)/)?.[1];
  const navigation = [...html.matchAll(/class="nav-item(?: active)?"[^>]*data-sales-view="[^"]+"[^>]*>([^<]+)<\/button>/g)].map(m => m[1]);
  assert.ok(version);
  assert.equal(manifest.salesTrackerVersion, version, 'stale-tab identity must identify the served sales release');
  for (const key of ['site', 'dashboard', 'journey', 'ordering', 'cosi_scope', 'crm']) {
    assert.equal(identity['broome_salesperson_' + key].asset_version, version, key);
  }
  assert.deepEqual(identity.broome_salesperson_dashboard.navigation, navigation);
  assert.deepEqual(identity.broome_salesperson_crm.navigation, navigation);
  const modules = {};
  for (const m of html.matchAll(/(?:src|href)="([^"?]+)\?v=([^"&]+)/g)) {
    if (!m[1].startsWith('../')) modules[m[1]] = m[2];
  }
  assert.deepEqual(identity.broome_salesperson_site.asset_versions, modules, 'each asset keeps its actual cache marker');
  assert.equal(identity.broome_salesperson_crm.asset_version, modules['crm-workspace.js']);
  assert.equal(identity.broome_salesperson_finance.asset_version, modules['finance-pipeline.js']);
  assert.equal(identity.broome_salesperson_labels.asset_version, modules['zebra-labels.js']);
  assert.equal(identity.broome_salesperson_customer_emails.asset_version, modules['customer-emails.js']);
  assert.equal(navigation.includes('Leads'), false);
  assert.equal(identity.staging_project_ref, 'cdsmnqxtyyoeoznmbidd');
  assert.equal(identity.production_unchanged, true);
  assert.equal(identity.broome_salesperson_ordering.writes_to_pdc, false);
  assert.equal(identity.broome_salesperson_import_format.workshop_writes, false);
});
