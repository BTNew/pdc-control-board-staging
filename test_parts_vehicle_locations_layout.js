'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const css = fs.readFileSync(path.join(__dirname, 'styles.css'), 'utf8');
const desktopCss = fs.readFileSync(path.join(__dirname, 'desktop-operations.css'), 'utf8');
const app = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');

assert.match(css, /Operational readiness — Parts follows the Vehicle Locations continuous page table/);
assert.match(css, /#parts \.parts-home-content \{ flex: 1 1 auto; display: block; overflow: visible !important; \}/);
assert.match(css, /#parts \.parts-table-wrap \{[\s\S]*?height: auto !important;[\s\S]*?min-height: 0;[\s\S]*?max-height: none !important;/);
assert.match(css, /#parts \.parts-queue-table \{ width: 100%; min-width: 1480px; table-layout: fixed; \}/);
assert.match(css, /#parts \.parts-queue-table th:nth-child\(6\), #parts \.parts-queue-table td:nth-child\(6\) \{ width: 9% !important; \}/);
assert.match(css, /\.parts-action-group \{[\s\S]*?display: flex;[\s\S]*?justify-content: flex-start;/);
assert.match(css, /\.parts-email-sales-secondary \{[\s\S]*?width: auto;[\s\S]*?border-top: 0;/);
const operationalCssStart = css.indexOf('Operational readiness — Parts follows the Vehicle Locations continuous page table');
assert.ok(operationalCssStart >= 0, 'Operational-readiness Parts override block must exist');
assert.ok(!/\.parts-email-sales-secondary \{[^}]*justify-content: flex-end;[^}]*\}/s.test(css.slice(operationalCssStart)));
assert.match(css, /@media \(max-width: 1180px\) \{[\s\S]*?\.parts-action-primary \{ flex-wrap: wrap; white-space: normal; \}/);
assert.match(css, /\.parts-worst-eta input \{ width: 100%; min-width: 0; max-width: 100%; \}/);
assert.match(desktopCss, /\.parts-queue-table \{[\s\S]*?min-width: 1480px;/);
assert.match(desktopCss, /\.parts-queue-table \.parts-action-group \{[\s\S]*?display: flex !important;[\s\S]*?flex-wrap: wrap !important;/);
assert.doesNotMatch(desktopCss, /\.parts-queue-table \.parts-action-group \{[^}]*display: grid !important;/s);
assert.match(desktopCss, /\.parts-queue-table \.parts-email-sales-secondary \{[\s\S]*?width: auto !important;/);
assert.match(app, /<th>Parts status<\/th><th>Parts ETA<\/th><th>ETA counter<\/th><th>JITA<\/th><th>Outstanding station work<\/th><th>Parts STOPPAGE reason<\/th><th>Actions<\/th>/);
assert.match(app, /parts-visible-actions/);
assert.match(app, /data-parts-toggle-jita/);

console.log('Parts/Vehicle Locations layout regression tests passed.');
