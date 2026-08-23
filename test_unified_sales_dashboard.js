'use strict';

const assert = require('assert');
const fs = require('fs');
const service = require('./pdc-email-vehicle-location-service.js');

const mapped = service.mapServerVehicle({
  id: '11111111-1111-4111-8111-111111111111',
  version: 7,
  stock_number: '13047224',
  salesperson_code: 'BG',
  salesperson_name: 'Bryce Guthrie',
  sales_preparation: { tint_raised: true, build_po_raised: true, tray_ordered: false },
  workshop_bookings: [{
    booking_id: '22222222-2222-4222-8222-222222222222',
    stage_code: 'FITTING',
    stage_name: 'Fitting',
    status: 'planned',
    scheduled_start_at: '2026-08-24T00:00:00Z',
  }],
});

assert.strictEqual(mapped.salespersonCode, 'BG');
assert.strictEqual(mapped.consultant, 'BG');
assert.strictEqual(mapped.salesPreparation.tintRaised, true);
assert.strictEqual(mapped.salesPreparation.buildPoRaised, true);
assert.strictEqual(mapped.salesWorkshopBookings[0].stageCode, 'FITTING');
assert.strictEqual(mapped.salesWorkshopBookings[0].status, 'planned');

const app = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
const stagingHtml = fs.readFileSync('staging.html', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/20260820074007_unified_sales_dashboard.sql', 'utf8');

assert.ok(!html.includes('id="dashboard-view-select"'));
assert.ok(!stagingHtml.includes('id="dashboard-view-select"'));
assert.ok(!app.includes("on($('#dashboard-view-select'), 'change'"));
assert.ok(!app.includes('populateDashboardViewSelect();'));
assert.ok(!app.includes("if (String(app.dashboardView || 'operations') !== 'operations')"));
// Keep the underlying shared model dormant so it can be restored later
// without exposing the salesperson dashboard Craig removed.
assert.ok(app.includes("value: `sales:${String(record.code).toUpperCase()}`"));
assert.ok(app.includes('renderSalesDashboardBoard()'));
assert.ok(app.includes('service.updateSalesPreparation'));
assert.ok(migration.includes('alter table public.vehicles'));
assert.ok(migration.includes('update_pdc_vehicle_sales_preparation'));
assert.ok(migration.includes('from public.workshop_bookings b'));
assert.ok(!migration.includes('create table public.vehicles'));

console.log('Unified sales dashboard staging contract passed.');
