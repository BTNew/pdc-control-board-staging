'use strict';

const fs = require('fs');
const path = require('path');
const assert = require('assert');

const root = __dirname;
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const htmlFiles = ['index.html', 'no-vehicles.html', 'test-50.html', 'test-75.html', 'test-100.html'];
const version = '2026.07.16.25-workshop-drop-followup';

assert.match(app, new RegExp(`const APP_VERSION = '${version.replaceAll('.', '\\.')}'`));
assert.match(app, /pdc-grid-station-heading[^`]*title="\$\{escapeHtml\(label\)\}"><span>\$\{escapeHtml\(label\)\}<\/span>/);
assert.match(app, /const marker = complete \? '✓' : blocked \? '!' : required \? '•' : '–';/);

for (const label of ['Parts', 'Tint', 'Bus 4x4', 'Hoist', 'Fitting', 'Fab', 'Elec', 'Tyre', 'Sublet', 'Pit']) {
  assert.ok(app.includes(label), `Missing full stage label: ${label}`);
}
assert.ok(app.includes("const rowOrder = ['parts', 'tint', 'bus4x4', 'hoist', 'fitting', 'fabrication', 'electrical', 'tyre', 'sublet', 'pitInspection']"), 'Work-status rows must show Parts first, Bus 4x4 third and Sublet second-last');
assert.ok(app.includes("{ key: 'sublet', label: 'SUBLET', short: 'S', requireKey: 'pdcRequiresSublet', completeKey: 'pdcCompleteSublet'"), 'The Sublet required/completed work control is missing');

const marker = '2026.07.10.23 — Uniform Stage Matrix';
const matrixCss = css.slice(css.indexOf(marker));
assert.ok(matrixCss.length > 1500, 'Uniform Stage Matrix CSS block is missing');
assert.match(matrixCss, /--pdc-grid-stations-width:\s*556px/);
assert.match(matrixCss, /--pdc-station-template:\s*repeat\(10, 52px\)/);
assert.match(matrixCss, /grid-template-columns:\s*repeat\(10, 52px\)\s*!important/);
assert.match(matrixCss, /width:\s*52px\s*!important/);
assert.match(matrixCss, /height:\s*30px\s*!important/);
assert.match(matrixCss, /transform:\s*rotate\(-45deg\)\s*!important/);
assert.match(matrixCss, /\.incoming-work-label\s*\{[\s\S]*?display:\s*none\s*!important/);
assert.match(matrixCss, /\.incoming-work-check\.is-not-required[\s\S]*?background:/);
assert.match(matrixCss, /\.incoming-work-check\.is-blocked[\s\S]*?background:/);

// Vowel-stripped labels are intentionally rejected; the real names remain visible once in the header.
for (const disallowed of ['FBRCTN', 'ELCTRCL', 'PIT INSPCTN']) {
  assert.ok(!app.includes(disallowed) && !css.includes(disallowed), `Ambiguous vowel-stripped label found: ${disallowed}`);
}

for (const file of htmlFiles) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(html.includes(version), `${file} has stale cache-busting/version text`);
}

console.log('Uniform Stage Matrix regression checks passed');
