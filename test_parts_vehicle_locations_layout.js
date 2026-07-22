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
assert.match(css, /\.parts-queue-table \{ min-width: 0; width: 100%; table-layout: fixed; \}/);
assert.match(css, /\.parts-queue-table th:nth-child\(6\), \.parts-queue-table td:nth-child\(6\) \{ width: 44px !important; \}/);
assert.match(css, /\.parts-action-group \{[\s\S]*?display: flex;[\s\S]*?justify-content: flex-start;/);
assert.match(css, /\.parts-email-sales-secondary \{[\s\S]*?width: auto;[\s\S]*?border-top: 0;/);
assert.ok(!/\.parts-email-sales-secondary \{[^}]*justify-content: flex-end;[^}]*\}/s.test(css.slice(css.indexOf('Combined staging remediation'))));
assert.match(desktopCss, /\.parts-queue-table \{[\s\S]*?min-width: 0;/);
assert.doesNotMatch(desktopCss, /\.parts-queue-table \{[\s\S]*?min-width: 1480px;/);
assert.match(desktopCss, /\.parts-queue-table \.parts-action-group \{[\s\S]*?display: flex !important;[\s\S]*?flex-wrap: wrap !important;/);
assert.doesNotMatch(desktopCss, /\.parts-queue-table \.parts-action-group \{[^}]*display: grid !important;/s);
assert.match(desktopCss, /\.parts-queue-table \.parts-email-sales-secondary \{[\s\S]*?width: auto !important;/);
assert.match(app, /<th>Parts ETA<\/th><th>Jita<\/th><th>Blocker<\/th><th>Stage \/ update<\/th><th>Actions<\/th>/);
assert.match(app, /parts-action-primary/);
assert.match(app, /parts-email-sales-secondary/);

console.log('Parts/Vehicle Locations layout regression tests passed.');
