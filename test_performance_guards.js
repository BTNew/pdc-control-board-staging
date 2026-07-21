'use strict';

const assert = require('assert');
const fs = require('fs');

const source = fs.readFileSync('app.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');

function functionSource(name) {
  const start = source.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `${name} is missing`);
  const brace = source.indexOf('{', start);
  let depth = 0;
  for (let index = brace; index < source.length; index += 1) {
    if (source[index] === '{') depth += 1;
    if (source[index] === '}') depth -= 1;
    if (depth === 0) return source.slice(start, index + 1);
  }
  throw new Error(`Could not extract ${name}`);
}

const activeRender = functionSource('renderActiveView');
assert.ok(!activeRender.includes('renderVehicleTable();'), 'Dashboard must not render the hidden legacy vehicle table');
assert.ok(source.includes("on($('#incoming-search'), 'input', queueIncomingDashboardRender);"), 'Vehicle search must use the debounced renderer');
assert.ok(functionSource('queueIncomingDashboardRender').includes('setTimeout'), 'Vehicle search renderer must be debounced');
assert.ok(source.includes("dashboard: ['incoming-main-board', 'kpi-grid', 'vehicle-table']"), 'Heavy dashboard DOM hosts must be registered for release');
assert.ok(functionSource('showView').includes('releaseHeavyViewDom(app.currentView, nextView);'), 'Navigation must release the previous heavy view DOM');
assert.ok(functionSource('releaseHeavyViewDom').includes('replaceChildren()'), 'Heavy inactive views must be unmounted rather than retained');
assert.ok(!html.includes('<script src="vendor/pdfjs/pdf.min.js'), 'PDF.js should load only when a PDF is processed');
assert.ok(!html.includes('<script src="vendor/qz/qz-tray.js'), 'QZ Tray should load only when printing is requested');
assert.ok(!html.includes('<script src="workshop-planner.js'), 'Workshop Planner should load only when its view is opened');
assert.ok(html.includes('<script src="data.js'), 'Optional lazy loading must preserve the production vehicle dataset');
assert.ok(source.includes("loadExternalScript('vendor/pdfjs/pdf.min.js"), 'PDF processing must retain an on-demand PDF.js path');
assert.ok(source.includes("loadExternalScript('vendor/qz/qz-tray.js"), 'Printing must retain an on-demand QZ Tray path');
assert.ok(source.includes('let activeRenderJsonCache = null;'), 'Local JSON reuse must be explicitly scoped to a synchronous render');
assert.ok(functionSource('loadJson').includes('activeRenderJsonCache?.has(key)'), 'Repeated reads in one render must reuse the parsed value');
assert.ok(functionSource('loadJson').includes('JSON.parse(JSON.stringify(fallback))'), 'Render cache must preserve loadJson fallback clone semantics');
assert.ok(functionSource('saveJson').includes('activeRenderJsonCache?.delete(key)'), 'Every normal local JSON write must invalidate the render cache key first');
assert.ok(activeRender.includes('activeRenderJsonCache = new Map();') && activeRender.includes('finally') && activeRender.includes('activeRenderJsonCache = previousRenderJsonCache;'), 'Render-scoped cache must always be discarded/restored in finally');

console.log('Performance guard checks passed');
