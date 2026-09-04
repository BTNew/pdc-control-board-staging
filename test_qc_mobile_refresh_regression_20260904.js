'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const appSource = fs.readFileSync('app.js', 'utf8');
const styles = fs.readFileSync('styles.css', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');

function extractFunction(name) {
  const start = appSource.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} exists`);
  let parens = 0;
  let open = -1;
  for (let index = appSource.indexOf('(', start); index < appSource.length; index += 1) {
    if (appSource[index] === '(') parens += 1;
    if (appSource[index] === ')' && --parens === 0) {
      open = appSource.indexOf('{', index);
      break;
    }
  }
  assert.ok(open >= 0, `body for ${name} exists`);
  let depth = 0;
  for (let index = open; index < appSource.length; index += 1) {
    if (appSource[index] === '{') depth += 1;
    if (appSource[index] === '}' && --depth === 0) return appSource.slice(start, index + 1);
  }
  throw new Error(`unterminated ${name}`);
}

const refreshLoader = appSource.slice(
  appSource.indexOf('function operationalRefreshCommonLoaders'),
  appSource.indexOf('function getOperationalRefreshCoordinator'),
);
const workOperationLoader = refreshLoader.slice(
  refreshLoader.indexOf('workOperationStates:'),
  refreshLoader.indexOf('routeAuthority:'),
);
assert.match(
  workOperationLoader,
  /if \(route !== 'workshop'\) return \{ ok: true, skipped: true \};/,
  'QC and other non-Workshop routes must not call the revoked unscoped Workshop snapshot',
);
assert.match(
  workOperationLoader,
  /if \(typeof service\.setScope !== 'function' \|\| typeof workshopState !== 'function'\) return \{ ok: true, skipped: true \};/,
  'Workshop refresh must fail closed when a scoped station snapshot cannot be established',
);
assert.match(workOperationLoader, /service\.setScope/);
assert.match(workOperationLoader, /service\.loadSnapshot\(`operational_refresh:\$\{route\}`\)/);

const context = {
  vehicleInQualityControlGate: vehicle => vehicle.pdcLocation === 'QC',
};
vm.createContext(context);
vm.runInContext(`
  ${extractFunction('qcPageOperationLines')}
  ${extractFunction('qcPageVehicleIsEligible')}
  this.qcPageVehicleIsEligible = qcPageVehicleIsEligible;
`, context);
const qcVehicle = {
  __emailVehicleServerAuthoritative: true,
  pdcLocation: 'QC',
  pdcQcComplete: false,
  pdcQcOperationLinesProjectionPresent: true,
  pdcQcOperationLines: [{
    active: true,
    lineIdentity: 'source:dcfa128d-7a97-4fc6-b74b-f4d289cc461b',
    stageCode: 'FITTING',
    operationNo: 'OP1',
    completed: false,
  }],
};
assert.strictEqual(
  context.qcPageVehicleIsEligible(qcVehicle),
  true,
  'an active vehicle already at the QC gate must render while its operation checklist is incomplete',
);
assert.strictEqual(
  context.qcPageVehicleIsEligible({ ...qcVehicle, pdcQcOperationLinesProjectionPresent: false }),
  false,
  'missing authoritative QC projection stays fail closed',
);
assert.strictEqual(
  context.qcPageVehicleIsEligible({ ...qcVehicle, pdcQcOperationLines: [] }),
  false,
  'an empty authoritative operation-line projection stays fail closed',
);

assert.match(
  styles,
  /@media \(max-width: 600px\)[\s\S]*?\.qc-page-panel > \.panel-header\s*\{[^}]*flex-direction:\s*column;[^}]*align-items:\s*stretch;/,
  'the QC intro and actions stack at a 390px-class viewport',
);
assert.match(
  styles,
  /@media \(max-width: 600px\)[\s\S]*?\.qc-page-panel \.pdc-operational-refresh-status\s*\{[^}]*white-space:\s*normal;[^}]*overflow-wrap:\s*anywhere;/,
  'the full QC refresh error/status remains readable instead of ellipsizing on mobile',
);
assert.match(
  styles,
  /@media \(max-width: 600px\)[\s\S]*?\.qc-page-panel > \.panel-header > \.panel-actions \.pdc-operational-refresh-control\s*\{[^}]*width:\s*100%;[^}]*flex-wrap:\s*wrap;/,
  'the injected QC refresh control occupies the mobile panel-actions row instead of squeezing its status against the right edge',
);
assert.match(
  styles,
  /@media \(max-width: 600px\)[\s\S]*?\.qc-page-panel \.pdc-operational-refresh-status\s*\{[^}]*flex:\s*1 1 100%;[^}]*width:\s*100%;/,
  'the QC refresh status receives a full mobile row so normal and long error text wrap readably',
);
assert.match(styles, /\.qc-vehicle-card\s*\{[\s\S]*?width:\s*100%;[\s\S]*?min-height:\s*86px;/);
assert.match(styles, /@media \(max-width: 900px\)\s*\{[\s\S]*?\.qc-page-layout\s*\{\s*grid-template-columns:\s*1fr;/);
assert.strictEqual(
  (indexSource.match(/qc-mobile-refresh=2026\.09\.04\.02/g) || []).length,
  2,
  'both changed frontend assets carry the QC mobile repair cache marker',
);

console.log('QC mobile refresh/projection regression: PASS');
