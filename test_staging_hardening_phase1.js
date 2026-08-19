'use strict';

const assert = require('assert');
const fs = require('fs');
const app = fs.readFileSync('app.js', 'utf8');
const planner = fs.readFileSync('workshop-planner.js', 'utf8');
const index = fs.readFileSync('index.html', 'utf8');
const migration = fs.readFileSync('supabase/staging_only/306_staging_hardening_phase1.sql', 'utf8');
const workflow = fs.readFileSync('.github/workflows/staging-pages-release.yml', 'utf8');
const buildIdentity = fs.readFileSync('scripts/build-staging-deployment-identity.py', 'utf8');
const verifyDeployment = fs.readFileSync('scripts/verify-staging-deployment.py', 'utf8');

function between(source, start, end) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from + start.length);
  assert.ok(from >= 0 && to > from, `could not isolate ${start}`);
  return source.slice(from, to);
}

const localSave = between(app, 'function saveVehicleEdits(', 'async function openVehicleWorkBookingsFromTile');
assert.ok(localSave.includes('Local operational writes are disabled in staging hardening phase 1'), 'legacy local saves must fail closed');
assert.ok(!localSave.includes('runStorageTransaction(') && !localSave.includes('Object.assign(vehicle, nextUpdates)'), 'legacy local saves must not mutate browser state');

const navisionImport = between(app, 'async function importNavisionVehicles()', 'async function applySharedNavisionImport()');
assert.ok(!navisionImport.includes('return importNavisionVehiclesLocal(text)'), 'Navision local fallback must be removed');
const navisionLocal = between(app, 'function importNavisionVehiclesLocal(', 'async function applySharedNavisionImport()');
assert.ok(navisionLocal.includes('Local Navision import is disabled') && !navisionLocal.includes('applyNavisionImportPlan('), 'local Navision import path must be read-only');

const restore = between(app, 'function restoreCrmBackup(', 'function renderBackupStatus(');
assert.ok(restore.includes('CRM backup restore is disabled') && !restore.includes('runStorageTransaction(') && !restore.includes('app.data = buildVehicleData()'), 'backup upload cannot restore local operational state');

const sublet = between(app, 'async function updateSubletField(', 'async function setSubletReturned(');
assert.ok(sublet.includes('canonical server identity') && !sublet.includes("recordVehicleAudit(vehicle, 'Sublet booking updated'") && !sublet.includes('saveVehicleEdits(key,'), 'non-canonical Sublet rows must have no local fallback');
assert.ok(app.includes('function subletRowIsServerWritable('), 'Sublet rendering must identify authoritative writable rows');

const persist = between(planner, 'function workshopPersistVerifiedCanonicalLink(', 'function workshopVehicleLinkValuesEqual(');
assert.ok(persist.includes('Browser-local canonical-link persistence is disabled') && !persist.includes('setItem(') && !persist.includes('saveVehicleEdits'), 'canonical links cannot persist in browser storage');
const ref = between(planner, 'async function workshopVerifiedCanonicalVehicleRef(', 'function workshopVehicleLinkReadinessStatus(');
assert.ok(ref.includes('canonical_server_identity_required') && !ref.includes('persistLink('), 'scheduling must fail closed without snapshot canonical identity');

assert.ok(migration.includes("version='306'") && migration.includes("set_config('pdc.parts_completion_revision_managed','on',true)") && migration.includes("current_setting('pdc.parts_completion_revision_managed', true) = 'on'"), 'migration must suppress trigger fan-out for Parts completion');
assert.ok(migration.includes("'parts_completed'") && migration.includes("'replayed'") && migration.includes('update public.pdc_email_vehicle_revision'), 'migration must retain receipt and single revision semantics');

assert.ok(index.includes('pdc-release-compatibility.js'), 'runtime must load release compatibility guard');
assert.ok(workflow.includes('build-staging-deployment-identity.py') && workflow.includes('verify-staging-deployment.py') && workflow.includes('actions/deploy-pages'), 'staging Pages workflow must generate and verify identity');
assert.ok(buildIdentity.includes('GITHUB_SHA') && buildIdentity.includes('staging_project_ref'), 'identity must derive from deployed build SHA');
assert.ok(verifyDeployment.includes('cdsmnqxtyyoeoznmbidd') && verifyDeployment.includes('release compatibility'), 'deployment verifier must pin staging project and require server compatibility');

console.log('Staging hardening Phase 1 contract passed.');
