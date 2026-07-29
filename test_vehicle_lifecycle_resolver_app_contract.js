'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8').replace(/\r\n/g, '\n');
const stagingConfig = fs.readFileSync(path.join(root, 'pdc-supabase-config.staging.js'), 'utf8');
const productionConfigPath = fs.existsSync(path.join(root, 'pdc-supabase-config.js'))
  ? path.join(root, 'pdc-supabase-config.js')
  : path.join(root, 'pdc-supabase-config.example.js');
const productionConfig = fs.readFileSync(productionConfigPath, 'utf8');
const stagingHtml = fs.readFileSync(path.join(root, 'staging.html'), 'utf8');
const lifecycleModule = fs.readFileSync(path.join(root, 'vehicle-lifecycle-actions.js'), 'utf8');

assert(!app.includes('&limit=1'), 'the old lifecycle first-match limit=1 query must be removed');
assert(app.includes('&limit=2'), 'explicit staging rollback must detect a second direct-read candidate');
assert(app.includes('rows.length > 1'), 'rollback direct-read path must return ambiguity, never the first row');
console.log('PASS 1: first-match lookup is gone and rollback direct-read detects ambiguity');

assert(stagingConfig.includes("projectRef: 'cdsmnqxtyyoeoznmbidd'"));
assert(stagingConfig.includes('resolverRollbackDirectRead: false'));
assert(!productionConfig.includes('resolverRollbackDirectRead'));
assert(app.includes('vehicleLifecycleResolverRollbackEnabled(window.PDC_SUPABASE_CONFIG)'));
assert(app.includes("mode: 'staging_direct_read'"));
assert(lifecycleModule.includes("STAGE2B_STAGING_SUPABASE_URL = 'https://cdsmnqxtyyoeoznmbidd.supabase.co'"));
assert(lifecycleModule.includes("STAGE2B_STAGING_SITE_ORIGIN = 'https://btnew.github.io'"));
assert(lifecycleModule.includes("'/pdc-control-board-staging/'"));
console.log('PASS 2: rollback is observable, disabled by default, and absent from production config');

assert(app.includes("createPdcSupabaseTableRealtimeSubscription('vehicle_lifecycle_resolver_revision'"));
assert(app.includes("new CustomEvent('pdc-vehicle-lifecycle-resolver-refresh'"));
assert(app.includes('window.__vehicleLifecycleIdentityResolver.start()'));
assert(app.includes('window.__vehicleLifecycleIdentityResolver.stop()'));
assert(app.includes("reconcile?.('auth_ready')"));
assert(app.includes("reconcile?.('online_return')"));
assert(app.includes("reconcile?.('visibility_return')"));
console.log('PASS 3: resolver revision Realtime refresh starts and tears down with auth lifecycle');

const resolverCallSites = app.match(/await vehicleLifecycleSharedRef\(vehicle\)/g) || [];
const resolvedGuards = app.match(/ref\.outcome !== 'resolved'/g) || [];
assert.strictEqual(resolverCallSites.length, 7, 'PMB transfer, Ready for QC, PIT movement, QC sign-off, Vehicle Detail deletion, legacy RFT transfer and collection are the only lifecycle consumers');
assert.strictEqual(resolvedGuards.length, 7, 'every lifecycle consumer must require an explicit resolved outcome');
assert((app.match(/ref\.isArchived/g) || []).length >= 7, 'every lifecycle mutation must reject archived vehicles');
console.log('PASS 4: all seven lifecycle consumers fail closed on outcome and archive state');

assert(app.includes("return { outcome: 'service_unavailable' }"));
assert(app.includes('configured shared lifecycle actions fail closed'));
const resolverFunction = app.match(/async function vehicleLifecycleSharedRef[\s\S]*?\n}\n\nfunction describeVehicleLifecycleResolutionOutcome/);
assert(resolverFunction, 'vehicleLifecycleSharedRef function must exist');
assert(!resolverFunction[0].includes('vehicleKey('), 'C1 resolver must not reverse-map mutable local display identity');
assert(!resolverFunction[0].includes('displayStockNumber('), 'typed stock identity must not use display/order fallbacks');
console.log('PASS 5: configured shared lifecycle failures cannot silently switch to local authority');

assert.strictEqual((app.match(/recordVehicleAudit\([^\n]*shared:\s*true/g) || []).length, 0,
  'shared lifecycle success paths must not write browser-local audit history');
assert(app.includes('if (change.shared !== true)'));
assert(/title: 'Vehicle ready for transport \(RFT\)'[\s\S]{0,220}shared: true/.test(app),
  'shared RFT salesperson draft must suppress browser-local audit writes');
assert(/title: 'Vehicle completed and collected'[\s\S]{0,220}shared: true/.test(app),
  'shared collection salesperson draft must suppress browser-local audit writes');
console.log('PASS 6: shared lifecycle actions do not create browser-local audit authority');

const appVersion = (app.match(/const\s+APP_VERSION\s*=\s*['\"]([^'\"]+)['\"]/) || [])[1];
assert(appVersion && stagingConfig.includes(`resolverAssetVersion: '${appVersion}'`), 'staging lifecycle bridge cache key must match the current APP_VERSION');
assert(appVersion && stagingHtml.includes(`app.js?v=${appVersion}`), 'staging app cache key must match the current APP_VERSION');
assert(app.includes('vehicleLifecycle.resolverAssetVersion || APP_VERSION'));
console.log('PASS 7: staging cache busts both app and resolver module without production-file changes');
